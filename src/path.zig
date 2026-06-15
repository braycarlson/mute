const std = @import("std");

const win32 = @import("win32").everything;

pub const path_length_max: u32 = 512;
pub const appdata_length_max: u32 = 256;

pub const PathError = error{
    AppDataNotFound,
    PathTooLong,
};

pub fn get_appdata_path(buffer: *[path_length_max]u8, subfolder: []const u8) PathError![]const u8 {
    std.debug.assert(subfolder.len > 0);
    std.debug.assert(subfolder.len < path_length_max);

    var appdata_buffer: [appdata_length_max]u8 = undefined;

    const appdata = get_local_appdata_path(&appdata_buffer) orelse {
        return PathError.AppDataNotFound;
    };

    std.debug.assert(appdata.len > 0);
    std.debug.assert(appdata.len < appdata_length_max);

    return join_path(buffer, appdata, subfolder) orelse PathError.PathTooLong;
}

pub fn join_path(buffer: *[path_length_max]u8, base: []const u8, filename: []const u8) ?[]const u8 {
    std.debug.assert(base.len > 0);
    std.debug.assert(filename.len > 0);

    const base_length: u32 = @intCast(base.len);
    const filename_length: u32 = @intCast(filename.len);
    const total_length = base_length + 1 + filename_length;

    if (total_length >= path_length_max) {
        return null;
    }

    @memcpy(buffer[0..base_length], base);
    buffer[base_length] = '\\';
    @memcpy(buffer[base_length + 1 ..][0..filename_length], filename);

    return buffer[0..total_length];
}

pub fn ensure_directory_exists(io: std.Io, path: []const u8) PathError!void {
    std.debug.assert(path.len > 0);
    std.debug.assert(path.len < path_length_max);

    const directory = std.fs.path.dirname(path) orelse {
        return PathError.PathTooLong;
    };

    std.debug.assert(directory.len > 0);
    std.debug.assert(directory.len < path.len);

    std.Io.Dir.createDirAbsolute(io, directory, .default_dir) catch |err| {
        if (err != error.PathAlreadyExists) {
            return PathError.PathTooLong;
        }
    };
}

fn get_local_appdata_path(buffer: *[appdata_length_max]u8) ?[]const u8 {
    var wide_buffer: [appdata_length_max:0]u16 = undefined;

    const wide_length = win32.GetEnvironmentVariableW(
        std.unicode.utf8ToUtf16LeStringLiteral("LOCALAPPDATA"),
        &wide_buffer,
        wide_buffer.len + 1,
    );

    if (wide_length == 0 or wide_length >= appdata_length_max) {
        return null;
    }

    const env_wide = wide_buffer[0..wide_length];

    std.debug.assert(env_wide.len > 0);

    const utf8_length = std.unicode.utf16LeToUtf8(buffer, env_wide) catch {
        return null;
    };

    if (utf8_length == 0) {
        return null;
    }

    return buffer[0..utf8_length];
}
