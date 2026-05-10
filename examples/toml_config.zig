const std = @import("std");
const zerde = @import("zerde");

const Server = struct {
    host: []const u8,
    port: u16,
};

const Feature = struct {
    name: []const u8,
    enabled: bool = true,
};

const Config = struct {
    app_name: []const u8,
    started_at: zerde.OffsetDateTime,
    server: Server,
    features: []const Feature,
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const input =
        \\app_name = "zerde-demo"
        \\started_at = 2026-05-09T12:30:00Z
        \\
        \\[server]
        \\host = "127.0.0.1"
        \\port = 8080
        \\
        \\[[features]]
        \\name = "json"
        \\enabled = true
        \\
        \\[[features]]
        \\name = "msgpack"
    ;

    const config = try zerde.toml.readSlice(Config, allocator, input);
    defer zerde.deinit(Config, allocator, config);

    std.debug.print("{s} listens on {s}:{d}\n", .{
        config.app_name,
        config.server.host,
        config.server.port,
    });
    for (config.features) |feature| {
        std.debug.print("feature {s}: enabled={any}\n", .{ feature.name, feature.enabled });
    }

    const roundtrip = try zerde.toml.writeAlloc(allocator, config);
    defer allocator.free(roundtrip);
    std.debug.print("roundtrip TOML:\n{s}\n", .{roundtrip});
}
