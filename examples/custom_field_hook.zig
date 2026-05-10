const std = @import("std");
const zerde = @import("zerde");

const BoolAsYesNo = struct {
    pub fn write(value: bool, encoder: anytype) !void {
        try encoder.emitString(if (value) "yes" else "no");
    }

    pub fn read(comptime T: type, allocator: std.mem.Allocator, decoder: anytype) !T {
        const value = try decoder.readString(allocator);
        defer allocator.free(value);

        if (std.ascii.eqlIgnoreCase(value, "yes")) return true;
        if (std.ascii.eqlIgnoreCase(value, "no")) return false;
        return error.InvalidValue;
    }
};

const Account = struct {
    username: []const u8,
    active: bool,

    pub const zerde = .{
        .fields = .{
            .active = .{ .with = BoolAsYesNo },
        },
    };
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const account = Account{ .username = "Ada", .active = true };
    const json = try zerde.json.writeAlloc(allocator, account);
    defer allocator.free(json);
    std.debug.print("custom hook JSON: {s}\n", .{json});

    const parsed = try zerde.json.readSlice(Account, allocator, "{\"username\":\"Grace\",\"active\":\"No\"}");
    defer zerde.deinit(Account, allocator, parsed);
    std.debug.print("parsed {s}: active={any}\n", .{ parsed.username, parsed.active });
}
