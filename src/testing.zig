//! Public API integration tests for the root Zerde module.

const std = @import("std");
const zerde = @import("zerde.zig");

test "root exposes codec write API" {
    const User = struct {
        id: u8,
        name: []const u8,
    };

    var buffer: [128]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);

    try zerde.Codec(User).write(&writer, .{ .id = 1, .name = "Grant" }, zerde.Format.json);

    try std.testing.expectEqualStrings("{\"id\":1,\"name\":\"Grant\"}", writer.buffered());
}
