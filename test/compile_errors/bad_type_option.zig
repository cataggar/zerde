const zerde = @import("zerde");

const User = struct {
    id: u64,

    pub const zerde = .{
        .renameAll = .camel_case,
    };
};

test "metadata rejects unknown type option names" {
    _ = zerde.Codec(User);
}
