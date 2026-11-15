const std = @import("std");

const mantra = @import("mantra");
const nimble = @import("nimble");
const toml = @import("toml");
const umbra = @import("umbra");

const Binding = @import("binding.zig").Binding;

const assert = std.debug.assert;

const CapacityError = toml.CapacityError || error{
    ContentTooLong,
    PathTooLong,
    ScratchExhausted,
};

const PlatformError = error{
    ReadFailed,
    WriteFailed,
};

const SettingsError = error{
    ContentInvalid,
};

const LoadError = PathError || ReadError;
const ParseError = CapacityError || SettingsError;
const PathError = umbra.CapacityError || umbra.PlatformError;
const ReadError = error{FileMissing} || CapacityError || PlatformError || SettingsError;
const capture_hotkey_default = "PageUp";
const capture_volume_default = 0.7;
const content_bytes_max: u32 = 64 * 1024;
pub const directory_name = "mute";
const document_node_count_max: u32 = 64;
const document_text_bytes_max: u32 = 4096;
const eval_branch_quota: u32 = 1 << 16;
const file_name = "config.toml";
const file_name_legacy = "config.zon";
const render_hotkey_default = "PageDown";
const render_volume_default = 0.3;
const scratch_bytes_max: u32 = 128 * 1024;
const write_bytes_max: u32 = 4096;

const writer_options: toml.Writer.Options = .{
    .layout = .compact,
    .strings = .auto,
    .version = .v1_1,
};

const Document = toml.DocumentType(.{
    .line_count_max = null,
    .node_count_max = document_node_count_max,
    .text_bytes_max = document_text_bytes_max,
});

const TomlSide = struct {
    hotkey: ?[]const u8 = null,
    name: ?[]const u8 = null,
    volume: ?f32 = null,
};

const TomlConfig = struct {
    capture: TomlSide = .{},
    render: TomlSide = .{},
};

const default_toml = TomlConfig{
    .capture = .{ .hotkey = capture_hotkey_default, .volume = capture_volume_default },
    .render = .{ .hotkey = render_hotkey_default, .volume = render_volume_default },
};

comptime {
    assert(directory_name.len > 0);
    assert(file_name.len > 0);
    assert(!std.mem.endsWith(u8, file_name, file_name_legacy));
    assert(!std.mem.eql(u8, capture_hotkey_default, render_hotkey_default));
    assert(capture_volume_default >= mantra.limits.volume_fraction_min);
    assert(capture_volume_default <= mantra.limits.volume_fraction_max);
    assert(render_volume_default >= mantra.limits.volume_fraction_min);
    assert(render_volume_default <= mantra.limits.volume_fraction_max);
    assert(content_bytes_max < scratch_bytes_max);
    assert(content_bytes_max <= toml.limits.source_bytes_max);
    assert(document_node_count_max >= 1 + 2 * (1 + @typeInfo(TomlSide).@"struct".field_names.len));
    assert(document_text_bytes_max >= 2 * mantra.limits.name_bytes_max);
    assert(document_text_bytes_max <= content_bytes_max);
    assert(write_bytes_max > 0);
}

pub const Config = struct {
    capture: Side,
    content: [content_bytes_max + 1]u8,
    diagnostic: ?Diagnostic,
    document: Document,
    io: std.Io,
    path: [umbra.limits.path_bytes_max]u8,
    path_length: u32,
    render: Side,
    scratch: [scratch_bytes_max]u8,

    pub const Diagnostic = struct {
        position: toml.Position,
        reason: []const u8,
    };

    pub const Side = struct {
        hotkey: Binding,
        name: [mantra.limits.name_bytes_max]u8 = @splat(0),
        name_length: u32 = 0,
        volume: f32,

        pub fn clear_name(side: *Side) void {
            side.name_length = 0;

            assert(side.get_name() == null);
        }

        pub fn get_hotkey(side: *const Side) *const Binding {
            assert(side.hotkey.key_count > 0);

            return &side.hotkey;
        }

        pub fn get_name(side: *const Side) ?[]const u8 {
            assert(side.name_length <= mantra.limits.name_bytes_max);

            if (side.name_length == 0) {
                return null;
            }

            return side.name[0..side.name_length];
        }

        fn set_name(side: *Side, name: []const u8) void {
            assert(name.len <= document_text_bytes_max);

            const length: u32 = @intCast(@min(name.len, mantra.limits.name_bytes_max));

            @memcpy(side.name[0..length], name[0..length]);
            side.name_length = length;

            assert(side.name_length == length);
            assert(side.name_length <= mantra.limits.name_bytes_max);
        }
    };

    pub fn init(config: *Config, io: std.Io) void {
        config.* = .{
            .capture = .{
                .hotkey = default_binding(capture_hotkey_default),
                .volume = capture_volume_default,
            },
            .content = undefined,
            .diagnostic = null,
            .document = undefined,
            .io = io,
            .path = @splat(0),
            .path_length = 0,
            .render = .{
                .hotkey = default_binding(render_hotkey_default),
                .volume = render_volume_default,
            },
            .scratch = undefined,
        };

        assert(config.get_path() == null);
        assert(config.diagnostic == null);
    }

    pub fn get_path(config: *const Config) ?[]const u8 {
        assert(config.path_length <= umbra.limits.path_bytes_max);

        if (config.path_length == 0) {
            return null;
        }

        return config.path[0..config.path_length];
    }

    pub fn load(config: *Config, comptime App: type) LoadError!void {
        var buffer: [umbra.limits.path_bytes_max]u8 = undefined;

        const directory = try App.config_dir(config.io, &buffer, directory_name);

        assert(directory.len > 0);

        try config.load_from(directory);
    }

    pub fn parse(config: *Config, content: []const u8) ParseError!void {
        assert(content.len > 0);
        assert(content.len <= content_bytes_max);

        config.diagnostic = null;

        const settings = try config.parse_toml(content);

        config.apply(&settings);

        assert(config.diagnostic == null);
    }

    pub fn reload(config: *Config) (ReadError || ParseError)!void {
        config.diagnostic = null;

        const settings = try config.read_settings();

        config.apply(&settings);

        assert(config.diagnostic == null);
        assert(config.get_path() != null);
    }

    fn apply(config: *Config, settings: *const TomlConfig) void {
        config.capture = parse_side(
            &settings.capture,
            capture_volume_default,
            default_binding(capture_hotkey_default),
        );

        config.render = parse_side(
            &settings.render,
            render_volume_default,
            default_binding(render_hotkey_default),
        );

        assert(config.capture.volume >= mantra.limits.volume_fraction_min);
        assert(config.capture.volume <= mantra.limits.volume_fraction_max);
        assert(config.render.volume >= mantra.limits.volume_fraction_min);
        assert(config.render.volume <= mantra.limits.volume_fraction_max);
    }

    fn load_from(config: *Config, directory: []const u8) LoadError!void {
        assert(directory.len > 0);

        try config.resolve_path(directory, file_name);

        config.reload() catch |err| switch (err) {
            error.FileMissing => try config.migrate(directory),
            else => |other| return other,
        };

        assert(config.get_path() != null);
        assert(config.diagnostic == null);
    }

    fn migrate(config: *Config, directory: []const u8) LoadError!void {
        assert(directory.len > 0);

        var buffer: [umbra.limits.path_bytes_max]u8 = undefined;

        const path = try join(&buffer, directory, file_name);

        try config.resolve_path(directory, file_name_legacy);

        const settings = config.read_settings() catch |err| switch (err) {
            error.FileMissing => default_toml,
            else => |other| return other,
        };

        config.apply(&settings);

        try config.save(path, &settings);
        try config.resolve_path(directory, file_name);
        try config.reload();

        assert(config.path_length == path.len);
    }

    fn parse_legacy(config: *Config, content: [:0]const u8) ParseError!TomlConfig {
        assert(content.len > 0);
        assert(content.len <= content_bytes_max);

        var arena = std.heap.FixedBufferAllocator.init(&config.scratch);
        var diagnostics: std.zon.parse.Diagnostics = undefined;

        return std.zon.parse.fromSlice(TomlConfig, .{
            .gpa = arena.allocator(),
            .arena = arena.allocator(),
            .source = content,
            .diagnostics = &diagnostics,
        }) catch |err| switch (err) {
            error.OutOfMemory => return error.ScratchExhausted,
            error.ParseZon => return error.ContentInvalid,
        };
    }

    fn parse_toml(config: *Config, content: []const u8) ParseError!TomlConfig {
        assert(content.len > 0);
        assert(content.len <= content_bytes_max);

        config.document.parse(content, .{ .version = .v1_1 }) catch |err| {
            config.diagnostic = .{
                .position = config.document.diagnostic(),
                .reason = toml.message(err),
            };

            return switch (err) {
                error.DepthExceeded,
                error.NodesExhausted,
                error.TextExhausted,
                => |capacity| capacity,
                else => error.ContentInvalid,
            };
        };

        var position: toml.Position = undefined;
        var region: toml.Region = .init(&config.scratch);
        var result: TomlConfig = undefined;

        const document = &config.document.base;

        toml.decode(TomlConfig, &region, document, document.root(), &result, .{
            .diagnostic = &position,
            .unknown_members = .refused,
        }) catch |err| {
            config.diagnostic = .{ .position = position, .reason = toml.message(err) };

            return switch (err) {
                error.MemberMissing, error.MemberUnknown, error.Mismatch => error.ContentInvalid,
                error.RegionFull => error.ScratchExhausted,
            };
        };

        return result;
    }

    fn read(config: *Config, path: []const u8) ReadError![:0]const u8 {
        assert(path.len > 0);
        assert(path.len <= umbra.limits.path_bytes_max);

        const file = std.Io.Dir.openFileAbsolute(config.io, path, .{}) catch |err| switch (err) {
            error.FileNotFound => return error.FileMissing,
            else => return error.ReadFailed,
        };

        defer file.close(config.io);

        const count = file.readPositionalAll(config.io, &config.content, 0) catch {
            return error.ReadFailed;
        };

        if (count == 0) {
            return error.ContentInvalid;
        }

        if (count > content_bytes_max) {
            return error.ContentTooLong;
        }

        config.content[count] = 0;

        return config.content[0..count :0];
    }

    fn read_settings(config: *Config) (ReadError || ParseError)!TomlConfig {
        const path = config.get_path() orelse return error.FileMissing;
        const content = try config.read(path);

        assert(content.len > 0);
        assert(content.len <= content_bytes_max);

        if (std.mem.endsWith(u8, path, file_name_legacy)) {
            return config.parse_legacy(content);
        }

        return config.parse_toml(content);
    }

    fn resolve_path(config: *Config, directory: []const u8, name: []const u8) CapacityError!void {
        assert(directory.len > 0);
        assert(name.len > 0);
        assert(std.mem.findScalar(u8, name, std.Io.Dir.path.sep) == null);

        config.path_length = 0;

        const full = try join(&config.path, directory, name);

        config.path_length = @intCast(full.len);

        assert(config.path_length > directory.len);
        assert(config.path_length <= umbra.limits.path_bytes_max);
    }

    fn save(
        config: *const Config,
        path: []const u8,
        settings: *const TomlConfig,
    ) (PlatformError || SettingsError)!void {
        assert(path.len > 0);
        assert(std.Io.Dir.path.isAbsolute(path));

        const options: std.Io.Dir.CreateFileAtomicOptions = .{
            .make_path = true,
            .replace = false,
        };

        var atomic = std.Io.Dir.cwd().createFileAtomic(config.io, path, options) catch {
            return error.WriteFailed;
        };

        defer atomic.deinit(config.io);

        var buffer: [write_bytes_max]u8 = undefined;
        var sink = atomic.file.writer(config.io, &buffer);
        var writer: toml.Writer = undefined;

        writer.init(&sink.interface, writer_options);

        toml.encode(TomlConfig, &writer, settings) catch |err| switch (err) {
            error.DatetimeInvalid, error.Utf8Invalid => return error.ContentInvalid,
            error.WriteFailed => return error.WriteFailed,
        };

        writer.finish();

        sink.interface.flush() catch {
            return error.WriteFailed;
        };

        atomic.file.sync(config.io) catch {
            return error.WriteFailed;
        };

        atomic.link(config.io) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return error.WriteFailed,
        };
    }

    fn default_binding(comptime text: []const u8) Binding {
        comptime assert(text.len > 0);

        const result = comptime parsed: {
            @setEvalBranchQuota(eval_branch_quota);

            break :parsed Binding.parse(text) catch @compileError("mute: invalid default binding");
        };

        return result;
    }

    fn join(buffer: []u8, directory: []const u8, name: []const u8) CapacityError![]const u8 {
        assert(buffer.len == umbra.limits.path_bytes_max);
        assert(directory.len > 0);
        assert(name.len > 0);

        const result = std.mem.print(
            buffer,
            "{s}{c}{s}",
            .{ directory, std.Io.Dir.path.sep, name },
        ) catch {
            return error.PathTooLong;
        };

        assert(result.len == directory.len + 1 + name.len);

        return result;
    }

    fn parse_side(source: *const TomlSide, volume_default: f32, hotkey_default: Binding) Side {
        assert(volume_default >= mantra.limits.volume_fraction_min);
        assert(volume_default <= mantra.limits.volume_fraction_max);

        const level: f32 = source.volume orelse volume_default;

        var result = Side{
            .hotkey = hotkey_default,
            .volume = std.math.clamp(
                level,
                mantra.limits.volume_fraction_min,
                mantra.limits.volume_fraction_max,
            ),
        };

        assert(result.volume >= mantra.limits.volume_fraction_min);
        assert(result.volume <= mantra.limits.volume_fraction_max);

        if (source.name) |name| {
            result.set_name(name);
        }

        if (source.hotkey) |hotkey| {
            result.hotkey = Binding.parse(hotkey) catch result.hotkey;
        }

        assert(result.hotkey.key_count > 0);

        return result;
    }
};

const testing = std.testing;

const Keycode = nimble.Keycode;

const default_text =
    \\[capture]
    \\hotkey = "PageUp"
    \\volume = 0.7
    \\
    \\[render]
    \\hotkey = "PageDown"
    \\volume = 0.3
    \\
;

const legacy_default =
    \\.{ .capture = .{
    \\    .hotkey = "PageUp",
    \\    .name = null,
    \\    .volume = 0.7,
    \\}, .render = .{
    \\    .hotkey = "PageDown",
    \\    .name = null,
    \\    .volume = 0.3,
    \\} }
;

fn absolute_path_of(temporary: *const testing.TmpDir, buffer: []u8) ![]const u8 {
    assert(buffer.len >= umbra.limits.path_bytes_max);

    const length = try temporary.dir.realPath(testing.io, buffer);
    return buffer[0..length];
}

fn expect_config_equal(expected: *const Config, actual: *const Config) !void {
    try testing.expectEqual(expected.capture.hotkey, actual.capture.hotkey);
    try testing.expectEqual(expected.render.hotkey, actual.render.hotkey);
    try testing.expectEqual(expected.capture.volume, actual.capture.volume);
    try testing.expectEqual(expected.render.volume, actual.render.volume);
    try testing.expectEqualDeep(expected.capture.get_name(), actual.capture.get_name());
    try testing.expectEqualDeep(expected.render.get_name(), actual.render.get_name());
}

test Config {
    const fixture = try testing.allocator.create(Config);
    defer testing.allocator.destroy(fixture);

    fixture.init(testing.io);

    try fixture.parse(
        \\[capture]
        \\hotkey = "Ctrl+Shift+K"
        \\name = "Microphone"
        \\volume = 0.25
        \\
        \\[render]
        \\hotkey = "F9"
        \\name = "Speakers"
        \\volume = 0.75
    );

    const capture = fixture.capture.get_hotkey();

    try testing.expectEqual(Keycode.k, capture.trigger());
    try testing.expect(capture.modifiers.ctrl());
    try testing.expect(capture.modifiers.shift());
    try testing.expectEqualStrings("Microphone", fixture.capture.get_name().?);
    try testing.expectEqual(@as(f32, 0.25), fixture.capture.volume);

    try testing.expectEqual(Keycode.f9, fixture.render.get_hotkey().trigger());
    try testing.expectEqualStrings("Speakers", fixture.render.get_name().?);
    try testing.expectEqual(@as(f32, 0.75), fixture.render.volume);
}

test "a default configuration carries a usable binding for both directions" {
    const fixture = try testing.allocator.create(Config);
    defer testing.allocator.destroy(fixture);

    fixture.init(testing.io);

    try testing.expectEqual(Keycode.page_up, fixture.capture.get_hotkey().trigger());
    try testing.expectEqual(Keycode.page_down, fixture.render.get_hotkey().trigger());
    try testing.expectEqual(capture_volume_default, fixture.capture.volume);
    try testing.expectEqual(render_volume_default, fixture.render.volume);
}

test "a fresh start writes the default file and loads it as the default configuration" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();

    var buffer: [umbra.limits.path_bytes_max]u8 = undefined;
    const absolute = try absolute_path_of(&temporary, &buffer);
    const expected = try testing.allocator.create(Config);
    defer testing.allocator.destroy(expected);

    const fixture = try testing.allocator.create(Config);
    defer testing.allocator.destroy(fixture);

    expected.init(testing.io);
    fixture.init(testing.io);

    try fixture.load_from(absolute);
    try expect_config_equal(expected, fixture);

    var source: [write_bytes_max]u8 = undefined;
    const written = try temporary.dir.readFile(testing.io, file_name, &source);
    const legacy = temporary.dir.access(testing.io, file_name_legacy, .{});

    try testing.expectEqualStrings(default_text, written);
    try testing.expectError(error.FileNotFound, legacy);
    try testing.expect(std.mem.endsWith(u8, fixture.get_path().?, file_name));
}

test "a full configuration survives an encode and a decode through TOML text" {
    const original = TomlConfig{
        .capture = .{ .hotkey = "Ctrl+Shift+K", .name = "Bob's \"USB\" Mic", .volume = 0.25 },
        .render = .{ .hotkey = "F9", .name = "C:\\Audio\\Speakers", .volume = 0.75 },
    };

    var buffer: [write_bytes_max]u8 = undefined;
    var sink: std.Io.Writer = .fixed(&buffer);
    var writer: toml.Writer = undefined;

    writer.init(&sink, writer_options);

    try toml.encode(TomlConfig, &writer, &original);

    writer.finish();

    const fixture = try testing.allocator.create(Config);
    defer testing.allocator.destroy(fixture);

    fixture.init(testing.io);

    const decoded = try fixture.parse_toml(sink.buffered());

    try testing.expectEqualDeep(original, decoded);

    try fixture.parse(sink.buffered());

    try testing.expectEqual(try Binding.parse("Ctrl+Shift+K"), fixture.capture.hotkey);
    try testing.expectEqual(try Binding.parse("F9"), fixture.render.hotkey);
    try testing.expectEqualStrings("Bob's \"USB\" Mic", fixture.capture.get_name().?);
    try testing.expectEqualStrings("C:\\Audio\\Speakers", fixture.render.get_name().?);
    try testing.expectEqual(@as(f32, 0.25), fixture.capture.volume);
    try testing.expectEqual(@as(f32, 0.75), fixture.render.volume);
}

test "a legacy default ZON file migrates to TOML once and the TOML file wins after" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();

    try temporary.dir.writeFile(testing.io, .{
        .sub_path = file_name_legacy,
        .data = legacy_default,
    });

    var buffer: [umbra.limits.path_bytes_max]u8 = undefined;
    const absolute = try absolute_path_of(&temporary, &buffer);
    const expected = try testing.allocator.create(Config);
    defer testing.allocator.destroy(expected);

    const fixture = try testing.allocator.create(Config);
    defer testing.allocator.destroy(fixture);

    expected.init(testing.io);
    expected.apply(&try expected.parse_legacy(legacy_default));
    fixture.init(testing.io);

    try fixture.load_from(absolute);
    try expect_config_equal(expected, fixture);

    var source: [write_bytes_max]u8 = undefined;
    var written: [write_bytes_max]u8 = undefined;

    try testing.expectEqualStrings(
        legacy_default,
        try temporary.dir.readFile(testing.io, file_name_legacy, &source),
    );

    try testing.expectEqualStrings(
        default_text,
        try temporary.dir.readFile(testing.io, file_name, &written),
    );

    try temporary.dir.writeFile(testing.io, .{
        .sub_path = file_name,
        .data = "[capture]\nvolume = 0.5\n",
    });

    try fixture.load_from(absolute);

    try testing.expectEqual(@as(f32, 0.5), fixture.capture.volume);
    try testing.expectEqual(expected.render.volume, fixture.render.volume);

    try testing.expectEqualStrings(
        legacy_default,
        try temporary.dir.readFile(testing.io, file_name_legacy, &source),
    );
}

test "a legacy ZON file that fails to parse stays in use and nothing is written" {
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();

    try temporary.dir.writeFile(testing.io, .{ .sub_path = file_name_legacy, .data = "not zon" });

    var buffer: [umbra.limits.path_bytes_max]u8 = undefined;
    const absolute = try absolute_path_of(&temporary, &buffer);
    const fixture = try testing.allocator.create(Config);
    defer testing.allocator.destroy(fixture);

    fixture.init(testing.io);

    try testing.expectError(error.ContentInvalid, fixture.load_from(absolute));
    try testing.expectError(error.FileNotFound, temporary.dir.access(testing.io, file_name, .{}));
    try testing.expect(std.mem.endsWith(u8, fixture.get_path().?, file_name_legacy));
    try testing.expect(fixture.diagnostic == null);
    try testing.expectEqual(Keycode.page_up, fixture.capture.get_hotkey().trigger());

    try temporary.dir.writeFile(testing.io, .{
        .sub_path = file_name_legacy,
        .data = ".{ .capture = .{ .hotkey = \"F9\" } }",
    });

    try fixture.reload();

    try testing.expectEqual(Keycode.f9, fixture.capture.get_hotkey().trigger());
    try testing.expectError(error.FileNotFound, temporary.dir.access(testing.io, file_name, .{}));
}

test "a legacy ZON file that TOML cannot hold stays in use and nothing is written" {
    const legacy = ".{ .capture = .{ .hotkey = \"F9\", .name = \"\\xff\" } }";

    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();

    try temporary.dir.writeFile(testing.io, .{ .sub_path = file_name_legacy, .data = legacy });

    var buffer: [umbra.limits.path_bytes_max]u8 = undefined;
    const absolute = try absolute_path_of(&temporary, &buffer);
    const fixture = try testing.allocator.create(Config);
    defer testing.allocator.destroy(fixture);

    fixture.init(testing.io);

    try testing.expectError(error.ContentInvalid, fixture.load_from(absolute));
    try testing.expectError(error.FileNotFound, temporary.dir.access(testing.io, file_name, .{}));
    try testing.expect(std.mem.endsWith(u8, fixture.get_path().?, file_name_legacy));
    try testing.expectEqual(Keycode.f9, fixture.capture.get_hotkey().trigger());
    try testing.expectEqualStrings("\xff", fixture.capture.get_name().?);

    var source: [write_bytes_max]u8 = undefined;
    const kept = try temporary.dir.readFile(testing.io, file_name_legacy, &source);

    try testing.expectEqualStrings(legacy, kept);
}

test "an unusable binding falls back to the default for that direction" {
    const fixture = try testing.allocator.create(Config);
    defer testing.allocator.destroy(fixture);

    fixture.init(testing.io);

    try fixture.parse(
        \\[capture]
        \\hotkey = "Ctrl+A+B"
        \\
        \\[render]
        \\hotkey = "Ctrl+Nonsense"
    );

    try testing.expectEqual(Keycode.page_up, fixture.capture.get_hotkey().trigger());
    try testing.expectEqual(Keycode.page_down, fixture.render.get_hotkey().trigger());
}

test "a hotkey part longer than any name falls back rather than crashing" {
    const fixture = try testing.allocator.create(Config);
    defer testing.allocator.destroy(fixture);

    fixture.init(testing.io);

    try fixture.parse(
        \\capture = { hotkey = "Ctrl+abcdefghijklmnopq" }
    );

    try testing.expectEqual(Keycode.page_up, fixture.capture.get_hotkey().trigger());
}

test "an omitted volume falls back to the default for that direction" {
    const fixture = try testing.allocator.create(Config);
    defer testing.allocator.destroy(fixture);

    fixture.init(testing.io);

    try fixture.parse(
        \\[capture]
        \\name = "Microphone"
        \\
        \\[render]
        \\name = "Speakers"
    );

    try testing.expectEqual(capture_volume_default, fixture.capture.volume);
    try testing.expectEqual(render_volume_default, fixture.render.volume);
}

test "an explicit volume is kept even when it matches nothing in particular" {
    const fixture = try testing.allocator.create(Config);
    defer testing.allocator.destroy(fixture);

    fixture.init(testing.io);

    try fixture.parse(
        \\[capture]
        \\volume = 0.5
        \\
        \\[render]
        \\volume = 0.5
    );

    try testing.expectEqual(@as(f32, 0.5), fixture.capture.volume);
    try testing.expectEqual(@as(f32, 0.5), fixture.render.volume);
}

test "malformed content is reported rather than applied" {
    const fixture = try testing.allocator.create(Config);
    defer testing.allocator.destroy(fixture);

    fixture.init(testing.io);

    try testing.expectError(error.ContentInvalid, fixture.parse("not toml at all"));
    try testing.expectEqual(Keycode.page_up, fixture.capture.get_hotkey().trigger());
}

test "a malformed file names the line, the column, and the reason" {
    const malformed = "[capture]\nhotkey = \"F9\"\nhotkey = \"F10\"\n";

    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();

    try temporary.dir.writeFile(testing.io, .{ .sub_path = file_name, .data = malformed });

    var buffer: [umbra.limits.path_bytes_max]u8 = undefined;
    const absolute = try absolute_path_of(&temporary, &buffer);
    const fixture = try testing.allocator.create(Config);
    defer testing.allocator.destroy(fixture);

    fixture.init(testing.io);

    try testing.expectError(error.ContentInvalid, fixture.load_from(absolute));

    var source: [write_bytes_max]u8 = undefined;
    const kept = try temporary.dir.readFile(testing.io, file_name, &source);

    try testing.expectEqualStrings(malformed, kept);

    const syntax = fixture.diagnostic orelse return error.DiagnosticMissing;

    try testing.expectEqual(@as(u32, 3), syntax.position.line);
    try testing.expectEqual(@as(u32, 1), syntax.position.column);
    try testing.expectEqualStrings("duplicate key", syntax.reason);
    try testing.expectEqual(Keycode.page_up, fixture.capture.get_hotkey().trigger());

    const mismatch = fixture.parse(
        \\[render]
        \\name = "Speakers"
        \\volume = "loud"
    );

    try testing.expectError(error.ContentInvalid, mismatch);

    const kind = fixture.diagnostic orelse return error.DiagnosticMissing;

    try testing.expectEqual(@as(u32, 3), kind.position.line);
    try testing.expectEqual(@as(u32, 10), kind.position.column);
    try testing.expectEqualStrings("the value does not match the field's type", kind.reason);
    try testing.expectEqual(Keycode.page_down, fixture.render.get_hotkey().trigger());
    try testing.expect(fixture.render.get_name() == null);

    try fixture.parse("[render]\nvolume = 0.5\n");

    try testing.expect(fixture.diagnostic == null);

    const unknown = fixture.parse("[capture]\nvolume = 0.5\nvolumes = 0.5\n");

    try testing.expectError(error.ContentInvalid, unknown);

    const member = fixture.diagnostic orelse return error.DiagnosticMissing;
    const expected: toml.Position = .{ .column = 1, .line = 3, .offset = 23 };

    try testing.expectEqual(expected, member.position);
    try testing.expectEqualStrings("unknown key", member.reason);
    try testing.expectEqual(@as(f32, 0.5), fixture.render.volume);
}

test "a device name longer than the field is truncated rather than overflowing" {
    const fixture = try testing.allocator.create(Config);
    defer testing.allocator.destroy(fixture);

    fixture.init(testing.io);

    const name: [mantra.limits.name_bytes_max + 32]u8 = @splat('n');

    fixture.capture.set_name(&name);

    try testing.expectEqual(mantra.limits.name_bytes_max, fixture.capture.name_length);
    try testing.expectEqual(mantra.limits.name_bytes_max, fixture.capture.get_name().?.len);

    fixture.capture.clear_name();

    try testing.expect(fixture.capture.get_name() == null);
}

test "a configuration without a resolved path reports no path" {
    const fixture = try testing.allocator.create(Config);
    defer testing.allocator.destroy(fixture);

    fixture.init(testing.io);

    try testing.expect(fixture.get_path() == null);
    try testing.expectError(error.FileMissing, fixture.reload());
}
