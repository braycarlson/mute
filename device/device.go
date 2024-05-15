package device

import (
	"errors"
	"syscall"
	"unsafe"

	"github.com/braycarlson/mute/policy"
	"github.com/go-ole/go-ole"
	"github.com/moutend/go-wca/pkg/wca"
)

type Device struct {
	MMDevice      *wca.IMMDevice
	PropertyStore *wca.IPropertyStore
	Volume        *wca.IAudioEndpointVolume
}

func (device *Device) Endpoint(endpoint *string) (err error) {
	if device.MMDevice == nil {
		return errors.New("MMDevice is nil")
	}

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
		ole.CoTaskMemFree(uintptr(ptr))
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

	return nil
}

func (device *Device) Id() (string, error) {
	if device.MMDevice == nil {
		return "", errors.New("MMDevice is nil")
	}

	var identifier string
	var err error

	err = device.MMDevice.GetId(&identifier)
	return identifier, err
}

func (device *Device) IsAllDefault() (bool, error) {
	if device.MMDevice == nil {
		return false, errors.New("MMDevice is nil")
	}

	var enumerator *wca.IMMDeviceEnumerator
	var err error

	enumerator, err = createDeviceEnumerator()

	if err != nil {
		return false, err
	}

	defer enumerator.Release()

	var deviceID string
	deviceID, err = device.Id()

	if err != nil {
		return false, err
	}

	roles := []wca.ERole{
		wca.EConsole,
		wca.ECommunications,
		wca.EMultimedia,
	}

	for _, role := range roles {
		var pDefaultDevice *wca.IMMDevice
		pDefaultDevice, err = getDefaultAudioEndpoint(enumerator, role)

		if err != nil {
			return false, err
		}

		defer pDefaultDevice.Release()

		var defaultID string
		err = pDefaultDevice.GetId(&defaultID)

		if err != nil {
			return false, err
		}

		if deviceID != defaultID {
			return false, nil
		}
	}

	return true, nil
}

func (device *Device) IsDefault(role wca.ERole) (bool, error) {
	if device.MMDevice == nil {
		return false, errors.New("MMDevice is nil")
	}

	var enumerator *wca.IMMDeviceEnumerator
	var err error

	enumerator, err = createDeviceEnumerator()

	if err != nil {
		return false, err
	}

	defer enumerator.Release()

	var pDefaultDevice *wca.IMMDevice
	pDefaultDevice, err = getDefaultAudioEndpoint(enumerator, role)

	if err != nil {
		return false, err
	}

	defer pDefaultDevice.Release()

	var deviceID string
	deviceID, err = device.Id()

	if err != nil {
		return false, err
	}

	var defaultID string
	err = pDefaultDevice.GetId(&defaultID)

	if err != nil {
		return false, err
	}

	return deviceID == defaultID, nil
}

func (device *Device) IsEnabled() (bool, error) {
	if device.MMDevice == nil {
		return false, errors.New("MMDevice is nil")
	}

	var state uint32
	var err error

	err = device.MMDevice.GetState(&state)

	if err != nil {
		return false, err
	}

	return state == wca.DEVICE_STATE_ACTIVE, nil
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

	defer ps.Release()

	var pv wca.PROPVARIANT
	ps.GetValue(&wca.PKEY_Device_FriendlyName, &pv)

	return pv.String()
}

func (device *Device) ToggleMute() bool {
	if device.MMDevice == nil || device.Volume == nil {
		return false
	}

	var current bool = device.IsMuted()
	var state bool = !current

	device.Volume.SetMute(state, nil)

	return state
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
	coInitialize()
	defer coUninitialize()

	var pcv *policy.IPolicyConfigVista
	var err error

	pcv, err = createPolicyConfigVista()

	if err != nil {
		return err
	}

	var endpoint string
	device.Endpoint(&endpoint)

	if err != nil {
		return err
	}

	for _, role := range []wca.ERole{wca.EConsole, wca.ECommunications, wca.EMultimedia} {
		err = pcv.SetDefaultEndpoint(endpoint, role)

		if err != nil {
			return err
		}
	}

	return nil
}

func (device *Device) SetVolume(level int8) error {
	if device.MMDevice == nil || device.Volume == nil {
		return errors.New("No device or volume")
	}

	var volume float32 = float32(level) / 100
	var err error

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

func createDeviceEnumerator() (*wca.IMMDeviceEnumerator, error) {
	var enumerator *wca.IMMDeviceEnumerator
	var err error

	err = wca.CoCreateInstance(
		wca.CLSID_MMDeviceEnumerator,
		0,
		wca.CLSCTX_ALL,
		wca.IID_IMMDeviceEnumerator,
		&enumerator,
	)

	return enumerator, err
}

func getDefaultAudioEndpoint(enumerator *wca.IMMDeviceEnumerator, role wca.ERole) (*wca.IMMDevice, error) {
	var pDefaultDevice *wca.IMMDevice
	var err error

	err = enumerator.GetDefaultAudioEndpoint(
		wca.ERender,
		uint32(role),
		&pDefaultDevice,
	)

	return pDefaultDevice, err
}

func createPolicyConfigVista() (*policy.IPolicyConfigVista, error) {
	var pcv *policy.IPolicyConfigVista
	var err error

	err = wca.CoCreateInstance(
		policy.CLSID_PolicyConfigVista,
		0,
		wca.CLSCTX_ALL,
		policy.IID_IPolicyConfigVista,
		&pcv,
	)

	return pcv, err
}

func coInitialize() {
	ole.CoInitializeEx(0, ole.COINIT_APARTMENTTHREADED)
}

func coUninitialize() {
	ole.CoUninitialize()
}
