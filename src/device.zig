const std = @import("std");
const wca = @import("wca");

const MuteError = @import("error.zig").MuteError;

pub const Device = struct {
    const role_count: u32 = 3;

    allocator: std.mem.Allocator,
    data_flow: wca.EDataFlow,
    device: *wca.IMMDevice,
    volume: *wca.IAudioEndpointVolume,

    pub fn init(
        device: *wca.IMMDevice,
        volume: *wca.IAudioEndpointVolume,
        data_flow: wca.EDataFlow,
        allocator: std.mem.Allocator,
    ) Device {
        return Device{
            .allocator = allocator,
            .data_flow = data_flow,
            .device = device,
            .volume = volume,
        };
    }

    pub fn deinit(self: *Device) void {
        _ = self.volume.release();
        _ = self.device.release();
    }

    pub fn getId(self: *Device) ![]u8 {
        const result = try self.device.getId(self.allocator);

        std.debug.assert(result.len > 0);

        return result;
    }

    pub fn getName(self: *Device) ![]u8 {
        const store = try self.device.openPropertyStore(wca.constants.StorageMode.Read);
        defer _ = store.release();

        if (try store.getStringValue(&wca.property.PKEY_Device_FriendlyName, self.allocator)) |name| {
            std.debug.assert(name.len > 0);
            return name;
        }

        return MuteError.DeviceNotFound;
    }

    pub fn getVolume(self: *Device) f32 {
        const result = self.volume.getMasterVolumeLevelScalar() catch 0.0;

        std.debug.assert(result >= 0.0);
        std.debug.assert(result <= 1.0);

        return result;
    }

    pub fn isAllDefault(self: *Device) !bool {
        const roles = [_]wca.ERole{ .Console, .Multimedia, .Communications };

        var i: u32 = 0;

        while (i < role_count) : (i += 1) {
            std.debug.assert(i < roles.len);

            if (!try self.isDefault(roles[i])) {
                return false;
            }
        }

        return true;
    }

    pub fn isDefault(self: *Device, role: wca.ERole) !bool {
        const enumerator = try wca.IMMDeviceEnumerator.create();
        defer _ = enumerator.release();

        const default = try enumerator.getDefaultAudioEndpoint(self.data_flow, role);
        defer _ = default.release();

        const device_id = try self.getId();
        defer self.allocator.free(device_id);

        const default_id = try default.getId(self.allocator);
        defer self.allocator.free(default_id);

        std.debug.assert(device_id.len > 0);
        std.debug.assert(default_id.len > 0);

        return std.mem.eql(u8, device_id, default_id);
    }

    pub fn isEnabled(self: *Device) bool {
        const state = self.device.getState() catch return false;

        return state == wca.types.DeviceState.Active;
    }

    pub fn isMuted(self: *Device) bool {
        return self.volume.getMute() catch false;
    }

    pub fn mute(self: *Device) void {
        self.volume.setMute(true, null) catch {};
    }

    pub fn setAsDefault(self: *Device) !void {
        const id = try self.device.getId(self.allocator);
        defer self.allocator.free(id);

        std.debug.assert(id.len > 0);

        const id16 = try std.unicode.utf8ToUtf16LeAllocZ(self.allocator, id);
        defer self.allocator.free(id16);

        std.debug.assert(id16.len > 0);

        const policy = try wca.IPolicyConfigVista.create();
        defer _ = policy.release();

        try policy.setDefaultEndpointAllRoles(id16);
    }

    pub fn setVolume(self: *Device, level: f32) void {
        std.debug.assert(level >= 0.0);
        std.debug.assert(level <= 1.0);

        self.volume.setMasterVolumeLevelScalar(level, null) catch {};
    }

    pub fn toggleMute(self: *Device) bool {
        const current = self.isMuted();

        if (current) {
            self.unmute();
        } else {
            self.mute();
        }

        const result = !current;

        std.debug.assert(result != current);

        return result;
    }

    pub fn unmute(self: *Device) void {
        self.volume.setMute(false, null) catch {};
    }
};
