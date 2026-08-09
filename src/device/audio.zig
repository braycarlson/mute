const std = @import("std");

const mantra = @import("mantra");

const assert = std.debug.assert;

const DeviceList = mantra.DeviceList;

pub const name_len_max: u32 = mantra.name_bytes_max;
pub const row_len_max: u32 = name_len_max + 1;
pub const score_max: u32 = 20;

comptime {
    assert(name_len_max > 0);
    assert(row_len_max > name_len_max);
    assert(score_max > 0);
}

pub fn match(list: *const DeviceList, name: []const u8) ?u32 {
    if (name.len == 0 or name.len > name_len_max) {
        return null;
    }

    var best_index: ?u32 = null;
    var best_score: u32 = score_max;

    var index: u32 = 0;

    while (index < list.count) : (index += 1) {
        assert(index < mantra.devices_max);

        const candidate = list.items[index].get_name();

        if (candidate.len == 0 or candidate.len > name_len_max) {
            continue;
        }

        const distance = @min(levenshtein_distance(candidate, name), score_max);

        if (distance >= best_score) {
            continue;
        }

        best_index = index;
        best_score = distance;
    }

    assert(best_index == null or best_score < score_max);

    return best_index;
}

pub fn levenshtein_distance(source: []const u8, target: []const u8) u32 {
    assert(source.len <= name_len_max);
    assert(target.len <= name_len_max);

    if (source.len == 0) {
        return @intCast(target.len);
    }

    if (target.len == 0) {
        return @intCast(source.len);
    }

    const short = if (source.len <= target.len) source else target;
    const long = if (source.len <= target.len) target else source;

    const col: u32 = @intCast(short.len + 1);
    const row_count: u32 = @intCast(long.len);

    assert(col > 0);
    assert(col <= row_len_max);
    assert(row_count > 0);

    var prev_row: [row_len_max]u32 = undefined;
    var curr_row: [row_len_max]u32 = undefined;

    var init_idx: u32 = 0;

    while (init_idx < col) : (init_idx += 1) {
        assert(init_idx < row_len_max);

        prev_row[init_idx] = init_idx;
    }

    assert(init_idx == col);

    var row_idx: u32 = 1;

    while (row_idx <= row_count) : (row_idx += 1) {
        assert(row_idx > 0);
        assert(row_idx <= row_count);
        assert(row_idx - 1 < long.len);

        curr_row[0] = row_idx;

        fill_row(&prev_row, &curr_row, short, long[row_idx - 1], col);

        var copy_idx: u32 = 0;

        while (copy_idx < col) : (copy_idx += 1) {
            assert(copy_idx < row_len_max);

            prev_row[copy_idx] = curr_row[copy_idx];
        }
    }

    assert(row_idx == row_count + 1);

    const result = prev_row[col - 1];

    assert(result <= @max(source.len, target.len));

    return result;
}

fn fill_row(prev_row: []const u32, curr_row: []u32, short: []const u8, symbol: u8, col: u32) void {
    var col_idx: u32 = 1;

    while (col_idx < col) : (col_idx += 1) {
        assert(col_idx > 0);
        assert(col_idx < col);
        assert(col_idx < row_len_max);
        assert(col_idx - 1 < short.len);

        const cost: u32 = if (symbol == short[col_idx - 1]) 0 else 1;

        const deletion = prev_row[col_idx] + 1;
        const insertion = curr_row[col_idx - 1] + 1;
        const substitution = prev_row[col_idx - 1] + cost;

        curr_row[col_idx] = @min(@min(deletion, insertion), substitution);
    }

    assert(col_idx == col);
}

const testing = std.testing;

fn seed(list: *DeviceList, names: []const []const u8) !void {
    for (names) |name| {
        const id = try mantra.DeviceId.init(.capture, name);

        try list.append(mantra.DeviceInfo.init(id, name, false));
    }
}

test "an identical name scores zero and anything unrelated scores its length" {
    try testing.expectEqual(@as(u32, 0), levenshtein_distance("Headset", "Headset"));
    try testing.expectEqual(@as(u32, 7), levenshtein_distance("", "Headset"));
    try testing.expectEqual(@as(u32, 7), levenshtein_distance("Headset", ""));
    try testing.expectEqual(@as(u32, 1), levenshtein_distance("Headset", "Headsets"));
    try testing.expectEqual(@as(u32, 3), levenshtein_distance("kitten", "sitting"));
}

test "the closest device name wins the match" {
    var list = DeviceList.init();

    try seed(&list, &.{ "Speakers", "Headset (Arctis 7)", "Microphone (USB Audio)" });

    const found = match(&list, "Headset (Arctis 7)") orelse return error.MissingMatch;

    try testing.expectEqual(@as(u32, 1), found);
}

test "a near miss still matches inside the score bound" {
    var list = DeviceList.init();

    try seed(&list, &.{ "Speakers", "Headset (Arctis 7)" });

    const found = match(&list, "Headset (Arctis 9)") orelse return error.MissingMatch;

    try testing.expectEqual(@as(u32, 1), found);
}

test "a name further away than the score bound matches nothing" {
    var list = DeviceList.init();

    try seed(&list, &.{"Speakers"});

    try testing.expect(match(&list, "Completely Different Hardware") == null);
}

test "an empty list and an empty name match nothing" {
    var list = DeviceList.init();

    try testing.expect(match(&list, "Speakers") == null);

    try seed(&list, &.{"Speakers"});

    try testing.expect(match(&list, "") == null);
}

test "the first of two equally distant names wins" {
    var list = DeviceList.init();

    try seed(&list, &.{ "Device A", "Device B" });

    const found = match(&list, "Device C") orelse return error.MissingMatch;

    try testing.expectEqual(@as(u32, 0), found);
}
