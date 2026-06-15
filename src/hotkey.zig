const nimble = @import("nimble");

pub const HotkeyCallback = *const fn () void;

pub fn HotkeyHandler(comptime queue_capacity: u32) type {
    return struct {
        const Self = @This();
        const hotkey_len_max: u32 = 32;

        const Hook = nimble.Keyboard(.{
            .capacity = queue_capacity,
            .capacity_chord = 1,
            .capacity_command = 1,
            .capacity_timer = 1,
            .capacity_repeat = 1,
            .capacity_macro = 1,
            .capacity_toggle = 1,
            .capacity_sequence = 1,
        });

        callback: ?HotkeyCallback = null,
        hook: Hook = Hook.init(),
        hotkey: [hotkey_len_max]u8 = undefined,
        hotkey_len: u32 = 0,
        binding_id: ?u32 = null,

        pub fn init() Self {
            return Self{};
        }

        pub fn deinit(self: *Self) void {
            self.remove();
        }

        pub fn set_callback(self: *Self, callback: HotkeyCallback) void {
            self.callback = callback;
        }

        pub fn set_hotkey(self: *Self, hotkey: ?[]const u8) void {
            self.unregister_binding();

            if (hotkey) |keys| {
                if (keys.len > 0 and keys.len <= hotkey_len_max) {
                    @memcpy(self.hotkey[0..keys.len], keys);
                    self.hotkey_len = @intCast(keys.len);
                    self.register_binding();
                    return;
                }
            }

            self.hotkey_len = 0;
        }

        pub fn install(self: *Self) void {
            self.hook.start() catch {};
        }

        pub fn remove(self: *Self) void {
            self.unregister_binding();
            self.hook.stop();
        }

        pub fn is_running(self: *Self) bool {
            return self.hook.is_running();
        }

        fn register_binding(self: *Self) void {
            if (self.hotkey_len == 0) {
                return;
            }

            if (self.binding_id != null) {
                return;
            }

            const keys = self.hotkey[0..self.hotkey_len];

            if (keys.len == 1) {
                self.binding_id = self.hook.registry.register(
                    keys[0],
                    .{},
                    invoke_callback,
                    self,
                    .{},
                ) catch null;
            } else {
                self.binding_id = self.hook.sequence_registry.register(
                    keys,
                    invoke_callback_sequence,
                    self,
                    .{},
                ) catch null;
            }
        }

        fn unregister_binding(self: *Self) void {
            if (self.binding_id) |id| {
                if (self.hotkey_len == 1) {
                    self.hook.registry.unregister(id) catch {};
                } else {
                    self.hook.sequence_registry.unregister(id) catch {};
                }
                self.binding_id = null;
            }
        }

        fn invoke_callback(ctx: *anyopaque, _: *const nimble.Key) nimble.Response {
            const handler: *Self = @ptrCast(@alignCast(ctx));

            if (handler.callback) |callback| {
                callback();
            }

            return .consume;
        }

        fn invoke_callback_sequence(ctx: *anyopaque) void {
            const handler: *Self = @ptrCast(@alignCast(ctx));

            if (handler.callback) |callback| {
                callback();
            }
        }
    };
}
