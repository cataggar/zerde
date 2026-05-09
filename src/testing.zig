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

test "readme quick start json allocator helpers" {
    const User = struct {
        user_id: u64,
        display_name: []const u8,
        active: bool = true,
    };

    const user = User{
        .user_id = 1,
        .display_name = "Ada",
    };

    const json = try zerde.json.writeAlloc(std.testing.allocator, user);
    defer std.testing.allocator.free(json);

    try std.testing.expectEqualStrings("{\"user_id\":1,\"display_name\":\"Ada\",\"active\":true}", json);

    const parsed = try zerde.json.readSlice(User, std.testing.allocator, json);
    defer zerde.deinit(User, std.testing.allocator, parsed);

    try std.testing.expectEqual(@as(u64, 1), parsed.user_id);
    try std.testing.expectEqualStrings("Ada", parsed.display_name);
    try std.testing.expect(parsed.active);
}

test "readme codec namespace and write options" {
    const User = struct {
        user_id: u16,
        display_name: []const u8,
        active: bool = true,
    };
    const UserCodec = zerde.Codec(User);

    const user = User{
        .user_id = 0x1234,
        .display_name = "Ada",
    };

    var json_buffer: [256]u8 = undefined;
    var json_writer: std.Io.Writer = .fixed(&json_buffer);
    try UserCodec.write(&json_writer, user, .json);
    try std.testing.expectEqualStrings("{\"user_id\":4660,\"display_name\":\"Ada\",\"active\":true}", json_writer.buffered());

    var reader: std.Io.Reader = .fixed(json_writer.buffered());
    const parsed = try UserCodec.read(std.testing.allocator, &reader, .json);
    defer UserCodec.deinit(std.testing.allocator, parsed);

    try UserCodec.validate(parsed);
    const schema = comptime UserCodec.schema();
    try std.testing.expectEqualStrings(@typeName(User), schema.type_name);

    var pretty_buffer: [256]u8 = undefined;
    var pretty_writer: std.Io.Writer = .fixed(&pretty_buffer);
    try UserCodec.writeWithOptions(std.testing.allocator, &pretty_writer, user, .json, .{
        .pretty = true,
        .indent = 2,
    });
    try std.testing.expectEqualStrings(
        \\{
        \\  "user_id": 4660,
        \\  "display_name": "Ada",
        \\  "active": true
        \\}
    , pretty_writer.buffered());

    var binary_buffer: [128]u8 = undefined;
    var binary_writer: std.Io.Writer = .fixed(&binary_buffer);
    try UserCodec.writeWithOptions(std.testing.allocator, &binary_writer, user, .binary, .{
        .endian = .big,
    });

    var binary_reader: std.Io.Reader = .fixed(binary_writer.buffered());
    const binary_parsed = try UserCodec.readWithOptions(std.testing.allocator, &binary_reader, .binary, .{
        .endian = .big,
    });
    defer UserCodec.deinit(std.testing.allocator, binary_parsed);

    try std.testing.expectEqual(user.user_id, binary_parsed.user_id);
    try std.testing.expectEqualStrings(user.display_name, binary_parsed.display_name);
    try std.testing.expectEqual(user.active, binary_parsed.active);
}

test "readme metadata example applies field rules" {
    const ApiUser = struct {
        user_id: u64,
        display_name: []const u8,
        password_hash: []const u8 = "redacted",

        pub const zerde = .{
            .rename_all = .camel_case,
            .deny_unknown_fields = true,
            .fields = .{
                .display_name = .{ .rename = "name" },
                .password_hash = .{ .skip_writing = true },
            },
        };
    };

    const encoded = try zerde.json.writeAlloc(std.testing.allocator, ApiUser{
        .user_id = 1,
        .display_name = "Ada",
        .password_hash = "secret",
    });
    defer std.testing.allocator.free(encoded);

    try std.testing.expectEqualStrings("{\"userId\":1,\"name\":\"Ada\"}", encoded);

    const parsed = try zerde.json.readSlice(ApiUser, std.testing.allocator, encoded);
    defer zerde.deinit(ApiUser, std.testing.allocator, parsed);

    try std.testing.expectEqual(@as(u64, 1), parsed.user_id);
    try std.testing.expectEqualStrings("Ada", parsed.display_name);
    try std.testing.expectEqualStrings("redacted", parsed.password_hash);
    try std.testing.expectError(error.UnknownField, zerde.json.readSlice(ApiUser, std.testing.allocator, "{\"userId\":1,\"name\":\"Ada\",\"extra\":true}"));
}

test "readme tagged union representations" {
    const ExternalShape = union(enum) {
        circle: struct { radius: u8 },
        point,
    };

    const AdjacentShape = union(enum) {
        circle: struct { radius: u8 },
        point,

        pub const zerde = .{ .union_repr = .adjacent };
    };

    const InternalShape = union(enum) {
        circle: struct { radius: u8 },
        point,

        pub const zerde = .{ .union_repr = .internal };
    };

    const external = try zerde.json.writeAlloc(std.testing.allocator, ExternalShape{ .circle = .{ .radius = 10 } });
    defer std.testing.allocator.free(external);
    try std.testing.expectEqualStrings("{\"circle\":{\"radius\":10}}", external);

    const adjacent = try zerde.json.writeAlloc(std.testing.allocator, AdjacentShape{ .circle = .{ .radius = 10 } });
    defer std.testing.allocator.free(adjacent);
    try std.testing.expectEqualStrings("{\"tag\":\"circle\",\"value\":{\"radius\":10}}", adjacent);

    const internal = try zerde.json.writeAlloc(std.testing.allocator, InternalShape{ .circle = .{ .radius = 10 } });
    defer std.testing.allocator.free(internal);
    try std.testing.expectEqualStrings("{\"tag\":\"circle\",\"radius\":10}", internal);
}

test "readme raw bytes examples encode base64 in text formats" {
    const Blob = struct {
        name: []const u8,
        data: []const u8,

        pub const zerde = .{
            .fields = .{
                .data = .{ .bytes = true },
            },
        };
    };

    const WrappedBlob = struct {
        name: []const u8,
        data: zerde.Bytes,
    };

    const raw = [_]u8{ 0, 1, 2, 3 };

    const blob_json = try zerde.json.writeAlloc(std.testing.allocator, Blob{ .name = "raw", .data = raw[0..] });
    defer std.testing.allocator.free(blob_json);
    try std.testing.expectEqualStrings("{\"name\":\"raw\",\"data\":\"AAECAw==\"}", blob_json);

    const parsed_blob = try zerde.json.readSlice(Blob, std.testing.allocator, blob_json);
    defer zerde.deinit(Blob, std.testing.allocator, parsed_blob);
    try std.testing.expectEqualSlices(u8, raw[0..], parsed_blob.data);

    const wrapped_toml = try zerde.toml.writeAlloc(std.testing.allocator, WrappedBlob{
        .name = "raw",
        .data = .{ .value = raw[0..] },
    });
    defer std.testing.allocator.free(wrapped_toml);
    try std.testing.expectEqualStrings(
        \\name = "raw"
        \\data = "AAECAw=="
    , wrapped_toml);
}

test "readme custom field hook accepts yes no in any case" {
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

    const encoded = try zerde.json.writeAlloc(std.testing.allocator, Account{ .username = "Ada", .active = true });
    defer std.testing.allocator.free(encoded);
    try std.testing.expectEqualStrings("{\"username\":\"Ada\",\"active\":\"yes\"}", encoded);

    const yes = try zerde.json.readSlice(Account, std.testing.allocator, "{\"username\":\"Ada\",\"active\":\"YES\"}");
    defer zerde.deinit(Account, std.testing.allocator, yes);
    try std.testing.expect(yes.active);

    const no = try zerde.json.readSlice(Account, std.testing.allocator, "{\"username\":\"Ada\",\"active\":\"No\"}");
    defer zerde.deinit(Account, std.testing.allocator, no);
    try std.testing.expect(!no.active);
}

test "readme native hooks override reflected type shape" {
    const UserId = struct {
        value: u64,

        pub fn zerdeWrite(self: @This(), encoder: anytype) !void {
            try encoder.emitInt(self.value);
        }

        pub fn zerdeRead(allocator: std.mem.Allocator, decoder: anytype) !@This() {
            _ = allocator;
            return .{ .value = try decoder.readInt(u64) };
        }
    };

    const User = struct {
        id: UserId,
        name: []const u8,
    };

    const encoded = try zerde.json.writeAlloc(std.testing.allocator, User{
        .id = .{ .value = 42 },
        .name = "Ada",
    });
    defer std.testing.allocator.free(encoded);
    try std.testing.expectEqualStrings("{\"id\":42,\"name\":\"Ada\"}", encoded);

    const parsed = try zerde.json.readSlice(User, std.testing.allocator, encoded);
    defer zerde.deinit(User, std.testing.allocator, parsed);
    try std.testing.expectEqual(@as(u64, 42), parsed.id.value);
    try std.testing.expectEqualStrings("Ada", parsed.name);
}
