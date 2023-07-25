package main

import (
	"bytes"
	_ "embed"
	"log"
	"os"
	"path/filepath"
	"sync"
	"unsafe"

	"github.com/JamesHovious/w32"
	"github.com/braycarlson/mute/device"
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
	queue    []byte
	hotkey   []byte
	render   *device.Device
	name     string
	mutex    sync.Mutex
	deafen   *[]byte
	undeafen *[]byte
}

func NewDeafen() *Deafen {
	return &Deafen{
		hotkey:   []byte{34},
		deafen:   &deafen,
		undeafen: &undeafen,
	}
}

func (deafen *Deafen) listener(identifier int, wparam w32.WPARAM, lparam w32.LPARAM) w32.LRESULT {
	switch wparam {
	case w32.WPARAM(w32.WM_KEYDOWN), w32.WPARAM(w32.WM_SYSKEYDOWN):
		var message unsafe.Pointer = unsafe.Pointer(lparam)
		var kbdstruct *w32.KBDLLHOOKSTRUCT = (*w32.KBDLLHOOKSTRUCT)(message)

		var key byte = byte(kbdstruct.VkCode)

		if len(deafen.queue) == 1 {
			deafen.queue = deafen.queue[1:]
		}

		deafen.queue = append(deafen.queue, key)

		if bytes.Equal(deafen.queue, deafen.hotkey) {
			deafen.mutex.Lock()

			if deafen.render.IsMuted() {
				deafen.render.Unmute()
				systray.SetIcon(*deafen.undeafen)

				log.Println("The device was undeafened.")
			} else {
				deafen.render.Mute()
				systray.SetIcon(*deafen.deafen)

				log.Println("The device was deafened.")
			}

			deafen.mutex.Unlock()
			return 1
		}
	}

	return w32.CallNextHookEx(
		w32.HHOOK(deafen.hook),
		identifier,
		wparam,
		lparam,
	)
}

func (deafen *Deafen) onDefaultDeviceChanged(dataflow wca.EDataFlow, role wca.ERole, identifier string) error {
	log.Println("The default device was changed.")

	var err error

	if err = ole.CoInitializeEx(0, ole.COINIT_APARTMENTTHREADED); err != nil {
		log.Fatalln(err)
	}

	defer ole.CoUninitialize()

	deafen.mutex.Lock()
	defer deafen.mutex.Unlock()

	var identical bool = false

	if deafen.render != nil {
		identical = deafen.render.IsDevice(identifier)
	}

	if identical {
		return nil
	}

	switch dataflow {
	case wca.ERender:
		err = deafen.render.SetAsDefault()
		log.Fatalln(err)
	default:
		err = deafen.render.SetAsDefault()
		log.Fatalln(err)
	}

	return nil
}

func (deafen *Deafen) onDeviceAdded(identifier string) error {
	log.Println("A device was added.")

	deafen.mutex.Lock()
	defer deafen.mutex.Unlock()

	if deafen.render == nil {
		deafen.render = device.Find(deafen.name, wca.ERender)
	}

	return nil
}

func (deafen *Deafen) onDeviceRemoved(identifier string) error {
	log.Println("A device was removed.")

	deafen.mutex.Lock()
	defer deafen.mutex.Unlock()

	if deafen.render.IsDevice(identifier) {
		deafen.render.Release()
		deafen.render = nil
	}

	return nil
}

func (deafen *Deafen) onDeviceStateChanged(identifier string, state uint64) error {
	log.Println("The state of a device was changed.")

	if state == wca.DEVICE_STATE_ACTIVE {
		return nil
	}

	deafen.mutex.Lock()
	defer deafen.mutex.Unlock()

	if deafen.render.IsDevice(identifier) {
		deafen.render.Release()
		deafen.render = nil
	}

	return nil
}

func (deafen *Deafen) onReady() {
	log.Println("Starting...")

	systray.SetTitle("Deafen")
	systray.SetTooltip("Deafen")
	quit := systray.AddMenuItem("Quit", "Quit")

	go func() {
		<-quit.ClickedCh
		systray.Quit()
	}()

	deafen.run()
}

func (deafen *Deafen) onExit() {
	log.Println("Exiting...")

	w32.UnhookWindowsHookEx(deafen.hook)
}

func (deafen *Deafen) run() {
	var err error

	if err = ole.CoInitializeEx(0, ole.COINIT_APARTMENTTHREADED); err != nil {
		log.Fatalln(err)
	}

	defer ole.CoUninitialize()

	var fallback *device.Device
	fallback, _ = device.GetDefault(wca.ERender, wca.EConsole)

	var settings *settings.Settings = settings.NewSettings()
	deafen.render = device.Find(settings.Render, wca.ERender)
	deafen.render.SetVolume(30)

	defer deafen.render.Release()

	if deafen.render == nil {
		log.Fatalln("No render device found")
	}

	if fallback.Name() != deafen.render.Name() {
		deafen.render.SetAsDefault()
		fallback.Release()
	}

	if deafen.render.IsMuted() {
		systray.SetIcon(*deafen.deafen)
	} else {
		systray.SetIcon(*deafen.undeafen)
	}

	var mmde *wca.IMMDeviceEnumerator

	if err = wca.CoCreateInstance(
		wca.CLSID_MMDeviceEnumerator,
		0,
		wca.CLSCTX_ALL,
		wca.IID_IMMDeviceEnumerator,
		&mmde,
	); err != nil {
		log.Fatalln(err)
	}

	defer mmde.Release()

	var callback wca.IMMNotificationClientCallback = wca.IMMNotificationClientCallback{
		OnDefaultDeviceChanged: deafen.onDefaultDeviceChanged,
		OnDeviceAdded:          deafen.onDeviceAdded,
		OnDeviceRemoved:        deafen.onDeviceRemoved,
		OnDeviceStateChanged:   deafen.onDeviceStateChanged,
	}

	var mmnc *wca.IMMNotificationClient = wca.NewIMMNotificationClient(callback)

	if err = mmde.RegisterEndpointNotificationCallback(mmnc); err != nil {
		log.Fatalln(err)
	}

	deafen.queue = make([]byte, 0, 1)

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

	file, err := os.OpenFile(
		path,
		os.O_CREATE|os.O_WRONLY|os.O_APPEND,
		0666,
	)

	if err != nil {
		log.Println(err)
	}

	log.SetOutput(file)

	var deafen *Deafen = NewDeafen()
	systray.Run(deafen.onReady, deafen.onExit)
}
