const std = @import("std");

const gdiplus = @import("gdiplus.zig");

pub const GdiplusContext = struct {
    token: usize = 0,

    pub fn init() GdiplusContext {
        var self = GdiplusContext{};
        var input = gdiplus.StartupInput{};

        const status = gdiplus.GdiplusStartup(&self.token, &input, null);

        std.debug.assert((status == .Ok) == (self.token != 0));

        return self;
    }

    pub fn deinit(self: *GdiplusContext) void {
        if (self.token != 0) {
            gdiplus.GdiplusShutdown(self.token);
            self.token = 0;
        }

        std.debug.assert(self.token == 0);
    }

    pub fn is_valid(self: *const GdiplusContext) bool {
        return self.token != 0;
    }
};
