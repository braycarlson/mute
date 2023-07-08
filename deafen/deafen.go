package main

import (
	"bytes"
	_ "embed"
	"fmt"
	"syscall"
	"unsafe"

	"github.com/JamesHovious/w32"
	"github.com/braycarlson/mute/device"
	"github.com/braycarlson/mute/settings"
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

	DeafenHotkey []byte = []byte{34}

	render *device.Device
	name   string

	//go:embed asset/deafen.ico
	deafen []byte

	//go:embed asset/undeafen.ico
	undeafen []byte
)

func listener(identifier int, wparam w32.WPARAM, lparam w32.LPARAM) w32.LRESULT {
	switch wparam {
	case
		w32.WPARAM(w32.WM_KEYDOWN),
		w32.WPARAM(w32.WM_SYSKEYDOWN):

		var message unsafe.Pointer = unsafe.Pointer(lparam)
		var kbdstruct *w32.KBDLLHOOKSTRUCT = (*w32.KBDLLHOOKSTRUCT)(message)

		var key byte = byte(kbdstruct.VkCode)

		if len(queue) == 1 {
			queue = queue[1:]
		}

		queue = append(queue, key)

		if bytes.Equal(queue, DeafenHotkey) {
			if render.IsMuted() {
				render.Unmute()
				systray.SetIcon(undeafen)
			} else {
				render.Mute()
				systray.SetIcon(deafen)
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
	var kernel *syscall.LazyDLL = syscall.NewLazyDLL("kernel32.dll")
	var setPriorityClass *syscall.LazyProc = kernel.NewProc("SetPriorityClass")
	var err error

	if err = setPriorityClass.Find(); err != nil {
		return err
	}

	var handle syscall.Handle
	handle, err = syscall.GetCurrentProcess()

	if err != nil {
		return err
	}

	defer syscall.CloseHandle(handle)

	var result uintptr
	result, _, err = setPriorityClass.Call(uintptr(handle), priority)

	if result != 0 {
		return nil
	}

	return nil
}

func onDefaultDeviceChanged(dataflow wca.EDataFlow, role wca.ERole, identifier string) error {
	var err error

	if err = ole.CoInitializeEx(0, ole.COINIT_APARTMENTTHREADED); err != nil {
		fmt.Println(err)
	}

	defer ole.CoUninitialize()

	var identical bool = render.IsDevice(identifier)

	if identical {
		return nil
	}

	switch dataflow {
	case wca.ERender:
		err = render.SetAsDefault()
		fmt.Println(err)
	default:
		err = render.SetAsDefault()
		fmt.Println(err)
	}

	return nil
}

func onDeviceAdded(identifier string) error {
	if render == nil {
		render = device.Find(name, wca.ERender)
	}

	return nil
}

func onDeviceRemoved(identifier string) error {
	if render.IsDevice(identifier) {
		render.Release()
		render = nil
	}

	return nil
}

func onDeviceStateChanged(identifier string, state uint64) error {
	if state == wca.DEVICE_STATE_ACTIVE {
		return nil
	}

	if render.IsDevice(identifier) {
		render.Release()
		render = nil
	}

	return nil
}

func onReady() {
	systray.SetTitle("Deafen")
	systray.SetTooltip("Deafen")
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
	var err error

	if err = ole.CoInitializeEx(0, ole.COINIT_APARTMENTTHREADED); err != nil {
		fmt.Println(err)
	}

	defer ole.CoUninitialize()

	var fallback *device.Device
	fallback, _ = device.GetDefault(wca.ERender, wca.EConsole)

	var settings *settings.Settings = settings.NewSettings()
	render = device.Find(settings.Render, wca.ERender)
	render.SetVolume(30)

	defer render.Release()

	if render == nil {
		fmt.Println("No render device found")
	}

	if fallback.Name() != render.Name() {
		render.SetAsDefault()
		fallback.Release()
	}

	if render.IsMuted() {
		systray.SetIcon(deafen)
	} else {
		systray.SetIcon(undeafen)
	}

	var mmde *wca.IMMDeviceEnumerator

	if err = wca.CoCreateInstance(
		wca.CLSID_MMDeviceEnumerator,
		0,
		wca.CLSCTX_ALL,
		wca.IID_IMMDeviceEnumerator,
		&mmde,
	); err != nil {
		fmt.Println(err)
	}

	defer mmde.Release()

	var callback wca.IMMNotificationClientCallback = wca.IMMNotificationClientCallback{
		OnDefaultDeviceChanged: onDefaultDeviceChanged,
		OnDeviceAdded:          onDeviceAdded,
		OnDeviceRemoved:        onDeviceRemoved,
		OnDeviceStateChanged:   onDeviceStateChanged,
	}

	var mmnc *wca.IMMNotificationClient = wca.NewIMMNotificationClient(callback)

	if err = mmde.RegisterEndpointNotificationCallback(mmnc); err != nil {
		fmt.Println(err)
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
}

func main() {
	var err error
	err = setPriority(HighPriority)

	if err != nil {
		fmt.Println(err)
	}

	systray.Run(onReady, onExit)
}
