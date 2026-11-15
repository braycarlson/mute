const std = @import("std");

const kalymma = @import("kalymma");

const rect = @import("rect.zig");
const theme = @import("theme.zig");

const assert = std.debug.assert;

const Rect = rect.Rect;

const size = theme.size;

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

const Track = struct {
    left: f32,
    right: f32,
    width: f32,
};

const footer_gap: i32 = 12;
const navigation_offset: i32 = 46;
const slider_row_height: i32 = 28;

comptime {
    for (regions()) |region| {
        assert(region.is_valid());
        assert(region.left >= 0);
        assert(region.top >= 0);
        assert(region.right <= size.widget_width);
        assert(region.bottom <= size.widget_height);
    }
}

pub fn close_button() Rect {
    return Rect{
        .left = size.widget_width - 32,
        .top = 4,
        .right = size.widget_width - 4,
        .bottom = 32,
    };
}

pub fn device_nav() Rect {
    const top = size.padding + navigation_offset;

    return Rect{
        .left = size.padding,
        .top = top,
        .right = size.widget_width - size.padding,
        .bottom = top + size.button_nav,
    };
}

pub fn hit_test(point: kalymma.Point) HitRegion {
    assert(rect.is_position(point));

    if (close_button().contains(point)) return .button_close;
    if (speaker_icon().contains(point)) return .icon_speaker;
    if (slider().contains(point)) return .slider;
    if (prev_button().contains(point)) return .button_prev;
    if (next_button().contains(point)) return .button_next;
    if (set_default_button().contains(point)) return .button_set_default;
    if (reset_default_button().contains(point)) return .button_reset_default;
    return .none;
}

pub fn next_button() Rect {
    const nav = device_nav();

    return Rect{
        .left = nav.right - size.button_nav,
        .top = nav.top,
        .right = nav.right,
        .bottom = nav.bottom,
    };
}

pub fn prev_button() Rect {
    const nav = device_nav();

    return Rect{
        .left = nav.left,
        .top = nav.top,
        .right = nav.left + size.button_nav,
        .bottom = nav.bottom,
    };
}

pub fn reset_default_button() Rect {
    const button_width = footer_button_width();

    return Rect{
        .left = size.padding + button_width + footer_gap,
        .top = size.widget_height - size.padding - size.button_height,
        .right = size.widget_width - size.padding,
        .bottom = size.widget_height - size.padding,
    };
}

pub fn set_default_button() Rect {
    const button_width = footer_button_width();

    return Rect{
        .left = size.padding,
        .top = size.widget_height - size.padding - size.button_height,
        .right = size.padding + button_width,
        .bottom = size.widget_height - size.padding,
    };
}

pub fn slider() Rect {
    const header = volume_header();
    const speaker = speaker_icon();

    return Rect{
        .left = speaker.right + 10,
        .top = header.bottom,
        .right = size.widget_width - size.padding,
        .bottom = header.bottom + slider_row_height,
    };
}

pub fn slider_track_bounds() Track {
    const bounds = slider();
    const thumb_offset: i32 = @intFromFloat(size.slider_thumb_radius);
    const left: f32 = @floatFromInt(bounds.left + thumb_offset);
    const right: f32 = @floatFromInt(bounds.right - thumb_offset);
    const width = right - left;

    assert(width >= 0);
    assert(right >= left);

    return .{ .left = left, .right = right, .width = width };
}

pub fn speaker_icon() Rect {
    const header = volume_header();
    const center_y = header.bottom + @divTrunc(slider_row_height, 2);
    const half = @divTrunc(size.icon_speaker, 2);

    return Rect{
        .left = size.padding,
        .top = center_y - half,
        .right = size.padding + size.icon_speaker,
        .bottom = center_y + half,
    };
}

pub fn title() Rect {
    return Rect{ .left = size.padding, .top = 4, .right = size.widget_width - 32, .bottom = 32 };
}

pub fn volume_from_x(x: i32) f32 {
    assert(rect.is_coordinate(x));

    const track = slider_track_bounds();
    const track_left: i32 = @intFromFloat(track.left);
    const track_right: i32 = @intFromFloat(track.right);

    assert(track_right >= track_left);

    if (track.width <= 0) {
        return 0.0;
    }

    const clamped = @as(f32, @floatFromInt(std.math.clamp(x, track_left, track_right)));
    const raw = (clamped - track.left) / track.width;
    const result = @round(raw * 100.0) / 100.0;

    assert(result >= 0.0);
    assert(result <= 1.0);

    return result;
}

pub fn volume_header() Rect {
    const base = size.padding + navigation_offset + size.button_nav + 20;

    return Rect{
        .left = size.padding,
        .top = base,
        .right = size.widget_width - size.padding,
        .bottom = base + 24,
    };
}

fn footer_button_width() i32 {
    const result = @divTrunc(size.widget_width - size.padding * 2 - footer_gap, 2);

    assert(result > 0);

    return result;
}

fn regions() [10]Rect {
    return .{
        close_button(),
        device_nav(),
        prev_button(),
        next_button(),
        volume_header(),
        speaker_icon(),
        slider(),
        set_default_button(),
        reset_default_button(),
        title(),
    };
}

const testing = std.testing;

test hit_test {
    const inside_close = close_button().center();
    const inside_slider = slider().center();
    const inside_prev = prev_button().center();

    try testing.expectEqual(HitRegion.button_close, hit_test(.{
        .x = @intFromFloat(inside_close.x),
        .y = @intFromFloat(inside_close.y),
    }));

    try testing.expectEqual(HitRegion.slider, hit_test(.{
        .x = @intFromFloat(inside_slider.x),
        .y = @intFromFloat(inside_slider.y),
    }));

    try testing.expectEqual(HitRegion.button_prev, hit_test(.{
        .x = @intFromFloat(inside_prev.x),
        .y = @intFromFloat(inside_prev.y),
    }));

    try testing.expectEqual(HitRegion.none, hit_test(.{ .x = 0, .y = size.widget_height - 1 }));
    try testing.expectEqual(HitRegion.none, hit_test(.{ .x = -5, .y = -5 }));
}

test "every region stays inside the widget" {
    for (regions()) |region| {
        try testing.expect(region.is_valid());
        try testing.expect(region.left >= 0);
        try testing.expect(region.top >= 0);
        try testing.expect(region.right <= size.widget_width);
        try testing.expect(region.bottom <= size.widget_height);
    }
}

test "the navigation buttons sit at the two ends of the nav strip" {
    const nav = device_nav();
    const previous = prev_button();
    const next = next_button();

    try testing.expectEqual(nav.left, previous.left);
    try testing.expectEqual(nav.right, next.right);
    try testing.expect(previous.right < next.left);
}

test "the two footer buttons never overlap" {
    const set = set_default_button();
    const reset = reset_default_button();

    try testing.expect(set.right < reset.left);
    try testing.expectEqual(set.top, reset.top);
    try testing.expectEqual(set.bottom, reset.bottom);
}

test "the slider maps its ends to the full volume range" {
    const track = slider_track_bounds();

    try testing.expect(track.width > 0);
    try testing.expectEqual(@as(f32, 0.0), volume_from_x(@intFromFloat(track.left)));
    try testing.expectEqual(@as(f32, 1.0), volume_from_x(@intFromFloat(track.right)));
}

test "the slider clamps anything beyond its ends" {
    try testing.expectEqual(@as(f32, 0.0), volume_from_x(-1000));
    try testing.expectEqual(@as(f32, 1.0), volume_from_x(1000));
}

test "the slider quantises to whole percent steps" {
    const track = slider_track_bounds();
    const middle: i32 = @intFromFloat(track.left + track.width / 2.0);
    const value = volume_from_x(middle);

    try testing.expectEqual(@round(value * 100.0), value * 100.0);
}
