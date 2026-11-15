const std = @import("std");

const mantra = @import("mantra");

const canvas = @import("canvas.zig");
const layout = @import("layout.zig");
const rect = @import("rect.zig");
const theme = @import("theme.zig");

const assert = std.debug.assert;

const Canvas = canvas.Canvas;
const Point = rect.Point;
const Rect = rect.Rect;

pub const title_bytes_max: u32 = 64;
const percent_bytes_max: u32 = 8;

comptime {
    assert(percent_bytes_max > 0);
    assert(title_bytes_max > 0);
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
    assert(state.device_name.len <= mantra.limits.name_bytes_max);
    assert(state.title.len <= title_bytes_max);

    target.clear();

    draw_background(target);
    draw_title(target, state.title);
    draw_close_button(target, state);
    draw_device_nav(target, state);
    draw_volume_header(target, state);
    draw_speaker_icon(target, state);
    draw_slider(target, state);
    draw_buttons(target, state);
}

fn draw_background(target: *Canvas) void {
    const bounds = Rect{
        .left = 0,
        .top = 0,
        .right = theme.size.widget_width,
        .bottom = theme.size.widget_height,
    };

    target.fill_rounded_rect(bounds, .{
        .border = theme.color.border,
        .color = theme.color.background,
        .radius = theme.size.corner_radius,
    });
}

fn draw_title(target: *Canvas, text: []const u8) void {
    assert(text.len <= title_bytes_max);

    target.draw_text(text, layout.title(), .{
        .color = theme.color.text_dim,
        .face = .regular_small,
    });
}

fn draw_close_button(target: *Canvas, state: *const State) void {
    const middle = layout.close_button().center();
    const stroke = if (state.hover == .button_close) theme.color.text else theme.color.text_dim;

    draw_cross(target, middle, 5, stroke, 1.5);
}

fn draw_cross(target: *Canvas, center: Point, arm: f32, stroke: u32, thickness: f32) void {
    assert(center.is_finite());
    assert(arm > 0);
    assert(stroke >> 24 > 0);
    assert(thickness > 0);

    const falling = rect.Segment{
        .end = .{ .x = center.x + arm, .y = center.y + arm },
        .start = .{ .x = center.x - arm, .y = center.y - arm },
    };

    const rising = rect.Segment{
        .end = .{ .x = center.x - arm, .y = center.y + arm },
        .start = .{ .x = center.x + arm, .y = center.y - arm },
    };

    target.draw_line(falling, thickness, stroke);
    target.draw_line(rising, thickness, stroke);
}

fn draw_device_nav(target: *Canvas, state: *const State) void {
    assert(state.device_name.len <= mantra.limits.name_bytes_max);

    const previous = layout.prev_button().center();
    const next = layout.next_button().center();

    const color_previous = if (state.hover == .button_prev)
        theme.color.text
    else
        theme.color.text_dim;

    const color_next = if (state.hover == .button_next)
        theme.color.text
    else
        theme.color.text_dim;

    const points_previous = [_]Point{
        .{ .x = previous.x + 4, .y = previous.y - 6 },
        .{ .x = previous.x - 4, .y = previous.y },
        .{ .x = previous.x + 4, .y = previous.y + 6 },
    };

    const points_next = [_]Point{
        .{ .x = next.x - 4, .y = next.y - 6 },
        .{ .x = next.x + 4, .y = next.y },
        .{ .x = next.x - 4, .y = next.y + 6 },
    };

    target.fill_polygon(&points_previous, color_previous);
    target.fill_polygon(&points_next, color_next);

    draw_device_name(target, state.device_name);
}

fn draw_device_name(target: *Canvas, device_name: []const u8) void {
    assert(device_name.len <= mantra.limits.name_bytes_max);

    const name = if (device_name.len > 0) device_name else "Default Device";
    const nav = layout.device_nav();
    const previous = layout.prev_button();
    const next = layout.next_button();

    const bounds = Rect{
        .left = previous.right + 10,
        .top = nav.top,
        .right = next.left - 10,
        .bottom = nav.bottom,
    };

    target.draw_text(name, bounds, .{
        .alignment = .center,
        .color = theme.color.text,
        .face = .regular_large,
        .overflow = .ellipsis,
    });
}

fn draw_volume_header(target: *Canvas, state: *const State) void {
    assert(state.volume >= 0.0);
    assert(state.volume <= 1.0);

    const bounds = layout.volume_header();

    const label = Rect{
        .left = bounds.left,
        .top = bounds.top,
        .right = bounds.left + 100,
        .bottom = bounds.bottom,
    };

    target.draw_text("Volume", label, .{ .color = theme.color.text, .face = .regular_small });

    draw_volume_percent(target, bounds, state);
}

fn draw_volume_percent(target: *Canvas, bounds: Rect, state: *const State) void {
    assert(bounds.right >= bounds.left + 100);
    assert(state.volume >= 0.0);
    assert(state.volume <= 1.0);

    const display = if (state.is_muted) 0.0 else state.volume;

    var buffer: [percent_bytes_max]u8 = undefined;

    const percent = std.mem.print(&buffer, "{d}%", .{
        @as(u32, @intFromFloat(@round(display * 100.0))),
    }) catch "0%";

    assert(percent.len <= percent_bytes_max);

    const value = Rect{
        .left = bounds.left + 100,
        .top = bounds.top,
        .right = bounds.right,
        .bottom = bounds.bottom,
    };

    target.draw_text(percent, value, .{
        .alignment = .far,
        .color = if (state.is_muted) theme.color.muted else theme.color.accent_hover,
        .face = .regular_small,
    });
}

fn draw_speaker_icon(target: *Canvas, state: *const State) void {
    const middle = layout.speaker_icon().center();

    const fill = if (state.is_muted)
        theme.color.muted
    else if (state.hover == .icon_speaker)
        theme.color.text
    else
        theme.color.text_dim;

    const x = middle.x - 2;

    const points = [_]Point{
        .{ .x = x - 4, .y = middle.y - 2.5 },
        .{ .x = x - 1, .y = middle.y - 2.5 },
        .{ .x = x + 3, .y = middle.y - 6 },
        .{ .x = x + 3, .y = middle.y + 6 },
        .{ .x = x - 1, .y = middle.y + 2.5 },
        .{ .x = x - 4, .y = middle.y + 2.5 },
    };

    target.fill_polygon(&points, fill);

    if (state.is_muted) {
        draw_cross(target, .{ .x = middle.x + 8, .y = middle.y }, 3.5, theme.color.muted, 1.5);
    }
}

fn draw_slider(target: *Canvas, state: *const State) void {
    assert(state.volume >= 0.0);
    assert(state.volume <= 1.0);

    const bounds = layout.slider();
    const track = layout.slider_track_bounds();
    const center_y: f32 = @floatFromInt(bounds.top + @divTrunc(bounds.height(), 2));
    const half_height = theme.size.slider_height / 2.0;
    const display = if (state.is_muted) 0.0 else state.volume;
    const fill_width = track.width * display;

    assert(fill_width >= 0);

    const groove = rect.Segment{
        .end = .{ .x = track.right, .y = center_y },
        .start = .{ .x = track.left, .y = center_y },
    };

    target.fill_capsule(groove, half_height, theme.color.slider_track);

    if (fill_width > 0) {
        const level = rect.Segment{
            .end = .{ .x = track.left + fill_width, .y = center_y },
            .start = .{ .x = track.left, .y = center_y },
        };

        const fill = if (state.is_muted) theme.color.muted else theme.color.accent;

        target.fill_capsule(level, half_height, fill);
    }

    draw_slider_thumb(target, .{ .x = track.left + fill_width, .y = center_y }, state);
}

fn draw_slider_thumb(target: *Canvas, center: Point, state: *const State) void {
    assert(center.x >= layout.slider_track_bounds().left);

    const active = state.hover == .slider or state.dragging or state.focus == .slider;
    const resting = theme.size.slider_thumb_radius;
    const radius = if (active) resting + 1 else resting;

    assert(radius > 0);

    if (active) {
        target.fill_circle(center, radius + 3, theme.color.glow);
    }

    target.fill_circle(center, radius, theme.color.text);
}

fn draw_buttons(target: *Canvas, state: *const State) void {
    const set = layout.set_default_button();
    const reset = layout.reset_default_button();

    assert(set.width() > 0);
    assert(reset.width() > 0);

    target.fill_rounded_rect(set, .{
        .color = if (state.hover == .button_set_default)
            theme.color.accent_hover
        else
            theme.color.accent,
        .radius = theme.size.button_radius,
    });

    target.fill_rounded_rect(reset, .{
        .border = theme.color.border,
        .color = if (state.hover == .button_reset_default)
            theme.color.surface_hover
        else
            theme.color.surface,
        .radius = theme.size.button_radius,
    });

    target.draw_text("Set Default", set, .{
        .alignment = .center,
        .color = theme.color.text,
        .face = .regular_small,
    });

    const reset_color = if (state.hover == .button_reset_default)
        theme.color.text
    else
        theme.color.text_dim;

    target.draw_text("Reset", reset, .{
        .alignment = .center,
        .color = reset_color,
        .face = .regular_small,
    });
}

const testing = std.testing;

const pixel_count: usize = @intCast(theme.size.widget_width * theme.size.widget_height);

const Scratch = struct {
    canvas: Canvas,
    pixels: [pixel_count]u32,
};

fn draw(scratch: *Scratch, state: *const State) *Canvas {
    scratch.canvas = Canvas.init(&scratch.pixels, theme.size.widget_width);

    render(&scratch.canvas, state);

    return &scratch.canvas;
}

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

test render {
    const scratch = try testing.allocator.create(Scratch);
    defer testing.allocator.destroy(scratch);

    const state = base();
    const target = draw(scratch, &state);

    try testing.expect(ink_of(target) > pixel_count / 2);
    try testing.expectEqual(@as(u32, 0), target.pixels[0] >> 24);
}

test "the volume changes what the widget draws" {
    const scratch = try testing.allocator.create(Scratch);
    defer testing.allocator.destroy(scratch);

    var state = base();

    const quiet = checksum_of(draw(scratch, &state));

    state.volume = 0.9;

    const loud = checksum_of(draw(scratch, &state));

    try testing.expect(quiet != loud);
}

test "muting changes what the widget draws" {
    const scratch = try testing.allocator.create(Scratch);
    defer testing.allocator.destroy(scratch);

    var state = base();

    const unmuted = checksum_of(draw(scratch, &state));

    state.is_muted = true;

    const muted = checksum_of(draw(scratch, &state));

    try testing.expect(unmuted != muted);
}

test "hovering a region changes what the widget draws" {
    const scratch = try testing.allocator.create(Scratch);
    defer testing.allocator.destroy(scratch);

    var state = base();

    const idle = checksum_of(draw(scratch, &state));

    state.hover = .button_set_default;

    const hovered = checksum_of(draw(scratch, &state));

    try testing.expect(idle != hovered);
}

test "a device name renders differently from the default label" {
    const scratch = try testing.allocator.create(Scratch);
    defer testing.allocator.destroy(scratch);

    var state = base();

    const named = checksum_of(draw(scratch, &state));

    state.device_name = "";

    const unnamed = checksum_of(draw(scratch, &state));

    try testing.expect(named != unnamed);
}

test "an arbitrary utf8 device name renders without escaping the widget" {
    const scratch = try testing.allocator.create(Scratch);
    defer testing.allocator.destroy(scratch);

    var state = base();

    state.device_name = "\u{00C9}couteurs \u{4E2D}\u{6587} \u{1F50A}";

    const target = draw(scratch, &state);

    try testing.expect(ink_of(target) > 0);
    try testing.expectEqual(@as(u32, 0), target.pixels[0] >> 24);
}

test "every rendered pixel keeps its colour channels inside its alpha" {
    const scratch = try testing.allocator.create(Scratch);
    defer testing.allocator.destroy(scratch);

    const state = base();
    const target = draw(scratch, &state);

    for (target.pixels) |pixel| {
        const alpha = pixel >> 24;

        try testing.expect(pixel >> 16 & 0xFF <= alpha);
        try testing.expect(pixel >> 8 & 0xFF <= alpha);
        try testing.expect(pixel & 0xFF <= alpha);
    }
}
