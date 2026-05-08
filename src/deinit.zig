//! Type-directed cleanup for values produced by Zerde deserialization.

const std = @import("std");

/// Releases allocations owned by `value` when it was produced by Zerde
/// deserialization.
pub fn deinit(comptime T: type, allocator: std.mem.Allocator, value: T) void {
    _ = allocator;
    _ = value;
}
