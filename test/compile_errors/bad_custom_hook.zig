const zerde = @import("zerde");

const BadHook = struct {
    pub fn write(value: u64, encoder: anytype) !void {
        try encoder.emitInt(value);
    }
};

const User = struct {
    id: u64,

    pub const zerde = .{
        .fields = .{
            .id = .{ .with = BadHook },
        },
    };
};

test "metadata rejects custom hooks with missing methods" {
    _ = zerde.Codec(User);
}
