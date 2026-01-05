const std = @import("std");

const wisp = @import("wisp");

const constant = @import("constant.zig");
const Mode = @import("mode.zig").Mode;

const App = wisp.App;
const Icon = wisp.Icon;
const IconBuilder = wisp.IconBuilder;

pub fn IconManager(comptime mode: Mode) type {
    _ = mode;

    return struct {
        const Self = @This();

        app: *App,

        pub fn init(app: *App) Self {
            return Self{
                .app = app,
            };
        }

        pub fn configure(self: *Self) void {
            _ = IconBuilder.init(self.app.get_icon())
                .resource("active", constant.Resource.mute_icon)
                .resource("inactive", constant.Resource.unmute_icon)
                .system("active_fallback", .shield)
                .system("inactive_fallback", .application)
                .done();

            self.app.get_icon().set_current("inactive") catch {
                self.app.get_icon().set_current("inactive_fallback") catch {};
            };
        }

        pub fn get_icon_for_state(self: *Self, active: bool) ?*const Icon {
            const name = if (active) "active" else "inactive";
            const fallback = if (active) "active_fallback" else "inactive_fallback";

            if (self.app.get_icon().get(name)) |icon| {
                return icon;
            }

            return self.app.get_icon().get(fallback);
        }

        pub fn update(self: *Self, active: bool) void {
            const name = if (active) "active" else "inactive";
            const fallback = if (active) "active_fallback" else "inactive_fallback";

            self.app.get_icon().set_current(name) catch {
                self.app.get_icon().set_current(fallback) catch {};
            };
        }
    };
}
