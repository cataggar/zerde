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

test "root exposes codec read deinit validate and schema API" {
    const User = struct {
        id: u8,
        name: []const u8,
    };
    const UserSerde = zerde.Codec(User);

    var reader: std.Io.Reader = .fixed("{\"id\":1,\"name\":\"Grant\"}");
    const user = try UserSerde.read(std.testing.allocator, &reader, zerde.Format.json);
    defer UserSerde.deinit(std.testing.allocator, user);

    try UserSerde.validate(user);
    try std.testing.expectEqualStrings(@typeName(User), UserSerde.schema().type_name);
    try std.testing.expectEqual(@as(u8, 1), user.id);
    try std.testing.expectEqualStrings("Grant", user.name);
}
