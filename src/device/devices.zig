const std = @import("std");

const mantra = @import("mantra");

const audio = @import("audio.zig");
const Config = @import("../config.zig").Config;
const DeviceType = @import("../device.zig").DeviceType;
const Mode = @import("../mode.zig").Mode;

const assert = std.debug.assert;

const Entry = mantra.Device;
const PlatformError = mantra.PlatformError;
const RequestError = mantra.RequestError;

const limits = mantra.limits;

pub fn DevicesType(comptime Mixer: type, comptime mode: Mode) type {
    return struct {
        current: ?Device = null,
        index: u32 = 0,
        list: Entry.List = Entry.List.init(),
        mixer: *Mixer,

        const Devices = @This();
        const Device = DeviceType(Mixer);

        pub fn init(mixer: *Mixer) Devices {
            const result = Devices{ .mixer = mixer };

            assert(result.list.is_empty());

            return result;
        }

        pub fn deinit(devices: *Devices) void {
            devices.current = null;
            devices.index = 0;

            devices.list.clear();

            assert(devices.list.is_empty());
        }

        pub fn count(devices: *const Devices) u32 {
            assert(devices.list.count <= limits.device_count_max);

            return devices.list.count;
        }

        pub fn entry(devices: *const Devices) ?*const Entry {
            assert(devices.list.count <= limits.device_count_max);

            if (devices.list.count == 0) {
                return null;
            }

            if (devices.index >= devices.list.count) {
                return null;
            }

            assert(devices.index < limits.device_count_max);

            return &devices.list.items[devices.index];
        }

        pub fn enumerate(devices: *Devices) bool {
            devices.mixer.enumerate(&devices.list, mode.to_direction()) catch {
                devices.list.clear();

                assert(devices.list.is_empty());

                return false;
            };

            assert(devices.list.count <= limits.device_count_max);

            return true;
        }

        pub fn find(devices: *const Devices, side: *const Config.Side) ?Device {
            if (side.get_name()) |name| {
                const found = audio.match(&devices.list, name) orelse {
                    return null;
                };

                assert(found < devices.list.count);

                return Device.init(devices.mixer, devices.list.items[found].id);
            }

            const id = devices.mixer.default(mode.to_direction()) catch {
                return null;
            };

            return Device.init(devices.mixer, id);
        }

        pub fn next(devices: *Devices) void {
            if (devices.list.count == 0) {
                return;
            }

            const wanted = if (devices.index + 1 >= devices.list.count) 0 else devices.index + 1;

            devices.select_by_index(wanted);
        }

        pub fn previous(devices: *Devices) void {
            if (devices.list.count == 0) {
                return;
            }

            const wanted = if (devices.index == 0) devices.list.count - 1 else devices.index - 1;

            devices.select_by_index(wanted);
        }

        pub fn prune(devices: *Devices) bool {
            const device = devices.current orelse {
                return false;
            };

            assert(device.id.is_valid());
            assert(devices.list.count <= limits.device_count_max);

            if (devices.list.find(&device.id) != null) {
                return false;
            }

            devices.current = null;

            assert(devices.current == null);

            return true;
        }

        pub fn restore_default(devices: *Devices) (PlatformError || RequestError)!void {
            if (devices.current) |*device| {
                if (device.is_default()) {
                    return;
                }

                try device.set_as_default();
            }
        }

        pub fn update_index(devices: *Devices) void {
            const device = devices.current orelse return;

            var position: u32 = 0;

            while (position < devices.list.count) : (position += 1) {
                assert(position < limits.device_count_max);

                if (devices.list.items[position].id.eql(&device.id)) {
                    devices.index = position;

                    return;
                }
            }
        }

        fn select_by_index(devices: *Devices, wanted: u32) void {
            assert(wanted < devices.list.count);
            assert(wanted < limits.device_count_max);

            const info = &devices.list.items[wanted];

            if (!info.id.is_valid()) {
                return;
            }

            devices.current = Device.init(devices.mixer, info.id);
            devices.index = wanted;
        }
    };
}

const testing = std.testing;

const Fakes = @import("../fakes.zig");

const Capture = DevicesType(Fakes.Mixer, .capture);

fn seed(devices: *Capture, names: []const []const u8) !void {
    assert(names.len > 0);
    assert(names.len <= mantra.limits.device_count_max);

    for (names) |name| {
        const id = try Entry.Id.init(.capture, name);

        try devices.list.append(Entry.init(id, name, .{}));
    }
}

test DevicesType {
    var mixer: Fakes.Mixer = undefined;

    try mixer.init(.{});
    defer mixer.deinit();

    var devices = Capture.init(&mixer);
    defer devices.deinit();

    try testing.expectEqual(@as(u32, 0), devices.count());
    try testing.expect(devices.entry() == null);

    try seed(&devices, &.{ "First", "Second", "Third" });

    devices.next();

    try testing.expectEqual(@as(u32, 1), devices.index);
    try testing.expectEqualStrings("Second", devices.entry().?.get_name());

    devices.previous();
    devices.previous();

    try testing.expectEqual(@as(u32, 2), devices.index);
    try testing.expectEqualStrings("Third", devices.current.?.id.slice());
}

test "cycling an empty list is inert" {
    var mixer: Fakes.Mixer = undefined;

    try mixer.init(.{});
    defer mixer.deinit();

    var devices = Capture.init(&mixer);

    devices.next();
    devices.previous();

    try testing.expectEqual(@as(u32, 0), devices.index);
    try testing.expect(devices.current == null);
}

test "the index follows the current device after a re-enumeration" {
    var mixer: Fakes.Mixer = undefined;

    try mixer.init(.{});
    defer mixer.deinit();

    var devices = Capture.init(&mixer);

    try seed(&devices, &.{ "First", "Second", "Third" });

    devices.current = Capture.Device.init(&mixer, try Entry.Id.init(.capture, "Third"));

    devices.update_index();

    try testing.expectEqual(@as(u32, 2), devices.index);

    const info = devices.entry() orelse return error.MissingInfo;

    try testing.expectEqualStrings("Third", info.get_name());
}

test "a current device that is gone leaves the index untouched" {
    var mixer: Fakes.Mixer = undefined;

    try mixer.init(.{});
    defer mixer.deinit();

    var devices = Capture.init(&mixer);

    try seed(&devices, &.{ "First", "Second" });

    devices.index = 1;
    devices.current = Capture.Device.init(&mixer, try Entry.Id.init(.capture, "Absent"));

    devices.update_index();

    try testing.expectEqual(@as(u32, 1), devices.index);
}

test "a current device still in the list survives a prune" {
    var mixer: Fakes.Mixer = undefined;

    try mixer.init(.{});
    defer mixer.deinit();

    var devices = Capture.init(&mixer);

    try seed(&devices, &.{ "First", "Second" });

    devices.current = Capture.Device.init(&mixer, try Entry.Id.init(.capture, "Second"));

    try testing.expect(!devices.prune());
    try testing.expect(devices.current != null);
}

test "a current device missing from the list is pruned" {
    var mixer: Fakes.Mixer = undefined;

    try mixer.init(.{});
    defer mixer.deinit();

    var devices = Capture.init(&mixer);

    try seed(&devices, &.{ "First", "Second" });

    devices.current = Capture.Device.init(&mixer, try Entry.Id.init(.capture, "Absent"));

    try testing.expect(devices.prune());
    try testing.expect(devices.current == null);
}

test "pruning without a selection is inert" {
    var mixer: Fakes.Mixer = undefined;

    try mixer.init(.{});
    defer mixer.deinit();

    var devices = Capture.init(&mixer);

    try seed(&devices, &.{"First"});

    try testing.expect(!devices.prune());
    try testing.expect(devices.current == null);
}

test "deinit clears the list and the selection" {
    var mixer: Fakes.Mixer = undefined;

    try mixer.init(.{});
    defer mixer.deinit();

    var devices = Capture.init(&mixer);

    try seed(&devices, &.{"First"});

    devices.current = Capture.Device.init(&mixer, try Entry.Id.init(.capture, "First"));

    devices.deinit();

    try testing.expectEqual(@as(u32, 0), devices.count());
    try testing.expect(devices.current == null);
}
