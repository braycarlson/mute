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
#cgo CFLAGS: -I${SRCDIR}/../dll
#cgo LDFLAGS: -L${SRCDIR}/../dll -lhook
#include "../dll/hook.h"
*/
import "C"

var (
	//go:embed asset/deafen.ico
	deafenIcon []byte

	//go:embed asset/undeafen.ico
	undeafenIcon []byte
	app          *Deafen
)

type Deafen struct {
	queue    *buffer.CircularBuffer
	hotkey   []byte
	manager  *manager.AudioManager
	render   *device.Device
	name     string
	deafen   []byte
	undeafen []byte
}

func NewDeafen() *Deafen {
	return &Deafen{
		hotkey:   []byte{34},
		queue:    buffer.NewCircularBuffer(2),
		deafen:   deafenIcon,
		undeafen: undeafenIcon,
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
				if app.render != nil {
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

func (app *Deafen) toggleMute() {
	if app.render.IsMuted() {
		app.render.Unmute()
		systray.SetIcon(app.undeafen)
	} else {
		app.render.Mute()
		systray.SetIcon(app.deafen)
	}
}

func (app *Deafen) onDefaultDeviceChanged(dataflow wca.EDataFlow, role wca.ERole, identifier string) error {
	if app.render == nil || dataflow == wca.ECapture {
		return nil
	}

	var id string
	var err error

	id, err = app.render.Id()

	if err != nil || id == identifier {
		return err
	}

	var enabled bool
	enabled, err = app.render.IsEnabled()

	if err == nil && enabled {
		err = app.render.SetAsDefault()

		if err != nil {
			log.Println(err)
		}
	}

	return err
}

func (app *Deafen) onDeviceAdded(identifier string) error {
	if app.render == nil {
		var err error

		var render *device.Device
		render, err = app.manager.Find(app.name, wca.ERender)

		if err == nil {
			app.render = render

			err = app.render.SetAsDefault()

			if err != nil {
				log.Println(err)
			}
		}

		return err
	}

	return nil
}

func (app *Deafen) onDeviceRemoved(identifier string) error {
	if app.render == nil {
		return nil
	}

	var id string
	var err error

	id, err = app.render.Id()

	if err == nil && id == identifier {
		app.render.Release()
		app.render = nil
	}

	return err
}

func (app *Deafen) onDeviceStateChanged(identifier string, state uint64) error {
	if app.render == nil || state == 0 {
		return nil
	}

	return nil
}

func (app *Deafen) onReady() {
	systray.SetTitle("Deafen")
	systray.SetTooltip("Deafen")

	var quit *systray.MenuItem
	quit = systray.AddMenuItem("Quit", "Quit")

	go func() {
		<-quit.ClickedCh
		systray.Quit()
	}()

	app.run()
}

func (app *Deafen) onExit() {
	if app.render != nil {
		app.render.Release()
	}

	C.removeHook()
}

func (app *Deafen) run() {
	var err error

	err = ole.CoInitializeEx(0, ole.COINIT_APARTMENTTHREADED)

	if err != nil {
		log.Fatalln(err)
	}

	defer ole.CoUninitialize()

	var render *device.Device
	var settings *settings.Settings = settings.NewSettings()

	render, err = app.manager.Find(settings.Render, wca.ERender)

	if render == nil || err != nil {
		systray.SetIcon(app.undeafen)
	} else {
		app.render = render
		app.render.SetVolume(20)

		var status bool
		status, err = app.render.IsAllDefault()

		if !status && err == nil {
			app.render.SetAsDefault()
		}

		if app.render.IsMuted() {
			systray.SetIcon(app.deafen)
		} else {
			systray.SetIcon(app.undeafen)
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
	app = NewDeafen()
	systray.Run(app.onReady, app.onExit)
}
