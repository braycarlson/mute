pub const Icon = struct {
    pub const dimension: u32 = 32;
};

pub const Menu = struct {
    pub const exit: u32 = 1001;
};

pub const Message = struct {
    pub const config_reload: u32 = 1;
    pub const device_changed: u32 = 2;
    pub const device_default_changed: u32 = 3;
    pub const toggle: u32 = 4;
    pub const widget_input: u32 = 5;
};

pub const Timer = struct {
    pub const rehook_id: u32 = 1;
    pub const rehook_interval_ms: u32 = 10 * 60 * 1000;
};
