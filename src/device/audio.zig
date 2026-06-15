const std = @import("std");

const wca = @import("wca");

const Device = @import("device.zig").Device;
const MuteError = @import("../error.zig").MuteError;

pub const AudioManager = struct {
    const devices_max: u32 = 256;
    const search_score_max: u32 = 20;
    const name_len_max: u32 = 256;

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) AudioManager {
        return AudioManager{
            .allocator = allocator,
        };
    }

    pub fn find(self: *AudioManager, name: []const u8, dataflow: wca.EDataFlow) !Device {
        std.debug.assert(name.len > 0);
        std.debug.assert(name.len <= name_len_max);

        const enumerator = try wca.IMMDeviceEnumerator.create();
        defer _ = enumerator.release();

        const collection = try enumerator.enumAudioEndpoints(dataflow, wca.types.DeviceState.Active);
        defer _ = collection.release();

        const raw_count = try collection.getCount();
        const count: u32 = @min(raw_count, devices_max);

        std.debug.assert(count <= devices_max);

        var target_device: ?*wca.IMMDevice = null;
        var target_volume: ?*wca.IAudioEndpointVolume = null;
        var best_score: u32 = search_score_max;

        var index: u32 = 0;

        while (index < count) : (index += 1) {
            std.debug.assert(index < devices_max);
            std.debug.assert(index < count);

            const search_result = self.search_device(collection, index, name, best_score);

            if (search_result.device) |new_device| {
                if (search_result.volume) |new_volume| {
                    if (target_device) |old_device| {
                        if (target_volume) |old_volume| {
                            _ = old_volume.release();
                        }
                        _ = old_device.release();
                    }

                    target_device = new_device;
                    target_volume = new_volume;
                    best_score = search_result.score;

                    std.debug.assert(best_score < search_score_max);
                }
            }
        }

        std.debug.assert(index == count);

        if (target_device) |device| {
            if (target_volume) |volume| {
                return Device.init(device, volume, dataflow, self.allocator);
            }
        }

        return MuteError.DeviceNotFound;
    }

    const SearchResult = struct {
        device: ?*wca.IMMDevice = null,
        volume: ?*wca.IAudioEndpointVolume = null,
        score: u32 = search_score_max,
    };

    fn search_device(
        self: *AudioManager,
        collection: anytype,
        index: u32,
        name: []const u8,
        best_score: u32,
    ) SearchResult {
        std.debug.assert(index < devices_max);
        std.debug.assert(name.len > 0);
        std.debug.assert(name.len <= name_len_max);
        std.debug.assert(best_score <= search_score_max);

        const device = collection.item(index) catch return .{};

        const store = device.openPropertyStore(wca.constants.StorageMode.Read) catch {
            _ = device.release();
            return .{};
        };
        defer _ = store.release();

        const device_name = store.getStringValue(
            &wca.property.PKEY_Device_FriendlyName,
            self.allocator,
        ) catch {
            _ = device.release();
            return .{};
        } orelse {
            _ = device.release();
            return .{};
        };
        defer self.allocator.free(device_name);

        if (device_name.len == 0) {
            _ = device.release();
            return .{};
        }

        std.debug.assert(device_name.len > 0);

        const distance = levenshtein_distance(device_name, name);
        const distance_u32: u32 = @min(distance, search_score_max);

        if (distance_u32 >= best_score) {
            _ = device.release();
            return .{};
        }

        const volume = device.activateEndpointVolume() catch {
            _ = device.release();
            return .{};
        };

        std.debug.assert(distance_u32 < best_score);

        return .{
            .device = device,
            .volume = volume,
            .score = distance_u32,
        };
    }

    pub fn get_default(self: *AudioManager, dataflow: wca.EDataFlow, role: wca.ERole) !Device {
        const enumerator = try wca.IMMDeviceEnumerator.create();
        defer _ = enumerator.release();

        const device = try enumerator.getDefaultAudioEndpoint(dataflow, role);
        errdefer _ = device.release();

        const volume = try device.activateEndpointVolume();

        return Device.init(device, volume, dataflow, self.allocator);
    }
};

fn levenshtein_distance(source: []const u8, target: []const u8) u32 {
    const row_len_max: u32 = AudioManager.name_len_max + 1;

    std.debug.assert(source.len <= AudioManager.name_len_max);
    std.debug.assert(target.len <= AudioManager.name_len_max);

    if (source.len == 0) {
        return @intCast(target.len);
    }

    if (target.len == 0) {
        return @intCast(source.len);
    }

    const short = if (source.len <= target.len) source else target;
    const long = if (source.len <= target.len) target else source;

    const col: u32 = @intCast(short.len + 1);
    const row_count: u32 = @intCast(long.len);

    std.debug.assert(col > 0);
    std.debug.assert(col <= row_len_max);
    std.debug.assert(row_count > 0);

    var prev_row: [row_len_max]u32 = undefined;
    var curr_row: [row_len_max]u32 = undefined;

    var init_idx: u32 = 0;

    while (init_idx < col) : (init_idx += 1) {
        std.debug.assert(init_idx < row_len_max);

        prev_row[init_idx] = init_idx;
    }

    std.debug.assert(init_idx == col);

    var row_idx: u32 = 1;

    while (row_idx <= row_count) : (row_idx += 1) {
        std.debug.assert(row_idx > 0);
        std.debug.assert(row_idx <= row_count);
        std.debug.assert(row_idx - 1 < long.len);

        curr_row[0] = row_idx;

        var col_idx: u32 = 1;

        while (col_idx < col) : (col_idx += 1) {
            std.debug.assert(col_idx > 0);
            std.debug.assert(col_idx < col);
            std.debug.assert(col_idx < row_len_max);
            std.debug.assert(col_idx - 1 < short.len);

            const cost: u32 = if (long[row_idx - 1] == short[col_idx - 1]) 0 else 1;

            const deletion = prev_row[col_idx] + 1;
            const insertion = curr_row[col_idx - 1] + 1;
            const substitution = prev_row[col_idx - 1] + cost;

            curr_row[col_idx] = @min(@min(deletion, insertion), substitution);
        }

        std.debug.assert(col_idx == col);

        var copy_idx: u32 = 0;

        while (copy_idx < col) : (copy_idx += 1) {
            std.debug.assert(copy_idx < row_len_max);

            prev_row[copy_idx] = curr_row[copy_idx];
        }
    }

    std.debug.assert(row_idx == row_count + 1);

    const result = prev_row[col - 1];

    std.debug.assert(result <= @max(source.len, target.len));

    return result;
}
