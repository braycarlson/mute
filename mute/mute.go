package main

import (
	_ "embed"
	"log"
	"unsafe"

	"github.com/JamesHovious/w32"
	"github.com/braycarlson/mute/buffer"
	"github.com/braycarlson/mute/device"
	"github.com/braycarlson/mute/manager"
	"github.com/braycarlson/mute/settings"
	"github.com/getlantern/systray"
	"github.com/go-ole/go-ole"
	"github.com/moutend/go-wca/pkg/wca"
)

/*
#cgo LDFLAGS: -Ldll -lhook
#include "dll/hook.h"
*/
import "C"

var (
	//go:embed asset/mute.ico
	muteIcon []byte

	//go:embed asset/unmute.ico
	unmuteIcon []byte
	app        *Mute
)

type Mute struct {
	queue   *buffer.CircularBuffer
	hotkey  []byte
	capture *device.Device
	manager *manager.AudioManager
	name    string
	mute    []byte
	unmute  []byte
}

func NewMute() *Mute {
	return &Mute{
		hotkey: []byte{33},
		queue:  buffer.NewCircularBuffer(2),
		mute:   muteIcon,
		unmute: unmuteIcon,
	}
}

//export GoKeyboardProc
func GoKeyboardProc(nCode C.int, wParam C.WPARAM, lParam C.LPARAM) C.LRESULT {
	if nCode >= 0 {
		if wParam == C.WPARAM(w32.WM_KEYDOWN) || wParam == C.WPARAM(w32.WM_SYSKEYDOWN) {
			var message unsafe.Pointer = unsafe.Pointer(uintptr(lParam))
			var kbdstruct *w32.KBDLLHOOKSTRUCT = (*w32.KBDLLHOOKSTRUCT)(message)

			var key byte = byte(kbdstruct.VkCode)
			app.queue.Push(key)

			if app.queue.IsMatch(app.hotkey) {
				if app.capture != nil {
					go app.toggleMute()
				}
				return 1
			}
		}
	}
	return C.callNextHookEx(nCode, wParam, lParam)
}

//export GoMouseProc
func GoMouseProc(nCode C.int, wParam C.WPARAM, lParam C.LPARAM) C.LRESULT {
	return C.callNextHookEx(nCode, wParam, lParam)
}

func (app *Mute) toggleMute() {
	if app.capture.IsMuted() {
		app.capture.Unmute()
		systray.SetIcon(app.unmute)
	} else {
		app.capture.Mute()
		systray.SetIcon(app.mute)
	}
}

func (app *Mute) onDefaultDeviceChanged(dataflow wca.EDataFlow, role wca.ERole, identifier string) error {
	if app.capture == nil || dataflow == wca.ERender {
		return nil
	}

	var id string
	var err error

	id, err = app.capture.Id()

	if err != nil || id == identifier {
		return nil
	}

	var enabled bool
	enabled, err = app.capture.IsEnabled()

	if err == nil && enabled {
		err = app.capture.SetAsDefault()

		if err != nil {
			log.Println(err)
		}
	}

	return err
}

func (app *Mute) onDeviceAdded(identifier string) error {
	if app.capture == nil {
		var err error

		var capture *device.Device
		capture, err = app.manager.Find(app.name, wca.ECapture)

		if err == nil {
			app.capture = capture

			err = app.capture.SetAsDefault()

			if err != nil {
				log.Println(err)
			}
		}

		return err
	}

	return nil
}

func (app *Mute) onDeviceRemoved(identifier string) error {
	if app.capture == nil {
		return nil
	}

	var id string
	var err error

	id, err = app.capture.Id()

	if id == identifier {
		app.capture.Release()
		app.capture = nil
	}

	return err
}

func (app *Mute) onDeviceStateChanged(identifier string, state uint64) error {
	if app.capture == nil || state == 0 {
		return nil
	}

	return nil
}

func (app *Mute) onReady() {
	systray.SetTitle("Mute")
	systray.SetTooltip("Mute")

	var quit *systray.MenuItem
	quit = systray.AddMenuItem("Quit", "Quit")

	go func() {
		<-quit.ClickedCh
		systray.Quit()
	}()

	app.run()
}

func (app *Mute) onExit() {
	if app.capture != nil {
		app.capture.Release()
	}

	C.removeHook()
}

func (app *Mute) run() {
	var err error

	err = ole.CoInitializeEx(0, ole.COINIT_APARTMENTTHREADED)

	if err != nil {
		log.Fatalln(err)
	}

	defer ole.CoUninitialize()

	var capture *device.Device
	var settings *settings.Settings = settings.NewSettings()

	capture, err = app.manager.Find(settings.Capture, wca.ECapture)

	if capture == nil || err != nil {
		systray.SetIcon(app.unmute)
	} else {
		app.capture = capture
		app.capture.SetVolume(70)

		var status bool
		status, err = app.capture.IsAllDefault()

		if !status && err == nil {
			app.capture.SetAsDefault()
		}

		if app.capture.IsMuted() {
			systray.SetIcon(app.mute)
		} else {
			systray.SetIcon(app.unmute)
		}
	}

	var mmde *wca.IMMDeviceEnumerator

	err = wca.CoCreateInstance(
		wca.CLSID_MMDeviceEnumerator,
		0,
		wca.CLSCTX_ALL,
		wca.IID_IMMDeviceEnumerator,
		&mmde,
	)

	if err != nil {
		log.Fatalln(err)
	}

	var callback wca.IMMNotificationClientCallback = wca.IMMNotificationClientCallback{
		OnDefaultDeviceChanged: app.onDefaultDeviceChanged,
		OnDeviceAdded:          app.onDeviceAdded,
		OnDeviceRemoved:        app.onDeviceRemoved,
		OnDeviceStateChanged:   app.onDeviceStateChanged,
	}

	var mmnc *wca.IMMNotificationClient = wca.NewIMMNotificationClient(callback)

	err = mmde.RegisterEndpointNotificationCallback(mmnc)

	if err != nil {
		log.Fatalln(err)
	}

	defer mmde.UnregisterEndpointNotificationCallback(mmnc)
	defer mmde.Release()

	C.setGoKeyboardProc(C.HOOKPROC(C.GoKeyboardProc))
	C.setGoMouseProc(C.HOOKPROC(C.GoMouseProc))
	C.setKeyboardHook(C.getModuleHandle())

	var message w32.MSG

	for {
		var status int
		status = w32.GetMessage(&message, 0, 0, 0)

		if status == 0 || status == -1 {
			break
		}

		w32.TranslateMessage(&message)
		w32.DispatchMessage(&message)
	}
}

func main() {
	app = NewMute()
	systray.Run(app.onReady, app.onExit)
}
