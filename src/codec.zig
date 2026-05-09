//! Type-specialized codec API.

const std = @import("std");

const meta = @import("meta.zig");
const rename = @import("rename.zig");
const schema_mod = @import("schema.zig");
const binary = @import("binary.zig");
const csv = @import("csv.zig");
const human = @import("human.zig");
const json = @import("json.zig");
const msgpack = @import("msgpack.zig");
const toml = @import("toml.zig");
const zon = @import("zon.zig");
const deinitValue = @import("deinit.zig").deinit;

/// Formats supported by the simple codec dispatch API.
pub const Format = enum {
    json,
    toml,
    msgpack,
    zon,
    binary,
    csv,
    human,
};

/// Returns a type-specific namespace for serialization, deserialization,
/// validation, schema generation, and cleanup.
pub fn Codec(comptime T: type) type {
    comptime {
        meta.validate(T, meta.optionsFor(T));
        schema_mod.validateType(T);
    }

    return struct {
        /// The Zig type handled by this codec namespace.
        pub const Type = T;
        /// Normalized metadata options for `Type`.
        pub const options = meta.optionsFor(T);

        /// Serializes `value` in the selected comptime-known `format`.
        pub fn write(writer: *std.Io.Writer, value: T, comptime format: Format) !void {
            switch (format) {
                .json => try json.write(writer, value),
                .toml => try toml.write(writer, value),
                .msgpack => try msgpack.write(writer, value),
                .zon => try zon.write(writer, value),
                .binary => try binary.write(writer, value),
                .csv => try csv.write(writer, value),
                .human => try human.write(writer, value),
            }
        }

        /// Deserializes a `Type` value from `reader` in the selected format.
        pub fn read(allocator: std.mem.Allocator, reader: *std.Io.Reader, comptime format: Format) !T {
            return switch (format) {
                .json => try json.read(T, allocator, reader),
                .toml => try toml.read(T, allocator, reader),
                .msgpack => try msgpack.read(T, allocator, reader),
                .zon => try zon.read(T, allocator, reader),
                .binary => try binary.read(T, allocator, reader),
                .csv => try csv.read(T, allocator, reader),
                .human => @compileError("human format is write-only"),
            };
        }

        /// Serializes `value` in the selected format with explicit format options.
        pub fn writeWithOptions(
            allocator: std.mem.Allocator,
            writer: *std.Io.Writer,
            value: T,
            comptime format: Format,
            format_options: anytype,
        ) !void {
            switch (format) {
                .json => try json.writeWithOptions(writer, value, coerceOptions(json.WriteOptions, format_options)),
                .toml => try toml.writeWithOptions(allocator, writer, value, coerceOptions(toml.WriteOptions, format_options)),
                .msgpack => try msgpack.writeWithOptions(writer, value, coerceOptions(msgpack.WriteOptions, format_options)),
                .zon => try zon.writeWithOptions(writer, value, coerceOptions(zon.WriteOptions, format_options)),
                .binary => try binary.writeWithOptions(writer, value, coerceOptions(binary.Options, format_options)),
                .csv => try csv.writeWithOptions(writer, value, coerceOptions(csv.Options, format_options)),
                .human => try human.writeWithOptions(writer, value, coerceOptions(human.WriteOptions, format_options)),
            }
        }

        /// Deserializes a `Type` value with explicit format options where supported.
        pub fn readWithOptions(
            allocator: std.mem.Allocator,
            reader: *std.Io.Reader,
            comptime format: Format,
            format_options: anytype,
        ) !T {
            return switch (format) {
                .binary => try binary.readWithOptions(T, allocator, reader, coerceOptions(binary.Options, format_options)),
                .csv => try csv.readWithOptions(T, allocator, reader, coerceOptions(csv.Options, format_options)),
                .json => @compileError("json read has no format options"),
                .toml => @compileError("toml read has no format options"),
                .msgpack => @compileError("msgpack read has no format options"),
                .zon => @compileError("zon read has no format options"),
                .human => @compileError("human format is write-only"),
            };
        }

        /// Validates a value against codec-level rules.
        pub fn validate(value: T) !void {
            _ = value;
            comptime schema_mod.validateType(T);
        }

        /// Returns the internal schema descriptor for `Type`.
        pub fn schema() schema_mod.Schema {
            return schema_mod.forType(T);
        }

        /// Cleans up allocations owned by a value produced by Zerde deserialization.
        pub fn deinit(allocator: std.mem.Allocator, value: T) void {
            deinitValue(T, allocator, value);
        }
    };
}

fn coerceOptions(comptime Options: type, options: anytype) Options {
    const Actual = @TypeOf(options);
    if (@typeInfo(Actual) != .@"struct") @compileError("format options must be a struct literal");

    var result = Options{};
    inline for (@typeInfo(Actual).@"struct".fields) |field| {
        if (!@hasField(Options, field.name)) @compileError("unknown format option '" ++ field.name ++ "'");
        @field(result, field.name) = @field(options, field.name);
    }
    return result;
}

fn expectCodecWrite(comptime T: type, value: T, comptime format: Format, expected: []const u8) !void {
    var buffer: [1024]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);

    try Codec(T).write(&writer, value, format);

    try std.testing.expectEqualStrings(expected, writer.buffered());
}

test "codec exposes type metadata namespace" {
    const User = struct {
        id: u64,
        name: []const u8,
    };
    const UserSerde = Codec(User);

    try std.testing.expectEqual(User, UserSerde.Type);
    try UserSerde.validate(.{ .id = 1, .name = "Grant" });
    try std.testing.expectEqualStrings(@typeName(User), UserSerde.schema().type_name);
}

test "codec writes json equivalent to format api" {
    const User = struct {
        id: u64,
        name: []const u8,
        active: bool,
    };

    const user = User{ .id = 1, .name = "Grant", .active = true };

    var format_buffer: [1024]u8 = undefined;
    var format_writer: std.Io.Writer = .fixed(&format_buffer);
    try json.write(&format_writer, user);

    var codec_buffer: [1024]u8 = undefined;
    var codec_writer: std.Io.Writer = .fixed(&codec_buffer);
    try Codec(User).write(&codec_writer, user, .json);

    try std.testing.expectEqualStrings(format_writer.buffered(), codec_writer.buffered());
    try std.testing.expectEqualStrings("{\"id\":1,\"name\":\"Grant\",\"active\":true}", codec_writer.buffered());
}

test "codec writes human equivalent to format api" {
    const User = struct {
        id: u64,
        name: []const u8,
        active: bool,
    };

    const user = User{ .id = 1, .name = "Grant", .active = true };

    var format_buffer: [1024]u8 = undefined;
    var format_writer: std.Io.Writer = .fixed(&format_buffer);
    try human.write(&format_writer, user);

    var codec_buffer: [1024]u8 = undefined;
    var codec_writer: std.Io.Writer = .fixed(&codec_buffer);
    try Codec(User).write(&codec_writer, user, .human);

    try std.testing.expectEqualStrings(format_writer.buffered(), codec_writer.buffered());
    try std.testing.expectEqualStrings("User { id: 1, name: \"Grant\", active: true }", codec_writer.buffered());
}

test "codec writes toml equivalent to format api" {
    const User = struct {
        id: u64,
        name: []const u8,
        active: bool,
    };

    const user = User{ .id = 1, .name = "Grant", .active = true };

    var format_buffer: [1024]u8 = undefined;
    var format_writer: std.Io.Writer = .fixed(&format_buffer);
    try toml.write(&format_writer, user);

    var codec_buffer: [1024]u8 = undefined;
    var codec_writer: std.Io.Writer = .fixed(&codec_buffer);
    try Codec(User).write(&codec_writer, user, .toml);

    try std.testing.expectEqualStrings(format_writer.buffered(), codec_writer.buffered());
    try std.testing.expectEqualStrings(
        \\id = 1
        \\name = "Grant"
        \\active = true
    ,
        codec_writer.buffered(),
    );
}

test "codec writes zon equivalent to format api" {
    const Color = enum { red, green, blue };
    const User = struct {
        id: u64,
        name: []const u8,
        active: bool,
        color: Color,
    };

    const user = User{ .id = 1, .name = "Grant", .active = true, .color = .green };

    var format_buffer: [1024]u8 = undefined;
    var format_writer: std.Io.Writer = .fixed(&format_buffer);
    try zon.write(&format_writer, user);

    var codec_buffer: [1024]u8 = undefined;
    var codec_writer: std.Io.Writer = .fixed(&codec_buffer);
    try Codec(User).write(&codec_writer, user, .zon);

    try std.testing.expectEqualStrings(format_writer.buffered(), codec_writer.buffered());
    try std.testing.expectEqualStrings(".{ .id = 1, .name = \"Grant\", .active = true, .color = .green }", codec_writer.buffered());
}

test "codec writes and reads msgpack equivalent to format api" {
    const User = struct {
        id: u8,
        name: []const u8,
        active: bool,
    };

    const user = User{ .id = 1, .name = "Ada", .active = true };

    var format_buffer: [128]u8 = undefined;
    var format_writer: std.Io.Writer = .fixed(&format_buffer);
    try msgpack.write(&format_writer, user);

    var codec_buffer: [128]u8 = undefined;
    var codec_writer: std.Io.Writer = .fixed(&codec_buffer);
    try Codec(User).write(&codec_writer, user, .msgpack);

    try std.testing.expectEqualSlices(u8, format_writer.buffered(), codec_writer.buffered());
    try std.testing.expectEqualSlices(u8, &.{
        0x83,
        0xa2,
        'i',
        'd',
        0x01,
        0xa4,
        'n',
        'a',
        'm',
        'e',
        0xa3,
        'A',
        'd',
        'a',
        0xa6,
        'a',
        'c',
        't',
        'i',
        'v',
        'e',
        0xc3,
    }, codec_writer.buffered());

    var reader: std.Io.Reader = .fixed(codec_writer.buffered());
    const parsed = try Codec(User).read(std.testing.allocator, &reader, .msgpack);
    defer Codec(User).deinit(std.testing.allocator, parsed);

    try std.testing.expectEqual(user.id, parsed.id);
    try std.testing.expectEqualStrings(user.name, parsed.name);
    try std.testing.expectEqual(user.active, parsed.active);
}

test "codec writes supported values through both milestone 3 formats" {
    const Color = enum { red, green, blue };
    const Item = struct {
        name: []const u8,
        color: Color,
        scores: []const u16,
        nickname: ?[]const u8,
    };

    const scores = [_]u16{ 10, 20, 30 };
    const item = Item{
        .name = "Ada",
        .color = .green,
        .scores = scores[0..],
        .nickname = null,
    };

    try expectCodecWrite(Item, item, .json, "{\"name\":\"Ada\",\"color\":\"green\",\"scores\":[10,20,30],\"nickname\":null}");
    try expectCodecWrite(Item, item, .human, "Item { name: \"Ada\", color: \"green\", scores: [10, 20, 30], nickname: null }");
}

test "codec namespace can be reused for multiple writes" {
    const User = struct {
        id: u8,
        name: []const u8,
    };
    const UserSerde = Codec(User);

    var json_buffer: [128]u8 = undefined;
    var json_writer: std.Io.Writer = .fixed(&json_buffer);
    try UserSerde.write(&json_writer, .{ .id = 7, .name = "Ada" }, .json);

    var human_buffer: [128]u8 = undefined;
    var human_writer: std.Io.Writer = .fixed(&human_buffer);
    try UserSerde.write(&human_writer, .{ .id = 8, .name = "Grace" }, .human);

    try std.testing.expectEqualStrings("{\"id\":7,\"name\":\"Ada\"}", json_writer.buffered());
    try std.testing.expectEqualStrings("User { id: 8, name: \"Grace\" }", human_writer.buffered());
}

test "codec json write propagates encoder errors" {
    const Message = struct {
        text: []const u8,
    };
    const invalid = [_]u8{0xff};

    var buffer: [128]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);

    try std.testing.expectError(error.InvalidUtf8, Codec(Message).write(
        &writer,
        .{ .text = invalid[0..] },
        .json,
    ));
}

test "codec validates metadata and writes renamed fields" {
    const ApiUser = struct {
        user_id: u64,
        display_name: []const u8,
        password_hash: []const u8,

        pub const zerde = .{
            .rename_all = .camel_case,
            .fields = .{
                .password_hash = .{ .skip_writing = true },
            },
        };
    };

    const ApiUserSerde = Codec(ApiUser);

    try std.testing.expectEqual(rename.RenameRule.camel_case, ApiUserSerde.options.rename_all);
    try expectCodecWrite(ApiUser, .{
        .user_id = 1,
        .display_name = "Grant",
        .password_hash = "secret",
    }, .json, "{\"userId\":1,\"displayName\":\"Grant\"}");
}

test "codec writes metadata consistently across formats" {
    const User = struct {
        user_id: u64,
        display_name: []const u8,
        password_hash: []const u8,

        pub const zerde = .{
            .rename_all = .camel_case,
            .fields = .{
                .display_name = .{ .rename = "name" },
                .password_hash = .{ .skip = true },
            },
        };
    };

    const user = User{ .user_id = 1, .display_name = "Grant", .password_hash = "secret" };

    try expectCodecWrite(User, user, .json, "{\"userId\":1,\"name\":\"Grant\"}");
    try expectCodecWrite(User, user, .human, "User { userId: 1, name: \"Grant\" }");
}

test "codec reads json equivalent to format api" {
    const User = struct {
        id: u64,
        name: []const u8,
        active: bool,
    };
    const input = "{\"id\":1,\"name\":\"Grant\",\"active\":true}";

    const format_value = try json.readSlice(User, std.testing.allocator, input);
    defer deinitValue(User, std.testing.allocator, format_value);

    var reader: std.Io.Reader = .fixed(input);
    const codec_value = try Codec(User).read(std.testing.allocator, &reader, .json);
    defer Codec(User).deinit(std.testing.allocator, codec_value);

    try std.testing.expectEqual(format_value.id, codec_value.id);
    try std.testing.expectEqualStrings(format_value.name, codec_value.name);
    try std.testing.expectEqual(format_value.active, codec_value.active);
}

test "codec reads toml equivalent to format api" {
    const User = struct {
        id: u64,
        name: []const u8,
        active: bool,
    };
    const input =
        \\id = 1
        \\name = "Grant"
        \\active = true
    ;

    const format_value = try toml.readSlice(User, std.testing.allocator, input);
    defer deinitValue(User, std.testing.allocator, format_value);

    var reader: std.Io.Reader = .fixed(input);
    const codec_value = try Codec(User).read(std.testing.allocator, &reader, .toml);
    defer Codec(User).deinit(std.testing.allocator, codec_value);

    try std.testing.expectEqual(format_value.id, codec_value.id);
    try std.testing.expectEqualStrings(format_value.name, codec_value.name);
    try std.testing.expectEqual(format_value.active, codec_value.active);
}

test "codec reads zon equivalent to format api" {
    const Color = enum { red, green, blue };
    const User = struct {
        id: u64,
        name: []const u8,
        active: bool,
        color: Color,
    };
    const input = ".{ .id = 1, .name = \"Grant\", .active = true, .color = .green }";

    const format_value = try zon.readSlice(User, std.testing.allocator, input);
    defer deinitValue(User, std.testing.allocator, format_value);

    var reader: std.Io.Reader = .fixed(input);
    const codec_value = try Codec(User).read(std.testing.allocator, &reader, .zon);
    defer Codec(User).deinit(std.testing.allocator, codec_value);

    try std.testing.expectEqual(format_value.id, codec_value.id);
    try std.testing.expectEqualStrings(format_value.name, codec_value.name);
    try std.testing.expectEqual(format_value.active, codec_value.active);
    try std.testing.expectEqual(format_value.color, codec_value.color);
}

test "codec writes and reads binary equivalent to format api" {
    const User = struct {
        id: u16,
        name: []const u8,
        active: bool,
    };

    const user = User{ .id = 0x1234, .name = "Ada", .active = true };

    var format_buffer: [128]u8 = undefined;
    var format_writer: std.Io.Writer = .fixed(&format_buffer);
    try binary.write(&format_writer, user);

    var codec_buffer: [128]u8 = undefined;
    var codec_writer: std.Io.Writer = .fixed(&codec_buffer);
    try Codec(User).write(&codec_writer, user, .binary);

    try std.testing.expectEqualSlices(u8, format_writer.buffered(), codec_writer.buffered());

    var reader: std.Io.Reader = .fixed(codec_writer.buffered());
    const parsed = try Codec(User).read(std.testing.allocator, &reader, .binary);
    defer Codec(User).deinit(std.testing.allocator, parsed);

    try std.testing.expectEqual(user.id, parsed.id);
    try std.testing.expectEqualStrings(user.name, parsed.name);
    try std.testing.expectEqual(user.active, parsed.active);
}

test "codec reads json using metadata rules" {
    const ApiUser = struct {
        user_id: u64,
        display_name: []const u8,
        password_hash: []const u8 = "redacted",

        pub const zerde = .{
            .rename_all = .camel_case,
            .deny_unknown_fields = true,
            .fields = .{
                .display_name = .{ .rename = "name" },
                .password_hash = .{ .skip_reading = true },
            },
        };
    };

    var reader: std.Io.Reader = .fixed("{\"userId\":1,\"name\":\"Grant\"}");
    const value = try Codec(ApiUser).read(std.testing.allocator, &reader, .json);
    defer Codec(ApiUser).deinit(std.testing.allocator, value);

    try std.testing.expectEqual(@as(u64, 1), value.user_id);
    try std.testing.expectEqualStrings("Grant", value.display_name);
    try std.testing.expectEqualStrings("redacted", value.password_hash);

    var unknown_reader: std.Io.Reader = .fixed("{\"userId\":1,\"name\":\"Grant\",\"extra\":true}");
    try std.testing.expectError(error.UnknownField, Codec(ApiUser).read(std.testing.allocator, &unknown_reader, .json));
}

test "codec deinit frees json deserialized owned values" {
    const Tag = struct {
        name: []const u8,
    };
    const User = struct {
        name: []const u8,
        tags: []const Tag,
        nickname: ?[]const u8,
    };
    const UserSerde = Codec(User);

    const value = try json.readSlice(User, std.testing.allocator,
        \\{
        \\  "name": "Ada",
        \\  "tags": [{"name":"admin"},{"name":"ops"}],
        \\  "nickname": "a"
        \\}
    );
    defer UserSerde.deinit(std.testing.allocator, value);

    try std.testing.expectEqualStrings("Ada", value.name);
    try std.testing.expectEqual(@as(usize, 2), value.tags.len);
    try std.testing.expectEqualStrings("admin", value.tags[0].name);
    try std.testing.expectEqualStrings("ops", value.tags[1].name);
    try std.testing.expectEqualStrings("a", value.nickname.?);
}

test "codec supports tagged union json workflows" {
    const Shape = union(enum) {
        label: []const u8,
        none,
    };
    const ShapeSerde = Codec(Shape);

    try expectCodecWrite(Shape, .{ .label = "home" }, .json, "{\"label\":\"home\"}");
    try expectCodecWrite(Shape, .{ .none = {} }, .human, "Shape { none: null }");

    var reader: std.Io.Reader = .fixed("{\"label\":\"home\"}");
    const value = try ShapeSerde.read(std.testing.allocator, &reader, .json);
    defer ShapeSerde.deinit(std.testing.allocator, value);

    switch (value) {
        .label => |label| try std.testing.expectEqualStrings("home", label),
        .none => return error.InvalidValue,
    }

    const schema = comptime ShapeSerde.schema();
    try std.testing.expectEqual(@as(usize, 2), schema.shape.union_.variants.len);
}

test "codec read and deinit are leak-free for owned json values" {
    const Child = struct {
        label: []const u8,
    };
    const Value = struct {
        name: []const u8,
        children: []const Child,
        note: ?[]const u8,
    };

    var reader: std.Io.Reader = .fixed(
        \\{
        \\  "name": "root",
        \\  "children": [{"label":"one"},{"label":"two"}],
        \\  "note": "owned"
        \\}
    );
    const value = try Codec(Value).read(std.testing.allocator, &reader, .json);
    defer Codec(Value).deinit(std.testing.allocator, value);

    try std.testing.expectEqualStrings("root", value.name);
    try std.testing.expectEqual(@as(usize, 2), value.children.len);
    try std.testing.expectEqualStrings("one", value.children[0].label);
    try std.testing.expectEqualStrings("two", value.children[1].label);
    try std.testing.expectEqualStrings("owned", value.note.?);
}

test "codec schema compiles for supported types" {
    const Role = enum { admin, user };
    const Account = struct {
        account_id: u64,
        roles: []const Role,
        nickname: ?[]const u8,
        enabled: bool = true,

        pub const zerde = .{
            .rename_all = .camel_case,
        };
    };

    const account_schema = comptime Codec(Account).schema();
    const fields = account_schema.shape.struct_.fields;

    try std.testing.expectEqualStrings(@typeName(Account), account_schema.type_name);
    try std.testing.expectEqual(@as(usize, 4), fields.len);
    try std.testing.expectEqualStrings("accountId", fields[0].wire_name);
    try std.testing.expect(fields[0].required);
    try std.testing.expectEqual(@as(?usize, null), fields[1].schema.shape.seq.len);
    try std.testing.expectEqualStrings("admin", fields[1].schema.shape.seq.child.shape.enum_.tags[0]);
    try std.testing.expect(!fields[2].required);
    try std.testing.expect(fields[3].has_default);
}

test "codec writeWithOptions supports format options" {
    const User = struct {
        id: u16,
        name: []const u8,
        active: bool,
    };
    const UserSerde = Codec(User);

    var json_buffer: [128]u8 = undefined;
    var json_writer: std.Io.Writer = .fixed(&json_buffer);
    try UserSerde.writeWithOptions(
        std.testing.allocator,
        &json_writer,
        .{ .id = 0x1234, .name = "Ada", .active = true },
        .json,
        .{ .pretty = true },
    );
    try std.testing.expectEqualStrings(
        \\{
        \\  "id": 4660,
        \\  "name": "Ada",
        \\  "active": true
        \\}
    , json_writer.buffered());

    var human_buffer: [128]u8 = undefined;
    var human_writer: std.Io.Writer = .fixed(&human_buffer);
    try UserSerde.writeWithOptions(
        std.testing.allocator,
        &human_writer,
        .{ .id = 0x1234, .name = "Ada", .active = true },
        .human,
        .{},
    );
    try std.testing.expectEqualStrings("User { id: 4660, name: \"Ada\", active: true }", human_writer.buffered());

    var binary_buffer: [128]u8 = undefined;
    var binary_writer: std.Io.Writer = .fixed(&binary_buffer);
    try UserSerde.writeWithOptions(
        std.testing.allocator,
        &binary_writer,
        .{ .id = 0x1234, .name = "Ada", .active = true },
        .binary,
        .{ .endian = .big },
    );
    try std.testing.expectEqualSlices(u8, &.{
        0x12, 0x34,
        0x00, 0x00,
        0x00, 0x00,
        0x00, 0x00,
        0x00, 0x03,
        'A',  'd',
        'a',  0x01,
    }, binary_writer.buffered());

    var binary_reader: std.Io.Reader = .fixed(binary_writer.buffered());
    const parsed = try UserSerde.readWithOptions(std.testing.allocator, &binary_reader, .binary, .{ .endian = .big });
    defer UserSerde.deinit(std.testing.allocator, parsed);

    try std.testing.expectEqual(@as(u16, 0x1234), parsed.id);
    try std.testing.expectEqualStrings("Ada", parsed.name);
    try std.testing.expect(parsed.active);
}

test "codec writes and reads csv with delimiter options" {
    const User = struct {
        id: u8,
        name: []const u8,
    };
    const UsersSerde = Codec([]const User);
    const users = [_]User{
        .{ .id = 1, .name = "Ada" },
        .{ .id = 2, .name = "has\ttab" },
    };

    var buffer: [128]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    try UsersSerde.writeWithOptions(std.testing.allocator, &writer, users[0..], .csv, .{
        .delimiter = .tab,
        .record_terminator = .lf,
    });
    try std.testing.expectEqualStrings("id\tname\n1\tAda\n2\t\"has\ttab\"", writer.buffered());

    var reader: std.Io.Reader = .fixed(writer.buffered());
    const parsed = try UsersSerde.readWithOptions(std.testing.allocator, &reader, .csv, .{ .delimiter = .tab });
    defer UsersSerde.deinit(std.testing.allocator, parsed);
    try std.testing.expectEqual(@as(usize, 2), parsed.len);
    try std.testing.expectEqual(@as(u8, 2), parsed[1].id);
    try std.testing.expectEqualStrings("has\ttab", parsed[1].name);
}

test "codec writeWithOptions supports toml sections" {
    const Database = struct {
        host: []const u8,
        port: u16,
    };
    const Config = struct {
        name: []const u8,
        database: Database,
    };

    var buffer: [256]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    try Codec(Config).writeWithOptions(
        std.testing.allocator,
        &writer,
        .{ .name = "app", .database = .{ .host = "localhost", .port = 5432 } },
        .toml,
        .{ .layout = .sections },
    );

    try std.testing.expectEqualStrings(
        \\name = "app"
        \\
        \\[database]
        \\host = "localhost"
        \\port = 5432
    , writer.buffered());
}
