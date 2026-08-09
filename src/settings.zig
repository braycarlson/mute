const std = @import("std");

const arc = @import("arc");
const wisp = @import("wisp");

const Config = @import("config.zig").Config;

const assert = std.debug.assert;

const Logger = arc.Logger;

pub const SettingsManager = struct {
    configuration: *Config,
    handle: ?wisp.watcher.Handle,
    logger: ?*Logger,

    pub fn init(configuration: *Config, logger: ?*Logger) SettingsManager {
        const result = SettingsManager{
            .configuration = configuration,
            .handle = null,
            .logger = logger,
        };

        return result;
    }

    pub fn deinit(manager: *SettingsManager) void {
        const handle = manager.handle orelse return;

        manager.handle = null;

        wisp.watcher.unwatch(handle);

        assert(manager.handle == null);
    }

    pub fn open(manager: *SettingsManager) void {
        const path = manager.configuration.get_config_path() orelse return;

        assert(path.len > 0);

        manager.log("Opening settings file");

        wisp.shell.open(path) catch {
            manager.log("Unable to open the settings file");

            return;
        };
    }

    pub fn reload(manager: *SettingsManager) bool {
        var storage: [Config.content_len_max + 1]u8 = undefined;

        const content = manager.configuration.read(&storage) catch {
            manager.log("Unable to read the settings file");

            return false;
        };

        manager.configuration.parse(content) catch {
            manager.log("Unable to parse the settings file");

            return false;
        };

        return true;
    }

    pub fn watch(
        manager: *SettingsManager,
        callback: wisp.watcher.Callback,
        context: ?*anyopaque,
    ) void {
        assert(manager.handle == null);

        const path = manager.configuration.get_config_path() orelse return;

        assert(path.len > 0);

        manager.handle = wisp.watcher.watch(path, callback, context) catch {
            manager.log("Unable to watch the settings file");

            return;
        };

        assert(manager.handle != null);
    }

    fn log(manager: *SettingsManager, message: []const u8) void {
        assert(message.len > 0);

        if (manager.logger) |logger| {
            logger.info(message, &.{}, @src());
        }
    }
};
