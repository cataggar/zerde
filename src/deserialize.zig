//! Generic type-directed deserialization traversal.

const std = @import("std");

/// Deserializes a value of type `T` by walking `T` at comptime and calling
/// methods on `decoder`'s structural protocol.
pub fn deserialize(comptime T: type, allocator: std.mem.Allocator, decoder: anytype) !T {
    _ = allocator;
    _ = decoder;
    return error.Unsupported;
}
