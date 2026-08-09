const std = @import("std");

const canvas = @import("canvas.zig");
const layout = @import("layout.zig");
const rect = @import("rect.zig");
const theme = @import("theme.zig");

const assert = std.debug.assert;

const Canvas = canvas.Canvas;
const Color = theme.Color;
const Point = rect.Point;
const Rect = rect.Rect;
const Size = theme.Size;

pub const device_name_len_max: u32 = 256;
pub const percent_bytes_max: u32 = 8;
pub const title_len_max: u32 = 64;

comptime {
    assert(device_name_len_max > 0);
    assert(percent_bytes_max > 0);
    assert(title_len_max > 0);
}

pub const State = struct {
    device_name: []const u8,
    dragging: bool,
    focus: FocusRegion,
    hover: layout.HitRegion,
    is_muted: bool,
    title: []const u8,
    volume: f32,

    pub const FocusRegion = enum { none, device, slider };
};

pub fn render(target: *Canvas, state: *const State) void {
    assert(state.volume >= 0.0);
    assert(state.volume <= 1.0);
    assert(state.device_name.len <= device_name_len_max);
    assert(state.title.len <= title_len_max);

    target.clear();

    draw_background(target);
    draw_title(target, state.title);
    draw_close_button(target, state.hover == .button_close);
    draw_device_nav(target, state.device_name, state.hover);
    draw_volume_header(target, state.volume, state.is_muted);
    draw_speaker_icon(target, state.is_muted, state.hover == .icon_speaker);
    draw_slider(target, state);
    draw_buttons(target, state.hover);
}

fn draw_background(target: *Canvas) void {
    target.fill_rounded_rect(
        Rect.init(0, 0, Size.widget_width, Size.widget_height),
        Size.corner_radius,
        Color.background,
        Color.border,
    );
}

fn draw_title(target: *Canvas, text: []const u8) void {
    assert(text.len <= title_len_max);

    target.draw_text(.regular_small, text, layout.title(), Color.text_dim, .near, false);
}

fn draw_close_button(target: *Canvas, hover: bool) void {
    const middle = layout.close_button().center();
    const color = if (hover) Color.text else Color.text_dim;

    draw_cross(target, middle.x, middle.y, 5, color, 1.5);
}

fn draw_cross(target: *Canvas, x: f32, y: f32, arm: f32, color: u32, thickness: f32) void {
    assert(arm > 0);
    assert(thickness > 0);

    target.draw_line(x - arm, y - arm, x + arm, y + arm, thickness, color);
    target.draw_line(x + arm, y - arm, x - arm, y + arm, thickness, color);
}

fn draw_device_nav(target: *Canvas, device_name: []const u8, hover: layout.HitRegion) void {
    assert(device_name.len <= device_name_len_max);

    const previous = layout.prev_button().center();
    const next = layout.next_button().center();

    const previous_color = if (hover == .button_prev) Color.text else Color.text_dim;
    const next_color = if (hover == .button_next) Color.text else Color.text_dim;

    const previous_points = [_]Point{
        .{ .x = previous.x + 4, .y = previous.y - 6 },
        .{ .x = previous.x - 4, .y = previous.y },
        .{ .x = previous.x + 4, .y = previous.y + 6 },
    };

    const next_points = [_]Point{
        .{ .x = next.x - 4, .y = next.y - 6 },
        .{ .x = next.x + 4, .y = next.y },
        .{ .x = next.x - 4, .y = next.y + 6 },
    };

    target.fill_polygon(&previous_points, previous_color);
    target.fill_polygon(&next_points, next_color);

    draw_device_name(target, device_name);
}

fn draw_device_name(target: *Canvas, device_name: []const u8) void {
    const name = if (device_name.len > 0) device_name else "Default Device";

    const nav = layout.device_nav();
    const previous = layout.prev_button();
    const next = layout.next_button();

    const bounds = Rect.init(previous.right + 10, nav.top, next.left - 10, nav.bottom);

    target.draw_text(.regular_large, name, bounds, Color.text, .center, true);
}

fn draw_volume_header(target: *Canvas, volume: f32, is_muted: bool) void {
    assert(volume >= 0.0);
    assert(volume <= 1.0);

    const bounds = layout.volume_header();

    target.draw_text(
        .regular_small,
        "Volume",
        Rect.init(bounds.left, bounds.top, bounds.left + 100, bounds.bottom),
        Color.text,
        .near,
        false,
    );

    draw_volume_percent(target, bounds, volume, is_muted);
}

fn draw_volume_percent(target: *Canvas, bounds: Rect, volume: f32, is_muted: bool) void {
    assert(volume >= 0.0);
    assert(volume <= 1.0);

    const display = if (is_muted) 0.0 else volume;

    var buffer: [percent_bytes_max]u8 = undefined;

    const percent = std.fmt.bufPrint(&buffer, "{d}%", .{
        @as(u32, @intFromFloat(@round(display * 100.0))),
    }) catch "0%";

    assert(percent.len <= percent_bytes_max);

    target.draw_text(
        .regular_small,
        percent,
        Rect.init(bounds.left + 100, bounds.top, bounds.right, bounds.bottom),
        if (is_muted) Color.muted else Color.accent_hover,
        .far,
        false,
    );
}

fn draw_speaker_icon(target: *Canvas, is_muted: bool, hover: bool) void {
    const middle = layout.speaker_icon().center();

    const color = if (is_muted)
        Color.muted
    else if (hover)
        Color.text
    else
        Color.text_dim;

    const x = middle.x - 2;

    const points = [_]Point{
        .{ .x = x - 4, .y = middle.y - 2.5 },
        .{ .x = x - 1, .y = middle.y - 2.5 },
        .{ .x = x + 3, .y = middle.y - 6 },
        .{ .x = x + 3, .y = middle.y + 6 },
        .{ .x = x - 1, .y = middle.y + 2.5 },
        .{ .x = x - 4, .y = middle.y + 2.5 },
    };

    target.fill_polygon(&points, color);

    if (is_muted) {
        draw_cross(target, middle.x + 8, middle.y, 3.5, Color.muted, 1.5);
    }
}

fn draw_slider(target: *Canvas, state: *const State) void {
    assert(state.volume >= 0.0);
    assert(state.volume <= 1.0);

    const bounds = layout.slider();
    const track = layout.slider_track_bounds();

    const center_y: f32 = @floatFromInt(bounds.top + @divTrunc(bounds.height(), 2));
    const half_height = Size.slider_height / 2.0;

    const display = if (state.is_muted) 0.0 else state.volume;
    const fill_width = track.width * display;

    assert(fill_width >= 0);

    target.fill_capsule(
        track.left,
        center_y,
        track.right,
        center_y,
        half_height,
        Color.slider_track,
    );

    if (fill_width > 0) {
        const fill_color = if (state.is_muted) Color.muted else Color.accent;

        target.fill_capsule(
            track.left,
            center_y,
            track.left + fill_width,
            center_y,
            half_height,
            fill_color,
        );
    }

    draw_slider_thumb(target, track.left + fill_width, center_y, state);
}

fn draw_slider_thumb(target: *Canvas, x: f32, y: f32, state: *const State) void {
    const active = state.hover == .slider or state.dragging or state.focus == .slider;
    const radius = if (active) Size.slider_thumb_radius + 1 else Size.slider_thumb_radius;

    assert(radius > 0);

    if (active) {
        target.fill_circle(x, y, radius + 3, Color.glow);
    }

    target.fill_circle(x, y, radius, Color.text);
}

fn draw_buttons(target: *Canvas, hover: layout.HitRegion) void {
    const set = layout.set_default_button();
    const reset = layout.reset_default_button();

    assert(set.width() > 0);
    assert(reset.width() > 0);

    target.fill_rounded_rect(
        set,
        Size.button_radius,
        if (hover == .button_set_default) Color.accent_hover else Color.accent,
        null,
    );

    target.fill_rounded_rect(
        reset,
        Size.button_radius,
        if (hover == .button_reset_default) Color.surface_hover else Color.surface,
        Color.border,
    );

    target.draw_text(.regular_small, "Set Default", set, Color.text, .center, false);

    const reset_color = if (hover == .button_reset_default) Color.text else Color.text_dim;

    target.draw_text(.regular_small, "Reset", reset, reset_color, .center, false);
}

const testing = std.testing;

const pixel_count: usize = @intCast(Size.widget_width * Size.widget_height);

var scratch: [pixel_count]u32 = @splat(0);

fn draw(state: *const State) *Canvas {
    canvas_state = Canvas.init(&scratch, Size.widget_width, Size.widget_height);

    render(&canvas_state, state);

    return &canvas_state;
}

var canvas_state: Canvas = undefined;

fn base() State {
    return .{
        .device_name = "Microphone",
        .dragging = false,
        .focus = .none,
        .hover = .none,
        .is_muted = false,
        .title = "Mute",
        .volume = 0.5,
    };
}

fn ink_of(target: *const Canvas) u32 {
    var total: u32 = 0;

    for (target.pixels) |pixel| {
        if (pixel >> 24 > 0) total += 1;
    }

    return total;
}

fn checksum_of(target: *const Canvas) u32 {
    var total: u32 = 2166136261;

    for (target.pixels) |pixel| {
        total = (total ^ pixel) *% 16777619;
    }

    return total;
}

test "a rendered widget covers most of its surface and leaves the corners clear" {
    const state = base();
    const target = draw(&state);

    try testing.expect(ink_of(target) > pixel_count / 2);
    try testing.expectEqual(@as(u32, 0), target.pixels[0] >> 24);
}

test "the volume changes what the widget draws" {
    var state = base();

    const quiet = checksum_of(draw(&state));

    state.volume = 0.9;

    const loud = checksum_of(draw(&state));

    try testing.expect(quiet != loud);
}

test "muting changes what the widget draws" {
    var state = base();

    const unmuted = checksum_of(draw(&state));

    state.is_muted = true;

    const muted = checksum_of(draw(&state));

    try testing.expect(unmuted != muted);
}

test "hovering a region changes what the widget draws" {
    var state = base();

    const idle = checksum_of(draw(&state));

    state.hover = .button_set_default;

    const hovered = checksum_of(draw(&state));

    try testing.expect(idle != hovered);
}

test "a device name renders differently from the default label" {
    var state = base();

    const named = checksum_of(draw(&state));

    state.device_name = "";

    const unnamed = checksum_of(draw(&state));

    try testing.expect(named != unnamed);
}

test "an arbitrary utf8 device name renders without escaping the widget" {
    var state = base();

    state.device_name = "\u{00C9}couteurs \u{4E2D}\u{6587} \u{1F50A}";

    const target = draw(&state);

    try testing.expect(ink_of(target) > 0);
    try testing.expectEqual(@as(u32, 0), target.pixels[0] >> 24);
}

test "every rendered pixel keeps its colour channels inside its alpha" {
    const state = base();
    const target = draw(&state);

    for (target.pixels) |pixel| {
        const alpha = pixel >> 24;

        try testing.expect(pixel >> 16 & 0xFF <= alpha);
        try testing.expect(pixel >> 8 & 0xFF <= alpha);
        try testing.expect(pixel & 0xFF <= alpha);
    }
}
