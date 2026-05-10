const std = @import("std");
const zerde = @import("zerde");

const Release = struct {
    name: []const u8,
    version: []const u8,
    stable: bool,
    downloads: u64,
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const value = Release{
        .name = "zerde",
        .version = "0.1.0",
        .stable = false,
        .downloads = 128,
    };

    const ReleaseCodec = zerde.Codec(Release);

    var json_buffer: [1024]u8 = undefined;
    var json_writer: std.Io.Writer = .fixed(&json_buffer);
    try ReleaseCodec.write(&json_writer, value, .json);

    var zon_buffer: [1024]u8 = undefined;
    var zon_writer: std.Io.Writer = .fixed(&zon_buffer);
    try ReleaseCodec.write(&zon_writer, value, .zon);

    var msgpack_buffer: [1024]u8 = undefined;
    var msgpack_writer: std.Io.Writer = .fixed(&msgpack_buffer);
    try ReleaseCodec.write(&msgpack_writer, value, .msgpack);
    const msgpack_base64 = try zerde.base64.encodeAlloc(allocator, msgpack_writer.buffered());
    defer allocator.free(msgpack_base64);

    std.debug.print("json: {s}\n", .{json_writer.buffered()});
    std.debug.print("zon: {s}\n", .{zon_writer.buffered()});
    std.debug.print("msgpack base64: {s}\n", .{msgpack_base64});
}
