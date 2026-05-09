//! Human-readable serialization format.

const std = @import("std");

const base64 = @import("base64.zig");
const serialize = @import("serialize.zig").serialize;

/// Human writer configuration. Reserved for future formatting options.
pub const WriteOptions = struct {};

/// Serializes `value` to a compact human-readable representation.
pub fn write(writer: *std.Io.Writer, value: anytype) !void {
    try writeWithOptions(writer, value, .{});
}

/// Serializes `value` to a compact human-readable representation with options.
pub fn writeWithOptions(writer: *std.Io.Writer, value: anytype, options: WriteOptions) !void {
    _ = options;
    var enc = encoder(writer);
    try serialize(value, &enc);
}

/// Returns a low-level human-readable encoder for use with `zerde.serialize`.
pub fn encoder(writer: *std.Io.Writer) Encoder {
    return .{ .writer = writer };
}

/// Low-level human-readable encoder used by the generic serializer.
pub const Encoder = struct {
    const Self = @This();
    const max_depth = 64;

    const Container = enum {
        seq,
        struct_,
    };

    const Frame = struct {
        container: Container,
        count: usize = 0,
        expecting_field_value: bool = false,
    };

    writer: *std.Io.Writer,
    stack: [max_depth]Frame = undefined,
    stack_len: usize = 0,

    /// Emits the `null` value.
    pub fn emitNull(self: *Self) !void {
        try self.beforeValue();
        try self.writer.writeAll("null");
    }

    /// Emits a boolean value.
    pub fn emitBool(self: *Self, value: bool) !void {
        try self.beforeValue();
        try self.writer.writeAll(if (value) "true" else "false");
    }

    /// Emits an integer value.
    pub fn emitInt(self: *Self, value: anytype) !void {
        try self.beforeValue();
        try self.writer.print("{d}", .{value});
    }

    /// Emits a float value.
    pub fn emitFloat(self: *Self, value: anytype) !void {
        try self.beforeValue();
        try self.writer.print("{d}", .{value});
    }

    /// Emits a quoted string with common escapes.
    pub fn emitString(self: *Self, value: []const u8) !void {
        try self.beforeValue();
        try self.writeEscapedString(value);
    }

    /// Emits raw bytes as a base64 string.
    pub fn emitBytes(self: *Self, value: []const u8) !void {
        try self.beforeValue();
        try self.writer.writeByte('"');
        try base64.writeEncoded(self.writer, value);
        try self.writer.writeByte('"');
    }

    /// Begins a sequence.
    pub fn beginSeq(self: *Self, len: ?usize) !void {
        _ = len;
        try self.beforeValue();
        try self.writer.writeAll("[");
        try self.push(.seq);
    }

    /// Ends the current sequence.
    pub fn endSeq(self: *Self) !void {
        self.pop(.seq);
        try self.writer.writeAll("]");
    }

    /// Begins a struct representation using the short Zig type name.
    pub fn beginStruct(self: *Self, comptime T: type, field_count: usize) !void {
        try self.beforeValue();
        try self.writer.print("{s} {{", .{shortTypeName(T)});
        if (field_count != 0) try self.writer.writeAll(" ");
        try self.push(.struct_);
    }

    /// Emits the next struct field name.
    pub fn emitFieldName(self: *Self, name: []const u8) !void {
        const frame = self.currentFrame(.struct_);
        if (frame.expecting_field_value) return error.InvalidHumanEncoderState;
        if (frame.count != 0) try self.writer.writeAll(", ");
        try self.writer.print("{s}: ", .{name});
        frame.count += 1;
        frame.expecting_field_value = true;
    }

    /// Ends the current struct representation.
    pub fn endStruct(self: *Self) !void {
        const frame = self.currentFrame(.struct_);
        if (frame.expecting_field_value) return error.InvalidHumanEncoderState;
        const had_fields = frame.count != 0;
        self.pop(.struct_);
        if (had_fields) try self.writer.writeAll(" ");
        try self.writer.writeAll("}");
    }

    /// Emits an enum tag as a string.
    pub fn emitEnumTag(self: *Self, tag: []const u8) !void {
        try self.emitString(tag);
    }

    fn beforeValue(self: *Self) !void {
        if (self.stack_len == 0) return;

        const frame = &self.stack[self.stack_len - 1];
        switch (frame.container) {
            .seq => {
                if (frame.count != 0) try self.writer.writeAll(", ");
                frame.count += 1;
            },
            .struct_ => {
                if (!frame.expecting_field_value) return error.InvalidHumanEncoderState;
                frame.expecting_field_value = false;
            },
        }
    }

    fn push(self: *Self, container: Container) !void {
        if (self.stack_len == self.stack.len) return error.NestingTooDeep;
        self.stack[self.stack_len] = .{ .container = container };
        self.stack_len += 1;
    }

    fn pop(self: *Self, expected: Container) void {
        std.debug.assert(self.stack_len != 0);
        std.debug.assert(self.stack[self.stack_len - 1].container == expected);
        self.stack_len -= 1;
    }

    fn currentFrame(self: *Self, expected: Container) *Frame {
        std.debug.assert(self.stack_len != 0);
        const frame = &self.stack[self.stack_len - 1];
        std.debug.assert(frame.container == expected);
        return frame;
    }

    fn writeEscapedString(self: *Self, value: []const u8) !void {
        try self.writer.writeAll("\"");
        for (value) |byte| {
            switch (byte) {
                '"' => try self.writer.writeAll("\\\""),
                '\\' => try self.writer.writeAll("\\\\"),
                '\n' => try self.writer.writeAll("\\n"),
                '\r' => try self.writer.writeAll("\\r"),
                '\t' => try self.writer.writeAll("\\t"),
                0x00...0x08, 0x0b...0x0c, 0x0e...0x1f => {
                    const digits = "0123456789abcdef";
                    try self.writer.writeAll("\\x");
                    try self.writer.writeByte(digits[byte >> 4]);
                    try self.writer.writeByte(digits[byte & 0x0f]);
                },
                else => try self.writer.writeByte(byte),
            }
        }
        try self.writer.writeAll("\"");
    }
};

fn shortTypeName(comptime T: type) []const u8 {
    const name = @typeName(T);
    comptime var start: usize = 0;
    inline for (name, 0..) |char, i| {
        if (char == '.') start = i + 1;
    }
    return name[start..];
}

fn expectHuman(value: anytype, expected: []const u8) !void {
    var buffer: [1024]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);

    try write(&writer, value);

    try std.testing.expectEqualStrings(expected, writer.buffered());
}

test "human writes primitive values" {
    try expectHuman(true, "true");
    try expectHuman(false, "false");
    try expectHuman(@as(i32, -42), "-42");
    try expectHuman(@as(u64, 42), "42");
    try expectHuman(@as(f64, 1.5), "1.5");
}

test "human writes strings" {
    try expectHuman("Grant", "\"Grant\"");
    try expectHuman(@as([]const u8, "Grant"), "\"Grant\"");

    var mutable = [_]u8{ 'Z', 'i', 'g' };
    const mutable_slice: []u8 = mutable[0..];
    try expectHuman(mutable_slice, "\"Zig\"");

    try expectHuman(@as([]const u8, "quote: \" slash: \\ newline:\n"), "\"quote: \\\" slash: \\\\ newline:\\n\"");
}

test "human writes bytes as base64 strings" {
    const Blob = struct {
        data: base64.Bytes,
    };
    const bytes = [_]u8{ 0, 1, 2, 3 };

    try expectHuman(Blob{ .data = .{ .value = bytes[0..] } }, "Blob { data: \"AAECAw==\" }");
}

test "human writes arrays and slices" {
    try expectHuman([3]u8{ 1, 2, 3 }, "[1, 2, 3]");

    const values = [_]u16{ 10, 20, 30 };
    const slice: []const u16 = values[0..];
    try expectHuman(slice, "[10, 20, 30]");
}

test "human writes optionals" {
    try expectHuman(@as(?u8, null), "null");
    try expectHuman(@as(?u8, 7), "7");
}

test "human writes enums as string tags" {
    const Color = enum { red, green, blue };

    try expectHuman(Color.green, "\"green\"");
}

test "human writes tagged unions with external tags" {
    const Circle = struct { radius: u8 };
    const Shape = union(enum) {
        circle: Circle,
        point,
    };

    try expectHuman(Shape{ .circle = .{ .radius = 10 } }, "Shape { circle: Circle { radius: 10 } }");
    try expectHuman(Shape{ .point = {} }, "Shape { point: null }");
}

test "human writes alternate tagged union representations" {
    const Circle = struct { radius: u8 };
    const Adjacent = union(enum) {
        circle: Circle,
        point,

        pub const zerde = .{ .union_repr = .adjacent };
    };
    const Internal = union(enum) {
        circle: Circle,
        point,

        pub const zerde = .{ .union_repr = .internal };
    };

    try expectHuman(Adjacent{ .circle = .{ .radius = 10 } }, "Adjacent { tag: \"circle\", value: Circle { radius: 10 } }");
    try expectHuman(Adjacent{ .point = {} }, "Adjacent { tag: \"point\", value: null }");
    try expectHuman(Internal{ .circle = .{ .radius = 10 } }, "Internal { tag: \"circle\", radius: 10 }");
    try expectHuman(Internal{ .point = {} }, "Internal { tag: \"point\" }");
}

test "human writes nested structs in declaration order" {
    const User = struct {
        id: u64,
        name: []const u8,
        active: bool,
    };
    const Session = struct {
        user: User,
        scores: [2]u8,
        nickname: ?[]const u8,
    };

    try expectHuman(Session{
        .user = .{ .id = 1, .name = "Grant", .active = true },
        .scores = .{ 9, 10 },
        .nickname = null,
    }, "Session { user: User { id: 1, name: \"Grant\", active: true }, scores: [9, 10], nickname: null }");
}

test "human writes structs with default fields" {
    const Defaults = struct {
        id: u8,
        active: bool = true,
        label: []const u8 = "new",
    };

    try expectHuman(Defaults{ .id = 1 }, "Defaults { id: 1, active: true, label: \"new\" }");
}

test "human writes metadata renamed and skipped fields" {
    const ApiUser = struct {
        user_id: u64,
        display_name: []const u8,
        password_hash: []const u8,

        pub const zerde = .{
            .rename_all = .camel_case,
            .fields = .{
                .password_hash = .{ .skip_serializing = true },
            },
        };
    };

    try expectHuman(ApiUser{
        .user_id = 1,
        .display_name = "Grant",
        .password_hash = "secret",
    }, "ApiUser { userId: 1, displayName: \"Grant\" }");
}

test "human explicit rename overrides rename_all" {
    const User = struct {
        user_id: u64,
        display_name: []const u8,

        pub const zerde = .{
            .rename_all = .camel_case,
            .fields = .{
                .display_name = .{ .rename = "name" },
            },
        };
    };

    try expectHuman(User{ .user_id = 1, .display_name = "Grant" }, "User { userId: 1, name: \"Grant\" }");
}

test "human skip metadata handles empty and middle fields" {
    const Hidden = struct {
        password_hash: []const u8,

        pub const zerde = .{
            .fields = .{
                .password_hash = .{ .skip = true },
            },
        };
    };
    const User = struct {
        id: u64,
        password_hash: []const u8,
        active: bool,

        pub const zerde = .{
            .fields = .{
                .password_hash = .{ .skip_serializing = true },
            },
        };
    };

    try expectHuman(Hidden{ .password_hash = "secret" }, "Hidden {}");
    try expectHuman(User{ .id = 1, .password_hash = "secret", .active = true }, "User { id: 1, active: true }");
}

test "human write includes skip_deserializing fields" {
    const User = struct {
        id: u8,
        token: []const u8,

        pub const zerde = .{
            .deny_unknown_fields = true,
            .fields = .{
                .token = .{ .skip_deserializing = true },
            },
        };
    };

    try expectHuman(User{ .id = 1, .token = "visible" }, "User { id: 1, token: \"visible\" }");
}
