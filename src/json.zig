//! JSON format support.

const std = @import("std");

const serialize = @import("serialize.zig").serialize;
const deserialize = @import("deserialize.zig").deserialize;
const deinitValue = @import("deinit.zig").deinit;
const number = @import("number.zig");

const JsonNumber = number.Parser(.{
    .decimal_float = true,
    .exponent = true,
    .strip_leading_positive_sign = false,
    .integer_to_float = true,
    .finite_float_emission = true,
});

/// JSON writer configuration.
pub const WriteOptions = struct {
    pretty: bool = false,
    indent: usize = 2,
};

/// Serializes `value` as compact JSON to `writer`.
///
/// Strings must be valid UTF-8. Non-finite floats are rejected because JSON has
/// no representation for NaN or infinity.
pub fn write(writer: *std.Io.Writer, value: anytype) !void {
    try writeWithOptions(writer, value, .{});
}

/// Serializes `value` as JSON to `writer` with explicit writer options.
pub fn writeWithOptions(writer: *std.Io.Writer, value: anytype, options: WriteOptions) !void {
    var enc = encoderWithOptions(writer, options);
    try serialize(value, &enc);
    try enc.finish();
}

/// Returns a low-level JSON encoder for use with `zerde.serialize` or custom
/// serialization code.
///
/// Call `Encoder.finish` after writing the root value to validate that a
/// complete JSON document was produced.
pub fn encoder(writer: *std.Io.Writer) Encoder {
    return encoderWithOptions(writer, .{});
}

/// Returns a low-level JSON encoder with explicit writer options.
pub fn encoderWithOptions(writer: *std.Io.Writer, options: WriteOptions) Encoder {
    return .{ .writer = writer, .options = options };
}

/// Deserializes JSON from `reader` into `T`.
pub fn read(comptime T: type, allocator: std.mem.Allocator, reader: *std.Io.Reader) !T {
    var dec = decoder(reader, allocator);
    const value = try deserialize(T, allocator, &dec);
    errdefer deinitValue(T, allocator, value);
    try dec.finish();
    return value;
}

/// Serializes `value` as compact JSON and returns allocator-owned bytes.
///
/// The caller owns the returned slice and must free it with `allocator.free`.
pub fn writeAlloc(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    return try writeAllocWithOptions(allocator, value, .{});
}

/// Serializes `value` as JSON with explicit writer options and returns
/// allocator-owned bytes.
pub fn writeAllocWithOptions(allocator: std.mem.Allocator, value: anytype, options: WriteOptions) ![]u8 {
    var allocating = std.Io.Writer.Allocating.init(allocator);
    errdefer allocating.deinit();

    try writeWithOptions(&allocating.writer, value, options);
    return try allocating.toOwnedSlice();
}

/// Deserializes JSON from `input` into `T`.
pub fn readSlice(comptime T: type, allocator: std.mem.Allocator, input: []const u8) !T {
    var reader: std.Io.Reader = .fixed(input);
    return try read(T, allocator, &reader);
}

/// Returns a low-level JSON decoder for use with `zerde.deserialize` or custom
/// deserialization code.
pub fn decoder(reader: *std.Io.Reader, allocator: std.mem.Allocator) Decoder {
    return .{ .reader = reader, .allocator = allocator };
}

/// JSON value kinds reported by `Decoder.peek`.
pub const Kind = enum {
    null,
    bool,
    int,
    float,
    string,
    seq,
    struct_,
};

/// Low-level JSON decoder used by the generic deserializer.
pub const Decoder = struct {
    const Self = @This();
    const max_depth = 64;

    const Container = enum {
        seq,
        object,
    };

    const Frame = struct {
        container: Container,
        first: bool = true,
    };

    reader: *std.Io.Reader,
    allocator: std.mem.Allocator,
    stack: [max_depth]Frame = undefined,
    stack_len: usize = 0,

    pub fn peek(self: *Self) !Kind {
        try self.skipWhitespace();
        const byte = (try self.peekByte()) orelse return error.EndOfStream;
        return switch (byte) {
            'n' => .null,
            't', 'f' => .bool,
            '"' => .string,
            '[' => .seq,
            '{' => .struct_,
            '-', '0'...'9' => try self.peekNumberKind(),
            else => error.InvalidJsonSyntax,
        };
    }

    pub fn readNull(self: *Self) !void {
        try self.expectLiteral("null");
    }

    pub fn readBool(self: *Self) !bool {
        try self.skipWhitespace();
        const byte = (try self.peekByte()) orelse return error.EndOfStream;
        return switch (byte) {
            't' => blk: {
                try self.expectLiteral("true");
                break :blk true;
            },
            'f' => blk: {
                try self.expectLiteral("false");
                break :blk false;
            },
            else => error.InvalidType,
        };
    }

    pub fn readInt(self: *Self, comptime T: type) !T {
        const token = try self.readNumber();
        defer token.deinit(self.allocator);
        return switch (token) {
            .int => |integer| try JsonNumber.readInt(T, integer),
            .float => error.InvalidType,
        };
    }

    pub fn readFloat(self: *Self, comptime T: type) !T {
        const token = try self.readNumber();
        defer token.deinit(self.allocator);
        return try JsonNumber.readFloat(T, token);
    }

    pub fn readString(self: *Self, allocator: std.mem.Allocator) ![]u8 {
        try self.skipWhitespace();
        try self.expectByte('"');

        var out = std.Io.Writer.Allocating.init(allocator);
        errdefer out.deinit();

        while (true) {
            const byte = try self.reader.takeByte();
            switch (byte) {
                '"' => {
                    const result = try out.toOwnedSlice();
                    errdefer allocator.free(result);
                    if (!std.unicode.utf8ValidateSlice(result)) return error.InvalidUtf8;
                    return result;
                },
                '\\' => try self.readEscape(&out.writer),
                0x00...0x1f => return error.InvalidJsonSyntax,
                else => try out.writer.writeByte(byte),
            }
        }
    }

    pub fn beginSeq(self: *Self) !?usize {
        try self.ensureCanPush();
        try self.skipWhitespace();
        try self.expectByte('[');
        self.push(.seq);
        return null;
    }

    pub fn hasNextSeqElem(self: *Self) !bool {
        const frame = self.currentFrame(.seq);
        try self.skipWhitespace();

        if (frame.first) {
            frame.first = false;
            if (try self.consumeIf(']')) return false;
            return true;
        }

        if (try self.consumeIf(']')) return false;
        try self.expectByte(',');
        return true;
    }

    pub fn endSeq(self: *Self) !void {
        self.pop(.seq);
    }

    pub fn beginStruct(self: *Self, comptime T: type) !void {
        _ = T;
        try self.ensureCanPush();
        try self.skipWhitespace();
        try self.expectByte('{');
        self.push(.object);
    }

    pub fn nextField(self: *Self) !?[]u8 {
        const frame = self.currentFrame(.object);
        try self.skipWhitespace();

        if (frame.first) {
            frame.first = false;
            if (try self.consumeIf('}')) return null;
        } else {
            if (try self.consumeIf('}')) return null;
            try self.expectByte(',');
        }

        const name = try self.readString(self.allocator);
        errdefer self.allocator.free(name);
        try self.skipWhitespace();
        try self.expectByte(':');
        return name;
    }

    pub fn endStruct(self: *Self) !void {
        self.pop(.object);
    }

    pub fn skipValue(self: *Self) !void {
        switch (try self.peek()) {
            .null => try self.readNull(),
            .bool => _ = try self.readBool(),
            .int => {
                const token = try self.readNumber();
                token.deinit(self.allocator);
            },
            .float => {
                const token = try self.readNumber();
                token.deinit(self.allocator);
            },
            .string => {
                const value = try self.readString(self.allocator);
                self.allocator.free(value);
            },
            .seq => {
                _ = try self.beginSeq();
                while (try self.hasNextSeqElem()) try self.skipValue();
                try self.endSeq();
            },
            .struct_ => {
                try self.beginStruct(void);
                while (try self.nextField()) |field_name| {
                    self.allocator.free(field_name);
                    try self.skipValue();
                }
                try self.endStruct();
            },
        }
    }

    pub fn finish(self: *Self) !void {
        try self.skipWhitespace();
        if (self.stack_len != 0) return error.InvalidJsonDecoderState;
        if ((try self.peekByte()) != null) return error.InvalidJsonSyntax;
    }

    fn skipWhitespace(self: *Self) !void {
        while (try self.peekByte()) |byte| {
            switch (byte) {
                ' ', '\n', '\r', '\t' => _ = try self.reader.takeByte(),
                else => return,
            }
        }
    }

    fn expectLiteral(self: *Self, literal: []const u8) !void {
        try self.skipWhitespace();
        for (literal) |expected| try self.expectByte(expected);
    }

    fn expectByte(self: *Self, expected: u8) !void {
        const actual = try self.reader.takeByte();
        if (actual != expected) return error.InvalidJsonSyntax;
    }

    fn consumeIf(self: *Self, expected: u8) !bool {
        if (try self.peekByte()) |actual| {
            if (actual == expected) {
                _ = try self.reader.takeByte();
                return true;
            }
        }
        return false;
    }

    fn peekByte(self: *Self) !?u8 {
        return self.reader.peekByte() catch |err| switch (err) {
            error.EndOfStream => null,
            else => |e| return e,
        };
    }

    fn readNumber(self: *Self) !number.Token {
        try self.skipWhitespace();

        var out = std.Io.Writer.Allocating.init(self.allocator);
        errdefer out.deinit();

        if (try self.consumeIf('-')) try out.writer.writeByte('-');

        const first_digit = (try self.peekByte()) orelse return error.InvalidJsonSyntax;
        switch (first_digit) {
            '0' => {
                try out.writer.writeByte(try self.reader.takeByte());
                if (try self.peekByte()) |next| if (isDigit(next)) return error.InvalidJsonSyntax;
            },
            '1'...'9' => {
                while (try self.peekByte()) |byte| {
                    if (!isDigit(byte)) break;
                    try out.writer.writeByte(try self.reader.takeByte());
                }
            },
            else => return error.InvalidType,
        }

        if (try self.consumeIf('.')) {
            try out.writer.writeByte('.');
            try self.readDigits(&out.writer);
        }

        if (try self.peekByte()) |byte| {
            if (byte == 'e' or byte == 'E') {
                try out.writer.writeByte(try self.reader.takeByte());
                if (try self.peekByte()) |sign| {
                    if (sign == '+' or sign == '-') try out.writer.writeByte(try self.reader.takeByte());
                }
                try self.readDigits(&out.writer);
            }
        }

        const bytes = try out.toOwnedSlice();
        return JsonNumber.parseOwned(self.allocator, bytes) catch |err| switch (err) {
            error.InvalidNumberSyntax => error.InvalidJsonSyntax,
            else => |e| return e,
        };
    }

    fn peekNumberKind(self: *Self) !Kind {
        var index: usize = 0;

        if ((try self.peekBufferedByte(index)) == '-') index += 1;
        while (try self.peekBufferedByte(index)) |byte| {
            if (!isDigit(byte)) break;
            index += 1;
        }

        if (try self.peekBufferedByte(index)) |byte| {
            if (byte == '.' or byte == 'e' or byte == 'E') return .float;
        }
        return .int;
    }

    fn peekBufferedByte(self: *Self, offset: usize) !?u8 {
        while (self.reader.bufferedLen() <= offset) {
            self.reader.fillMore() catch |err| switch (err) {
                error.EndOfStream => return null,
                else => |e| return e,
            };
        }
        return self.reader.buffered()[offset];
    }

    fn readDigits(self: *Self, writer: *std.Io.Writer) !void {
        var count: usize = 0;
        while (try self.peekByte()) |byte| {
            if (!isDigit(byte)) break;
            try writer.writeByte(try self.reader.takeByte());
            count += 1;
        }
        if (count == 0) return error.InvalidJsonSyntax;
    }

    fn readEscape(self: *Self, writer: *std.Io.Writer) !void {
        const escape = try self.reader.takeByte();
        switch (escape) {
            '"' => try writer.writeByte('"'),
            '\\' => try writer.writeByte('\\'),
            '/' => try writer.writeByte('/'),
            'b' => try writer.writeByte(0x08),
            'f' => try writer.writeByte(0x0c),
            'n' => try writer.writeByte('\n'),
            'r' => try writer.writeByte('\r'),
            't' => try writer.writeByte('\t'),
            'u' => try self.readUnicodeEscape(writer),
            else => return error.InvalidJsonSyntax,
        }
    }

    fn readUnicodeEscape(self: *Self, writer: *std.Io.Writer) !void {
        const first = try self.readHexQuad();
        const codepoint: u21 = if (first >= 0xd800 and first <= 0xdbff) blk: {
            try self.expectByte('\\');
            try self.expectByte('u');
            const second = try self.readHexQuad();
            if (second < 0xdc00 or second > 0xdfff) return error.InvalidJsonSyntax;
            break :blk 0x10000 + ((@as(u21, first - 0xd800)) << 10) + @as(u21, second - 0xdc00);
        } else if (first >= 0xdc00 and first <= 0xdfff) {
            return error.InvalidJsonSyntax;
        } else @as(u21, first);

        var buffer: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(codepoint, &buffer) catch return error.InvalidUtf8;
        try writer.writeAll(buffer[0..len]);
    }

    fn readHexQuad(self: *Self) !u16 {
        var value: u16 = 0;
        for (0..4) |_| {
            const digit = hexValue(try self.reader.takeByte()) orelse return error.InvalidJsonSyntax;
            value = (value << 4) | digit;
        }
        return value;
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
};

fn isDigit(byte: u8) bool {
    return byte >= '0' and byte <= '9';
}

fn hexValue(byte: u8) ?u16 {
    return switch (byte) {
        '0'...'9' => byte - '0',
        'a'...'f' => byte - 'a' + 10,
        'A'...'F' => byte - 'A' + 10,
        else => null,
    };
}

/// Low-level JSON encoder used by the generic serializer.
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
    options: WriteOptions = .{},
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
        try JsonNumber.emitFloat(value);

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
        const frame = self.currentFrame(.seq);
        if (self.options.pretty and frame.count != 0) try self.writeNewlineAndIndent(self.stack_len - 1);
        self.pop(.seq);
        try self.writer.writeAll("]");
    }

    /// Begins a JSON object for a Zig struct.
    ///
    /// `T` and `field_count` are accepted for the generic encoder protocol but
    /// are not required by JSON output.
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
        if (self.options.pretty) try self.writeNewlineAndIndent(self.stack_len);
        try self.writeEscapedString(name);
        try self.writer.writeAll(":");
        if (self.options.pretty) try self.writer.writeAll(" ");
        frame.count += 1;
        frame.expecting_field_value = true;
    }

    /// Ends the current JSON object.
    pub fn endStruct(self: *Self) !void {
        const frame = self.currentFrame(.object);
        if (frame.expecting_field_value) return error.InvalidJsonEncoderState;
        if (self.options.pretty and frame.count != 0) try self.writeNewlineAndIndent(self.stack_len - 1);
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
                if (self.options.pretty) try self.writeNewlineAndIndent(self.stack_len);
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

    fn writeNewlineAndIndent(self: *Self, depth: usize) !void {
        try self.writer.writeByte('\n');
        for (0..depth * self.options.indent) |_| try self.writer.writeByte(' ');
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

fn expectJsonWithOptions(value: anytype, options: WriteOptions, expected: []const u8) !void {
    var buffer: [1024]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);

    try writeWithOptions(&writer, value, options);

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

test "json pretty writes arrays and structs with default indent" {
    const User = struct {
        id: u64,
        name: []const u8,
        scores: [2]u8,
    };

    try expectJsonWithOptions(User{
        .id = 1,
        .name = "Grant",
        .scores = .{ 9, 10 },
    }, .{ .pretty = true },
        \\{
        \\  "id": 1,
        \\  "name": "Grant",
        \\  "scores": [
        \\    9,
        \\    10
        \\  ]
        \\}
    );
}

test "json pretty supports custom numeric indent" {
    const Nested = struct {
        values: [2]u8,
    };

    try expectJsonWithOptions(Nested{ .values = .{ 1, 2 } }, .{ .pretty = true, .indent = 4 },
        \\{
        \\    "values": [
        \\        1,
        \\        2
        \\    ]
        \\}
    );
}

test "json pretty keeps empty containers compact" {
    const Empty = struct {};
    const Container = struct {
        empty_array: [0]u8,
        empty_struct: Empty,
    };

    try expectJsonWithOptions(Container{ .empty_array = .{}, .empty_struct = .{} }, .{ .pretty = true },
        \\{
        \\  "empty_array": [],
        \\  "empty_struct": {}
        \\}
    );
}

test "json pretty supports zero-space indent and root arrays" {
    const values = [_]u16{ 1, 2 };

    try expectJsonWithOptions(values, .{ .pretty = true, .indent = 0 },
        \\[
        \\1,
        \\2
        \\]
    );
}

test "json pretty handles nested empty and non-empty containers" {
    const Empty = struct {};
    const Nested = struct {
        empty: Empty,
        values: [2]u8,
        more_empty: [0]u8,
    };

    try expectJsonWithOptions(Nested{ .empty = .{}, .values = .{ 1, 2 }, .more_empty = .{} }, .{ .pretty = true },
        \\{
        \\  "empty": {},
        \\  "values": [
        \\    1,
        \\    2
        \\  ],
        \\  "more_empty": []
        \\}
    );
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

test "json writes metadata renamed and skipped fields" {
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

    try expectJson(ApiUser{
        .user_id = 1,
        .display_name = "Grant",
        .password_hash = "secret",
    }, "{\"userId\":1,\"displayName\":\"Grant\"}");
}

test "json writes explicit field rename metadata" {
    const User = struct {
        id: u64,
        display_name: []const u8,

        pub const zerde = .{
            .fields = .{
                .display_name = .{ .rename = "name" },
            },
        };
    };

    try expectJson(User{ .id = 1, .display_name = "Grant" }, "{\"id\":1,\"name\":\"Grant\"}");
}

test "json explicit rename overrides rename_all" {
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

    try expectJson(User{ .user_id = 1, .display_name = "Grant" }, "{\"userId\":1,\"name\":\"Grant\"}");
}

test "json snake_case rename_all preserves field names" {
    const User = struct {
        user_id: u64,
        display_name: []const u8,

        pub const zerde = .{
            .rename_all = .snake_case,
        };
    };

    try expectJson(User{ .user_id = 1, .display_name = "Grant" }, "{\"user_id\":1,\"display_name\":\"Grant\"}");
}

test "json skip metadata omits fields from field count" {
    const Hidden = struct {
        password_hash: []const u8,

        pub const zerde = .{
            .fields = .{
                .password_hash = .{ .skip = true },
            },
        };
    };

    try expectJson(Hidden{ .password_hash = "secret" }, "{}");
}

test "json skip_serializing omits middle field without extra commas" {
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

    try expectJson(User{ .id = 1, .password_hash = "secret", .active = true }, "{\"id\":1,\"active\":true}");
}

test "json applies metadata to nested structs independently" {
    const User = struct {
        user_id: u64,
        display_name: []const u8,

        pub const zerde = .{
            .rename_all = .camel_case,
        };
    };
    const Session = struct {
        session_id: u64,
        user: User,

        pub const zerde = .{
            .fields = .{
                .session_id = .{ .rename = "sid" },
            },
        };
    };

    try expectJson(Session{
        .session_id = 99,
        .user = .{ .user_id = 1, .display_name = "Grant" },
    }, "{\"sid\":99,\"user\":{\"userId\":1,\"displayName\":\"Grant\"}}");
}

test "json writes enums as string tags" {
    const Color = enum { red, green, blue };

    try expectJson(Color.green, "\"green\"");
}

test "json writes tagged unions with external tags" {
    const Circle = struct { radius: u8 };
    const Rect = struct { width: u8, height: u8 };
    const Shape = union(enum) {
        circle: Circle,
        rect: Rect,
        point,
    };

    try expectJson(Shape{ .circle = .{ .radius = 10 } }, "{\"circle\":{\"radius\":10}}");
    try expectJson(Shape{ .rect = .{ .width = 3, .height = 4 } }, "{\"rect\":{\"width\":3,\"height\":4}}");
    try expectJson(Shape{ .point = {} }, "{\"point\":null}");
}

test "json writes externally tagged unions with varied payload types" {
    const Shape = union(enum) {
        count: u8,
        label: []const u8,
        scores: []const u16,
        maybe: ?u8,
        none,
    };
    const scores = [_]u16{ 2, 3, 5 };

    try expectJson(Shape{ .count = 7 }, "{\"count\":7}");
    try expectJson(Shape{ .label = "home" }, "{\"label\":\"home\"}");
    try expectJson(Shape{ .scores = scores[0..] }, "{\"scores\":[2,3,5]}");
    try expectJson(Shape{ .maybe = null }, "{\"maybe\":null}");
    try expectJson(Shape{ .none = {} }, "{\"none\":null}");
}

test "json writes adjacently tagged unions" {
    const Circle = struct { radius: u8 };
    const Shape = union(enum) {
        count: u8,
        circle: Circle,
        none,

        pub const zerde = .{ .union_repr = .adjacent };
    };

    try expectJson(Shape{ .count = 7 }, "{\"tag\":\"count\",\"value\":7}");
    try expectJson(Shape{ .circle = .{ .radius = 10 } }, "{\"tag\":\"circle\",\"value\":{\"radius\":10}}");
    try expectJson(Shape{ .none = {} }, "{\"tag\":\"none\",\"value\":null}");
}

test "json writes internally tagged unions" {
    const Circle = struct { radius: u8 };
    const Rect = struct { width: u8, height: u8 };
    const Shape = union(enum) {
        circle: Circle,
        rect: Rect,
        point,

        pub const zerde = .{ .union_repr = .internal };
    };

    try expectJson(Shape{ .circle = .{ .radius = 10 } }, "{\"tag\":\"circle\",\"radius\":10}");
    try expectJson(Shape{ .rect = .{ .width = 3, .height = 4 } }, "{\"tag\":\"rect\",\"width\":3,\"height\":4}");
    try expectJson(Shape{ .point = {} }, "{\"tag\":\"point\"}");
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

test "json writeAllocWithOptions returns pretty owned bytes" {
    const User = struct {
        id: u64,
        name: []const u8,
    };

    const bytes = try writeAllocWithOptions(std.testing.allocator, User{
        .id = 1,
        .name = "Grant",
    }, .{ .pretty = true, .indent = 1 });
    defer std.testing.allocator.free(bytes);

    try std.testing.expectEqualStrings(
        \\{
        \\ "id": 1,
        \\ "name": "Grant"
        \\}
    ,
        bytes,
    );
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

fn expectRead(comptime T: type, input: []const u8, expected: T) !void {
    const value = try readSlice(T, std.testing.allocator, input);
    defer deinitValue(T, std.testing.allocator, value);

    try std.testing.expectEqualDeep(expected, value);
}

fn expectReadFails(comptime T: type, input: []const u8) !void {
    if (readSlice(T, std.testing.allocator, input)) |value| {
        defer deinitValue(T, std.testing.allocator, value);
        return error.ExpectedReadFailure;
    } else |_| {}
}

test "json reads primitive values" {
    try expectRead(bool, " true ", true);
    try expectRead(i32, "-42", -42);
    try expectRead(u64, "42", 42);
    try expectRead(f64, "1.5", 1.5);
}

test "json reads valid number edge cases" {
    try expectRead(i64, "-0", 0);
    try expectRead(f64, "0.0", 0.0);
    try expectRead(f64, "-1.25", -1.25);
    try expectRead(f64, "1e10", 1e10);
    try expectRead(f64, "1e+10", 1e10);

    const small = try readSlice(f64, std.testing.allocator, "1E-10");
    try std.testing.expect(std.math.approxEqAbs(f64, small, 1e-10, 1e-20));
}

test "json reads strings with escapes" {
    const value = try readSlice([]const u8, std.testing.allocator, "\"quote: \\\" slash: \\\\ newline: \\n\"");
    defer deinitValue([]const u8, std.testing.allocator, value);

    try std.testing.expectEqualStrings("quote: \" slash: \\ newline: \n", value);

    const unicode = try readSlice([]const u8, std.testing.allocator, "\"\\u6771\\u4eac\\ud83d\\ude80\"");
    defer deinitValue([]const u8, std.testing.allocator, unicode);

    try std.testing.expectEqualStrings("東京🚀", unicode);
}

test "json reads valid string escape edge cases" {
    const escaped = try readSlice([]const u8, std.testing.allocator, "\"\\/\\b\\f\\u0000\\u001f\\u007f\\udbff\\udfff\"");
    defer deinitValue([]const u8, std.testing.allocator, escaped);

    const expected = "/" ++ [_]u8{ 0x08, 0x0c, 0x00, 0x1f, 0x7f } ++ "\xf4\x8f\xbf\xbf";
    try std.testing.expectEqualStrings(expected, escaped);
}

test "json validates raw utf-8 strings" {
    const valid = try readSlice([]const u8, std.testing.allocator, "\"東京市\"");
    defer deinitValue([]const u8, std.testing.allocator, valid);
    try std.testing.expectEqualStrings("東京市", valid);

    const invalid = [_]u8{ '"', 0xff, '"' };
    try std.testing.expectError(error.InvalidUtf8, readSlice([]const u8, std.testing.allocator, invalid[0..]));
}

test "json reads arrays and slices" {
    try expectRead([3]u8, "[1, 2, 3]", .{ 1, 2, 3 });

    const expected = [_]u16{ 10, 20, 30 };
    try expectRead([]const u16, "[10,20,30]", expected[0..]);
}

test "json reads top-level arrays and empty objects" {
    const Empty = struct {};

    try expectRead(Empty, "{}", .{});
    try expectRead([]const u16, "[]", &[_]u16{});
    try expectRead([]const u16,
        \\[
        \\  1,
        \\  2,
        \\  3
        \\]
    , &[_]u16{ 1, 2, 3 });
}

test "json reads optionals" {
    try expectRead(?u8, "null", null);
    try expectRead(?u8, "7", 7);

    const name = try readSlice(?[]const u8, std.testing.allocator, "\"Ada\"");
    defer deinitValue(?[]const u8, std.testing.allocator, name);

    try std.testing.expectEqualStrings("Ada", name.?);
}

test "json reads enums as string tags" {
    const Color = enum { red, green, blue };

    try expectRead(Color, "\"green\"", .green);
    try std.testing.expectError(error.InvalidEnumTag, readSlice(Color, std.testing.allocator, "\"purple\""));
}

test "json reads tagged unions with external tags" {
    const Circle = struct { radius: u8 };
    const Rect = struct { width: u8, height: u8 };
    const Shape = union(enum) {
        circle: Circle,
        rect: Rect,
        point,
    };

    const circle = try readSlice(Shape, std.testing.allocator, "{\"circle\":{\"radius\":10}}");
    try std.testing.expectEqualDeep(Shape{ .circle = .{ .radius = 10 } }, circle);

    const rect = try readSlice(Shape, std.testing.allocator, "{\"rect\":{\"width\":3,\"height\":4}}");
    try std.testing.expectEqualDeep(Shape{ .rect = .{ .width = 3, .height = 4 } }, rect);

    const point = try readSlice(Shape, std.testing.allocator, "{\"point\":null}");
    try std.testing.expectEqualDeep(Shape{ .point = {} }, point);

    try std.testing.expectError(error.UnknownUnionTag, readSlice(Shape, std.testing.allocator, "{\"triangle\":{}}"));
    try std.testing.expectError(error.DuplicateField, readSlice(Shape, std.testing.allocator, "{\"point\":null,\"circle\":{\"radius\":1}}"));
    try expectReadFails(Shape, "{\"point\":{}}");
    try expectReadFails(Shape, "{\"circle\":null}");
}

test "json reads externally tagged unions with varied payload types" {
    const Shape = union(enum) {
        count: u8,
        label: []const u8,
        scores: []const u16,
        maybe: ?u8,
        none,
    };

    const count = try readSlice(Shape, std.testing.allocator, "{\"count\":7}");
    defer deinitValue(Shape, std.testing.allocator, count);
    try std.testing.expectEqualDeep(Shape{ .count = 7 }, count);

    const label = try readSlice(Shape, std.testing.allocator, "{\"label\":\"home\"}");
    defer deinitValue(Shape, std.testing.allocator, label);
    switch (label) {
        .label => |value| try std.testing.expectEqualStrings("home", value),
        else => return error.InvalidValue,
    }

    const scores = try readSlice(Shape, std.testing.allocator, "{\"scores\":[2,3,5]}");
    defer deinitValue(Shape, std.testing.allocator, scores);
    switch (scores) {
        .scores => |value| try std.testing.expectEqualDeep(&[_]u16{ 2, 3, 5 }, value),
        else => return error.InvalidValue,
    }

    const maybe = try readSlice(Shape, std.testing.allocator, "{\"maybe\":null}");
    defer deinitValue(Shape, std.testing.allocator, maybe);
    try std.testing.expectEqualDeep(Shape{ .maybe = null }, maybe);
}

test "json reads adjacently tagged unions" {
    const Circle = struct { radius: u8 };
    const Shape = union(enum) {
        count: u8,
        circle: Circle,
        none,

        pub const zerde = .{ .union_repr = .adjacent };
    };

    const count = try readSlice(Shape, std.testing.allocator, "{\"tag\":\"count\",\"value\":7}");
    try std.testing.expectEqualDeep(Shape{ .count = 7 }, count);

    const circle = try readSlice(Shape, std.testing.allocator, "{\"tag\":\"circle\",\"value\":{\"radius\":10}}");
    try std.testing.expectEqualDeep(Shape{ .circle = .{ .radius = 10 } }, circle);

    const none = try readSlice(Shape, std.testing.allocator, "{\"tag\":\"none\",\"value\":null}");
    try std.testing.expectEqualDeep(Shape{ .none = {} }, none);

    try std.testing.expectError(error.UnknownUnionTag, readSlice(Shape, std.testing.allocator, "{\"tag\":\"triangle\",\"value\":{}}"));
    try std.testing.expectError(error.MissingUnionTag, readSlice(Shape, std.testing.allocator, "{\"value\":7,\"tag\":\"count\"}"));
    try expectReadFails(Shape, "{\"tag\":\"none\",\"value\":{}}");
    try expectReadFails(Shape, "{\"tag\":\"circle\",\"value\":null}");
}

test "json reads internally tagged unions" {
    const Circle = struct { radius: u8 };
    const Rect = struct { width: u8, height: u8 };
    const Shape = union(enum) {
        circle: Circle,
        rect: Rect,
        point,

        pub const zerde = .{ .union_repr = .internal };
    };

    const circle = try readSlice(Shape, std.testing.allocator, "{\"tag\":\"circle\",\"radius\":10}");
    try std.testing.expectEqualDeep(Shape{ .circle = .{ .radius = 10 } }, circle);

    const rect = try readSlice(Shape, std.testing.allocator, "{\"tag\":\"rect\",\"width\":3,\"height\":4}");
    try std.testing.expectEqualDeep(Shape{ .rect = .{ .width = 3, .height = 4 } }, rect);

    const point = try readSlice(Shape, std.testing.allocator, "{\"tag\":\"point\"}");
    try std.testing.expectEqualDeep(Shape{ .point = {} }, point);

    try std.testing.expectError(error.UnknownUnionTag, readSlice(Shape, std.testing.allocator, "{\"tag\":\"triangle\"}"));
    try std.testing.expectError(error.MissingUnionTag, readSlice(Shape, std.testing.allocator, "{\"radius\":10,\"tag\":\"circle\"}"));
}

test "json rejects tagged unions without a tag" {
    const Shape = union(enum) {
        circle: struct { radius: u8 },
        point,
    };

    try std.testing.expectError(error.MissingUnionTag, readSlice(Shape, std.testing.allocator, "{}"));
}

test "json reads optional tagged unions" {
    const Shape = union(enum) {
        label: []const u8,
        none,
    };

    const missing = try readSlice(?Shape, std.testing.allocator, "null");
    defer deinitValue(?Shape, std.testing.allocator, missing);
    try std.testing.expect(missing == null);

    const labeled = try readSlice(?Shape, std.testing.allocator, "{\"label\":\"home\"}");
    defer deinitValue(?Shape, std.testing.allocator, labeled);
    switch (labeled.?) {
        .label => |label| try std.testing.expectEqualStrings("home", label),
        .none => return error.InvalidValue,
    }

    const none = try readSlice(?Shape, std.testing.allocator, "{\"none\":null}");
    defer deinitValue(?Shape, std.testing.allocator, none);
    try std.testing.expectEqualDeep(Shape{ .none = {} }, none.?);
}

test "json reads structs and nested structs" {
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

    const value = try readSlice(Session, std.testing.allocator,
        \\{
        \\  "user": {"id": 1, "name": "Grant", "active": true},
        \\  "scores": [9, 10],
        \\  "nickname": null
        \\}
    );
    defer deinitValue(Session, std.testing.allocator, value);

    try std.testing.expectEqual(@as(u64, 1), value.user.id);
    try std.testing.expectEqualStrings("Grant", value.user.name);
    try std.testing.expect(value.user.active);
    try std.testing.expectEqualDeep([2]u8{ 9, 10 }, value.scores);
    try std.testing.expect(value.nickname == null);
}

test "json reads tagged union nested in struct" {
    const Shape = union(enum) {
        label: []const u8,
        none,
    };
    const Drawing = struct {
        id: u8,
        shape: Shape,
    };

    const value = try readSlice(Drawing, std.testing.allocator, "{\"id\":1,\"shape\":{\"label\":\"home\"}}");
    defer deinitValue(Drawing, std.testing.allocator, value);

    try std.testing.expectEqual(@as(u8, 1), value.id);
    switch (value.shape) {
        .label => |label| try std.testing.expectEqualStrings("home", label),
        .none => return error.InvalidValue,
    }
}

test "json reads tagged unions in slices" {
    const Shape = union(enum) {
        label: []const u8,
        none,
    };

    const values = try readSlice([]const Shape, std.testing.allocator,
        \\[
        \\  {"label":"first"},
        \\  {"none":null},
        \\  {"label":"second"}
        \\]
    );
    defer deinitValue([]const Shape, std.testing.allocator, values);

    try std.testing.expectEqual(@as(usize, 3), values.len);
    switch (values[0]) {
        .label => |label| try std.testing.expectEqualStrings("first", label),
        .none => return error.InvalidValue,
    }
    try std.testing.expectEqualDeep(Shape{ .none = {} }, values[1]);
    switch (values[2]) {
        .label => |label| try std.testing.expectEqualStrings("second", label),
        .none => return error.InvalidValue,
    }
}

test "json reads defaulted tagged union fields" {
    const Shape = union(enum) {
        label: []const u8,
        none,
    };
    const Drawing = struct {
        id: u8,
        shape: Shape = .{ .label = "default" },
    };

    const value = try readSlice(Drawing, std.testing.allocator, "{\"id\":1}");
    defer deinitValue(Drawing, std.testing.allocator, value);

    try std.testing.expectEqual(@as(u8, 1), value.id);
    switch (value.shape) {
        .label => |label| try std.testing.expectEqualStrings("default", label),
        .none => return error.InvalidValue,
    }
}

test "json read cleans up tagged union payload on extra tag" {
    const Shape = union(enum) {
        label: []const u8,
        none,
    };

    try std.testing.expectError(error.DuplicateField, readSlice(Shape, std.testing.allocator, "{\"label\":\"owned\",\"none\":null}"));
}

test "json reads whitespace-heavy formatted documents" {
    const User = struct {
        id: u64,
        name: []const u8,
        active: bool,
        scores: []const u16,
    };

    const value = try readSlice(User, std.testing.allocator,
        \\  {
        \\    "id" : 1,
        \\    "name" : "Grant",
        \\    "active" : true,
        \\    "scores" : [
        \\      9,
        \\      10,
        \\      11
        \\    ]
        \\  }
        \\  
    );
    defer deinitValue(User, std.testing.allocator, value);

    try std.testing.expectEqual(@as(u64, 1), value.id);
    try std.testing.expectEqualStrings("Grant", value.name);
    try std.testing.expect(value.active);
    try std.testing.expectEqualDeep(&[_]u16{ 9, 10, 11 }, value.scores);
}

test "json skips unknown struct fields" {
    const User = struct {
        id: u64,
        name: []const u8,
    };

    const value = try readSlice(User, std.testing.allocator,
        \\{"extra":{"nested":[true,null,"skip"]},"id":1,"name":"Ada"}
    );
    defer deinitValue(User, std.testing.allocator, value);

    try std.testing.expectEqual(@as(u64, 1), value.id);
    try std.testing.expectEqualStrings("Ada", value.name);
}

test "json skips unknown fields with mixed nested values" {
    const User = struct {
        id: u8,
    };

    const value = try readSlice(User, std.testing.allocator,
        \\{
        \\  "extra": {
        \\    "object": {"nested": [1, -2.5, "escaped\nstring", false, null]},
        \\    "array": [{}, [], "\u6771"]
        \\  },
        \\  "id": 7
        \\}
    );

    try std.testing.expectEqual(@as(u8, 7), value.id);
}

test "json reads metadata renamed fields" {
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

    const value = try readSlice(User, std.testing.allocator, "{\"userId\":1,\"name\":\"Ada\"}");
    defer deinitValue(User, std.testing.allocator, value);

    try std.testing.expectEqual(@as(u64, 1), value.user_id);
    try std.testing.expectEqualStrings("Ada", value.display_name);
}

test "json reads missing defaulted and optional fields" {
    const User = struct {
        id: u64,
        active: bool = true,
        nickname: ?[]const u8,
        label: []const u8 = "guest",
    };

    const value = try readSlice(User, std.testing.allocator, "{\"id\":1}");
    defer deinitValue(User, std.testing.allocator, value);

    try std.testing.expectEqual(@as(u64, 1), value.id);
    try std.testing.expect(value.active);
    try std.testing.expect(value.nickname == null);
    try std.testing.expectEqualStrings("guest", value.label);
}

test "json denies unknown fields when metadata requests it" {
    const User = struct {
        id: u64,

        pub const zerde = .{
            .deny_unknown_fields = true,
        };
    };

    try std.testing.expectError(error.UnknownField, readSlice(User, std.testing.allocator, "{\"id\":1,\"extra\":2}"));
}

test "json read honors skip and skip_deserializing metadata" {
    const User = struct {
        id: u8,
        password_hash: []const u8,
        token: []const u8 = "default-token",
        cached_score: u8 = 42,

        pub const zerde = .{
            .fields = .{
                .password_hash = .{ .skip_serializing = true },
                .token = .{ .skip_deserializing = true },
                .cached_score = .{ .skip = true },
            },
        };
    };

    const value = try readSlice(User, std.testing.allocator,
        \\{
        \\  "id": 1,
        \\  "password_hash": "from-input",
        \\  "token": "ignored-input",
        \\  "cached_score": 99
        \\}
    );
    defer deinitValue(User, std.testing.allocator, value);

    try std.testing.expectEqual(@as(u8, 1), value.id);
    try std.testing.expectEqualStrings("from-input", value.password_hash);
    try std.testing.expectEqualStrings("default-token", value.token);
    try std.testing.expectEqual(@as(u8, 42), value.cached_score);
}

test "json skip_deserializing required field remains missing" {
    const User = struct {
        id: u8,
        token: []const u8,

        pub const zerde = .{
            .fields = .{
                .token = .{ .skip_deserializing = true },
            },
        };
    };

    try std.testing.expectError(error.MissingField, readSlice(User, std.testing.allocator,
        \\{"id":1,"token":"ignored"}
    ));
}

test "json deny_unknown_fields respects renamed wire names" {
    const User = struct {
        user_id: u64,
        display_name: []const u8,

        pub const zerde = .{
            .rename_all = .camel_case,
            .deny_unknown_fields = true,
            .fields = .{
                .display_name = .{ .rename = "name" },
            },
        };
    };

    const value = try readSlice(User, std.testing.allocator, "{\"userId\":1,\"name\":\"Ada\"}");
    defer deinitValue(User, std.testing.allocator, value);

    try std.testing.expectEqual(@as(u64, 1), value.user_id);
    try std.testing.expectEqualStrings("Ada", value.display_name);
    try std.testing.expectError(error.UnknownField, readSlice(User, std.testing.allocator, "{\"user_id\":1,\"name\":\"Ada\"}"));
    try std.testing.expectError(error.UnknownField, readSlice(User, std.testing.allocator, "{\"userId\":1,\"name\":\"Ada\",\"extra\":true}"));
}

test "json detects duplicate skipped deserialization fields" {
    const User = struct {
        id: u8,
        token: []const u8 = "default-token",

        pub const zerde = .{
            .fields = .{
                .token = .{ .skip_deserializing = true },
            },
        };
    };

    try std.testing.expectError(error.DuplicateField, readSlice(User, std.testing.allocator,
        \\{"id":1,"token":"one","token":"two"}
    ));
}

test "json low-level decoder works with deserialize" {
    const User = struct {
        id: u8,
        name: []const u8,
    };

    var reader: std.Io.Reader = .fixed("{\"id\":7,\"name\":\"Ada\"}");
    var dec = decoder(&reader, std.testing.allocator);

    const value = try deserialize(User, std.testing.allocator, &dec);
    defer deinitValue(User, std.testing.allocator, value);
    try dec.finish();

    try std.testing.expectEqual(@as(u8, 7), value.id);
    try std.testing.expectEqualStrings("Ada", value.name);
}

test "json reader reports invalid numbers and trailing input" {
    try std.testing.expectError(error.IntegerOverflow, readSlice(u8, std.testing.allocator, "300"));
    try std.testing.expectError(error.InvalidValue, readSlice(u32, std.testing.allocator, "-1"));
    try std.testing.expectError(error.InvalidType, readSlice(u32, std.testing.allocator, "1.5"));
    try std.testing.expectError(error.InvalidJsonSyntax, readSlice(bool, std.testing.allocator, "true false"));
}

test "json reader rejects non-json number tokens" {
    try expectReadFails(f64, "NaN");
    try expectReadFails(f64, "Infinity");
    try expectReadFails(f64, "-Infinity");
    try expectReadFails(f64, ".5");
    try expectReadFails(i64, "1_000");
}

test "json reader reports type mismatches" {
    const User = struct {
        id: u8,
    };

    try expectReadFails(bool, "\"true\"");
    try expectReadFails(i64, "\"1\"");
    try expectReadFails(User, "[]");
    try expectReadFails([]const u16, "{}");
}

test "json reader reports struct duplicate missing and unknown-only fields" {
    const User = struct {
        id: u8,
        name: []const u8,
    };

    try std.testing.expectError(error.DuplicateField, readSlice(User, std.testing.allocator, "{\"id\":1,\"id\":2,\"name\":\"Ada\"}"));
    try std.testing.expectError(error.MissingField, readSlice(User, std.testing.allocator, "{\"id\":1}"));
    try std.testing.expectError(error.MissingField, readSlice(User, std.testing.allocator, "{\"extra\":1}"));
    try std.testing.expectError(error.MissingField, readSlice(User, std.testing.allocator, "{\"id\":1,\"name_extra\":\"Ada\"}"));
}

test "json read cleans up owned fields on missing required field" {
    const User = struct {
        name: []const u8,
        id: u8,
    };

    try std.testing.expectError(error.MissingField, readSlice(User, std.testing.allocator, "{\"name\":\"Ada\"}"));
}

test "json read cleans up owned fields on duplicate field" {
    const User = struct {
        name: []const u8,
    };

    try std.testing.expectError(error.DuplicateField, readSlice(User, std.testing.allocator,
        \\{"name":"Ada","name":"Grace"}
    ));
}

test "json read cleans up owned array elements on invalid length" {
    try std.testing.expectError(error.InvalidArrayLength, readSlice([2][]const u8, std.testing.allocator,
        \\[
        \\  "one",
        \\  "two",
        \\  "three"
        \\]
    ));

    try std.testing.expectError(error.InvalidArrayLength, readSlice([2][]const u8, std.testing.allocator,
        \\[
        \\  "one"
        \\]
    ));
}

test "json reader rejects malformed literals and trailing tokens" {
    try expectReadFails(bool, "");
    try expectReadFails(bool, "tru");
    try expectReadFails(bool, "truex");
    try expectReadFails(bool, "false null");
    try expectReadFails(?u8, "nul");
    try expectReadFails(?u8, "nullx");
}

test "json reader rejects malformed numbers" {
    try expectReadFails(i64, "+1");
    try expectReadFails(i64, "--1");
    try expectReadFails(i64, "-");
    try expectReadFails(i64, "01");
    try expectReadFails(f64, "1.");
    try expectReadFails(f64, "1e");
    try expectReadFails(f64, "1e+");
    try expectReadFails(f64, "1e-");
}

test "json reader rejects malformed strings" {
    try expectReadFails([]const u8, "\"unterminated");
    try expectReadFails([]const u8, "\"bad\\q\"");
    try expectReadFails([]const u8, "\"bad\x01control\"");
    try expectReadFails([]const u8, "\"bad\\u12\"");
    try expectReadFails([]const u8, "\"bad\\u12xz\"");
    try expectReadFails([]const u8, "\"bad\\udc00\"");
    try expectReadFails([]const u8, "\"bad\\ud800x\"");
    try expectReadFails([]const u8, "\"bad\\ud800\\u0041\"");
}

test "json reader rejects malformed arrays" {
    try expectReadFails([]const u16, "[");
    try expectReadFails([]const u16, "[1");
    try expectReadFails([]const u16, "[1 2]");
    try expectReadFails([]const u16, "[1,]");
    try expectReadFails([]const u16, "[,1]");
    try expectReadFails([]const u16, "[1,,2]");
}

test "json reader rejects malformed objects" {
    const User = struct {
        id: u8,
        name: []const u8,
    };

    try expectReadFails(User, "{");
    try expectReadFails(User, "{\"id\":1");
    try expectReadFails(User, "{id:1,\"name\":\"Ada\"}");
    try expectReadFails(User, "{\"id\" 1,\"name\":\"Ada\"}");
    try expectReadFails(User, "{\"id\":1 \"name\":\"Ada\"}");
    try expectReadFails(User, "{\"id\":1,\"name\":\"Ada\",}");
    try expectReadFails(User, "{\"id\":1,,\"name\":\"Ada\"}");
}

test "json reader rejects excessive nesting while skipping values" {
    const User = struct {
        id: u8,
    };

    var buffer: [256]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    try writer.writeAll("{\"extra\":");
    for (0..65) |_| try writer.writeByte('[');
    for (0..65) |_| try writer.writeByte(']');
    try writer.writeAll(",\"id\":1}");

    try std.testing.expectError(error.NestingTooDeep, readSlice(User, std.testing.allocator, writer.buffered()));
}

test "json compact and pretty roundtrip basic structs" {
    const User = struct {
        id: u64,
        name: []const u8,
        scores: []const u16,
        nickname: ?[]const u8,
    };

    const scores = [_]u16{ 9, 10, 11 };
    const user = User{ .id = 1, .name = "Grant", .scores = scores[0..], .nickname = "g" };

    const compact = try writeAlloc(std.testing.allocator, user);
    defer std.testing.allocator.free(compact);
    const compact_parsed = try readSlice(User, std.testing.allocator, compact);
    defer deinitValue(User, std.testing.allocator, compact_parsed);
    try std.testing.expectEqualDeep(user, compact_parsed);

    const pretty = try writeAllocWithOptions(std.testing.allocator, user, .{ .pretty = true });
    defer std.testing.allocator.free(pretty);
    const pretty_parsed = try readSlice(User, std.testing.allocator, pretty);
    defer deinitValue(User, std.testing.allocator, pretty_parsed);
    try std.testing.expectEqualDeep(user, pretty_parsed);
}

test "json roundtrips tagged unions with owned payloads" {
    const Shape = union(enum) {
        label: []const u8,
        scores: []const u16,
        none,
    };
    const scores = [_]u16{ 2, 3, 5 };

    const labeled = Shape{ .label = "home" };
    const labeled_bytes = try writeAlloc(std.testing.allocator, labeled);
    defer std.testing.allocator.free(labeled_bytes);
    const labeled_parsed = try readSlice(Shape, std.testing.allocator, labeled_bytes);
    defer deinitValue(Shape, std.testing.allocator, labeled_parsed);
    try std.testing.expectEqualDeep(labeled, labeled_parsed);

    const scored = Shape{ .scores = scores[0..] };
    const scored_bytes = try writeAlloc(std.testing.allocator, scored);
    defer std.testing.allocator.free(scored_bytes);
    const scored_parsed = try readSlice(Shape, std.testing.allocator, scored_bytes);
    defer deinitValue(Shape, std.testing.allocator, scored_parsed);
    try std.testing.expectEqualDeep(scored, scored_parsed);

    const none = Shape{ .none = {} };
    const none_bytes = try writeAlloc(std.testing.allocator, none);
    defer std.testing.allocator.free(none_bytes);
    const none_parsed = try readSlice(Shape, std.testing.allocator, none_bytes);
    defer deinitValue(Shape, std.testing.allocator, none_parsed);
    try std.testing.expectEqualDeep(none, none_parsed);
}

test "json field with hook serializes and deserializes" {
    const OffsetTimestamp = struct {
        pub fn serialize(value: i64, enc: anytype) !void {
            try enc.emitInt(value + 1000);
        }

        pub fn deserialize(comptime T: type, allocator: std.mem.Allocator, dec: anytype) !T {
            _ = allocator;
            return (try dec.readInt(T)) - 1000;
        }
    };

    const Event = struct {
        name: []const u8,
        created_at: i64,

        pub const zerde = .{
            .fields = .{
                .created_at = .{ .with = OffsetTimestamp },
            },
        };
    };

    try expectJson(Event{ .name = "deploy", .created_at = 42 }, "{\"name\":\"deploy\",\"created_at\":1042}");

    const parsed = try readSlice(Event, std.testing.allocator, "{\"name\":\"deploy\",\"created_at\":1042}");
    defer deinitValue(Event, std.testing.allocator, parsed);

    try std.testing.expectEqualStrings("deploy", parsed.name);
    try std.testing.expectEqual(@as(i64, 42), parsed.created_at);
}

test "json field hook serializes small binary packet to and from bytes" {
    const Packet = struct {
        opcode: u8,
        flags: u8,
        payload_len: u16,
    };

    const PacketBytes = struct {
        pub fn serialize(value: Packet, enc: anytype) !void {
            try enc.beginSeq(4);
            try enc.emitInt(value.opcode);
            try enc.emitInt(value.flags);
            try enc.emitInt(@as(u8, @intCast(value.payload_len >> 8)));
            try enc.emitInt(@as(u8, @intCast(value.payload_len & 0xff)));
            try enc.endSeq();
        }

        pub fn deserialize(comptime T: type, allocator: std.mem.Allocator, dec: anytype) !T {
            _ = allocator;

            _ = try dec.beginSeq();
            if (!try dec.hasNextSeqElem()) return error.InvalidArrayLength;
            const opcode = try dec.readInt(u8);
            if (!try dec.hasNextSeqElem()) return error.InvalidArrayLength;
            const flags = try dec.readInt(u8);
            if (!try dec.hasNextSeqElem()) return error.InvalidArrayLength;
            const len_hi = try dec.readInt(u8);
            if (!try dec.hasNextSeqElem()) return error.InvalidArrayLength;
            const len_lo = try dec.readInt(u8);
            if (try dec.hasNextSeqElem()) return error.InvalidArrayLength;
            try dec.endSeq();

            return T{
                .opcode = opcode,
                .flags = flags,
                .payload_len = (@as(u16, len_hi) << 8) | len_lo,
            };
        }
    };

    const Message = struct {
        id: u8,
        packet: Packet,

        pub const zerde = .{
            .fields = .{
                .packet = .{ .with = PacketBytes },
            },
        };
    };

    const message = Message{
        .id = 9,
        .packet = .{ .opcode = 0xa1, .flags = 0x05, .payload_len = 0x1234 },
    };

    try expectJson(message, "{\"id\":9,\"packet\":[161,5,18,52]}");

    const parsed = try readSlice(Message, std.testing.allocator, "{\"id\":9,\"packet\":[161,5,18,52]}");
    try std.testing.expectEqualDeep(message, parsed);
}

test "json serializes same small packet message without custom hooks" {
    const Packet = struct {
        opcode: u8,
        flags: u8,
        payload_len: u16,
    };

    const Message = struct {
        id: u8,
        packet: Packet,
    };

    const message = Message{
        .id = 9,
        .packet = .{ .opcode = 0xa1, .flags = 0x05, .payload_len = 0x1234 },
    };

    try expectJson(message, "{\"id\":9,\"packet\":{\"opcode\":161,\"flags\":5,\"payload_len\":4660}}");

    const parsed = try readSlice(Message, std.testing.allocator, "{\"id\":9,\"packet\":{\"opcode\":161,\"flags\":5,\"payload_len\":4660}}");
    try std.testing.expectEqualDeep(message, parsed);
}

test "json field split hooks can serialize or deserialize independently" {
    const BoolAsYesNo = struct {
        pub fn serialize(value: bool, enc: anytype) !void {
            try enc.emitString(if (value) "yes" else "no");
        }
    };

    const YesNoAsBool = struct {
        pub fn deserialize(comptime T: type, allocator: std.mem.Allocator, dec: anytype) !T {
            const value = try dec.readString(allocator);
            defer allocator.free(value);
            if (std.mem.eql(u8, value, "yes")) return true;
            if (std.mem.eql(u8, value, "no")) return false;
            return error.InvalidValue;
        }
    };

    const Outbound = struct {
        active: bool,

        pub const zerde = .{
            .fields = .{
                .active = .{ .serialize_with = BoolAsYesNo },
            },
        };
    };

    const Inbound = struct {
        active: bool,

        pub const zerde = .{
            .fields = .{
                .active = .{ .deserialize_with = YesNoAsBool },
            },
        };
    };

    try expectJson(Outbound{ .active = true }, "{\"active\":\"yes\"}");

    const parsed = try readSlice(Inbound, std.testing.allocator, "{\"active\":\"no\"}");
    try std.testing.expect(!parsed.active);
}

test "json type-native serialize hook takes precedence over fields" {
    const Value = struct {
        raw: u8,

        pub fn zerdeSerialize(self: @This(), enc: anytype) !void {
            try enc.emitInt(self.raw + 1);
        }
    };

    try expectJson(Value{ .raw = 7 }, "8");
}

test "json type-native deserialize hook takes precedence over fields" {
    const Value = struct {
        raw: u8,

        pub fn zerdeDeserialize(allocator: std.mem.Allocator, dec: anytype) !@This() {
            _ = allocator;
            return .{ .raw = (try dec.readInt(u8)) - 1 };
        }
    };

    const parsed = try readSlice(Value, std.testing.allocator, "8");
    try std.testing.expectEqual(@as(u8, 7), parsed.raw);
}
