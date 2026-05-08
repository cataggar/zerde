//! Type-directed cleanup for values produced by Zerde deserialization.

const std = @import("std");

/// Releases allocations owned by `value` when it was produced by Zerde
/// deserialization.
pub fn deinit(comptime T: type, allocator: std.mem.Allocator, value: T) void {
    switch (@typeInfo(T)) {
        .bool, .int, .comptime_int, .float, .comptime_float, .null, .@"enum", .enum_literal => {},
        .optional => |optional_info| {
            if (value) |child_value| deinit(optional_info.child, allocator, child_value);
        },
        .array => |array_info| {
            for (value) |item| deinit(array_info.child, allocator, item);
        },
        .pointer => |pointer_info| switch (pointer_info.size) {
            .slice => {
                if (pointer_info.child != u8) {
                    for (value) |item| deinit(pointer_info.child, allocator, item);
                }
                allocator.free(value);
            },
            else => {},
        },
        .@"struct" => |struct_info| {
            inline for (struct_info.fields) |field| {
                if (!field.is_comptime) deinit(field.type, allocator, @field(value, field.name));
            }
        },
        else => {},
    }
}
