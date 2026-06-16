const std = @import("std");

const arc = @import("arc");

const Application = @import("application.zig").Application;
const Mode = @import("mode.zig").Mode;
const path_util = @import("path.zig");

const log_size_max: u32 = 5 * 1024 * 1024;

pub fn main() !void {
    var threaded: std.Io.Threaded = .init_single_threaded;
    const io = threaded.io();

    var rotating = init_rotating(io, .render);
    defer if (rotating) |*writer| writer.deinit(io);

    var logger = init_logger(io, if (rotating) |*writer| writer else null);
    defer if (logger) |*log| log.sync() catch {};

    var application: Application(.render) = undefined;

    application.init(std.heap.page_allocator, io, if (logger) |*log| log else null) catch |err| {
        if (logger) |*log| {
            log.@"error"("Failed to initialize", &.{arc.err_from(err)}, @src());
        }

        return err;
    };

    defer application.deinit();

    if (logger) |*log| {
        log.info("Starting application", &.{}, @src());
    }

    application.run();
}

fn init_logger(io: std.Io, writer: ?*arc.RotatingWriter) ?arc.Logger {
    const target = writer orelse return null;

    const config = arc.Config.development()
        .with_level(.info)
        .without_caller()
        .with_stacktrace_level(.fatal)
        .with_encoder_config(arc.EncoderConfig.development()
            .with_level_encoding(.capital)
            .with_time_encoding(.rfc3339_nano))
        .with_writer(.{ .rotating = target });

    return arc.Logger.init_with_config(io, config);
}

fn init_rotating(io: std.Io, comptime mode: Mode) ?arc.RotatingWriter {
    var appdata_buffer: [path_util.path_length_max]u8 = undefined;

    const base = path_util.get_appdata_path(&appdata_buffer, "mute") catch return null;

    var path_buffer: [path_util.path_length_max]u8 = undefined;

    const log_path = path_util.join_path(&path_buffer, base, mode.to_log_filename()) orelse return null;

    path_util.ensure_directory_exists(io, log_path) catch return null;

    return arc.RotatingWriter.init(io, .{ .path = log_path, .size_max = log_size_max }) catch null;
}

test {
    _ = @import("application.zig");
    _ = @import("config.zig");
    _ = @import("constant.zig");
    _ = @import("handler.zig");
    _ = @import("hotkey.zig");
    _ = @import("icon.zig");
    _ = @import("menu.zig");
    _ = @import("mode.zig");
    _ = @import("settings.zig");
    _ = @import("widget.zig");
}
