const wisp = @import("wisp");

const IconManager = @import("icon.zig").IconManager;
const Mode = @import("mode.zig").Mode;

const App = wisp.App;

pub fn NotificationManager(comptime mode: Mode) type {
    return struct {
        const Self = @This();

        app: *App,
        icon: *IconManager(mode),

        pub fn init(app: *App, icon: *IconManager(mode)) Self {
            return Self{
                .app = app,
                .icon = icon,
            };
        }

        pub fn show(self: *Self, active: bool) void {
            const icon = self.icon.get_icon_for_state(active) orelse return;

            const title = mode.to_notification_title();
            const message = mode.to_notification_message(active);

            self.app.get_tray().show_balloon_with_icon(title, message, icon) catch {};
        }
    };
}
