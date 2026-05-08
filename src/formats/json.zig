//! Compact JSON format support.

const std = @import("std");

const serialize = @import("../serialize.zig").serialize;

/// Serializes `value` as compact JSON to `writer`.
///
/// Strings must be valid UTF-8. Non-finite floats are rejected because JSON has
/// no representation for NaN or infinity.
pub fn write(writer: *std.Io.Writer, value: anytype) !void {
    var enc = encoder(writer);
    try serialize(value, &enc);
    try enc.finish();
}

/// Returns a low-level JSON encoder for use with `zerde.serialize` or custom
/// serialization code.
///
/// Call `Encoder.finish` after writing the root value to validate that a
/// complete JSON document was produced.
pub fn encoder(writer: *std.Io.Writer) Encoder {
    return .{ .writer = writer };
}

/// Deserializes JSON from `reader` into `T`.
///
/// JSON reading is not implemented until the JSON reader milestone.
pub fn read(comptime T: type, allocator: std.mem.Allocator, reader: *std.Io.Reader) !T {
    _ = allocator;
    _ = reader;
    return error.Unsupported;
}

/// Serializes `value` as compact JSON and returns allocator-owned bytes.
///
/// The caller owns the returned slice and must free it with `allocator.free`.
pub fn writeAlloc(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    var allocating = std.Io.Writer.Allocating.init(allocator);
    errdefer allocating.deinit();

    try write(&allocating.writer, value);
    return try allocating.toOwnedSlice();
}

/// Deserializes JSON from `input` into `T`.
///
/// JSON reading is not implemented until the JSON reader milestone.
pub fn readSlice(comptime T: type, allocator: std.mem.Allocator, input: []const u8) !T {
    _ = allocator;
    _ = input;
    return error.Unsupported;
}

/// Low-level compact JSON encoder used by the generic serializer.
///
/// The encoder owns no memory. It writes directly to the supplied
/// `std.Io.Writer`, tracks container state for comma insertion, validates UTF-8
/// strings, rejects non-finite floats, and enforces a fixed nesting limit.
pub const Encoder = struct {
    const Self = @This();
    const max_depth = 64;

    const Container = enum {
        seq,
        object,
    };

    const Frame = struct {
        container: Container,
        count: usize = 0,
        expecting_field_value: bool = false,
    };

    writer: *std.Io.Writer,
    stack: [max_depth]Frame = undefined,
    stack_len: usize = 0,
    root_count: usize = 0,

    /// Emits the JSON `null` value.
    pub fn emitNull(self: *Self) !void {
        try self.beforeValue();
        try self.writer.writeAll("null");
    }

    /// Emits a JSON boolean value.
    pub fn emitBool(self: *Self, value: bool) !void {
        try self.beforeValue();
        try self.writer.writeAll(if (value) "true" else "false");
    }

    /// Emits a JSON integer value.
    pub fn emitInt(self: *Self, value: anytype) !void {
        try self.beforeValue();
        try self.writer.print("{d}", .{value});
    }

    /// Emits a JSON number from a finite float.
    pub fn emitFloat(self: *Self, value: anytype) !void {
        const Float = switch (@typeInfo(@TypeOf(value))) {
            .comptime_float => f64,
            else => @TypeOf(value),
        };
        const finite_value: Float = value;
        if (!std.math.isFinite(finite_value)) return error.InvalidJsonFloat;

        try self.beforeValue();
        try self.writer.print("{d}", .{value});
    }

    /// Emits a JSON string after validating that `value` is valid UTF-8.
    pub fn emitString(self: *Self, value: []const u8) !void {
        try validateString(value);
        try self.beforeValue();
        try self.writeEscapedString(value);
    }

    /// Begins a JSON array.
    ///
    /// `len` is accepted for the generic encoder protocol but is not required
    /// by JSON output.
    pub fn beginSeq(self: *Self, len: ?usize) !void {
        _ = len;
        try self.ensureCanPush();
        try self.beforeValue();
        try self.writer.writeAll("[");
        self.push(.seq);
    }

    /// Ends the current JSON array.
    pub fn endSeq(self: *Self) !void {
        self.pop(.seq);
        try self.writer.writeAll("]");
    }

    /// Begins a JSON object for a Zig struct.
    ///
    /// `T` and `field_count` are accepted for the generic encoder protocol but
    /// are not required by compact JSON output.
    pub fn beginStruct(self: *Self, comptime T: type, field_count: usize) !void {
        _ = T;
        _ = field_count;
        try self.ensureCanPush();
        try self.beforeValue();
        try self.writer.writeAll("{");
        self.push(.object);
    }

    /// Emits a JSON object field name after validating that `name` is valid UTF-8.
    pub fn emitFieldName(self: *Self, name: []const u8) !void {
        try validateString(name);

        const frame = self.currentFrame(.object);
        if (frame.expecting_field_value) return error.InvalidJsonEncoderState;
        if (frame.count != 0) try self.writer.writeAll(",");
        try self.writeEscapedString(name);
        try self.writer.writeAll(":");
        frame.count += 1;
        frame.expecting_field_value = true;
    }

    /// Ends the current JSON object.
    pub fn endStruct(self: *Self) !void {
        const frame = self.currentFrame(.object);
        if (frame.expecting_field_value) return error.InvalidJsonEncoderState;
        self.pop(.object);
        try self.writer.writeAll("}");
    }

    /// Emits an enum tag as a JSON string.
    pub fn emitEnumTag(self: *Self, tag: []const u8) !void {
        try self.emitString(tag);
    }

    /// Verifies that exactly one complete JSON root value has been emitted.
    ///
    /// This catches incomplete custom encoder usage, such as an unclosed array
    /// or an object field name without a following value.
    pub fn finish(self: *Self) !void {
        if (self.root_count == 0) return error.IncompleteJsonDocument;
        if (self.stack_len == 0) return;

        const frame = &self.stack[self.stack_len - 1];
        if (frame.container == .object and frame.expecting_field_value) return error.InvalidJsonEncoderState;
        return error.IncompleteJsonDocument;
    }

    fn beforeValue(self: *Self) !void {
        if (self.stack_len == 0) {
            if (self.root_count != 0) return error.InvalidJsonEncoderState;
            self.root_count += 1;
            return;
        }

        const frame = &self.stack[self.stack_len - 1];
        switch (frame.container) {
            .seq => {
                if (frame.count != 0) try self.writer.writeAll(",");
                frame.count += 1;
            },
            .object => {
                if (!frame.expecting_field_value) return error.InvalidJsonEncoderState;
                frame.expecting_field_value = false;
            },
        }
    }

    fn ensureCanPush(self: *Self) !void {
        if (self.stack_len == self.stack.len) return error.NestingTooDeep;
    }

    fn push(self: *Self, container: Container) void {
        std.debug.assert(self.stack_len != self.stack.len);
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

    fn validateString(value: []const u8) !void {
        if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidUtf8;
    }

    fn writeEscapedString(self: *Self, value: []const u8) !void {
        try self.writer.writeAll("\"");
        var run_start: usize = 0;
        for (value, 0..) |byte, i| {
            switch (byte) {
                '"' => try self.writeEscapedByte(value, &run_start, i, "\\\""),
                '\\' => try self.writeEscapedByte(value, &run_start, i, "\\\\"),
                '\n' => try self.writeEscapedByte(value, &run_start, i, "\\n"),
                '\r' => try self.writeEscapedByte(value, &run_start, i, "\\r"),
                '\t' => try self.writeEscapedByte(value, &run_start, i, "\\t"),
                0x00...0x08, 0x0b...0x0c, 0x0e...0x1f => {
                    const digits = "0123456789abcdef";
                    try self.writer.writeAll(value[run_start..i]);
                    try self.writer.writeAll("\\u00");
                    try self.writer.writeByte(digits[byte >> 4]);
                    try self.writer.writeByte(digits[byte & 0x0f]);
                    run_start = i + 1;
                },
                else => {},
            }
        }
        try self.writer.writeAll(value[run_start..]);
        try self.writer.writeAll("\"");
    }

    fn writeEscapedByte(self: *Self, value: []const u8, run_start: *usize, index: usize, escaped: []const u8) !void {
        try self.writer.writeAll(value[run_start.*..index]);
        try self.writer.writeAll(escaped);
        run_start.* = index + 1;
    }
};

fn expectJson(value: anytype, expected: []const u8) !void {
    var buffer: [1024]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);

    try write(&writer, value);

    try std.testing.expectEqualStrings(expected, writer.buffered());
}

test "json writes null optionals" {
    try expectJson(@as(?u8, null), "null");
    try expectJson(@as(?u8, 7), "7");
}

test "json writes primitive values" {
    try expectJson(true, "true");
    try expectJson(false, "false");
    try expectJson(@as(i32, -42), "-42");
    try expectJson(@as(u64, 42), "42");
    try expectJson(@as(f64, 1.5), "1.5");
}

test "json writes escaped strings" {
    try expectJson("Grant", "\"Grant\"");
    try expectJson(@as([]const u8, "quote: \" slash: \\ newline:\n"), "\"quote: \\\" slash: \\\\ newline:\\n\"");
    try expectJson(@as([]const u8, "tab:\t cr:\r control:\x01"), "\"tab:\\t cr:\\r control:\\u0001\"");
    try expectJson(@as([]const u8, "東京市"), "\"東京市\"");
}

test "json writes arrays and slices" {
    try expectJson([3]u8{ 1, 2, 3 }, "[1,2,3]");

    const values = [_]u16{ 10, 20, 30 };
    const slice: []const u16 = values[0..];
    try expectJson(slice, "[10,20,30]");
}

test "json writes empty containers" {
    const Empty = struct {};
    const Container = struct {
        empty_array: [0]u8,
        empty_slice: []const u16,
        empty_struct: Empty,
    };

    const values = [_]u16{};
    const slice: []const u16 = values[0..];
    try expectJson([0]u8{}, "[]");
    try expectJson(slice, "[]");
    try expectJson(Empty{}, "{}");
    try expectJson(Container{
        .empty_array = .{},
        .empty_slice = slice,
        .empty_struct = .{},
    }, "{\"empty_array\":[],\"empty_slice\":[],\"empty_struct\":{}}");
}

test "json writes structs and nested structs" {
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

    try expectJson(User{ .id = 1, .name = "Grant", .active = true }, "{\"id\":1,\"name\":\"Grant\",\"active\":true}");
    try expectJson(Session{
        .user = .{ .id = 1, .name = "Grant", .active = true },
        .scores = .{ 9, 10 },
        .nickname = null,
    }, "{\"user\":{\"id\":1,\"name\":\"Grant\",\"active\":true},\"scores\":[9,10],\"nickname\":null}");
}

test "json writes enums as string tags" {
    const Color = enum { red, green, blue };

    try expectJson(Color.green, "\"green\"");
}

test "json writeAlloc returns owned bytes" {
    const User = struct {
        id: u64,
        name: []const u8,
        active: bool,
    };

    const bytes = try writeAlloc(std.testing.allocator, User{
        .id = 1,
        .name = "Grant",
        .active = true,
    });
    defer std.testing.allocator.free(bytes);

    try std.testing.expectEqualStrings("{\"id\":1,\"name\":\"Grant\",\"active\":true}", bytes);
}

test "json rejects non-finite floats" {
    var buffer: [128]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);

    try std.testing.expectError(error.InvalidJsonFloat, write(&writer, std.math.inf(f64)));
    try std.testing.expectError(error.InvalidJsonFloat, write(&writer, -std.math.inf(f64)));
    try std.testing.expectError(error.InvalidJsonFloat, write(&writer, std.math.nan(f64)));
}

test "json rejects invalid utf-8 strings" {
    var buffer: [128]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    const invalid = [_]u8{0xff};

    try std.testing.expectError(error.InvalidUtf8, write(&writer, invalid[0..]));
    try std.testing.expectEqual(@as(usize, 0), writer.buffered().len);
}

test "json reports nesting too deep" {
    var buffer: [1024]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    var enc = encoder(&writer);

    for (0..64) |_| try enc.beginSeq(null);
    try std.testing.expectError(error.NestingTooDeep, enc.beginSeq(null));
    try std.testing.expectEqual(@as(usize, 64), writer.buffered().len);
}

test "json low-level encoder can be finished" {
    var buffer: [128]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    var enc = encoder(&writer);

    try enc.beginSeq(null);
    try enc.emitInt(@as(u8, 1));
    try enc.emitString("two");
    try enc.endSeq();
    try enc.finish();

    try std.testing.expectEqualStrings("[1,\"two\"]", writer.buffered());
}

test "json low-level extension API works with serialize" {
    const User = struct {
        id: u8,
        name: []const u8,
    };

    var buffer: [128]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    var enc = encoder(&writer);

    try serialize(User{ .id = 7, .name = "Ada" }, &enc);
    try enc.finish();

    try std.testing.expectEqualStrings("{\"id\":7,\"name\":\"Ada\"}", writer.buffered());
}

test "json finish rejects incomplete documents" {
    var buffer: [128]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    var enc = encoder(&writer);

    try std.testing.expectError(error.IncompleteJsonDocument, enc.finish());

    try enc.beginSeq(null);
    try enc.emitBool(true);
    try std.testing.expectError(error.IncompleteJsonDocument, enc.finish());
}

test "json finish rejects pending object field values" {
    const Object = struct { value: u8 };

    var buffer: [128]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    var enc = encoder(&writer);

    try enc.beginStruct(Object, 1);
    try enc.emitFieldName("value");

    try std.testing.expectError(error.InvalidJsonEncoderState, enc.finish());
}

test "json encoder rejects multiple root values" {
    var buffer: [128]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    var enc = encoder(&writer);

    try enc.emitNull();
    try std.testing.expectError(error.InvalidJsonEncoderState, enc.emitBool(true));
    try enc.finish();

    try std.testing.expectEqualStrings("null", writer.buffered());
}
