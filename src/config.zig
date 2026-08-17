const std = @import("std");

const umbra = @import("umbra");

const binding = @import("binding.zig");

const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const Binding = binding.Binding;

pub const Error = error{
    ContentTooLarge,
    InvalidPath,
    NotFound,
    ParseError,
    ReadFailed,
    WriteFailed,
};

pub const file_name = "config.zon";

pub const capture_hotkey_default = "PageUp";
pub const render_hotkey_default = "PageDown";

pub const capture_volume_default: f32 = 0.7;
pub const render_volume_default: f32 = 0.3;

comptime {
    assert(file_name.len > 0);
    assert(capture_hotkey_default.len > 0);
    assert(render_hotkey_default.len > 0);
    assert(!std.mem.eql(u8, capture_hotkey_default, render_hotkey_default));
    assert(capture_volume_default >= 0.0 and capture_volume_default <= 1.0);
    assert(render_volume_default >= 0.0 and render_volume_default <= 1.0);
}

const eval_branch_quota: u32 = 1 << 16;

fn default_binding(comptime text: []const u8) Binding {
    const result = comptime parsed: {
        @setEvalBranchQuota(eval_branch_quota);

        break :parsed Binding.parse(text) catch @compileError("mute: invalid default binding");
    };

    return result;
}

const ZonDevice = struct {
    hotkey: ?[]const u8 = null,
    name: ?[]const u8 = null,
    volume: ?f32 = null,
};

const ZonConfig = struct {
    capture: ZonDevice = .{},
    render: ZonDevice = .{},
};

pub const DeviceConfig = struct {
    pub const name_len_max: u32 = 256;

    hotkey: Binding = default_binding(capture_hotkey_default),
    name: [name_len_max]u8 = [_]u8{0} ** name_len_max,
    name_len: u32 = 0,
    volume: f32 = capture_volume_default,

    pub fn get_hotkey(config: *const DeviceConfig) *const Binding {
        assert(config.hotkey.key_count > 0);

        return &config.hotkey;
    }

    pub fn get_name(config: *const DeviceConfig) ?[]const u8 {
        assert(config.name_len <= name_len_max);

        if (config.name_len == 0) {
            return null;
        }

        return config.name[0..config.name_len];
    }

    pub fn set_name(config: *DeviceConfig, name: []const u8) void {
        const length: u32 = @intCast(@min(name.len, name_len_max));

        @memcpy(config.name[0..length], name[0..length]);
        config.name_len = length;

        assert(config.name_len == length);
        assert(config.name_len <= name_len_max);
    }
};

pub const Config = struct {
    pub const content_len_max: u32 = 1024 * 64;
    pub const path_len_max: u32 = 512;

    const write_buffer_len_max: u32 = 4096;

    gpa: Allocator,
    capture: DeviceConfig = .{
        .hotkey = default_binding(capture_hotkey_default),
        .volume = capture_volume_default,
    },
    config_path: [path_len_max]u8 = [_]u8{0} ** path_len_max,
    config_path_len: u32 = 0,
    io: std.Io,
    is_loaded_from_file: bool = false,
    render: DeviceConfig = .{
        .hotkey = default_binding(render_hotkey_default),
        .volume = render_volume_default,
    },

    pub fn init(gpa: Allocator, io: std.Io) Config {
        return Config{
            .gpa = gpa,
            .io = io,
        };
    }

    pub fn deinit(config: *Config) void {
        assert(config.config_path_len <= path_len_max);

        config.config_path_len = 0;
    }

    pub fn load(gpa: Allocator, io: std.Io, app_name: []const u8) Error!Config {
        assert(app_name.len > 0);

        var config = Config.init(gpa, io);
        errdefer config.deinit();

        try config.load_config_path(app_name);
        try config.load_from_file();

        assert(config.config_path_len > 0);
        assert(config.capture.volume >= 0.0 and config.capture.volume <= 1.0);
        assert(config.render.volume >= 0.0 and config.render.volume <= 1.0);

        return config;
    }

    pub fn get_config_path(config: *const Config) ?[]const u8 {
        assert(config.config_path_len <= path_len_max);

        if (config.config_path_len == 0) {
            return null;
        }

        return config.config_path[0..config.config_path_len];
    }

    pub fn parse(config: *Config, content: [:0]const u8) Error!void {
        assert(content.len > 0);
        assert(content.len <= content_len_max);

        const parsed = std.zon.parse.fromSliceAlloc(
            ZonConfig,
            config.gpa,
            content,
            null,
            .{},
        ) catch {
            return Error.ParseError;
        };

        defer std.zon.parse.free(config.gpa, parsed);

        config.capture = parse_device(
            parsed.capture,
            capture_volume_default,
            default_binding(capture_hotkey_default),
        );

        config.render = parse_device(
            parsed.render,
            render_volume_default,
            default_binding(render_hotkey_default),
        );

        assert(config.capture.volume >= 0.0 and config.capture.volume <= 1.0);
        assert(config.render.volume >= 0.0 and config.render.volume <= 1.0);
    }

    pub fn read(config: *Config, storage: *[content_len_max + 1]u8) Error![:0]const u8 {
        const path = config.get_config_path() orelse {
            return Error.InvalidPath;
        };

        const file = std.Io.Dir.openFileAbsolute(config.io, path, .{}) catch |err| switch (err) {
            error.FileNotFound => return Error.NotFound,
            else => return Error.ReadFailed,
        };

        defer file.close(config.io);

        const count = file.readPositionalAll(config.io, storage, 0) catch {
            return Error.ReadFailed;
        };

        if (count == 0) {
            return Error.ParseError;
        }

        if (count > content_len_max) {
            return Error.ContentTooLarge;
        }

        assert(count > 0);
        assert(count <= content_len_max);

        storage[count] = 0;

        return storage[0..count :0];
    }

    pub fn save(config: *Config) Error!void {
        assert(config.config_path_len <= path_len_max);

        if (!config.is_loaded_from_file) {
            return;
        }

        assert(config.config_path_len > 0);

        const path = config.config_path[0..config.config_path_len];

        try config.create_directory(path);
        try config.write_config_file(path);
    }

    fn create_directory(config: *Config, path: []const u8) Error!void {
        assert(path.len > 0);

        const directory = std.fs.path.dirname(path) orelse {
            return Error.InvalidPath;
        };

        assert(directory.len > 0);
        assert(directory.len < path.len);

        std.Io.Dir.cwd().createDirPath(config.io, directory) catch {
            return Error.WriteFailed;
        };
    }

    fn load_config_path(config: *Config, app_name: []const u8) Error!void {
        assert(app_name.len > 0);

        var directory_buffer: [path_len_max]u8 = undefined;

        const directory = umbra.paths.config_dir(&directory_buffer, app_name) catch {
            return Error.InvalidPath;
        };

        assert(directory.len > 0);

        const full = std.fmt.bufPrint(
            &config.config_path,
            "{s}{c}{s}",
            .{ directory, std.fs.path.sep, file_name },
        ) catch {
            return Error.InvalidPath;
        };

        config.config_path_len = @intCast(full.len);

        assert(config.config_path_len > directory.len);
        assert(config.config_path_len <= path_len_max);
    }

    fn load_from_file(config: *Config) Error!void {
        assert(config.config_path_len > 0);
        assert(config.config_path_len <= path_len_max);

        var storage: [content_len_max + 1]u8 = undefined;

        const content = config.read(&storage) catch |err| switch (err) {
            Error.NotFound => {
                config.is_loaded_from_file = true;

                try config.save();

                return;
            },
            else => return err,
        };

        try config.parse(content);

        config.is_loaded_from_file = true;
    }

    fn to_zon_config(
        config: *const Config,
        capture_text: []u8,
        render_text: []u8,
    ) !ZonConfig {
        const capture_hotkey = try config.capture.hotkey.to_text(capture_text);
        const render_hotkey = try config.render.hotkey.to_text(render_text);

        return .{
            .capture = .{
                .hotkey = capture_hotkey,
                .name = config.capture.get_name(),
                .volume = config.capture.volume,
            },
            .render = .{
                .hotkey = render_hotkey,
                .name = config.render.get_name(),
                .volume = config.render.volume,
            },
        };
    }

    fn write_config_file(config: *Config, path: []const u8) Error!void {
        assert(path.len > 0);
        assert(path.len <= path_len_max);

        var capture_text: [binding.text_bytes_max]u8 = undefined;
        var render_text: [binding.text_bytes_max]u8 = undefined;

        const zon = config.to_zon_config(&capture_text, &render_text) catch {
            return Error.WriteFailed;
        };

        const file = std.Io.Dir.createFileAbsolute(config.io, path, .{}) catch {
            return Error.WriteFailed;
        };

        defer file.close(config.io);

        var buffer: [write_buffer_len_max]u8 = undefined;
        var writer = file.writer(config.io, &buffer);

        std.zon.stringify.serialize(zon, .{}, &writer.interface) catch {
            return Error.WriteFailed;
        };

        writer.interface.flush() catch {
            return Error.WriteFailed;
        };
    }
};

fn parse_device(device: ZonDevice, volume_default: f32, hotkey_default: Binding) DeviceConfig {
    assert(volume_default >= 0.0);
    assert(volume_default <= 1.0);

    const level = device.volume orelse volume_default;

    var result = DeviceConfig{
        .hotkey = hotkey_default,
        .volume = std.math.clamp(level, 0.0, 1.0),
    };

    assert(result.volume >= 0.0);
    assert(result.volume <= 1.0);

    if (device.name) |name| {
        result.set_name(name);
    }

    if (device.hotkey) |hotkey| {
        result.hotkey = Binding.parse(hotkey) catch result.hotkey;
    }

    assert(result.hotkey.key_count > 0);

    return result;
}

const testing = std.testing;

test "a default configuration carries a usable binding for both directions" {
    var config = Config.init(testing.allocator, testing.io);
    defer config.deinit();

    var buffer: [binding.text_bytes_max]u8 = undefined;

    try testing.expectEqualStrings(
        capture_hotkey_default,
        try config.capture.get_hotkey().to_text(&buffer),
    );

    try testing.expectEqualStrings(
        render_hotkey_default,
        try config.render.get_hotkey().to_text(&buffer),
    );

    try testing.expectEqual(capture_volume_default, config.capture.volume);
    try testing.expectEqual(render_volume_default, config.render.volume);
}

test "parsing replaces the binding, the name and the volume" {
    var config = Config.init(testing.allocator, testing.io);
    defer config.deinit();

    const content =
        \\.{
        \\    .capture = .{ .hotkey = "Ctrl+Shift+K", .name = "Microphone", .volume = 0.25 },
        \\    .render = .{ .hotkey = "F9", .name = "Speakers", .volume = 0.75 },
        \\}
    ;

    try config.parse(content);

    var buffer: [binding.text_bytes_max]u8 = undefined;

    try testing.expectEqualStrings("Ctrl+Shift+K", try config.capture.hotkey.to_text(&buffer));
    try testing.expectEqualStrings("Microphone", config.capture.get_name().?);
    try testing.expectEqual(@as(f32, 0.25), config.capture.volume);

    try testing.expectEqualStrings("F9", try config.render.hotkey.to_text(&buffer));
    try testing.expectEqualStrings("Speakers", config.render.get_name().?);
    try testing.expectEqual(@as(f32, 0.75), config.render.volume);
}

test "an unusable binding falls back to the default for that direction" {
    var config = Config.init(testing.allocator, testing.io);
    defer config.deinit();

    const content =
        \\.{
        \\    .capture = .{ .hotkey = "Ctrl+A+B" },
        \\    .render = .{ .hotkey = "Ctrl+Nonsense" },
        \\}
    ;

    try config.parse(content);

    var buffer: [binding.text_bytes_max]u8 = undefined;

    try testing.expectEqualStrings(
        capture_hotkey_default,
        try config.capture.hotkey.to_text(&buffer),
    );

    try testing.expectEqualStrings(
        render_hotkey_default,
        try config.render.hotkey.to_text(&buffer),
    );
}

test "an omitted volume falls back to the default for that direction" {
    var config = Config.init(testing.allocator, testing.io);
    defer config.deinit();

    const content =
        \\.{
        \\    .capture = .{ .name = "Microphone" },
        \\    .render = .{ .name = "Speakers" },
        \\}
    ;

    try config.parse(content);

    try testing.expectEqual(capture_volume_default, config.capture.volume);
    try testing.expectEqual(render_volume_default, config.render.volume);
}

test "an explicit volume is kept even when it matches nothing in particular" {
    var config = Config.init(testing.allocator, testing.io);
    defer config.deinit();

    const content =
        \\.{
        \\    .capture = .{ .volume = 0.5 },
        \\    .render = .{ .volume = 0.5 },
        \\}
    ;

    try config.parse(content);

    try testing.expectEqual(@as(f32, 0.5), config.capture.volume);
    try testing.expectEqual(@as(f32, 0.5), config.render.volume);
}

test "malformed content is reported rather than applied" {
    var config = Config.init(testing.allocator, testing.io);
    defer config.deinit();

    try testing.expectError(Error.ParseError, config.parse("not zon at all"));
}

test "an unset device name reads as absent" {
    const device = DeviceConfig{};

    try testing.expect(device.get_name() == null);
}

test "a device name longer than the field is truncated rather than overflowing" {
    var device = DeviceConfig{};

    const name = "n" ** (DeviceConfig.name_len_max + 32);

    device.set_name(name);

    try testing.expectEqual(DeviceConfig.name_len_max, device.name_len);
    try testing.expectEqual(DeviceConfig.name_len_max, device.get_name().?.len);
}

test "a configuration without a resolved path reports no path" {
    var config = Config.init(testing.allocator, testing.io);
    defer config.deinit();

    try testing.expect(config.get_config_path() == null);
}
