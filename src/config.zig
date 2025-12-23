const std = @import("std");

const toolkit = @import("toolkit");

pub const ConfigError = error{
    BufferTooSmall,
    InvalidKey,
    InvalidPath,
    InvalidSequence,
    ParseError,
    SequenceTooLong,
};

pub const KeySequence = struct {
    pub const max: u32 = 32;

    data: [max]u8 = [_]u8{0} ** max,
    len: u32 = 0,

    pub fn init(source: []const u8) ConfigError!KeySequence {
        const length: u32 = @intCast(source.len);

        if (length == 0) {
            return ConfigError.InvalidSequence;
        }

        if (length > max) {
            return ConfigError.SequenceTooLong;
        }

        std.debug.assert(length > 0);
        std.debug.assert(length <= max);

        var result = KeySequence{};
        var index: u32 = 0;

        while (index < length) : (index += 1) {
            std.debug.assert(index < max);

            result.data[index] = toVirtualKey(source[index]);
        }

        result.len = length;

        std.debug.assert(result.len == length);
        std.debug.assert(result.len > 0);

        return result;
    }

    pub fn fromKeyName(input: []const u8) ConfigError!KeySequence {
        if (input.len == 0) {
            return ConfigError.InvalidSequence;
        }

        var result = KeySequence{};
        var index: u32 = 0;

        var iterator = std.mem.splitScalar(u8, input, '+');
        var iteration: u32 = 0;
        const max_iteration: u32 = 64;

        while (iterator.next()) |part| {
            if (iteration >= max_iteration) {
                break;
            }

            iteration += 1;

            if (index >= max) {
                return ConfigError.SequenceTooLong;
            }

            const trimmed = std.mem.trim(u8, part, " ");

            if (trimmed.len == 0) {
                continue;
            }

            var lower: [32]u8 = undefined;
            const len = @min(trimmed.len, lower.len);

            std.debug.assert(len <= 32);

            var i: u32 = 0;

            while (i < len) : (i += 1) {
                lower[i] = std.ascii.toLower(trimmed[i]);
            }

            const key = toolkit.input.VirtualKey.fromString(lower[0..len]) orelse {
                return ConfigError.InvalidKey;
            };

            std.debug.assert(key <= 0xFF);

            result.data[index] = @truncate(key);
            index += 1;
        }

        if (index == 0) {
            return ConfigError.InvalidSequence;
        }

        result.len = index;

        std.debug.assert(result.len > 0);
        std.debug.assert(result.len <= max);

        return result;
    }

    fn toVirtualKey(character: u8) u8 {
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

    pub fn toKeyName(self: *const KeySequence, allocator: std.mem.Allocator) ![]const u8 {
        std.debug.assert(self.len <= max);

        var buffer: [256]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buffer);
        const writer = fbs.writer();

        var index: u32 = 0;

        while (index < self.len) : (index += 1) {
            std.debug.assert(index < max);

            if (index > 0) {
                try writer.writeAll("+");
            }

            const code: u32 = self.data[index];

            std.debug.assert(code <= 0xFF);

            if (toolkit.input.VirtualKey.toString(code)) |name| {
                try writer.writeAll(name);
            } else if (code >= 'A' and code <= 'Z') {
                try writer.writeByte(@truncate(code));
            } else if (code >= '0' and code <= '9') {
                try writer.writeByte(@truncate(code));
            } else {
                try writer.print("0x{X:0>2}", .{code});
            }
        }

        const written = fbs.getWritten();

        std.debug.assert(written.len <= 256);

        return try allocator.dupe(u8, written);
    }

    pub fn toSlice(self: *const KeySequence) []const u8 {
        std.debug.assert(self.len <= max);

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
    const name_max: u32 = 256;

    hotkey: KeySequence = undefined,
    name: [name_max]u8 = [_]u8{0} ** name_max,
    name_len: u32 = 0,
    volume: f32 = 0.5,

    pub fn getHotkey(self: *const DeviceConfig) []const u8 {
        return self.hotkey.toSlice();
    }

    pub fn getName(self: *const DeviceConfig) ?[]const u8 {
        if (self.name_len == 0) {
            return null;
        }

        std.debug.assert(self.name_len <= name_max);

        return self.name[0..self.name_len];
    }

    pub fn setName(self: *DeviceConfig, name: []const u8) void {
        std.debug.assert(name.len <= name_max);

        const length: u32 = @intCast(@min(name.len, name_max));

        @memcpy(self.name[0..length], name[0..length]);
        self.name_len = length;

        std.debug.assert(self.name_len == length);
    }
};

pub const Config = struct {
    pub const content_max: u32 = 1024 * 64;
    pub const path_max: u32 = 512;

    allocator: std.mem.Allocator,
    capture: DeviceConfig = .{
        .hotkey = defaultHotkey(),
        .volume = 0.7,
    },
    config_path: [path_max]u8 = [_]u8{0} ** path_max,
    config_path_len: u32 = 0,
    is_loaded_from_file: bool = false,
    render: DeviceConfig = .{
        .hotkey = defaultHotkey(),
        .volume = 0.2,
    },

    fn defaultHotkey() KeySequence {
        var seq = KeySequence{};
        seq.data[0] = toolkit.input.VirtualKey.prior;
        seq.data[1] = toolkit.input.VirtualKey.next;
        seq.len = 2;

        std.debug.assert(seq.len == 2);

        return seq;
    }

    pub fn init(allocator: std.mem.Allocator) Config {
        return Config{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Config) void {
        _ = self;
    }

    fn ensureDirectoryExists(path: []const u8) !void {
        std.debug.assert(path.len > 0);
        std.debug.assert(path.len <= path_max);

        const directory = std.fs.path.dirname(path) orelse return error.InvalidPath;

        std.fs.makeDirAbsolute(directory) catch |err| {
            if (err != error.PathAlreadyExists) {
                return err;
            }
        };
    }

    fn loadConfigPath(self: *Config, app_name: []const u8) !void {
        std.debug.assert(app_name.len > 0);

        const directory = try std.fs.getAppDataDir(self.allocator, app_name);
        defer self.allocator.free(directory);

        std.debug.assert(directory.len > 0);

        const path = try std.fs.path.join(self.allocator, &[_][]const u8{ directory, "config.zon" });
        defer self.allocator.free(path);

        const length: u32 = @intCast(path.len);

        if (length > path_max) {
            return ConfigError.InvalidPath;
        }

        std.debug.assert(length <= path_max);

        @memcpy(self.config_path[0..length], path);
        self.config_path_len = length;

        std.debug.assert(self.config_path_len == length);
        std.debug.assert(self.config_path_len > 0);
    }

    fn loadFromFile(self: *Config) !void {
        std.debug.assert(self.config_path_len > 0);
        std.debug.assert(self.config_path_len <= path_max);

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

        var buffer: [content_max]u8 = undefined;

        const count = file.readAll(&buffer) catch {
            return ConfigError.ParseError;
        };

        if (count == 0) {
            return ConfigError.ParseError;
        }

        std.debug.assert(count > 0);
        std.debug.assert(count <= content_max);

        const slice: [:0]const u8 = buffer[0..count :0];

        try self.parse(slice);
        self.is_loaded_from_file = true;

        std.debug.assert(self.is_loaded_from_file == true);
    }

    fn parseDevice(device: ZonDevice, default_volume: f32) DeviceConfig {
        std.debug.assert(default_volume >= 0.0);
        std.debug.assert(default_volume <= 1.0);

        var result = DeviceConfig{
            .volume = std.math.clamp(device.volume, 0.0, 1.0),
            .hotkey = defaultHotkey(),
        };

        if (result.volume == 0.5) {
            result.volume = default_volume;
        }

        if (device.name) |name| {
            std.debug.assert(name.len <= DeviceConfig.name_max);
            result.setName(name);
        }

        if (device.hotkey) |hotkey| {
            result.hotkey = KeySequence.fromKeyName(hotkey) catch result.hotkey;
        }

        std.debug.assert(result.volume >= 0.0);
        std.debug.assert(result.volume <= 1.0);

        return result;
    }

    fn toZonConfig(self: *Config) !ZonConfig {
        return .{
            .capture = .{
                .hotkey = try self.capture.hotkey.toKeyName(self.allocator),
                .name = self.capture.getName(),
                .volume = self.capture.volume,
            },
            .render = .{
                .hotkey = try self.render.hotkey.toKeyName(self.allocator),
                .name = self.render.getName(),
                .volume = self.render.volume,
            },
        };
    }

    fn writeConfigFile(self: *Config, path: []const u8) !void {
        std.debug.assert(path.len > 0);
        std.debug.assert(path.len <= path_max);

        const file = try std.fs.createFileAbsolute(path, .{});
        defer file.close();

        var allocating: std.Io.Writer.Allocating = .init(self.allocator);
        defer allocating.deinit();

        const zon = try self.toZonConfig();

        defer self.allocator.free(zon.capture.hotkey.?);
        defer self.allocator.free(zon.render.hotkey.?);

        try std.zon.stringify.serialize(zon, .{}, &allocating.writer);

        var buffer: [4096]u8 = undefined;
        var writer: std.fs.File.Writer = .init(file, &buffer);

        try writer.interface.writeAll(allocating.writer.buffered());
        try writer.interface.flush();
    }

    pub fn getConfigPath(self: *Config) ?[]const u8 {
        if (self.config_path_len == 0) {
            return null;
        }

        std.debug.assert(self.config_path_len <= path_max);

        return self.config_path[0..self.config_path_len];
    }

    pub fn load(allocator: std.mem.Allocator, app_name: []const u8) !Config {
        std.debug.assert(app_name.len > 0);

        var cfg = Config.init(allocator);
        errdefer cfg.deinit();

        try cfg.loadConfigPath(app_name);
        try cfg.loadFromFile();

        std.debug.assert(cfg.config_path_len > 0);

        return cfg;
    }

    pub fn parse(self: *Config, content: [:0]const u8) !void {
        std.debug.assert(content.len > 0);
        std.debug.assert(content.len <= content_max);

        const parsed = std.zon.parse.fromSlice(ZonConfig, self.allocator, content, null, .{}) catch {
            return ConfigError.ParseError;
        };

        self.capture = parseDevice(parsed.capture, 0.7);
        self.render = parseDevice(parsed.render, 0.2);

        std.debug.assert(self.capture.volume >= 0.0);
        std.debug.assert(self.capture.volume <= 1.0);
        std.debug.assert(self.render.volume >= 0.0);
        std.debug.assert(self.render.volume <= 1.0);
    }

    pub fn save(self: *Config) !void {
        if (!self.is_loaded_from_file) {
            return;
        }

        std.debug.assert(self.config_path_len > 0);
        std.debug.assert(self.config_path_len <= path_max);

        const path = self.config_path[0..self.config_path_len];

        try ensureDirectoryExists(path);
        try self.writeConfigFile(path);
    }
};

const testing = std.testing;

test "KeySequence.init valid" {
    const seq = try KeySequence.init("ABC");

    try testing.expectEqual(@as(u32, 3), seq.len);
    try testing.expectEqualStrings("ABC", seq.toSlice());
}

test "KeySequence.init lowercase converts" {
    const seq = try KeySequence.init("abc");

    try testing.expectEqualStrings("ABC", seq.toSlice());
}

test "KeySequence.init empty fails" {
    try testing.expectError(ConfigError.InvalidSequence, KeySequence.init(""));
}

test "KeySequence.toKeyName" {
    var seq = KeySequence{};
    seq.data[0] = toolkit.input.VirtualKey.prior;
    seq.data[1] = toolkit.input.VirtualKey.next;
    seq.len = 2;

    const name = try seq.toKeyName(testing.allocator);
    defer testing.allocator.free(name);

    try testing.expectEqualStrings("PageUp+PageDown", name);
}

test "KeySequence.fromKeyName" {
    const seq = try KeySequence.fromKeyName("PageUp+PageDown");

    try testing.expectEqual(@as(u32, 2), seq.len);
    try testing.expectEqual(toolkit.input.VirtualKey.prior, @as(u32, seq.data[0]));
    try testing.expectEqual(toolkit.input.VirtualKey.next, @as(u32, seq.data[1]));
}

test "DeviceConfig.getName empty" {
    const cfg = DeviceConfig{
        .hotkey = Config.defaultHotkey(),
    };

    try testing.expect(cfg.getName() == null);
}

test "DeviceConfig.setName and getName" {
    var cfg = DeviceConfig{
        .hotkey = Config.defaultHotkey(),
    };

    cfg.setName("Microphone");

    try testing.expectEqualStrings("Microphone", cfg.getName().?);
}

test "Config.init defaults" {
    var cfg = Config.init(testing.allocator);
    defer cfg.deinit();

    try testing.expectApproxEqAbs(@as(f32, 0.7), cfg.capture.volume, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0.2), cfg.render.volume, 0.001);
}
