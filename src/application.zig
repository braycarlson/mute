const std = @import("std");

const w32 = @import("win32").everything;

const nimble = @import("nimble");
const wca = @import("wca");
const wisp = @import("wisp");

const constant = @import("constant.zig");
const Config = @import("config.zig").Config;
const DeviceConfig = @import("config.zig").DeviceConfig;
const DeviceEvent = @import("device/notifier.zig").DeviceEvent;
const DeviceManager = @import("device/manager.zig").DeviceManager;
const DeviceNotifier = @import("device/notifier.zig").DeviceNotifier;
const Dispatcher = @import("handler.zig").Dispatcher;
const EventHandler = @import("handler.zig").EventHandler;
const HotkeyHandler = @import("hotkey.zig").HotkeyHandler;
const IconManager = @import("icon.zig").IconManager;
const Logger = @import("logger.zig").Logger;
const MenuManager = @import("menu.zig").MenuManager;
const Mode = @import("mode.zig").Mode;
const SettingsManager = @import("settings.zig").SettingsManager;
const Widget = @import("widget.zig").Widget;
const WidgetEvent = @import("widget.zig").WidgetEvent;

const App = wisp.App;

const queue_capacity: u32 = 16;

pub fn Application(comptime mode: Mode) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        active: bool,
        app: App,
        configuration: Config,
        devices: DeviceManager(mode),
        handler: EventHandler(mode),
        hotkey: HotkeyHandler(queue_capacity),
        icon: IconManager(mode),
        logger: *?Logger,
        menu: MenuManager(mode),
        notifier: DeviceNotifier(mode),
        settings: SettingsManager,
        widget: ?*Widget,

        var instance: std.atomic.Value(?*Self) = std.atomic.Value(?*Self).init(null);

        const dispatcher = Dispatcher{
            .on_config_reload = dispatch_config_reload,
            .on_device_event = dispatch_device_event,
            .on_exit = dispatch_exit,
            .on_init = dispatch_init,
            .on_menu_show = dispatch_menu_show,
            .on_open_settings = dispatch_open_settings,
            .on_shutdown = dispatch_shutdown,
            .on_timer_tick = dispatch_timer_tick,
            .on_toggle_state = dispatch_toggle_state,
            .on_tray_click = dispatch_tray_click,
        };

        pub fn init(allocator: std.mem.Allocator, logger: *?Logger) !Self {
            wca.com.initialize(wca.com.COINIT_APARTMENTTHREADED) catch {
                return error.ComInitFailed;
            };

            const configuration = load_configuration(allocator, logger);

            var app = App.init(.{
                .name = mode.to_title(),
                .tooltip = mode.to_tray_title(),
                .initial_state = "inactive",
            });

            _ = app.configure();

            return Self{
                .allocator = allocator,
                .active = false,
                .app = app,
                .configuration = configuration,
                .devices = DeviceManager(mode).init(allocator),
                .handler = undefined,
                .hotkey = HotkeyHandler(queue_capacity).init(),
                .icon = undefined,
                .logger = logger,
                .menu = undefined,
                .notifier = undefined,
                .settings = undefined,
                .widget = null,
            };
        }

        pub fn configure(self: *Self) !void {
            self.icon = IconManager(mode).init(&self.app);
            self.icon.configure();

            self.menu = MenuManager(mode).init(&self.app);

            self.settings = SettingsManager.init(&self.configuration, self.logger);

            self.handler = EventHandler(mode).init(&self.app, &dispatcher);

            self.setup_hotkey();
            self.setup_devices();

            self.log("Application is ready");
        }

        pub fn deinit(self: *Self) void {
            self.log("Shutting down");

            instance.store(null, .seq_cst);

            if (self.widget) |widget| {
                widget.destroy();
            }

            self.notifier.deinit();
            self.hotkey.deinit();
            self.devices.deinit();
            self.settings.deinit();
            self.app.deinit();
            self.configuration.deinit();
        }

        pub fn run(self: *Self) void {
            instance.store(self, .seq_cst);

            self.configure() catch |err| {
                self.log_error("Failed to configure application", err);
                return;
            };

            self.handler.register();

            self.app.run() catch |err| {
                self.log_error("Failed to run application", err);
            };
        }

        fn activate(self: *Self) void {
            if (self.devices.current) |*device| {
                device.mute();
                self.active = true;
                self.icon.update(true);
                self.update_widget();
                self.log(mode.to_action(true));
            }
        }

        fn deactivate(self: *Self) void {
            if (self.devices.current) |*device| {
                device.unmute();
                self.active = false;
                self.icon.update(false);
                self.update_widget();
                self.log(mode.to_action(false));
            }
        }

        fn get_device_config(self: *Self) *DeviceConfig {
            return switch (mode) {
                .capture => &self.configuration.capture,
                .render => &self.configuration.render,
            };
        }

        fn log(self: *Self, message: []const u8) void {
            if (self.logger.*) |*logger| {
                logger.log("{s}", .{message});
            }
        }

        fn log_error(self: *Self, message: []const u8, err: anyerror) void {
            if (self.logger.*) |*logger| {
                logger.log("{s}: {}", .{ message, err });
            }
        }

        fn log_device_info(self: *Self) void {
            if (self.logger.*) |*l| {
                if (self.get_device_config().get_name()) |name| {
                    l.log("Using {s} device: {s}", .{ mode.to_string(), name });
                } else {
                    l.log("Using default {s} device", .{mode.to_string()});
                }
            }
        }

        fn on_config_reload(self: *Self) void {
            if (!self.settings.reload()) {
                return;
            }

            self.hotkey.set_hotkey(self.get_device_config().get_hotkey());

            self.log("Config reloaded");
        }

        fn on_device_event(self: *Self, event: DeviceEvent) void {
            switch (event) {
                .added, .removed, .state_changed => {
                    self.devices.enumerate();

                    if (self.devices.current == null) {
                        self.devices.current = self.devices.find(self.get_device_config());
                    }

                    self.devices.update_index();
                    self.update_widget();
                },
                .default_changed => {
                    self.devices.restore_default() catch {};
                    self.update_widget();
                },
            }
        }

        fn on_exit(self: *Self) void {
            self.log("Exiting");
            self.app.quit();
        }

        fn on_init(self: *Self) void {
            const hwnd = self.app.get_hwnd() orelse return;

            self.notifier = DeviceNotifier(mode).init(
                self.allocator,
                hwnd,
                constant.wm_device_event,
            );

            self.notifier.register() catch |err| {
                self.log_error("Could not register device notifications", err);
            };

            _ = self.app.get_timer().start(
                constant.Timer.rehook_id,
                constant.Timer.rehook_interval_ms,
            ) catch null;

            self.settings.watch(on_config_file_changed);

            self.setup_widget();
        }

        fn on_menu_show(self: *Self) void {
            self.menu.build();
        }

        fn on_open_settings(self: *Self) void {
            if (self.widget) |widget| {
                self.update_widget();
                widget.show();
            }
        }

        fn on_shutdown(self: *Self) void {
            self.hotkey.deinit();
        }

        fn on_timer_tick(self: *Self, timer_id: u32) void {
            if (timer_id == constant.Timer.rehook_id) {
                self.refresh_hooks();
            }
        }

        fn on_toggle_state(self: *Self) void {
            self.toggle();
        }

        fn on_tray_click(self: *Self) void {
            if (self.widget) |widget| {
                widget.post_toggle();
            }
        }

        fn refresh_hooks(self: *Self) void {
            if (!self.hotkey.is_running()) {
                self.hotkey.install();
            }
        }

        fn setup_devices(self: *Self) void {
            self.devices.enumerate();
            self.devices.current = self.devices.find(self.get_device_config());
            self.devices.update_index();

            if (self.devices.current) |*device| {
                device.set_volume(self.get_device_config().volume);
                self.active = device.is_muted();
                self.devices.restore_default() catch {};
                self.icon.update(self.active);
                self.log_device_info();
            } else {
                if (self.logger.*) |*l| {
                    l.log("No {s} device found", .{mode.to_string()});
                }
            }
        }

        fn setup_hotkey(self: *Self) void {
            self.hotkey.set_hotkey(self.get_device_config().get_hotkey());
            self.hotkey.set_callback(hotkey_callback);
            self.hotkey.install();
        }

        fn setup_widget(self: *Self) void {
            const hwnd = self.app.get_hwnd() orelse return;

            self.widget = Widget.create(
                self.allocator,
                hwnd,
                mode.to_widget_class(),
            ) catch {
                self.log("Could not create widget");
                return;
            };

            if (self.widget) |widget| {
                widget.set_callback(handle_widget_event, self);
                widget.set_default_volume(self.get_device_config().volume);
                widget.set_title(mode.to_widget_title());
            }

            self.update_widget();
        }

        fn toggle(self: *Self) void {
            if (self.devices.current) |*device| {
                self.active = device.toggle_mute();
                self.icon.update(self.active);
                self.update_widget();
                self.log(mode.to_action(self.active));
            }
        }

        fn update_widget(self: *Self) void {
            const widget = self.widget orelse return;

            if (self.devices.current) |*device| {
                widget.set_volume(device.get_volume());
                widget.set_muted(self.active);
            }

            widget.set_default_volume(self.get_device_config().volume);

            if (self.devices.get_current_info()) |info| {
                widget.set_device_info(info.get_name_slice(), self.devices.index, self.devices.count);
            } else {
                widget.set_device_info(null, 0, 0);
            }
        }

        fn dispatch_config_reload() void {
            const app = instance.load(.seq_cst) orelse return;
            app.on_config_reload();
        }

        fn dispatch_device_event(event: DeviceEvent) void {
            const app = instance.load(.seq_cst) orelse return;
            app.on_device_event(event);
        }

        fn dispatch_exit() void {
            const app = instance.load(.seq_cst) orelse return;
            app.on_exit();
        }

        fn dispatch_init() void {
            const app = instance.load(.seq_cst) orelse return;
            app.on_init();
        }

        fn dispatch_menu_show() void {
            const app = instance.load(.seq_cst) orelse return;
            app.on_menu_show();
        }

        fn dispatch_open_settings() void {
            const app = instance.load(.seq_cst) orelse return;
            app.on_open_settings();
        }

        fn dispatch_shutdown() void {
            const app = instance.load(.seq_cst) orelse return;
            app.on_shutdown();
        }

        fn dispatch_timer_tick(timer_id: u32) void {
            const app = instance.load(.seq_cst) orelse return;
            app.on_timer_tick(timer_id);
        }

        fn dispatch_toggle_state() void {
            const app = instance.load(.seq_cst) orelse return;
            app.on_toggle_state();
        }

        fn dispatch_tray_click() void {
            const app = instance.load(.seq_cst) orelse return;
            app.on_tray_click();
        }

        fn handle_widget_event(event: WidgetEvent, value: f32, context: ?*anyopaque) void {
            const app: *Self = @ptrCast(@alignCast(context orelse return));

            switch (event) {
                .volume_changed => {
                    if (app.devices.current) |*device| {
                        device.set_volume(value);
                    }
                },
                .device_next => {
                    app.devices.next();
                    app.update_widget();
                },
                .device_prev => {
                    app.devices.previous();
                    app.update_widget();
                },
                .set_default => {
                    if (app.devices.current) |*device| {
                        device.set_as_default() catch {};
                    }
                },
                .reset_default => {
                    app.get_device_config().name_len = 0;
                    app.setup_devices();
                },
                .mute_toggled => {
                    app.toggle();
                },
                .closed => {},
            }
        }

        fn hotkey_callback() void {
            const app = instance.load(.seq_cst) orelse return;
            app.toggle();
        }

        fn on_config_file_changed() void {
            const app = instance.load(.seq_cst) orelse return;
            const hwnd = app.app.get_hwnd() orelse return;

            _ = w32.PostMessageW(hwnd, constant.wm_config_reload, 0, 0);
        }

        fn load_configuration(allocator: std.mem.Allocator, logger: *?Logger) Config {
            return Config.load(allocator, "mute") catch |err| {
                if (logger.*) |*l| {
                    l.log("Could not load config file, using defaults: {}", .{err});
                }

                return Config.init(allocator);
            };
        }
    };
}
