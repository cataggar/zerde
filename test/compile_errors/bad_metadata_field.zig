const zerde = @import("zerde");

const User = struct {
    id: u64,

    pub const zerde = .{
        .fields = .{
            .name = .{ .rename = "username" },
        },
    };
};

test "metadata rejects unknown field names" {
    _ = zerde.Codec(User);
}
