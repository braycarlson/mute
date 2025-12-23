pub const Menu = struct {
    pub const exit: u32 = 1002;
    pub const toggle: u32 = 1001;
};

pub const Resource = struct {
    pub const mute_icon: u32 = 101;
    pub const unmute_icon: u32 = 102;
};

pub const Timer = struct {
    pub const rehook_id: usize = 1;
    pub const rehook_interval_ms: u32 = 10 * 60 * 1000;
};
