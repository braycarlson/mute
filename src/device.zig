const std = @import("std");

const mantra = @import("mantra");

pub const devices = @import("device/devices.zig");
pub const event = @import("device/event.zig");

const assert = std.debug.assert;

const Id = mantra.Device.Id;
const PlatformError = mantra.PlatformError;
const RequestError = mantra.RequestError;

const limits = mantra.limits;

pub fn DeviceType(comptime Mixer: type) type {
    return struct {
        id: Id,
        mixer: *Mixer,

        const Device = @This();

        pub fn init(mixer: *Mixer, id: Id) Device {
            assert(id.is_valid());

            return Device{ .id = id, .mixer = mixer };
        }

        pub fn get_volume(device: *const Device) f32 {
            const result = device.mixer.get_volume(&device.id) catch limits.volume_fraction_min;

            assert(result >= limits.volume_fraction_min);
            assert(result <= limits.volume_fraction_max);

            return result;
        }

        pub fn is_default(device: *const Device) bool {
            const current = device.mixer.default(device.id.direction) catch {
                return false;
            };

            return current.eql(&device.id);
        }

        pub fn is_muted(device: *const Device) bool {
            return device.mixer.is_muted(&device.id) catch false;
        }

        pub fn mute(device: *Device) void {
            device.mixer.mute(&device.id) catch {
                return;
            };
        }

        pub fn set_as_default(device: *Device) (PlatformError || RequestError)!void {
            try device.mixer.set_default(&device.id);
        }

        pub fn set_volume(device: *Device, level: f32) void {
            assert(level >= limits.volume_fraction_min);
            assert(level <= limits.volume_fraction_max);

            device.mixer.set_volume(&device.id, level) catch {
                return;
            };
        }

        pub fn unmute(device: *Device) void {
            device.mixer.unmute(&device.id) catch {
                return;
            };
        }
    };
}

const testing = std.testing;

const Fakes = @import("fakes.zig");

test DeviceType {
    var mixer: Fakes.Mixer = undefined;

    try mixer.init(.{});
    defer mixer.deinit();

    var list = mantra.Device.List.init();

    try mixer.enumerate(&list, .capture);
    try testing.expect(!list.is_empty());

    var device = DeviceType(Fakes.Mixer).init(&mixer, list.slice()[0].id);

    device.mute();

    try testing.expect(device.is_muted());

    device.unmute();

    try testing.expect(!device.is_muted());
    try testing.expectEqual(mantra.Direction.capture, device.id.direction);
}
