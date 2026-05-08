pub fn isString(comptime T: type) bool {
    return T == []const u8 or T == []u8;
}
