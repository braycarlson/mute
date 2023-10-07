package main

import (
	_ "embed"
	"log"
	"os"
	"path/filepath"
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
	logger   chan string
	shutdown chan bool
}

func NewDeafen() *Deafen {
	return &Deafen{
		hotkey:   []byte{34},
		queue:    buffer.NewCircularBuffer(2),
		deafen:   deafen,
		undeafen: undeafen,
		logger:   make(chan string, 1000),
		shutdown: make(chan bool),
	}
}

func (deafen *Deafen) logging() {
	for {
		select {
		case message, ok := <-deafen.logger:
			if !ok {
				return
			}

			log.Println(message)
		case <-deafen.shutdown:
			close(deafen.logger)
		}
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
			if deafen.render == nil {
				return 1
			}

			if deafen.render.IsMuted() {
				deafen.render.Unmute()
				systray.SetIcon(deafen.undeafen)

				deafen.logger <- "The device was undeafened."
			} else {
				deafen.render.Mute()
				systray.SetIcon(deafen.deafen)

				deafen.logger <- "The device was deafened."
			}

			return 1
		}
	}

	var result w32.LRESULT = w32.CallNextHookEx(
		w32.HHOOK(deafen.hook),
		identifier,
		wparam,
		lparam,
	)

	return result
}

func (deafen *Deafen) onDefaultDeviceChanged(dataflow wca.EDataFlow, role wca.ERole, identifier string) error {
	if deafen.render == nil || dataflow == wca.ECapture {
		return nil
	}

	var id string
	var err error

	id, err = deafen.render.Id()

	if id == identifier {
		return nil
	}

	deafen.logger <- "The default device was changed."

	var enabled bool
	enabled, err = deafen.render.IsEnabled()

	if !enabled {
		return nil
	}

	err = deafen.render.SetAsDefault()

	if err != nil {
		log.Println(err)
	}

	return nil
}

func (deafen *Deafen) onDeviceAdded(identifier string) error {
	deafen.logger <- "A device was added."

	var err error

	if deafen.render == nil {
		var render *device.Device
		render, err = deafen.manager.Find(deafen.name, wca.ERender)

		if err == nil {
			deafen.render = render

			err = deafen.render.SetAsDefault()

			if err != nil {
				log.Println(err)
			}
		}
	}

	return err
}

func (deafen *Deafen) onDeviceRemoved(identifier string) error {
	deafen.logger <- "A device was removed."

	if deafen.render == nil {
		return nil
	}

	var id string
	var err error

	id, err = deafen.render.Id()

	if id == identifier {
		deafen.render.Release()
		deafen.render = nil
	}

	return err
}

func (deafen *Deafen) onDeviceStateChanged(identifier string, state uint64) error {
	if deafen.render == nil || state == 0 {
		return nil
	}

	deafen.logger <- "The state of a device was changed."

	switch state {
	case 1:
		deafen.logger <- "The audio endpoint device is disabled."
	case 2:
		deafen.logger <- "The audio endpoint device is not present."
	case 3:
		deafen.logger <- "The audio endpoint device is unplugged."
	}

	return nil
}

func (deafen *Deafen) onReady() {
	go deafen.logging()

	deafen.logger <- "Starting..."

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
	deafen.logger <- "Exiting..."

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
		deafen.logger <- "No render device found"
		systray.SetIcon(deafen.undeafen)
	} else {
		deafen.render = render
		deafen.render.SetVolume(30)

		var status bool
		status, err = deafen.render.IsAllDefault()

		if !status {
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
	var err error

	var configuration, _ = os.UserConfigDir()
	var home = filepath.Join(configuration, "mute")
	var path = filepath.Join(home, "deafen.log")

	if err = os.MkdirAll(home, os.ModeDir); err != nil {
		log.Fatalln(err)
	}

	var file *os.File

	file, err = os.OpenFile(
		path,
		os.O_CREATE|os.O_WRONLY|os.O_APPEND,
		0666,
	)

	if err != nil {
		log.Println(err)
	}

	log.SetOutput(file)

	defer file.Close()

	var deafen *Deafen = NewDeafen()
	systray.Run(deafen.onReady, deafen.onExit)
}
