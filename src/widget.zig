const std = @import("std");

const w32 = @import("win32").everything;

const nimble = @import("nimble");

const hook = nimble.hook;

const gdiplus = @import("ui/gdiplus.zig");
const layout = @import("ui/layout.zig");
const renderer = @import("ui/renderer.zig");
const theme = @import("ui/theme.zig");

const GdiplusContext = @import("ui/context.zig").GdiplusContext;
const Size = theme.Size;

const VK_LEFT: u32 = 0x25;
const VK_UP: u32 = 0x26;
const VK_RIGHT: u32 = 0x27;
const VK_DOWN: u32 = 0x28;

const focus_loss_threshold_ms: i64 = 300;
const device_name_len_max: u32 = 256;
const title_len_max: u32 = 64;
const row_bytes: u32 = @intCast(Size.widget_width * 4);

const BLENDFUNCTION = extern struct {
    BlendOp: u8 = 0,
    BlendFlags: u8 = 0,
    SourceConstantAlpha: u8 = 255,
    AlphaFormat: u8 = 1,
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
    current: f32 = 0.5,
    default: f32 = 0.5,
    before_mute: f32 = 0.5,
    is_muted: bool = false,
};

const DeviceState = struct {
    name: [device_name_len_max]u8 = [_]u8{0} ** device_name_len_max,
    name_len: u32 = 0,
    index: u32 = 0,
    count: u32 = 1,

    pub fn get_name_slice(self: *const DeviceState) []const u8 {
        std.debug.assert(self.name_len <= device_name_len_max);

        return self.name[0..self.name_len];
    }

    pub fn set_name(self: *DeviceState, name: ?[]const u8) void {
        if (name) |n| {
            const length: u32 = @intCast(@min(n.len, device_name_len_max));

            std.debug.assert(length <= device_name_len_max);

            var index: u32 = 0;
            while (index < length) : (index += 1) {
                std.debug.assert(index < device_name_len_max);

                self.name[index] = n[index];
            }

            std.debug.assert(index == length);

            self.name_len = length;
        } else {
            self.name_len = 0;
        }
    }
};

const InteractionState = struct {
    dragging: bool = false,
    focused_region: renderer.State.FocusRegion = .none,
    focus_loss_hide_time: i64 = 0,
    hover_region: layout.HitRegion = .none,
};

pub const Widget = struct {
    allocator: std.mem.Allocator,
    callback: ?WidgetCallback = null,
    callback_context: ?*anyopaque = null,
    class_name: [:0]const u16,
    device: DeviceState = .{},
    fonts: renderer.Fonts = .{},
    gdiplus_context: GdiplusContext = .{},
    handle: ?w32.HWND = null,
    interaction: InteractionState = .{},
    parent: w32.HWND,
    title: [title_len_max]u8 = [_]u8{0} ** title_len_max,
    title_len: u32 = 0,
    volume: VolumeState = .{},

    pub fn create(allocator: std.mem.Allocator, parent: w32.HWND, class_name: [:0]const u16) !*Widget {
        std.debug.assert(class_name.len > 0);

        var self = try allocator.create(Widget);
        errdefer allocator.destroy(self);

        self.* = Widget{
            .allocator = allocator,
            .class_name = class_name,
            .parent = parent,
        };

        self.gdiplus_context = GdiplusContext.init();
        self.fonts = renderer.Fonts.init();

        try self.register_class();
        try self.create_window();

        return self;
    }

    pub fn destroy(self: *Widget) void {
        std.debug.assert(self.class_name.len > 0);

        self.hide();

        if (self.handle) |handle| {
            _ = w32.DestroyWindow(handle);
        }

        self.fonts.deinit();
        self.gdiplus_context.deinit();
        self.allocator.destroy(self);
    }

    fn register_class(self: *Widget) !void {
        std.debug.assert(self.class_name.len > 0);

        var window_class = std.mem.zeroes(w32.WNDCLASSEXW);
        window_class.cbSize = @sizeOf(w32.WNDCLASSEXW);
        window_class.lpfnWndProc = window_proc;
        window_class.hInstance = hook.module();
        window_class.lpszClassName = self.class_name;
        window_class.hCursor = w32.LoadCursorW(null, w32.IDC_ARROW);
        window_class.style = .{ .HREDRAW = 1, .VREDRAW = 1 };

        const result = w32.RegisterClassExW(&window_class);

        if (result == 0) {
            const err = w32.GetLastError();

            if (@intFromEnum(err) != 1410) {
                return error.ClassRegistrationFailed;
            }
        }
    }

    fn create_window(self: *Widget) !void {
        std.debug.assert(self.class_name.len > 0);

        self.handle = w32.CreateWindowExW(
            .{ .TOPMOST = 1, .TOOLWINDOW = 1, .LAYERED = 1 },
            self.class_name,
            std.unicode.utf8ToUtf16LeStringLiteral(""),
            .{ .POPUP = 1 },
            0,
            0,
            Size.widget_width,
            Size.widget_height,
            self.parent,
            null,
            hook.module(),
            null,
        );

        if (self.handle == null) {
            return error.WindowCreationFailed;
        }

        _ = w32.SetWindowLongPtrW(
            self.handle.?,
            w32.GWLP_USERDATA,
            @bitCast(@intFromPtr(self)),
        );
    }

    fn get_render_state(self: *Widget) renderer.State {
        std.debug.assert(self.volume.current >= 0.0);
        std.debug.assert(self.volume.current <= 1.0);

        return .{
            .volume = self.volume.current,
            .is_muted = self.volume.is_muted,
            .hover = self.interaction.hover_region,
            .focus = self.interaction.focused_region,
            .dragging = self.interaction.dragging,
            .device_name = self.device.get_name_slice(),
            .title = self.title[0..self.title_len],
        };
    }

    fn paint(self: *Widget, device_context: w32.HDC) void {
        std.debug.assert(self.volume.current >= 0.0);
        std.debug.assert(self.volume.current <= 1.0);

        var bitmap: *gdiplus.Bitmap = undefined;

        const bitmap_status = gdiplus.GdipCreateBitmapFromScan0(
            Size.widget_width,
            Size.widget_height,
            0,
            gdiplus.pixel_format_32bpp_pargb,
            null,
            &bitmap,
        );

        if (bitmap_status != .Ok) {
            return;
        }

        defer _ = gdiplus.GdipDisposeImage(bitmap);

        var graphics: *gdiplus.Graphics = undefined;

        if (gdiplus.GdipGetImageGraphicsContext(bitmap, &graphics) != .Ok) {
            return;
        }

        defer _ = gdiplus.GdipDeleteGraphics(graphics);

        const state = self.get_render_state();
        renderer.render(graphics, &self.fonts, &state);

        self.update_layered_window(device_context, bitmap);
    }

    fn update_layered_window(self: *Widget, device_context: w32.HDC, bitmap: *gdiplus.Bitmap) void {
        const handle = self.handle orelse return;

        var locked: gdiplus.BitmapData = undefined;

        const lock_status = gdiplus.GdipBitmapLockBits(
            bitmap,
            null,
            gdiplus.image_lock_mode_read,
            gdiplus.pixel_format_32bpp_pargb,
            &locked,
        );

        if (lock_status != .Ok) {
            return;
        }

        defer _ = gdiplus.GdipBitmapUnlockBits(bitmap, &locked);

        var bitmap_info = std.mem.zeroes(w32.BITMAPINFO);
        bitmap_info.bmiHeader.biSize = @sizeOf(w32.BITMAPINFOHEADER);
        bitmap_info.bmiHeader.biWidth = Size.widget_width;
        bitmap_info.bmiHeader.biHeight = -Size.widget_height;
        bitmap_info.bmiHeader.biPlanes = 1;
        bitmap_info.bmiHeader.biBitCount = 32;
        bitmap_info.bmiHeader.biCompression = w32.BI_RGB;

        const memory_device_context = w32.CreateCompatibleDC(device_context);
        defer _ = w32.DeleteDC(memory_device_context);

        var bits: ?*anyopaque = null;

        const dib = w32.CreateDIBSection(
            memory_device_context,
            &bitmap_info,
            w32.DIB_RGB_COLORS,
            &bits,
            null,
            0,
        );
        defer _ = w32.DeleteObject(dib);

        if (bits) |destination| {
            self.copy_bitmap_data(locked, destination);
        }

        _ = w32.SelectObject(memory_device_context, dib);

        var point_zero = w32.POINT{ .x = 0, .y = 0 };
        var point_position: w32.POINT = undefined;
        var window_rect: w32.RECT = undefined;

        _ = w32.GetWindowRect(handle, &window_rect);

        point_position.x = window_rect.left;
        point_position.y = window_rect.top;

        var size = w32.SIZE{ .cx = Size.widget_width, .cy = Size.widget_height };
        var blend = BLENDFUNCTION{};

        _ = w32.UpdateLayeredWindow(
            handle,
            device_context,
            &point_position,
            &size,
            memory_device_context,
            &point_zero,
            0,
            @ptrCast(&blend),
            w32.ULW_ALPHA,
        );
    }

    fn copy_bitmap_data(self: *Widget, locked: gdiplus.BitmapData, destination: *anyopaque) void {
        _ = self;

        const source: [*]u8 = @ptrCast(locked.scan0);
        const destination_ptr: [*]u8 = @ptrCast(destination);
        const absolute_stride: u32 = @intCast(if (locked.stride < 0) -locked.stride else locked.stride);
        const height: u32 = @intCast(Size.widget_height);

        var row_index: u32 = 0;
        while (row_index < height) : (row_index += 1) {
            std.debug.assert(row_index < height);

            const source_row = source + row_index * absolute_stride;
            const destination_row = destination_ptr + row_index * row_bytes;

            @memcpy(destination_row[0..row_bytes], source_row[0..row_bytes]);
        }

        std.debug.assert(row_index == height);
    }

    fn invalidate(self: *Widget) void {
        if (self.handle) |handle| {
            const device_context = w32.GetDC(handle);

            if (device_context) |dc| {
                self.paint(dc);
                _ = w32.ReleaseDC(handle, dc);
            }
        }
    }

    fn fire_event(self: *Widget, event_type: WidgetEvent, value: f32) void {
        if (self.callback) |callback| {
            callback(event_type, value, self.callback_context);
        }
    }

    fn toggle_mute(self: *Widget) void {
        std.debug.assert(self.volume.current >= 0.0);
        std.debug.assert(self.volume.current <= 1.0);

        if (self.volume.is_muted) {
            self.volume.is_muted = false;
            self.volume.current = self.volume.before_mute;
            self.invalidate();
            self.fire_event(.mute_toggled, self.volume.current);
        } else {
            self.volume.before_mute = self.volume.current;
            self.volume.is_muted = true;
            self.invalidate();
            self.fire_event(.mute_toggled, 0.0);
        }
    }

    fn is_window_visible(self: *Widget) bool {
        if (self.handle) |handle| {
            return w32.IsWindowVisible(handle) != 0;
        }

        return false;
    }

    pub fn hide(self: *Widget) void {
        if (self.handle) |handle| {
            _ = w32.ShowWindow(handle, w32.SW_HIDE);
        }

        self.interaction.dragging = false;
        self.interaction.focused_region = .none;
    }

    pub fn is_visible(self: *Widget) bool {
        return self.is_window_visible();
    }

    pub fn post_toggle(self: *Widget) void {
        const now = std.time.milliTimestamp();

        const recently_hidden = self.interaction.focus_loss_hide_time > 0 and
            (now - self.interaction.focus_loss_hide_time) < focus_loss_threshold_ms;

        if (recently_hidden) {
            self.interaction.focus_loss_hide_time = 0;
            return;
        }

        if (self.is_window_visible()) {
            self.hide();
        } else {
            self.show();
        }
    }

    pub fn set_callback(self: *Widget, callback: WidgetCallback, context: ?*anyopaque) void {
        self.callback = callback;
        self.callback_context = context;
    }

    pub fn set_default_volume(self: *Widget, volume: f32) void {
        std.debug.assert(volume >= 0.0);
        std.debug.assert(volume <= 1.0);

        self.volume.default = std.math.clamp(volume, 0.0, 1.0);

        std.debug.assert(self.volume.default >= 0.0);
        std.debug.assert(self.volume.default <= 1.0);

        self.invalidate();
    }

    pub fn set_device_info(self: *Widget, name: ?[]const u8, index: u32, count: u32) void {
        self.device.set_name(name);
        self.device.index = index;
        self.device.count = count;

        self.invalidate();
    }

    pub fn set_muted(self: *Widget, muted: bool) void {
        if (muted and !self.volume.is_muted) {
            self.volume.before_mute = self.volume.current;
        }

        self.volume.is_muted = muted;

        self.invalidate();
    }

    pub fn set_title(self: *Widget, title_text: []const u8) void {
        std.debug.assert(title_text.len <= title_len_max);

        const length: u32 = @intCast(@min(title_text.len, title_len_max));

        var index: u32 = 0;
        while (index < length) : (index += 1) {
            std.debug.assert(index < title_len_max);

            self.title[index] = title_text[index];
        }

        std.debug.assert(index == length);

        self.title_len = length;

        self.invalidate();
    }

    pub fn set_volume(self: *Widget, volume: f32) void {
        std.debug.assert(volume >= 0.0);
        std.debug.assert(volume <= 1.0);

        self.volume.current = std.math.clamp(volume, 0.0, 1.0);

        if (volume > 0.0) {
            self.volume.is_muted = false;
        }

        std.debug.assert(self.volume.current >= 0.0);
        std.debug.assert(self.volume.current <= 1.0);

        self.invalidate();
    }

    pub fn show(self: *Widget) void {
        const handle = self.handle orelse return;

        self.interaction.focus_loss_hide_time = 0;

        var cursor: w32.POINT = undefined;
        _ = w32.GetCursorPos(&cursor);

        var monitor_info: w32.MONITORINFO = undefined;
        monitor_info.cbSize = @sizeOf(w32.MONITORINFO);

        const monitor = w32.MonitorFromPoint(cursor, w32.MONITOR_DEFAULTTONEAREST);
        _ = w32.GetMonitorInfoW(monitor, &monitor_info);

        const work = monitor_info.rcWork;
        const screen = monitor_info.rcMonitor;
        const taskbar_height = screen.bottom - work.bottom;

        var x = work.right - Size.widget_width - 12;
        var y: i32 = undefined;

        if (taskbar_height > 0) {
            y = work.bottom - Size.widget_height - 12;
        } else {
            const taskbar_top = work.top - screen.top;

            if (taskbar_top > 0) {
                y = work.top + 12;
            } else {
                y = work.bottom - Size.widget_height - 12;
            }
        }

        if (x < work.left) {
            x = work.left + 12;
        }

        _ = w32.SetWindowPos(
            handle,
            w32.HWND_TOPMOST,
            x,
            y,
            Size.widget_width,
            Size.widget_height,
            .{ .SHOWWINDOW = 1 },
        );

        _ = w32.ShowWindow(handle, w32.SW_SHOW);
        _ = w32.SetForegroundWindow(handle);

        self.invalidate();
    }

    pub fn toggle(self: *Widget) void {
        if (self.is_window_visible()) {
            self.hide();
        } else {
            self.show();
        }
    }

    fn window_proc(
        hwnd: w32.HWND,
        message: u32,
        w_param: usize,
        l_param: isize,
    ) callconv(.c) isize {
        const address: isize = w32.GetWindowLongPtrW(hwnd, w32.GWLP_USERDATA);

        if (address == 0) {
            return w32.DefWindowProcW(hwnd, message, w_param, l_param);
        }

        const self: *Widget = @ptrFromInt(@as(usize, @intCast(address)));

        switch (message) {
            w32.WM_PAINT => return handle_paint(hwnd),
            w32.WM_MOUSEMOVE => return self.handle_mouse_move(hwnd, l_param),
            w32.WM_MOUSELEAVE => return self.handle_mouse_leave(),
            w32.WM_LBUTTONDOWN => return self.handle_left_button_down(hwnd, l_param),
            w32.WM_LBUTTONUP => return self.handle_left_button_up(l_param),
            w32.WM_KEYDOWN => return self.handle_key_down(w_param),
            w32.WM_KILLFOCUS => return self.handle_kill_focus(),
            else => {},
        }

        return w32.DefWindowProcW(hwnd, message, w_param, l_param);
    }

    fn handle_paint(hwnd: w32.HWND) isize {
        var paint_struct: w32.PAINTSTRUCT = undefined;

        _ = w32.BeginPaint(hwnd, &paint_struct);
        _ = w32.EndPaint(hwnd, &paint_struct);

        return 0;
    }

    fn handle_mouse_move(self: *Widget, hwnd: w32.HWND, l_param: isize) isize {
        const x: i32 = @as(i16, @truncate(l_param & 0xFFFF));
        const y: i32 = @as(i16, @truncate((l_param >> 16) & 0xFFFF));

        if (self.interaction.dragging) {
            const new_volume = layout.volume_from_x(x);
            self.volume.current = new_volume;

            if (new_volume > 0.0) {
                self.volume.is_muted = false;
            }

            self.invalidate();
            self.fire_event(.volume_changed, new_volume);
        } else {
            const new_hover = layout.hit_test(x, y);

            if (new_hover != self.interaction.hover_region) {
                self.interaction.hover_region = new_hover;
                self.invalidate();
            }
        }

        var track_mouse_event = w32.TRACKMOUSEEVENT{
            .cbSize = @sizeOf(w32.TRACKMOUSEEVENT),
            .dwFlags = .{ .LEAVE = 1 },
            .hwndTrack = hwnd,
            .dwHoverTime = 0,
        };

        _ = w32.TrackMouseEvent(&track_mouse_event);

        return 0;
    }

    fn handle_mouse_leave(self: *Widget) isize {
        self.interaction.hover_region = .none;
        self.invalidate();

        return 0;
    }

    fn handle_left_button_down(self: *Widget, hwnd: w32.HWND, l_param: isize) isize {
        const x: i32 = @as(i16, @truncate(l_param & 0xFFFF));
        const y: i32 = @as(i16, @truncate((l_param >> 16) & 0xFFFF));

        const region = layout.hit_test(x, y);

        if (region == .slider) {
            self.interaction.dragging = true;
            self.interaction.focused_region = .slider;

            const new_volume = layout.volume_from_x(x);
            self.volume.current = new_volume;

            if (new_volume > 0.0) {
                self.volume.is_muted = false;
            }

            self.invalidate();
            self.fire_event(.volume_changed, new_volume);
            _ = w32.SetCapture(hwnd);
        } else if (region == .button_prev or region == .button_next) {
            self.interaction.focused_region = .device;
            self.invalidate();
        } else {
            self.interaction.focused_region = .none;
            self.invalidate();
        }

        return 0;
    }

    fn handle_left_button_up(self: *Widget, l_param: isize) isize {
        const x: i32 = @as(i16, @truncate(l_param & 0xFFFF));
        const y: i32 = @as(i16, @truncate((l_param >> 16) & 0xFFFF));

        if (self.interaction.dragging) {
            self.interaction.dragging = false;
            _ = w32.ReleaseCapture();
            return 0;
        }

        switch (layout.hit_test(x, y)) {
            .button_prev => {
                self.interaction.focused_region = .device;
                self.fire_event(.device_prev, 0);
            },
            .button_next => {
                self.interaction.focused_region = .device;
                self.fire_event(.device_next, 0);
            },
            .button_set_default => {
                self.fire_event(.set_default, self.volume.current);
            },
            .button_reset_default => {
                self.volume.current = self.volume.default;
                self.volume.is_muted = false;
                self.invalidate();
                self.fire_event(.reset_default, self.volume.default);
            },
            .icon_speaker => {
                self.toggle_mute();
            },
            .button_close => {
                self.hide();
                self.fire_event(.closed, 0);
            },
            else => {},
        }

        return 0;
    }

    fn handle_key_down(self: *Widget, w_param: usize) isize {
        const virtual_key: u32 = @truncate(w_param);

        if (self.interaction.focused_region == .slider) {
            self.handle_slider_key_input(virtual_key);
        } else if (self.interaction.focused_region == .device) {
            self.handle_device_key_input(virtual_key);
        }

        return 0;
    }

    fn handle_slider_key_input(self: *Widget, virtual_key: u32) void {
        if (virtual_key == VK_LEFT or virtual_key == VK_DOWN) {
            self.volume.current = @max(0.0, self.volume.current - 0.01);

            if (self.volume.current == 0.0) {
                self.volume.is_muted = true;
            }

            self.invalidate();
            self.fire_event(.volume_changed, self.volume.current);
        } else if (virtual_key == VK_RIGHT or virtual_key == VK_UP) {
            self.volume.current = @min(1.0, self.volume.current + 0.01);
            self.volume.is_muted = false;
            self.invalidate();
            self.fire_event(.volume_changed, self.volume.current);
        }
    }

    fn handle_device_key_input(self: *Widget, virtual_key: u32) void {
        if (virtual_key == VK_LEFT or virtual_key == VK_UP) {
            self.fire_event(.device_prev, 0);
        } else if (virtual_key == VK_RIGHT or virtual_key == VK_DOWN) {
            self.fire_event(.device_next, 0);
        }
    }

    fn handle_kill_focus(self: *Widget) isize {
        if (self.is_window_visible()) {
            self.interaction.focus_loss_hide_time = std.time.milliTimestamp();
            self.hide();
            self.fire_event(.closed, 0);
        }

        return 0;
    }
};
