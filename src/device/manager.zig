const std = @import("std");

const wca = @import("wca");

const AudioManager = @import("audio.zig").AudioManager;
const Config = @import("../config.zig").Config;
const DeviceConfig = @import("../config.zig").DeviceConfig;
const Device = @import("device.zig").Device;
const Mode = @import("../mode.zig").Mode;

pub const DeviceInfo = struct {
    const id_len_max: u32 = 256;
    const name_len_max: u32 = 256;

    id: [id_len_max]u8 = [_]u8{0} ** id_len_max,
    id_len: u32 = 0,
    name: [name_len_max]u8 = [_]u8{0} ** name_len_max,
    name_len: u32 = 0,

    pub fn get_id_slice(self: *const DeviceInfo) []const u8 {
        std.debug.assert(self.id_len <= id_len_max);

        return self.id[0..self.id_len];
    }

    pub fn get_name_slice(self: *const DeviceInfo) []const u8 {
        std.debug.assert(self.name_len <= name_len_max);

        return self.name[0..self.name_len];
    }
};

pub fn DeviceManager(comptime mode: Mode) type {
    return struct {
        const Self = @This();
        const devices_max: u32 = 32;

        allocator: std.mem.Allocator,
        audio: AudioManager,
        count: u32 = 0,
        current: ?Device = null,
        index: u32 = 0,
        list: [devices_max]DeviceInfo = undefined,

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .allocator = allocator,
                .audio = AudioManager.init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            std.debug.assert(self.count <= devices_max);

            if (self.current) |*device| {
                device.deinit();
            }

            self.current = null;
        }

        pub fn enumerate(self: *Self) void {
            std.debug.assert(self.count <= devices_max);

            self.count = 0;

            const enumerator = wca.IMMDeviceEnumerator.create() catch return;
            defer _ = enumerator.release();

            const collection = enumerator.enumAudioEndpoints(
                mode.to_data_flow(),
                wca.types.DeviceState.Active,
            ) catch return;
            defer _ = collection.release();

            const raw_count = collection.getCount() catch return;
            const bounded_count = @min(raw_count, devices_max);

            var index: u32 = 0;

            while (index < bounded_count) : (index += 1) {
                std.debug.assert(index < devices_max);

                const device = collection.item(index) catch continue;
                defer _ = device.release();

                self.add_device_info(device, index);
            }

            std.debug.assert(index <= devices_max);
        }

        fn add_device_info(self: *Self, device: *wca.IMMDevice, index: u32) void {
            std.debug.assert(index < devices_max);

            const id = device.getId(self.allocator) catch return;
            defer self.allocator.free(id);

            const store = device.openPropertyStore(wca.constants.StorageMode.Read) catch return;
            defer _ = store.release();

            const name = store.getStringValue(
                &wca.property.PKEY_Device_FriendlyName,
                self.allocator,
            ) catch return;

            if (name) |n| {
                defer self.allocator.free(n);

                const id_len: u32 = @intCast(@min(id.len, DeviceInfo.id_len_max));
                const name_len: u32 = @intCast(@min(n.len, DeviceInfo.name_len_max));

                @memcpy(self.list[index].id[0..id_len], id[0..id_len]);
                self.list[index].id_len = id_len;

                @memcpy(self.list[index].name[0..name_len], n[0..name_len]);
                self.list[index].name_len = name_len;

                self.count += 1;
            }
        }

        pub fn find(self: *Self, device_config: *DeviceConfig) ?Device {
            std.debug.assert(self.count <= devices_max);

            if (device_config.get_name()) |name| {
                return self.audio.find(name, mode.to_data_flow()) catch null;
            }

            return self.audio.get_default(mode.to_data_flow(), .Multimedia) catch null;
        }

        pub fn update_index(self: *Self) void {
            std.debug.assert(self.count <= devices_max);

            if (self.current) |*device| {
                const id = device.get_id() catch return;
                defer self.allocator.free(id);

                var i: u32 = 0;

                while (i < self.count) : (i += 1) {
                    std.debug.assert(i < devices_max);

                    if (std.mem.eql(u8, id, self.list[i].get_id_slice())) {
                        self.index = i;
                        return;
                    }
                }
            }
        }

        pub fn save_default(self: *Self) !void {
            std.debug.assert(self.count <= devices_max);

            if (self.current) |*device| {
                try device.set_as_default();
            }
        }

        pub fn get_current_info(self: *Self) ?*DeviceInfo {
            std.debug.assert(self.count <= devices_max);

            if (self.count > 0 and self.index < self.count) {
                std.debug.assert(self.index < devices_max);
                return &self.list[self.index];
            }

            return null;
        }

        pub fn restore_default(self: *Self) !void {
            std.debug.assert(self.count <= devices_max);

            if (self.current) |*device| {
                const is_default = device.is_all_default() catch false;

                if (!is_default) {
                    try device.set_as_default();
                }
            }
        }

        pub fn next(self: *Self) void {
            std.debug.assert(self.count <= devices_max);

            if (self.count == 0) {
                return;
            }

            const new_index = if (self.index + 1 >= self.count) 0 else self.index + 1;

            self.select_by_index(new_index);
        }

        pub fn previous(self: *Self) void {
            std.debug.assert(self.count <= devices_max);

            if (self.count == 0) {
                return;
            }

            const new_index = if (self.index == 0) self.count - 1 else self.index - 1;

            self.select_by_index(new_index);
        }

        fn select_by_index(self: *Self, new_index: u32) void {
            std.debug.assert(self.count <= devices_max);
            std.debug.assert(new_index < self.count);

            if (new_index >= self.count) {
                return;
            }

            const info = &self.list[new_index];
            const name = info.get_name_slice();

            if (name.len == 0) {
                return;
            }

            const new_device = self.audio.find(name, mode.to_data_flow()) catch return;

            if (self.current) |*old_device| {
                old_device.deinit();
            }

            self.current = new_device;
            self.index = new_index;
        }

        pub fn handle_added(self: *Self, device_config: *DeviceConfig) bool {
            std.debug.assert(self.count <= devices_max);

            if (self.current != null) {
                return false;
            }

            self.current = self.find(device_config);

            if (self.current != null) {
                self.update_index();
                return true;
            }

            return false;
        }

        pub fn handle_removed(self: *Self, device_config: *DeviceConfig) bool {
            std.debug.assert(self.count <= devices_max);

            if (self.current) |*device| {
                const id = device.get_id() catch return false;
                defer self.allocator.free(id);

                std.debug.assert(id.len > 0);

                var current = self.find(device_config) orelse {
                    device.deinit();
                    self.current = null;
                    return true;
                };

                const current_id = current.get_id() catch {
                    current.deinit();
                    return false;
                };
                defer self.allocator.free(current_id);

                std.debug.assert(current_id.len > 0);

                if (!std.mem.eql(u8, id, current_id)) {
                    device.deinit();
                    self.current = null;
                    current.deinit();
                    return true;
                }

                current.deinit();
            }

            return false;
        }
    };
}
