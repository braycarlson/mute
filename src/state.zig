const std = @import("std");

pub const State = enum(u8) {
    active = 0,
    inactive = 1,

    pub fn is_active(state: State) bool {
        return state == .active;
    }

    pub fn to_string(state: State) []const u8 {
        return switch (state) {
            .active => "active",
            .inactive => "inactive",
        };
    }
};

const testing = std.testing;

test State {
    try testing.expect(State.active.is_active());
    try testing.expect(!State.inactive.is_active());
    try testing.expectEqualStrings("active", State.active.to_string());
    try testing.expectEqualStrings("inactive", State.inactive.to_string());
}
