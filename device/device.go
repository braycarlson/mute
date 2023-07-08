package device

import (
	"errors"
	"syscall"
	"unsafe"

	"github.com/braycarlson/mute/policy"
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

	var hresult uintptr

	hresult, _, _ = syscall.Syscall(
		device.MMDevice.VTable().GetId,
		2,
		uintptr(unsafe.Pointer(device.MMDevice)),
		uintptr(unsafe.Pointer(&ptr)),
		0,
	)

	if hresult != 0 {
		err = ole.NewError(hresult)
		return
	}

	// An endpoint ID string is a null-terminated, wide-character string.
	// https://msdn.microsoft.com/en-us/library/windows/desktop/dd370837(v=vs.85).aspx
	var unicode []uint16
	var index uint32
	var start = unsafe.Pointer(uintptr(ptr))

	for {
		current := *(*uint16)(unsafe.Pointer(uintptr(start) + 2*uintptr(index)))

		if current == 0 {
			break
		}

		unicode = append(unicode, current)
		index++
	}

	*endpoint = syscall.UTF16ToString(unicode)
	ole.CoTaskMemFree(uintptr(ptr))

	return
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

	var index uint32

	for index = 0; index < count; index++ {
		var mmd *wca.IMMDevice
		mmdc.Item(index, &mmd)

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

func GetDefault(dataflow uint32, role uint32) (*Device, error) {
	var mmde *wca.IMMDeviceEnumerator
	var mmd *wca.IMMDevice
	var aev *wca.IAudioEndpointVolume
	var ps *wca.IPropertyStore
	var err error

	if err = wca.CoCreateInstance(
		wca.CLSID_MMDeviceEnumerator,
		0,
		wca.CLSCTX_ALL,
		wca.IID_IMMDeviceEnumerator,
		&mmde,
	); err != nil {
		return nil, err
	}
	defer mmde.Release()

	if err = mmde.GetDefaultAudioEndpoint(dataflow, role, &mmd); err != nil {
		return nil, err
	}

	mmd.Activate(
		wca.IID_IAudioEndpointVolume,
		wca.CLSCTX_ALL,
		nil,
		&aev,
	)

	mmd.OpenPropertyStore(wca.STGM_READ, &ps)

	return &Device{
		MMDevice:      mmd,
		PropertyStore: ps,
		Volume:        aev,
	}, nil
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

func (device *Device) ToggleMute() bool {
	if device.MMDevice == nil || device.Volume == nil {
		return false
	}

	currentState := device.IsMuted()
	newState := !currentState
	device.Volume.SetMute(newState, nil)

	return newState
}

func (device *Device) Release() {
	if device.Volume != nil {
		device.Volume.Release()
		device.Volume = nil
	}

	if device.PropertyStore != nil {
		device.PropertyStore.Release()
		device.PropertyStore = nil
	}

	if device.MMDevice != nil {
		device.MMDevice.Release()
		device.MMDevice = nil
	}
}

func (device *Device) SetAsDefault() error {
	var pcv *policy.IPolicyConfigVista
	var err error

	if err = wca.CoCreateInstance(
		policy.CLSID_PolicyConfigVista,
		0,
		wca.CLSCTX_ALL,
		policy.IID_IPolicyConfigVista,
		&pcv,
	); err != nil {
		return err
	}

	var endpoint string
	device.Endpoint(&endpoint)

	if err = pcv.SetDefaultEndpoint(endpoint, wca.EConsole); err != nil {
		return err
	}

	if err = pcv.SetDefaultEndpoint(endpoint, wca.ECommunications); err != nil {
		return err
	}

	if err = pcv.SetDefaultEndpoint(endpoint, wca.EMultimedia); err != nil {
		return err
	}

	return nil
}

func (device *Device) SetVolume(level int8) error {
	var err error

	if device.MMDevice == nil || device.Volume == nil {
		return errors.New("No device or volume")
	}

	var volume float32 = float32(level) / 100
	err = device.Volume.SetMasterVolumeLevelScalar(volume, nil)

	if err != nil {
		return err
	}

	return nil
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
