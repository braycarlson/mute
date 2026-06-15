const win32 = @import("win32").everything;

pub const Menu = struct {
    pub const exit: u32 = 1001;
};

pub const Resource = struct {
    pub const mute_icon: u32 = 101;
    pub const unmute_icon: u32 = 102;
};

pub const Timer = struct {
    pub const rehook_id: u32 = 1;
    pub const rehook_interval_ms: u32 = 10 * 60 * 1000;
};

pub const wm_config_reload: u32 = win32.WM_APP + 2;
pub const wm_device_event: u32 = win32.WM_APP + 3;
