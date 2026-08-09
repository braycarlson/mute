const std = @import("std");

const mantra = @import("mantra");

const assert = std.debug.assert;

const DeviceId = mantra.DeviceId;

pub const Device = struct {
    id: DeviceId,

    pub fn init(id: DeviceId) Device {
        assert(id.is_valid());

        return Device{ .id = id };
    }

    pub fn get_id(device: *const Device) []const u8 {
        const result = device.id.slice();

        assert(result.len > 0);

        return result;
    }

    pub fn get_volume(device: *const Device) f32 {
        const result = mantra.control.get_volume(&device.id) catch mantra.volume_min;

        assert(result >= mantra.volume_min);
        assert(result <= mantra.volume_max);

        return result;
    }

    pub fn is_default(device: *const Device) bool {
        const current = mantra.devices.default(device.id.direction) catch {
            return false;
        };

        return current.eql(&device.id);
    }

    pub fn is_enabled(device: *const Device) bool {
        var list = mantra.DeviceList.init();

        mantra.devices.enumerate(device.id.direction, &list) catch {
            return false;
        };

        return list.find(&device.id) != null;
    }

    pub fn is_muted(device: *const Device) bool {
        return mantra.control.is_muted(&device.id) catch false;
    }

    pub fn mute(device: *Device) void {
        mantra.control.set_mute(&device.id, true) catch {
            return;
        };
    }

    pub fn set_as_default(device: *Device) mantra.DeviceError!void {
        try mantra.devices.set_default(&device.id);
    }

    pub fn set_volume(device: *Device, level: f32) void {
        assert(level >= mantra.volume_min);
        assert(level <= mantra.volume_max);

        mantra.control.set_volume(&device.id, level) catch {
            return;
        };
    }

    pub fn toggle_mute(device: *Device) bool {
        const current = device.is_muted();

        if (current) {
            device.unmute();
        } else {
            device.mute();
        }

        return !current;
    }

    pub fn unmute(device: *Device) void {
        mantra.control.set_mute(&device.id, false) catch {
            return;
        };
    }
};

const testing = std.testing;

test "a device carries the identifier it was built from" {
    const id = try DeviceId.init(.render, "endpoint-one");

    const device = Device.init(id);

    try testing.expectEqualStrings("endpoint-one", device.get_id());
    try testing.expectEqual(mantra.Direction.render, device.id.direction);
}
