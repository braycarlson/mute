## mute

mute is a script to mute/unmute a recording device and deafen/undeafen a playback device on Windows using [AutoHotkey](https://www.autohotkey.com/).

## Getting Started
1. Download and install [AutoHotkey](https://www.autohotkey.com/).
2. Download and extract [mute](https://github.com/braycarlson/mute/releases).

## Setup
1. Please ensure the device(s) you want to mute or deafen are connected to the computer.
2. Open the `mute` directory and double-click on `soundcard.ahk`. Find the name of the device(s) in the `Device` column, and remember the number in the corresponding `ID` column.
3. Open `devices.ini` from the `mute` directory, and change the value of `playback_id` or `recording_id` to the ID of the device(s) from `soundcard.ahk`.
5. Save `devices.ini`.
6. Double-click on `mute.ahk` and `deafen.ahk` to run each script or right-click on each file and select `Run Script`.

- `deafen.ahk` uses the **`*`** key on the **numberpad** to deafen/undeafen the playback device.
- `mute.ahk` uses the **`-`** key on the **numberpad** to mute/unmute the recording device.

## Run `mute` on Startup

You can use Task Scheduler or copy and paste a shortcut of each script to Windows' startup directory. However, it is recommended to use Task Scheduler as it is more robust. **Please note that the example below is for `mute.ahk`, and you will have to repeat this for `deafen.ahk`**.

### 1) Task Scheduler
1. Press `Win` + `R`
2. Type: `taskschd.msc`
3. Click `OK` or press `Enter`
4. Click `Create Task...`

#### General
- Name: `mute`
- Select `Run only when user is logged on`
- Check `Run with highest privileges`

#### Triggers
- Click `New...`
- Begin the task: `At log on`
- Select `Any user`
- Check `Delay task for:` and select `30 seconds`
- Check `Enabled`
- Click `OK`

#### Actions
- Click `New...`
- Action: `Start a program`
- Program/script: Copy and paste the path to the `mute.ahk` file
    - **Example:** C:\\Users\\Brayden\\Documents\\mute\\mute.ahk
- Start in (optional): Copy and paste the path to the `mute` directory
    - **Example:** C:\\Users\\Brayden\\Documents\\mute
- Click `OK`

### 2) Windows Startup
1. Open the `mute` directory
2. Right-click on `mute.ahk` and select `Copy`
3. Press `Win` + `R`
4. Type: `shell:startup`
5. Click `OK`
6. Right-click in the file explorer and select `Paste shortcut`.

## Note
- The ID of a device may change if you connect/disconnect a device or install/uninstall an audio driver, so you may have to open `soundcard.ahk` to get the new ID for each device, and then change the values in `devices.ini` and reload `mute.ahk` and `deafen.ahk`.

- If you wish to modify the hotkey in `mute.ahk` or `deafen.ahk`:
    - Right-click on `mute.ahk`, select `Edit Script`  and change `NumpadSub` to a key from [AutoHotkey - List of Keys](https://www.autohotkey.com/docs/KeyList.htm).
    - Right-click on `deafen.ahk`, select `Edit Script` and change `NumpadMult` to a key from [AutoHotkey - List of Keys](https://www.autohotkey.com/docs/KeyList.htm).

- If you wish to modify the sounds in `mute.ahk`:
    - You must have the correct audio codec installed.
    - You must put the audio file in the `sounds` directory.
    - You must rename the audio file to `mute.xxx` or `unmute.xxx`.

## Acknowledgement
Thanks to Lexikos for [Vista Audio Control Functions](https://autohotkey.com/board/topic/21984-vista-audio-control-functions/) and `soundcard.ahk` *(which I have modified for this repository)*.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
