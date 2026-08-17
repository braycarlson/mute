const std = @import("std");

const umbra = @import("umbra");

const assert = std.debug.assert;

const Bus = umbra.Bus;
const Event = umbra.Event;
const Response = umbra.Response;

pub fn EventHandlerType(comptime Owner: type) type {
    return struct {
        pub fn register(bus: *Bus, owner: *Owner) void {
            _ = bus.on(.app_init, on_app_init, owner);
            _ = bus.on(.app_shutdown, on_app_shutdown, owner);
            _ = bus.on(.custom, on_custom, owner);
            _ = bus.on(.icon_change, on_icon_change, owner);
            _ = bus.on(.menu_select, on_menu_select, owner);
            _ = bus.on(.menu_show, on_menu_show, owner);
            _ = bus.on(.timer_tick, on_timer_tick, owner);
            _ = bus.on(.tray_left_click, on_tray_click, owner);

            assert(bus.handler_count() > 0);
        }

        fn on_app_init(_: *const Event, context: ?*anyopaque) Response {
            owner_of(context).on_init();

            return .pass;
        }

        fn on_app_shutdown(_: *const Event, context: ?*anyopaque) Response {
            owner_of(context).on_shutdown();

            return .pass;
        }

        fn on_custom(event: *const Event, context: ?*anyopaque) Response {
            const payload = event.payload.custom;

            owner_of(context).on_custom(payload.code);

            return .pass;
        }

        fn on_icon_change(event: *const Event, context: ?*anyopaque) Response {
            const payload = event.payload.icon_change;

            owner_of(context).on_icon_change(payload.name);

            return .pass;
        }

        fn on_menu_select(event: *const Event, context: ?*anyopaque) Response {
            const payload = event.payload.menu_select;

            owner_of(context).on_menu_select(payload.id);

            return .pass;
        }

        fn on_menu_show(_: *const Event, context: ?*anyopaque) Response {
            owner_of(context).on_menu_show();

            return .pass;
        }

        fn on_timer_tick(event: *const Event, context: ?*anyopaque) Response {
            const payload = event.payload.timer_tick;

            owner_of(context).on_timer_tick(payload.id);

            return .pass;
        }

        fn on_tray_click(_: *const Event, context: ?*anyopaque) Response {
            owner_of(context).on_tray_click();

            return .pass;
        }

        fn owner_of(context: ?*anyopaque) *Owner {
            assert(context != null);

            const result: *Owner = @ptrCast(@alignCast(context.?));

            return result;
        }
    };
}

const testing = std.testing;

const Recorder = struct {
    clicks: u32 = 0,
    codes: u32 = 0,
    icons: u32 = 0,
    inits: u32 = 0,
    selections: u32 = 0,
    shows: u32 = 0,
    shutdowns: u32 = 0,
    ticks: u32 = 0,
    last_code: u32 = 0,
    last_id: u32 = 0,

    pub fn on_custom(recorder: *Recorder, code: u32) void {
        recorder.codes += 1;
        recorder.last_code = code;
    }

    pub fn on_icon_change(recorder: *Recorder, name: []const u8) void {
        assert(name.len > 0);

        recorder.icons += 1;
    }

    pub fn on_init(recorder: *Recorder) void {
        recorder.inits += 1;
    }

    pub fn on_menu_select(recorder: *Recorder, id: u32) void {
        recorder.selections += 1;
        recorder.last_id = id;
    }

    pub fn on_menu_show(recorder: *Recorder) void {
        recorder.shows += 1;
    }

    pub fn on_shutdown(recorder: *Recorder) void {
        recorder.shutdowns += 1;
    }

    pub fn on_timer_tick(recorder: *Recorder, id: u32) void {
        recorder.ticks += 1;
        recorder.last_id = id;
    }

    pub fn on_tray_click(recorder: *Recorder) void {
        recorder.clicks += 1;
    }
};

test "every registered event reaches its owner method" {
    var bus = Bus.init();
    defer bus.deinit();

    var recorder = Recorder{};

    EventHandlerType(Recorder).register(&bus, &recorder);

    const started = Event.app_init();
    const posted = Event.custom(7, null);
    const changed = Event.icon_change("active");
    const selected = Event.menu_select(2, false);
    const shown = Event.menu_show();
    const ticked = Event.timer_tick(1, 0);
    const clicked = Event.tray_left_click();
    const stopped = Event.app_shutdown();

    _ = bus.emit(&started);
    _ = bus.emit(&posted);
    _ = bus.emit(&changed);
    _ = bus.emit(&selected);
    _ = bus.emit(&shown);
    _ = bus.emit(&ticked);
    _ = bus.emit(&clicked);
    _ = bus.emit(&stopped);

    try testing.expectEqual(@as(u32, 1), recorder.inits);
    try testing.expectEqual(@as(u32, 1), recorder.codes);
    try testing.expectEqual(@as(u32, 7), recorder.last_code);
    try testing.expectEqual(@as(u32, 1), recorder.icons);
    try testing.expectEqual(@as(u32, 1), recorder.selections);
    try testing.expectEqual(@as(u32, 1), recorder.shows);
    try testing.expectEqual(@as(u32, 1), recorder.ticks);
    try testing.expectEqual(@as(u32, 1), recorder.clicks);
    try testing.expectEqual(@as(u32, 1), recorder.shutdowns);
}

test "an unregistered event leaves the owner untouched" {
    var bus = Bus.init();
    defer bus.deinit();

    var recorder = Recorder{};

    EventHandlerType(Recorder).register(&bus, &recorder);

    const clicked = Event.tray_right_click();

    _ = bus.emit(&clicked);

    try testing.expectEqual(@as(u32, 0), recorder.codes);
    try testing.expectEqual(@as(u32, 0), recorder.clicks);
}
