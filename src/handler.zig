const std = @import("std");

const wisp = @import("wisp");

const constant = @import("constant.zig");
const DeviceEvent = @import("device/notifier.zig").DeviceEvent;
const Mode = @import("mode.zig").Mode;

const App = wisp.App;
const Event = wisp.Event;
const Response = wisp.Response;

pub const Dispatcher = struct {
    on_config_reload: *const fn () void,
    on_device_event: *const fn (DeviceEvent) void,
    on_exit: *const fn () void,
    on_init: *const fn () void,
    on_menu_show: *const fn () void,
    on_open_settings: *const fn () void,
    on_shutdown: *const fn () void,
    on_timer_tick: *const fn (u32) void,
    on_toggle_state: *const fn () void,
    on_tray_click: *const fn () void,
};

pub fn EventHandler(comptime mode: Mode) type {
    _ = mode;

    return struct {
        const Self = @This();

        app: *App,
        dispatcher: *const Dispatcher,

        pub fn init(app: *App, dispatcher: *const Dispatcher) Self {
            return Self{
                .app = app,
                .dispatcher = dispatcher,
            };
        }

        pub fn register(self: *Self) void {
            _ = self.app.event_bus().on(.app_init, on_app_init, self);
            _ = self.app.event_bus().on(.app_shutdown, on_app_shutdown, self);
            _ = self.app.event_bus().on(.icon_change, on_icon_change, self);
            _ = self.app.event_bus().on(.menu_select, on_menu_select, self);
            _ = self.app.event_bus().on(.menu_show, on_menu_show, self);
            _ = self.app.event_bus().on(.taskbar_restart, on_taskbar_restart, self);
            _ = self.app.event_bus().on(.timer_tick, on_timer_tick, self);
            _ = self.app.event_bus().on(.tray_left_click, on_tray_click, self);
            _ = self.app.event_bus().on(.window_message, on_window_message, self);
        }

        fn on_app_init(e: *const Event, ctx: ?*anyopaque) Response {
            _ = e;

            const handler: *Self = @ptrCast(@alignCast(ctx orelse return .pass));
            handler.dispatcher.on_init();

            return .pass;
        }

        fn on_app_shutdown(e: *const Event, ctx: ?*anyopaque) Response {
            _ = e;

            const handler: *Self = @ptrCast(@alignCast(ctx orelse return .pass));
            handler.dispatcher.on_shutdown();

            return .pass;
        }

        fn on_icon_change(e: *const Event, ctx: ?*anyopaque) Response {
            const handler: *Self = @ptrCast(@alignCast(ctx orelse return .pass));
            const data = e.payload.icon_change;

            const icon = handler.app.get_icon().get(data.name) orelse return .pass;

            handler.app.get_tray().set_icon(icon) catch {};

            return .pass;
        }

        fn on_menu_select(e: *const Event, ctx: ?*anyopaque) Response {
            const handler: *Self = @ptrCast(@alignCast(ctx orelse return .pass));
            const data = e.payload.menu_select;

            handle_command(handler, data.id);

            return .pass;
        }

        fn on_menu_show(e: *const Event, ctx: ?*anyopaque) Response {
            _ = e;

            const handler: *Self = @ptrCast(@alignCast(ctx orelse return .pass));
            handler.dispatcher.on_menu_show();

            return .pass;
        }

        fn on_taskbar_restart(e: *const Event, ctx: ?*anyopaque) Response {
            _ = e;
            _ = ctx;

            return .pass;
        }

        fn on_timer_tick(e: *const Event, ctx: ?*anyopaque) Response {
            const handler: *Self = @ptrCast(@alignCast(ctx orelse return .pass));
            const data = e.payload.timer_tick;

            handler.dispatcher.on_timer_tick(data.id);

            return .pass;
        }

        fn on_tray_click(e: *const Event, ctx: ?*anyopaque) Response {
            _ = e;

            const handler: *Self = @ptrCast(@alignCast(ctx orelse return .pass));
            handler.dispatcher.on_tray_click();

            return .pass;
        }

        fn on_window_message(e: *const Event, ctx: ?*anyopaque) Response {
            const handler: *Self = @ptrCast(@alignCast(ctx orelse return .pass));
            const data = e.payload.window_message;

            if (data.message == constant.wm_config_reload) {
                handler.dispatcher.on_config_reload();
                return .handled;
            }

            if (data.message == constant.wm_device_event) {
                const event: DeviceEvent = @enumFromInt(data.wparam);
                handler.dispatcher.on_device_event(event);
                return .handled;
            }

            return .pass;
        }

        fn handle_command(handler: *Self, command: u32) void {
            switch (command) {
                constant.Menu.exit => handler.dispatcher.on_exit(),
                else => {},
            }
        }
    };
}
