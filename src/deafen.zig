const std = @import("std");

const app = @import("app.zig");

const Deafen = app.App(.render);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var logger = app.initLogger(allocator, .render);

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

    var deafen = try Deafen.init(allocator, &logger);
    defer deafen.deinit();

    deafen.run();
}
