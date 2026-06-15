const std = @import("std");

const nimble = @import("nimble");

pub const path_length_max: u32 = 512;

const backup_count_max: u32 = 5;
const buffer_size: u32 = 4096;
const path_with_suffix_length_max: u32 = path_length_max + 8;

pub const LoggerError = error{
    InvalidPath,
    DirectoryCreationFailed,
    FileOpenFailed,
    StatFailed,
    SeekFailed,
    RotationFailed,
    FormatFailed,
    WriteFailed,
};

pub const Date = struct {
    day: u5,
    month: u4,
    year: u16,

    pub fn current(io: std.Io) Date {
        const timestamp = std.Io.Timestamp.now(io, .real).toSeconds();

        return Date.from_timestamp(timestamp);
    }

    pub fn from_timestamp(timestamp: i64) Date {
        std.debug.assert(timestamp >= 0);

        const datetime = std.time.epoch.EpochSeconds{ .secs = @intCast(timestamp) };
        const day = datetime.getEpochDay();
        const year_day = day.calculateYearDay();
        const month_day = year_day.calculateMonthDay();

        return Date{
            .year = year_day.year,
            .month = month_day.month.numeric(),
            .day = month_day.day_index + 1,
        };
    }

    pub fn eql(self: *const Date, other: *const Date) bool {
        return self.year == other.year and self.month == other.month and self.day == other.day;
    }
};

pub const Logger = struct {
    pub const Options = struct {
        path: []const u8,
        size: u32 = 5 * 1024 * 1024,
    };

    current_size: u32 = 0,
    file: ?std.Io.File = null,
    io: std.Io,
    last_date: ?Date = null,
    max_size: u32 = 5 * 1024 * 1024,
    mutex: nimble.Mutex = .{},
    path: [path_length_max]u8 = [_]u8{0} ** path_length_max,
    path_length: u32 = 0,
    write_error_count: u32 = 0,

    pub fn init(io: std.Io, options: Options) LoggerError!Logger {
        std.debug.assert(options.path.len > 0);
        std.debug.assert(options.path.len <= path_length_max);

        const length: u32 = @intCast(options.path.len);

        if (length == 0 or length > path_length_max) {
            return LoggerError.InvalidPath;
        }

        var logger = Logger{
            .io = io,
            .max_size = options.size,
        };

        @memcpy(logger.path[0..length], options.path);
        logger.path_length = length;

        std.debug.assert(logger.path_length == length);
        std.debug.assert(logger.path_length > 0);

        try logger.open_file();

        logger.last_date = Date.current(io);

        return logger;
    }

    pub fn deinit(self: *Logger) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.file) |file| {
            file.close(self.io);
            self.file = null;
        }
    }

    pub fn log(self: *Logger, comptime format: []const u8, argument: anytype) void {
        std.debug.assert(self.path_length > 0);
        std.debug.assert(self.path_length <= path_length_max);

        self.mutex.lock();
        defer self.mutex.unlock();

        self.ensure_file_ready();

        var buffer: [buffer_size]u8 = undefined;

        const content = self.format_message(&buffer, format, argument) catch {
            return;
        };

        self.write_to_file(content);
    }

    fn ensure_file_ready(self: *Logger) void {
        if (self.should_rotate()) {
            self.rotate() catch {
                self.write_error_count += 1;
            };
        }
    }

    fn format_message(
        self: *Logger,
        buffer: *[buffer_size]u8,
        comptime format: []const u8,
        argument: anytype,
    ) LoggerError![]const u8 {
        var writer = std.Io.Writer.fixed(buffer);

        write_timestamp(self.io, &writer) catch {
            self.write_error_count += 1;
            return LoggerError.FormatFailed;
        };

        writer.print(format ++ "\n", argument) catch {
            self.write_error_count += 1;
            return LoggerError.FormatFailed;
        };

        return writer.buffered();
    }

    fn get_path_slice(self: *const Logger) []const u8 {
        std.debug.assert(self.path_length > 0);
        std.debug.assert(self.path_length <= path_length_max);

        return self.path[0..self.path_length];
    }

    fn has_date_changed(self: *const Logger) bool {
        const today = Date.current(self.io);

        if (self.last_date) |last| {
            return !today.eql(&last);
        }

        return false;
    }

    fn open_file(self: *Logger) LoggerError!void {
        std.debug.assert(self.path_length > 0);

        const path = self.get_path_slice();
        const directory = std.fs.path.dirname(path) orelse {
            return LoggerError.InvalidPath;
        };

        std.Io.Dir.createDirAbsolute(self.io, directory, .default_dir) catch |err| {
            if (err != error.PathAlreadyExists) {
                return LoggerError.DirectoryCreationFailed;
            }
        };

        self.file = std.Io.Dir.createFileAbsolute(self.io, path, .{ .read = true, .truncate = false }) catch {
            return LoggerError.FileOpenFailed;
        };

        const stat = self.file.?.stat(self.io) catch {
            return LoggerError.StatFailed;
        };

        self.current_size = @intCast(stat.size);
    }

    fn rotate(self: *Logger) LoggerError!void {
        std.debug.assert(self.path_length > 0);

        if (self.file) |file| {
            file.close(self.io);
            self.file = null;
        }

        self.rotate_backups();

        self.current_size = 0;
        self.last_date = Date.current(self.io);

        self.open_file() catch {
            return LoggerError.FileOpenFailed;
        };
    }

    fn rotate_backups(self: *Logger) void {
        std.debug.assert(self.path_length > 0);
        std.debug.assert(self.path_length <= path_length_max);

        const path = self.get_path_slice();

        var index: u32 = backup_count_max;

        while (index > 0) : (index -= 1) {
            std.debug.assert(index <= backup_count_max);
            std.debug.assert(index > 0);

            var old_path_buffer: [path_with_suffix_length_max]u8 = undefined;
            var new_path_buffer: [path_with_suffix_length_max]u8 = undefined;

            const old_path = if (index == 1)
                path
            else
                std.fmt.bufPrint(&old_path_buffer, "{s}.{d}", .{ path, index - 1 }) catch continue;

            const new_path = std.fmt.bufPrint(&new_path_buffer, "{s}.{d}", .{ path, index }) catch continue;

            if (index == backup_count_max) {
                std.Io.Dir.deleteFileAbsolute(self.io, new_path) catch {};
            }

            std.Io.Dir.renameAbsolute(old_path, new_path, self.io) catch {};
        }
    }

    fn should_rotate(self: *Logger) bool {
        if (self.current_size >= self.max_size) {
            return true;
        }

        if (self.has_date_changed()) {
            return true;
        }

        return false;
    }

    fn write_timestamp(io: std.Io, writer: *std.Io.Writer) !void {
        const timestamp = std.Io.Timestamp.now(io, .real).toSeconds();
        std.debug.assert(timestamp >= 0);

        const date = Date.from_timestamp(timestamp);

        const datetime = std.time.epoch.EpochSeconds{ .secs = @intCast(timestamp) };
        const day_seconds = datetime.getDaySeconds();

        try writer.print("[{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}] ", .{
            date.year,
            date.month,
            date.day,
            day_seconds.getHoursIntoDay(),
            day_seconds.getMinutesIntoHour(),
            day_seconds.getSecondsIntoMinute(),
        });
    }

    fn write_to_file(self: *Logger, content: []const u8) void {
        std.debug.assert(content.len > 0);

        const file = self.file orelse return;
        const length: u32 = @intCast(content.len);

        file.writePositionalAll(self.io, content, self.current_size) catch {
            self.write_error_count += 1;
            return;
        };

        file.sync(self.io) catch {
            self.write_error_count += 1;
        };

        self.current_size += length;
    }
};
