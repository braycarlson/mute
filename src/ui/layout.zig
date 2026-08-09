const std = @import("std");

const rect = @import("rect.zig");
const theme = @import("theme.zig");

const assert = std.debug.assert;

const Point = rect.Point;
const Rect = rect.Rect;
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

pub const Track = struct {
    left: f32,
    right: f32,
    width: f32,
};

pub fn close_button() Rect {
    return Rect.init(Size.widget_width - 32, 4, Size.widget_width - 4, 32);
}

pub fn device_nav() Rect {
    const top = Size.padding + 46;

    return Rect.init(
        Size.padding,
        top,
        Size.widget_width - Size.padding,
        top + Size.button_nav_size,
    );
}

pub fn prev_button() Rect {
    const nav = device_nav();

    return Rect.init(nav.left, nav.top, nav.left + Size.button_nav_size, nav.bottom);
}

pub fn next_button() Rect {
    const nav = device_nav();

    return Rect.init(nav.right - Size.button_nav_size, nav.top, nav.right, nav.bottom);
}

pub fn volume_header() Rect {
    const base = Size.padding + 46 + Size.button_nav_size + 20;

    return Rect.init(Size.padding, base, Size.widget_width - Size.padding, base + 24);
}

pub fn speaker_icon() Rect {
    const header = volume_header();
    const center_y = header.bottom + @divTrunc(28, 2);
    const half = @divTrunc(Size.icon_speaker_size, 2);

    return Rect.init(
        Size.padding,
        center_y - half,
        Size.padding + Size.icon_speaker_size,
        center_y + half,
    );
}

pub fn slider() Rect {
    const header = volume_header();
    const speaker = speaker_icon();

    return Rect.init(
        speaker.right + 10,
        header.bottom,
        Size.widget_width - Size.padding,
        header.bottom + 28,
    );
}

pub fn set_default_button() Rect {
    const button_width = @divTrunc(Size.widget_width - Size.padding * 2 - 12, 2);

    return Rect.init(
        Size.padding,
        Size.widget_height - Size.padding - Size.button_height,
        Size.padding + button_width,
        Size.widget_height - Size.padding,
    );
}

pub fn reset_default_button() Rect {
    const button_width = @divTrunc(Size.widget_width - Size.padding * 2 - 12, 2);

    return Rect.init(
        Size.padding + button_width + 12,
        Size.widget_height - Size.padding - Size.button_height,
        Size.widget_width - Size.padding,
        Size.widget_height - Size.padding,
    );
}

pub fn title() Rect {
    return Rect.init(Size.padding, 4, Size.widget_width - 32, 32);
}

pub fn hit_test(x: i32, y: i32) HitRegion {
    if (close_button().contains(x, y)) return .button_close;
    if (speaker_icon().contains(x, y)) return .icon_speaker;
    if (slider().contains(x, y)) return .slider;
    if (prev_button().contains(x, y)) return .button_prev;
    if (next_button().contains(x, y)) return .button_next;
    if (set_default_button().contains(x, y)) return .button_set_default;
    if (reset_default_button().contains(x, y)) return .button_reset_default;

    return .none;
}

pub fn center(bounds: Rect) Point {
    return bounds.center();
}

pub fn slider_track_bounds() Track {
    const bounds = slider();
    const thumb_offset: i32 = @intFromFloat(Size.slider_thumb_radius);

    const left: f32 = @floatFromInt(bounds.left + thumb_offset);
    const right: f32 = @floatFromInt(bounds.right - thumb_offset);

    const width = right - left;

    assert(width >= 0);
    assert(right >= left);

    return .{ .left = left, .right = right, .width = width };
}

pub fn volume_from_x(x: i32) f32 {
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

const testing = std.testing;

test "every region stays inside the widget" {
    const regions = [_]Rect{
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

    for (regions) |region| {
        try testing.expect(region.is_valid());
        try testing.expect(region.left >= 0);
        try testing.expect(region.top >= 0);
        try testing.expect(region.right <= Size.widget_width);
        try testing.expect(region.bottom <= Size.widget_height);
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

test "hit testing finds the region a point falls in" {
    const inside_close = close_button().center();
    const inside_slider = slider().center();
    const inside_prev = prev_button().center();

    try testing.expectEqual(HitRegion.button_close, hit_test(
        @intFromFloat(inside_close.x),
        @intFromFloat(inside_close.y),
    ));

    try testing.expectEqual(HitRegion.slider, hit_test(
        @intFromFloat(inside_slider.x),
        @intFromFloat(inside_slider.y),
    ));

    try testing.expectEqual(HitRegion.button_prev, hit_test(
        @intFromFloat(inside_prev.x),
        @intFromFloat(inside_prev.y),
    ));
}

test "a point in no region hits nothing" {
    try testing.expectEqual(HitRegion.none, hit_test(0, Size.widget_height - 1));
    try testing.expectEqual(HitRegion.none, hit_test(-5, -5));
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
