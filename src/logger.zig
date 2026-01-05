const std = @import("std");

pub const Config = struct {
    path: []const u8,
    size: usize = 5 * 1024 * 1024,
};

pub const Logger = struct {
    const backup_count_max: u32 = 5;
    const buffer_size: u32 = 4096;
    const path_len_max: u32 = 512;
    const path_with_suffix_len_max: u32 = path_len_max + 8;
    const timestamp_buffer_size: u32 = 32;

    const Date = struct {
        day: u5,
        month: u4,
        year: u16,

        fn eql(self: Date, other: Date) bool {
            return self.year == other.year and
                self.month == other.month and
                self.day == other.day;
        }
    };

    current_size: u32 = 0,
    file: ?std.fs.File = null,
    last_date: ?Date = null,
    max_size: usize = 5 * 1024 * 1024,
    mutex: std.Thread.Mutex = .{},
    path: [path_len_max]u8 = [_]u8{0} ** path_len_max,
    path_len: u32 = 0,
    write_error_count: u32 = 0,

    pub fn init(cfg: Config) !Logger {
        std.debug.assert(cfg.path.len > 0);
        std.debug.assert(cfg.path.len <= path_len_max);

        const length: u32 = @intCast(cfg.path.len);

        if (length == 0 or length > path_len_max) {
            return error.InvalidPath;
        }

        var self = Logger{
            .max_size = cfg.size,
        };

        @memcpy(self.path[0..length], cfg.path);
        self.path_len = length;

        std.debug.assert(self.path_len == length);
        std.debug.assert(self.path_len > 0);

        try self.open_file();

        return self;
    }

    pub fn deinit(self: *Logger) void {
        std.debug.assert(self.path_len <= path_len_max);

        if (self.file) |file| {
            file.close();
            self.file = null;
        }
    }

    pub fn log(self: *Logger, comptime format: []const u8, args: anytype) void {
        std.debug.assert(self.path_len > 0);
        std.debug.assert(self.path_len <= path_len_max);

        self.mutex.lock();
        defer self.mutex.unlock();

        if (!self.ensure_file_ready()) {
            return;
        }

        var buffer: [buffer_size]u8 = undefined;

        const slice = self.format_message(&buffer, format, args) orelse return;

        std.debug.assert(slice.len > 0);
        std.debug.assert(slice.len <= buffer_size);

        self.write_to_file(slice);
    }

    fn ensure_file_ready(self: *Logger) bool {
        std.debug.assert(self.path_len > 0);
        std.debug.assert(self.path_len <= path_len_max);

        if (self.should_rotate()) {
            self.rotate() catch {
                self.write_error_count += 1;
                return false;
            };
        }

        if (self.file == null) {
            self.write_error_count += 1;
            return false;
        }

        return true;
    }

    fn format_message(
        self: *Logger,
        buffer: *[buffer_size]u8,
        comptime format: []const u8,
        args: anytype,
    ) ?[]u8 {
        _ = self;

        const timestamp = get_timestamp() catch return null;

        var stream = std.io.fixedBufferStream(buffer);
        const writer = stream.writer();

        writer.print("{s} ", .{timestamp}) catch return null;
        writer.print(format, args) catch return null;
        writer.writeByte('\n') catch return null;

        const result = stream.getWritten();

        std.debug.assert(result.len > 0);
        std.debug.assert(result.len <= buffer_size);

        return result;
    }

    fn write_to_file(self: *Logger, data: []const u8) void {
        std.debug.assert(data.len > 0);
        std.debug.assert(data.len <= buffer_size);

        const file = self.file orelse return;

        file.writeAll(data) catch {
            self.write_error_count += 1;
            return;
        };

        self.current_size += @intCast(data.len);
    }

    fn should_rotate(self: *Logger) bool {
        const today = get_current_date() catch return false;

        if (self.last_date) |last| {
            if (!last.eql(today)) {
                return true;
            }
        }

        if (self.current_size >= self.max_size) {
            return true;
        }

        return false;
    }

    fn rotate(self: *Logger) !void {
        std.debug.assert(self.path_len > 0);
        std.debug.assert(self.path_len <= path_len_max);

        if (self.file) |file| {
            file.close();
            self.file = null;
        }

        try self.rotate_backups();
        try self.open_file();
    }

    fn rotate_backups(self: *Logger) !void {
        std.debug.assert(self.path_len > 0);
        std.debug.assert(self.path_len <= path_len_max);

        const path = self.path[0..self.path_len];

        var i: u32 = backup_count_max;
        while (i > 0) : (i -= 1) {
            std.debug.assert(i <= backup_count_max);
            std.debug.assert(i > 0);

            var old_path: [path_with_suffix_len_max]u8 = undefined;
            var new_path: [path_with_suffix_len_max]u8 = undefined;

            const old_len = if (i == 1)
                std.fmt.bufPrint(&old_path, "{s}", .{path}) catch continue
            else
                std.fmt.bufPrint(&old_path, "{s}.{d}", .{ path, i - 1 }) catch continue;

            const new_len = std.fmt.bufPrint(&new_path, "{s}.{d}", .{ path, i }) catch continue;

            std.fs.renameAbsolute(old_path[0..old_len.len], new_path[0..new_len.len]) catch {};
        }

        std.debug.assert(i == 0);
    }

    fn open_file(self: *Logger) !void {
        std.debug.assert(self.path_len > 0);
        std.debug.assert(self.path_len <= path_len_max);

        const path = self.path[0..self.path_len];

        self.ensure_directory(path);

        self.file = std.fs.createFileAbsolute(path, .{
            .truncate = false,
        }) catch |err| {
            return err;
        };

        if (self.file) |file| {
            const stat = file.stat() catch {
                self.current_size = 0;
                return;
            };

            self.current_size = @intCast(stat.size);

            file.seekFromEnd(0) catch {};
        }

        self.last_date = get_current_date() catch null;
    }

    fn ensure_directory(self: *Logger, path: []const u8) void {
        _ = self;

        std.debug.assert(path.len > 0);
        std.debug.assert(path.len <= path_len_max);

        const dir = std.fs.path.dirname(path) orelse return;

        std.fs.makeDirAbsolute(dir) catch {};
    }

    fn get_current_date() !Date {
        const timestamp = std.time.timestamp();
        const epoch = std.time.epoch.EpochSeconds{ .secs = @intCast(timestamp) };
        const day = epoch.getEpochDay();
        const year_day = day.calculateYearDay();
        const month_day = year_day.calculateMonthDay();

        return Date{
            .year = year_day.year,
            .month = month_day.month.numeric(),
            .day = @intCast(month_day.day_index + 1),
        };
    }

    fn get_timestamp() ![]const u8 {
        const timestamp = std.time.timestamp();
        const epoch = std.time.epoch.EpochSeconds{ .secs = @intCast(timestamp) };
        const day = epoch.getEpochDay();
        const year_day = day.calculateYearDay();
        const month_day = year_day.calculateMonthDay();
        const day_seconds = epoch.getDaySeconds();

        const State = struct {
            var buffer: [timestamp_buffer_size]u8 = undefined;
        };

        const result = std.fmt.bufPrint(&State.buffer, "{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}", .{
            year_day.year,
            month_day.month.numeric(),
            month_day.day_index + 1,
            day_seconds.getHoursIntoDay(),
            day_seconds.getMinutesIntoHour(),
            day_seconds.getSecondsIntoMinute(),
        }) catch return error.FormatFailed;

        return result;
    }
};
