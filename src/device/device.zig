const std = @import("std");

const wca = @import("wca");

const MuteError = @import("../error.zig").MuteError;

pub const Device = struct {
    const role_count: u32 = 3;
    const id_len_max: u32 = 512;
    const name_len_max: u32 = 256;

    allocator: std.mem.Allocator,
    data_flow: wca.EDataFlow,
    device: *wca.IMMDevice,
    volume: *wca.IAudioEndpointVolume,

    pub fn init(
        device: *wca.IMMDevice,
        volume_endpoint: *wca.IAudioEndpointVolume,
        data_flow: wca.EDataFlow,
        allocator: std.mem.Allocator,
    ) Device {
        return Device{
            .allocator = allocator,
            .data_flow = data_flow,
            .device = device,
            .volume = volume_endpoint,
        };
    }

    pub fn deinit(self: *Device) void {
        _ = self.volume.release();
        _ = self.device.release();
    }

    pub fn get_id(self: *Device) ![]u8 {
        const result = try self.device.getId(self.allocator);

        std.debug.assert(result.len > 0);
        std.debug.assert(result.len <= id_len_max);

        return result;
    }

    pub fn get_name(self: *Device) ![]u8 {
        const store = try self.device.openPropertyStore(wca.constants.StorageMode.Read);
        defer _ = store.release();

        const name = try store.getStringValue(
            &wca.property.PKEY_Device_FriendlyName,
            self.allocator,
        );

        if (name) |result| {
            std.debug.assert(result.len > 0);
            std.debug.assert(result.len <= name_len_max);
            return result;
        }

        return MuteError.DeviceNotFound;
    }

    pub fn get_volume(self: *Device) f32 {
        const result = self.volume.getMasterVolumeLevelScalar() catch 0.0;

        std.debug.assert(result >= 0.0);
        std.debug.assert(result <= 1.0);

        return result;
    }

    pub fn is_all_default(self: *Device) !bool {
        const roles = [_]wca.ERole{ .Console, .Multimedia, .Communications };

        var index: u32 = 0;
        while (index < role_count) : (index += 1) {
            std.debug.assert(index < roles.len);
            std.debug.assert(index < role_count);

            if (!try self.is_default(roles[index])) {
                return false;
            }
        }

        std.debug.assert(index == role_count);

        return true;
    }

    pub fn is_default(self: *Device, role: wca.ERole) !bool {
        const enumerator = try wca.IMMDeviceEnumerator.create();
        defer _ = enumerator.release();

        const default = try enumerator.getDefaultAudioEndpoint(self.data_flow, role);
        defer _ = default.release();

        const device_id = try self.get_id();
        defer self.allocator.free(device_id);

        const default_id = try default.getId(self.allocator);
        defer self.allocator.free(default_id);

        std.debug.assert(device_id.len > 0);
        std.debug.assert(default_id.len > 0);

        return std.mem.eql(u8, device_id, default_id);
    }

    pub fn is_enabled(self: *Device) bool {
        const state = self.device.getState() catch return false;

        return state == wca.types.DeviceState.Active;
    }

    pub fn is_muted(self: *Device) bool {
        return self.volume.getMute() catch false;
    }

    pub fn mute(self: *Device) void {
        self.volume.setMute(true, null) catch {};
    }

    pub fn set_as_default(self: *Device) !void {
        const id = try self.device.getId(self.allocator);
        defer self.allocator.free(id);

        std.debug.assert(id.len > 0);
        std.debug.assert(id.len <= id_len_max);

        const id16 = try std.unicode.utf8ToUtf16LeAllocZ(self.allocator, id);
        defer self.allocator.free(id16);

        std.debug.assert(id16.len > 0);

        const policy = try wca.IPolicyConfigVista.create();
        defer _ = policy.release();

        try policy.setDefaultEndpointAllRoles(id16);
    }

    pub fn set_volume(self: *Device, level: f32) void {
        std.debug.assert(level >= 0.0);
        std.debug.assert(level <= 1.0);

        self.volume.setMasterVolumeLevelScalar(level, null) catch {};
    }

    pub fn toggle_mute(self: *Device) bool {
        const current = self.is_muted();

        if (current) {
            self.unmute();
        } else {
            self.mute();
        }

        return !current;
    }

    pub fn unmute(self: *Device) void {
        self.volume.setMute(false, null) catch {};
    }
};
