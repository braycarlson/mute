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
	//go:embed asset/deafen.ico
	deafen []byte

	//go:embed asset/undeafen.ico
	undeafen []byte
)

type Deafen struct {
	hook     w32.HHOOK
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
		deafen:   deafen,
		undeafen: undeafen,
	}
}

func (deafen *Deafen) listener(identifier int, wparam w32.WPARAM, lparam w32.LPARAM) w32.LRESULT {
	switch wparam {
	case
		w32.WPARAM(w32.WM_KEYDOWN),
		w32.WPARAM(w32.WM_SYSKEYDOWN):

		var message unsafe.Pointer = unsafe.Pointer(lparam)
		var kbdstruct *w32.KBDLLHOOKSTRUCT = (*w32.KBDLLHOOKSTRUCT)(message)

		var key byte = byte(kbdstruct.VkCode)
		deafen.queue.Push(key)

		if deafen.queue.IsMatch(deafen.hotkey) {
			if deafen.render != nil {
				go deafen.toggleMute()
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

func (deafen *Deafen) toggleMute() {
	if deafen.render.IsMuted() {
		deafen.render.Unmute()
		systray.SetIcon(deafen.undeafen)
	} else {
		deafen.render.Mute()
		systray.SetIcon(deafen.deafen)
	}
}

func (deafen *Deafen) onDefaultDeviceChanged(dataflow wca.EDataFlow, role wca.ERole, identifier string) error {
	if deafen.render == nil || dataflow == wca.ECapture {
		return nil
	}

	var id string
	var err error

	id, err = deafen.render.Id()

	if err != nil || id == identifier {
		return err
	}

	var enabled bool
	enabled, err = deafen.render.IsEnabled()

	if err == nil && enabled {
		err = deafen.render.SetAsDefault()

		if err != nil {
			log.Println(err)
		}
	}

	return err
}

func (deafen *Deafen) onDeviceAdded(identifier string) error {
	if deafen.render == nil {
		var err error

		var render *device.Device
		render, err = deafen.manager.Find(deafen.name, wca.ERender)

		if err == nil {
			deafen.render = render

			err = deafen.render.SetAsDefault()

			if err != nil {
				log.Println(err)
			}
		}

		return err
	}

	return nil
}

func (deafen *Deafen) onDeviceRemoved(identifier string) error {
	if deafen.render == nil {
		return nil
	}

	var id string
	var err error

	id, err = deafen.render.Id()

	if err == nil && id == identifier {
		deafen.render.Release()
		deafen.render = nil
	}

	return err
}

func (deafen *Deafen) onDeviceStateChanged(identifier string, state uint64) error {
	if deafen.render == nil || state == 0 {
		return nil
	}

	return nil
}

func (deafen *Deafen) onReady() {
	systray.SetTitle("Deafen")
	systray.SetTooltip("Deafen")

	var quit *systray.MenuItem
	quit = systray.AddMenuItem("Quit", "Quit")

	go func() {
		<-quit.ClickedCh
		systray.Quit()
	}()

	deafen.run()
}

func (deafen *Deafen) onExit() {
	if deafen.render != nil {
		deafen.render.Release()
	}

	w32.UnhookWindowsHookEx(deafen.hook)
}

func (deafen *Deafen) run() {
	var err error

	err = ole.CoInitializeEx(0, ole.COINIT_APARTMENTTHREADED)

	if err != nil {
		log.Fatalln(err)
	}

	defer ole.CoUninitialize()

	var render *device.Device
	var settings *settings.Settings = settings.NewSettings()

	render, err = deafen.manager.Find(settings.Render, wca.ERender)

	if render == nil || err != nil {
		systray.SetIcon(deafen.undeafen)
	} else {
		deafen.render = render
		deafen.render.SetVolume(30)

		var status bool
		status, err = deafen.render.IsAllDefault()

		if !status && err == nil {
			deafen.render.SetAsDefault()
		}

		if deafen.render.IsMuted() {
			systray.SetIcon(deafen.deafen)
		} else {
			systray.SetIcon(deafen.undeafen)
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
		OnDefaultDeviceChanged: deafen.onDefaultDeviceChanged,
		OnDeviceAdded:          deafen.onDeviceAdded,
		OnDeviceRemoved:        deafen.onDeviceRemoved,
		OnDeviceStateChanged:   deafen.onDeviceStateChanged,
	}

	var mmnc *wca.IMMNotificationClient = wca.NewIMMNotificationClient(callback)

	err = mmde.RegisterEndpointNotificationCallback(mmnc)

	if err != nil {
		log.Fatalln(err)
	}

	defer mmde.UnregisterEndpointNotificationCallback(mmnc)
	defer mmde.Release()

	deafen.hook = w32.SetWindowsHookEx(
		w32.WH_KEYBOARD_LL,
		w32.HOOKPROC(deafen.listener),
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
	var deafen *Deafen = NewDeafen()
	systray.Run(deafen.onReady, deafen.onExit)
}
