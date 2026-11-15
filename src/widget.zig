const std = @import("std");

const kalymma = @import("kalymma");
const mantra = @import("mantra");

const canvas = @import("ui.zig").canvas;
const layout = @import("ui.zig").layout;
const rect = @import("ui.zig").rect;
const renderer = @import("ui.zig").renderer;
const State = @import("state.zig").State;
const theme = @import("ui.zig").theme;

const assert = std.debug.assert;

const Canvas = canvas.Canvas;

const focus_loss_threshold_ms: i64 = 300;
const surface_margin: u32 = 12;
const volume_step: f32 = 0.01;

comptime {
    assert(focus_loss_threshold_ms > 0);
    assert(volume_step > 0);
    assert(theme.size.widget_width > 0);
    assert(theme.size.widget_height > 0);
    assert(theme.size.widget_width <= kalymma.limits.width_pixels_max);
    assert(theme.size.widget_height <= kalymma.limits.height_pixels_max);
}

const DeviceState = struct {
    name: [mantra.limits.name_bytes_max]u8 = @splat(0),
    name_length: u32 = 0,

    fn get_name(state: *const DeviceState) []const u8 {
        assert(state.name_length <= mantra.limits.name_bytes_max);

        return state.name[0..state.name_length];
    }

    fn set_name(state: *DeviceState, name: ?[]const u8) void {
        const value = name orelse {
            state.name_length = 0;

            return;
        };

        const length: u32 = @intCast(@min(value.len, mantra.limits.name_bytes_max));

        @memcpy(state.name[0..length], value[0..length]);

        state.name_length = length;

        assert(state.name_length <= mantra.limits.name_bytes_max);
    }
};

const InteractionState = struct {
    dragging: bool = false,
    focus_loss_hide_time: i64 = 0,
    focused_region: renderer.State.FocusRegion = .none,
    hover_region: layout.HitRegion = .none,
};

const VolumeState = struct {
    before_mute: f32 = 0.5,
    current: f32 = 0.5,
    default: f32 = 0.5,
    is_muted: bool = false,
};

pub fn WidgetType(comptime Runtime: type) type {
    return struct {
        device: DeviceState,
        interaction: InteractionState,
        runtime: *Runtime,
        surface: kalymma.Surface,
        title: [renderer.title_bytes_max]u8,
        title_length: u32,
        volume: VolumeState,

        const Widget = @This();

        pub const Action = union(enum) {
            closed,
            device_next,
            device_previous,
            mute_toggled,
            reset_default,
            set_default,
            volume_changed: f32,
        };

        pub const ActionList = struct {
            count: u32,
            items: [kalymma.limits.event_count_max]Action,

            pub fn init() ActionList {
                return ActionList{ .count = 0, .items = undefined };
            }

            pub fn slice(list: *const ActionList) []const Action {
                assert(list.count <= kalymma.limits.event_count_max);

                return list.items[0..list.count];
            }

            fn append(list: *ActionList, action: Action) void {
                assert(list.count < kalymma.limits.event_count_max);

                list.items[list.count] = action;
                list.count += 1;
            }
        };

        pub fn init(runtime: *Runtime, name: []const u8) kalymma.Error!Widget {
            assert(name.len > 0);

            const surface = try runtime.surface_create(.{
                .anchor = .bottom_right,
                .height = @intCast(theme.size.widget_height),
                .margin = surface_margin,
                .name = name,
                .width = @intCast(theme.size.widget_width),
            });

            assert(!runtime.surface_is_visible(surface));

            return Widget{
                .device = .{},
                .interaction = .{},
                .runtime = runtime,
                .surface = surface,
                .title = @splat(0),
                .title_length = 0,
                .volume = .{},
            };
        }

        pub fn deinit(widget: *Widget) void {
            widget.runtime.surface_destroy(widget.surface);
        }

        pub fn drain(widget: *Widget, actions: *ActionList, now_ms: u64) void {
            assert(actions.count == 0);
            assert(now_ms > 0);

            var list = kalymma.Event.List.init();

            _ = widget.runtime.events_poll(&list);

            for (list.slice()) |event| {
                const surface = switch (event.source) {
                    .surface => |surface| surface,
                    .display, .shade => continue,
                };

                if (surface != widget.surface) {
                    continue;
                }

                if (widget.dispatch(event.input, now_ms)) |action| {
                    actions.append(action);
                }
            }

            assert(actions.count <= list.slice().len);
        }

        pub fn is_visible(widget: *const Widget) bool {
            return widget.runtime.surface_is_visible(widget.surface);
        }

        pub fn post_toggle(widget: *Widget, now_ms: u64) void {
            assert(now_ms > 0);

            const now: i64 = @intCast(now_ms);

            const recently_hidden = widget.interaction.focus_loss_hide_time > 0 and
                (now - widget.interaction.focus_loss_hide_time) < focus_loss_threshold_ms;

            if (recently_hidden) {
                widget.interaction.focus_loss_hide_time = 0;

                return;
            }

            widget.toggle();
        }

        pub fn set_default_volume(widget: *Widget, volume: f32) void {
            assert(volume >= 0.0);
            assert(volume <= 1.0);

            widget.volume.default = std.math.clamp(volume, 0.0, 1.0);

            widget.invalidate();
        }

        pub fn set_device_name(widget: *Widget, name: ?[]const u8) void {
            if (name) |value| assert(value.len <= mantra.limits.name_bytes_max);

            widget.device.set_name(name);

            widget.invalidate();
        }

        pub fn set_state(widget: *Widget, state: State) void {
            const muted = state.is_active();

            if (muted) {
                if (!widget.volume.is_muted) {
                    widget.volume.before_mute = widget.volume.current;
                }
            }

            widget.volume.is_muted = muted;

            widget.invalidate();
        }

        pub fn set_title(widget: *Widget, text: []const u8) void {
            assert(text.len > 0);
            assert(text.len <= renderer.title_bytes_max);

            const length: u32 = @intCast(@min(text.len, renderer.title_bytes_max));

            @memcpy(widget.title[0..length], text[0..length]);

            widget.title_length = length;

            assert(widget.title_length <= renderer.title_bytes_max);

            widget.invalidate();
        }

        pub fn set_volume(widget: *Widget, volume: f32) void {
            assert(volume >= 0.0);
            assert(volume <= 1.0);

            widget.volume.current = std.math.clamp(volume, 0.0, 1.0);

            if (volume > 0.0) {
                widget.volume.is_muted = false;
            }

            widget.invalidate();
        }

        pub fn show(widget: *Widget) void {
            widget.interaction.focus_loss_hide_time = 0;

            widget.runtime.surface_show(widget.surface) catch {
                return;
            };

            widget.invalidate();
        }

        pub fn toggle(widget: *Widget) void {
            if (widget.is_visible()) {
                widget.hide();

                return;
            }

            widget.show();
        }

        fn apply_slider(widget: *Widget, value: f32) Action {
            assert(value >= 0.0);
            assert(value <= 1.0);

            widget.volume.current = value;

            if (value > 0.0) {
                widget.volume.is_muted = false;
            }

            widget.invalidate();

            return .{ .volume_changed = value };
        }

        fn dispatch(widget: *Widget, input: kalymma.Event.Input, now_ms: u64) ?Action {
            assert(now_ms > 0);

            return switch (input) {
                .pointer_move => |point| widget.on_pointer_move(point),
                .pointer_down => |point| widget.on_pointer_down(point),
                .pointer_up => |point| widget.on_pointer_up(point),
                .pointer_leave => widget.on_pointer_leave(),
                .key_down => |key| widget.on_key_down(key),
                .focus_lost => widget.on_focus_lost(now_ms),
                .monitors_changed => null,
            };
        }

        fn hide(widget: *Widget) void {
            widget.runtime.surface_hide(widget.surface);

            widget.interaction.dragging = false;
            widget.interaction.focused_region = .none;
        }

        fn invalidate(widget: *Widget) void {
            const pixels = widget.runtime.surface_frame(widget.surface);

            if (pixels.len == 0) {
                return;
            }

            var target = Canvas.init(pixels, theme.size.widget_width);

            assert(target.height == theme.size.widget_height);

            const state = widget.render_state();

            renderer.render(&target, &state);

            widget.runtime.surface_present(widget.surface) catch {
                return;
            };
        }

        fn on_focus_lost(widget: *Widget, now_ms: u64) ?Action {
            assert(now_ms > 0);

            if (!widget.is_visible()) {
                return null;
            }

            widget.interaction.focus_loss_hide_time = @intCast(now_ms);

            widget.hide();

            return .closed;
        }

        fn on_key_down(widget: *Widget, key: kalymma.Key) ?Action {
            return switch (widget.interaction.focused_region) {
                .slider => widget.on_slider_key(key),
                .device => device_key_action(key),
                .none => null,
            };
        }

        fn on_pointer_down(widget: *Widget, point: kalymma.Point) ?Action {
            assert(rect.is_position(point));

            const region = layout.hit_test(point);

            if (region == .slider) {
                widget.interaction.dragging = true;
                widget.interaction.focused_region = .slider;

                return widget.apply_slider(layout.volume_from_x(point.x));
            }

            widget.interaction.focused_region = switch (region) {
                .button_next, .button_prev => .device,
                else => .none,
            };

            widget.invalidate();

            return null;
        }

        fn on_pointer_leave(widget: *Widget) ?Action {
            widget.interaction.hover_region = .none;

            widget.invalidate();

            return null;
        }

        fn on_pointer_move(widget: *Widget, point: kalymma.Point) ?Action {
            assert(rect.is_position(point));

            if (widget.interaction.dragging) {
                return widget.apply_slider(layout.volume_from_x(point.x));
            }

            const hover = layout.hit_test(point);

            if (hover == widget.interaction.hover_region) {
                return null;
            }

            widget.interaction.hover_region = hover;

            widget.invalidate();

            return null;
        }

        fn on_pointer_up(widget: *Widget, point: kalymma.Point) ?Action {
            assert(rect.is_position(point));

            if (widget.interaction.dragging) {
                widget.interaction.dragging = false;

                widget.invalidate();

                return null;
            }

            switch (layout.hit_test(point)) {
                .button_prev => {
                    widget.interaction.focused_region = .device;

                    return .device_previous;
                },
                .button_next => {
                    widget.interaction.focused_region = .device;

                    return .device_next;
                },
                .button_set_default => return .set_default,
                .button_reset_default => {
                    widget.volume.current = widget.volume.default;
                    widget.volume.is_muted = false;

                    widget.invalidate();

                    return .reset_default;
                },
                .icon_speaker => return widget.toggle_mute(),
                .button_close => {
                    widget.hide();

                    return .closed;
                },
                .none, .slider => return null,
            }
        }

        fn on_slider_key(widget: *Widget, key: kalymma.Key) ?Action {
            switch (key) {
                .left, .down => {
                    widget.volume.current = @max(0.0, widget.volume.current - volume_step);

                    if (widget.volume.current == 0.0) {
                        widget.volume.is_muted = true;
                    }

                    widget.invalidate();

                    return .{ .volume_changed = widget.volume.current };
                },
                .right, .up => {
                    widget.volume.current = @min(1.0, widget.volume.current + volume_step);
                    widget.volume.is_muted = false;

                    widget.invalidate();

                    return .{ .volume_changed = widget.volume.current };
                },
                else => return null,
            }
        }

        fn render_state(widget: *const Widget) renderer.State {
            assert(widget.volume.current >= 0.0);
            assert(widget.volume.current <= 1.0);

            return .{
                .device_name = widget.device.get_name(),
                .dragging = widget.interaction.dragging,
                .focus = widget.interaction.focused_region,
                .hover = widget.interaction.hover_region,
                .is_muted = widget.volume.is_muted,
                .title = widget.title[0..widget.title_length],
                .volume = widget.volume.current,
            };
        }

        fn toggle_mute(widget: *Widget) Action {
            if (widget.volume.is_muted) {
                widget.volume.is_muted = false;
                widget.volume.current = widget.volume.before_mute;

                widget.invalidate();

                return .mute_toggled;
            }

            widget.volume.before_mute = widget.volume.current;
            widget.volume.is_muted = true;

            widget.invalidate();

            return .mute_toggled;
        }

        fn device_key_action(key: kalymma.Key) ?Action {
            return switch (key) {
                .left, .up => .device_previous,
                .right, .down => .device_next,
                else => null,
            };
        }
    };
}

const testing = std.testing;

const Fakes = @import("fakes.zig");

const FakeWidget = WidgetType(Fakes.Runtime);

test WidgetType {
    const runtime = try testing.allocator.create(Fakes.Runtime);
    defer testing.allocator.destroy(runtime);

    try runtime.init(.{});
    defer runtime.deinit();

    var widget = try FakeWidget.init(runtime, "widget-test");
    defer widget.deinit();

    widget.set_title("Mute");
    widget.set_device_name("Microphone");
    widget.show();

    try testing.expect(widget.is_visible());

    const slider = layout.slider().center();
    const next = layout.next_button().center();
    const press = kalymma.Point{ .x = @intFromFloat(slider.x), .y = @intFromFloat(slider.y) };
    const click = kalymma.Point{ .x = @intFromFloat(next.x), .y = @intFromFloat(next.y) };

    runtime.platform.inject(widget.surface, .{ .pointer_down = press });
    runtime.platform.inject(widget.surface, .{ .pointer_up = press });
    runtime.platform.inject(widget.surface, .{ .pointer_up = click });

    var actions = FakeWidget.ActionList.init();

    widget.drain(&actions, 1_000);

    const drained = actions.slice();

    try testing.expectEqual(@as(usize, 2), drained.len);
    try testing.expect(drained[0] == .volume_changed);
    try testing.expect(drained[1] == .device_next);
}

test "a device name longer than the field is truncated rather than overflowing" {
    var device = DeviceState{};
    const name: [mantra.limits.name_bytes_max + 32]u8 = @splat('n');

    device.set_name(&name);

    try testing.expectEqual(mantra.limits.name_bytes_max, device.name_length);
    try testing.expectEqual(@as(usize, mantra.limits.name_bytes_max), device.get_name().len);
}

test "a null device name clears the field" {
    var device = DeviceState{};

    device.set_name("Microphone");

    try testing.expectEqualStrings("Microphone", device.get_name());

    device.set_name(null);

    try testing.expectEqual(@as(u32, 0), device.name_length);
}

test "a device key steps through the devices and ignores the rest" {
    const Action = FakeWidget.Action;

    try testing.expectEqual(Action.device_previous, FakeWidget.device_key_action(.left).?);
    try testing.expectEqual(Action.device_next, FakeWidget.device_key_action(.down).?);
}
