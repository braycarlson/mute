const std = @import("std");

const assert = std.debug.assert;

pub const Point = struct {
    x: f32 = 0,
    y: f32 = 0,
};

pub const Rect = struct {
    bottom: i32 = 0,
    left: i32 = 0,
    right: i32 = 0,
    top: i32 = 0,

    pub fn init(left: i32, top: i32, right: i32, bottom: i32) Rect {
        const result = Rect{ .bottom = bottom, .left = left, .right = right, .top = top };

        assert(result.is_valid());

        return result;
    }

    pub fn center(rect: Rect) Point {
        assert(rect.is_valid());

        return .{
            .x = @floatFromInt(rect.left + @divTrunc(rect.width(), 2)),
            .y = @floatFromInt(rect.top + @divTrunc(rect.height(), 2)),
        };
    }

    pub fn contains(rect: Rect, x: i32, y: i32) bool {
        assert(rect.is_valid());

        return x >= rect.left and x < rect.right and y >= rect.top and y < rect.bottom;
    }

    pub fn height(rect: Rect) i32 {
        return rect.bottom - rect.top;
    }

    pub fn is_valid(rect: Rect) bool {
        return rect.right >= rect.left and rect.bottom >= rect.top;
    }

    pub fn width(rect: Rect) i32 {
        return rect.right - rect.left;
    }
};

const testing = std.testing;

test "a rectangle reports its extent and its centre" {
    const rect = Rect.init(10, 20, 110, 60);

    try testing.expectEqual(@as(i32, 100), rect.width());
    try testing.expectEqual(@as(i32, 40), rect.height());
    try testing.expectEqual(@as(f32, 60), rect.center().x);
    try testing.expectEqual(@as(f32, 40), rect.center().y);
}

test "containment is inclusive on the near edge and exclusive on the far edge" {
    const rect = Rect.init(0, 0, 10, 10);

    try testing.expect(rect.contains(0, 0));
    try testing.expect(rect.contains(9, 9));
    try testing.expect(!rect.contains(10, 5));
    try testing.expect(!rect.contains(5, 10));
    try testing.expect(!rect.contains(-1, 5));
}

test "an empty rectangle is still valid and contains nothing" {
    const rect = Rect.init(5, 5, 5, 5);

    try testing.expect(rect.is_valid());
    try testing.expect(!rect.contains(5, 5));
}
