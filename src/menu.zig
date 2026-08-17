const std = @import("std");

const umbra = @import("umbra");

const constant = @import("constant.zig");

const assert = std.debug.assert;

const App = umbra.App;

pub const MenuManager = struct {
    app: *App,

    pub fn init(app: *App) MenuManager {
        const result = MenuManager{
            .app = app,
        };

        return result;
    }

    pub fn build(manager: *MenuManager) void {
        const menu = &manager.app.menu;

        menu.clear();

        assert(menu.is_empty());

        menu.add_action(constant.Menu.exit, "Exit") catch {
            return;
        };

        assert(!menu.is_empty());
    }

    pub fn push(manager: *MenuManager) void {
        manager.app.menu.build() catch {
            return;
        };
    }
};
