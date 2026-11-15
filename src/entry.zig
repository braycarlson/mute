const std = @import("std");

const arc = @import("arc");
const kalymma = @import("kalymma");
const mantra = @import("mantra");
const nimble = @import("nimble");
const umbra = @import("umbra");

const ApplicationType = @import("application.zig").ApplicationType;
const directory_name = @import("config.zig").directory_name;
const Mode = @import("mode.zig").Mode;

const assert = std.debug.assert;

const Native = struct {
    pub const App = umbra.App;
    pub const Client = nimble.remote.Client;
    pub const Mixer = mantra.Mixer;
    pub const Runtime = kalymma.Runtime;
};

const exit_failure: u8 = 1;
const exit_success: u8 = 0;
const log_backup_count: u32 = 5;
const log_bytes_max: u32 = 5 * 1024 * 1024;

comptime {
    assert(exit_failure != exit_success);
    assert(log_backup_count <= arc.limits.rotating_backup_count_max);
    assert(log_bytes_max > 0);
}

pub fn run(comptime mode: Mode) u8 {
    const Application = ApplicationType(Native, mode);
    var core: arc.Core = undefined;
    var rotating_file: arc.RotatingFile = undefined;
    var threaded: std.Io.Threaded = .init_single_threaded;
    const io = threaded.io();
    const rotating = init_rotating(io, &rotating_file, mode);
    defer if (rotating) |file| file.deinit(io);

    const logger = if (rotating) |file| init_logger(io, &core, file) else null;
    defer if (logger) |log| flush(log);

    const application = std.heap.page_allocator.create(Application) catch |err| {
        report(logger, "Unable to initialise the application", err);

        return exit_failure;
    };

    defer std.heap.page_allocator.destroy(application);

    application.init(io, logger) catch |err| {
        report(logger, "Unable to initialise the application", err);

        return exit_failure;
    };

    defer application.deinit();

    if (logger) |log| {
        log.information("Starting application", &.{}, &@src());
    }

    application.run() catch |err| {
        report(logger, "Unable to run the application", err);

        return exit_failure;
    };

    return exit_success;
}

fn init_logger(io: std.Io, target: *arc.Core, file: *arc.RotatingFile) *const arc.Logger {
    var encoding: arc.Encoding = .development;

    encoding.level = .capital;
    encoding.time = .rfc3339_nano;

    const sinks = [_]arc.Core.Sink{.{
        .encoding = encoding,
        .level = .debug,
        .writer = .{ .rotating_file = file },
    }};

    var options: arc.Core.Options = .development;

    options.caller = false;
    options.level = .information;
    options.sinks = &sinks;

    target.init(io, &options);

    assert(target.logger.enabled(.information));
    assert(!target.logger.enabled(.debug));

    return &target.logger;
}

fn init_rotating(io: std.Io, target: *arc.RotatingFile, comptime mode: Mode) ?*arc.RotatingFile {
    var directory_buffer: [umbra.limits.path_bytes_max]u8 = undefined;

    const directory = Native.App.state_dir(io, &directory_buffer, directory_name) catch {
        return null;
    };

    assert(directory.len > 0);

    std.Io.Dir.cwd().createDirPath(io, directory) catch {
        return null;
    };

    var path_buffer: [umbra.limits.path_bytes_max]u8 = undefined;

    const path = std.mem.print(
        &path_buffer,
        "{s}{c}{s}",
        .{ directory, std.Io.Dir.path.sep, mode.to_log_filename() },
    ) catch {
        return null;
    };

    assert(path.len > directory.len);

    target.init(io, &.{
        .backup_count = log_backup_count,
        .path = path,
        .roll_daily = true,
        .size_max = log_bytes_max,
    }) catch {
        return null;
    };

    return target;
}

fn flush(logger: *const arc.Logger) void {
    logger.core.flush() catch {
        return;
    };
}

fn report(logger: ?*const arc.Logger, message: []const u8, err: anyerror) void {
    assert(message.len > 0);
    if (logger) |held| assert(held.enabled(.err));

    const log = logger orelse return;

    log.err(message, &.{.{ .key = "error", .value = .{ .string = @errorName(err) } }}, &@src());
}
