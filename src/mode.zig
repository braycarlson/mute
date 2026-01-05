const std = @import("std");

const wca = @import("wca");

pub const Mode = enum {
    capture,
    render,

    pub fn to_data_flow(self: Mode) wca.EDataFlow {
        return switch (self) {
            .capture => .Capture,
            .render => .Render,
        };
    }

    pub fn to_string(self: Mode) []const u8 {
        return switch (self) {
            .capture => "capture",
            .render => "render",
        };
    }

    pub fn to_action(self: Mode, active: bool) []const u8 {
        return switch (self) {
            .capture => if (active) "Muted" else "Unmuted",
            .render => if (active) "Deafened" else "Undeafened",
        };
    }

    pub fn to_label(self: Mode, active: bool) []const u8 {
        return switch (self) {
            .capture => if (active) "Unmute" else "Mute",
            .render => if (active) "Undeafen" else "Deafen",
        };
    }

    pub fn to_title(self: Mode) []const u8 {
        return switch (self) {
            .capture => "Mute",
            .render => "Deafen",
        };
    }

    pub fn to_tray_title(self: Mode) []const u8 {
        return switch (self) {
            .capture => "Mute",
            .render => "Deafen",
        };
    }

    pub fn to_widget_class(self: Mode) [:0]const u16 {
        return switch (self) {
            .capture => std.unicode.utf8ToUtf16LeStringLiteral("MuteWidget"),
            .render => std.unicode.utf8ToUtf16LeStringLiteral("DeafenWidget"),
        };
    }

    pub fn to_widget_title(self: Mode) []const u8 {
        return switch (self) {
            .capture => "Mute",
            .render => "Deafen",
        };
    }

    pub fn to_log_filename(self: Mode) []const u8 {
        return switch (self) {
            .capture => "mute.log",
            .render => "deafen.log",
        };
    }

    pub fn to_notification_title(self: Mode) []const u8 {
        return switch (self) {
            .capture => "Microphone",
            .render => "Audio",
        };
    }

    pub fn to_notification_message(self: Mode, active: bool) []const u8 {
        return switch (self) {
            .capture => if (active) "Microphone is muted" else "Microphone is unmuted",
            .render => if (active) "Audio is deafened" else "Audio is undeafened",
        };
    }
};
