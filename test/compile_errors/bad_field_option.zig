const zerde = @import("zerde");

const User = struct {
    id: u64,

    pub const zerde = .{
        .fields = .{
            .id = .{ .skip_serialize = true },
        },
    };
};

test "metadata rejects unknown field option names" {
    _ = zerde.Codec(User);
}
