package main

import (
	"bytes"
	_ "embed"
	"fmt"
	"syscall"
	"unsafe"

	"github.com/JamesHovious/w32"
	"github.com/braycarlson/muter/device"
	"github.com/braycarlson/muter/settings"
	"github.com/getlantern/systray"
	"github.com/go-ole/go-ole"
	"github.com/moutend/go-wca/pkg/wca"
	"golang.design/x/hotkey/mainthread"
)

const (
	HighPriority = 0x00000080
)

var (
	hook  w32.HHOOK
	queue []byte

	MuteHotkey = []byte{33}

	capture *device.Device
	name    string

	//go:embed asset/mute.ico
	mute []byte

	//go:embed asset/unmute.ico
	unmute []byte
)

func listener(identifier int, wparam w32.WPARAM, lparam w32.LPARAM) w32.LRESULT {
	switch wparam {
	case
		w32.WPARAM(w32.WM_KEYDOWN),
		w32.WPARAM(w32.WM_SYSKEYDOWN):

		message := unsafe.Pointer(lparam)
		kbdstruct := (*w32.KBDLLHOOKSTRUCT)(message)

		var key byte = byte(kbdstruct.VkCode)

		if len(queue) == 1 {
			queue = queue[1:]
		}

		queue = append(queue, key)

		if bytes.Equal(queue, MuteHotkey) {
			if capture.IsMuted() {
				capture.Unmute()
				systray.SetIcon(unmute)
			} else {
				capture.Mute()
				systray.SetIcon(mute)
			}

			return 1
		}
	}

	return w32.CallNextHookEx(
		w32.HHOOK(hook),
		identifier,
		wparam,
		lparam,
	)
}

func setPriority(priority uintptr) error {
	kernel := syscall.NewLazyDLL("kernel32.dll")
	setPriorityClass := kernel.NewProc("SetPriorityClass")

	if err := setPriorityClass.Find(); err != nil {
		return err
	}

	handle, err := syscall.GetCurrentProcess()

	if err != nil {
		return err
	}

	defer syscall.CloseHandle(handle)

	result, _, err := setPriorityClass.Call(uintptr(handle), priority)

	if result != 0 {
		return nil
	}

	return nil
}

func onDefaultDeviceChanged(dataflow wca.EDataFlow, role wca.ERole, identifier string) error {
	var identical bool = capture.IsDevice(identifier)

	if identical {
		return nil
	}

	switch dataflow {
	case wca.ECapture:
		capture.SetAsDefault()
	default:
		capture.SetAsDefault()
	}

	return nil
}

func onDeviceAdded(identifier string) error {
	if capture == nil {
		capture = device.Find(name, wca.ECapture)
	}

	return nil
}

func onDeviceRemoved(identifier string) error {
	if capture.IsDevice(identifier) {
		capture.MMDevice.Release()
		capture.PropertyStore.Release()
		capture.Volume.Release()

		capture = nil
	}

	return nil
}

func onDeviceStateChanged(identifier string, state uint64) error {
	if state == wca.DEVICE_STATE_ACTIVE {
		return nil
	}

	if capture.IsDevice(identifier) {
		capture.MMDevice.Release()
		capture.PropertyStore.Release()
		capture.Volume.Release()

		capture = nil
	}

	return nil
}

func onReady() {
	systray.SetTitle("Mute")
	systray.SetTooltip("Mute")
	quit := systray.AddMenuItem("Quit", "Quit")

	go func() {
		<-quit.ClickedCh
		systray.Quit()
	}()

	mainthread.Init(run)
}

func onExit() {
	w32.UnhookWindowsHookEx(hook)
}

func run() {
	var settings *settings.Settings = settings.NewSettings()
	name = settings.Capture

	if err := ole.CoInitializeEx(0, ole.COINIT_APARTMENTTHREADED); err != nil {
		fmt.Println(err)
	}

	defer ole.CoUninitialize()

	capture = device.Find(settings.Capture, wca.ECapture)

	if capture == nil {
		fmt.Println("No capture device found")
	}

	if capture.IsMuted() {
		systray.SetIcon(mute)
	} else {
		systray.SetIcon(unmute)
	}

	queue = make([]byte, 0, 1)

	hook = w32.SetWindowsHookEx(
		w32.WH_KEYBOARD_LL,
		w32.HOOKPROC(listener),
		0,
		0,
	)

	var message w32.MSG

	for w32.GetMessage(&message, 0, 0, 0) != 0 {
		w32.TranslateMessage(&message)
		w32.DispatchMessage(&message)
	}

	var mmde *wca.IMMDeviceEnumerator

	if err := wca.CoCreateInstance(wca.CLSID_MMDeviceEnumerator, 0, wca.CLSCTX_ALL, wca.IID_IMMDeviceEnumerator, &mmde); err != nil {
		fmt.Println(err)
	}

	defer mmde.Release()

	callback := wca.IMMNotificationClientCallback{
		OnDefaultDeviceChanged: onDefaultDeviceChanged,
		OnDeviceAdded:          onDeviceAdded,
		OnDeviceRemoved:        onDeviceRemoved,
		OnDeviceStateChanged:   onDeviceStateChanged,
	}

	mmnc := wca.NewIMMNotificationClient(callback)

	if err := mmde.RegisterEndpointNotificationCallback(mmnc); err != nil {
		fmt.Println(err)
	}
}

func main() {
	err := setPriority(HighPriority)

	if err != nil {
		fmt.Println(err)
	}

	systray.Run(onReady, onExit)
}
