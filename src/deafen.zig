const entry = @import("entry.zig");

pub fn main() u8 {
    return entry.run(.render);
}
