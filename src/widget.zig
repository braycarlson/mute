const std = @import("std");

const kalymma = @import("kalymma");
const umbra = @import("umbra");

const canvas = @import("ui/canvas.zig");
const layout = @import("ui/layout.zig");
const renderer = @import("ui/renderer.zig");
const theme = @import("ui/theme.zig");

const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const Canvas = canvas.Canvas;
const Size = theme.Size;

pub const device_name_len_max: u32 = 256;
pub const focus_loss_threshold_ms: i64 = 300;
pub const surface_margin: u32 = 12;
pub const title_len_max: u32 = 64;
pub const volume_step: f32 = 0.01;

comptime {
    assert(device_name_len_max > 0);
    assert(focus_loss_threshold_ms > 0);
    assert(title_len_max > 0);
    assert(volume_step > 0);
    assert(Size.widget_width > 0);
    assert(Size.widget_height > 0);
    assert(Size.widget_width <= kalymma.width_max);
    assert(Size.widget_height <= kalymma.height_max);
}

pub const Error = error{
    SurfaceFailed,
};

pub const WidgetEvent = enum {
    volume_changed,
    device_next,
    device_prev,
    set_default,
    reset_default,
    mute_toggled,
    closed,
};

pub const WidgetCallback = *const fn (event: WidgetEvent, value: f32, context: ?*anyopaque) void;

const VolumeState = struct {
    before_mute: f32 = 0.5,
    current: f32 = 0.5,
    default: f32 = 0.5,
    is_muted: bool = false,
};

const DeviceState = struct {
    count: u32 = 1,
    index: u32 = 0,
    name: [device_name_len_max]u8 = @splat(0),
    name_len: u32 = 0,

    pub fn get_name_slice(state: *const DeviceState) []const u8 {
        assert(state.name_len <= device_name_len_max);

        return state.name[0..state.name_len];
    }

    pub fn set_name(state: *DeviceState, name: ?[]const u8) void {
        const value = name orelse {
            state.name_len = 0;

            return;
        };

        const length: u32 = @intCast(@min(value.len, device_name_len_max));

        @memcpy(state.name[0..length], value[0..length]);

        state.name_len = length;

        assert(state.name_len <= device_name_len_max);
    }
};

const InteractionState = struct {
    dragging: bool = false,
    focus_loss_hide_time: i64 = 0,
    focused_region: renderer.State.FocusRegion = .none,
    hover_region: layout.HitRegion = .none,
};

pub const Widget = struct {
    gpa: Allocator,
    callback: ?WidgetCallback = null,
    callback_context: ?*anyopaque = null,
    device: DeviceState = .{},
    interaction: InteractionState = .{},
    surface: kalymma.Handle = .{},
    title: [title_len_max]u8 = @splat(0),
    title_len: u32 = 0,
    volume: VolumeState = .{},

    pub fn create(gpa: Allocator, name: []const u8) Error!*Widget {
        assert(name.len > 0);

        const self = gpa.create(Widget) catch {
            return Error.SurfaceFailed;
        };

        errdefer gpa.destroy(self);

        self.* = Widget{ .gpa = gpa };

        self.surface = kalymma.surface.create(.{
            .anchor = .bottom_right,
            .height = @intCast(Size.widget_height),
            .margin = surface_margin,
            .name = name,
            .width = @intCast(Size.widget_width),
        }) catch {
            return Error.SurfaceFailed;
        };

        assert(self.surface.is_valid());

        return self;
    }

    pub fn destroy(widget: *Widget) void {
        kalymma.surface.destroy(widget.surface);

        widget.gpa.destroy(widget);
    }

    pub fn drain(widget: *Widget) void {
        var list = kalymma.EventList.init();

        _ = kalymma.events.poll(&list);

        for (list.slice()) |event| {
            if (!event.handle.eql(widget.surface)) {
                continue;
            }

            widget.dispatch(event.input);
        }
    }

    pub fn hide(widget: *Widget) void {
        kalymma.surface.hide(widget.surface);

        widget.interaction.dragging = false;
        widget.interaction.focused_region = .none;
    }

    pub fn is_visible(widget: *const Widget) bool {
        return kalymma.surface.is_visible(widget.surface);
    }

    pub fn post_toggle(widget: *Widget) void {
        const now: i64 = @intCast(umbra.time.now_ms());

        const recently_hidden = widget.interaction.focus_loss_hide_time > 0 and
            (now - widget.interaction.focus_loss_hide_time) < focus_loss_threshold_ms;

        if (recently_hidden) {
            widget.interaction.focus_loss_hide_time = 0;

            return;
        }

        widget.toggle();
    }

    pub fn set_callback(widget: *Widget, callback: WidgetCallback, context: ?*anyopaque) void {
        widget.callback = callback;
        widget.callback_context = context;
    }

    pub fn set_default_volume(widget: *Widget, volume: f32) void {
        assert(volume >= 0.0);
        assert(volume <= 1.0);

        widget.volume.default = std.math.clamp(volume, 0.0, 1.0);

        widget.invalidate();
    }

    pub fn set_device_info(widget: *Widget, name: ?[]const u8, index: u32, count: u32) void {
        widget.device.set_name(name);

        widget.device.index = index;
        widget.device.count = count;

        widget.invalidate();
    }

    pub fn set_muted(widget: *Widget, muted: bool) void {
        if (muted and !widget.volume.is_muted) {
            widget.volume.before_mute = widget.volume.current;
        }

        widget.volume.is_muted = muted;

        widget.invalidate();
    }

    pub fn set_title(widget: *Widget, text: []const u8) void {
        const length: u32 = @intCast(@min(text.len, title_len_max));

        @memcpy(widget.title[0..length], text[0..length]);

        widget.title_len = length;

        assert(widget.title_len <= title_len_max);

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

        kalymma.surface.show(widget.surface) catch {
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

    fn get_render_state(widget: *const Widget) renderer.State {
        assert(widget.volume.current >= 0.0);
        assert(widget.volume.current <= 1.0);

        return .{
            .device_name = widget.device.get_name_slice(),
            .dragging = widget.interaction.dragging,
            .focus = widget.interaction.focused_region,
            .hover = widget.interaction.hover_region,
            .is_muted = widget.volume.is_muted,
            .title = widget.title[0..widget.title_len],
            .volume = widget.volume.current,
        };
    }

    fn invalidate(widget: *Widget) void {
        const pixels = kalymma.surface.frame(widget.surface);

        if (pixels.len == 0) {
            return;
        }

        var target = Canvas.init(pixels, Size.widget_width, Size.widget_height);

        const state = widget.get_render_state();

        renderer.render(&target, &state);

        kalymma.surface.present(widget.surface) catch {
            return;
        };
    }

    fn fire_event(widget: *Widget, event: WidgetEvent, value: f32) void {
        const callback = widget.callback orelse return;

        callback(event, value, widget.callback_context);
    }

    fn dispatch(widget: *Widget, input: kalymma.InputEvent) void {
        switch (input) {
            .pointer_move => |point| widget.on_pointer_move(point.x, point.y),
            .pointer_down => |point| widget.on_pointer_down(point.x, point.y),
            .pointer_up => |point| widget.on_pointer_up(point.x, point.y),
            .pointer_leave => widget.on_pointer_leave(),
            .key_down => |key| widget.on_key_down(key),
            .focus_lost => widget.on_focus_lost(),
        }
    }

    fn on_pointer_move(widget: *Widget, x: i32, y: i32) void {
        if (widget.interaction.dragging) {
            widget.apply_slider(layout.volume_from_x(x));

            return;
        }

        const hover = layout.hit_test(x, y);

        if (hover == widget.interaction.hover_region) {
            return;
        }

        widget.interaction.hover_region = hover;

        widget.invalidate();
    }

    fn on_pointer_down(widget: *Widget, x: i32, y: i32) void {
        const region = layout.hit_test(x, y);

        if (region == .slider) {
            widget.interaction.dragging = true;
            widget.interaction.focused_region = .slider;

            widget.apply_slider(layout.volume_from_x(x));

            return;
        }

        widget.interaction.focused_region = if (region == .button_prev or region == .button_next)
            .device
        else
            .none;

        widget.invalidate();
    }

    fn on_pointer_up(widget: *Widget, x: i32, y: i32) void {
        if (widget.interaction.dragging) {
            widget.interaction.dragging = false;

            widget.invalidate();

            return;
        }

        switch (layout.hit_test(x, y)) {
            .button_prev => {
                widget.interaction.focused_region = .device;

                widget.fire_event(.device_prev, 0);
            },
            .button_next => {
                widget.interaction.focused_region = .device;

                widget.fire_event(.device_next, 0);
            },
            .button_set_default => {
                widget.fire_event(.set_default, widget.volume.current);
            },
            .button_reset_default => {
                widget.volume.current = widget.volume.default;
                widget.volume.is_muted = false;

                widget.invalidate();
                widget.fire_event(.reset_default, widget.volume.default);
            },
            .icon_speaker => {
                widget.toggle_mute();
            },
            .button_close => {
                widget.hide();
                widget.fire_event(.closed, 0);
            },
            else => {},
        }
    }

    fn on_pointer_leave(widget: *Widget) void {
        widget.interaction.hover_region = .none;

        widget.invalidate();
    }

    fn on_key_down(widget: *Widget, key: kalymma.Key) void {
        switch (widget.interaction.focused_region) {
            .slider => widget.on_slider_key(key),
            .device => widget.on_device_key(key),
            .none => {},
        }
    }

    fn on_slider_key(widget: *Widget, key: kalymma.Key) void {
        switch (key) {
            .left, .down => {
                widget.volume.current = @max(0.0, widget.volume.current - volume_step);

                if (widget.volume.current == 0.0) {
                    widget.volume.is_muted = true;
                }

                widget.invalidate();
                widget.fire_event(.volume_changed, widget.volume.current);
            },
            .right, .up => {
                widget.volume.current = @min(1.0, widget.volume.current + volume_step);
                widget.volume.is_muted = false;

                widget.invalidate();
                widget.fire_event(.volume_changed, widget.volume.current);
            },
            else => {},
        }
    }

    fn on_device_key(widget: *Widget, key: kalymma.Key) void {
        switch (key) {
            .left, .up => widget.fire_event(.device_prev, 0),
            .right, .down => widget.fire_event(.device_next, 0),
            else => {},
        }
    }

    fn on_focus_lost(widget: *Widget) void {
        if (!widget.is_visible()) {
            return;
        }

        widget.interaction.focus_loss_hide_time = @intCast(umbra.time.now_ms());

        widget.hide();
        widget.fire_event(.closed, 0);
    }

    fn apply_slider(widget: *Widget, value: f32) void {
        assert(value >= 0.0);
        assert(value <= 1.0);

        widget.volume.current = value;

        if (value > 0.0) {
            widget.volume.is_muted = false;
        }

        widget.invalidate();
        widget.fire_event(.volume_changed, value);
    }

    fn toggle_mute(widget: *Widget) void {
        if (widget.volume.is_muted) {
            widget.volume.is_muted = false;
            widget.volume.current = widget.volume.before_mute;

            widget.invalidate();
            widget.fire_event(.mute_toggled, widget.volume.current);

            return;
        }

        widget.volume.before_mute = widget.volume.current;
        widget.volume.is_muted = true;

        widget.invalidate();
        widget.fire_event(.mute_toggled, 0.0);
    }
};

const testing = std.testing;

test "a device name longer than the field is truncated rather than overflowing" {
    var device = DeviceState{};

    device.set_name("n" ** (device_name_len_max + 32));

    try testing.expectEqual(device_name_len_max, device.name_len);
    try testing.expectEqual(@as(usize, device_name_len_max), device.get_name_slice().len);
}

test "a null device name clears the field" {
    var device = DeviceState{};

    device.set_name("Microphone");

    try testing.expectEqualStrings("Microphone", device.get_name_slice());

    device.set_name(null);

    try testing.expectEqual(@as(u32, 0), device.name_len);
}

test "the widget fits inside the surface contract" {
    try testing.expect(Size.widget_width <= kalymma.width_max);
    try testing.expect(Size.widget_height <= kalymma.height_max);
}
