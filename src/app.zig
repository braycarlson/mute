const std = @import("std");

const toolkit = @import("toolkit");
const w32 = @import("win32").everything;
const wca = @import("wca");

const constant = @import("constant.zig");

const AudioManager = @import("manager.zig").AudioManager;
const Config = @import("config.zig").Config;
const DeviceConfig = @import("config.zig").DeviceConfig;
const Device = @import("device.zig").Device;
const Logger = @import("logger.zig").Logger;
const MuteError = @import("error.zig").MuteError;

const wm_config_reload: u32 = w32.WM_APP + 2;
const wm_device_event: u32 = w32.WM_APP + 3;

pub const Mode = enum {
    capture,
    render,

    pub fn toDataFlow(self: Mode) wca.EDataFlow {
        return switch (self) {
            .capture => .Capture,
            .render => .Render,
        };
    }

    pub fn toString(self: Mode) []const u8 {
        return switch (self) {
            .capture => "capture",
            .render => "render",
        };
    }

    pub fn toAction(self: Mode, active: bool) []const u8 {
        return switch (self) {
            .capture => if (active) "Muted" else "Unmuted",
            .render => if (active) "Deafened" else "Undeafened",
        };
    }

    pub fn toLabel(self: Mode, active: bool) [:0]const u16 {
        return switch (self) {
            .capture => if (active)
                std.unicode.utf8ToUtf16LeStringLiteral("Unmute")
            else
                std.unicode.utf8ToUtf16LeStringLiteral("Mute"),
            .render => if (active)
                std.unicode.utf8ToUtf16LeStringLiteral("Undeafen")
            else
                std.unicode.utf8ToUtf16LeStringLiteral("Deafen"),
        };
    }

    pub fn toTitle(self: Mode) [:0]const u16 {
        return switch (self) {
            .capture => std.unicode.utf8ToUtf16LeStringLiteral("Mute"),
            .render => std.unicode.utf8ToUtf16LeStringLiteral("Deafen"),
        };
    }

    pub fn toTrayTitle(self: Mode) [:0]const u8 {
        return switch (self) {
            .capture => "Mute",
            .render => "Deafen",
        };
    }
};

pub fn App(comptime mode: Mode) type {
    return struct {
        const Self = @This();
        const queue_capacity: u32 = 16;
        const max_hotkey_len: u32 = 32;

        allocator: std.mem.Allocator,
        active: bool = false,
        cfg: Config,
        context_menu: toolkit.ui.Menu = undefined,
        device: ?Device = null,
        enumerator: ?*wca.IMMDeviceEnumerator = null,
        hotkey: []const u8 = undefined,
        keyboard_hook: toolkit.input.Hook = .{},
        logger: *?Logger,
        manager: AudioManager,
        notification_client: ?*wca.IMMNotificationClient = null,
        rehook_timer: toolkit.os.Timer = undefined,
        sequence: toolkit.input.Sequence(queue_capacity) = .{},
        tray: toolkit.ui.Tray = undefined,
        watcher: toolkit.os.Watcher,
        window: toolkit.os.Window = undefined,

        icon: struct {
            active: toolkit.ui.Icon = .{},
            inactive: toolkit.ui.Icon = .{},
        } = .{},

        var instance: *Self = undefined;

        pub fn init(allocator: std.mem.Allocator, logger: *?Logger) !*Self {
            var self = try allocator.create(Self);
            errdefer allocator.destroy(self);

            wca.com.initialize(wca.com.COINIT_APARTMENTTHREADED) catch {
                return MuteError.ComInitFailed;
            };

            const cfg = loadConfig(allocator, logger);

            self.* = Self{
                .sequence = toolkit.input.Sequence(queue_capacity).init(),
                .manager = AudioManager.init(allocator),
                .cfg = cfg,
                .logger = logger,
                .watcher = toolkit.os.Watcher.init(),
                .allocator = allocator,
            };

            self.hotkey = self.getDeviceConfig().getHotkey();

            std.debug.assert(self.hotkey.len <= max_hotkey_len);

            self.device = self.findDevice();
            self.initializeDevice();
            self.setupIcon();

            try self.setupWindow();
            errdefer self.window.deinit();

            try self.setupTray();
            self.setupContextMenu();
            self.setupTimer();

            instance = self;

            self.setupDeviceNotifications();

            if (self.logger.*) |*l| {
                l.log("{s} is ready", .{@as([]const u8, mode.toTrayTitle())});
            }

            return self;
        }

        fn initializeDevice(self: *Self) void {
            if (self.device) |*device| {
                device.setVolume(self.getDeviceConfig().volume);
                self.active = device.isMuted();

                const is_default = device.isAllDefault() catch false;

                if (!is_default) {
                    device.setAsDefault() catch {};
                }

                if (self.logger.*) |*l| {
                    if (self.getDeviceConfig().getName()) |name| {
                        std.debug.assert(name.len > 0);
                        l.log("Using {s} device: {s}", .{ mode.toString(), name });
                    } else {
                        l.log("Using default {s} device", .{mode.toString()});
                    }
                }
            } else {
                if (self.logger.*) |*l| {
                    l.log("No {s} device found", .{mode.toString()});
                }
            }
        }

        pub fn deinit(self: *Self) void {
            if (self.logger.*) |*l| {
                l.log("Shutting down", .{});
            }

            self.cleanupDeviceNotifications();
            self.watcher.deinit();
            self.rehook_timer.stop();
            self.keyboard_hook.remove();

            if (self.device) |*device| {
                device.deinit();
            }

            self.tray.remove();
            self.context_menu.deinit();
            self.icon.active.deinit();
            self.icon.inactive.deinit();
            self.window.deinit();
            self.cfg.deinit();

            wca.com.uninitialize();

            self.allocator.destroy(self);
        }

        fn cleanupDeviceNotifications(self: *Self) void {
            if (self.enumerator) |enumerator| {
                if (self.notification_client) |client| {
                    enumerator.unregisterEndpointNotificationCallback(@ptrCast(client)) catch {};
                    _ = client.vtable.Release(client);
                }

                _ = enumerator.release();
            }

            self.enumerator = null;
            self.notification_client = null;

            std.debug.assert(self.enumerator == null);
            std.debug.assert(self.notification_client == null);
        }

        fn findDevice(self: *Self) ?Device {
            if (self.getDeviceConfig().getName()) |name| {
                std.debug.assert(name.len > 0);
                return self.manager.find(name, mode.toDataFlow()) catch null;
            }

            return self.manager.getDefault(mode.toDataFlow(), .Console) catch null;
        }

        fn getDeviceConfig(self: *Self) *DeviceConfig {
            return switch (mode) {
                .capture => &self.cfg.capture,
                .render => &self.cfg.render,
            };
        }

        fn handleKeyDown(self: *Self, code: u32) bool {
            std.debug.assert(code <= 0xFF);

            self.sequence.push(@truncate(code));

            const matched = self.sequence.matches(self.hotkey) catch false;

            if (matched) {
                self.toggle();
                return true;
            }

            return false;
        }

        fn handleMenuCommand(self: *Self, command: u32) void {
            if (command == constant.Menu.toggle) {
                self.toggle();
                return;
            }

            if (command == constant.Menu.exit) {
                toolkit.os.quit();
                return;
            }
        }

        fn loadConfig(allocator: std.mem.Allocator, logger: *?Logger) Config {
            return Config.load(allocator, "mute") catch |err| {
                if (logger.*) |*l| {
                    l.log("Could not load config file, using defaults: {}", .{err});
                }

                return Config.init(allocator);
            };
        }

        fn onDefaultDeviceChanged(flow: wca.EDataFlow, role: wca.ERole, device_id: []const u8) anyerror!void {
            _ = role;
            _ = device_id;

            if (flow != mode.toDataFlow()) {
                return;
            }

            _ = w32.PostMessageW(instance.window.handle, wm_device_event, 0, 0);
        }

        fn onDeviceAdded(device_id: []const u8) anyerror!void {
            _ = device_id;
            _ = w32.PostMessageW(instance.window.handle, wm_device_event, 1, 0);
        }

        fn onDeviceRemoved(device_id: []const u8) anyerror!void {
            _ = device_id;
            _ = w32.PostMessageW(instance.window.handle, wm_device_event, 2, 0);
        }

        fn onDeviceStateChanged(device_id: []const u8, new_state: u32) anyerror!void {
            _ = device_id;
            _ = new_state;
            _ = w32.PostMessageW(instance.window.handle, wm_device_event, 3, 0);
        }

        fn refreshHook(self: *Self) void {
            self.keyboard_hook.remove();
            self.keyboard_hook = toolkit.input.Hook.install(.keyboard, keyboardProc);
        }

        fn setupContextMenu(self: *Self) void {
            self.context_menu = toolkit.ui.Menu.init() orelse return;
        }

        fn setupDeviceNotifications(self: *Self) void {
            self.enumerator = wca.IMMDeviceEnumerator.create() catch {
                if (self.logger.*) |*l| {
                    l.log("Could not create device enumerator", .{});
                }

                return;
            };

            self.notification_client = wca.IMMNotificationClient.create(self.allocator, .{
                .onDefaultDeviceChanged = &onDefaultDeviceChanged,
                .onDeviceAdded = &onDeviceAdded,
                .onDeviceRemoved = &onDeviceRemoved,
                .onDeviceStateChanged = &onDeviceStateChanged,
            }) catch {
                if (self.logger.*) |*l| {
                    l.log("Could not create notification client", .{});
                }

                return;
            };

            if (self.enumerator) |enumerator| {
                enumerator.registerEndpointNotificationCallback(@ptrCast(self.notification_client)) catch {
                    if (self.logger.*) |*l| {
                        l.log("Could not register notification callback", .{});
                    }
                };
            }

            if (self.logger.*) |*l| {
                l.log("Device notifications registered", .{});
            }
        }

        fn setupIcon(self: *Self) void {
            self.icon.active = toolkit.ui.Icon.fromResource(constant.Resource.mute_icon);
            self.icon.inactive = toolkit.ui.Icon.fromResource(constant.Resource.unmute_icon);

            if (!self.icon.active.isValid()) {
                self.icon.active = toolkit.ui.Icon.fromSystem(.shield);
            }

            if (!self.icon.inactive.isValid()) {
                self.icon.inactive = toolkit.ui.Icon.fromSystem(.application);
            }

            std.debug.assert(self.icon.active.isValid());
            std.debug.assert(self.icon.inactive.isValid());
        }

        fn setupTimer(self: *Self) void {
            self.rehook_timer = toolkit.os.Timer.init(self.window.handle, constant.Timer.rehook_id);
            _ = self.rehook_timer.start(constant.Timer.rehook_interval_ms);
        }

        fn setupTray(self: *Self) !void {
            self.tray = .{ .hwnd = self.window.handle };

            const icon = if (self.active) self.icon.active else self.icon.inactive;

            std.debug.assert(icon.isValid());

            try self.tray.add(icon, mode.toTrayTitle());
        }

        fn setupWindow(self: *Self) !void {
            self.window = try toolkit.os.Window.init(
                mode.toTitle(),
                windowProc,
                self,
            );
        }

        fn updateTrayIcon(self: *Self) void {
            const icon = if (self.active) self.icon.active else self.icon.inactive;

            std.debug.assert(icon.isValid());

            self.tray.setIcon(icon);
        }

        pub fn activate(self: *Self) void {
            if (self.device) |*device| {
                device.mute();
                self.active = true;
                self.updateTrayIcon();

                if (self.logger.*) |*l| {
                    l.log("{s}", .{mode.toAction(true)});
                }

                std.debug.assert(self.active == true);
            }
        }

        pub fn deactivate(self: *Self) void {
            if (self.device) |*device| {
                device.unmute();
                self.active = false;
                self.updateTrayIcon();

                if (self.logger.*) |*l| {
                    l.log("{s}", .{mode.toAction(false)});
                }

                std.debug.assert(self.active == false);
            }
        }

        pub fn handleDeviceEvent(self: *Self, event_type: usize) void {
            std.debug.assert(event_type <= 3);

            switch (event_type) {
                0 => self.restoreDefaultDevice(),
                1 => self.handleDeviceAdded(),
                2 => self.handleDeviceRemoved(),
                3 => self.handleDeviceStateChanged(),
                else => {},
            }
        }

        fn handleDeviceAdded(self: *Self) void {
            if (self.device != null) {
                return;
            }

            self.device = self.findDevice();

            if (self.device) |*device| {
                device.setVolume(self.getDeviceConfig().volume);
                self.restoreDefaultDevice();

                if (self.logger.*) |*l| {
                    l.log("Device reconnected", .{});
                }
            }
        }

        fn handleDeviceRemoved(self: *Self) void {
            if (self.device) |*device| {
                const id = device.getId() catch return;
                defer self.allocator.free(id);

                std.debug.assert(id.len > 0);

                var current = self.findDevice() orelse {
                    device.deinit();
                    self.device = null;

                    if (self.logger.*) |*l| {
                        l.log("Device disconnected", .{});
                    }

                    return;
                };

                const current_id = current.getId() catch {
                    current.deinit();
                    return;
                };

                defer self.allocator.free(current_id);

                std.debug.assert(current_id.len > 0);

                if (!std.mem.eql(u8, id, current_id)) {
                    device.deinit();
                    self.device = null;

                    if (self.logger.*) |*l| {
                        l.log("Device disconnected", .{});
                    }
                }

                current.deinit();
            }
        }

        fn handleDeviceStateChanged(self: *Self) void {
            if (self.device) |*device| {
                const enabled = device.isEnabled();

                if (enabled) {
                    self.restoreDefaultDevice();
                }
            }
        }

        pub fn isHotkeyKey(self: *Self, code: u32) bool {
            std.debug.assert(code <= 0xFF);

            const key: u8 = @truncate(code);

            var i: u32 = 0;
            const len: u32 = @intCast(self.hotkey.len);

            while (i < len) : (i += 1) {
                std.debug.assert(i < max_hotkey_len);

                if (self.hotkey[i] == key) {
                    return true;
                }
            }

            return false;
        }

        pub fn reloadConfig(self: *Self) void {
            const path = self.cfg.config_path[0..self.cfg.config_path_len];

            std.debug.assert(path.len > 0);
            std.debug.assert(path.len <= Config.path_max);

            const file = std.fs.openFileAbsolute(path, .{}) catch |err| {
                if (self.logger.*) |*l| {
                    l.log("Could not open config file: {}", .{err});
                }

                return;
            };

            defer file.close();

            var buffer: [Config.content_max]u8 = undefined;

            const count = file.readAll(&buffer) catch |err| {
                if (self.logger.*) |*l| {
                    l.log("Could not read config file: {}", .{err});
                }

                return;
            };

            if (count == 0) {
                return;
            }

            std.debug.assert(count <= Config.content_max);

            const slice: [:0]const u8 = buffer[0..count :0];

            self.cfg.parse(slice) catch |err| {
                if (self.logger.*) |*l| {
                    l.log("Could not parse config file: {}", .{err});
                }

                return;
            };

            self.hotkey = self.getDeviceConfig().getHotkey();

            std.debug.assert(self.hotkey.len <= max_hotkey_len);

            if (self.device) |*device| {
                device.deinit();
            }

            self.device = self.findDevice();

            if (self.device) |*device| {
                device.setVolume(self.getDeviceConfig().volume);
            }

            if (self.logger.*) |*l| {
                l.log("Config reloaded", .{});
            }
        }

        pub fn restoreDefaultDevice(self: *Self) void {
            if (self.device) |*device| {
                const is_default = device.isAllDefault() catch false;

                if (!is_default) {
                    device.setAsDefault() catch |err| {
                        if (self.logger.*) |*l| {
                            l.log("Could not set device as default: {}", .{err});
                        }

                        return;
                    };

                    if (self.logger.*) |*l| {
                        l.log("Restored default device", .{});
                    }
                }
            }
        }

        pub fn run(self: *Self) void {
            self.keyboard_hook = toolkit.input.Hook.install(.keyboard, keyboardProc);

            if (self.cfg.getConfigPath()) |path| {
                std.debug.assert(path.len > 0);

                self.watcher.watch(path, onConfigChanged) catch |err| {
                    if (self.logger.*) |*l| {
                        l.log("Could not watch config file: {}", .{err});
                    }
                };
            }

            toolkit.os.runMessageLoop();
        }

        pub fn showContextMenu(self: *Self) void {
            self.context_menu.clear();

            const label = mode.toLabel(self.active);

            self.context_menu.add(0, constant.Menu.toggle, label);
            self.context_menu.addSeparator(1);
            self.context_menu.add(2, constant.Menu.exit, std.unicode.utf8ToUtf16LeStringLiteral("Exit"));

            const command = self.context_menu.show(self.window.handle);

            self.handleMenuCommand(command);
        }

        pub fn toggle(self: *Self) void {
            if (self.device) |*device| {
                self.active = device.toggleMute();
                self.updateTrayIcon();

                if (self.logger.*) |*l| {
                    l.log("{s}", .{mode.toAction(self.active)});
                }
            }
        }

        fn keyboardProc(code: c_int, wparam: usize, lparam: isize) callconv(.c) isize {
            if (code < 0) {
                return toolkit.input.Hook.callNext(code, wparam, lparam);
            }

            const event = toolkit.input.KeyEvent.fromHook(wparam, lparam);

            std.debug.assert(event.vk <= 0xFF);

            if (instance.isHotkeyKey(event.vk)) {
                if (event.is_down) {
                    _ = instance.handleKeyDown(event.vk);
                }

                return 1;
            }

            return toolkit.input.Hook.callNext(code, wparam, lparam);
        }

        fn onConfigChanged() void {
            _ = w32.PostMessageW(instance.window.handle, wm_config_reload, 0, 0);
        }

        fn windowProc(hwnd: w32.HWND, msg: u32, wparam: usize, lparam: isize) callconv(.c) isize {
            const self = toolkit.os.Window.getContext(Self, hwnd) orelse {
                return w32.DefWindowProcW(hwnd, msg, wparam, lparam);
            };

            if (msg == self.window.taskbar_restart_msg) {
                const icon = if (self.active) self.icon.active else self.icon.inactive;
                self.tray.add(icon, mode.toTrayTitle()) catch {};
                return 0;
            }

            if (msg == toolkit.ui.wm_trayicon) {
                if (toolkit.ui.parseTrayEvent(lparam)) |event| {
                    switch (event) {
                        .left_click => self.toggle(),
                        .right_click => self.showContextMenu(),
                        .left_double_click => {},
                    }
                }

                return 0;
            }

            if (msg == wm_config_reload) {
                self.reloadConfig();
                return 0;
            }

            if (msg == wm_device_event) {
                self.handleDeviceEvent(wparam);
                return 0;
            }

            if (msg == w32.WM_TIMER) {
                if (wparam == constant.Timer.rehook_id) {
                    self.refreshHook();
                }

                return 0;
            }

            if (msg == w32.WM_DESTROY) {
                toolkit.os.quit();
                return 0;
            }

            return w32.DefWindowProcW(hwnd, msg, wparam, lparam);
        }
    };
}

pub fn getLogPath(allocator: std.mem.Allocator, comptime mode: Mode) ![]u8 {
    const directory = try std.fs.getAppDataDir(allocator, "mute");
    defer allocator.free(directory);

    std.debug.assert(directory.len > 0);

    const filename = switch (mode) {
        .capture => "mute.log",
        .render => "deafen.log",
    };

    const result = try std.fs.path.join(allocator, &[_][]const u8{ directory, filename });

    std.debug.assert(result.len > 0);

    return result;
}

pub fn initLogger(allocator: std.mem.Allocator, comptime mode: Mode) ?Logger {
    const path = getLogPath(allocator, mode) catch return null;
    defer allocator.free(path);

    return Logger.init(path, .{ .both = 1024 * 1024 }) catch return null;
}
