const std = @import("std");

pub fn deinit(comptime T: type, allocator: std.mem.Allocator, value: T) void {
    _ = allocator;
    _ = value;
}
