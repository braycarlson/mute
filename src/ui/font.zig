const std = @import("std");

const atlas = @import("atlas.zig");

const assert = std.debug.assert;

const Glyph = atlas.Glyph;

pub const advance_scale: i32 = atlas.advance_scale;
pub const replacement: u21 = 0xFFFD;

pub const bold_small_mask = @embedFile("atlas_bold_small.a8");
pub const regular_large_mask = @embedFile("atlas_regular_large.a8");
pub const regular_small_mask = @embedFile("atlas_regular_small.a8");

comptime {
    assert(advance_scale > 0);
    assert(@rem(advance_scale, 2) == 0);
    assert(atlas.glyph_count > 0);
    assert(atlas.fallback_index == atlas.glyph_count - 1);
    assert(bold_small_mask.len == atlas.atlas_width * atlas.bold_small.height);
    assert(regular_large_mask.len == atlas.atlas_width * atlas.regular_large.height);
    assert(regular_small_mask.len == atlas.atlas_width * atlas.regular_small.height);
}

pub const Face = enum {
    regular_small,
    bold_small,
    regular_large,

    pub fn ascent(face: Face) i32 {
        const result: i32 = switch (face) {
            .regular_small => atlas.regular_small.ascent,
            .bold_small => atlas.bold_small.ascent,
            .regular_large => atlas.regular_large.ascent,
        };

        assert(result > 0);

        return result;
    }

    pub fn line_height(face: Face) i32 {
        const result: i32 = switch (face) {
            .regular_small => atlas.regular_small.line_height,
            .bold_small => atlas.bold_small.line_height,
            .regular_large => atlas.regular_large.line_height,
        };

        assert(result > 0);

        return result;
    }

    pub fn mask(face: Face) []const u8 {
        const result: []const u8 = switch (face) {
            .regular_small => regular_small_mask,
            .bold_small => bold_small_mask,
            .regular_large => regular_large_mask,
        };

        assert(result.len > 0);

        return result;
    }

    pub fn mask_height(face: Face) u32 {
        const result: u32 = switch (face) {
            .regular_small => atlas.regular_small.height,
            .bold_small => atlas.bold_small.height,
            .regular_large => atlas.regular_large.height,
        };

        assert(result > 0);

        return result;
    }

    pub fn glyph(face: Face, codepoint: u21) Glyph {
        const index = index_of(codepoint);

        assert(index < atlas.glyph_count);

        const result = switch (face) {
            .regular_small => atlas.regular_small.glyphs[index],
            .bold_small => atlas.bold_small.glyphs[index],
            .regular_large => atlas.regular_large.glyphs[index],
        };

        return result;
    }
};

pub fn index_of(codepoint: u21) u32 {
    if (codepoint >= atlas.ascii_first and codepoint <= atlas.ascii_last) {
        return codepoint - atlas.ascii_first;
    }

    if (codepoint >= atlas.latin_first and codepoint <= atlas.latin_last) {
        const offset = atlas.ascii_last - atlas.ascii_first + 1;

        return offset + (codepoint - atlas.latin_first);
    }

    return atlas.fallback_index;
}

pub fn decode(text: []const u8, cursor: *usize) u21 {
    assert(cursor.* < text.len);

    const length = std.unicode.utf8ByteSequenceLength(text[cursor.*]) catch {
        cursor.* += 1;

        return replacement;
    };

    if (cursor.* + length > text.len) {
        cursor.* = text.len;

        return replacement;
    }

    const value = std.unicode.utf8Decode(text[cursor.*..][0..length]) catch {
        cursor.* += length;

        return replacement;
    };

    cursor.* += length;

    return value;
}

pub fn measure(face: Face, text: []const u8) i32 {
    const result = to_pixels(measure_scaled(face, text));

    assert(result >= 0);

    return result;
}

pub fn measure_scaled(face: Face, text: []const u8) i32 {
    var cursor: usize = 0;
    var total: i32 = 0;

    while (cursor < text.len) {
        const codepoint = decode(text, &cursor);

        total += face.glyph(codepoint).advance_scaled;
    }

    assert(total >= 0);

    return total;
}

pub fn to_pixels(scaled: i32) i32 {
    const half = @divExact(advance_scale, 2);

    return @divFloor(scaled + half, advance_scale);
}

pub fn fit(face: Face, text: []const u8, budget: i32) usize {
    assert(budget >= 0);

    var cursor: usize = 0;
    var total: i32 = 0;

    while (cursor < text.len) {
        const previous = cursor;
        const codepoint = decode(text, &cursor);

        total += face.glyph(codepoint).advance_scaled;

        if (to_pixels(total) > budget) {
            return previous;
        }
    }

    return text.len;
}

const testing = std.testing;

test "every printable ascii codepoint maps to its own glyph" {
    try testing.expectEqual(@as(u32, 0), index_of(' '));
    try testing.expectEqual(@as(u32, 1), index_of('!'));
    try testing.expectEqual(@as(u32, 'A' - 0x20), index_of('A'));
    try testing.expectEqual(@as(u32, '~' - 0x20), index_of('~'));
}

test "latin one letters land after the ascii block" {
    const offset = atlas.ascii_last - atlas.ascii_first + 1;

    try testing.expectEqual(offset, index_of(0xA0));
    try testing.expectEqual(offset + 0x5F, index_of(0xFF));
}

test "anything outside the atlas falls back to the visible replacement" {
    try testing.expectEqual(atlas.fallback_index, index_of(0x4E2D));
    try testing.expectEqual(atlas.fallback_index, index_of(0x1F50A));
    try testing.expectEqual(atlas.fallback_index, index_of(0x1F));
    try testing.expectEqual(atlas.fallback_index, index_of(0x9F));
}

test "a malformed byte decodes to the replacement without consuming the rest" {
    const text = [_]u8{ 'a', 0xFF, 'b' };

    var cursor: usize = 0;

    try testing.expectEqual(@as(u21, 'a'), decode(&text, &cursor));
    try testing.expectEqual(replacement, decode(&text, &cursor));
    try testing.expectEqual(@as(u21, 'b'), decode(&text, &cursor));
    try testing.expectEqual(text.len, cursor);
}

test "a truncated sequence decodes to the replacement and stops" {
    const text = [_]u8{ 0xE2, 0x82 };

    var cursor: usize = 0;

    try testing.expectEqual(replacement, decode(&text, &cursor));
    try testing.expectEqual(text.len, cursor);
}

test "a multi byte codepoint decodes whole" {
    const text = "\u{00E9}\u{20AC}";

    var cursor: usize = 0;

    try testing.expectEqual(@as(u21, 0xE9), decode(text, &cursor));
    try testing.expectEqual(@as(u21, 0x20AC), decode(text, &cursor));
    try testing.expectEqual(text.len, cursor);
}

test "measuring grows with the text and is zero when empty" {
    const short = measure(.regular_small, "Hi");
    const long = measure(.regular_small, "Hi there");

    try testing.expectEqual(@as(i32, 0), measure(.regular_small, ""));
    try testing.expect(short > 0);
    try testing.expect(long > short);
}

test "the bold face is never narrower than the regular face" {
    try testing.expect(measure(.bold_small, "Volume") >= measure(.regular_small, "Volume"));
}

test "fitting stops at the last glyph that stays inside the budget" {
    const text = "Microphone";
    const full = measure(.regular_small, text);

    try testing.expectEqual(text.len, fit(.regular_small, text, full));
    try testing.expectEqual(@as(usize, 0), fit(.regular_small, text, 0));
    try testing.expect(fit(.regular_small, text, @divTrunc(full, 2)) < text.len);
}

test "every face carries a positive ascent and a mask the metrics agree with" {
    const faces = [_]Face{ .regular_small, .bold_small, .regular_large };

    for (faces) |face| {
        try testing.expect(face.ascent() > 0);
        try testing.expect(face.line_height() > 0);
        try testing.expectEqual(face.mask().len, atlas.atlas_width * face.mask_height());
    }
}
