const std = @import("std");
const zerde = @import("zerde");

const ApiUser = struct {
    user_id: u64,
    display_name: []const u8,
    password_hash: []const u8 = "redacted",
    cached_score: u16 = 0,
    token: []const u8 = "server-generated",
    active: bool = true,

    pub const zerde = .{
        .rename_all = .camel_case,
        .deny_unknown_fields = true,
        .fields = .{
            .display_name = .{ .rename = "name" },
            .password_hash = .{ .skip_writing = true },
            .cached_score = .{ .skip = true },
            .token = .{ .skip_reading = true },
        },
    };
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const user = ApiUser{
        .user_id = 42,
        .display_name = "Ada",
        .password_hash = "not-on-the-wire",
        .cached_score = 9001,
        .token = "write-only-token",
    };

    const json = try zerde.json.writeAllocWithOptions(allocator, user, .{ .pretty = true });
    defer allocator.free(json);
    std.debug.print("metadata JSON:\n{s}\n", .{json});

    const input =
        \\{
        \\  "userId": 7,
        \\  "name": "Grace",
        \\  "token": "ignored-client-token",
        \\  "active": false
        \\}
    ;
    const parsed = try zerde.json.readSlice(ApiUser, allocator, input);
    defer zerde.deinit(ApiUser, allocator, parsed);

    std.debug.print("parsed id={d} name={s} token={s} active={any}\n", .{
        parsed.user_id,
        parsed.display_name,
        parsed.token,
        parsed.active,
    });
}
