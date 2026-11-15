const std = @import("std");

const atlas = @import("atlas.zig");
const font = @import("font.zig");
const rect = @import("rect.zig");

const assert = std.debug.assert;

const Face = font.Face;
const Point = rect.Point;
const Rect = rect.Rect;
const Segment = rect.Segment;

const Align = enum {
    near,
    center,
    far,
};

const Overflow = enum {
    clip,
    ellipsis,
};

const Rounded = struct {
    border: ?u32 = null,
    color: u32,
    radius: f32,
};

const Text = struct {
    alignment: Align = .near,
    color: u32,
    face: Face,
    overflow: Overflow = .clip,
};

const polygon_points_max: u32 = 16;
const samples_per_axis: u32 = 4;
const spacing: f32 = @floatFromInt(samples_per_axis);

comptime {
    assert(samples_per_axis > 1);
    assert(polygon_points_max > 2);
}

pub const Canvas = struct {
    height: i32,
    pixels: []u32,
    width: i32,

    pub fn init(pixels: []u32, width: i32) Canvas {
        assert(width > 0);
        assert(pixels.len > 0);
        assert(pixels.len % @as(usize, @intCast(width)) == 0);

        const height: i32 = @intCast(pixels.len / @as(usize, @intCast(width)));
        return Canvas{ .height = height, .pixels = pixels, .width = width };
    }

    pub fn clear(canvas: *Canvas) void {
        @memset(canvas.pixels, 0);
    }

    pub fn draw_line(canvas: *Canvas, segment: Segment, thickness: f32, color: u32) void {
        assert(segment.is_finite());
        assert(thickness > 0);
        assert(color >> 24 > 0);

        canvas.fill_capsule(segment, thickness / 2.0, color);
    }

    pub fn draw_text(canvas: *Canvas, text: []const u8, bounds: Rect, options: Text) void {
        assert(text.len <= font.text_bytes_max);
        assert(bounds.is_valid());
        assert(options.color >> 24 > 0);

        if (text.len == 0) {
            return;
        }

        const face = options.face;

        var visible = text;
        var truncated = false;

        if (options.overflow == .ellipsis) {
            if (font.measure(face, text) > bounds.width()) {
                const budget = bounds.width() - font.measure(face, "...");

                visible = text[0..font.fit(face, text, @max(budget, 0))];
                truncated = true;
            }
        }

        if (options.overflow == .clip) {
            if (font.measure(face, text) > bounds.width()) {
                visible = text[0..font.fit(face, text, bounds.width())];
            }
        }

        const width = font.measure(face, visible) + if (truncated)
            font.measure(face, "...")
        else
            0;

        var pen = switch (options.alignment) {
            .near => bounds.left,
            .center => bounds.left + @divTrunc(bounds.width() - width, 2),
            .far => bounds.right - width,
        };

        const baseline = bounds.top + @divTrunc(bounds.height() + face.line_height(), 2) -
            (face.line_height() - face.ascent());

        pen = canvas.draw_run(face, visible, pen, baseline, options.color);

        if (truncated) {
            _ = canvas.draw_run(face, "...", pen, baseline, options.color);
        }
    }

    pub fn fill_capsule(canvas: *Canvas, segment: Segment, radius: f32, color: u32) void {
        assert(segment.is_finite());
        assert(radius >= 0);
        assert(color >> 24 > 0);

        const start = segment.start;
        const end = segment.end;
        const x_min: i32 = @intFromFloat(@floor(@min(start.x, end.x) - radius - 1));
        const y_min: i32 = @intFromFloat(@floor(@min(start.y, end.y) - radius - 1));
        const x_max: i32 = @intFromFloat(@ceil(@max(start.x, end.x) + radius + 1));
        const y_max: i32 = @intFromFloat(@ceil(@max(start.y, end.y) + radius + 1));

        var y = @max(y_min, 0);

        const bottom = @min(y_max, canvas.height);
        const left = @max(x_min, 0);
        const right = @min(x_max, canvas.width);

        while (y < bottom) : (y += 1) {
            var x = left;

            while (x < right) : (x += 1) {
                const sample = Point{
                    .x = @as(f32, @floatFromInt(x)) + 0.5,
                    .y = @as(f32, @floatFromInt(y)) + 0.5,
                };

                const distance = segment_distance(sample, segment) - radius;

                canvas.blend(x, y, color, coverage_of(distance));
            }
        }
    }

    pub fn fill_circle(canvas: *Canvas, center: Point, radius: f32, color: u32) void {
        assert(radius >= 0);
        assert(color >> 24 > 0);

        canvas.fill_capsule(.{ .end = center, .start = center }, radius, color);
    }

    pub fn fill_polygon(canvas: *Canvas, points: []const Point, color: u32) void {
        assert(points.len >= 3);
        assert(points.len <= polygon_points_max);
        assert(color >> 24 > 0);

        var x_min = points[0].x;
        var y_min = points[0].y;
        var x_max = points[0].x;
        var y_max = points[0].y;

        for (points) |point| {
            x_min = @min(x_min, point.x);
            y_min = @min(y_min, point.y);
            x_max = @max(x_max, point.x);
            y_max = @max(y_max, point.y);
        }

        var y: i32 = @max(@as(i32, @intFromFloat(@floor(y_min))), 0);

        const bottom = @min(@as(i32, @intFromFloat(@ceil(y_max))) + 1, canvas.height);
        const left = @max(@as(i32, @intFromFloat(@floor(x_min))), 0);
        const right = @min(@as(i32, @intFromFloat(@ceil(x_max))) + 1, canvas.width);

        while (y < bottom) : (y += 1) {
            var x = left;

            while (x < right) : (x += 1) {
                const coverage = sample_polygon(points, x, y);

                canvas.blend(x, y, color, coverage);
            }
        }
    }

    pub fn fill_rounded_rect(canvas: *Canvas, bounds: Rect, style: Rounded) void {
        assert(bounds.is_valid());
        assert(style.radius >= 0);

        const half_width = @as(f32, @floatFromInt(bounds.width())) / 2.0;
        const half_height = @as(f32, @floatFromInt(bounds.height())) / 2.0;
        const middle = bounds.center();

        var y = @max(bounds.top - 1, 0);

        const bottom = @min(bounds.bottom + 1, canvas.height);
        const left = @max(bounds.left - 1, 0);
        const right = @min(bounds.right + 1, canvas.width);

        while (y < bottom) : (y += 1) {
            var x = left;

            while (x < right) : (x += 1) {
                const px = @as(f32, @floatFromInt(x)) + 0.5 - middle.x;
                const py = @as(f32, @floatFromInt(y)) + 0.5 - middle.y;
                const distance = rounded_box(px, py, half_width, half_height, style.radius);

                canvas.blend(x, y, style.color, coverage_of(distance));

                if (style.border) |stroke| {
                    const edge = @abs(distance + 0.5) - 0.5;

                    canvas.blend(x, y, stroke, coverage_of(edge));
                }
            }
        }
    }

    fn blend(canvas: *Canvas, x: i32, y: i32, color: u32, coverage: f32) void {
        assert(rect.is_coordinate(x));
        assert(rect.is_coordinate(y));
        assert(coverage >= 0.0);
        assert(coverage <= 1.0);

        if (coverage <= 0.0) {
            return;
        }

        if (x < 0) {
            return;
        }

        if (y < 0) {
            return;
        }

        if (x >= canvas.width) {
            return;
        }

        if (y >= canvas.height) {
            return;
        }

        const alpha = @as(f32, @floatFromInt(color >> 24)) / 255.0 * @min(coverage, 1.0);

        if (alpha <= 0.0) {
            return;
        }

        const index: usize = @intCast(y * canvas.width + x);
        const destination = canvas.pixels[index];
        const red = channel(color, 16) * alpha;
        const green = channel(color, 8) * alpha;
        const blue = channel(color, 0) * alpha;
        const keep = 1.0 - alpha;
        const out_a = alpha + channel(destination, 24) * keep;
        const out_r = red + channel(destination, 16) * keep;
        const out_g = green + channel(destination, 8) * keep;
        const out_b = blue + channel(destination, 0) * keep;

        canvas.pixels[index] = pack(out_a, out_r, out_g, out_b);
    }

    fn blit(
        canvas: *Canvas,
        face: Face,
        glyph: atlas.Glyph,
        pen: i32,
        baseline: i32,
        color: u32,
    ) void {
        assert(glyph.x + glyph.width <= atlas.width);
        assert(rect.is_coordinate(pen));
        assert(rect.is_coordinate(baseline));
        assert(color >> 24 > 0);
        assert((glyph.y + glyph.height) * atlas.width <= face.mask().len);

        if (glyph.width == 0) {
            return;
        }

        if (glyph.height == 0) {
            return;
        }

        const mask = face.mask();
        const top = baseline - face.ascent() + glyph.top;
        const left = pen + glyph.left;

        var row: u32 = 0;

        while (row < glyph.height) : (row += 1) {
            assert(row < glyph.height);

            var column: u32 = 0;

            while (column < glyph.width) : (column += 1) {
                const index = (glyph.y + row) * atlas.width + glyph.x + column;

                if (index >= mask.len) {
                    continue;
                }

                const coverage = @as(f32, @floatFromInt(mask[index])) / 255.0;

                canvas.blend(
                    left + @as(i32, @intCast(column)),
                    top + @as(i32, @intCast(row)),
                    color,
                    coverage,
                );
            }
        }
    }

    fn draw_run(
        canvas: *Canvas,
        face: Face,
        text: []const u8,
        origin: i32,
        baseline: i32,
        color: u32,
    ) i32 {
        assert(text.len <= font.text_bytes_max);
        assert(rect.is_coordinate(origin));
        assert(rect.is_coordinate(baseline));
        assert(color >> 24 > 0);

        var cursor: usize = 0;
        var pen_scaled = origin * font.advance_scale;

        for (0..text.len) |_| {
            if (cursor == text.len) break;

            const codepoint = font.decode(text, &cursor);
            const glyph = face.glyph(codepoint);

            canvas.blit(face, glyph, font.to_pixels(pen_scaled), baseline, color);

            pen_scaled += glyph.advance_scaled;
        }

        assert(cursor == text.len);

        return font.to_pixels(pen_scaled);
    }

    fn fill_rect(canvas: *Canvas, bounds: Rect, color: u32) void {
        assert(bounds.is_valid());
        assert(color >> 24 > 0);

        var y = @max(bounds.top, 0);

        const bottom = @min(bounds.bottom, canvas.height);
        const left = @max(bounds.left, 0);
        const right = @min(bounds.right, canvas.width);

        while (y < bottom) : (y += 1) {
            var x = left;

            while (x < right) : (x += 1) {
                canvas.blend(x, y, color, 1.0);
            }
        }
    }
};

fn channel(color: u32, shift: u5) f32 {
    assert(shift % 8 == 0);

    const value: u8 = @truncate(color >> shift);
    const result = @as(f32, @floatFromInt(value)) / 255.0;

    assert(result >= 0.0);
    assert(result <= 1.0);

    return result;
}

fn contains_point(points: []const Point, x: f32, y: f32) bool {
    assert(points.len >= 3);
    assert(std.math.isFinite(x));
    assert(std.math.isFinite(y));

    var inside = false;
    var index: usize = 0;
    var previous = points.len - 1;

    while (index < points.len) : (index += 1) {
        const current = points[index];
        const other = points[previous];
        const straddles = (current.y > y) != (other.y > y);

        if (straddles) {
            const span = other.y - current.y;
            const crossing = (other.x - current.x) * (y - current.y) / span + current.x;

            if (x < crossing) inside = !inside;
        }

        previous = index;
    }

    return inside;
}

fn coverage_of(distance: f32) f32 {
    assert(!std.math.isNan(distance));

    const result = std.math.clamp(0.5 - distance, 0.0, 1.0);

    assert(result >= 0.0);
    assert(result <= 1.0);

    return result;
}

fn pack(a: f32, r: f32, g: f32, b: f32) u32 {
    assert(!std.math.isNan(a));
    assert(!std.math.isNan(r));
    assert(!std.math.isNan(g));
    assert(!std.math.isNan(b));

    const alpha: u32 = to_byte(a);
    const red: u32 = to_byte(r);
    const green: u32 = to_byte(g);
    const blue: u32 = to_byte(b);

    return (alpha << 24) | (red << 16) | (green << 8) | blue;
}

fn rounded_box(px: f32, py: f32, half_width: f32, half_height: f32, radius: f32) f32 {
    assert(std.math.isFinite(px));
    assert(std.math.isFinite(py));
    assert(half_width >= 0.0);
    assert(half_height >= 0.0);
    assert(radius >= 0.0);

    const limit = @min(radius, @min(half_width, half_height));
    const qx = @abs(px) - half_width + limit;
    const qy = @abs(py) - half_height + limit;
    const outside_x = @max(qx, 0.0);
    const outside_y = @max(qy, 0.0);
    const outside = @sqrt(outside_x * outside_x + outside_y * outside_y);
    const inside = @min(@max(qx, qy), 0.0);
    const result = outside + inside - limit;

    assert(!std.math.isNan(result));

    return result;
}

fn sample_polygon(points: []const Point, x: i32, y: i32) f32 {
    assert(points.len >= 3);
    assert(points.len <= polygon_points_max);
    assert(x >= 0);
    assert(y >= 0);

    var hits: u32 = 0;
    var row: u32 = 0;

    while (row < samples_per_axis) : (row += 1) {
        assert(row < samples_per_axis);

        var column: u32 = 0;

        while (column < samples_per_axis) : (column += 1) {
            const offset_x = (@as(f32, @floatFromInt(column)) + 0.5) / spacing;
            const offset_y = (@as(f32, @floatFromInt(row)) + 0.5) / spacing;
            const sx = @as(f32, @floatFromInt(x)) + offset_x;
            const sy = @as(f32, @floatFromInt(y)) + offset_y;

            if (contains_point(points, sx, sy)) hits += 1;
        }
    }

    const total = samples_per_axis * samples_per_axis;
    const result = @as(f32, @floatFromInt(hits)) / @as(f32, @floatFromInt(total));

    assert(result >= 0.0);
    assert(result <= 1.0);

    return result;
}

fn segment_distance(point: Point, segment: Segment) f32 {
    assert(point.is_finite());
    assert(segment.is_finite());

    const x0 = segment.start.x;
    const y0 = segment.start.y;
    const dx = segment.end.x - x0;
    const dy = segment.end.y - y0;
    const length = dx * dx + dy * dy;

    if (length <= 0.0) {
        const direct = @sqrt((point.x - x0) * (point.x - x0) + (point.y - y0) * (point.y - y0));
        assert(direct >= 0.0);

        return direct;
    }

    const raw = ((point.x - x0) * dx + (point.y - y0) * dy) / length;
    const t = std.math.clamp(raw, 0.0, 1.0);
    const cx = x0 + t * dx;
    const cy = y0 + t * dy;
    const result = @sqrt((point.x - cx) * (point.x - cx) + (point.y - cy) * (point.y - cy));

    assert(result >= 0.0);

    return result;
}

fn to_byte(value: f32) u32 {
    assert(!std.math.isNan(value));

    const scaled = std.math.clamp(value, 0.0, 1.0) * 255.0 + 0.5;
    const result: u32 = @intFromFloat(scaled);

    assert(result <= 255);

    return result;
}

const testing = std.testing;

fn scratch(pixels: []u32, width: i32) Canvas {
    assert(width > 0);
    assert(pixels.len > 0);

    var canvas = Canvas.init(pixels, width);

    canvas.clear();

    return canvas;
}

fn ink_in(pixels: []const u32) u32 {
    assert(pixels.len > 0);

    var total: u32 = 0;

    for (pixels) |pixel| {
        if (pixel >> 24 > 0) total += 1;
    }

    return total;
}

test Canvas {
    var pixels: [4096]u32 = undefined;
    var canvas = scratch(&pixels, 128);

    try testing.expectEqual(@as(i32, 32), canvas.height);

    canvas.fill_rounded_rect(
        .{ .left = 0, .top = 0, .right = 64, .bottom = 32 },
        .{ .color = 0xFF204060, .radius = 8 },
    );

    canvas.fill_circle(.{ .x = 96, .y = 16 }, 8, 0xFFFFFFFF);

    canvas.draw_text("Volume", .{ .left = 0, .top = 0, .right = 128, .bottom = 32 }, .{
        .color = 0xFFFFFFFF,
        .face = .regular_small,
    });

    try testing.expectEqual(@as(u32, 0xFF), pixels[16 * 128 + 96] >> 24);
    try testing.expect(pixels[0] >> 24 < 0xFF);
    try testing.expect(ink_in(&pixels) > 0);
}

test "a cleared canvas is fully transparent" {
    var pixels: [64]u32 = @splat(0xFFFFFFFF);
    var canvas = scratch(&pixels, 8);

    _ = &canvas;

    for (pixels) |pixel| {
        try testing.expectEqual(@as(u32, 0), pixel);
    }
}

test "an opaque fill lands exactly inside its rectangle" {
    var pixels: [64]u32 = undefined;
    var canvas = scratch(&pixels, 8);

    canvas.fill_rect(.{ .left = 2, .top = 2, .right = 6, .bottom = 6 }, 0xFF204060);

    try testing.expectEqual(@as(u32, 0xFF204060), pixels[2 * 8 + 2]);
    try testing.expectEqual(@as(u32, 0xFF204060), pixels[5 * 8 + 5]);
    try testing.expectEqual(@as(u32, 0), pixels[1 * 8 + 1]);
    try testing.expectEqual(@as(u32, 0), pixels[6 * 8 + 6]);
}

test "drawing outside the canvas is clipped rather than wrapping" {
    var pixels: [64]u32 = undefined;
    var canvas = scratch(&pixels, 8);

    canvas.fill_rect(.{ .left = -10, .top = -10, .right = 20, .bottom = 20 }, 0xFFFFFFFF);

    for (pixels) |pixel| {
        try testing.expectEqual(@as(u32, 0xFFFFFFFF), pixel);
    }

    canvas.blend(100, 100, 0xFF000000, 1.0);
    canvas.blend(-1, 0, 0xFF000000, 1.0);
}

test "a translucent source composites over what is already there" {
    var pixels: [4]u32 = undefined;
    var canvas = scratch(&pixels, 2);

    canvas.blend(0, 0, 0xFF000000, 1.0);
    canvas.blend(0, 0, 0x80FFFFFF, 1.0);

    const blended = pixels[0];

    try testing.expectEqual(@as(u32, 0xFF), blended >> 24);
    try testing.expect(blended & 0xFF > 0x70);
    try testing.expect(blended & 0xFF < 0x90);
}

test "zero coverage never touches the destination" {
    var pixels: [4]u32 = undefined;
    var canvas = scratch(&pixels, 2);

    canvas.blend(0, 0, 0xFFFFFFFF, 0.0);
    canvas.blend(1, 1, 0x00FFFFFF, 1.0);

    try testing.expectEqual(@as(u32, 0), pixels[0]);
    try testing.expectEqual(@as(u32, 0), pixels[3]);
}

test "a rounded rectangle leaves its corners lighter than its middle" {
    var pixels: [1024]u32 = undefined;
    var canvas = scratch(&pixels, 32);

    const bounds = Rect{ .left = 0, .top = 0, .right = 32, .bottom = 32 };

    canvas.fill_rounded_rect(bounds, .{ .color = 0xFFFFFFFF, .radius = 8 });

    const corner = pixels[0] >> 24;
    const middle = pixels[16 * 32 + 16] >> 24;

    try testing.expectEqual(@as(u32, 0xFF), middle);
    try testing.expect(corner < middle);
}

test "a circle covers its centre and misses its corners" {
    var pixels: [1024]u32 = undefined;
    var canvas = scratch(&pixels, 32);

    canvas.fill_circle(.{ .x = 16, .y = 16 }, 8, 0xFFFFFFFF);

    try testing.expectEqual(@as(u32, 0xFF), pixels[16 * 32 + 16] >> 24);
    try testing.expectEqual(@as(u32, 0), pixels[0] >> 24);
}

test "a capsule spans both of its ends" {
    var pixels: [1024]u32 = undefined;
    var canvas = scratch(&pixels, 32);

    const segment = Segment{ .end = .{ .x = 24, .y = 16 }, .start = .{ .x = 8, .y = 16 } };

    canvas.fill_capsule(segment, 3, 0xFFFFFFFF);

    try testing.expectEqual(@as(u32, 0xFF), pixels[16 * 32 + 8] >> 24);
    try testing.expectEqual(@as(u32, 0xFF), pixels[16 * 32 + 24] >> 24);
    try testing.expectEqual(@as(u32, 0xFF), pixels[16 * 32 + 16] >> 24);
    try testing.expectEqual(@as(u32, 0), pixels[2 * 32 + 16] >> 24);
}

test "a triangle fills its interior and leaves the outside alone" {
    var pixels: [1024]u32 = undefined;
    var canvas = scratch(&pixels, 32);

    const points = [_]Point{ .{ .x = 4, .y = 4 }, .{ .x = 28, .y = 16 }, .{ .x = 4, .y = 28 } };

    canvas.fill_polygon(&points, 0xFFFFFFFF);

    try testing.expectEqual(@as(u32, 0xFF), pixels[16 * 32 + 8] >> 24);
    try testing.expectEqual(@as(u32, 0), pixels[2 * 32 + 30] >> 24);
}

test "point containment agrees with the winding of the polygon" {
    const points = [_]Point{
        .{ .x = 0, .y = 0 },
        .{ .x = 10, .y = 0 },
        .{ .x = 10, .y = 10 },
        .{ .x = 0, .y = 10 },
    };

    try testing.expect(contains_point(&points, 5, 5));
    try testing.expect(!contains_point(&points, 15, 5));
    try testing.expect(!contains_point(&points, 5, -1));
}

test "text lands inside its rectangle and shifts with the alignment" {
    var pixels: [4096]u32 = undefined;
    var canvas = scratch(&pixels, 128);

    const bounds = Rect{ .left = 0, .top = 0, .right = 128, .bottom = 32 };

    canvas.draw_text("Volume", bounds, .{ .color = 0xFFFFFFFF, .face = .regular_small });

    try testing.expect(ink_in(pixels[0..2048]) > 0);

    canvas.clear();

    canvas.draw_text("Volume", bounds, .{
        .alignment = .far,
        .color = 0xFFFFFFFF,
        .face = .regular_small,
    });

    var far_left: u32 = 0;
    var row: usize = 0;

    while (row < 32) : (row += 1) {
        var column: usize = 0;

        while (column < 32) : (column += 1) {
            if (pixels[row * 128 + column] >> 24 > 0) far_left += 1;
        }
    }

    try testing.expectEqual(@as(u32, 0), far_left);
}

test "an empty string draws nothing" {
    var pixels: [4096]u32 = undefined;
    var canvas = scratch(&pixels, 128);

    const bounds = Rect{ .left = 0, .top = 0, .right = 128, .bottom = 32 };

    canvas.draw_text("", bounds, .{ .color = 0xFFFFFFFF, .face = .regular_small });

    for (pixels) |pixel| {
        try testing.expectEqual(@as(u32, 0), pixel);
    }
}

test "an over long string is truncated with an ellipsis rather than overflowing" {
    var pixels: [4096]u32 = undefined;
    var canvas = scratch(&pixels, 128);

    const text = "A very long capture device name that cannot possibly fit";
    const bounds = Rect{ .left = 0, .top = 0, .right = 60, .bottom = 32 };

    canvas.draw_text(text, bounds, .{
        .color = 0xFFFFFFFF,
        .face = .regular_small,
        .overflow = .ellipsis,
    });

    var overflow: u32 = 0;
    var row: usize = 0;

    while (row < 32) : (row += 1) {
        var column: usize = 64;

        while (column < 128) : (column += 1) {
            if (pixels[row * 128 + column] >> 24 > 0) overflow += 1;
        }
    }

    try testing.expectEqual(@as(u32, 0), overflow);
}

test "an over long string is clipped to its bounds by default" {
    var pixels: [4096]u32 = undefined;
    var canvas = scratch(&pixels, 128);

    const text = "A very long capture device name that cannot possibly fit";
    const bounds = Rect{ .left = 0, .top = 0, .right = 60, .bottom = 32 };

    canvas.draw_text(text, bounds, .{ .color = 0xFFFFFFFF, .face = .regular_small });

    var overflow: u32 = 0;
    var row: usize = 0;

    while (row < 32) : (row += 1) {
        var column: usize = 64;

        while (column < 128) : (column += 1) {
            if (pixels[row * 128 + column] >> 24 > 0) overflow += 1;
        }
    }

    try testing.expectEqual(@as(u32, 0), overflow);
    try testing.expect(ink_in(&pixels) > 0);
}

test "malformed text still renders visible ink" {
    var pixels: [4096]u32 = undefined;
    var canvas = scratch(&pixels, 128);

    const text = [_]u8{ 'a', 0xFF, 0xFE, 'b' };
    const bounds = Rect{ .left = 0, .top = 0, .right = 128, .bottom = 32 };

    canvas.draw_text(&text, bounds, .{ .color = 0xFFFFFFFF, .face = .regular_small });

    try testing.expect(ink_in(&pixels) > 0);
}
