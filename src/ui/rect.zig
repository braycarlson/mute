const std = @import("std");

const kalymma = @import("kalymma");

const assert = std.debug.assert;

pub const coordinate_max: i32 = 1 << 24;

comptime {
    assert(coordinate_max > std.math.maxInt(i16));
}

pub const Point = struct {
    x: f32 = 0,
    y: f32 = 0,

    pub fn is_finite(point: Point) bool {
        if (!std.math.isFinite(point.x)) return false;
        return std.math.isFinite(point.y);
    }
};

pub const Rect = struct {
    bottom: i32 = 0,
    left: i32 = 0,
    right: i32 = 0,
    top: i32 = 0,

    pub fn center(rect: Rect) Point {
        assert(rect.is_valid());

        return .{
            .x = @floatFromInt(rect.left + @divTrunc(rect.width(), 2)),
            .y = @floatFromInt(rect.top + @divTrunc(rect.height(), 2)),
        };
    }

    pub fn contains(rect: Rect, point: kalymma.Point) bool {
        assert(rect.is_valid());
        assert(is_position(point));

        const inside_x = point.x >= rect.left and point.x < rect.right;
        const inside_y = point.y >= rect.top and point.y < rect.bottom;

        return inside_x and inside_y;
    }

    pub fn height(rect: Rect) i32 {
        assert(rect.bottom >= rect.top);

        return rect.bottom - rect.top;
    }

    pub fn is_valid(rect: Rect) bool {
        return rect.right >= rect.left and rect.bottom >= rect.top;
    }

    pub fn width(rect: Rect) i32 {
        assert(rect.right >= rect.left);

        return rect.right - rect.left;
    }
};

pub const Segment = struct {
    end: Point,
    start: Point,

    pub fn is_finite(segment: Segment) bool {
        if (!segment.end.is_finite()) return false;
        return segment.start.is_finite();
    }
};

pub fn is_coordinate(value: i32) bool {
    return value >= -coordinate_max and value <= coordinate_max;
}

pub fn is_position(point: kalymma.Point) bool {
    if (point.x < -coordinate_max) return false;
    if (point.x > coordinate_max) return false;
    if (point.y < -coordinate_max) return false;
    return point.y <= coordinate_max;
}

const testing = std.testing;

test Rect {
    const rect = Rect{ .left = 10, .top = 20, .right = 110, .bottom = 60 };

    try testing.expect(rect.is_valid());
    try testing.expectEqual(@as(i32, 100), rect.width());
    try testing.expectEqual(@as(i32, 40), rect.height());
    try testing.expectEqual(@as(f32, 60), rect.center().x);
    try testing.expectEqual(@as(f32, 40), rect.center().y);
}

test "containment is inclusive on the near edge and exclusive on the far edge" {
    const rect = Rect{ .left = 0, .top = 0, .right = 10, .bottom = 10 };

    try testing.expect(rect.contains(.{ .x = 0, .y = 0 }));
    try testing.expect(rect.contains(.{ .x = 9, .y = 9 }));
    try testing.expect(!rect.contains(.{ .x = 10, .y = 5 }));
    try testing.expect(!rect.contains(.{ .x = 5, .y = 10 }));
    try testing.expect(!rect.contains(.{ .x = -1, .y = 5 }));
}

test "an empty rectangle is still valid and contains nothing" {
    const rect = Rect{ .left = 5, .top = 5, .right = 5, .bottom = 5 };

    try testing.expect(rect.is_valid());
    try testing.expect(!rect.contains(.{ .x = 5, .y = 5 }));
}

test "a position is accepted exactly when both of its coordinates are" {
    const values = [_]i32{
        std.math.minInt(i32),
        -coordinate_max - 1,
        -coordinate_max,
        std.math.minInt(i16),
        0,
        std.math.maxInt(i16),
        coordinate_max,
        coordinate_max + 1,
        std.math.maxInt(i32),
    };

    for (values) |x| {
        for (values) |y| {
            const expected = is_coordinate(x) and is_coordinate(y);

            try testing.expectEqual(expected, is_position(.{ .x = x, .y = y }));
        }
    }
}

test "a point or segment with any coordinate that is not a finite number is not finite" {
    const infinity = std.math.inf(f32);
    const nan = std.math.nan(f32);

    try testing.expect((Point{ .x = 1, .y = -2 }).is_finite());
    try testing.expect(!(Point{ .x = nan, .y = 0 }).is_finite());
    try testing.expect(!(Point{ .x = 0, .y = -infinity }).is_finite());
    try testing.expect((Segment{ .end = .{ .x = 3 }, .start = .{ .y = 4 } }).is_finite());
    try testing.expect(!(Segment{ .end = .{}, .start = .{ .x = infinity } }).is_finite());
    try testing.expect(!(Segment{ .end = .{ .y = nan }, .start = .{} }).is_finite());
}
