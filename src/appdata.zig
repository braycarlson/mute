const std = @import("std");

const w32 = @import("win32").everything;

const appdata_len_max: u32 = 260;

pub fn get_app_data_dir(allocator: std.mem.Allocator, app_name: []const u8) ![]u8 {
    std.debug.assert(app_name.len > 0);

    var wide_buffer: [appdata_len_max:0]u16 = undefined;

    const wide_length = w32.GetEnvironmentVariableW(
        std.unicode.utf8ToUtf16LeStringLiteral("LOCALAPPDATA"),
        &wide_buffer,
        wide_buffer.len + 1,
    );

    if (wide_length == 0 or wide_length > wide_buffer.len) {
        return error.AppDataNotFound;
    }

    var utf8_buffer: [appdata_len_max * 3]u8 = undefined;
    const utf8_length = try std.unicode.utf16LeToUtf8(&utf8_buffer, wide_buffer[0..wide_length]);

    const result = try std.fs.path.join(allocator, &[_][]const u8{ utf8_buffer[0..utf8_length], app_name });

    return result;
}
