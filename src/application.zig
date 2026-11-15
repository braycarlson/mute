const std = @import("std");

const arc = @import("arc");
const mantra = @import("mantra");
const umbra = @import("umbra");

const Config = @import("config.zig").Config;
const DeviceEventsType = @import("device.zig").event.DeviceEventsType;
const DevicesType = @import("device.zig").devices.DevicesType;
const HotkeyType = @import("hotkey.zig").HotkeyType;
const icon = @import("icon.zig");
const menu = @import("menu.zig");
const Message = @import("message.zig").Message;
const Mode = @import("mode.zig").Mode;
const State = @import("state.zig").State;
const WidgetType = @import("widget.zig").WidgetType;

const assert = std.debug.assert;

const Command = menu.Command;
const Custom = umbra.Event.Custom;
const Logger = arc.Logger;
const Selection = umbra.Event.Selection;
const Tick = umbra.Event.Tick;

const InitError = mantra.PlatformError || umbra.Error;

pub const TimerID = enum(u32) {
    recovery = 2,
    rehook = 1,
    _,
};

const recovery_interval_ms: u32 = 5 * 1000;
const rehook_interval_ms: u32 = 10 * 60 * 1000;

comptime {
    assert(recovery_interval_ms > 0);
    assert(rehook_interval_ms > 0);
}

pub fn ApplicationType(comptime Libraries: type, comptime mode: Mode) type {
    return struct {
        configuration: Config,
        devices: Devices,
        hotkey: Hotkey,
        logger: ?*const Logger,
        mixer: Mixer,
        overlay: Runtime,
        runtime: App,
        state: State,
        watch: ?umbra.Watch,
        widget: ?Widget,

        const Application = @This();
        const App = Libraries.App;
        const DeviceEvents = DeviceEventsType(App, mode);
        const Devices = DevicesType(Mixer, mode);
        const Hotkey = HotkeyType(Libraries.Client, App);
        const Mixer = Libraries.Mixer;
        const Runtime = Libraries.Runtime;
        const Widget = WidgetType(Runtime);

        pub fn init(application: *Application, io: std.Io, logger: ?*const Logger) InitError!void {
            if (logger) |held| assert(held.enabled(.information));

            application.logger = logger;
            application.state = .inactive;
            application.watch = null;
            application.widget = null;

            try application.runtime.init(.{ .name = mode.to_title(), .tooltip = mode.to_title() });
            errdefer application.runtime.deinit();

            try application.mixer.init(.{});
            errdefer application.mixer.deinit();

            application.configuration.init(io);
            application.devices = Devices.init(&application.mixer);
            application.hotkey = Hotkey.init(&application.runtime);

            application.configuration.load(App) catch |err| {
                application.log_configuration_error(
                    "Could not load config file, using defaults",
                    err,
                );
            };

            try icon.register(App, &application.runtime.icons, mode);
            try icon.show(App, &application.runtime.icons, application.state);

            application.refresh_menu();
            application.setup_hotkey();
            application.setup_devices();

            assert(!application.runtime.is_running());

            application.log("Application is ready");
        }

        pub fn deinit(application: *Application) void {
            application.log("Shutting down");

            if (application.widget) |*widget| {
                widget.deinit();

                application.overlay.events_unsubscribe();
                application.overlay.deinit();

                application.widget = null;
            }

            application.mixer.unsubscribe();

            application.hotkey.deinit();
            application.devices.deinit();

            if (application.watch) |handle| {
                application.runtime.unwatch(handle);

                application.watch = null;
            }

            application.runtime.deinit();
            application.mixer.deinit();

            assert(!application.runtime.is_running());
            assert(application.widget == null);
        }

        pub fn run(application: *Application) umbra.Error!void {
            try application.runtime.bus.attach(Application, application);
            try application.runtime.run();
        }

        pub fn on_app_init(application: *Application) void {
            application.subscribe_devices() catch |err| {
                application.log_error("Could not register device notifications", err);
            };

            application.start_rehook_timer();
            application.start_recovery_timer();

            application.watch_configuration();
            application.setup_widget();

            application.log("Initialized");
        }

        pub fn on_app_shutdown(application: *Application) void {
            application.log("Shutdown event received");

            application.hotkey.stop();
        }

        pub fn on_custom(application: *Application, custom: Custom) void {
            assert(@backingInt(custom.code) > 0);

            switch (@as(Message, @fromBackingInt(@backingInt(custom.code)))) {
                .config_reload => application.on_config_reload(),
                .device_changed => application.on_device_changed(),
                .device_default_changed => application.on_default_changed(),
                .toggle => application.toggle(),
                .widget_input => application.on_widget_input(),
                _ => {},
            }
        }

        pub fn on_menu_select(application: *Application, selection: Selection) void {
            assert(selection.id <= umbra.limits.menu_item_id_max);

            switch (@as(Command, @fromBackingInt(selection.id))) {
                .exit => application.on_exit(),
                .volume => application.show_widget(),
                _ => {},
            }
        }

        pub fn on_menu_show(application: *Application) void {
            application.refresh_menu();
        }

        pub fn on_timer_tick(application: *Application, tick: Tick) void {
            assert(tick.id <= umbra.limits.timer_id_max);

            switch (@as(TimerID, @fromBackingInt(tick.id))) {
                .recovery => application.recover_devices(),
                .rehook => application.hotkey.refresh() catch |err| {
                    application.log_error("Unable to restart the input hook", err);
                },
                _ => {},
            }
        }

        pub fn on_tray_left_click(application: *Application) void {
            const widget = if (application.widget) |*live| live else return;

            widget.post_toggle(application.runtime.now_ms());
        }

        fn activate(application: *Application) void {
            if (application.devices.current) |*device| {
                device.mute();

                application.set_state(.active);
            }
        }

        fn adopt_device(application: *Application) void {
            const side = application.get_side();

            assert(side.volume >= mantra.limits.volume_fraction_min);
            assert(side.volume <= mantra.limits.volume_fraction_max);

            if (application.devices.current) |*device| {
                assert(device.id.is_valid());

                device.set_volume(side.volume);

                application.state = if (device.is_muted()) .active else .inactive;

                icon.show(App, &application.runtime.icons, application.state) catch {
                    application.log("Unable to show the tray icon");
                };

                application.log_device();
            }
        }

        fn deactivate(application: *Application) void {
            if (application.devices.current) |*device| {
                device.unmute();

                application.set_state(.inactive);
            }
        }

        fn follow_default(application: *Application) void {
            const wanted = application.devices.find(application.get_side()) orelse {
                return;
            };

            assert(wanted.id.is_valid());

            if (application.devices.current) |*device| {
                if (device.id.eql(&wanted.id)) {
                    return;
                }
            }

            _ = application.devices.enumerate();

            application.devices.current = wanted;

            application.devices.update_index();
            application.adopt_device();
        }

        fn get_side(application: *Application) *Config.Side {
            return switch (mode) {
                .capture => &application.configuration.capture,
                .render => &application.configuration.render,
            };
        }

        fn handle_action(application: *Application, action: Widget.Action) void {
            if (action == .volume_changed) assert(action.volume_changed >= 0.0);
            if (action == .volume_changed) assert(action.volume_changed <= 1.0);

            switch (action) {
                .volume_changed => |level| {
                    if (application.devices.current) |*device| {
                        device.set_volume(level);
                    }
                },
                .device_next => {
                    application.devices.next();
                    application.update_widget();
                },
                .device_previous => {
                    application.devices.previous();
                    application.update_widget();
                },
                .set_default => {
                    if (application.devices.current) |*device| {
                        device.set_as_default() catch {
                            application.log("Unable to set the current device as the default");
                        };
                    }
                },
                .reset_default => {
                    application.get_side().clear_name();
                    application.setup_devices();
                },
                .mute_toggled => application.toggle(),
                .closed => {},
            }
        }

        fn on_config_file_changed(app: *App) void {
            _ = app.post(@fromBackingInt(@backingInt(Message.config_reload)));
        }

        fn on_config_reload(application: *Application) void {
            application.configuration.reload() catch |err| {
                application.log_configuration_error("Unable to reload the settings file", err);

                return;
            };

            application.hotkey.bind(application.get_side().get_hotkey()) catch |err| {
                application.log_error("Unable to bind the configured hotkey", err);

                return;
            };

            application.log("Config reloaded");
        }

        fn on_default_changed(application: *Application) void {
            if (application.get_side().get_name() == null) {
                application.follow_default();
                application.update_widget();

                return;
            }

            application.devices.restore_default() catch |err| {
                application.log_error("Unable to restore the default device", err);
            };

            application.update_widget();
        }

        fn on_device_changed(application: *Application) void {
            if (!application.devices.enumerate()) {
                return;
            }

            assert(application.devices.count() <= mantra.limits.device_count_max);

            if (application.devices.prune()) {
                application.log("Current device disappeared");
            }

            if (application.devices.current == null) {
                application.devices.current = application.devices.find(application.get_side());

                application.devices.update_index();
                application.adopt_device();
                application.update_widget();

                return;
            }

            application.devices.update_index();
            application.update_widget();
        }

        fn on_exit(application: *Application) void {
            application.log("Exiting");
            application.runtime.quit();
        }

        fn on_widget_input(application: *Application) void {
            const widget = if (application.widget) |*live| live else return;

            var actions = Widget.ActionList.init();

            widget.drain(&actions, application.runtime.now_ms());

            for (actions.slice()) |action| {
                application.handle_action(action);
            }
        }

        fn on_widget_wake(app: *App) void {
            _ = app.post(@fromBackingInt(@backingInt(Message.widget_input)));
        }

        fn recover_devices(application: *Application) void {
            if (application.mixer.is_subscribed()) {
                return;
            }

            application.mixer.unsubscribe();

            assert(!application.mixer.is_subscribed());

            application.subscribe_devices() catch {
                return;
            };

            application.log("Device notifications restored");

            application.on_device_changed();
        }

        fn refresh_menu(application: *Application) void {
            menu.fill(App, &application.runtime.menu) catch {
                application.log("Unable to fill the menu");
            };

            application.runtime.menu.build() catch {
                return;
            };
        }

        fn set_state(application: *Application, value: State) void {
            application.state = value;

            icon.show(App, &application.runtime.icons, value) catch {
                application.log("Unable to show the tray icon");
            };

            application.update_widget();
            application.log(mode.to_action(value));

            assert(application.state == value);
        }

        fn setup_devices(application: *Application) void {
            _ = application.devices.enumerate();

            application.devices.current = application.devices.find(application.get_side());

            application.devices.update_index();
            application.adopt_device();

            if (application.devices.current == null) {
                application.log_device_absent();

                return;
            }

            application.devices.restore_default() catch |err| {
                application.log_error("Unable to restore the default device", err);
            };
        }

        fn setup_hotkey(application: *Application) void {
            application.hotkey.start() catch |err| {
                application.log_error("Unable to start the input hook", err);

                return;
            };

            application.hotkey.bind(application.get_side().get_hotkey()) catch |err| {
                application.log_error("Unable to bind the configured hotkey", err);
            };
        }

        fn setup_widget(application: *Application) void {
            assert(application.widget == null);

            application.overlay.init(.{}) catch {
                application.log("No overlay surface available, running tray only");

                return;
            };

            var widget = Widget.init(&application.overlay, mode.to_widget_name()) catch {
                application.log("Could not create the overlay surface");

                application.overlay.deinit();

                return;
            };

            application.overlay.events_subscribe(App, &application.runtime, on_widget_wake);

            widget.set_default_volume(application.get_side().volume);
            widget.set_title(mode.to_title());

            application.widget = widget;

            application.update_widget();
            application.log("Overlay surface ready");
        }

        fn show_widget(application: *Application) void {
            const widget = if (application.widget) |*live| live else return;

            widget.show();
        }

        fn start_recovery_timer(application: *Application) void {
            const recovery = App.TimerSet.Timer{
                .id = @backingInt(TimerID.recovery),
                .interval_ms = recovery_interval_ms,
            };

            application.runtime.timers.start(recovery) catch {
                application.log("Unable to start the recovery timer");

                return;
            };
        }

        fn start_rehook_timer(application: *Application) void {
            const rehook = App.TimerSet.Timer{
                .id = @backingInt(TimerID.rehook),
                .interval_ms = rehook_interval_ms,
            };

            application.runtime.timers.start(rehook) catch {
                application.log("Unable to start the rehook timer");

                return;
            };
        }

        fn subscribe_devices(application: *Application) mantra.PlatformError!void {
            assert(!application.mixer.is_subscribed());

            try application.mixer.subscribe(App, &application.runtime, DeviceEvents.on_change);

            assert(application.mixer.is_subscribed());
        }

        fn toggle(application: *Application) void {
            if (application.state.is_active()) {
                application.deactivate();

                return;
            }

            application.activate();
        }

        fn update_widget(application: *Application) void {
            const widget = if (application.widget) |*live| live else return;

            if (application.devices.current) |*device| {
                widget.set_volume(device.get_volume());
                widget.set_state(application.state);
            }

            widget.set_default_volume(application.get_side().volume);

            const name = if (application.devices.entry()) |entry| entry.get_name() else null;

            widget.set_device_name(name);
        }

        fn watch_configuration(application: *Application) void {
            assert(application.watch == null);

            const path = application.configuration.get_path() orelse return;

            assert(path.len > 0);

            application.watch = application.runtime.watch(
                path,
                App,
                &application.runtime,
                on_config_file_changed,
            ) catch {
                application.log("Unable to watch the settings file");

                return;
            };

            assert(application.watch != null);
        }

        fn log(application: *Application, message: []const u8) void {
            assert(message.len > 0);

            if (application.logger) |logger| {
                logger.information(message, &.{}, &@src());
            }
        }

        fn log_configuration_error(
            application: *Application,
            message: []const u8,
            err: anyerror,
        ) void {
            assert(message.len > 0);

            const diagnostic = application.configuration.diagnostic orelse {
                application.log_error(message, err);

                return;
            };

            if (application.logger) |logger| {
                logger.err(
                    message,
                    &.{
                        .{ .key = "error", .value = .{ .string = @errorName(err) } },
                        .{ .key = "line", .value = .{ .unsigned = diagnostic.position.line } },
                        .{ .key = "column", .value = .{ .unsigned = diagnostic.position.column } },
                        .{ .key = "reason", .value = .{ .string = diagnostic.reason } },
                    },
                    &@src(),
                );
            }
        }

        fn log_device(application: *Application) void {
            const logger = application.logger orelse return;

            if (application.get_side().get_name()) |name| {
                logger.information(
                    "Using device",
                    &.{
                        .{ .key = "kind", .value = .{ .string = mode.to_string() } },
                        .{ .key = "name", .value = .{ .string = name } },
                    },
                    &@src(),
                );

                return;
            }

            logger.information(
                "Using default device",
                &.{.{ .key = "kind", .value = .{ .string = mode.to_string() } }},
                &@src(),
            );
        }

        fn log_device_absent(application: *Application) void {
            if (application.logger) |logger| {
                logger.information(
                    "No device found",
                    &.{.{ .key = "kind", .value = .{ .string = mode.to_string() } }},
                    &@src(),
                );
            }
        }

        fn log_error(application: *Application, message: []const u8, err: anyerror) void {
            assert(message.len > 0);

            if (application.logger) |logger| {
                logger.err(
                    message,
                    &.{.{ .key = "error", .value = .{ .string = @errorName(err) } }},
                    &@src(),
                );
            }
        }
    };
}

const testing = std.testing;

const Fakes = @import("fakes.zig");

test ApplicationType {
    const application = try testing.allocator.create(ApplicationType(Fakes, .capture));
    defer testing.allocator.destroy(application);

    try application.init(testing.io, null);
    defer application.deinit();

    application.on_app_init();

    const device = application.devices.current orelse return error.MissingDevice;

    try testing.expectEqual(State.inactive, application.state);
    try testing.expect(application.widget != null);

    application.on_custom(.{ .code = @fromBackingInt(@backingInt(Message.toggle)) });

    try testing.expectEqual(State.active, application.state);
    try testing.expect(try application.mixer.is_muted(&device.id));
    try testing.expectEqualStrings("active", application.runtime.icons.get_current_name().?);
}
