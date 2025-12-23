const std = @import("std");

const app = @import("app.zig");

const Mute = app.App(.capture);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var logger = app.initLogger(allocator, .capture);

    defer {
        if (logger) |*l| {
            l.deinit();
        }
    }

    defer {
        const check = gpa.deinit();

        if (check == .leak) {
            if (logger) |*l| {
                l.log("Memory leak detected!", .{});
            }
        }
    }

    var mute = try Mute.init(allocator, &logger);
    defer mute.deinit();

    mute.run();
}
