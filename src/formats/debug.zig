const std = @import("std");

const serialize = @import("../serialize.zig").serialize;

pub fn write(writer: *std.Io.Writer, value: anytype) !void {
    var enc = encoder(writer);
    try serialize(value, &enc);
}

pub fn encoder(writer: *std.Io.Writer) Encoder {
    return .{ .writer = writer };
}

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

    pub fn emitNull(self: *Self) !void {
        try self.beforeValue();
        try self.writer.writeAll("null");
    }

    pub fn emitBool(self: *Self, value: bool) !void {
        try self.beforeValue();
        try self.writer.writeAll(if (value) "true" else "false");
    }

    pub fn emitInt(self: *Self, value: anytype) !void {
        try self.beforeValue();
        try self.writer.print("{d}", .{value});
    }

    pub fn emitFloat(self: *Self, value: anytype) !void {
        try self.beforeValue();
        try self.writer.print("{d}", .{value});
    }

    pub fn emitString(self: *Self, value: []const u8) !void {
        try self.beforeValue();
        try self.writeEscapedString(value);
    }

    pub fn beginSeq(self: *Self, len: ?usize) !void {
        _ = len;
        try self.beforeValue();
        try self.writer.writeAll("[");
        try self.push(.seq);
    }

    pub fn endSeq(self: *Self) !void {
        self.pop(.seq);
        try self.writer.writeAll("]");
    }

    pub fn beginStruct(self: *Self, comptime T: type, field_count: usize) !void {
        try self.beforeValue();
        try self.writer.print("{s} {{", .{shortTypeName(T)});
        if (field_count != 0) try self.writer.writeAll(" ");
        try self.push(.struct_);
    }

    pub fn emitFieldName(self: *Self, name: []const u8) !void {
        const frame = self.currentFrame(.struct_);
        if (frame.expecting_field_value) return error.InvalidDebugEncoderState;
        if (frame.count != 0) try self.writer.writeAll(", ");
        try self.writer.print("{s}: ", .{name});
        frame.count += 1;
        frame.expecting_field_value = true;
    }

    pub fn endStruct(self: *Self) !void {
        const frame = self.currentFrame(.struct_);
        if (frame.expecting_field_value) return error.InvalidDebugEncoderState;
        const had_fields = frame.count != 0;
        self.pop(.struct_);
        if (had_fields) try self.writer.writeAll(" ");
        try self.writer.writeAll("}");
    }

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
                if (!frame.expecting_field_value) return error.InvalidDebugEncoderState;
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

fn expectDebug(value: anytype, expected: []const u8) !void {
    var buffer: [1024]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);

    try write(&writer, value);

    try std.testing.expectEqualStrings(expected, writer.buffered());
}

test "debug writes primitive values" {
    try expectDebug(true, "true");
    try expectDebug(false, "false");
    try expectDebug(@as(i32, -42), "-42");
    try expectDebug(@as(u64, 42), "42");
    try expectDebug(@as(f64, 1.5), "1.5");
}

test "debug writes strings" {
    try expectDebug("Grant", "\"Grant\"");
    try expectDebug(@as([]const u8, "Grant"), "\"Grant\"");

    var mutable = [_]u8{ 'Z', 'i', 'g' };
    const mutable_slice: []u8 = mutable[0..];
    try expectDebug(mutable_slice, "\"Zig\"");

    try expectDebug(@as([]const u8, "quote: \" slash: \\ newline:\n"), "\"quote: \\\" slash: \\\\ newline:\\n\"");
}

test "debug writes arrays and slices" {
    try expectDebug([3]u8{ 1, 2, 3 }, "[1, 2, 3]");

    const values = [_]u16{ 10, 20, 30 };
    const slice: []const u16 = values[0..];
    try expectDebug(slice, "[10, 20, 30]");
}

test "debug writes optionals" {
    try expectDebug(@as(?u8, null), "null");
    try expectDebug(@as(?u8, 7), "7");
}

test "debug writes enums as string tags" {
    const Color = enum { red, green, blue };

    try expectDebug(Color.green, "\"green\"");
}

test "debug writes nested structs in declaration order" {
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

    try expectDebug(Session{
        .user = .{ .id = 1, .name = "Grant", .active = true },
        .scores = .{ 9, 10 },
        .nickname = null,
    }, "Session { user: User { id: 1, name: \"Grant\", active: true }, scores: [9, 10], nickname: null }");
}

test "debug writes structs with default fields" {
    const Defaults = struct {
        id: u8,
        active: bool = true,
        label: []const u8 = "new",
    };

    try expectDebug(Defaults{ .id = 1 }, "Defaults { id: 1, active: true, label: \"new\" }");
}
