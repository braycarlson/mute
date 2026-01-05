const std = @import("std");

const w32 = @import("win32").everything;

const theme = @import("theme.zig");

const Size = theme.Size;

pub const HitRegion = enum {
    none,
    slider,
    button_prev,
    button_next,
    button_set_default,
    button_reset_default,
    button_close,
    icon_speaker,
};

pub fn close_button() w32.RECT {
    return w32.RECT{
        .left = Size.widget_width - 32,
        .top = 4,
        .right = Size.widget_width - 4,
        .bottom = 32,
    };
}

pub fn device_nav() w32.RECT {
    return w32.RECT{
        .left = Size.padding,
        .top = Size.padding + 46,
        .right = Size.widget_width - Size.padding,
        .bottom = Size.padding + 46 + Size.button_nav_size,
    };
}

pub fn prev_button() w32.RECT {
    const nav = device_nav();

    return w32.RECT{
        .left = nav.left,
        .top = nav.top,
        .right = nav.left + Size.button_nav_size,
        .bottom = nav.bottom,
    };
}

pub fn next_button() w32.RECT {
    const nav = device_nav();

    return w32.RECT{
        .left = nav.right - Size.button_nav_size,
        .top = nav.top,
        .right = nav.right,
        .bottom = nav.bottom,
    };
}

pub fn volume_header() w32.RECT {
    const base = Size.padding + 46 + Size.button_nav_size + 20;

    return w32.RECT{
        .left = Size.padding,
        .top = base,
        .right = Size.widget_width - Size.padding,
        .bottom = base + 24,
    };
}

pub fn speaker_icon() w32.RECT {
    const header = volume_header();
    const base = header.bottom;
    const center_y = base + @divTrunc(28, 2);

    return w32.RECT{
        .left = Size.padding,
        .top = center_y - @divTrunc(Size.icon_speaker_size, 2),
        .right = Size.padding + Size.icon_speaker_size,
        .bottom = center_y + @divTrunc(Size.icon_speaker_size, 2),
    };
}

pub fn slider() w32.RECT {
    const header = volume_header();
    const base = header.bottom;
    const speaker = speaker_icon();

    return w32.RECT{
        .left = speaker.right + 10,
        .top = base,
        .right = Size.widget_width - Size.padding,
        .bottom = base + 28,
    };
}

pub fn set_default_button() w32.RECT {
    const button_width = @divTrunc(Size.widget_width - Size.padding * 2 - 12, 2);

    return w32.RECT{
        .left = Size.padding,
        .top = Size.widget_height - Size.padding - Size.button_height,
        .right = Size.padding + button_width,
        .bottom = Size.widget_height - Size.padding,
    };
}

pub fn reset_default_button() w32.RECT {
    const button_width = @divTrunc(Size.widget_width - Size.padding * 2 - 12, 2);

    return w32.RECT{
        .left = Size.padding + button_width + 12,
        .top = Size.widget_height - Size.padding - Size.button_height,
        .right = Size.widget_width - Size.padding,
        .bottom = Size.widget_height - Size.padding,
    };
}

pub fn hit_test(x: i32, y: i32) HitRegion {
    if (contains_point(close_button(), x, y)) return .button_close;
    if (contains_point(speaker_icon(), x, y)) return .icon_speaker;
    if (contains_point(slider(), x, y)) return .slider;
    if (contains_point(prev_button(), x, y)) return .button_prev;
    if (contains_point(next_button(), x, y)) return .button_next;
    if (contains_point(set_default_button(), x, y)) return .button_set_default;
    if (contains_point(reset_default_button(), x, y)) return .button_reset_default;

    return .none;
}

pub fn contains_point(rect: w32.RECT, x: i32, y: i32) bool {
    std.debug.assert(rect.right >= rect.left);
    std.debug.assert(rect.bottom >= rect.top);

    return x >= rect.left and x < rect.right and y >= rect.top and y < rect.bottom;
}

pub fn center(rect: w32.RECT) struct { x: f32, y: f32 } {
    std.debug.assert(rect.right >= rect.left);
    std.debug.assert(rect.bottom >= rect.top);

    return .{
        .x = @floatFromInt(rect.left + @divTrunc(rect.right - rect.left, 2)),
        .y = @floatFromInt(rect.top + @divTrunc(rect.bottom - rect.top, 2)),
    };
}

pub fn slider_track_bounds() struct { left: f32, right: f32, width: f32 } {
    const rect = slider();
    const thumb_offset: i32 = @intFromFloat(Size.slider_thumb_radius);
    const left: f32 = @floatFromInt(rect.left + thumb_offset);
    const right: f32 = @floatFromInt(rect.right - thumb_offset);
    const width = right - left;

    std.debug.assert(width >= 0);
    std.debug.assert(right >= left);

    return .{
        .left = left,
        .right = right,
        .width = width,
    };
}

pub fn volume_from_x(x: i32) f32 {
    const track = slider_track_bounds();
    const track_left: i32 = @intFromFloat(track.left);
    const track_right: i32 = @intFromFloat(track.right);

    std.debug.assert(track_right >= track_left);

    if (track.width <= 0) {
        return 0.0;
    }

    const clamped = @as(f32, @floatFromInt(std.math.clamp(x, track_left, track_right)));
    const raw = (clamped - track.left) / track.width;
    const result = @round(raw * 100.0) / 100.0;

    std.debug.assert(result >= 0.0);
    std.debug.assert(result <= 1.0);

    return result;
}

pub fn title() w32.RECT {
    return w32.RECT{
        .left = Size.padding,
        .top = 4,
        .right = Size.widget_width - 32,
        .bottom = 32,
    };
}
