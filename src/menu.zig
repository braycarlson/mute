const std = @import("std");

const umbra = @import("umbra");

const assert = std.debug.assert;

const CapacityError = umbra.CapacityError;

pub const Command = enum(u32) {
    exit = 1001,
    volume = 1002,
    _,
};

pub fn fill(comptime App: type, menu: *App.Menu) CapacityError!void {
    menu.clear();

    assert(menu.is_empty());

    _ = try App.MenuBuilder.init(menu)
        .action(@backingInt(Command.volume), "Volume")
        .separator()
        .action(@backingInt(Command.exit), "Exit")
        .done();

    assert(!menu.is_empty());
}

const testing = std.testing;

const Fakes = @import("fakes.zig");

test fill {
    var app: Fakes.App = undefined;

    try app.init(.{ .name = "menu" });
    defer app.deinit();

    try fill(Fakes.App, &app.menu);
    try fill(Fakes.App, &app.menu);

    const volume = app.menu.get_item(@backingInt(Command.volume)) orelse return error.ItemMissing;
    const exit = app.menu.get_item(@backingInt(Command.exit)) orelse return error.ItemMissing;

    try testing.expectEqual(@as(u8, 3), app.menu.count);
    try testing.expectEqualStrings("Volume", volume.get_label());
    try testing.expectEqualStrings("Exit", exit.get_label());
}
