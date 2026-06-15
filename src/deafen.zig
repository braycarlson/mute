const std = @import("std");

const Application = @import("application.zig").Application;
const Logger = @import("logger.zig").Logger;
const Mode = @import("mode.zig").Mode;
const path_util = @import("path.zig");

const log_size_max: u32 = 5 * 1024 * 1024;

pub fn main() !void {
    var threaded: std.Io.Threaded = .init_single_threaded;
    const io = threaded.io();

    var logger = init_logger(io, .render);
    defer deinit_logger(&logger);

    var application: Application(.render) = undefined;

    application.init(std.heap.page_allocator, io, if (logger) |*log| log else null) catch |err| {
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

fn init_logger(io: std.Io, comptime mode: Mode) ?Logger {
    var appdata_buffer: [path_util.path_length_max]u8 = undefined;

    const base = path_util.get_appdata_path(&appdata_buffer, "mute") catch return null;

    var path_buffer: [path_util.path_length_max]u8 = undefined;

    const log_path = path_util.join_path(&path_buffer, base, mode.to_log_filename()) orelse return null;

    return Logger.init(io, .{ .path = log_path, .size = log_size_max }) catch null;
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
