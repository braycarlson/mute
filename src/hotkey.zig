const std = @import("std");

const nimble = @import("nimble");
const wisp = @import("wisp");

const binding = @import("binding.zig");
const constant = @import("constant.zig");

const assert = std.debug.assert;

const Binding = binding.Binding;
const Client = nimble.remote.Client;
const Key = nimble.Key;
const Keycode = nimble.Keycode;

pub const Error = error{
    BindFailed,
    HookFailed,
    RuntimeOpenFailed,
    SpawnFailed,
};

pub const Combo = struct {
    fired: bool = false,
    held: [binding.key_max]bool = @splat(false),

    pub fn clear(combo: *Combo) void {
        combo.fired = false;
        combo.held = @splat(false);

        assert(!combo.fired);
    }

    pub fn press(combo: *Combo, value: *const Binding, code: Keycode) bool {
        const slot = index_of(value, code) orelse return false;

        assert(slot < binding.key_max);

        combo.held[slot] = true;

        if (combo.fired) {
            return false;
        }

        if (!combo.is_complete(value)) {
            return false;
        }

        combo.fired = true;

        return true;
    }

    pub fn release(combo: *Combo, value: *const Binding, code: Keycode) void {
        const slot = index_of(value, code) orelse return;

        assert(slot < binding.key_max);

        combo.held[slot] = false;
        combo.fired = false;
    }

    pub fn is_complete(combo: *const Combo, value: *const Binding) bool {
        assert(value.key_count > 0);
        assert(value.key_count <= binding.key_max);

        var index: u32 = 0;

        while (index < value.key_count) : (index += 1) {
            assert(index < binding.key_max);

            if (!combo.held[index]) return false;
        }

        return true;
    }

    fn index_of(value: *const Binding, code: Keycode) ?u32 {
        assert(value.key_count <= binding.key_max);

        var index: u32 = 0;

        while (index < value.key_count) : (index += 1) {
            assert(index < binding.key_max);

            if (value.keys[index] == code) return index;
        }

        return null;
    }
};

pub const InputThread = struct {
    active: ?Binding,
    identifier: ?u32,
    client: Client,

    pub fn init() InputThread {
        return InputThread{ .active = null, .identifier = null, .client = .{} };
    }

    pub fn deinit(thread: *InputThread) void {
        thread.stop();
        thread.active = null;

        assert(!thread.is_bound());
    }

    pub fn bind(thread: *InputThread, value: *const Binding) Error!void {
        assert(value.key_count > 0);

        thread.active = value.*;

        if (!thread.client.is_connected()) {
            return;
        }

        thread.rebind() catch {
            thread.active = null;

            return Error.BindFailed;
        };

        assert(thread.is_bound());
    }

    pub fn unbind(thread: *InputThread) void {
        if (thread.identifier) |identifier| {
            thread.client.unbind(identifier);
        }

        thread.active = null;
        thread.identifier = null;
    }

    pub fn is_bound(thread: *const InputThread) bool {
        return thread.active != null;
    }

    pub fn is_running(thread: *const InputThread) bool {
        return thread.client.is_connected();
    }

    pub fn start(thread: *InputThread) Error!void {
        thread.client.connect() catch {
            return Error.RuntimeOpenFailed;
        };

        errdefer thread.client.disconnect();

        if (thread.active != null) {
            try thread.rebind();
        }
    }

    pub fn stop(thread: *InputThread) void {
        thread.client.disconnect();

        thread.identifier = null;

        assert(!thread.is_running());
    }

    pub fn refresh(thread: *InputThread) Error!void {
        if (thread.is_running()) {
            return;
        }

        thread.stop();

        try thread.start();
    }

    fn rebind(thread: *InputThread) Error!void {
        assert(thread.active != null);
        assert(thread.client.is_connected());

        const value = &thread.active.?;

        if (thread.identifier) |identifier| {
            thread.client.unbind(identifier);

            thread.identifier = null;
        }

        if (value.is_chord()) {
            thread.identifier = thread.client.bind_chord(
                value.to_keys(),
                .{ .consume = true },
                on_trigger,
                thread,
            ) catch return Error.BindFailed;

            return;
        }

        thread.identifier = thread.client.bind_key(
            value.trigger(),
            value.modifiers,
            .{ .consume = true },
            on_trigger,
            thread,
        ) catch return Error.BindFailed;
    }
};

fn on_trigger(_: ?*anyopaque, _: ?*const Key) void {
    _ = wisp.loop.post(constant.Message.toggle);
}

const testing = std.testing;

test "an input thread starts unbound and disconnected" {
    var input = InputThread.init();
    defer input.deinit();

    try testing.expect(!input.is_bound());
    try testing.expect(!input.is_running());
}

test "stopping an unstarted input thread is inert" {
    var input = InputThread.init();
    defer input.deinit();

    input.stop();

    try testing.expect(!input.is_running());
}

test "binding while disconnected stores the binding for the next connect" {
    var input = InputThread.init();
    defer input.deinit();

    const value = try Binding.parse("Ctrl+Alt+M");

    try input.bind(&value);

    try testing.expect(input.is_bound());
    try testing.expect(input.identifier == null);
}

test "a multi key binding is retained as a chord" {
    var input = InputThread.init();
    defer input.deinit();

    const value = try Binding.parse("A+B");

    try input.bind(&value);

    try testing.expect(input.is_bound());
    try testing.expect(input.active.?.is_chord());
}

test "a combo fires once when every key is held, in either order" {
    const value = try Binding.parse("PageUp+PageDown");

    var forward = Combo{};

    try testing.expect(!forward.press(&value, .page_up));
    try testing.expect(forward.press(&value, .page_down));

    var reverse = Combo{};

    try testing.expect(!reverse.press(&value, .page_down));
    try testing.expect(reverse.press(&value, .page_up));
}

test "a repeated key never re-fires or breaks a combo in progress" {
    const value = try Binding.parse("PageUp+PageDown");

    var combo = Combo{};

    var beat: u32 = 0;

    while (beat < 7) : (beat += 1) {
        try testing.expect(!combo.press(&value, .page_up));
    }

    try testing.expect(combo.press(&value, .page_down));

    beat = 0;

    while (beat < 5) : (beat += 1) {
        try testing.expect(!combo.press(&value, .page_down));
        try testing.expect(!combo.press(&value, .page_up));
    }
}

test "a combo re-arms once a key is released" {
    const value = try Binding.parse("PageUp+PageDown");

    var combo = Combo{};

    _ = combo.press(&value, .page_up);

    try testing.expect(combo.press(&value, .page_down));

    combo.release(&value, .page_down);

    try testing.expect(combo.press(&value, .page_down));
}

test "a key outside the combo is ignored entirely" {
    const value = try Binding.parse("PageUp+PageDown");

    var combo = Combo{};

    try testing.expect(!combo.press(&value, .a));
    try testing.expect(!combo.press(&value, .page_up));
    try testing.expect(!combo.press(&value, .escape));
    try testing.expect(combo.press(&value, .page_down));
}

test "rebinding swaps the active binding" {
    var input = InputThread.init();
    defer input.deinit();

    const first = try Binding.parse("PageUp+PageDown");
    const second = try Binding.parse("Ctrl+Alt+M");

    try input.bind(&first);
    try input.bind(&second);

    try testing.expect(input.is_bound());
    try testing.expectEqual(Keycode.m, input.active.?.trigger());
}

test "unbinding clears the active binding" {
    var input = InputThread.init();
    defer input.deinit();

    const value = try Binding.parse("Ctrl+Alt+M");

    try input.bind(&value);

    input.unbind();
    input.unbind();

    try testing.expect(!input.is_bound());
}
