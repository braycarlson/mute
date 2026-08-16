const std = @import("std");

const mantra = @import("mantra");

const audio = @import("audio.zig");
const DeviceConfig = @import("../config.zig").DeviceConfig;
const Device = @import("device.zig").Device;
const Mode = @import("../mode.zig").Mode;

const assert = std.debug.assert;

pub const DeviceInfo = mantra.DeviceInfo;
pub const DeviceList = mantra.DeviceList;

pub const devices_max: u32 = mantra.devices_max;

comptime {
    assert(devices_max > 0);
}

pub fn DeviceManagerType(comptime mode: Mode) type {
    return struct {
        current: ?Device = null,
        index: u32 = 0,
        list: DeviceList = DeviceList.init(),

        pub fn init() @This() {
            const result = @This(){};

            assert(result.list.is_empty());

            return result;
        }

        pub fn deinit(self: *@This()) void {
            self.current = null;
            self.index = 0;

            self.list.clear();

            assert(self.list.is_empty());
        }

        pub fn count(self: *const @This()) u32 {
            assert(self.list.count <= devices_max);

            return self.list.count;
        }

        pub fn enumerate(self: *@This()) bool {
            mantra.devices.enumerate(mode.to_direction(), &self.list) catch {
                self.list.clear();

                assert(self.list.is_empty());

                return false;
            };

            assert(self.list.count <= devices_max);

            return true;
        }

        pub fn prune(self: *@This()) bool {
            const device = self.current orelse {
                return false;
            };

            assert(device.id.is_valid());
            assert(self.list.count <= devices_max);

            if (self.list.find(&device.id) != null) {
                return false;
            }

            self.current = null;

            assert(self.current == null);

            return true;
        }

        pub fn find(self: *@This(), device_config: *DeviceConfig) ?Device {
            if (device_config.get_name()) |name| {
                const found = audio.match(&self.list, name) orelse {
                    return null;
                };

                assert(found < self.list.count);

                return Device.init(self.list.items[found].id);
            }

            const id = mantra.devices.default(mode.to_direction()) catch {
                return null;
            };

            return Device.init(id);
        }

        pub fn get_current_info(self: *@This()) ?*const DeviceInfo {
            assert(self.list.count <= devices_max);

            if (self.list.count == 0 or self.index >= self.list.count) {
                return null;
            }

            assert(self.index < devices_max);

            return &self.list.items[self.index];
        }

        pub fn update_index(self: *@This()) void {
            const device = self.current orelse return;

            var position: u32 = 0;

            while (position < self.list.count) : (position += 1) {
                assert(position < devices_max);

                if (self.list.items[position].id.eql(&device.id)) {
                    self.index = position;

                    return;
                }
            }
        }

        pub fn next(self: *@This()) void {
            if (self.list.count == 0) {
                return;
            }

            const wanted = if (self.index + 1 >= self.list.count) 0 else self.index + 1;

            self.select_by_index(wanted);
        }

        pub fn previous(self: *@This()) void {
            if (self.list.count == 0) {
                return;
            }

            const wanted = if (self.index == 0) self.list.count - 1 else self.index - 1;

            self.select_by_index(wanted);
        }

        pub fn restore_default(self: *@This()) mantra.DeviceError!void {
            if (self.current) |*device| {
                if (device.is_default()) {
                    return;
                }

                try device.set_as_default();
            }
        }

        pub fn save_default(self: *@This()) mantra.DeviceError!void {
            if (self.current) |*device| {
                try device.set_as_default();
            }
        }

        pub fn handle_added(self: *@This(), device_config: *DeviceConfig) bool {
            if (self.current != null) {
                return false;
            }

            self.current = self.find(device_config);

            if (self.current == null) {
                return false;
            }

            self.update_index();

            return true;
        }

        pub fn handle_removed(self: *@This(), device_config: *DeviceConfig) bool {
            const device = self.current orelse {
                return false;
            };

            const replacement = self.find(device_config) orelse {
                self.current = null;

                return true;
            };

            if (!replacement.id.eql(&device.id)) {
                self.current = null;

                return true;
            }

            return false;
        }

        fn select_by_index(self: *@This(), wanted: u32) void {
            assert(wanted < self.list.count);
            assert(wanted < devices_max);

            const info = &self.list.items[wanted];

            if (!info.id.is_valid()) {
                return;
            }

            self.current = Device.init(info.id);
            self.index = wanted;
        }
    };
}

const testing = std.testing;

const Capture = DeviceManagerType(.capture);

fn seed(manager: *Capture, names: []const []const u8) !void {
    for (names) |name| {
        const id = try mantra.DeviceId.init(.capture, name);

        try manager.list.append(DeviceInfo.init(id, name, false));
    }
}

test "a fresh manager holds nothing" {
    var manager = Capture.init();

    try testing.expectEqual(@as(u32, 0), manager.count());
    try testing.expect(manager.current == null);
    try testing.expect(manager.get_current_info() == null);
}

test "cycling wraps in both directions" {
    var manager = Capture.init();

    try seed(&manager, &.{ "First", "Second", "Third" });

    try testing.expectEqual(@as(u32, 3), manager.count());

    manager.next();

    try testing.expectEqual(@as(u32, 1), manager.index);

    manager.next();
    manager.next();

    try testing.expectEqual(@as(u32, 0), manager.index);

    manager.previous();

    try testing.expectEqual(@as(u32, 2), manager.index);
}

test "cycling an empty list is inert" {
    var manager = Capture.init();

    manager.next();
    manager.previous();

    try testing.expectEqual(@as(u32, 0), manager.index);
    try testing.expect(manager.current == null);
}

test "the index follows the current device after a re-enumeration" {
    var manager = Capture.init();

    try seed(&manager, &.{ "First", "Second", "Third" });

    manager.current = Device.init(try mantra.DeviceId.init(.capture, "Third"));

    manager.update_index();

    try testing.expectEqual(@as(u32, 2), manager.index);

    const info = manager.get_current_info() orelse return error.MissingInfo;

    try testing.expectEqualStrings("Third", info.get_name());
}

test "a current device that is gone leaves the index untouched" {
    var manager = Capture.init();

    try seed(&manager, &.{ "First", "Second" });

    manager.index = 1;
    manager.current = Device.init(try mantra.DeviceId.init(.capture, "Absent"));

    manager.update_index();

    try testing.expectEqual(@as(u32, 1), manager.index);
}

test "a current device still in the list survives a prune" {
    var manager = Capture.init();

    try seed(&manager, &.{ "First", "Second" });

    manager.current = Device.init(try mantra.DeviceId.init(.capture, "Second"));

    try testing.expect(!manager.prune());
    try testing.expect(manager.current != null);
}

test "a current device missing from the list is pruned" {
    var manager = Capture.init();

    try seed(&manager, &.{ "First", "Second" });

    manager.current = Device.init(try mantra.DeviceId.init(.capture, "Absent"));

    try testing.expect(manager.prune());
    try testing.expect(manager.current == null);
}

test "pruning without a selection is inert" {
    var manager = Capture.init();

    try seed(&manager, &.{"First"});

    try testing.expect(!manager.prune());
    try testing.expect(manager.current == null);
}

test "deinit clears the list and the selection" {
    var manager = Capture.init();

    try seed(&manager, &.{"First"});

    manager.current = Device.init(try mantra.DeviceId.init(.capture, "First"));

    manager.deinit();

    try testing.expectEqual(@as(u32, 0), manager.count());
    try testing.expect(manager.current == null);
}
