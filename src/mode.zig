const mantra = @import("mantra");

pub const Mode = enum {
    capture,
    render,

    pub fn to_direction(mode: Mode) mantra.Direction {
        return switch (mode) {
            .capture => .capture,
            .render => .render,
        };
    }

    pub fn to_string(mode: Mode) []const u8 {
        return switch (mode) {
            .capture => "capture",
            .render => "render",
        };
    }

    pub fn to_action(mode: Mode, active: bool) []const u8 {
        return switch (mode) {
            .capture => if (active) "Muted" else "Unmuted",
            .render => if (active) "Deafened" else "Undeafened",
        };
    }

    pub fn to_label(mode: Mode, active: bool) []const u8 {
        return switch (mode) {
            .capture => if (active) "Unmute" else "Mute",
            .render => if (active) "Undeafen" else "Deafen",
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

    pub fn to_log_filename(mode: Mode) []const u8 {
        return switch (mode) {
            .capture => "mute.log",
            .render => "deafen.log",
        };
    }

    pub fn to_notification_title(mode: Mode) []const u8 {
        return switch (mode) {
            .capture => "Microphone",
            .render => "Audio",
        };
    }

    pub fn to_notification_message(mode: Mode, active: bool) []const u8 {
        return switch (mode) {
            .capture => if (active) "Microphone is muted" else "Microphone is unmuted",
            .render => if (active) "Audio is deafened" else "Audio is undeafened",
        };
    }
};
