//! Internal schema descriptors for reflected Zig types.

/// Minimal schema descriptor used until full schema generation is implemented.
pub const Schema = struct {
    /// Fully qualified Zig type name.
    type_name: []const u8,
};

/// Builds the internal schema descriptor for `T`.
pub fn forType(comptime T: type) Schema {
    return .{ .type_name = @typeName(T) };
}
