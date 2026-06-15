const std = @import("std");

const wisp = @import("wisp");
const win32 = @import("win32").everything;

const Config = @import("config.zig").Config;
const Logger = @import("logger.zig").Logger;

pub const SettingsManager = struct {
    configuration: *Config,
    logger: ?*Logger,
    watcher: wisp.Watcher,

    pub fn init(configuration: *Config, logger: ?*Logger) SettingsManager {
        return SettingsManager{
            .configuration = configuration,
            .logger = logger,
            .watcher = wisp.Watcher.init(),
        };
    }

    pub fn deinit(self: *SettingsManager) void {
        self.watcher.deinit();
    }

    pub fn open(self: *SettingsManager) void {
        const path = self.configuration.get_config_path() orelse return;

        self.log("Opening settings file");
        open_path(path);
    }

    pub fn reload(self: *SettingsManager) bool {
        const path = self.configuration.get_config_path() orelse return false;

        var buffer: [Config.content_len_max]u8 = undefined;

        const io = self.configuration.io;

        const file = std.Io.Dir.openFileAbsolute(io, path, .{}) catch return false;
        defer file.close(io);

        const count = file.readPositionalAll(io, &buffer, 0) catch return false;

        if (count == 0) {
            return false;
        }

        buffer[count] = 0;
        const slice: [:0]const u8 = buffer[0..count :0];

        self.configuration.parse(slice) catch return false;

        return true;
    }

    pub fn watch(self: *SettingsManager, callback: *const fn () void) void {
        const path = self.configuration.get_config_path() orelse return;
        self.watcher.watch(path, callback) catch {};
    }

    fn log(self: *SettingsManager, message: []const u8) void {
        if (self.logger) |logger| {
            logger.log("{s}", .{message});
        }
    }
};

fn open_path(path: []const u8) void {
    if (path.len == 0 or path.len > Config.path_len_max) {
        return;
    }

    var buffer: [Config.path_len_max]u16 = undefined;

    const length = std.unicode.utf8ToUtf16Le(&buffer, path) catch return;

    if (length == 0 or length >= Config.path_len_max) {
        return;
    }

    buffer[length] = 0;

    _ = win32.ShellExecuteW(
        null,
        std.unicode.utf8ToUtf16LeStringLiteral("open"),
        @ptrCast(&buffer),
        null,
        null,
        1,
    );
}
