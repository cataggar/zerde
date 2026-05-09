const zerde = @import("zerde");

const Event = union(enum) {
    started: struct {
        kind: []const u8,

        pub const zerde = .{
            .fields = .{
                .kind = .{ .rename = "tag" },
            },
        };
    },

    pub const zerde = .{ .union_repr = .internal };
};

test "metadata rejects internal union tag field collision" {
    _ = zerde.Codec(Event);
}
