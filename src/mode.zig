const std = @import("std");

const mantra = @import("mantra");

const State = @import("state.zig").State;

pub const Mode = enum {
    capture,
    render,

    pub fn to_action(mode: Mode, state: State) []const u8 {
        return switch (mode) {
            .capture => switch (state) {
                .active => "Muted",
                .inactive => "Unmuted",
            },
            .render => switch (state) {
                .active => "Deafened",
                .inactive => "Undeafened",
            },
        };
    }

    pub fn to_direction(mode: Mode) mantra.Direction {
        return switch (mode) {
            .capture => .capture,
            .render => .render,
        };
    }

    pub fn to_log_filename(mode: Mode) []const u8 {
        return switch (mode) {
            .capture => "mute.log",
            .render => "deafen.log",
        };
    }

    pub fn to_string(mode: Mode) []const u8 {
        return switch (mode) {
            .capture => "capture",
            .render => "render",
        };
    }

    pub fn to_title(mode: Mode) []const u8 {
        return switch (mode) {
            .capture => "Mute",
            .render => "Deafen",
        };
    }

    pub fn to_widget_name(mode: Mode) []const u8 {
        return switch (mode) {
            .capture => "mute-widget",
            .render => "deafen-widget",
        };
    }
};

const testing = std.testing;

test Mode {
    try testing.expectEqualStrings("Muted", Mode.capture.to_action(.active));
    try testing.expectEqualStrings("Undeafened", Mode.render.to_action(.inactive));
    try testing.expectEqual(mantra.Direction.render, Mode.render.to_direction());
    try testing.expectEqualStrings("mute.log", Mode.capture.to_log_filename());
    try testing.expectEqualStrings("render", Mode.render.to_string());
    try testing.expectEqualStrings("Deafen", Mode.render.to_title());
    try testing.expectEqualStrings("mute-widget", Mode.capture.to_widget_name());
}
