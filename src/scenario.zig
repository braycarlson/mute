const std = @import("std");

const kalymma = @import("kalymma");
const mantra = @import("mantra");
const nimble = @import("nimble");

const constant = @import("constant.zig");
const layout = @import("ui/layout.zig");

const ApplicationType = @import("application.zig").ApplicationType;

const audio = mantra.mock.state;
const surfaces = kalymma.mock.state;

const Capture = ApplicationType(.capture);

const testing = std.testing;

fn open(application: *Capture) !void {
    audio.reset();
    surfaces.reset();
    nimble.mock.reset();

    try application.init(testing.allocator, testing.io, null);

    application.on_init();
}

fn label_of(application: *const Capture, id: u32) []const u8 {
    const item = application.app.menu.get_item(id) orelse return "";

    return item.get_label();
}

fn icon_of(application: *const Capture) []const u8 {
    const name = application.app.icon.get_current_name() orelse return "";

    return name;
}

fn first_capture() !mantra.DeviceId {
    var list = mantra.DeviceList.init();

    try mantra.devices.enumerate(.capture, &list);
    try testing.expect(!list.is_empty());

    return list.items[0].id;
}

test "a fresh application adopts the default capture device and starts unmuted" {
    var application: Capture = undefined;

    try open(&application);
    defer application.deinit();

    try testing.expect(!application.active);
    try testing.expect(application.devices.current != null);
    try testing.expectEqualStrings("inactive", icon_of(&application));
    try testing.expectEqualStrings("Exit", label_of(&application, constant.Menu.exit));
}

test "a posted toggle mutes the device the manager holds" {
    var application: Capture = undefined;

    try open(&application);
    defer application.deinit();

    const id = try first_capture();

    application.on_custom(constant.Message.toggle);

    try testing.expect(application.active);
    try testing.expect(try mantra.control.is_muted(&id));
    try testing.expectEqualStrings("active", icon_of(&application));
}

test "a second posted toggle unmutes it again" {
    var application: Capture = undefined;

    try open(&application);
    defer application.deinit();

    const id = try first_capture();

    application.on_custom(constant.Message.toggle);
    application.on_custom(constant.Message.toggle);

    try testing.expect(!application.active);
    try testing.expect(!try mantra.control.is_muted(&id));
    try testing.expectEqualStrings("inactive", icon_of(&application));
}

test "an unknown custom code leaves the application alone" {
    var application: Capture = undefined;

    try open(&application);
    defer application.deinit();

    application.on_custom(constant.Message.widget_input + 1);

    try testing.expect(!application.active);
}

test "many toggles leave the mute state consistent" {
    var application: Capture = undefined;

    try open(&application);
    defer application.deinit();

    const id = try first_capture();

    var round: u32 = 0;

    while (round < 32) : (round += 1) {
        application.on_custom(constant.Message.toggle);

        try testing.expectEqual(round % 2 == 0, application.active);
        try testing.expectEqual(round % 2 == 0, try mantra.control.is_muted(&id));
    }

    try testing.expect(!application.active);
}

test "the render mode drives the render half of the device list" {
    var application: ApplicationType(.render) = undefined;

    audio.reset();
    surfaces.reset();
    nimble.mock.reset();

    try application.init(testing.allocator, testing.io, null);
    defer application.deinit();

    application.on_init();

    const current = application.devices.current orelse return error.MissingDevice;

    try testing.expectEqual(mantra.Direction.render, current.id.direction);
}

test "a hotplug event re-enumerates and keeps the selection" {
    var application: Capture = undefined;

    try open(&application);
    defer application.deinit();

    const before = application.devices.count();

    audio.add(.capture, "capture-extra", "Extra Microphone");

    application.on_custom(constant.Message.device_changed);

    try testing.expectEqual(before + 1, application.devices.count());
    try testing.expect(application.devices.current != null);
}

test "losing the selected device leaves the manager without one" {
    var application: Capture = undefined;

    try open(&application);
    defer application.deinit();

    const current = application.devices.current orelse return error.MissingDevice;

    audio.remove(&current.id);

    application.devices.current = null;
    application.on_custom(constant.Message.device_changed);

    try testing.expect(application.devices.count() > 0);
}

test "a default change event asks the manager to restore the default" {
    var application: Capture = undefined;

    try open(&application);
    defer application.deinit();

    const before = audio.count_of(.set_default);

    application.devices.next();
    application.on_custom(constant.Message.device_default_changed);

    try testing.expect(audio.count_of(.set_default) >= before);
}

test "an audio event of the other direction never reaches the loop" {
    var application: Capture = undefined;

    try open(&application);
    defer application.deinit();

    try testing.expect(mantra.events.is_subscribed());

    audio.emit(.added, .render);
    audio.emit(.added, .capture);
}

test "the overlay surface opens with the application and closes with it" {
    var application: Capture = undefined;

    try open(&application);

    try testing.expect(kalymma.runtime.is_open());
    try testing.expect(application.widget != null);
    try testing.expectEqual(@as(u32, 1), surfaces.count_of(.create));

    application.deinit();

    try testing.expect(!kalymma.runtime.is_open());
}

test "a pointer press on the slider moves the real device volume" {
    var application: Capture = undefined;

    try open(&application);
    defer application.deinit();

    const widget = application.widget orelse return error.MissingWidget;
    const id = try first_capture();

    widget.show();

    surfaces.inject(widget.surface, .{ .pointer_down = .{ .x = 300, .y = 148 } });

    application.on_custom(constant.Message.widget_input);

    const level = try mantra.control.get_volume(&id);

    try testing.expect(level > 0.5);
}

test "a pointer press on the next button cycles the selected device" {
    var application: Capture = undefined;

    try open(&application);
    defer application.deinit();

    const widget = application.widget orelse return error.MissingWidget;

    widget.show();

    const before = application.devices.index;
    const next = widget_center(.button_next);

    surfaces.inject(widget.surface, .{ .pointer_down = .{ .x = next.x, .y = next.y } });
    surfaces.inject(widget.surface, .{ .pointer_up = .{ .x = next.x, .y = next.y } });

    application.on_custom(constant.Message.widget_input);

    try testing.expect(application.devices.index != before);
}

test "losing focus hides the overlay" {
    var application: Capture = undefined;

    try open(&application);
    defer application.deinit();

    const widget = application.widget orelse return error.MissingWidget;

    widget.show();

    try testing.expect(widget.is_visible());

    surfaces.inject(widget.surface, .{ .focus_lost = {} });

    application.on_custom(constant.Message.widget_input);

    try testing.expect(!widget.is_visible());
}

test "a tray click toggles the overlay" {
    var application: Capture = undefined;

    try open(&application);
    defer application.deinit();

    const widget = application.widget orelse return error.MissingWidget;

    try testing.expect(!widget.is_visible());

    application.on_tray_click();

    try testing.expect(widget.is_visible());

    application.on_tray_click();

    try testing.expect(!widget.is_visible());
}

test "showing the overlay presents a frame the renderer has drawn into" {
    var application: Capture = undefined;

    try open(&application);
    defer application.deinit();

    const widget = application.widget orelse return error.MissingWidget;

    widget.show();

    const pixels = kalymma.surface.frame(widget.surface);

    var ink: u32 = 0;

    for (pixels) |pixel| {
        if (pixel >> 24 > 0) ink += 1;
    }

    try testing.expect(ink > pixels.len / 2);
    try testing.expect(surfaces.count_of(.present) > 0);
    try testing.expectEqual(@as(u32, 0), pixels[0] >> 24);
}

test "hovering a region redraws the overlay differently" {
    var application: Capture = undefined;

    try open(&application);
    defer application.deinit();

    const widget = application.widget orelse return error.MissingWidget;

    widget.show();

    const idle = surfaces.checksum(widget.surface);
    const target = widget_center(.button_set_default);

    surfaces.inject(widget.surface, .{ .pointer_move = .{ .x = target.x, .y = target.y } });

    application.on_custom(constant.Message.widget_input);

    try testing.expect(surfaces.checksum(widget.surface) != idle);
}

test "the exit menu item stops the application" {
    var application: Capture = undefined;

    try open(&application);
    defer application.deinit();

    application.on_menu_select(constant.Menu.exit);
}

test "an unknown menu identifier is ignored" {
    var application: Capture = undefined;

    try open(&application);
    defer application.deinit();

    application.on_menu_select(constant.Menu.exit + 1);

    try testing.expect(!application.active);
}

test "a rebuilt menu still carries the exit item" {
    var application: Capture = undefined;

    try open(&application);
    defer application.deinit();

    application.on_menu_show();

    try testing.expectEqualStrings("Exit", label_of(&application, constant.Menu.exit));
}

test "a tick for another timer never restarts the input hook" {
    var application: Capture = undefined;

    try open(&application);
    defer application.deinit();

    application.on_timer_tick(constant.Timer.rehook_id + 1);
}

test "shutdown stops the input thread and leaves the application usable" {
    var application: Capture = undefined;

    try open(&application);
    defer application.deinit();

    application.on_shutdown();

    try testing.expect(!application.input.is_running());
}

fn widget_center(region: layout.HitRegion) struct { x: i32, y: i32 } {
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
