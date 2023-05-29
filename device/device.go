package device

import (
	"syscall"
	"unsafe"

	"github.com/braycarlson/muter/policy"
	"github.com/go-ole/go-ole"
	"github.com/lithammer/fuzzysearch/fuzzy"
	"github.com/moutend/go-wca/pkg/wca"
)

type Device struct {
	MMDevice      *wca.IMMDevice
	PropertyStore *wca.IPropertyStore
	Volume        *wca.IAudioEndpointVolume
}

func (device *Device) Endpoint(endpoint *string) (err error) {
	var ptr uint64

	hr, _, _ := syscall.Syscall(
		device.MMDevice.VTable().GetId,
		2,
		uintptr(unsafe.Pointer(device.MMDevice)),
		uintptr(unsafe.Pointer(&ptr)),
		0,
	)

	if hr != 0 {
		err = ole.NewError(hr)
		return
	}

	// An endpoint ID string is a null-terminated, wide-character string.
	// https://msdn.microsoft.com/en-us/library/windows/desktop/dd370837(v=vs.85).aspx
	var us []uint16
	var i uint32
	var start = unsafe.Pointer(uintptr(ptr))

	for {
		u := *(*uint16)(unsafe.Pointer(uintptr(start) + 2*uintptr(i)))

		if u == 0 {
			break
		}

		us = append(us, u)
		i++
	}

	*endpoint = syscall.UTF16ToString(us)
	ole.CoTaskMemFree(uintptr(ptr))

	return
}

func (device *Device) Id() string {
	if device.MMDevice == nil {
		return ""
	}

	var ps *wca.IPropertyStore
	device.MMDevice.OpenPropertyStore(wca.STGM_READ, &ps)

	var pv wca.PROPVARIANT
	ps.GetValue(&wca.PKEY_AudioEndpoint_GUID, &pv)

	return pv.String()
}

func (device *Device) Name() string {
	if device.MMDevice == nil {
		return ""
	}

	var ps *wca.IPropertyStore
	device.MMDevice.OpenPropertyStore(wca.STGM_READ, &ps)

	var pv wca.PROPVARIANT
	ps.GetValue(&wca.PKEY_Device_FriendlyName, &pv)

	return pv.String()
}

func (device *Device) IsDevice(identifier string) bool {
	var endpoint string
	device.Endpoint(&endpoint)

	return identifier == endpoint
}

func (device *Device) IsMuted() bool {
	if device.MMDevice == nil || device.Volume == nil {
		return false
	}

	var mute bool
	device.Volume.GetMute(&mute)

	return mute
}

func (device *Device) Mute() bool {
	if device.MMDevice == nil || device.Volume == nil {
		return false
	}

	if device.IsMuted() {
		return false
	}

	device.Volume.SetMute(true, nil)

	return true
}

func (device *Device) Unmute() bool {
	if device.MMDevice == nil || device.Volume == nil {
		return false
	}

	if !device.IsMuted() {
		return false
	}

	device.Volume.SetMute(false, nil)

	return true
}

func (device *Device) ToggleMute() bool {
	if device.MMDevice == nil || device.Volume == nil {
		return false
	}

	currentState := device.IsMuted()
	newState := !currentState
	device.Volume.SetMute(newState, nil)

	return newState
}

func (device *Device) SetAsDefault() error {
	var pcv *policy.IPolicyConfigVista

	if err := wca.CoCreateInstance(policy.CLSID_PolicyConfigVista, 0, wca.CLSCTX_ALL, policy.IID_IPolicyConfigVista, &pcv); err != nil {
		return err
	}

	var endpoint string
	device.Endpoint(&endpoint)

	err := pcv.SetDefaultEndpoint(
		endpoint,
		wca.EConsole,
	)

	err = pcv.SetDefaultEndpoint(
		endpoint,
		wca.ECommunications,
	)

	err = pcv.SetDefaultEndpoint(
		endpoint,
		wca.EMultimedia,
	)

	return err
}

func Find(name string, dataflow uint32) *Device {
	var mmde *wca.IMMDeviceEnumerator

	wca.CoCreateInstance(
		wca.CLSID_MMDeviceEnumerator,
		0,
		wca.CLSCTX_ALL,
		wca.IID_IMMDeviceEnumerator,
		&mmde,
	)

	defer mmde.Release()

	var mmdc *wca.IMMDeviceCollection

	mmde.EnumAudioEndpoints(
		dataflow,
		wca.DEVICE_STATE_ACTIVE,
		&mmdc,
	)

	defer mmdc.Release()

	var count uint32
	mmdc.GetCount(&count)

	var target *Device

	var i uint32

	for i = 0; i < count; i++ {
		var mmd *wca.IMMDevice
		mmdc.Item(i, &mmd)

		var aev *wca.IAudioEndpointVolume

		mmd.Activate(
			wca.IID_IAudioEndpointVolume,
			wca.CLSCTX_ALL,
			nil,
			&aev,
		)

		var ps *wca.IPropertyStore
		mmd.OpenPropertyStore(wca.STGM_READ, &ps)

		var pv wca.PROPVARIANT
		ps.GetValue(&wca.PKEY_Device_FriendlyName, &pv)

		var identifier string = pv.String()
		var score int = 20

		var distance int = fuzzy.LevenshteinDistance(identifier, name)

		if distance > score {
			defer mmd.Release()
			defer ps.Release()
			defer aev.Release()
		} else {
			score = distance

			target = &Device{
				MMDevice:      mmd,
				PropertyStore: ps,
				Volume:        aev,
			}
		}
	}

	return target
}
