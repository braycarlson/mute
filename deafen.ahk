; Directives
#NoEnv ; Prevents empty variables from being looked up as potential environment variables.
#KeyHistory 0 ; Do not display the script info and a history of the most recent keystrokes and mouse clicks.
#SingleInstance Force ; Skips the dialog box and replaces the old instance automatically.

; Optimizations
SetBatchLines, -1 ; Do not sleep and run at maximum speed.
ListLines, Off ; Do not display the script lines most recently executed.
Process, Priority,, High ; Changes the priority level of the first matching process.
SetWorkingDir %A_ScriptDir% ; The script's working directory is the default directory that is used to access files and folders.


; Undeafen the playback device on exit
undeafen_on_exit(ExitReason) {
    ; If the script is being reloaded then don't undeafen the device
    if ExitReason in Reload
        return

    SoundSet, 0, master, mute, %playback_device%
    playback_state = 0
}

; Set the tray icon
Menu, Tray, Icon, icons\undeafen.ico,,,

; The ID of the playback device
IniRead, playback_device, devices.ini, Playback, playback_id

; The state of the playback device
playback_state = 0

; Undeafen the playback device on startup
SoundSet, 0, master, mute, %playback_device%

; Register undeafen_on_exit() to be called on exit
OnExit("undeafen_on_exit")

; The [*] key on the numberpad
*NumpadMult::
    if (playback_state = 0) {
        SoundSet, 1, master, mute, %playback_device%
        playback_state = 1

        Menu, Tray, Icon, icons\deafen.ico,,,
    } else {
        SoundSet, 0, master, mute, %playback_device%
        playback_state = 0

        Menu, Tray, Icon, icons\undeafen.ico,,,
    }

return
