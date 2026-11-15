const std = @import("std");

const nimble = @import("nimble");

const assert = std.debug.assert;

const Keycode = nimble.Keycode;
const Kind = nimble.Modifier.Kind;
const Modifier = nimble.Modifier;

const CapacityError = error{
    KeysExhausted,
    TextTooLong,
};

const SettingsError = error{
    ChordInvalid,
    KeyInvalid,
    KeyMissing,
    TextEmpty,
};

const ParseError = CapacityError || SettingsError;
const hotkey_bytes_max: u32 = 64;
const part_bytes_max: u32 = 32;

comptime {
    assert(hotkey_bytes_max > 0);
    assert(part_bytes_max > 0);
    assert(hotkey_bytes_max > part_bytes_max);
}

pub const Binding = struct {
    key_count: u32 = 0,
    keys: [nimble.limits.remote_chord_keys_max]Keycode = @splat(.silent),
    modifiers: Modifier = .{},

    pub fn parse(text: []const u8) ParseError!Binding {
        if (text.len == 0) {
            return error.TextEmpty;
        }

        if (text.len > hotkey_bytes_max) {
            return error.TextTooLong;
        }

        var result = Binding{};
        var args = Modifier.Args{};
        var parts = std.mem.splitScalar(u8, text, '+');
        var part_count: u32 = 0;

        while (parts.next()) |part| {
            part_count += 1;

            assert(part_count <= text.len + 1);

            const trimmed = std.mem.trim(u8, part, " \t");
            if (trimmed.len == 0) continue;
            if (trimmed.len > part_bytes_max) return error.KeyInvalid;

            var lowered: [part_bytes_max]u8 = undefined;
            const name = std.ascii.lowerString(&lowered, trimmed);

            if (Kind.from_string(name)) |kind| {
                enable(&args, kind);

                continue;
            }

            const code = Keycode.from_string(name) orelse return error.KeyInvalid;

            if (result.key_count >= result.keys.len) {
                return error.KeysExhausted;
            }

            result.keys[result.key_count] = code;
            result.key_count += 1;
        }

        result.modifiers = Modifier.from(args);

        try result.validate();

        assert(result.key_count > 0);
        assert(result.key_count <= result.keys.len);

        return result;
    }

    pub fn is_chord(binding: *const Binding) bool {
        assert(binding.key_count <= binding.keys.len);

        return binding.key_count > 1;
    }

    pub fn to_keys(binding: *const Binding) []const Keycode {
        assert(binding.key_count > 1);
        assert(binding.key_count <= binding.keys.len);

        return binding.keys[0..binding.key_count];
    }

    pub fn trigger(binding: *const Binding) Keycode {
        assert(binding.key_count == 1);

        return binding.keys[0];
    }

    fn validate(binding: *const Binding) SettingsError!void {
        if (binding.key_count == 0) {
            return error.KeyMissing;
        }

        if (binding.key_count == 1) {
            return;
        }

        if (binding.modifiers.any()) {
            return error.ChordInvalid;
        }
    }
};

fn enable(args: *Modifier.Args, kind: Kind) void {
    assert(kind.is_valid());

    switch (kind) {
        .alt => args.alt = true,
        .ctrl => args.ctrl = true,
        .shift => args.shift = true,
        .win => args.win = true,
    }
}

const testing = std.testing;

test Binding {
    const single = try Binding.parse("Ctrl+Alt+M");

    try testing.expect(!single.is_chord());
    try testing.expectEqual(Keycode.m, single.trigger());
    try testing.expect(single.modifiers.ctrl());
    try testing.expect(single.modifiers.alt());
    try testing.expect(!single.modifiers.shift());

    const chord = try Binding.parse("PageUp+PageDown");

    try testing.expect(chord.is_chord());
    try testing.expectEqualSlices(Keycode, &.{ .page_up, .page_down }, chord.to_keys());
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

test "a rejected binding names whose fault it is" {
    const long: [hotkey_bytes_max + 1]u8 = @splat('A');

    try testing.expectError(error.TextEmpty, Binding.parse(""));
    try testing.expectError(error.KeyMissing, Binding.parse("Ctrl+Alt"));
    try testing.expectError(error.KeyInvalid, Binding.parse("Ctrl+Nonsense"));
    try testing.expectError(error.ChordInvalid, Binding.parse("Ctrl+A+B"));
    try testing.expectError(error.KeysExhausted, Binding.parse("A+B+C+D+E+F+G+H+I"));
    try testing.expectError(error.TextTooLong, Binding.parse(&long));
}

test "a part longer than any key or modifier name is rejected rather than trusted" {
    const long = "abcdefghijklmnopqrstuvwxyz0123456789";

    try testing.expectError(error.KeyInvalid, Binding.parse("Ctrl+abcdefghijklmnopq"));
    try testing.expectError(error.KeyInvalid, Binding.parse(long));
}

test "a chord of named keys no character can spell is accepted" {
    const parsed = try Binding.parse("PageUp+PageDown");

    try testing.expect(parsed.is_chord());
    try testing.expectEqualSlices(Keycode, &.{ .page_up, .page_down }, parsed.to_keys());
}
