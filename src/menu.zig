const wisp = @import("wisp");

const constant = @import("constant.zig");
const Mode = @import("mode.zig").Mode;

const App = wisp.App;

pub fn MenuManager(comptime mode: Mode) type {
    _ = mode;

    return struct {
        const Self = @This();

        app: *App,

        pub fn init(app: *App) Self {
            return Self{
                .app = app,
            };
        }

        pub fn build(self: *Self) void {
            const menu = self.app.get_menu();

            menu.clear();

            menu.add_action(constant.Menu.exit, "Exit") catch {};
        }
    };
}
