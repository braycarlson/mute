const std = @import("std");

const mantra = @import("mantra");

const assert = std.debug.assert;

const Device = mantra.Device;

const limits = mantra.limits;

const row_cells_max: u32 = limits.name_bytes_max + 1;
const score_max: u32 = 20;

comptime {
    assert(row_cells_max > limits.name_bytes_max);
    assert(score_max > 0);
}

pub fn match(list: *const Device.List, name: []const u8) ?u32 {
    if (name.len == 0) {
        return null;
    }

    if (name.len > limits.name_bytes_max) {
        return null;
    }

    var best_index: ?u32 = null;
    var best_score: u32 = score_max;
    var index: u32 = 0;

    while (index < list.count) : (index += 1) {
        assert(index < limits.device_count_max);

        const candidate = list.items[index].get_name();

        if (candidate.len == 0) {
            continue;
        }

        if (candidate.len > limits.name_bytes_max) {
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

fn levenshtein_distance(source: []const u8, target: []const u8) u32 {
    assert(source.len <= limits.name_bytes_max);
    assert(target.len <= limits.name_bytes_max);

    if (source.len == 0) {
        const result: u32 = @intCast(target.len);
        assert(result == @max(source.len, target.len));

        return result;
    }

    if (target.len == 0) {
        const result: u32 = @intCast(source.len);
        assert(result == @max(source.len, target.len));

        return result;
    }

    const short = if (source.len <= target.len) source else target;
    const long = if (source.len <= target.len) target else source;
    const col: u32 = @intCast(short.len + 1);
    const row_count: u32 = @intCast(long.len);

    assert(col > 0);
    assert(col <= row_cells_max);
    assert(row_count > 0);

    var prev_row: [row_cells_max]u32 = undefined;
    var curr_row: [row_cells_max]u32 = undefined;
    var init_idx: u32 = 0;

    while (init_idx < col) : (init_idx += 1) {
        assert(init_idx < row_cells_max);

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
            assert(copy_idx < row_cells_max);

            prev_row[copy_idx] = curr_row[copy_idx];
        }
    }

    assert(row_idx == row_count + 1);

    const result = prev_row[col - 1];

    assert(result <= @max(source.len, target.len));

    return result;
}

fn fill_row(prev_row: []const u32, curr_row: []u32, short: []const u8, symbol: u8, col: u32) void {
    assert(prev_row.len >= col);
    assert(curr_row.len >= col);
    assert(prev_row.ptr != curr_row.ptr);
    assert(short.len + 1 == col);
    assert(col <= row_cells_max);

    var col_idx: u32 = 1;

    while (col_idx < col) : (col_idx += 1) {
        assert(col_idx > 0);
        assert(col_idx < col);
        assert(col_idx < row_cells_max);
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

fn seed(list: *Device.List, names: []const []const u8) !void {
    assert(names.len > 0);
    assert(names.len <= mantra.limits.device_count_max);

    for (names) |name| {
        const id = try Device.Id.init(.capture, name);

        try list.append(Device.init(id, name, .{}));
    }
}

test match {
    var list = Device.List.init();

    try seed(&list, &.{ "Speakers", "Headset (Arctis 7)", "Microphone (USB Audio)" });

    try testing.expectEqual(@as(?u32, 1), match(&list, "Headset (Arctis 7)"));
    try testing.expectEqual(@as(?u32, 1), match(&list, "Headset (Arctis 9)"));
    try testing.expect(match(&list, "Completely Different Hardware") == null);
}

test "an identical name scores zero and anything unrelated scores its length" {
    try testing.expectEqual(@as(u32, 0), levenshtein_distance("Headset", "Headset"));
    try testing.expectEqual(@as(u32, 7), levenshtein_distance("", "Headset"));
    try testing.expectEqual(@as(u32, 7), levenshtein_distance("Headset", ""));
    try testing.expectEqual(@as(u32, 1), levenshtein_distance("Headset", "Headsets"));
    try testing.expectEqual(@as(u32, 3), levenshtein_distance("kitten", "sitting"));
}

test "an empty list and an empty name match nothing" {
    var list = Device.List.init();

    try testing.expect(match(&list, "Speakers") == null);

    try seed(&list, &.{"Speakers"});

    try testing.expect(match(&list, "") == null);
}

test "the first of two equally distant names wins" {
    var list = Device.List.init();

    try seed(&list, &.{ "Device A", "Device B" });

    const found = match(&list, "Device C") orelse return error.MissingMatch;

    try testing.expectEqual(@as(u32, 0), found);
}
