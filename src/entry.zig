const std = @import("std");

const arc = @import("arc");
const wisp = @import("wisp");

const ApplicationType = @import("application.zig").ApplicationType;
const Mode = @import("mode.zig").Mode;

const assert = std.debug.assert;

pub const directory_name = "mute";
pub const log_size_max: u32 = 5 * 1024 * 1024;
pub const path_bytes_max: u32 = 512;

pub const exit_failure: u8 = 1;
pub const exit_success: u8 = 0;

comptime {
    assert(directory_name.len > 0);
    assert(log_size_max > 0);
    assert(path_bytes_max > 0);
    assert(exit_failure != exit_success);
}

pub fn run(comptime mode: Mode) u8 {
    var threaded: std.Io.Threaded = .init_single_threaded;
    const io = threaded.io();

    var rotating = init_rotating(io, mode);
    defer if (rotating) |*writer| writer.deinit(io);

    var logger = init_logger(io, if (rotating) |*writer| writer else null);
    defer if (logger) |*log| flush(log);

    var application: ApplicationType(mode) = undefined;

    application.init(
        std.heap.page_allocator,
        io,
        if (logger) |*log| log else null,
    ) catch |err| {
        report(if (logger) |*log| log else null, "Unable to initialise the application", err);

        return exit_failure;
    };

    defer application.deinit();

    if (logger) |*log| {
        log.info("Starting application", &.{}, @src());
    }

    application.run() catch |err| {
        report(if (logger) |*log| log else null, "Unable to run the application", err);

        return exit_failure;
    };

    return exit_success;
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
    var directory_buffer: [path_bytes_max]u8 = undefined;

    const directory = wisp.paths.state_dir(&directory_buffer, directory_name) catch {
        return null;
    };

    assert(directory.len > 0);

    std.Io.Dir.cwd().createDirPath(io, directory) catch {
        return null;
    };

    var path_buffer: [path_bytes_max]u8 = undefined;

    const path = std.fmt.bufPrint(
        &path_buffer,
        "{s}{c}{s}",
        .{ directory, std.fs.path.sep, mode.to_log_filename() },
    ) catch {
        return null;
    };

    assert(path.len > directory.len);

    return arc.RotatingWriter.init(io, .{ .path = path, .size_max = log_size_max }) catch {
        return null;
    };
}

fn flush(logger: *arc.Logger) void {
    logger.sync() catch {
        return;
    };
}

fn report(logger: ?*arc.Logger, message: []const u8, err: anyerror) void {
    assert(message.len > 0);

    const log = logger orelse return;

    log.@"error"(message, &.{arc.err_from(err)}, @src());
}
