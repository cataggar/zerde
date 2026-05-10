const std = @import("std");
const zerde = @import("zerde");

const User = struct {
    user_id: u64,
    display_name: []const u8,
    active: bool = true,
    tags: []const []const u8,

    pub const zerde = .{
        .rename_all = .camel_case,
        .fields = .{
            .display_name = .{ .rename = "name" },
        },
    };
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const input =
        \\{
        \\  "userId": 42,
        \\  "name": "Ada Lovelace",
        \\  "tags": ["zig", "serde", "json"]
        \\}
    ;

    const user = try zerde.json.readSlice(User, allocator, input);
    defer zerde.deinit(User, allocator, user);

    const output = try zerde.json.writeAllocWithOptions(allocator, user, .{ .pretty = true, .indent = 2 });
    defer allocator.free(output);

    std.debug.print("user id: {d}\n", .{user.user_id});
    std.debug.print("name: {s}\n", .{user.display_name});
    std.debug.print("json:\n{s}\n", .{output});
}
