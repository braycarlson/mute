package policy

import (
	"syscall"
	"unsafe"

	"github.com/go-ole/go-ole"
	"github.com/moutend/go-wca/pkg/wca"
)

var (
	IID_IPolicyConfigVista  = ole.NewGUID("{568b9108-44bf-40b4-9006-86afe5b5a620}")
	CLSID_PolicyConfigVista = ole.NewGUID("{294935CE-F637-4E7C-A41B-AB255460B862}")
)

type IPolicyConfigVista struct {
	ole.IUnknown
}

type IPolicyConfigVistaVtbl struct {
	ole.IUnknownVtbl
	GetMixFormat          uintptr
	GetDeviceFormat       uintptr
	SetDeviceFormat       uintptr
	GetProcessingPeriod   uintptr
	SetProcessingPeriod   uintptr
	GetShareMode          uintptr
	SetShareMode          uintptr
	GetPropertyValue      uintptr
	SetPropertyValue      uintptr
	SetDefaultEndpoint    uintptr
	SetEndpointVisibility uintptr
}

func (pcv *IPolicyConfigVista) VTable() *IPolicyConfigVistaVtbl {
	return (*IPolicyConfigVistaVtbl)(unsafe.Pointer(pcv.RawVTable))
}

func (pcv *IPolicyConfigVista) SetDefaultEndpoint(identifier string, role wca.ERole) (err error) {
	err = pcvSetDefaultEndpoint(pcv, identifier, role)
	return
}

func pcvSetDefaultEndpoint(pcv *IPolicyConfigVista, identifier string, role wca.ERole) (err error) {
	var ptr *uint16

	if ptr, err = syscall.UTF16PtrFromString(identifier); err != nil {
		return
	}

	hr, _, _ := syscall.Syscall(
		pcv.VTable().SetDefaultEndpoint,
		3,
		uintptr(unsafe.Pointer(pcv)),
		uintptr(unsafe.Pointer(ptr)),
		uintptr(uint32(role)),
	)

	if hr != 0 {
		err = ole.NewError(hr)
	}

	return
}
