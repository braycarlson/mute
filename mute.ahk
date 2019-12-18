; Directives
#NoEnv ; Prevents empty variables from being looked up as potential environment variables.
#KeyHistory 0 ; Do not display the script info and a history of the most recent keystrokes and mouse clicks.
#SingleInstance Force ; Skips the dialog box and replaces the old instance automatically.

; Optimizations
SetBatchLines, -1 ; Do not sleep and run at maximum speed.
ListLines, Off ; Do not display the script lines most recently executed.
Process, Priority,, High ; Changes the priority level of the first matching process.
SetWorkingDir %A_ScriptDir% ; The script's working directory is the default directory that is used to access files and folders.


; Unmute the recording device on exit
unmute_on_exit(ExitReason) {
    ; If the script is being reloaded then don't unmute the device
    if ExitReason in Reload
        return

    SoundSet, 0, master, mute, %recording_device%
    recording_state = 0
}

; Play a sound asynchronously from memory
play_sound(ByRef Sound) {
    return DllCall("winmm.dll\PlaySound" (A_IsUnicode ? "W" : "A"), UInt, &Sound, UInt, 0, UInt, 0x4 | 0x1)
}

; Set the tray icon
Menu, Tray, Icon, icons\unmute.ico,,,

; Load each .wav file into memory
FileRead, mute, *c sounds\mute.wav
FileRead, unmute, *c sounds\unmute.wav

; The ID of the recording device
IniRead, recording_device, devices.ini, Recording, recording_id

; The state of the recording device
recording_state = 0

; Unmute the recording device on startup
SoundSet, 0, master, mute, %recording_device%

; Register unmute_on_exit() to be called on exit
OnExit("unmute_on_exit")

; The [-] key on the numberpad
*NumpadSub::
    if (recording_state = 0) {
        SoundSet, 1, master, mute, %recording_device%
        Menu, Tray, Icon, icons\mute.ico,,,
        play_sound(mute)
        recording_state = 1

    } else {
        SoundSet, 0, master, mute, %recording_device%
        Menu, Tray, Icon, icons\unmute.ico,,,
        play_sound(unmute)
        recording_state = 0
    }

return
