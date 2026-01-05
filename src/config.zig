const std = @import("std");

const nimble = @import("nimble");

const keycode = nimble.keycode;

pub const ConfigError = error{
    BufferTooSmall,
    InvalidKey,
    InvalidPath,
    InvalidSequence,
    ParseError,
    SequenceTooLong,
};

pub const KeySequence = struct {
    pub const len_max: u32 = 32;

    const key_name_len_max: u32 = 32;
    const output_len_max: u32 = 256;
    const iteration_max: u32 = 64;

    data: [len_max]u8 = [_]u8{0} ** len_max,
    len: u32 = 0,

    pub fn init(source: []const u8) ConfigError!KeySequence {
        if (source.len == 0) {
            return ConfigError.InvalidSequence;
        }

        if (source.len > len_max) {
            return ConfigError.SequenceTooLong;
        }

        const length: u32 = @intCast(source.len);

        std.debug.assert(length > 0);
        std.debug.assert(length <= len_max);

        var result = KeySequence{};
        var index: u32 = 0;

        while (index < length) : (index += 1) {
            std.debug.assert(index < len_max);
            std.debug.assert(index < length);

            result.data[index] = to_virtual_key(source[index]);
        }

        result.len = length;

        std.debug.assert(result.len == length);
        std.debug.assert(result.len > 0);
        std.debug.assert(result.len <= len_max);

        return result;
    }

    pub fn from_key_name(input: []const u8) ConfigError!KeySequence {
        if (input.len == 0) {
            return ConfigError.InvalidSequence;
        }

        std.debug.assert(input.len <= output_len_max);

        var result = KeySequence{};
        var index: u32 = 0;

        var iterator = std.mem.splitScalar(u8, input, '+');
        var iteration: u32 = 0;

        while (iteration < iteration_max) : (iteration += 1) {
            std.debug.assert(iteration < iteration_max);

            const part = iterator.next() orelse break;

            if (index >= len_max) {
                return ConfigError.SequenceTooLong;
            }

            std.debug.assert(index < len_max);

            const trimmed = std.mem.trim(u8, part, " ");

            if (trimmed.len == 0) {
                continue;
            }

            var lower: [key_name_len_max]u8 = undefined;
            const len: u32 = @intCast(@min(trimmed.len, key_name_len_max));

            std.debug.assert(len <= key_name_len_max);

            var char_index: u32 = 0;
            while (char_index < len) : (char_index += 1) {
                std.debug.assert(char_index < key_name_len_max);
                std.debug.assert(char_index < len);

                lower[char_index] = std.ascii.toLower(trimmed[char_index]);
            }

            std.debug.assert(char_index == len);

            const key = keycode.from_string(lower[0..len]) orelse {
                return ConfigError.InvalidKey;
            };

            std.debug.assert(keycode.is_valid(key));

            result.data[index] = key;
            index += 1;
        }

        if (index == 0) {
            return ConfigError.InvalidSequence;
        }

        result.len = index;

        std.debug.assert(result.len > 0);
        std.debug.assert(result.len <= len_max);

        return result;
    }

    fn to_virtual_key(character: u8) u8 {
        if (character >= 'a' and character <= 'z') {
            return character - 32;
        }

        if (character >= 'A' and character <= 'Z') {
            return character;
        }

        if (character >= '0' and character <= '9') {
            return character;
        }

        return character;
    }

    pub fn to_key_name(self: *const KeySequence, allocator: std.mem.Allocator) ![]u8 {
        std.debug.assert(self.len <= len_max);

        var buffer: [output_len_max]u8 = undefined;
        var fixed_buffer_stream = std.io.fixedBufferStream(&buffer);
        const writer = fixed_buffer_stream.writer();

        var index: u32 = 0;
        while (index < self.len) : (index += 1) {
            std.debug.assert(index < len_max);
            std.debug.assert(index < self.len);

            if (index > 0) {
                try writer.writeAll("+");
            }

            const value: u8 = self.data[index];

            std.debug.assert(keycode.is_valid(value));

            if (keycode.to_string(value)) |name| {
                try writer.writeAll(name);
            } else {
                if (value >= 'A' and value <= 'Z') {
                    try writer.writeByte(value);
                    continue;
                }

                if (value >= '0' and value <= '9') {
                    try writer.writeByte(value);
                    continue;
                }

                try writer.print("0x{X:0>2}", .{value});
            }
        }

        std.debug.assert(index == self.len);

        const written = fixed_buffer_stream.getWritten();

        std.debug.assert(written.len <= output_len_max);

        return try allocator.dupe(u8, written);
    }

    pub fn to_slice(self: *const KeySequence) []const u8 {
        std.debug.assert(self.len <= len_max);

        return self.data[0..self.len];
    }
};

const ZonDevice = struct {
    hotkey: ?[]const u8 = null,
    name: ?[]const u8 = null,
    volume: f32 = 0.5,
};

const ZonConfig = struct {
    capture: ZonDevice = .{},
    render: ZonDevice = .{},
};

pub const DeviceConfig = struct {
    pub const name_len_max: u32 = 256;

    hotkey: KeySequence = undefined,
    name: [name_len_max]u8 = [_]u8{0} ** name_len_max,
    name_len: u32 = 0,
    volume: f32 = 0.5,

    pub fn get_hotkey(self: *const DeviceConfig) []const u8 {
        std.debug.assert(self.hotkey.len <= KeySequence.len_max);

        return self.hotkey.to_slice();
    }

    pub fn get_name(self: *const DeviceConfig) ?[]const u8 {
        std.debug.assert(self.name_len <= name_len_max);

        if (self.name_len == 0) {
            return null;
        }

        return self.name[0..self.name_len];
    }

    pub fn set_name(self: *DeviceConfig, name: []const u8) void {
        std.debug.assert(name.len <= name_len_max);

        const length: u32 = @intCast(@min(name.len, name_len_max));

        @memcpy(self.name[0..length], name[0..length]);
        self.name_len = length;

        std.debug.assert(self.name_len == length);
        std.debug.assert(self.name_len <= name_len_max);
    }
};

pub const Config = struct {
    pub const content_len_max: u32 = 1024 * 64;
    pub const path_len_max: u32 = 512;
    pub const path_max: u32 = path_len_max;

    const write_buffer_len_max: u32 = 4096;

    allocator: std.mem.Allocator,
    capture: DeviceConfig = .{
        .hotkey = default_hotkey(),
        .volume = 0.7,
    },
    config_path: [path_len_max]u8 = [_]u8{0} ** path_len_max,
    config_path_len: u32 = 0,
    is_loaded_from_file: bool = false,
    render: DeviceConfig = .{
        .hotkey = default_hotkey(),
        .volume = 0.2,
    },

    fn default_hotkey() KeySequence {
        var sequence = KeySequence{};
        sequence.data[0] = keycode.prior;
        sequence.data[1] = keycode.next;
        sequence.len = 2;

        return sequence;
    }

    pub fn init(allocator: std.mem.Allocator) Config {
        return Config{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Config) void {
        std.debug.assert(self.config_path_len <= path_len_max);
        self.config_path_len = 0;
    }

    fn ensure_directory_exists(path: []const u8) !void {
        std.debug.assert(path.len > 0);
        std.debug.assert(path.len <= path_len_max);

        const directory = std.fs.path.dirname(path) orelse return error.InvalidPath;

        std.fs.makeDirAbsolute(directory) catch |err| {
            if (err != error.PathAlreadyExists) {
                return err;
            }
        };
    }

    fn load_config_path(self: *Config, app_name: []const u8) !void {
        std.debug.assert(app_name.len > 0);

        const directory = try std.fs.getAppDataDir(self.allocator, app_name);
        defer self.allocator.free(directory);

        std.debug.assert(directory.len > 0);

        const path = try std.fs.path.join(self.allocator, &[_][]const u8{ directory, "config.zon" });
        defer self.allocator.free(path);

        std.debug.assert(path.len > 0);

        const length: u32 = @intCast(path.len);

        if (length > path_len_max) {
            return ConfigError.InvalidPath;
        }

        std.debug.assert(length <= path_len_max);

        @memcpy(self.config_path[0..length], path);
        self.config_path_len = length;

        std.debug.assert(self.config_path_len > 0);
        std.debug.assert(self.config_path_len <= path_len_max);
    }

    fn load_from_file(self: *Config) !void {
        std.debug.assert(self.config_path_len > 0);
        std.debug.assert(self.config_path_len <= path_len_max);

        const path = self.config_path[0..self.config_path_len];

        const file = std.fs.openFileAbsolute(path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                self.is_loaded_from_file = true;
                try self.save();
                return;
            }

            return err;
        };
        defer file.close();

        var buffer: [content_len_max]u8 = undefined;

        const count = file.readAll(&buffer) catch {
            return ConfigError.ParseError;
        };

        if (count == 0) {
            return ConfigError.ParseError;
        }

        std.debug.assert(count > 0);
        std.debug.assert(count <= content_len_max);

        buffer[count] = 0;
        const slice: [:0]const u8 = buffer[0..count :0];

        try self.parse(slice);
        self.is_loaded_from_file = true;
    }

    fn parse_device(device: ZonDevice, volume_default: f32) DeviceConfig {
        std.debug.assert(volume_default >= 0.0);
        std.debug.assert(volume_default <= 1.0);

        var result = DeviceConfig{
            .volume = std.math.clamp(device.volume, 0.0, 1.0),
            .hotkey = default_hotkey(),
        };

        if (result.volume == 0.5) {
            result.volume = volume_default;
        }

        std.debug.assert(result.volume >= 0.0);
        std.debug.assert(result.volume <= 1.0);

        if (device.name) |name| {
            std.debug.assert(name.len <= DeviceConfig.name_len_max);
            result.set_name(name);
        }

        if (device.hotkey) |hotkey| {
            result.hotkey = KeySequence.from_key_name(hotkey) catch result.hotkey;
        }

        return result;
    }

    fn to_zon_config(self: *Config) !ZonConfig {
        std.debug.assert(self.config_path_len <= path_len_max);

        const capture_hotkey = try self.capture.hotkey.to_key_name(self.allocator);
        errdefer self.allocator.free(capture_hotkey);

        const render_hotkey = try self.render.hotkey.to_key_name(self.allocator);

        return .{
            .capture = .{
                .hotkey = capture_hotkey,
                .name = self.capture.get_name(),
                .volume = self.capture.volume,
            },
            .render = .{
                .hotkey = render_hotkey,
                .name = self.render.get_name(),
                .volume = self.render.volume,
            },
        };
    }

    fn write_config_file(self: *Config, path: []const u8) !void {
        std.debug.assert(path.len > 0);
        std.debug.assert(path.len <= path_len_max);

        const file = try std.fs.createFileAbsolute(path, .{});
        defer file.close();

        var allocating: std.Io.Writer.Allocating = .init(self.allocator);
        defer allocating.deinit();

        const zon = try self.to_zon_config();

        defer self.allocator.free(zon.capture.hotkey.?);
        defer self.allocator.free(zon.render.hotkey.?);

        try std.zon.stringify.serialize(zon, .{}, &allocating.writer);

        var buffer: [write_buffer_len_max]u8 = undefined;
        var writer: std.fs.File.Writer = .init(file, &buffer);

        try writer.interface.writeAll(allocating.writer.buffered());
        try writer.interface.flush();
    }

    pub fn get_config_path(self: *const Config) ?[]const u8 {
        std.debug.assert(self.config_path_len <= path_len_max);

        if (self.config_path_len == 0) {
            return null;
        }

        return self.config_path[0..self.config_path_len];
    }

    pub fn load(allocator: std.mem.Allocator, app_name: []const u8) !Config {
        std.debug.assert(app_name.len > 0);

        var config = Config.init(allocator);
        errdefer config.deinit();

        try config.load_config_path(app_name);
        try config.load_from_file();

        std.debug.assert(config.config_path_len > 0);
        std.debug.assert(config.capture.volume >= 0.0);
        std.debug.assert(config.capture.volume <= 1.0);
        std.debug.assert(config.render.volume >= 0.0);
        std.debug.assert(config.render.volume <= 1.0);

        return config;
    }

    pub fn parse(self: *Config, content: [:0]const u8) !void {
        std.debug.assert(content.len > 0);
        std.debug.assert(content.len <= content_len_max);

        const parsed = std.zon.parse.fromSlice(
            ZonConfig,
            self.allocator,
            content,
            null,
            .{},
        ) catch {
            return ConfigError.ParseError;
        };

        self.capture = parse_device(parsed.capture, 0.7);
        self.render = parse_device(parsed.render, 0.2);

        std.debug.assert(self.capture.volume >= 0.0);
        std.debug.assert(self.capture.volume <= 1.0);
        std.debug.assert(self.render.volume >= 0.0);
        std.debug.assert(self.render.volume <= 1.0);
    }

    pub fn save(self: *Config) !void {
        std.debug.assert(self.config_path_len <= path_len_max);

        if (!self.is_loaded_from_file) {
            return;
        }

        std.debug.assert(self.config_path_len > 0);
        std.debug.assert(self.config_path_len <= path_len_max);

        const path = self.config_path[0..self.config_path_len];

        std.debug.assert(path.len > 0);

        try ensure_directory_exists(path);
        try self.write_config_file(path);
    }
};

const testing = std.testing;

test "KeySequence.init valid" {
    const sequence = try KeySequence.init("ABC");

    try testing.expectEqual(@as(u32, 3), sequence.len);
    try testing.expectEqualStrings("ABC", sequence.to_slice());
}

test "KeySequence.init lowercase converts" {
    const sequence = try KeySequence.init("abc");

    try testing.expectEqualStrings("ABC", sequence.to_slice());
}

test "KeySequence.init empty fails" {
    try testing.expectError(ConfigError.InvalidSequence, KeySequence.init(""));
}

test "KeySequence.to_key_name" {
    var sequence = KeySequence{};
    sequence.data[0] = keycode.prior;
    sequence.data[1] = keycode.next;
    sequence.len = 2;

    const name = try sequence.to_key_name(testing.allocator);
    defer testing.allocator.free(name);

    try testing.expectEqualStrings("PageUp+PageDown", name);
}

test "KeySequence.from_key_name" {
    const sequence = try KeySequence.from_key_name("PageUp+PageDown");

    try testing.expectEqual(@as(u32, 2), sequence.len);
    try testing.expectEqual(keycode.prior, sequence.data[0]);
    try testing.expectEqual(keycode.next, sequence.data[1]);
}

test "DeviceConfig.get_name empty" {
    const device_config = DeviceConfig{};

    try testing.expect(device_config.get_name() == null);
}

test "DeviceConfig.set_name and get_name" {
    var device_config = DeviceConfig{};

    device_config.set_name("Microphone");

    try testing.expectEqualStrings("Microphone", device_config.get_name().?);
}
