const std = @import("std");

const arc = @import("arc");
const kalymma = @import("kalymma");
const mantra = @import("mantra");
const wisp = @import("wisp");

const constant = @import("constant.zig");
const Config = @import("config.zig").Config;
const DeviceConfig = @import("config.zig").DeviceConfig;
const DeviceEventsType = @import("device/event.zig").DeviceEventsType;
const DeviceManagerType = @import("device/manager.zig").DeviceManagerType;
const EventHandlerType = @import("handler.zig").EventHandlerType;
const IconManagerType = @import("icon.zig").IconManagerType;
const InputThread = @import("hotkey.zig").InputThread;
const MenuManager = @import("menu.zig").MenuManager;
const Mode = @import("mode.zig").Mode;
const SettingsManager = @import("settings.zig").SettingsManager;
const Widget = @import("widget.zig").Widget;
const WidgetEvent = @import("widget.zig").WidgetEvent;

const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const App = wisp.App;
const Logger = arc.Logger;

pub const Error = error{
    AudioInitFailed,
    RunFailed,
    SetupFailed,
};

pub const surface_name = "mute";

pub const directory_name = "mute";

comptime {
    assert(directory_name.len > 0);
    assert(surface_name.len > 0);
}

pub fn ApplicationType(comptime mode: Mode) type {
    return struct {
        active: bool,
        gpa: Allocator,
        app: App,
        configuration: Config,
        devices: DeviceManagerType(mode),
        icon: IconManagerType(mode),
        input: InputThread,
        logger: ?*Logger,
        menu: MenuManager,
        settings: SettingsManager,
        widget: ?*Widget,

        pub fn init(
            self: *@This(),
            gpa: Allocator,
            io: std.Io,
            logger: ?*Logger,
        ) Error!void {
            mantra.runtime.open() catch {
                return Error.AudioInitFailed;
            };

            errdefer mantra.runtime.close();

            self.* = @This(){
                .active = false,
                .gpa = gpa,
                .app = undefined,
                .configuration = load_configuration(gpa, io, logger),
                .devices = DeviceManagerType(mode).init(),
                .icon = undefined,
                .input = InputThread.init(),
                .logger = logger,
                .menu = undefined,
                .settings = undefined,
                .widget = null,
            };

            errdefer self.configuration.deinit();

            self.app.init(.{
                .name = mode.to_title(),
                .tooltip = mode.to_title(),
                .initial_state = "inactive",
            }) catch {
                return Error.SetupFailed;
            };

            errdefer self.app.deinit();

            self.icon = IconManagerType(mode).init(&self.app);
            self.menu = MenuManager.init(&self.app);
            self.settings = SettingsManager.init(&self.configuration, logger);

            self.icon.configure() catch {
                return Error.SetupFailed;
            };

            self.menu.build();
            self.menu.push();

            self.setup_hotkey();
            self.setup_devices();

            _ = self.app.configure();

            assert(!self.app.is_running());

            self.log("Application is ready");
        }

        pub fn deinit(self: *@This()) void {
            self.log("Shutting down");

            if (self.widget) |widget| {
                self.widget = null;

                widget.destroy();
            }

            kalymma.events.unsubscribe();
            kalymma.runtime.close();

            DeviceEventsType(mode).unsubscribe();

            self.input.deinit();
            self.devices.deinit();
            self.settings.deinit();
            self.app.deinit();
            self.configuration.deinit();

            mantra.runtime.close();

            assert(!self.app.is_running());
        }

        pub fn run(self: *@This()) Error!void {
            EventHandlerType(@This()).register(&self.app.bus, self);

            self.app.run() catch |err| {
                self.log_error("Unable to run the application", err);

                return Error.RunFailed;
            };
        }

        pub fn on_custom(self: *@This(), code: u32) void {
            switch (code) {
                constant.Message.config_reload => self.on_config_reload(),
                constant.Message.device_changed => self.on_device_changed(),
                constant.Message.device_default_changed => self.on_device_default_changed(),
                constant.Message.toggle => self.toggle(),
                constant.Message.widget_input => self.on_widget_input(),
                else => {},
            }
        }

        pub fn on_icon_change(self: *@This(), icon_name: []const u8) void {
            assert(icon_name.len > 0);

            const handle = self.app.icon.get(icon_name) orelse return;

            self.app.tray.set_icon(handle) catch {
                self.log("Unable to update the tray icon");

                return;
            };
        }

        pub fn on_init(self: *@This()) void {
            DeviceEventsType(mode).subscribe() catch |err| {
                self.log_error("Could not register device notifications", err);
            };

            self.start_rehook_timer();
            self.start_recovery_timer();

            self.settings.watch(on_config_file_changed, self);

            self.setup_widget();

            self.log("Initialized");
        }

        pub fn on_menu_select(self: *@This(), id: u32) void {
            switch (id) {
                constant.Menu.exit => self.on_exit(),
                else => {},
            }
        }

        pub fn on_menu_show(self: *@This()) void {
            self.menu.build();
            self.menu.push();
        }

        pub fn on_shutdown(self: *@This()) void {
            self.log("Shutdown event received");

            self.input.stop();
        }

        pub fn on_timer_tick(self: *@This(), timer_id: u32) void {
            if (timer_id == constant.Timer.recovery_id) {
                self.recover_devices();

                return;
            }

            if (timer_id != constant.Timer.rehook_id) {
                return;
            }

            self.input.refresh() catch |err| {
                self.log_error("Unable to restart the input hook", err);
            };
        }

        pub fn on_tray_click(self: *@This()) void {
            const widget = self.widget orelse return;

            widget.post_toggle();
        }

        fn activate(self: *@This()) void {
            if (self.devices.current) |*device| {
                device.mute();

                self.active = true;

                self.icon.update(true);
                self.update_widget();
                self.log(mode.to_action(true));
            }
        }

        fn deactivate(self: *@This()) void {
            if (self.devices.current) |*device| {
                device.unmute();

                self.active = false;

                self.icon.update(false);
                self.update_widget();
                self.log(mode.to_action(false));
            }
        }

        fn get_device_config(self: *@This()) *DeviceConfig {
            return switch (mode) {
                .capture => &self.configuration.capture,
                .render => &self.configuration.render,
            };
        }

        fn on_config_reload(self: *@This()) void {
            if (!self.settings.reload()) {
                return;
            }

            self.input.bind(self.get_device_config().get_hotkey()) catch |err| {
                self.log_error("Unable to bind the configured hotkey", err);

                return;
            };

            self.log("Config reloaded");
        }

        fn on_device_changed(self: *@This()) void {
            if (!self.devices.enumerate()) {
                return;
            }

            assert(self.devices.count() <= mantra.devices_max);

            if (self.devices.prune()) {
                self.log("Current device disappeared");
            }

            if (self.devices.current == null) {
                self.devices.current = self.devices.find(self.get_device_config());

                self.devices.update_index();
                self.adopt_device();
                self.update_widget();

                return;
            }

            self.devices.update_index();
            self.update_widget();
        }

        fn on_device_default_changed(self: *@This()) void {
            if (self.get_device_config().get_name() == null) {
                self.follow_default();
                self.update_widget();

                return;
            }

            self.devices.restore_default() catch |err| {
                self.log_error("Unable to restore the default device", err);
            };

            self.update_widget();
        }

        fn follow_default(self: *@This()) void {
            const wanted = self.devices.find(self.get_device_config()) orelse {
                return;
            };

            assert(wanted.id.is_valid());

            if (self.devices.current) |*device| {
                if (device.id.eql(&wanted.id)) {
                    return;
                }
            }

            _ = self.devices.enumerate();

            self.devices.current = wanted;

            self.devices.update_index();
            self.adopt_device();
        }

        fn adopt_device(self: *@This()) void {
            const config = self.get_device_config();
            assert(config.volume >= mantra.volume_min);
            assert(config.volume <= mantra.volume_max);

            if (self.devices.current) |*device| {
                assert(device.id.is_valid());

                device.set_volume(config.volume);

                self.active = device.is_muted();

                self.icon.update(self.active);
                self.log_device_info();
            }
        }

        fn on_exit(self: *@This()) void {
            self.log("Exiting");
            self.app.quit();
        }

        fn setup_devices(self: *@This()) void {
            _ = self.devices.enumerate();

            self.devices.current = self.devices.find(self.get_device_config());

            self.devices.update_index();
            self.adopt_device();

            if (self.devices.current == null) {
                self.log_device_absent();

                return;
            }

            self.devices.restore_default() catch |err| {
                self.log_error("Unable to restore the default device", err);
            };
        }

        fn setup_hotkey(self: *@This()) void {
            self.input.start() catch |err| {
                self.log_error("Unable to start the input hook", err);

                return;
            };

            self.input.bind(self.get_device_config().get_hotkey()) catch |err| {
                self.log_error("Unable to bind the configured hotkey", err);
            };
        }

        fn setup_widget(self: *@This()) void {
            kalymma.runtime.open(.{ .name = surface_name }) catch {
                self.log("No overlay surface available, running tray only");

                return;
            };

            self.widget = Widget.create(self.gpa, mode.to_widget_name()) catch {
                self.log("Could not create the overlay surface");

                kalymma.runtime.close();

                return;
            };

            const widget = self.widget orelse return;

            kalymma.events.subscribe(on_widget_wake, null) catch {
                self.log("Could not subscribe to overlay input");
            };

            widget.set_callback(handle_widget_event, self);
            widget.set_default_volume(self.get_device_config().volume);
            widget.set_title(mode.to_title());

            self.update_widget();
            self.log("Overlay surface ready");
        }

        fn on_widget_input(self: *@This()) void {
            const widget = self.widget orelse return;

            widget.drain();
        }

        fn start_recovery_timer(self: *@This()) void {
            _ = self.app.timer.start(
                constant.Timer.recovery_id,
                constant.Timer.recovery_interval_ms,
            ) catch {
                self.log("Unable to start the recovery timer");

                return;
            };
        }

        fn start_rehook_timer(self: *@This()) void {
            _ = self.app.timer.start(
                constant.Timer.rehook_id,
                constant.Timer.rehook_interval_ms,
            ) catch {
                self.log("Unable to start the rehook timer");

                return;
            };
        }

        fn recover_devices(self: *@This()) void {
            if (DeviceEventsType(mode).is_subscribed()) {
                return;
            }

            DeviceEventsType(mode).unsubscribe();

            assert(!DeviceEventsType(mode).is_subscribed());

            DeviceEventsType(mode).subscribe() catch {
                return;
            };

            self.log("Device notifications restored");

            self.on_device_changed();
        }

        fn toggle(self: *@This()) void {
            if (self.active) {
                self.deactivate();

                return;
            }

            self.activate();
        }

        fn update_widget(self: *@This()) void {
            const widget = self.widget orelse return;

            if (self.devices.current) |*device| {
                widget.set_volume(device.get_volume());
                widget.set_muted(self.active);
            }

            widget.set_default_volume(self.get_device_config().volume);

            if (self.devices.get_current_info()) |info| {
                widget.set_device_info(
                    info.get_name(),
                    self.devices.index,
                    self.devices.count(),
                );

                return;
            }

            widget.set_device_info(null, 0, 0);
        }

        fn log(self: *@This(), message: []const u8) void {
            assert(message.len > 0);

            if (self.logger) |logger| {
                logger.info(message, &.{}, @src());
            }
        }

        fn log_error(self: *@This(), message: []const u8, err: anyerror) void {
            assert(message.len > 0);

            if (self.logger) |logger| {
                logger.@"error"(message, &.{arc.err_from(err)}, @src());
            }
        }

        fn log_device_absent(self: *@This()) void {
            if (self.logger) |logger| {
                logger.info(
                    "No device found",
                    &.{arc.string("kind", mode.to_string())},
                    @src(),
                );
            }
        }

        fn log_device_info(self: *@This()) void {
            const logger = self.logger orelse return;

            if (self.get_device_config().get_name()) |name| {
                logger.info(
                    "Using device",
                    &.{ arc.string("kind", mode.to_string()), arc.string("name", name) },
                    @src(),
                );

                return;
            }

            logger.info(
                "Using default device",
                &.{arc.string("kind", mode.to_string())},
                @src(),
            );
        }

        fn handle_widget_event(event: WidgetEvent, value: f32, context: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(context orelse return));

            switch (event) {
                .volume_changed => {
                    if (self.devices.current) |*device| {
                        device.set_volume(value);
                    }
                },
                .device_next => {
                    self.devices.next();
                    self.update_widget();
                },
                .device_prev => {
                    self.devices.previous();
                    self.update_widget();
                },
                .set_default => {
                    if (self.devices.current) |*device| {
                        device.set_as_default() catch {
                            self.log("Unable to set the current device as the default");
                        };
                    }
                },
                .reset_default => {
                    self.get_device_config().name_len = 0;
                    self.setup_devices();
                },
                .mute_toggled => {
                    self.toggle();
                },
                .closed => {},
            }
        }

        fn on_config_file_changed(context: ?*anyopaque) void {
            _ = context;

            _ = wisp.loop.post(constant.Message.config_reload);
        }

        fn on_widget_wake(context: ?*anyopaque) void {
            _ = context;

            _ = wisp.loop.post(constant.Message.widget_input);
        }

        fn load_configuration(
            gpa: Allocator,
            io: std.Io,
            logger: ?*Logger,
        ) Config {
            return Config.load(gpa, io, directory_name) catch |err| {
                if (logger) |present| {
                    present.@"error"(
                        "Could not load config file, using defaults",
                        &.{arc.err_from(err)},
                        @src(),
                    );
                }

                return Config.init(gpa, io);
            };
        }
    };
}
