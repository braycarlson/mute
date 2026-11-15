const std = @import("std");

const mantra = @import("mantra");

const Message = @import("../message.zig").Message;
const Mode = @import("../mode.zig").Mode;

const assert = std.debug.assert;

const Direction = mantra.Direction;
const Event = mantra.Device.Event;

pub fn DeviceEventsType(comptime App: type, comptime mode: Mode) type {
    return struct {
        pub fn on_change(app: *App, event: Event, direction: ?Direction) void {
            if (direction) |value| assert(value.is_valid());

            if (!is_relevant(direction)) {
                return;
            }

            _ = app.post(@fromBackingInt(@backingInt(to_message(event))));
        }

        fn is_relevant(direction: ?Direction) bool {
            if (direction) |value| assert(value.is_valid());

            const value = direction orelse {
                return true;
            };

            return value == mode.to_direction();
        }
    };
}

fn to_message(event: Event) Message {
    const result: Message = switch (event) {
        .default_changed => .device_default_changed,
        .added, .removed, .state_changed => .device_changed,
    };

    assert(@backingInt(result) > 0);

    return result;
}

const testing = std.testing;

const Fakes = @import("../fakes.zig");

test DeviceEventsType {
    const capture = DeviceEventsType(Fakes.App, .capture);
    const render = DeviceEventsType(Fakes.App, .render);

    try testing.expect(capture.is_relevant(null));
    try testing.expect(capture.is_relevant(.capture));
    try testing.expect(!capture.is_relevant(.render));
    try testing.expect(render.is_relevant(null));
    try testing.expect(render.is_relevant(.render));
    try testing.expect(!render.is_relevant(.capture));
}

test "hotplug events share one code and the default change keeps its own" {
    try testing.expectEqual(Message.device_changed, to_message(.added));
    try testing.expectEqual(Message.device_changed, to_message(.removed));
    try testing.expectEqual(Message.device_changed, to_message(.state_changed));

    try testing.expectEqual(Message.device_default_changed, to_message(.default_changed));
}
