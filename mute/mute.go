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

var (
	//go:embed asset/mute.ico
	mute []byte

	//go:embed asset/unmute.ico
	unmute []byte
)

type Mute struct {
	hook    w32.HHOOK
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
		mute:   mute,
		unmute: unmute,
	}
}

func (mute *Mute) listener(identifier int, wparam w32.WPARAM, lparam w32.LPARAM) w32.LRESULT {
	switch wparam {
	case
		w32.WPARAM(w32.WM_KEYDOWN),
		w32.WPARAM(w32.WM_SYSKEYDOWN):

		var message unsafe.Pointer = unsafe.Pointer(lparam)
		var kbdstruct *w32.KBDLLHOOKSTRUCT = (*w32.KBDLLHOOKSTRUCT)(message)

		var key byte = byte(kbdstruct.VkCode)
		mute.queue.Push(key)

		if mute.queue.IsMatch(mute.hotkey) {
			if mute.capture != nil {
				go mute.toggleMute()
			}

			return 1
		}
	}

	return w32.CallNextHookEx(
		0,
		identifier,
		wparam,
		lparam,
	)
}

func (mute *Mute) toggleMute() {
	if mute.capture.IsMuted() {
		mute.capture.Unmute()
		systray.SetIcon(mute.unmute)
	} else {
		mute.capture.Mute()
		systray.SetIcon(mute.mute)
	}
}

func (mute *Mute) onDefaultDeviceChanged(dataflow wca.EDataFlow, role wca.ERole, identifier string) error {
	if mute.capture == nil || dataflow == wca.ERender {
		return nil
	}

	var id string
	var err error

	id, err = mute.capture.Id()

	if err != nil || id == identifier {
		return nil
	}

	var enabled bool
	enabled, err = mute.capture.IsEnabled()

	if err == nil && enabled {
		err = mute.capture.SetAsDefault()

		if err != nil {
			log.Println(err)
		}
	}

	return err
}

func (mute *Mute) onDeviceAdded(identifier string) error {
	if mute.capture == nil {
		var err error

		var capture *device.Device
		capture, err = mute.manager.Find(mute.name, wca.ECapture)

		if err == nil {
			mute.capture = capture

			err = mute.capture.SetAsDefault()

			if err != nil {
				log.Println(err)
			}
		}

		return err
	}

	return nil
}

func (mute *Mute) onDeviceRemoved(identifier string) error {
	if mute.capture == nil {
		return nil
	}

	var id string
	var err error

	id, err = mute.capture.Id()

	if id == identifier {
		mute.capture.Release()
		mute.capture = nil
	}

	return err
}

func (mute *Mute) onDeviceStateChanged(identifier string, state uint64) error {
	if mute.capture == nil || state == 0 {
		return nil
	}

	return nil
}

func (mute *Mute) onReady() {
	systray.SetTitle("Mute")
	systray.SetTooltip("Mute")

	var quit *systray.MenuItem
	quit = systray.AddMenuItem("Quit", "Quit")

	go func() {
		<-quit.ClickedCh
		systray.Quit()
	}()

	mute.run()
}

func (mute *Mute) onExit() {
	if mute.capture != nil {
		mute.capture.Release()
	}

	w32.UnhookWindowsHookEx(mute.hook)
}

func (mute *Mute) run() {
	var err error

	err = ole.CoInitializeEx(0, ole.COINIT_APARTMENTTHREADED)

	if err != nil {
		log.Fatalln(err)
	}

	defer ole.CoUninitialize()

	var capture *device.Device
	var settings *settings.Settings = settings.NewSettings()

	capture, err = mute.manager.Find(settings.Capture, wca.ECapture)

	if capture == nil || err != nil {
		systray.SetIcon(mute.unmute)
	} else {
		mute.capture = capture
		mute.capture.SetVolume(70)

		var status bool
		status, err = mute.capture.IsAllDefault()

		if !status && err == nil {
			mute.capture.SetAsDefault()
		}

		if mute.capture.IsMuted() {
			systray.SetIcon(mute.mute)
		} else {
			systray.SetIcon(mute.unmute)
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
		OnDefaultDeviceChanged: mute.onDefaultDeviceChanged,
		OnDeviceAdded:          mute.onDeviceAdded,
		OnDeviceRemoved:        mute.onDeviceRemoved,
		OnDeviceStateChanged:   mute.onDeviceStateChanged,
	}

	var mmnc *wca.IMMNotificationClient = wca.NewIMMNotificationClient(callback)

	err = mmde.RegisterEndpointNotificationCallback(mmnc)

	if err != nil {
		log.Fatalln(err)
	}

	defer mmde.UnregisterEndpointNotificationCallback(mmnc)
	defer mmde.Release()

	mute.hook = w32.SetWindowsHookEx(
		w32.WH_KEYBOARD_LL,
		w32.HOOKPROC(mute.listener),
		0,
		0,
	)

	var message w32.MSG

	for w32.GetMessage(&message, 0, 0, 0) != 0 {
		w32.TranslateMessage(&message)
		w32.DispatchMessage(&message)
	}
}

func main() {
	var mute *Mute = NewMute()
	systray.Run(mute.onReady, mute.onExit)
}
