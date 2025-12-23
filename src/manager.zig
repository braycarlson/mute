const std = @import("std");
const wca = @import("wca");

const Device = @import("device.zig").Device;
const MuteError = @import("error.zig").MuteError;

pub const AudioManager = struct {
    const max_devices: u32 = 256;
    const max_search_score: usize = 20;

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) AudioManager {
        return AudioManager{
            .allocator = allocator,
        };
    }

    pub fn find(self: *AudioManager, name: []const u8, dataflow: wca.EDataFlow) !Device {
        std.debug.assert(name.len > 0);

        const enumerator = try wca.IMMDeviceEnumerator.create();
        defer _ = enumerator.release();

        const collection = try enumerator.enumAudioEndpoints(dataflow, wca.types.DeviceState.Active);
        defer _ = collection.release();

        const count = try collection.getCount();

        std.debug.assert(count <= max_devices);

        var target_device: ?*wca.IMMDevice = null;
        var target_volume: ?*wca.IAudioEndpointVolume = null;
        var best_score: usize = max_search_score;

        var i: u32 = 0;

        while (i < count) : (i += 1) {
            std.debug.assert(i < max_devices);

            const device = try collection.item(i);
            errdefer _ = device.release();

            const store = try device.openPropertyStore(wca.constants.StorageMode.Read);
            defer _ = store.release();

            const device_name = try store.getStringValue(
                &wca.property.PKEY_Device_FriendlyName,
                self.allocator,
            ) orelse {
                _ = device.release();
                continue;
            };

            defer self.allocator.free(device_name);

            std.debug.assert(device_name.len > 0);

            const distance = levenshteinDistance(self.allocator, device_name, name) catch {
                _ = device.release();
                continue;
            };

            if (distance < best_score) {
                if (target_device) |old_device| {
                    if (target_volume) |old_volume| {
                        _ = old_volume.release();
                    }

                    _ = old_device.release();
                }

                best_score = distance;
                target_device = device;

                target_volume = device.activateEndpointVolume() catch {
                    target_device = null;
                    _ = device.release();

                    continue;
                };
            } else {
                _ = device.release();
            }
        }

        if (target_device) |device| {
            if (target_volume) |volume| {
                return Device.init(device, volume, dataflow, self.allocator);
            }
        }

        return MuteError.DeviceNotFound;
    }

    pub fn getDefault(self: *AudioManager, dataflow: wca.EDataFlow, role: wca.ERole) !Device {
        const enumerator = try wca.IMMDeviceEnumerator.create();
        defer _ = enumerator.release();

        const device = try enumerator.getDefaultAudioEndpoint(dataflow, role);
        errdefer _ = device.release();

        const volume = try device.activateEndpointVolume();

        return Device.init(device, volume, dataflow, self.allocator);
    }
};

fn levenshteinDistance(allocator: std.mem.Allocator, a: []const u8, b: []const u8) !usize {
    if (a.len == 0) return b.len;
    if (b.len == 0) return a.len;

    const row = a.len + 1;
    const col = b.len + 1;

    std.debug.assert(row > 0);
    std.debug.assert(col > 0);

    var matrix = try allocator.alloc(usize, row * col);
    defer allocator.free(matrix);

    std.debug.assert(matrix.len == row * col);

    var i: usize = 0;

    while (i < row) : (i += 1) {
        std.debug.assert(i * col < matrix.len);
        matrix[i * col] = i;
    }

    var j: usize = 0;

    while (j < col) : (j += 1) {
        std.debug.assert(j < matrix.len);
        matrix[j] = j;
    }

    i = 1;

    while (i < row) : (i += 1) {
        j = 1;

        while (j < col) : (j += 1) {
            std.debug.assert(i > 0);
            std.debug.assert(j > 0);
            std.debug.assert(i - 1 < a.len);
            std.debug.assert(j - 1 < b.len);

            const cost: usize = if (a[i - 1] == b[j - 1]) 0 else 1;

            const deletion = matrix[(i - 1) * col + j] + 1;
            const insertion = matrix[i * col + (j - 1)] + 1;
            const substitution = matrix[(i - 1) * col + (j - 1)] + cost;

            matrix[i * col + j] = @min(@min(deletion, insertion), substitution);
        }
    }

    const result = matrix[(row - 1) * col + (col - 1)];

    std.debug.assert(result <= @max(a.len, b.len));

    return result;
}
