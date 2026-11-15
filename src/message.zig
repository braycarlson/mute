pub const Message = enum(u32) {
    config_reload = 1,
    device_changed = 2,
    device_default_changed = 3,
    toggle = 4,
    widget_input = 5,
    _,
};
