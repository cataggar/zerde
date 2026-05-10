const std = @import("std");
const zerde = @import("zerde");

const ExternalEvent = union(enum) {
    login: struct { user: []const u8 },
    logout,
};

const AdjacentEvent = union(enum) {
    login: struct { user: []const u8 },
    logout,

    pub const zerde = .{ .union_repr = .adjacent };
};

const InternalEvent = union(enum) {
    login: struct { user: []const u8 },
    logout,

    pub const zerde = .{ .union_repr = .internal };
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    const external = try zerde.json.writeAlloc(allocator, ExternalEvent{ .login = .{ .user = "Ada" } });
    defer allocator.free(external);

    const adjacent = try zerde.json.writeAlloc(allocator, AdjacentEvent{ .login = .{ .user = "Ada" } });
    defer allocator.free(adjacent);

    const internal = try zerde.json.writeAlloc(allocator, InternalEvent{ .login = .{ .user = "Ada" } });
    defer allocator.free(internal);

    const zon_logout = try zerde.zon.writeAlloc(allocator, AdjacentEvent.logout);
    defer allocator.free(zon_logout);

    std.debug.print("external JSON: {s}\n", .{external});
    std.debug.print("adjacent JSON: {s}\n", .{adjacent});
    std.debug.print("internal JSON: {s}\n", .{internal});
    std.debug.print("adjacent ZON logout: {s}\n", .{zon_logout});
}
