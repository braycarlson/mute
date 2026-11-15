# mute

A tool to mute and deafen recording and playback device(s) on Windows and Linux. The project builds two tray applications, `mute` for capture and `deafen` for playback, each with a global hotkey that removes the need for per-application hotkeys. A click on the tray icon opens an on-screen panel for choosing a device and setting its volume. A preferred device is held as the default, so when a peripheral such as a PS5 controller takes over, the tool reverts the change at once. The settings live in a TOML file that reloads on change.
