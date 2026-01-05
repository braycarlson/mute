const std = @import("std");

const Application = @import("application.zig").Application;
const Logger = @import("logger.zig").Logger;
const Mode = @import("mode.zig").Mode;

const log_size_max: usize = 5 * 1024 * 1024;

pub fn main() !void {
    var logger = init_logger(std.heap.page_allocator, .render);
    defer deinit_logger(&logger);

    var application = Application(.render).init(std.heap.page_allocator, &logger) catch |err| {
        if (logger) |*log| {
            log.log("Failed to initialize: {}", .{err});
        }
        return err;
    };

    defer application.deinit();

    if (logger) |*log| {
        log.log("Starting application", .{});
    }

    application.run();
}

fn deinit_logger(logger: *?Logger) void {
    if (logger.*) |*log| {
        log.deinit();
    }
}

fn get_log_path(allocator: std.mem.Allocator, comptime mode: Mode) ![]u8 {
    const directory = try std.fs.getAppDataDir(allocator, "mute");
    defer allocator.free(directory);

    const result = try std.fs.path.join(allocator, &[_][]const u8{ directory, mode.to_log_filename() });

    return result;
}

fn init_logger(allocator: std.mem.Allocator, comptime mode: Mode) ?Logger {
    const path = get_log_path(allocator, mode) catch return null;
    defer allocator.free(path);

    return Logger.init(.{
        .path = path,
        .size = log_size_max,
    }) catch return null;
}

test {
    _ = @import("application.zig");
    _ = @import("config.zig");
    _ = @import("constant.zig");
    _ = @import("handler.zig");
    _ = @import("hotkey.zig");
    _ = @import("icon.zig");
    _ = @import("logger.zig");
    _ = @import("menu.zig");
    _ = @import("mode.zig");
    _ = @import("settings.zig");
    _ = @import("widget.zig");
}
