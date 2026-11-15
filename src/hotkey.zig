const std = @import("std");

const nimble = @import("nimble");

const Binding = @import("binding.zig").Binding;
const Message = @import("message.zig").Message;

const assert = std.debug.assert;

const CapacityError = nimble.remote.CapacityError;
const Key = nimble.Key;
const Keycode = nimble.Keycode;
const PlatformError = nimble.remote.PlatformError;
const RequestError = nimble.remote.RequestError;

const RemoteError = CapacityError || PlatformError || RequestError;

pub fn HotkeyType(comptime Client: type, comptime App: type) type {
    return struct {
        binding: ?Binding,
        client: Client,
        handle: ?Client.Binding,
        runtime: *App,

        const Hotkey = @This();

        pub fn init(runtime: *App) Hotkey {
            return Hotkey{ .binding = null, .client = .{}, .handle = null, .runtime = runtime };
        }

        pub fn deinit(hotkey: *Hotkey) void {
            hotkey.stop();
            hotkey.binding = null;

            assert(hotkey.binding == null);
            assert(!hotkey.is_running());
        }

        pub fn bind(hotkey: *Hotkey, value: *const Binding) RemoteError!void {
            assert(value.key_count > 0);

            hotkey.binding = value.*;

            if (!hotkey.client.is_connected()) {
                return;
            }

            hotkey.rebind() catch |err| {
                hotkey.binding = null;

                return err;
            };

            assert(hotkey.handle != null);
        }

        pub fn is_running(hotkey: *const Hotkey) bool {
            return hotkey.client.is_connected();
        }

        pub fn refresh(hotkey: *Hotkey) RemoteError!void {
            if (hotkey.is_running()) {
                return;
            }

            hotkey.stop();

            try hotkey.start();
        }

        pub fn start(hotkey: *Hotkey) RemoteError!void {
            try hotkey.client.connect();
            errdefer hotkey.client.disconnect();

            if (hotkey.binding != null) {
                try hotkey.rebind();
            }
        }

        pub fn stop(hotkey: *Hotkey) void {
            hotkey.client.disconnect();

            hotkey.handle = null;

            assert(!hotkey.is_running());
        }

        fn rebind(hotkey: *Hotkey) RemoteError!void {
            assert(hotkey.binding != null);
            assert(hotkey.client.is_connected());

            const value = &hotkey.binding.?;

            if (hotkey.handle) |handle| {
                hotkey.handle = null;

                try hotkey.client.unbind(handle);
            }

            if (value.is_chord()) {
                hotkey.handle = try hotkey.client.bind_chord(
                    value.to_keys(),
                    .{ .consume = true },
                    App,
                    hotkey.runtime,
                    on_trigger,
                );

                return;
            }

            hotkey.handle = try hotkey.client.bind_key(
                value.trigger(),
                value.modifiers,
                .{ .consume = true },
                App,
                hotkey.runtime,
                on_trigger,
            );
        }

        fn on_trigger(runtime: *App, _: ?*const Key) void {
            _ = runtime.post(@fromBackingInt(@backingInt(Message.toggle)));
        }
    };
}

const testing = std.testing;

const Fakes = @import("fakes.zig");

const FakeHotkey = HotkeyType(Fakes.Client, Fakes.App);

test HotkeyType {
    var app: Fakes.App = undefined;

    try app.init(.{ .name = "hotkey" });
    defer app.deinit();

    var hotkey = FakeHotkey.init(&app);
    defer hotkey.deinit();

    const value = try Binding.parse("Ctrl+Alt+M");

    try hotkey.bind(&value);

    try testing.expect(hotkey.binding != null);
    try testing.expect(hotkey.handle == null);
    try testing.expect(!hotkey.is_running());
}

test "stopping an unstarted hotkey is inert" {
    var app: Fakes.App = undefined;

    try app.init(.{ .name = "hotkey" });
    defer app.deinit();

    var hotkey = FakeHotkey.init(&app);
    defer hotkey.deinit();

    hotkey.stop();

    try testing.expect(!hotkey.is_running());
    try testing.expect(hotkey.binding == null);
}

test "a multi key binding is retained as a chord" {
    var app: Fakes.App = undefined;

    try app.init(.{ .name = "hotkey" });
    defer app.deinit();

    var hotkey = FakeHotkey.init(&app);
    defer hotkey.deinit();

    const value = try Binding.parse("A+B");

    try hotkey.bind(&value);

    try testing.expect(hotkey.binding.?.is_chord());
}

test "rebinding swaps the stored binding" {
    var app: Fakes.App = undefined;

    try app.init(.{ .name = "hotkey" });
    defer app.deinit();

    var hotkey = FakeHotkey.init(&app);
    defer hotkey.deinit();

    const first = try Binding.parse("PageUp+PageDown");
    const second = try Binding.parse("Ctrl+Alt+M");

    try hotkey.bind(&first);
    try hotkey.bind(&second);

    try testing.expectEqual(Keycode.m, hotkey.binding.?.trigger());
}
