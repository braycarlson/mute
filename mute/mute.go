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
	//go:embed asset/mute.ico
	mute []byte

	//go:embed asset/unmute.ico
	unmute []byte
)

type Mute struct {
	hook    w32.HHOOK
	queue   []byte
	hotkey  []byte
	capture *device.Device
	name    string
	mutex   sync.Mutex
	mute    []byte
	unmute  []byte
}

func NewMute() *Mute {
	return &Mute{
		hotkey: []byte{33},
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

		if len(mute.queue) == 1 {
			mute.queue = mute.queue[1:]
		}

		mute.queue = append(mute.queue, key)

		if bytes.Equal(mute.queue, mute.hotkey) {
			mute.mutex.Lock()

			if mute.capture != nil && mute.capture.IsMuted() {
				mute.capture.Unmute()
				systray.SetIcon(mute.unmute)

				log.Println("The device was muted.")
			} else {
				mute.capture.Mute()
				systray.SetIcon(mute.mute)

				log.Println("The device was unmuted.")
			}

			mute.mutex.Unlock()
			return 1
		}
	}

	return w32.CallNextHookEx(
		w32.HHOOK(mute.hook),
		identifier,
		wparam,
		lparam,
	)
}

func (mute *Mute) onDefaultDeviceChanged(dataflow wca.EDataFlow, role wca.ERole, identifier string) error {
	log.Println("The default device was changed.")

	var err error

	if err = ole.CoInitializeEx(0, ole.COINIT_APARTMENTTHREADED); err != nil {
		log.Fatalln(err)
	}

	defer ole.CoUninitialize()

	mute.mutex.Lock()
	defer mute.mutex.Unlock()

	var identical bool = false

	if mute.capture != nil {
		identical = mute.capture.IsDevice(identifier)
	}

	if identical {
		return nil
	}

	switch dataflow {
	case wca.ECapture:
		err = mute.capture.SetAsDefault()
		log.Fatalln(err)
	default:
		err = mute.capture.SetAsDefault()
		log.Fatalln(err)
	}

	return nil
}

func (mute *Mute) onDeviceAdded(identifier string) error {
	log.Println("A device was added.")

	mute.mutex.Lock()
	defer mute.mutex.Unlock()

	if mute.capture == nil {
		mute.capture = device.Find(mute.name, wca.ECapture)
	}

	return nil
}

func (mute *Mute) onDeviceRemoved(identifier string) error {
	log.Println("A device was removed.")

	mute.mutex.Lock()
	defer mute.mutex.Unlock()

	if mute.capture != nil && mute.capture.IsDevice(identifier) {
		mute.capture.Release()
		mute.capture = nil
	}

	return nil
}

func (mute *Mute) onDeviceStateChanged(identifier string, state uint64) error {
	log.Println("The state of a device was changed.")

	if state == wca.DEVICE_STATE_ACTIVE {
		return nil
	}

	mute.mutex.Lock()
	defer mute.mutex.Unlock()

	if mute.capture != nil && mute.capture.IsDevice(identifier) {
		mute.capture.Release()
		mute.capture = nil
	}

	return nil
}

func (mute *Mute) onReady() {
	log.Println("Starting...")

	systray.SetTitle("Mute")
	systray.SetTooltip("Mute")
	quit := systray.AddMenuItem("Quit", "Quit")

	go func() {
		<-quit.ClickedCh
		systray.Quit()
	}()

	mute.run()
}

func (mute *Mute) onExit() {
	log.Println("Exiting...")

	w32.UnhookWindowsHookEx(mute.hook)
}

func (mute *Mute) run() {
	var err error

	if err = ole.CoInitializeEx(0, ole.COINIT_APARTMENTTHREADED); err != nil {
		log.Fatalln(err)
	}

	defer ole.CoUninitialize()

	var fallback *device.Device
	fallback, _ = device.GetDefault(wca.ECapture, wca.EConsole)

	var settings *settings.Settings = settings.NewSettings()
	mute.capture = device.Find(settings.Capture, wca.ECapture)
	mute.capture.SetVolume(70)

	defer mute.capture.Release()

	if mute.capture == nil {
		log.Fatalln("No capture device found")
	}

	if fallback.Name() != mute.capture.Name() {
		mute.capture.SetAsDefault()
		fallback.Release()
	}

	if mute.capture.IsMuted() {
		systray.SetIcon(mute.mute)
	} else {
		systray.SetIcon(mute.unmute)
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
		OnDefaultDeviceChanged: mute.onDefaultDeviceChanged,
		OnDeviceAdded:          mute.onDeviceAdded,
		OnDeviceRemoved:        mute.onDeviceRemoved,
		OnDeviceStateChanged:   mute.onDeviceStateChanged,
	}

	var mmnc *wca.IMMNotificationClient = wca.NewIMMNotificationClient(callback)

	if err = mmde.RegisterEndpointNotificationCallback(mmnc); err != nil {
		log.Fatalln(err)
	}

	mute.queue = make([]byte, 0, 1)

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
	var err error

	var configuration, _ = os.UserConfigDir()
	var home = filepath.Join(configuration, "mute")
	var path = filepath.Join(home, "mute.log")

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

	var mute *Mute = NewMute()
	systray.Run(mute.onReady, mute.onExit)
}
