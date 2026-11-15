const std = @import("std");

const umbra = @import("umbra");

const Mode = @import("mode.zig").Mode;
const State = @import("state.zig").State;

const assert = std.debug.assert;

const CapacityError = umbra.CapacityError;
const Pixmap = umbra.Icon.Pixmap;
const PlatformError = umbra.PlatformError;
const RequestError = umbra.RequestError;

const Pixmaps = struct {
    active: Pixmap,
    inactive: Pixmap,
};

const dimension: u32 = 32;
const deafen = Pixmap.from_rgba(@embedFile("deafen.rgba"), dimension);
const mute = Pixmap.from_rgba(@embedFile("mute.rgba"), dimension);
const undeafen = Pixmap.from_rgba(@embedFile("undeafen.rgba"), dimension);
const unmute = Pixmap.from_rgba(@embedFile("unmute.rgba"), dimension);

comptime {
    assert(deafen.height == dimension);
    assert(mute.height == dimension);
    assert(undeafen.height == dimension);
    assert(unmute.height == dimension);
}

pub fn register(
    comptime App: type,
    icons: *App.IconSet,
    mode: Mode,
) (CapacityError || RequestError)!void {
    assert(icons.is_empty());

    const pixmaps = pixmaps_of(mode);

    _ = try App.IconBuilder.init(icons)
        .pixels(State.active.to_string(), pixmaps.active)
        .pixels(State.inactive.to_string(), pixmaps.inactive)
        .done();

    assert(!icons.is_empty());
}

pub fn show(
    comptime App: type,
    icons: *App.IconSet,
    state: State,
) (PlatformError || RequestError)!void {
    const name = state.to_string();

    assert(icons.get_source(name) != null);

    try icons.set_current(name);
}

fn pixmaps_of(mode: Mode) Pixmaps {
    return switch (mode) {
        .capture => .{ .active = mute, .inactive = unmute },
        .render => .{ .active = deafen, .inactive = undeafen },
    };
}

const testing = std.testing;

const Fakes = @import("fakes.zig");

test register {
    var app: Fakes.App = undefined;

    try app.init(.{ .name = "icon" });
    defer app.deinit();

    try register(Fakes.App, &app.icons, .capture);
    try show(Fakes.App, &app.icons, .inactive);

    try testing.expectEqualStrings("inactive", app.icons.get_current_name().?);
}

test show {
    var app: Fakes.App = undefined;

    try app.init(.{ .name = "icon" });
    defer app.deinit();

    try register(Fakes.App, &app.icons, .render);
    try show(Fakes.App, &app.icons, .active);

    try testing.expectEqualStrings("active", app.icons.get_current_name().?);

    try show(Fakes.App, &app.icons, .inactive);

    try testing.expectEqualStrings("inactive", app.icons.get_current_name().?);
}

test "every embedded pixmap is a complete 32 bit image" {
    const pixmaps = [_]Pixmap{ deafen, mute, undeafen, unmute };

    for (pixmaps) |pixmap| {
        try testing.expectEqual(dimension * dimension * 4, pixmap.argb.len);
        try testing.expect(pixmap.is_valid());
    }
}

test "each mode selects the pixmaps its own assets carry" {
    try testing.expectEqualSlices(u8, mute.argb, pixmaps_of(.capture).active.argb);
    try testing.expectEqualSlices(u8, unmute.argb, pixmaps_of(.capture).inactive.argb);
    try testing.expectEqualSlices(u8, deafen.argb, pixmaps_of(.render).active.argb);
    try testing.expectEqualSlices(u8, undeafen.argb, pixmaps_of(.render).inactive.argb);
}

test "an active pixmap is distinguishable from its inactive counterpart" {
    try testing.expect(!std.mem.eql(u8, mute.argb, unmute.argb));
    try testing.expect(!std.mem.eql(u8, deafen.argb, undeafen.argb));
}
