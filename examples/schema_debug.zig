const std = @import("std");
const zerde = @import("zerde");

const Role = enum { admin, editor, viewer };

const Profile = struct {
    display_name: []const u8,
    avatar: []const u8,

    pub const zerde = .{
        .rename_all = .camel_case,
        .fields = .{
            .avatar = .{ .bytes = true },
        },
    };
};

const Account = struct {
    account_id: u64,
    profile: Profile,
    roles: []const Role,
    nickname: ?[]const u8,
    enabled: bool = true,
    session_token: []const u8 = "server-generated",
    cached_score: u16 = 0,

    pub const zerde = .{
        .rename_all = .camel_case,
        .fields = .{
            .session_token = .{ .skip_reading = true },
            .cached_score = .{ .skip = true },
        },
    };
};

const AuditEvent = union(enum) {
    login: struct { account_id: u64, ip: []const u8 },
    role_changed: struct { account_id: u64, role: Role },
    heartbeat,

    pub const zerde = .{ .union_repr = .adjacent };
};

fn printSchema(writer: *std.Io.Writer, comptime T: type, title: []const u8) !void {
    const schema = zerde.Codec(T).schema();

    try writer.print("== {s} ==\n", .{title});
    try writer.writeAll("human:\n");
    try zerde.schema.write(writer, schema, .human);
    try writer.writeAll("json:\n");
    try zerde.schema.write(writer, schema, .json);
    try writer.writeByte('\n');
    try writer.writeAll("toml:\n");
    try zerde.schema.write(writer, schema, .toml);
    try writer.writeByte('\n');
    try writer.writeAll("msgpack base64:\n");

    var msgpack_buffer: [16384]u8 = undefined;
    var msgpack_writer: std.Io.Writer = .fixed(&msgpack_buffer);
    try zerde.schema.write(&msgpack_writer, schema, .msgpack);

    var base64_buffer: [32768]u8 = undefined;
    var base64_writer: std.Io.Writer = .fixed(&base64_buffer);
    try zerde.base64.writeEncoded(&base64_writer, msgpack_writer.buffered());
    try writer.print("{s}\n", .{base64_writer.buffered()});

    try writer.writeByte('\n');
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const writer = &stdout_writer.interface;

    try printSchema(writer, Account, "metadata struct with nested fields");
    try printSchema(writer, [3]Role, "fixed array of enums");
    try printSchema(writer, []const Account, "slice of structs");
    try printSchema(writer, std.StringHashMap(Account), "std map container");
    try printSchema(writer, AuditEvent, "adjacently tagged union");

    try writer.flush();
}
