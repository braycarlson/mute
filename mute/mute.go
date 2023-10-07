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
	//go:embed asset/mute.ico
	mute []byte

	//go:embed asset/unmute.ico
	unmute []byte
)

type Mute struct {
	hook     w32.HHOOK
	queue    *buffer.CircularBuffer
	hotkey   []byte
	capture  *device.Device
	manager  *manager.AudioManager
	name     string
	mute     []byte
	unmute   []byte
	logger   chan string
	shutdown chan bool
}

func NewMute() *Mute {
	return &Mute{
		hotkey:   []byte{33},
		queue:    buffer.NewCircularBuffer(2),
		mute:     mute,
		unmute:   unmute,
		logger:   make(chan string, 1000),
		shutdown: make(chan bool),
	}
}

func (mute *Mute) logging() {
	for {
		select {
		case message, ok := <-mute.logger:
			if !ok {
				return
			}

			log.Println(message)
		case <-mute.shutdown:
			close(mute.logger)
		}
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
			if mute.capture == nil {
				return 1
			}

			if mute.capture.IsMuted() {
				mute.capture.Unmute()
				systray.SetIcon(mute.unmute)

				mute.logger <- "The device was unmuted."
			} else {
				mute.capture.Mute()
				systray.SetIcon(mute.mute)

				mute.logger <- "The device was muted."
			}

			return 1
		}
	}

	var result w32.LRESULT = w32.CallNextHookEx(
		w32.HHOOK(mute.hook),
		identifier,
		wparam,
		lparam,
	)

	return result
}

func (mute *Mute) onDefaultDeviceChanged(dataflow wca.EDataFlow, role wca.ERole, identifier string) error {
	if mute.capture == nil || dataflow == wca.ERender {
		return nil
	}

	var id string
	var err error

	id, err = mute.capture.Id()

	if id == identifier {
		return nil
	}

	mute.logger <- "The default device was changed."

	var enabled bool
	enabled, err = mute.capture.IsEnabled()

	if !enabled {
		return nil
	}

	err = mute.capture.SetAsDefault()

	if err != nil {
		log.Println(err)
	}

	return nil
}

func (mute *Mute) onDeviceAdded(identifier string) error {
	mute.logger <- "A device was added."

	var err error

	if mute.capture == nil {
		var capture *device.Device
		capture, err = mute.manager.Find(mute.name, wca.ECapture)

		if err == nil {
			mute.capture = capture

			err = mute.capture.SetAsDefault()

			if err != nil {
				log.Println(err)
			}
		}
	}

	return err
}

func (mute *Mute) onDeviceRemoved(identifier string) error {
	mute.logger <- "A device was removed."

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

	mute.logger <- "The state of a device was changed."

	switch state {
	case 1:
		mute.logger <- "The audio endpoint device is disabled."
	case 2:
		mute.logger <- "The audio endpoint device is not present."
	case 3:
		mute.logger <- "The audio endpoint device is unplugged."
	}

	return nil
}

func (mute *Mute) onReady() {
	go mute.logging()

	mute.logger <- "Starting..."

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
	mute.logger <- "Exiting..."

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
		mute.logger <- "No capture device found"
		systray.SetIcon(mute.unmute)
	} else {
		mute.capture = capture
		mute.capture.SetVolume(70)

		var status bool
		status, err = mute.capture.IsAllDefault()

		if !status {
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
	var err error

	var configuration, _ = os.UserConfigDir()
	var home = filepath.Join(configuration, "mute")
	var path = filepath.Join(home, "mute.log")

	err = os.MkdirAll(home, os.ModeDir)

	if err != nil {
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

	var mute *Mute = NewMute()
	systray.Run(mute.onReady, mute.onExit)
}
