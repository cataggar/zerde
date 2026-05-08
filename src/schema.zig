pub const Schema = struct {
    type_name: []const u8,
};

pub fn forType(comptime T: type) Schema {
    return .{ .type_name = @typeName(T) };
}
