pub const MuteError = error{
    ComInitFailed,
    DeviceNotFound,
    ModuleNotFound,
    NoIcon,
    NoWindow,
    TrayCreationFailed,
    WindowCreationFailed,
};
