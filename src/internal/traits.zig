//! Internal type trait helpers.

/// Returns whether `T` is one of Zerde's default string slice types.
pub fn isString(comptime T: type) bool {
    return T == []const u8 or T == []u8;
}
