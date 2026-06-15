const std = @import("std");

const win32 = @import("win32").everything;

const arc_count_max: u32 = 4;
const polygon_points_max: u32 = 16;
const text_buffer_len_max: u32 = 256;

pub const Status = enum(i32) { Ok = 0, _ };

pub const Graphics = opaque {};
pub const Brush = opaque {};
pub const SolidFill = opaque {};
pub const Pen = opaque {};
pub const Path = opaque {};
pub const StringFormat = opaque {};
pub const FontFamily = opaque {};
pub const Font = opaque {};
pub const Bitmap = opaque {};

pub const StartupInput = extern struct {
    GdiplusVersion: u32 = 1,
    DebugEventCallback: ?*anyopaque = null,
    SuppressBackgroundThread: i32 = 0,
    SuppressExternalCodecs: i32 = 0,
};

pub const RectF = extern struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,

    pub fn from_rect(rect: win32.RECT) RectF {
        std.debug.assert(rect.right >= rect.left);
        std.debug.assert(rect.bottom >= rect.top);

        return .{
            .x = @floatFromInt(rect.left),
            .y = @floatFromInt(rect.top),
            .width = @floatFromInt(rect.right - rect.left),
            .height = @floatFromInt(rect.bottom - rect.top),
        };
    }
};

pub const PointF = extern struct {
    x: f32,
    y: f32,
};

pub const BitmapData = extern struct {
    width: u32,
    height: u32,
    stride: i32,
    pixel_format: i32,
    scan0: ?*anyopaque,
    reserved: usize,
};

pub const smoothing_mode_antialias: i32 = 4;
pub const text_rendering_hint_cleartype_grid_fit: i32 = 5;
pub const unit_pixel: i32 = 2;
pub const unit_point: i32 = 3;
pub const font_style_regular: i32 = 0;
pub const font_style_semibold: i32 = 0;
pub const string_alignment_near: i32 = 0;
pub const string_alignment_center: i32 = 1;
pub const string_alignment_far: i32 = 2;
pub const string_trimming_ellipsis_character: i32 = 3;
pub const pixel_format_32bpp_pargb: i32 = 0x000E200B;
pub const image_lock_mode_read: u32 = 1;

pub extern "gdiplus" fn GdiplusStartup(
    token: *usize,
    input: *const StartupInput,
    output: ?*anyopaque,
) callconv(.c) Status;

pub extern "gdiplus" fn GdiplusShutdown(token: usize) callconv(.c) void;
pub extern "gdiplus" fn GdipDeleteGraphics(graphics: *Graphics) callconv(.c) Status;
pub extern "gdiplus" fn GdipSetSmoothingMode(graphics: *Graphics, mode: i32) callconv(.c) Status;
pub extern "gdiplus" fn GdipSetTextRenderingHint(graphics: *Graphics, hint: i32) callconv(.c) Status;
pub extern "gdiplus" fn GdipGraphicsClear(graphics: *Graphics, color: u32) callconv(.c) Status;
pub extern "gdiplus" fn GdipCreateSolidFill(color: u32, brush: **SolidFill) callconv(.c) Status;
pub extern "gdiplus" fn GdipDeleteBrush(brush: *Brush) callconv(.c) Status;

pub extern "gdiplus" fn GdipFillEllipse(
    graphics: *Graphics,
    brush: *Brush,
    x: f32,
    y: f32,
    width: f32,
    height: f32,
) callconv(.c) Status;

pub extern "gdiplus" fn GdipFillRectangle(
    graphics: *Graphics,
    brush: *Brush,
    x: f32,
    y: f32,
    width: f32,
    height: f32,
) callconv(.c) Status;

pub extern "gdiplus" fn GdipFillPolygon(
    graphics: *Graphics,
    brush: *Brush,
    points: [*]const PointF,
    count: i32,
    fill_mode: i32,
) callconv(.c) Status;

pub extern "gdiplus" fn GdipCreatePen1(
    color: u32,
    width: f32,
    unit: i32,
    pen: **Pen,
) callconv(.c) Status;

pub extern "gdiplus" fn GdipDeletePen(pen: *Pen) callconv(.c) Status;

pub extern "gdiplus" fn GdipDrawLine(
    graphics: *Graphics,
    pen: *Pen,
    x1: f32,
    y1: f32,
    x2: f32,
    y2: f32,
) callconv(.c) Status;

pub extern "gdiplus" fn GdipCreatePath(fill_mode: i32, path: **Path) callconv(.c) Status;
pub extern "gdiplus" fn GdipDeletePath(path: *Path) callconv(.c) Status;

pub extern "gdiplus" fn GdipAddPathArc(
    path: *Path,
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    start_angle: f32,
    sweep_angle: f32,
) callconv(.c) Status;

pub extern "gdiplus" fn GdipClosePathFigure(path: *Path) callconv(.c) Status;
pub extern "gdiplus" fn GdipFillPath(graphics: *Graphics, brush: *Brush, path: *Path) callconv(.c) Status;
pub extern "gdiplus" fn GdipDrawPath(graphics: *Graphics, pen: *Pen, path: *Path) callconv(.c) Status;

pub extern "gdiplus" fn GdipCreateFontFamilyFromName(
    name: [*:0]const u16,
    collection: ?*anyopaque,
    family: **FontFamily,
) callconv(.c) Status;

pub extern "gdiplus" fn GdipDeleteFontFamily(family: *FontFamily) callconv(.c) Status;

pub extern "gdiplus" fn GdipCreateFont(
    family: *FontFamily,
    size: f32,
    style: i32,
    unit: i32,
    font: **Font,
) callconv(.c) Status;

pub extern "gdiplus" fn GdipDeleteFont(font: *Font) callconv(.c) Status;
pub extern "gdiplus" fn GdipCreateStringFormat(flags: i32, lang: u16, format: **StringFormat) callconv(.c) Status;
pub extern "gdiplus" fn GdipDeleteStringFormat(format: *StringFormat) callconv(.c) Status;
pub extern "gdiplus" fn GdipSetStringFormatAlign(format: *StringFormat, alignment: i32) callconv(.c) Status;
pub extern "gdiplus" fn GdipSetStringFormatLineAlign(format: *StringFormat, alignment: i32) callconv(.c) Status;
pub extern "gdiplus" fn GdipSetStringFormatTrimming(format: *StringFormat, trimming: i32) callconv(.c) Status;

pub extern "gdiplus" fn GdipDrawString(
    graphics: *Graphics,
    str: [*]const u16,
    len: i32,
    font: *Font,
    rect: *const RectF,
    format: ?*StringFormat,
    brush: *Brush,
) callconv(.c) Status;

pub extern "gdiplus" fn GdipCreateBitmapFromScan0(
    width: i32,
    height: i32,
    stride: i32,
    format: i32,
    scan0: ?*anyopaque,
    bitmap: **Bitmap,
) callconv(.c) Status;

pub extern "gdiplus" fn GdipDisposeImage(image: *Bitmap) callconv(.c) Status;
pub extern "gdiplus" fn GdipGetImageGraphicsContext(image: *Bitmap, graphics: **Graphics) callconv(.c) Status;

pub extern "gdiplus" fn GdipBitmapLockBits(
    bitmap: *Bitmap,
    rect: ?*const anyopaque,
    flags: u32,
    format: i32,
    locked_data: *BitmapData,
) callconv(.c) Status;

pub extern "gdiplus" fn GdipBitmapUnlockBits(bitmap: *Bitmap, locked_data: *BitmapData) callconv(.c) Status;

pub fn create_rounded_rect_path(x: f32, y: f32, width: f32, height: f32, radius: f32) ?*Path {
    std.debug.assert(width >= 0);
    std.debug.assert(height >= 0);
    std.debug.assert(radius >= 0);
    std.debug.assert(radius <= width / 2);
    std.debug.assert(radius <= height / 2);

    var path: *Path = undefined;

    if (GdipCreatePath(0, &path) != .Ok) {
        return null;
    }

    const diameter = radius * 2;

    const arc_params = [arc_count_max]struct { x: f32, y: f32, start: f32 }{
        .{ .x = x, .y = y, .start = 180 },
        .{ .x = x + width - diameter, .y = y, .start = 270 },
        .{ .x = x + width - diameter, .y = y + height - diameter, .start = 0 },
        .{ .x = x, .y = y + height - diameter, .start = 90 },
    };

    var arc_index: u32 = 0;
    while (arc_index < arc_count_max) : (arc_index += 1) {
        std.debug.assert(arc_index < arc_count_max);

        const params = arc_params[arc_index];
        const status = GdipAddPathArc(path, params.x, params.y, diameter, diameter, params.start, 90);

        if (status != .Ok) {
            _ = GdipDeletePath(path);
            return null;
        }
    }

    std.debug.assert(arc_index == arc_count_max);

    if (GdipClosePathFigure(path) != .Ok) {
        _ = GdipDeletePath(path);
        return null;
    }

    return path;
}

pub fn fill_rounded_rect(
    graphics: *Graphics,
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    radius: f32,
    fill_color: u32,
    border_color: ?u32,
) void {
    std.debug.assert(width >= 0);
    std.debug.assert(height >= 0);
    std.debug.assert(radius >= 0);

    const path = create_rounded_rect_path(x, y, width, height, radius) orelse return;
    defer _ = GdipDeletePath(path);

    var brush: *SolidFill = undefined;

    if (GdipCreateSolidFill(fill_color, &brush) == .Ok) {
        defer _ = GdipDeleteBrush(@ptrCast(brush));
        _ = GdipFillPath(graphics, @ptrCast(brush), path);
    }

    if (border_color) |color| {
        var pen: *Pen = undefined;

        if (GdipCreatePen1(color, 1.0, unit_pixel, &pen) == .Ok) {
            defer _ = GdipDeletePen(pen);
            _ = GdipDrawPath(graphics, pen, path);
        }
    }
}

pub fn fill_ellipse(graphics: *Graphics, x: f32, y: f32, width: f32, height: f32, color: u32) void {
    std.debug.assert(width >= 0);
    std.debug.assert(height >= 0);

    var brush: *SolidFill = undefined;

    if (GdipCreateSolidFill(color, &brush) == .Ok) {
        defer _ = GdipDeleteBrush(@ptrCast(brush));
        _ = GdipFillEllipse(graphics, @ptrCast(brush), x, y, width, height);
    }
}

pub fn fill_rect(graphics: *Graphics, x: f32, y: f32, width: f32, height: f32, color: u32) void {
    std.debug.assert(width >= 0);
    std.debug.assert(height >= 0);

    var brush: *SolidFill = undefined;

    if (GdipCreateSolidFill(color, &brush) == .Ok) {
        defer _ = GdipDeleteBrush(@ptrCast(brush));
        _ = GdipFillRectangle(graphics, @ptrCast(brush), x, y, width, height);
    }
}

pub fn fill_polygon(graphics: *Graphics, points: []const PointF, color: u32) void {
    std.debug.assert(points.len > 0);
    std.debug.assert(points.len <= polygon_points_max);

    var brush: *SolidFill = undefined;

    if (GdipCreateSolidFill(color, &brush) == .Ok) {
        defer _ = GdipDeleteBrush(@ptrCast(brush));
        _ = GdipFillPolygon(graphics, @ptrCast(brush), points.ptr, @intCast(points.len), 0);
    }
}

pub fn draw_line(graphics: *Graphics, x1: f32, y1: f32, x2: f32, y2: f32, color: u32, width: f32) void {
    std.debug.assert(width > 0);

    var pen: *Pen = undefined;

    if (GdipCreatePen1(color, width, unit_pixel, &pen) == .Ok) {
        defer _ = GdipDeletePen(pen);
        _ = GdipDrawLine(graphics, pen, x1, y1, x2, y2);
    }
}

pub fn draw_x(graphics: *Graphics, center_x: f32, center_y: f32, size: f32, color: u32, width: f32) void {
    std.debug.assert(size > 0);
    std.debug.assert(width > 0);

    var pen: *Pen = undefined;

    if (GdipCreatePen1(color, width, unit_pixel, &pen) == .Ok) {
        defer _ = GdipDeletePen(pen);
        _ = GdipDrawLine(graphics, pen, center_x - size, center_y - size, center_x + size, center_y + size);
        _ = GdipDrawLine(graphics, pen, center_x + size, center_y - size, center_x - size, center_y + size);
    }
}

pub fn draw_text(
    graphics: *Graphics,
    text: []const u8,
    rect: RectF,
    color: u32,
    font: *Font,
    alignment_horizontal: i32,
    alignment_vertical: i32,
    ellipsis: bool,
) void {
    std.debug.assert(text.len <= text_buffer_len_max);
    std.debug.assert(rect.width >= 0);
    std.debug.assert(rect.height >= 0);

    var wide_buffer: [text_buffer_len_max]u16 = undefined;
    const wide_len = std.unicode.utf8ToUtf16Le(&wide_buffer, text) catch return;

    std.debug.assert(wide_len <= text_buffer_len_max);

    var format: *StringFormat = undefined;

    if (GdipCreateStringFormat(0, 0, &format) != .Ok) {
        return;
    }

    defer _ = GdipDeleteStringFormat(format);

    _ = GdipSetStringFormatAlign(format, alignment_horizontal);
    _ = GdipSetStringFormatLineAlign(format, alignment_vertical);

    if (ellipsis) {
        _ = GdipSetStringFormatTrimming(format, string_trimming_ellipsis_character);
    }

    var brush: *SolidFill = undefined;

    if (GdipCreateSolidFill(color, &brush) != .Ok) {
        return;
    }

    defer _ = GdipDeleteBrush(@ptrCast(brush));

    _ = GdipDrawString(graphics, &wide_buffer, @intCast(wide_len), font, &rect, format, @ptrCast(brush));
}
