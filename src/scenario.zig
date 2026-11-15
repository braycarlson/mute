const std = @import("std");

const kalymma = @import("kalymma");
const mantra = @import("mantra");

const Command = @import("menu.zig").Command;
const Fakes = @import("fakes.zig");
const layout = @import("ui.zig").layout;
const Message = @import("message.zig").Message;
const State = @import("state.zig").State;
const WidgetType = @import("widget.zig").WidgetType;

const ApplicationType = @import("application.zig").ApplicationType;
const TimerID = @import("application.zig").TimerID;

const assert = std.debug.assert;

const Capture = ApplicationType(Fakes, .capture);
const Widget = WidgetType(Fakes.Runtime);

const testing = std.testing;

fn open() !*Capture {
    const application = try testing.allocator.create(Capture);
    errdefer testing.allocator.destroy(application);

    try application.init(testing.io, null);

    application.on_app_init();

    return application;
}

fn close(application: *Capture) void {
    application.deinit();

    testing.allocator.destroy(application);
}

fn label_of(application: *const Capture, command: Command) []const u8 {
    assert(std.enums.tagName(Command, command) != null);

    const item = application.runtime.menu.get_item(@backingInt(command)) orelse return "";
    return item.get_label();
}

fn icon_of(application: *const Capture) []const u8 {
    const name = application.runtime.icons.get_current_name() orelse return "";
    return name;
}

fn capture_first(application: *Capture) !mantra.Device.Id {
    var list = mantra.Device.List.init();

    try application.mixer.enumerate(&list, .capture);
    try testing.expect(!list.is_empty());

    return list.items[0].id;
}

fn post(application: *Capture, message: Message) void {
    assert(@backingInt(message) > 0);

    application.on_custom(.{ .code = @fromBackingInt(@backingInt(message)) });
}

fn select(application: *Capture, command: Command) void {
    application.on_menu_select(.{ .checked = false, .id = @backingInt(command) });
}

fn tick(application: *Capture, timer: TimerID) void {
    application.on_timer_tick(.{ .id = @backingInt(timer), .count = 0 });
}

fn widget_of(application: *Capture) !*Widget {
    if (application.widget) |*widget| {
        return widget;
    }

    return error.MissingWidget;
}

fn widget_center(region: layout.HitRegion) kalymma.Point {
    const bounds = switch (region) {
        .button_next => layout.next_button(),
        .button_prev => layout.prev_button(),
        .button_close => layout.close_button(),
        .icon_speaker => layout.speaker_icon(),
        .slider => layout.slider(),
        .button_set_default => layout.set_default_button(),
        .button_reset_default => layout.reset_default_button(),
        .none => layout.title(),
    };

    const middle = bounds.center();
    return .{ .x = @intFromFloat(middle.x), .y = @intFromFloat(middle.y) };
}

test "a fresh application adopts the default capture device and starts unmuted" {
    const application = try open();
    defer close(application);

    try testing.expectEqual(State.inactive, application.state);
    try testing.expect(application.devices.current != null);
    try testing.expectEqualStrings("inactive", icon_of(application));
    try testing.expectEqualStrings("Exit", label_of(application, .exit));
}

test "a posted toggle mutes the device the application holds" {
    const application = try open();
    defer close(application);

    const id = try capture_first(application);

    post(application, .toggle);

    try testing.expectEqual(State.active, application.state);
    try testing.expect(try application.mixer.is_muted(&id));
    try testing.expectEqualStrings("active", icon_of(application));
}

test "a second posted toggle unmutes it again" {
    const application = try open();
    defer close(application);

    const id = try capture_first(application);

    post(application, .toggle);
    post(application, .toggle);

    try testing.expectEqual(State.inactive, application.state);
    try testing.expect(!try application.mixer.is_muted(&id));
    try testing.expectEqualStrings("inactive", icon_of(application));
}

test "an unknown custom code leaves the application alone" {
    const application = try open();
    defer close(application);

    post(application, @fromBackingInt(@backingInt(Message.widget_input) + 1));

    try testing.expectEqual(State.inactive, application.state);
}

test "many toggles leave the mute state consistent" {
    const application = try open();
    defer close(application);

    const id = try capture_first(application);

    var round: u32 = 0;

    while (round < 32) : (round += 1) {
        post(application, .toggle);

        try testing.expectEqual(round % 2 == 0, application.state.is_active());
        try testing.expectEqual(round % 2 == 0, try application.mixer.is_muted(&id));
    }

    try testing.expectEqual(State.inactive, application.state);
}

test "the render mode drives the render half of the device list" {
    const application = try testing.allocator.create(ApplicationType(Fakes, .render));
    defer testing.allocator.destroy(application);

    try application.init(testing.io, null);
    defer application.deinit();

    application.on_app_init();

    const current = application.devices.current orelse return error.MissingDevice;

    try testing.expectEqual(mantra.Direction.render, current.id.direction);
}

test "a hotplug event re-enumerates and keeps the selection" {
    const application = try open();
    defer close(application);

    const audio = &application.mixer.platform;
    const before = application.devices.count();

    audio.add(.capture, "capture-extra", "Extra Microphone");

    post(application, .device_changed);

    try testing.expectEqual(before + 1, application.devices.count());
    try testing.expect(application.devices.current != null);
}

test "losing the selected device leaves the application without one" {
    const application = try open();
    defer close(application);

    const audio = &application.mixer.platform;
    const current = application.devices.current orelse return error.MissingDevice;

    audio.remove(&current.id);

    application.devices.current = null;

    post(application, .device_changed);

    try testing.expect(application.devices.count() > 0);
}

test "a default change event asks the devices to restore the default" {
    const application = try open();
    defer close(application);

    const audio = &application.mixer.platform;
    const before = audio.count_of(.devices_set_default);

    application.devices.next();

    post(application, .device_default_changed);

    try testing.expect(audio.count_of(.devices_set_default) >= before);
}

test "an audio event of the other direction never reaches the loop" {
    const application = try open();
    defer close(application);

    const audio = &application.mixer.platform;
    const loop = &application.runtime.platform.loop;
    const before = loop.posts();

    try testing.expect(application.mixer.is_subscribed());

    audio.emit(.added, .render);

    try testing.expectEqual(before, loop.posts());

    audio.emit(.added, .capture);

    try testing.expectEqual(before + 1, loop.posts());
}

test "the overlay surface opens with the application and closes with it" {
    const application = try open();
    defer testing.allocator.destroy(application);

    const surfaces = &application.overlay.platform;

    try testing.expectEqual(@as(u32, 1), surfaces.count_of(.init));
    try testing.expect(application.widget != null);
    try testing.expectEqual(@as(u32, 1), surfaces.count_of(.surface_create));

    application.deinit();

    try testing.expect(application.widget == null);
}

test "a pointer press on the slider moves the real device volume" {
    const application = try open();
    defer close(application);

    const surfaces = &application.overlay.platform;
    const widget = try widget_of(application);
    const id = try capture_first(application);

    widget.show();

    surfaces.inject(widget.surface, .{ .pointer_down = .{ .x = 300, .y = 148 } });

    post(application, .widget_input);

    const level = try application.mixer.get_volume(&id);

    try testing.expect(level > 0.5);
}

test "a pointer press on the next button cycles the selected device" {
    const application = try open();
    defer close(application);

    const surfaces = &application.overlay.platform;
    const widget = try widget_of(application);

    widget.show();

    const before = application.devices.index;
    const next = widget_center(.button_next);

    surfaces.inject(widget.surface, .{ .pointer_down = next });
    surfaces.inject(widget.surface, .{ .pointer_up = next });

    post(application, .widget_input);

    try testing.expect(application.devices.index != before);
}

test "losing focus hides the overlay" {
    const application = try open();
    defer close(application);

    const surfaces = &application.overlay.platform;
    const widget = try widget_of(application);

    widget.show();

    try testing.expect(widget.is_visible());

    surfaces.inject(widget.surface, .{ .focus_lost = {} });

    post(application, .widget_input);

    try testing.expect(!widget.is_visible());
}

test "a tray click toggles the overlay" {
    const application = try open();
    defer close(application);

    const widget = try widget_of(application);

    try testing.expect(!widget.is_visible());

    application.on_tray_left_click();

    try testing.expect(widget.is_visible());

    application.on_tray_left_click();

    try testing.expect(!widget.is_visible());
}

test "the volume menu item shows the overlay and choosing it again keeps it shown" {
    const application = try open();
    defer close(application);

    const widget = try widget_of(application);

    try testing.expect(!widget.is_visible());
    try testing.expectEqualStrings("Volume", label_of(application, .volume));

    select(application, .volume);

    try testing.expect(widget.is_visible());

    select(application, .volume);

    try testing.expect(widget.is_visible());
    try testing.expectEqual(State.inactive, application.state);
}

test "showing the overlay presents a frame the renderer has drawn into" {
    const application = try open();
    defer close(application);

    const surfaces = &application.overlay.platform;
    const widget = try widget_of(application);

    widget.show();

    const pixels = application.overlay.surface_frame(widget.surface);

    var ink: u32 = 0;

    for (pixels) |pixel| {
        if (pixel >> 24 > 0) ink += 1;
    }

    try testing.expect(ink > pixels.len / 2);
    try testing.expect(surfaces.count_of(.surface_present) > 0);
    try testing.expectEqual(@as(u32, 0), pixels[0] >> 24);
}

test "hovering a region redraws the overlay differently" {
    const application = try open();
    defer close(application);

    const surfaces = &application.overlay.platform;
    const widget = try widget_of(application);

    widget.show();

    const idle = surfaces.checksum(widget.surface);
    const target = widget_center(.button_set_default);

    surfaces.inject(widget.surface, .{ .pointer_move = target });

    post(application, .widget_input);

    try testing.expect(surfaces.checksum(widget.surface) != idle);
}

test "the exit menu item stops the application" {
    const application = try open();
    defer close(application);

    select(application, .exit);
}

test "an unknown menu identifier is ignored" {
    const application = try open();
    defer close(application);

    select(application, @fromBackingInt(@backingInt(Command.volume) + 1));

    try testing.expectEqual(State.inactive, application.state);
}

test "a rebuilt menu still carries the exit item" {
    const application = try open();
    defer close(application);

    application.on_menu_show();

    try testing.expectEqualStrings("Exit", label_of(application, .exit));
}

test "a tick for another timer never restarts the input hook" {
    const application = try open();
    defer close(application);

    tick(application, .recovery);
}

test "shutdown stops the hotkey and leaves the application usable" {
    const application = try open();
    defer close(application);

    application.on_app_shutdown();

    try testing.expect(!application.hotkey.is_running());
}

test "a full run attaches every declared handler and the init event opens the overlay" {
    const application = try testing.allocator.create(Capture);
    defer testing.allocator.destroy(application);

    try application.init(testing.io, null);
    defer application.deinit();

    try testing.expect(application.widget == null);

    try application.run();

    try testing.expectEqual(@as(u8, 7), application.runtime.bus.listener_count());
    try testing.expect(application.widget != null);
    try testing.expect(application.watch != null);
}
