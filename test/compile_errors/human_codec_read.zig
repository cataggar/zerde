const std = @import("std");
const zerde = @import("zerde");

const User = struct {
    id: u64,
};

test "codec rejects human reads at compile time" {
    var reader: std.Io.Reader = .fixed("{}");
    _ = try zerde.Codec(User).read(std.testing.allocator, &reader, .human);
}
