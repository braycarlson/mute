; Directives
#NoEnv ; Prevents empty variables from being looked up as potential environment variables.
#KeyHistory 0 ; Do not display the script info and a history of the most recent keystrokes and mouse clicks.
#SingleInstance Force ; Skips the dialog box and replaces the old instance automatically.

; Optimizations
ListLines, Off ; Do not display the script lines most recently executed.


global CLSID_MMDeviceEnumerator := "{BCDE0395-E52F-467C-8E3D-C4579291692E}"
global IID_IMMDeviceEnumerator := "{A95664D2-9614-4F35-A746-DE8DB63617E6}"

Gui +hwndGuiHwnd
Gui Add, ListView, vDevices gDevices r10 w300, ID | Device
populate_device()
Gui Show, Center, Soundcard
return

Devices:
    Gui ListView, Devices

    if (A_GuiEvent = "I" && InStr(ErrorLevel, "F", true)) {
        LV_GetText(device_number, A_EventInfo, 1)
    }

return

GuiEscape:
GuiClose:
ExitApp

populate_device() {
    Gui ListView, Devices
    LV_Delete()
    enum := ComObjCreate(CLSID_MMDeviceEnumerator, IID_IMMDeviceEnumerator)

    if VA_IMMDeviceEnumerator_EnumAudioEndpoints(enum, 2, 9, devices) >= 0 {
        VA_IMMDeviceEnumerator_GetDefaultAudioEndpoint(enum, 0, 0, device)
        VA_IMMDevice_GetId(device, default_id)
        ObjRelease(device)

        VA_IMMDeviceCollection_GetCount(devices, count)

        Loop % count {
            if (VA_IMMDeviceCollection_Item(devices, A_Index - 1, device) < 0) {
                continue
            }

            VA_IMMDevice_GetId(device, id)
            name := VA_GetDeviceName(device)

            LV_Add("", A_Index, name)
            ObjRelease(device)
        }
        ObjRelease(devices)
    }
    ObjRelease(enum)

    Loop 2 {
        LV_ModifyCol(A_Index, "AutoHdr")
    }
}
