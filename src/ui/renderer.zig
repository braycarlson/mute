const std = @import("std");

const w32 = @import("win32").everything;

const gdiplus = @import("gdiplus.zig");
const layout = @import("layout.zig");
const theme = @import("theme.zig");

const Color = theme.Color;
const Size = theme.Size;

const percent_buffer_len_max: u32 = 8;
const device_name_len_max: u32 = 256;
const title_len_max: u32 = 64;

pub const Fonts = struct {
    family: ?*gdiplus.FontFamily = null,
    regular: ?*gdiplus.Font = null,
    semibold: ?*gdiplus.Font = null,
    device: ?*gdiplus.Font = null,

    pub fn init() Fonts {
        var self = Fonts{};
        const font_name = std.unicode.utf8ToUtf16LeStringLiteral("Segoe UI");

        var family: *gdiplus.FontFamily = undefined;
        const family_status = gdiplus.GdipCreateFontFamilyFromName(font_name, null, &family);

        if (family_status != .Ok) {
            return self;
        }

        self.family = family;

        var regular: *gdiplus.Font = undefined;
        var semibold: *gdiplus.Font = undefined;
        var device: *gdiplus.Font = undefined;

        if (gdiplus.GdipCreateFont(family, 9.0, gdiplus.font_style_regular, gdiplus.unit_point, &regular) == .Ok) {
            self.regular = regular;
        }

        if (gdiplus.GdipCreateFont(family, 9.0, gdiplus.font_style_semibold, gdiplus.unit_point, &semibold) == .Ok) {
            self.semibold = semibold;
        }

        if (gdiplus.GdipCreateFont(family, 10.0, gdiplus.font_style_regular, gdiplus.unit_point, &device) == .Ok) {
            self.device = device;
        }

        return self;
    }

    pub fn deinit(self: *Fonts) void {
        if (self.regular) |font| {
            _ = gdiplus.GdipDeleteFont(font);
            self.regular = null;
        }

        if (self.semibold) |font| {
            _ = gdiplus.GdipDeleteFont(font);
            self.semibold = null;
        }

        if (self.device) |font| {
            _ = gdiplus.GdipDeleteFont(font);
            self.device = null;
        }

        if (self.family) |family| {
            _ = gdiplus.GdipDeleteFontFamily(family);
            self.family = null;
        }

        std.debug.assert(self.regular == null);
        std.debug.assert(self.semibold == null);
        std.debug.assert(self.device == null);
        std.debug.assert(self.family == null);
    }
};

pub const State = struct {
    volume: f32,
    is_muted: bool,
    hover: layout.HitRegion,
    focus: FocusRegion,
    dragging: bool,
    device_name: []const u8,
    title: []const u8,

    pub const FocusRegion = enum { none, device, slider };
};

pub fn render(graphics: *gdiplus.Graphics, fonts: *const Fonts, state: *const State) void {
    std.debug.assert(state.volume >= 0.0);
    std.debug.assert(state.volume <= 1.0);
    std.debug.assert(state.device_name.len <= device_name_len_max);
    std.debug.assert(state.title.len <= title_len_max);

    _ = gdiplus.GdipGraphicsClear(graphics, 0x00000000);
    _ = gdiplus.GdipSetSmoothingMode(graphics, gdiplus.smoothing_mode_antialias);
    _ = gdiplus.GdipSetTextRenderingHint(graphics, gdiplus.text_rendering_hint_cleartype_grid_fit);

    draw_background(graphics);
    draw_title(graphics, fonts, state.title);
    draw_close_button(graphics, state.hover == .button_close);
    draw_device_nav(graphics, fonts, state.device_name, state.hover);
    draw_volume_header(graphics, fonts, state.volume, state.is_muted);
    draw_speaker_icon(graphics, state.is_muted, state.hover == .icon_speaker);
    draw_slider(graphics, state);
    draw_buttons(graphics, fonts, state.hover);
}

fn draw_title(graphics: *gdiplus.Graphics, fonts: *const Fonts, title_text: []const u8) void {
    std.debug.assert(title_text.len <= title_len_max);

    const rect = layout.title();
    const font = fonts.semibold orelse return;

    gdiplus.draw_text(
        graphics,
        title_text,
        gdiplus.RectF.from_rect(rect),
        Color.text_dim,
        font,
        gdiplus.string_alignment_near,
        gdiplus.string_alignment_center,
        false,
    );
}

fn draw_background(graphics: *gdiplus.Graphics) void {
    gdiplus.fill_rounded_rect(
        graphics,
        0,
        0,
        Size.widget_width,
        Size.widget_height,
        Size.corner_radius,
        Color.background,
        Color.border,
    );
}

fn draw_close_button(graphics: *gdiplus.Graphics, hover: bool) void {
    const center_point = layout.center(layout.close_button());
    const color = if (hover) Color.text else Color.text_dim;

    gdiplus.draw_x(graphics, center_point.x, center_point.y, 5, color, 1.5);
}

fn draw_device_nav(
    graphics: *gdiplus.Graphics,
    fonts: *const Fonts,
    device_name: []const u8,
    hover: layout.HitRegion,
) void {
    std.debug.assert(device_name.len <= device_name_len_max);

    const nav = layout.device_nav();
    const prev = layout.center(layout.prev_button());
    const next = layout.center(layout.next_button());

    const prev_color = if (hover == .button_prev) Color.text else Color.text_dim;
    const next_color = if (hover == .button_next) Color.text else Color.text_dim;

    draw_prev_arrow(graphics, prev.x, prev.y, prev_color);
    draw_next_arrow(graphics, next.x, next.y, next_color);
    draw_device_name(graphics, fonts, device_name, nav);
}

fn draw_prev_arrow(graphics: *gdiplus.Graphics, x: f32, y: f32, color: u32) void {
    const prev_points = [_]gdiplus.PointF{
        .{ .x = x + 4, .y = y - 6 },
        .{ .x = x - 4, .y = y },
        .{ .x = x + 4, .y = y + 6 },
    };

    gdiplus.fill_polygon(graphics, &prev_points, color);
}

fn draw_next_arrow(graphics: *gdiplus.Graphics, x: f32, y: f32, color: u32) void {
    const next_points = [_]gdiplus.PointF{
        .{ .x = x - 4, .y = y - 6 },
        .{ .x = x + 4, .y = y },
        .{ .x = x - 4, .y = y + 6 },
    };

    gdiplus.fill_polygon(graphics, &next_points, color);
}

fn draw_device_name(
    graphics: *gdiplus.Graphics,
    fonts: *const Fonts,
    device_name: []const u8,
    nav: w32.RECT,
) void {
    std.debug.assert(nav.right > nav.left);
    std.debug.assert(nav.bottom > nav.top);

    const name = if (device_name.len > 0) device_name else "Default Device";
    const prev_rect = layout.prev_button();
    const next_rect = layout.next_button();
    const font = fonts.device orelse return;

    gdiplus.draw_text(
        graphics,
        name,
        .{
            .x = @floatFromInt(prev_rect.right + 10),
            .y = @floatFromInt(nav.top),
            .width = @floatFromInt(next_rect.left - prev_rect.right - 20),
            .height = @floatFromInt(nav.bottom - nav.top),
        },
        Color.text,
        font,
        gdiplus.string_alignment_center,
        gdiplus.string_alignment_center,
        true,
    );
}

fn draw_volume_header(
    graphics: *gdiplus.Graphics,
    fonts: *const Fonts,
    volume: f32,
    is_muted: bool,
) void {
    std.debug.assert(volume >= 0.0);
    std.debug.assert(volume <= 1.0);

    const rect = layout.volume_header();
    const font = fonts.semibold orelse return;

    gdiplus.draw_text(
        graphics,
        "Volume",
        .{
            .x = @floatFromInt(rect.left),
            .y = @floatFromInt(rect.top),
            .width = 100,
            .height = @floatFromInt(rect.bottom - rect.top),
        },
        Color.text,
        font,
        gdiplus.string_alignment_near,
        gdiplus.string_alignment_center,
        false,
    );

    draw_volume_percent(graphics, font, rect, volume, is_muted);
}

fn draw_volume_percent(
    graphics: *gdiplus.Graphics,
    font: *gdiplus.Font,
    rect: w32.RECT,
    volume: f32,
    is_muted: bool,
) void {
    std.debug.assert(volume >= 0.0);
    std.debug.assert(volume <= 1.0);

    const display = if (is_muted) 0.0 else volume;
    var buffer: [percent_buffer_len_max]u8 = undefined;

    const percent = std.fmt.bufPrint(&buffer, "{d}%", .{
        @as(u32, @intFromFloat(@round(display * 100.0))),
    }) catch "0%";

    std.debug.assert(percent.len <= percent_buffer_len_max);

    gdiplus.draw_text(
        graphics,
        percent,
        .{
            .x = @floatFromInt(rect.left + 100),
            .y = @floatFromInt(rect.top),
            .width = @floatFromInt(rect.right - rect.left - 100),
            .height = @floatFromInt(rect.bottom - rect.top),
        },
        if (is_muted) Color.muted else Color.accent_hover,
        font,
        gdiplus.string_alignment_far,
        gdiplus.string_alignment_center,
        false,
    );
}

fn draw_speaker_icon(graphics: *gdiplus.Graphics, is_muted: bool, hover: bool) void {
    const center_point = layout.center(layout.speaker_icon());
    const color = if (is_muted) Color.muted else if (hover) Color.text else Color.text_dim;

    const speaker_x = center_point.x - 2;

    const points = [_]gdiplus.PointF{
        .{ .x = speaker_x - 4, .y = center_point.y - 2.5 },
        .{ .x = speaker_x - 1, .y = center_point.y - 2.5 },
        .{ .x = speaker_x + 3, .y = center_point.y - 6 },
        .{ .x = speaker_x + 3, .y = center_point.y + 6 },
        .{ .x = speaker_x - 1, .y = center_point.y + 2.5 },
        .{ .x = speaker_x - 4, .y = center_point.y + 2.5 },
    };

    gdiplus.fill_polygon(graphics, &points, color);

    if (is_muted) {
        gdiplus.draw_x(graphics, center_point.x + 8, center_point.y, 3.5, Color.muted, 1.5);
    }
}

fn draw_slider(graphics: *gdiplus.Graphics, state: *const State) void {
    std.debug.assert(state.volume >= 0.0);
    std.debug.assert(state.volume <= 1.0);

    const rect = layout.slider();
    const center_y: f32 = @floatFromInt(rect.top + @divTrunc(rect.bottom - rect.top, 2));
    const track = layout.slider_track_bounds();
    const half_height = Size.slider_height / 2.0;

    const display = if (state.is_muted) 0.0 else state.volume;
    const fill_width = track.width * display;

    std.debug.assert(fill_width >= 0);

    draw_slider_track(graphics, track.left, track.right, track.width, center_y, half_height);
    draw_slider_fill(graphics, track.left, center_y, half_height, fill_width, state.is_muted);
    draw_slider_thumb(graphics, track.left, center_y, fill_width, state);
}

fn draw_slider_track(graphics: *gdiplus.Graphics, left: f32, right: f32, width: f32, center_y: f32, half_height: f32) void {
    std.debug.assert(half_height > 0);
    std.debug.assert(width >= 0);

    gdiplus.fill_ellipse(graphics, left - half_height, center_y - half_height, half_height * 2, half_height * 2, Color.slider_track);
    gdiplus.fill_rect(graphics, left, center_y - half_height, width, half_height * 2, Color.slider_track);
    gdiplus.fill_ellipse(graphics, right - half_height, center_y - half_height, half_height * 2, half_height * 2, Color.slider_track);
}

fn draw_slider_fill(
    graphics: *gdiplus.Graphics,
    left: f32,
    center_y: f32,
    half_height: f32,
    fill_width: f32,
    is_muted: bool,
) void {
    std.debug.assert(half_height > 0);
    std.debug.assert(fill_width >= 0);

    const fill_color = if (is_muted) Color.muted else Color.accent;

    if (fill_width > 0) {
        gdiplus.fill_ellipse(graphics, left - half_height, center_y - half_height, half_height * 2, half_height * 2, fill_color);
        gdiplus.fill_rect(graphics, left, center_y - half_height, fill_width, half_height * 2, fill_color);
        gdiplus.fill_ellipse(graphics, left + fill_width - half_height, center_y - half_height, half_height * 2, half_height * 2, fill_color);
    }
}

fn draw_slider_thumb(
    graphics: *gdiplus.Graphics,
    left: f32,
    center_y: f32,
    fill_width: f32,
    state: *const State,
) void {
    std.debug.assert(fill_width >= 0);

    const thumb_x = left + fill_width;
    const is_active = state.hover == .slider or state.dragging or state.focus == .slider;
    const thumb_radius = if (is_active) Size.slider_thumb_radius + 1 else Size.slider_thumb_radius;

    std.debug.assert(thumb_radius > 0);

    if (is_active) {
        gdiplus.fill_ellipse(
            graphics,
            thumb_x - thumb_radius - 3,
            center_y - thumb_radius - 3,
            (thumb_radius + 3) * 2,
            (thumb_radius + 3) * 2,
            Color.glow,
        );
    }

    gdiplus.fill_ellipse(graphics, thumb_x - thumb_radius, center_y - thumb_radius, thumb_radius * 2, thumb_radius * 2, Color.text);
}

fn draw_buttons(graphics: *gdiplus.Graphics, fonts: *const Fonts, hover: layout.HitRegion) void {
    const set_rect = layout.set_default_button();
    const reset_rect = layout.reset_default_button();

    std.debug.assert(set_rect.right > set_rect.left);
    std.debug.assert(reset_rect.right > reset_rect.left);

    gdiplus.fill_rounded_rect(
        graphics,
        @floatFromInt(set_rect.left),
        @floatFromInt(set_rect.top),
        @floatFromInt(set_rect.right - set_rect.left),
        @floatFromInt(set_rect.bottom - set_rect.top),
        Size.button_radius,
        if (hover == .button_set_default) Color.accent_hover else Color.accent,
        null,
    );

    gdiplus.fill_rounded_rect(
        graphics,
        @floatFromInt(reset_rect.left),
        @floatFromInt(reset_rect.top),
        @floatFromInt(reset_rect.right - reset_rect.left),
        @floatFromInt(reset_rect.bottom - reset_rect.top),
        Size.button_radius,
        if (hover == .button_reset_default) Color.surface_hover else Color.surface,
        Color.border,
    );

    if (fonts.semibold) |font| {
        gdiplus.draw_text(
            graphics,
            "Set Default",
            gdiplus.RectF.from_rect(set_rect),
            Color.text,
            font,
            gdiplus.string_alignment_center,
            gdiplus.string_alignment_center,
            false,
        );
    }

    if (fonts.regular) |font| {
        const color = if (hover == .button_reset_default) Color.text else Color.text_dim;

        gdiplus.draw_text(
            graphics,
            "Reset",
            gdiplus.RectF.from_rect(reset_rect),
            color,
            font,
            gdiplus.string_alignment_center,
            gdiplus.string_alignment_center,
            false,
        );
    }
}
