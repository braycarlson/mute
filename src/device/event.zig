const std = @import("std");

const mantra = @import("mantra");
const wisp = @import("wisp");

const constant = @import("../constant.zig");
const Mode = @import("../mode.zig").Mode;

const assert = std.debug.assert;

const DeviceEvent = mantra.DeviceEvent;
const Direction = mantra.Direction;

pub fn to_message(event: DeviceEvent) u32 {
    const result = switch (event) {
        .default_changed => constant.Message.device_default_changed,
        .added, .removed, .state_changed => constant.Message.device_changed,
    };

    assert(result > 0);

    return result;
}

pub fn DeviceEventsType(comptime mode: Mode) type {
    return struct {
        pub fn subscribe() mantra.EventError!void {
            try mantra.events.subscribe(handle, null);
        }

        pub fn unsubscribe() void {
            mantra.events.unsubscribe();
        }

        pub fn is_subscribed() bool {
            return mantra.events.is_subscribed();
        }

        pub fn is_relevant(direction: ?Direction) bool {
            const value = direction orelse {
                return true;
            };

            return value == mode.to_direction();
        }

        fn handle(event: DeviceEvent, direction: ?Direction, context: ?*anyopaque) void {
            _ = context;

            if (!is_relevant(direction)) {
                return;
            }

            _ = wisp.loop.post(to_message(event));
        }
    };
}

const testing = std.testing;

test "hotplug events share one code and the default change keeps its own" {
    try testing.expectEqual(constant.Message.device_changed, to_message(.added));
    try testing.expectEqual(constant.Message.device_changed, to_message(.removed));
    try testing.expectEqual(constant.Message.device_changed, to_message(.state_changed));

    try testing.expectEqual(
        constant.Message.device_default_changed,
        to_message(.default_changed),
    );
}

test "an event without a direction is always relevant" {
    const capture = DeviceEventsType(.capture);
    const render = DeviceEventsType(.render);

    try testing.expect(capture.is_relevant(null));
    try testing.expect(render.is_relevant(null));
}

test "an event carrying the other direction is dropped" {
    const capture = DeviceEventsType(.capture);
    const render = DeviceEventsType(.render);

    try testing.expect(capture.is_relevant(.capture));
    try testing.expect(!capture.is_relevant(.render));

    try testing.expect(render.is_relevant(.render));
    try testing.expect(!render.is_relevant(.capture));
}
