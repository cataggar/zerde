const std = @import("std");
const zerde = @import("zerde");

const Bytes = zerde.Bytes;

const Blob = struct {
    name: []const u8,
    payload: []const u8,
    checksum: [4]u8,
    wrapped: Bytes,

    pub const zerde = .{
        .fields = .{
            .payload = .{ .bytes = true },
            .checksum = .{ .bytes = true },
        },
    };
};

fn printBase64(allocator: std.mem.Allocator, label: []const u8, bytes: []const u8) !void {
    const encoded = try zerde.base64.encodeAlloc(allocator, bytes);
    defer allocator.free(encoded);
    std.debug.print("{s}: {s}\n", .{ label, encoded });
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const payload = [_]u8{ 0, 1, 2, 3, 4, 5 };
    const wrapped = [_]u8{ 'z', 'e', 'r', 'd', 'e' };

    const blob = Blob{
        .name = "packet",
        .payload = payload[0..],
        .checksum = .{ 0xde, 0xad, 0xbe, 0xef },
        .wrapped = .{ .value = wrapped[0..] },
    };

    const json = try zerde.json.writeAlloc(allocator, blob);
    defer allocator.free(json);
    std.debug.print("json bytes as base64 strings: {s}\n", .{json});

    const parsed = try zerde.json.readSlice(Blob, allocator, json);
    defer zerde.deinit(Blob, allocator, parsed);
    try printBase64(allocator, "parsed payload", parsed.payload);
    try printBase64(allocator, "parsed checksum", parsed.checksum[0..]);
    try printBase64(allocator, "parsed wrapped", parsed.wrapped.slice());

    const msgpack = try zerde.msgpack.writeAlloc(allocator, blob);
    defer allocator.free(msgpack);
    try printBase64(allocator, "messagepack", msgpack);
}
