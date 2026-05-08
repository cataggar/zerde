//! Type-specialized codec API.

const std = @import("std");

const meta = @import("meta.zig");
const schema_mod = @import("schema.zig");
const human = @import("human.zig");
const json = @import("json.zig");

/// Formats supported by the simple codec dispatch API.
pub const Format = enum {
    json,
    human,
};

/// Returns a type-specific namespace for serialization, deserialization,
/// validation, schema generation, and cleanup.
pub fn Codec(comptime T: type) type {
    comptime {
        meta.validate(T, meta.optionsFor(T));
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
                .human => try human.write(writer, value),
            }
        }

        /// Deserializes a `Type` value from `reader` in the selected format.
        pub fn read(allocator: std.mem.Allocator, reader: *std.Io.Reader, comptime format: Format) !T {
            _ = allocator;
            _ = reader;
            return switch (format) {
                .json, .human => error.Unsupported,
            };
        }

        /// Validates a value against codec-level rules.
        pub fn validate(value: T) !void {
            _ = value;
        }

        /// Returns the internal schema descriptor for `Type`.
        pub fn schema() schema_mod.Schema {
            return schema_mod.forType(T);
        }

        /// Cleans up allocations owned by a value produced by Zerde deserialization.
        pub fn deinit(allocator: std.mem.Allocator, value: T) void {
            _ = allocator;
            _ = value;
        }
    };
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
