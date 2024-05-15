package manager

import (
	"github.com/braycarlson/mute/device"
	"github.com/lithammer/fuzzysearch/fuzzy"
	"github.com/moutend/go-wca/pkg/wca"
)

type AudioManager struct{}

func (manager *AudioManager) Find(name string, dataflow uint32) (*device.Device, error) {
	var mmde *wca.IMMDeviceEnumerator
	var err error = nil

	err = wca.CoCreateInstance(
		wca.CLSID_MMDeviceEnumerator,
		0,
		wca.CLSCTX_ALL,
		wca.IID_IMMDeviceEnumerator,
		&mmde,
	)

	if err != nil {
		return nil, err
	}

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

	var target *device.Device
	var score int = 20

	var index uint32

	for index = 0; index < count; index++ {
		var mmd *wca.IMMDevice

		err = mmdc.Item(index, &mmd)

		if err != nil {
			return nil, err
		}

		var aev *wca.IAudioEndpointVolume

		err = mmd.Activate(
			wca.IID_IAudioEndpointVolume,
			wca.CLSCTX_ALL,
			nil,
			&aev,
		)

		if err != nil {
			mmd.Release()
			return nil, err
		}

		var ps *wca.IPropertyStore
		err = mmd.OpenPropertyStore(wca.STGM_READ, &ps)

		if err != nil {
			aev.Release()
			mmd.Release()
			return nil, err
		}

		var pv wca.PROPVARIANT
		err = ps.GetValue(&wca.PKEY_Device_FriendlyName, &pv)

		if err != nil {
			ps.Release()
			aev.Release()
			mmd.Release()
			return nil, err
		}

		var identifier string = pv.String()
		var distance int = fuzzy.LevenshteinDistance(identifier, name)

		if distance < score {
			score = distance

			if target != nil {
				target.Release()
			}

			target = &device.Device{
				MMDevice:      mmd,
				PropertyStore: ps,
				Volume:        aev,
			}
		} else {
			ps.Release()
			aev.Release()
			mmd.Release()
		}
	}

	if target == nil {
		return nil, err
	}

	return target, nil
}

func (manager *AudioManager) GetDefault(dataflow uint32, role uint32) (*device.Device, error) {
	var mmde *wca.IMMDeviceEnumerator
	var err error

	err = wca.CoCreateInstance(
		wca.CLSID_MMDeviceEnumerator,
		0,
		wca.CLSCTX_ALL,
		wca.IID_IMMDeviceEnumerator,
		&mmde,
	)

	if err != nil {
		return nil, err
	}

	defer mmde.Release()

	var mmd *wca.IMMDevice

	err = mmde.GetDefaultAudioEndpoint(dataflow, role, &mmd)

	if err != nil {
		return nil, err
	}

	var aev *wca.IAudioEndpointVolume

	err = mmd.Activate(
		wca.IID_IAudioEndpointVolume,
		wca.CLSCTX_ALL,
		nil,
		&aev,
	)

	if err != nil {
		mmd.Release()
		return nil, err
	}

	var ps *wca.IPropertyStore

	err = mmd.OpenPropertyStore(wca.STGM_READ, &ps)

	if err != nil {
		aev.Release()
		mmd.Release()
		return nil, err
	}

	return &device.Device{
		MMDevice:      mmd,
		PropertyStore: ps,
		Volume:        aev,
	}, nil
}
