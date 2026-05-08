const std = @import("std");

pub fn deserialize(comptime T: type, allocator: std.mem.Allocator, decoder: anytype) !T {
    _ = allocator;
    _ = decoder;
    return error.Unsupported;
}
