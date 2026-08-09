const std = @import("std");

const nimble = @import("nimble");

const assert = std.debug.assert;

const Keycode = nimble.Keycode;
const Kind = nimble.modifier.Kind;
const Set = nimble.Modifier;

pub const Error = error{
    Empty,
    ModifierOnly,
    TooLong,
    TooManyKeys,
    UnknownKey,
    Unrepresentable,
};

pub const key_max: u32 = 8;
pub const part_bytes_max: u32 = 32;
pub const text_bytes_max: u32 = 64;

comptime {
    assert(key_max > 1);
    assert(part_bytes_max > 0);
    assert(text_bytes_max > part_bytes_max);
}

pub const Binding = struct {
    key_count: u32 = 0,
    keys: [key_max]Keycode = [_]Keycode{.silent} ** key_max,
    modifiers: Set = .{},

    pub fn parse(text: []const u8) Error!Binding {
        if (text.len == 0) {
            return Error.Empty;
        }

        if (text.len > text_bytes_max) {
            return Error.TooLong;
        }

        var result = Binding{};
        var args = Set.Args{};
        var parts = std.mem.splitScalar(u8, text, '+');

        while (parts.next()) |part| {
            const trimmed = std.mem.trim(u8, part, " \t");

            if (trimmed.len == 0) {
                continue;
            }

            if (trimmed.len > part_bytes_max) {
                return Error.TooLong;
            }

            var lowered: [part_bytes_max]u8 = undefined;
            const name = to_lower(&lowered, trimmed);

            if (Kind.from_string(name)) |kind| {
                enable(&args, kind);

                continue;
            }

            const code = Keycode.from_string(name) orelse {
                return Error.UnknownKey;
            };

            if (result.key_count >= key_max) {
                return Error.TooManyKeys;
            }

            result.keys[result.key_count] = code;
            result.key_count += 1;
        }

        result.modifiers = Set.from(args);

        try result.validate();

        assert(result.key_count > 0);
        assert(result.key_count <= key_max);

        return result;
    }

    pub fn is_chord(binding: *const Binding) bool {
        assert(binding.key_count <= key_max);

        return binding.key_count > 1;
    }

    pub fn trigger(binding: *const Binding) Keycode {
        assert(binding.key_count == 1);

        return binding.keys[0];
    }

    pub fn to_keys(binding: *const Binding) []const Keycode {
        assert(binding.key_count > 1);
        assert(binding.key_count <= key_max);

        return binding.keys[0..binding.key_count];
    }

    pub fn to_text(binding: *const Binding, buffer: []u8) Error![]const u8 {
        assert(binding.key_count > 0);
        assert(binding.key_count <= key_max);

        var length: usize = 0;

        for (binding.modifiers.to_array()) |entry| {
            const kind = entry orelse continue;

            length = try append(buffer, length, kind.to_string());
        }

        var index: u32 = 0;

        while (index < binding.key_count) : (index += 1) {
            assert(index < key_max);

            var character: [1]u8 = undefined;

            const code = binding.keys[index];

            const name = code.to_name() orelse blk: {
                character[0] = code.to_char() orelse return Error.Unrepresentable;

                break :blk character[0..1];
            };

            length = try append(buffer, length, name);
        }

        assert(index == binding.key_count);
        assert(length > 0);

        return buffer[0..length];
    }

    fn validate(binding: *const Binding) Error!void {
        if (binding.key_count == 0) {
            return Error.ModifierOnly;
        }

        if (binding.key_count == 1) {
            return;
        }

        if (binding.modifiers.any()) {
            return Error.Unrepresentable;
        }
    }
};

fn append(buffer: []u8, length: usize, text: []const u8) Error!usize {
    assert(text.len > 0);

    const separator: usize = if (length == 0) 0 else 1;
    const total = length + separator + text.len;

    if (total > buffer.len) {
        return Error.TooLong;
    }

    if (separator == 1) {
        buffer[length] = '+';
    }

    @memcpy(buffer[length + separator ..][0..text.len], text);

    assert(total <= buffer.len);

    return total;
}

fn enable(args: *Set.Args, kind: Kind) void {
    assert(kind.is_valid());

    switch (kind) {
        .alt => args.alt = true,
        .ctrl => args.ctrl = true,
        .shift => args.shift = true,
        .win => args.win = true,
    }
}

fn to_lower(buffer: *[part_bytes_max]u8, text: []const u8) []const u8 {
    assert(text.len > 0);
    assert(text.len <= part_bytes_max);

    var index: usize = 0;

    while (index < text.len) : (index += 1) {
        assert(index < part_bytes_max);

        buffer[index] = std.ascii.toLower(text[index]);
    }

    assert(index == text.len);

    return buffer[0..text.len];
}

const testing = std.testing;

test "a modifier binding parses into a trigger and a modifier set" {
    const parsed = try Binding.parse("Ctrl+Alt+M");

    try testing.expectEqual(@as(u32, 1), parsed.key_count);
    try testing.expectEqual(Keycode.m, parsed.trigger());
    try testing.expect(parsed.modifiers.ctrl());
    try testing.expect(parsed.modifiers.alt());
    try testing.expect(!parsed.modifiers.shift());
    try testing.expect(!parsed.is_chord());
}

test "parsing is case insensitive and tolerates spaces" {
    const parsed = try Binding.parse(" control + ALT + m ");

    try testing.expectEqual(Keycode.m, parsed.trigger());
    try testing.expect(parsed.modifiers.ctrl());
    try testing.expect(parsed.modifiers.alt());
}

test "a named key without modifiers is a single trigger" {
    const parsed = try Binding.parse("PageDown");

    try testing.expectEqual(@as(u32, 1), parsed.key_count);
    try testing.expectEqual(Keycode.page_down, parsed.trigger());
    try testing.expect(!parsed.modifiers.any());
}

test "a character sequence parses as a chord" {
    const parsed = try Binding.parse("A+B");

    try testing.expect(parsed.is_chord());
    try testing.expectEqual(@as(u32, 2), parsed.key_count);
    try testing.expectEqualSlices(Keycode, &.{ .a, .b }, parsed.to_keys());
}

test "an empty binding is rejected" {
    try testing.expectError(Error.Empty, Binding.parse(""));
}

test "a modifier without a trigger is rejected" {
    try testing.expectError(Error.ModifierOnly, Binding.parse("Ctrl+Alt"));
}

test "an unknown key name is rejected" {
    try testing.expectError(Error.UnknownKey, Binding.parse("Ctrl+Nonsense"));
}

test "a chord of named keys no character can spell is accepted" {
    const parsed = try Binding.parse("PageUp+PageDown");

    try testing.expect(parsed.is_chord());
    try testing.expectEqualSlices(Keycode, &.{ .page_up, .page_down }, parsed.to_keys());
}

test "a chord with modifiers is rejected" {
    try testing.expectError(Error.Unrepresentable, Binding.parse("Ctrl+A+B"));
}

test "an over long binding is rejected" {
    const text = "A" ** (text_bytes_max + 1);

    try testing.expectError(Error.TooLong, Binding.parse(text));
}

test "text round trips through the parser" {
    var buffer: [text_bytes_max]u8 = undefined;

    const parsed = try Binding.parse("ctrl+alt+m");
    const text = try parsed.to_text(&buffer);

    try testing.expectEqualStrings("Ctrl+Alt+M", text);

    const again = try Binding.parse(text);

    try testing.expectEqual(parsed.key_count, again.key_count);
    try testing.expectEqual(parsed.trigger(), again.trigger());
    try testing.expectEqual(parsed.modifiers.to_bits(), again.modifiers.to_bits());
}

test "a named key round trips through the formatter" {
    var buffer: [text_bytes_max]u8 = undefined;

    const parsed = try Binding.parse("pageup");

    try testing.expectEqualStrings("PageUp", try parsed.to_text(&buffer));
}

test "a chord round trips through the formatter" {
    var buffer: [text_bytes_max]u8 = undefined;

    const parsed = try Binding.parse("a+b+c");

    try testing.expectEqualStrings("A+B+C", try parsed.to_text(&buffer));
}

test "a formatting buffer that is too small is reported" {
    var buffer: [2]u8 = undefined;

    const parsed = try Binding.parse("Ctrl+Alt+M");

    try testing.expectError(Error.TooLong, parsed.to_text(&buffer));
}
