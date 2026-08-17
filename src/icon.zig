const std = @import("std");

const umbra = @import("umbra");

const constant = @import("constant.zig");
const Mode = @import("mode.zig").Mode;

const assert = std.debug.assert;

const App = umbra.App;
const IconBuilder = umbra.IconBuilder;
const IconError = umbra.IconError;
const IconHandle = umbra.IconHandle;
const IconPixmap = umbra.IconPixmap;

pub const channel_count: u32 = 4;
pub const pixmap_bytes: u32 = constant.Icon.dimension * constant.Icon.dimension * channel_count;

pub const deafen_argb = to_argb(@embedFile("deafen.rgba"));
pub const mute_argb = to_argb(@embedFile("mute.rgba"));
pub const undeafen_argb = to_argb(@embedFile("undeafen.rgba"));
pub const unmute_argb = to_argb(@embedFile("unmute.rgba"));

comptime {
    assert(channel_count == 4);
    assert(constant.Icon.dimension > 0);
    assert(deafen_argb.len == pixmap_bytes);
    assert(mute_argb.len == pixmap_bytes);
    assert(undeafen_argb.len == pixmap_bytes);
    assert(unmute_argb.len == pixmap_bytes);
}

pub fn IconManagerType(comptime mode: Mode) type {
    return struct {
        const active_argb = switch (mode) {
            .capture => &mute_argb,
            .render => &deafen_argb,
        };

        const inactive_argb = switch (mode) {
            .capture => &unmute_argb,
            .render => &undeafen_argb,
        };

        app: *App,

        pub fn init(app: *App) @This() {
            const result = @This(){
                .app = app,
            };

            return result;
        }

        pub fn configure(self: *@This()) IconError!void {
            _ = try IconBuilder.init(&self.app.icon)
                .pixels("active", pixmap(active_argb))
                .pixels("inactive", pixmap(inactive_argb))
                .stock("active_fallback", .shield)
                .stock("inactive_fallback", .application)
                .done();

            self.update(false);
        }

        pub fn get_icon_for_state(self: *@This(), active: bool) ?IconHandle {
            const manager = &self.app.icon;

            if (manager.get(name_of(active))) |handle| {
                return handle;
            }

            return manager.get(fallback_of(active));
        }

        pub fn update(self: *@This(), active: bool) void {
            const manager = &self.app.icon;

            manager.set_current(name_of(active)) catch {
                manager.set_current(fallback_of(active)) catch {
                    return;
                };
            };
        }
    };
}

fn fallback_of(active: bool) []const u8 {
    const result = if (active) "active_fallback" else "inactive_fallback";

    assert(result.len > 0);

    return result;
}

fn name_of(active: bool) []const u8 {
    const result = if (active) "active" else "inactive";

    assert(result.len > 0);

    return result;
}

fn pixmap(argb: []const u8) IconPixmap {
    assert(argb.len == pixmap_bytes);

    const result = IconPixmap.init(argb, constant.Icon.dimension, constant.Icon.dimension);

    assert(result.is_valid());

    return result;
}

fn to_argb(comptime rgba: []const u8) [rgba.len]u8 {
    @setEvalBranchQuota(rgba.len * 8);

    var result: [rgba.len]u8 = undefined;
    var index: usize = 0;

    while (index + channel_count <= rgba.len) : (index += channel_count) {
        result[index + 0] = rgba[index + 3];
        result[index + 1] = rgba[index + 0];
        result[index + 2] = rgba[index + 1];
        result[index + 3] = rgba[index + 2];
    }

    return result;
}

const testing = std.testing;

test "every embedded pixmap is a complete 32 bit image" {
    try testing.expectEqual(pixmap_bytes, deafen_argb.len);
    try testing.expectEqual(pixmap_bytes, mute_argb.len);
    try testing.expectEqual(pixmap_bytes, undeafen_argb.len);
    try testing.expectEqual(pixmap_bytes, unmute_argb.len);

    try testing.expect(pixmap(&deafen_argb).is_valid());
    try testing.expect(pixmap(&mute_argb).is_valid());
    try testing.expect(pixmap(&undeafen_argb).is_valid());
    try testing.expect(pixmap(&unmute_argb).is_valid());
}

test "to_argb moves the alpha channel in front of the colour channels" {
    const rgba = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8 };
    const argb = to_argb(&rgba);

    try testing.expectEqualSlices(u8, &.{ 4, 1, 2, 3, 8, 5, 6, 7 }, &argb);
}

test "each mode selects the pixmaps its own assets carry" {
    const capture = IconManagerType(.capture);
    const render = IconManagerType(.render);

    try testing.expectEqualSlices(u8, &mute_argb, capture.active_argb);
    try testing.expectEqualSlices(u8, &unmute_argb, capture.inactive_argb);
    try testing.expectEqualSlices(u8, &deafen_argb, render.active_argb);
    try testing.expectEqualSlices(u8, &undeafen_argb, render.inactive_argb);
}

test "an active pixmap is distinguishable from its inactive counterpart" {
    try testing.expect(!std.mem.eql(u8, &mute_argb, &unmute_argb));
    try testing.expect(!std.mem.eql(u8, &deafen_argb, &undeafen_argb));
}

test "every fallback name is distinct from the state name" {
    try testing.expectEqualStrings("active", name_of(true));
    try testing.expectEqualStrings("inactive", name_of(false));
    try testing.expectEqualStrings("active_fallback", fallback_of(true));
    try testing.expectEqualStrings("inactive_fallback", fallback_of(false));
    try testing.expect(!std.mem.eql(u8, name_of(true), fallback_of(true)));
    try testing.expect(!std.mem.eql(u8, name_of(false), fallback_of(false)));
}
