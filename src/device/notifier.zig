const std = @import("std");

const w32 = @import("win32").everything;
const wca = @import("wca");

const Mode = @import("../mode.zig").Mode;

pub const DeviceEvent = enum(usize) {
    default_changed = 0,
    added = 1,
    removed = 2,
    state_changed = 3,
};

pub fn DeviceNotifier(comptime mode: Mode) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        client: ?*wca.IMMNotificationClient = null,
        enumerator: ?*wca.IMMDeviceEnumerator = null,
        target_hwnd: w32.HWND,
        message_id: u32,

        var instance: *Self = undefined;

        pub fn init(allocator: std.mem.Allocator, hwnd: w32.HWND, message_id: u32) Self {
            std.debug.assert(message_id >= w32.WM_APP);

            return Self{
                .allocator = allocator,
                .target_hwnd = hwnd,
                .message_id = message_id,
            };
        }

        pub fn deinit(self: *Self) void {
            if (self.enumerator) |enumerator| {
                if (self.client) |client| {
                    _ = enumerator.unregisterEndpointNotificationCallback(@ptrCast(client)) catch {};
                    _ = client.vtable.Release(client);
                }

                _ = enumerator.release();
            }

            self.enumerator = null;
            self.client = null;
        }

        pub fn register(self: *Self) !void {
            instance = self;

            self.enumerator = try wca.IMMDeviceEnumerator.create();
            errdefer {
                _ = self.enumerator.?.release();
                self.enumerator = null;
            }

            self.client = try wca.IMMNotificationClient.create(self.allocator, .{
                .onDefaultDeviceChanged = &on_default_device_changed,
                .onDeviceAdded = &on_device_added,
                .onDeviceRemoved = &on_device_removed,
                .onDeviceStateChanged = &on_device_state_changed,
            });
            errdefer {
                _ = self.client.?.vtable.Release(self.client.?);
                self.client = null;
            }

            try self.enumerator.?.registerEndpointNotificationCallback(@ptrCast(self.client));
        }

        fn post_event(event: DeviceEvent) void {
            std.debug.assert(instance.message_id >= w32.WM_APP);

            _ = w32.PostMessageW(
                instance.target_hwnd,
                instance.message_id,
                @intFromEnum(event),
                0,
            );
        }

        fn on_default_device_changed(
            flow: wca.EDataFlow,
            role: wca.ERole,
            device_id: []const u8,
        ) anyerror!void {
            _ = role;
            _ = device_id;

            if (flow != mode.to_data_flow()) {
                return;
            }

            post_event(.default_changed);
        }

        fn on_device_added(device_id: []const u8) anyerror!void {
            _ = device_id;

            post_event(.added);
        }

        fn on_device_removed(device_id: []const u8) anyerror!void {
            _ = device_id;

            post_event(.removed);
        }

        fn on_device_state_changed(device_id: []const u8, new_state: u32) anyerror!void {
            _ = device_id;
            _ = new_state;

            post_event(.state_changed);
        }
    };
}
