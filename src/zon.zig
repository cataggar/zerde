//! Zig Object Notation format support.

const std = @import("std");

const serialize = @import("serialize.zig").serialize;
const deserialize = @import("deserialize.zig").deserialize;
const base64 = @import("base64.zig");
const deinitValue = @import("deinit.zig").deinit;
const number = @import("number.zig");

const ZonNumber = number.Parser(.{
    .decimal_float = true,
    .exponent = true,
    .sign = .positive_and_negative,
    .digit_separator = '_',
    .prefixed_integers = .{ .binary = true, .octal = true, .hex = true },
    .special_floats = true,
    .integer_to_float = true,
});

/// ZON writer configuration.
pub const WriteOptions = struct {
    pretty: bool = false,
    indent: usize = 4,
};

/// Serializes `value` as compact ZON to `writer`.
pub fn write(writer: *std.Io.Writer, value: anytype) !void {
    try writeWithOptions(writer, value, .{});
}

/// Serializes `value` as ZON to `writer` with explicit writer options.
pub fn writeWithOptions(writer: *std.Io.Writer, value: anytype, options: WriteOptions) !void {
    var enc = encoderWithOptions(writer, options);
    try serialize(value, &enc);
    try enc.finish();
}

/// Serializes `value` as ZON and returns allocator-owned bytes.
pub fn writeAlloc(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    return try writeAllocWithOptions(allocator, value, .{});
}

/// Serializes `value` as ZON with explicit writer options and returns allocator-owned bytes.
pub fn writeAllocWithOptions(allocator: std.mem.Allocator, value: anytype, options: WriteOptions) ![]u8 {
    var allocating = std.Io.Writer.Allocating.init(allocator);
    errdefer allocating.deinit();

    try writeWithOptions(&allocating.writer, value, options);
    return try allocating.toOwnedSlice();
}

/// Returns a low-level ZON encoder for use with `zerde.serialize`.
pub fn encoder(writer: *std.Io.Writer) Encoder {
    return encoderWithOptions(writer, .{});
}

/// Returns a low-level ZON encoder with explicit writer options.
pub fn encoderWithOptions(writer: *std.Io.Writer, options: WriteOptions) Encoder {
    return .{ .writer = writer, .options = options };
}

/// Deserializes ZON from `reader` into `T`.
pub fn read(comptime T: type, allocator: std.mem.Allocator, reader: *std.Io.Reader) !T {
    var dec = decoder(reader, allocator);
    const value = try deserialize(T, allocator, &dec);
    errdefer deinitValue(T, allocator, value);
    try dec.finish();
    return value;
}

/// Deserializes ZON from `input` into `T`.
pub fn readSlice(comptime T: type, allocator: std.mem.Allocator, input: []const u8) !T {
    var reader: std.Io.Reader = .fixed(input);
    return try read(T, allocator, &reader);
}

/// Returns a low-level ZON decoder for use with `zerde.deserialize`.
pub fn decoder(reader: *std.Io.Reader, allocator: std.mem.Allocator) Decoder {
    return .{ .reader = reader, .allocator = allocator };
}

/// ZON value kinds reported by `Decoder.peek`.
pub const Kind = enum {
    null,
    bool,
    int,
    float,
    string,
    enum_,
    seq,
    struct_,
};

/// Low-level ZON encoder used by the generic serializer.
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

    /// Emits a ZON null value.
    pub fn emitNull(self: *Self) !void {
        try self.beforeValue();
        try self.writer.writeAll("null");
    }

    /// Emits a ZON boolean value.
    pub fn emitBool(self: *Self, value: bool) !void {
        try self.beforeValue();
        try self.writer.writeAll(if (value) "true" else "false");
    }

    /// Emits a ZON integer value.
    pub fn emitInt(self: *Self, value: anytype) !void {
        try self.beforeValue();
        try self.writer.print("{d}", .{value});
    }

    /// Emits a ZON floating-point value.
    pub fn emitFloat(self: *Self, value: anytype) !void {
        try self.beforeValue();
        try self.writer.print("{d}", .{value});
    }

    /// Emits a ZON string value.
    pub fn emitString(self: *Self, value: []const u8) !void {
        if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidUtf8;
        try self.beforeValue();
        try self.writeEscapedString(value);
    }

    /// Emits raw bytes as a base64 ZON string.
    pub fn emitBytes(self: *Self, value: []const u8) !void {
        try self.beforeValue();
        try self.writer.writeByte('"');
        try base64.writeEncoded(self.writer, value);
        try self.writer.writeByte('"');
    }

    /// Emits a ZON enum literal for `value`.
    pub fn emitEnum(self: *Self, comptime T: type, value: T) !void {
        try self.emitEnumTag(@tagName(value));
    }

    /// Emits a ZON enum literal by tag name.
    pub fn emitEnumTag(self: *Self, tag: []const u8) !void {
        try self.beforeValue();
        try self.writeDotName(tag);
    }

    /// Begins a ZON array literal.
    pub fn beginSeq(self: *Self, len: ?usize) !void {
        _ = len;
        try self.ensureCanPush();
        try self.beforeValue();
        try self.writer.writeAll(".{");
        self.push(.seq);
    }

    /// Ends the current ZON array literal.
    pub fn endSeq(self: *Self) !void {
        const frame = self.currentFrame(.seq);
        if (self.options.pretty) {
            if (frame.count != 0) try self.writeNewlineAndIndent(self.stack_len - 1);
        } else if (frame.count != 0) {
            try self.writer.writeByte(' ');
        }
        self.pop(.seq);
        try self.writer.writeByte('}');
    }

    /// Begins a ZON struct literal.
    pub fn beginStruct(self: *Self, comptime T: type, field_count: usize) !void {
        _ = T;
        _ = field_count;
        try self.ensureCanPush();
        try self.beforeValue();
        try self.writer.writeAll(".{");
        self.push(.object);
    }

    /// Emits the next ZON struct field name.
    pub fn emitFieldName(self: *Self, name: []const u8) !void {
        const frame = self.currentFrame(.object);
        if (frame.expecting_field_value) return error.InvalidZonEncoderState;

        if (frame.count != 0) try self.writer.writeByte(',');
        if (self.options.pretty) {
            try self.writeNewlineAndIndent(self.stack_len);
        } else {
            try self.writer.writeByte(' ');
        }

        try self.writeDotName(name);
        try self.writer.writeAll(" = ");
        frame.count += 1;
        frame.expecting_field_value = true;
    }

    /// Ends the current ZON struct literal.
    pub fn endStruct(self: *Self) !void {
        const frame = self.currentFrame(.object);
        if (frame.expecting_field_value) return error.InvalidZonEncoderState;
        if (self.options.pretty) {
            if (frame.count != 0) try self.writeNewlineAndIndent(self.stack_len - 1);
        } else if (frame.count != 0) {
            try self.writer.writeByte(' ');
        }
        self.pop(.object);
        try self.writer.writeByte('}');
    }

    /// Verifies that the ZON document was completely written.
    pub fn finish(self: *Self) !void {
        if (self.root_count == 0) return error.IncompleteZonDocument;
        if (self.stack_len == 0) return;

        const frame = &self.stack[self.stack_len - 1];
        if (frame.container == .object and frame.expecting_field_value) return error.InvalidZonEncoderState;
        return error.IncompleteZonDocument;
    }

    fn beforeValue(self: *Self) !void {
        if (self.stack_len == 0) {
            if (self.root_count != 0) return error.InvalidZonEncoderState;
            self.root_count += 1;
            return;
        }

        const frame = &self.stack[self.stack_len - 1];
        switch (frame.container) {
            .seq => {
                if (frame.count != 0) try self.writer.writeByte(',');
                if (self.options.pretty) {
                    try self.writeNewlineAndIndent(self.stack_len);
                } else {
                    try self.writer.writeByte(' ');
                }
                frame.count += 1;
            },
            .object => {
                if (!frame.expecting_field_value) return error.InvalidZonEncoderState;
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

    fn writeNewlineAndIndent(self: *Self, depth: usize) !void {
        try self.writer.writeByte('\n');
        for (0..depth * self.options.indent) |_| try self.writer.writeByte(' ');
    }

    fn writeDotName(self: *Self, name: []const u8) !void {
        try self.writer.writeByte('.');
        if (isIdentifier(name) and !isKeyword(name)) {
            try self.writer.writeAll(name);
        } else {
            try self.writer.writeByte('@');
            try self.writeEscapedString(name);
        }
    }

    fn writeEscapedString(self: *Self, value: []const u8) !void {
        try self.writer.writeByte('"');
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
                    try self.writer.writeAll("\\x");
                    try self.writer.writeByte(digits[byte >> 4]);
                    try self.writer.writeByte(digits[byte & 0x0f]);
                    run_start = i + 1;
                },
                else => {},
            }
        }
        try self.writer.writeAll(value[run_start..]);
        try self.writer.writeByte('"');
    }

    fn writeEscapedByte(self: *Self, value: []const u8, run_start: *usize, index: usize, escaped: []const u8) !void {
        try self.writer.writeAll(value[run_start.*..index]);
        try self.writer.writeAll(escaped);
        run_start.* = index + 1;
    }
};

/// Low-level ZON decoder used by the generic deserializer.
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

    /// Returns the kind of the next ZON value.
    pub fn peek(self: *Self) !Kind {
        try self.skipWhitespaceAndComments();
        const byte = (try self.peekByte()) orelse return error.EndOfStream;
        return switch (byte) {
            'n' => if (try self.peekLiteral("null")) .null else .float,
            't', 'f' => .bool,
            '"' => .string,
            '.' => blk: {
                if ((try self.peekBufferedByte(1)) == '{') break :blk .struct_;
                break :blk .enum_;
            },
            '+', '-', '0'...'9', 'i' => .int,
            else => error.InvalidZonSyntax,
        };
    }

    /// Reads a ZON null value.
    pub fn readNull(self: *Self) !void {
        try self.expectLiteral("null");
    }

    /// Reads a ZON boolean value.
    pub fn readBool(self: *Self) !bool {
        try self.skipWhitespaceAndComments();
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

    /// Reads a ZON integer into `T`.
    pub fn readInt(self: *Self, comptime T: type) !T {
        const token = try self.readNumber();
        defer token.deinit(self.allocator);
        return switch (token) {
            .int => |integer| try ZonNumber.readInt(T, integer),
            .float => error.InvalidType,
        };
    }

    /// Reads a ZON number into floating-point type `T`.
    pub fn readFloat(self: *Self, comptime T: type) !T {
        const token = try self.readNumber();
        defer token.deinit(self.allocator);
        return try ZonNumber.readFloat(T, token);
    }

    /// Reads a ZON string as allocator-owned UTF-8 bytes.
    pub fn readString(self: *Self, allocator: std.mem.Allocator) ![]u8 {
        try self.skipWhitespaceAndComments();
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
                0x00...0x1f => return error.InvalidZonSyntax,
                else => try out.writer.writeByte(byte),
            }
        }
    }

    /// Reads a ZON enum literal into `T`.
    pub fn readEnum(self: *Self, comptime T: type) !T {
        const enum_info = @typeInfo(T).@"enum";
        const tag = try self.readDotName(self.allocator);
        defer self.allocator.free(tag);

        inline for (enum_info.fields) |field| {
            if (std.mem.eql(u8, tag, field.name)) return @field(T, field.name);
        }
        return error.InvalidEnumTag;
    }

    /// Reads a ZON enum literal tag as allocator-owned bytes for event consumers.
    pub fn readEnumTag(self: *Self, allocator: std.mem.Allocator) ![]u8 {
        return try self.readDotName(allocator);
    }

    /// Begins reading a ZON array literal.
    pub fn beginSeq(self: *Self) !?usize {
        try self.ensureCanPush();
        try self.skipWhitespaceAndComments();
        try self.expectByte('.');
        try self.expectByte('{');
        self.push(.seq);
        return null;
    }

    /// Returns whether the current ZON array has another element.
    pub fn hasNextSeqElem(self: *Self) !bool {
        const frame = self.currentFrame(.seq);
        try self.skipWhitespaceAndComments();

        if (frame.first) {
            frame.first = false;
            if (try self.consumeIf('}')) return false;
            return true;
        }

        if (try self.consumeIf('}')) return false;
        try self.expectByte(',');
        try self.skipWhitespaceAndComments();
        if (try self.consumeIf('}')) return false;
        return true;
    }

    /// Ends the current ZON array literal.
    pub fn endSeq(self: *Self) !void {
        self.pop(.seq);
    }

    /// Begins reading a ZON struct literal.
    pub fn beginStruct(self: *Self, comptime T: type) !void {
        _ = T;
        try self.ensureCanPush();
        try self.skipWhitespaceAndComments();
        try self.expectByte('.');
        try self.expectByte('{');
        self.push(.object);
    }

    /// Begins reading a ZON struct literal for event consumers. ZON does not
    /// expose the field count before the literal has been read.
    pub fn beginStructEvent(self: *Self) !?usize {
        try self.beginStruct(void);
        return null;
    }

    /// Returns the next struct field name as allocator-owned bytes, or null when done.
    pub fn nextField(self: *Self) !?[]u8 {
        const frame = self.currentFrame(.object);
        try self.skipWhitespaceAndComments();

        if (frame.first) {
            frame.first = false;
            if (try self.consumeIf('}')) return null;
        } else {
            if (try self.consumeIf('}')) return null;
            try self.expectByte(',');
            try self.skipWhitespaceAndComments();
            if (try self.consumeIf('}')) return null;
        }

        const name = try self.readDotName(self.allocator);
        errdefer self.allocator.free(name);
        try self.skipWhitespaceAndComments();
        try self.expectByte('=');
        return name;
    }

    /// Ends the current ZON struct literal.
    pub fn endStruct(self: *Self) !void {
        self.pop(.object);
    }

    /// Skips one complete ZON value.
    pub fn skipValue(self: *Self) anyerror!void {
        switch (try self.peek()) {
            .null => try self.readNull(),
            .bool => _ = try self.readBool(),
            .int, .float => {
                const token = try self.readNumber();
                token.deinit(self.allocator);
            },
            .string => {
                const value = try self.readString(self.allocator);
                self.allocator.free(value);
            },
            .enum_ => {
                const value = try self.readDotName(self.allocator);
                self.allocator.free(value);
            },
            .seq, .struct_ => try self.skipAggregate(),
        }
    }

    /// Verifies that the ZON document was completely read.
    pub fn finish(self: *Self) !void {
        try self.skipWhitespaceAndComments();
        if (self.stack_len != 0) return error.InvalidZonDecoderState;
        if ((try self.peekByte()) != null) return error.InvalidZonSyntax;
    }

    fn skipAggregate(self: *Self) anyerror!void {
        try self.expectByte('.');
        try self.expectByte('{');
        try self.skipWhitespaceAndComments();
        if (try self.consumeIf('}')) return;

        const object = try self.aggregateLooksLikeObject();
        while (true) {
            if (object) {
                const field = try self.readDotName(self.allocator);
                self.allocator.free(field);
                try self.skipWhitespaceAndComments();
                try self.expectByte('=');
            }

            try self.skipValue();
            try self.skipWhitespaceAndComments();
            if (try self.consumeIf('}')) return;
            try self.expectByte(',');
            try self.skipWhitespaceAndComments();
            if (try self.consumeIf('}')) return;
        }
    }

    fn aggregateLooksLikeObject(self: *Self) !bool {
        var offset: usize = 0;
        if ((try self.peekBufferedByte(offset)) != '.') return false;
        offset += 1;

        const first = (try self.peekBufferedByte(offset)) orelse return false;
        if (first == '@') {
            offset += 1;
            if ((try self.peekBufferedByte(offset)) != '"') return false;
            offset += 1;
            while (try self.peekBufferedByte(offset)) |byte| : (offset += 1) {
                if (byte == '\\') {
                    offset += 2;
                    continue;
                }
                if (byte == '"') {
                    offset += 1;
                    break;
                }
            } else return false;
        } else if (isIdentifierStart(first)) {
            offset += 1;
            while (try self.peekBufferedByte(offset)) |byte| {
                if (!isIdentifierContinue(byte)) break;
                offset += 1;
            }
        } else {
            return false;
        }

        while (try self.peekBufferedByte(offset)) |byte| : (offset += 1) {
            switch (byte) {
                ' ', '\n', '\r', '\t' => {},
                '=' => return true,
                else => return false,
            }
        }
        return false;
    }

    fn skipWhitespaceAndComments(self: *Self) !void {
        while (true) {
            while (try self.peekByte()) |byte| {
                switch (byte) {
                    ' ', '\n', '\r', '\t' => _ = try self.reader.takeByte(),
                    else => break,
                }
            }

            if ((try self.peekByte()) != '/') return;
            const next = (try self.peekBufferedByte(1)) orelse return;
            if (next == '/') {
                _ = try self.reader.takeByte();
                _ = try self.reader.takeByte();
                while (true) {
                    const byte = self.reader.takeByte() catch |err| switch (err) {
                        error.EndOfStream => return,
                        else => |e| return e,
                    };
                    if (byte == '\n') break;
                }
            } else if (next == '*') {
                _ = try self.reader.takeByte();
                _ = try self.reader.takeByte();
                var prev: u8 = 0;
                while (true) {
                    const byte = try self.reader.takeByte();
                    if (prev == '*' and byte == '/') break;
                    prev = byte;
                }
            } else {
                return;
            }
        }
    }

    fn expectLiteral(self: *Self, literal: []const u8) !void {
        try self.skipWhitespaceAndComments();
        for (literal) |expected| try self.expectByte(expected);
    }

    fn expectByte(self: *Self, expected: u8) !void {
        const actual = try self.reader.takeByte();
        if (actual != expected) return error.InvalidZonSyntax;
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

    fn peekLiteral(self: *Self, literal: []const u8) !bool {
        for (literal, 0..) |expected, i| {
            if ((try self.peekBufferedByte(i)) != expected) return false;
        }
        return true;
    }

    fn peekByte(self: *Self) !?u8 {
        return self.reader.peekByte() catch |err| switch (err) {
            error.EndOfStream => null,
            else => |e| return e,
        };
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

    fn readNumber(self: *Self) !number.Token {
        try self.skipWhitespaceAndComments();

        var out = std.Io.Writer.Allocating.init(self.allocator);
        errdefer out.deinit();

        while (try self.peekByte()) |byte| {
            if (isValueDelimiter(byte)) break;
            try out.writer.writeByte(try self.reader.takeByte());
        }

        const bytes = try out.toOwnedSlice();
        return ZonNumber.parseOwned(self.allocator, bytes) catch |err| switch (err) {
            error.InvalidNumberSyntax => error.InvalidZonSyntax,
            else => |e| return e,
        };
    }

    fn readDotName(self: *Self, allocator: std.mem.Allocator) ![]u8 {
        try self.skipWhitespaceAndComments();
        try self.expectByte('.');

        if ((try self.peekByte()) == '@') {
            _ = try self.reader.takeByte();
            return try self.readString(allocator);
        }

        var out = std.Io.Writer.Allocating.init(allocator);
        errdefer out.deinit();

        const first = (try self.peekByte()) orelse return error.EndOfStream;
        if (!isIdentifierStart(first)) return error.InvalidZonSyntax;
        try out.writer.writeByte(try self.reader.takeByte());

        while (try self.peekByte()) |byte| {
            if (!isIdentifierContinue(byte)) break;
            try out.writer.writeByte(try self.reader.takeByte());
        }

        return try out.toOwnedSlice();
    }

    fn readEscape(self: *Self, writer: *std.Io.Writer) !void {
        const escape = try self.reader.takeByte();
        switch (escape) {
            '"' => try writer.writeByte('"'),
            '\\' => try writer.writeByte('\\'),
            'n' => try writer.writeByte('\n'),
            'r' => try writer.writeByte('\r'),
            't' => try writer.writeByte('\t'),
            'x' => {
                const hi = hexValue(try self.reader.takeByte()) orelse return error.InvalidZonSyntax;
                const lo = hexValue(try self.reader.takeByte()) orelse return error.InvalidZonSyntax;
                try writer.writeByte(@intCast((hi << 4) | lo));
            },
            'u' => try self.readUnicodeEscape(writer),
            else => return error.InvalidZonSyntax,
        }
    }

    fn readUnicodeEscape(self: *Self, writer: *std.Io.Writer) !void {
        try self.expectByte('{');
        var value: u21 = 0;
        var count: usize = 0;
        while (true) {
            const byte = try self.reader.takeByte();
            if (byte == '}') break;
            const digit = hexValue(byte) orelse return error.InvalidZonSyntax;
            if (count == 6) return error.InvalidZonSyntax;
            value = (value << 4) | digit;
            count += 1;
        }
        if (count == 0) return error.InvalidZonSyntax;

        var buffer: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(value, &buffer) catch return error.InvalidUtf8;
        try writer.writeAll(buffer[0..len]);
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

fn isIdentifier(value: []const u8) bool {
    if (value.len == 0 or !isIdentifierStart(value[0])) return false;
    for (value[1..]) |byte| if (!isIdentifierContinue(byte)) return false;
    return true;
}

fn isIdentifierStart(byte: u8) bool {
    return (byte >= 'a' and byte <= 'z') or (byte >= 'A' and byte <= 'Z') or byte == '_';
}

fn isIdentifierContinue(byte: u8) bool {
    return isIdentifierStart(byte) or (byte >= '0' and byte <= '9');
}

fn isKeyword(value: []const u8) bool {
    const keywords = [_][]const u8{
        "addrspace", "align",       "allowzero",   "and",     "anyframe",    "anytype",        "asm",      "async",
        "await",     "break",       "callconv",    "catch",   "comptime",    "const",          "continue", "defer",
        "else",      "enum",        "errdefer",    "error",   "export",      "extern",         "fn",       "for",
        "if",        "inline",      "linksection", "noalias", "noinline",    "nosuspend",      "opaque",   "or",
        "orelse",    "packed",      "pub",         "resume",  "return",      "struct",         "suspend",  "switch",
        "test",      "threadlocal", "try",         "union",   "unreachable", "usingnamespace", "var",      "volatile",
        "while",     "true",        "false",       "null",
    };

    for (keywords) |keyword| if (std.mem.eql(u8, value, keyword)) return true;
    return false;
}

fn isValueDelimiter(byte: u8) bool {
    return switch (byte) {
        ' ', '\n', '\r', '\t', ',', '}', '/' => true,
        else => false,
    };
}

fn hexValue(byte: u8) ?u21 {
    return switch (byte) {
        '0'...'9' => byte - '0',
        'a'...'f' => byte - 'a' + 10,
        'A'...'F' => byte - 'A' + 10,
        else => null,
    };
}

fn expectZon(value: anytype, expected: []const u8) !void {
    var buffer: [1024]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);

    try write(&writer, value);

    try std.testing.expectEqualStrings(expected, writer.buffered());
}

fn expectRead(comptime T: type, input: []const u8, expected: T) !void {
    const value = try readSlice(T, std.testing.allocator, input);
    defer deinitValue(T, std.testing.allocator, value);

    try std.testing.expectEqualDeep(expected, value);
}

test "zon writes primitive values" {
    try expectZon(null, "null");
    try expectZon(true, "true");
    try expectZon(@as(i32, -42), "-42");
    try expectZon(@as(u64, 42), "42");
    try expectZon(@as(f64, 1.5), "1.5");
}

test "zon writes strings arrays structs and enums" {
    const Color = enum { red, green, blue };
    const User = struct {
        id: u64,
        name: []const u8,
        color: Color,
        scores: [2]u8,
        nickname: ?[]const u8,
    };

    try expectZon(Color.green, ".green");
    try expectZon(User{
        .id = 1,
        .name = "Ada",
        .color = .green,
        .scores = .{ 9, 10 },
        .nickname = null,
    }, ".{ .id = 1, .name = \"Ada\", .color = .green, .scores = .{ 9, 10 }, .nickname = null }");
}

test "zon writes escaped field names" {
    const User = struct {
        display_name: []const u8,

        pub const zerde = .{
            .fields = .{
                .display_name = .{ .rename = "display-name" },
            },
        };
    };

    try expectZon(User{ .display_name = "Ada" }, ".{ .@\"display-name\" = \"Ada\" }");
}

test "zon writes keyword field names as escaped identifiers" {
    const User = struct {
        kind: []const u8,

        pub const zerde = .{
            .fields = .{
                .kind = .{ .rename = "struct" },
            },
        };
    };

    try expectZon(User{ .kind = "user" }, ".{ .@\"struct\" = \"user\" }");
}

test "zon writes keyword and non-identifier enum tags as escaped identifiers" {
    const Keyword = enum { @"struct", @"with-dash" };

    try expectZon(Keyword.@"struct", ".@\"struct\"");
    try expectZon(Keyword.@"with-dash", ".@\"with-dash\"");
}

test "zon reads primitive values" {
    try expectRead(bool, " true ", true);
    try expectRead(i32, "-42", -42);
    try expectRead(u64, "+42", 42);
    try expectRead(u8, "0b1010", 10);
    try expectRead(u8, "0o17", 15);
    try expectRead(u8, "0xff", 255);
    try expectRead(f64, "1_000.5", 1000.5);

    const positive_inf = try readSlice(f64, std.testing.allocator, "inf");
    try std.testing.expect(std.math.isPositiveInf(positive_inf));

    const negative_inf = try readSlice(f64, std.testing.allocator, "-inf");
    try std.testing.expect(std.math.isNegativeInf(negative_inf));

    const nan = try readSlice(f64, std.testing.allocator, "nan");
    try std.testing.expect(std.math.isNan(nan));
}

test "zon reads string escapes" {
    const value = try readSlice([]const u8, std.testing.allocator, "\"line\\nhex\\x21 rocket \\u{1f680}\"");
    defer deinitValue([]const u8, std.testing.allocator, value);

    try std.testing.expectEqualStrings("line\nhex! rocket " ++ "\xf0\x9f\x9a\x80", value);
}

test "zon reads escaped field names and enum tags" {
    const Keyword = enum { @"struct", @"with-dash" };
    const User = struct {
        display_name: []const u8,
        kind: Keyword,

        pub const zerde = .{
            .fields = .{
                .display_name = .{ .rename = "display-name" },
                .kind = .{ .rename = "struct" },
            },
        };
    };

    const value = try readSlice(User, std.testing.allocator, ".{ .@\"display-name\" = \"Ada\", .@\"struct\" = .@\"with-dash\" }");
    defer deinitValue(User, std.testing.allocator, value);

    try std.testing.expectEqualStrings("Ada", value.display_name);
    try std.testing.expectEqual(Keyword.@"with-dash", value.kind);
}

test "zon reads strings arrays structs optionals and enums" {
    const Color = enum { red, green, blue };
    const User = struct {
        id: u64,
        name: []const u8,
        color: Color,
        scores: []const u16,
        nickname: ?[]const u8,
    };

    const value = try readSlice(User, std.testing.allocator,
        \\.{
        \\    .id = 1,
        \\    .name = "Ada",
        \\    .color = .green,
        \\    .scores = .{ 9, 10, 11, },
        \\    .nickname = null,
        \\}
    );
    defer deinitValue(User, std.testing.allocator, value);

    try std.testing.expectEqual(@as(u64, 1), value.id);
    try std.testing.expectEqualStrings("Ada", value.name);
    try std.testing.expectEqual(Color.green, value.color);
    try std.testing.expectEqualDeep(&[_]u16{ 9, 10, 11 }, value.scores);
    try std.testing.expect(value.nickname == null);
}

test "zon roundtrips tagged unions with owned payloads" {
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

test "zon writes pretty nested containers" {
    const User = struct {
        id: u8,
        scores: [2]u8,
    };

    const bytes = try writeAllocWithOptions(std.testing.allocator, User{ .id = 1, .scores = .{ 9, 10 } }, .{ .pretty = true });
    defer std.testing.allocator.free(bytes);

    try std.testing.expectEqualStrings(
        \\.{
        \\    .id = 1,
        \\    .scores = .{
        \\        9,
        \\        10
        \\    }
        \\}
    , bytes);
}

test "zon writes and reads bytes as base64 strings" {
    const Blob = struct {
        wrapped: base64.Bytes,
        raw: []const u8,

        pub const zerde = .{
            .fields = .{
                .raw = .{ .bytes = true },
            },
        };
    };
    const raw = [_]u8{ 0, 1, 2, 3 };
    const blob = Blob{ .wrapped = .{ .value = raw[0..] }, .raw = raw[0..] };

    const encoded = try writeAlloc(std.testing.allocator, blob);
    defer std.testing.allocator.free(encoded);
    try std.testing.expectEqualStrings(".{ .wrapped = \"AAECAw==\", .raw = \"AAECAw==\" }", encoded);

    const parsed = try readSlice(Blob, std.testing.allocator, encoded);
    defer deinitValue(Blob, std.testing.allocator, parsed);
    try std.testing.expectEqualSlices(u8, raw[0..], parsed.wrapped.value);
    try std.testing.expectEqualSlices(u8, raw[0..], parsed.raw);
}

test "zon skips unknown fields and comments" {
    const User = struct {
        id: u8,
        name: []const u8,
    };

    const value = try readSlice(User, std.testing.allocator,
        \\.{
        \\    // skipped recursively
        \\    .extra = .{ .nested = .{ true, null, .green } },
        \\    .id = 7,
        \\    .name = "Ada",
        \\}
    );
    defer deinitValue(User, std.testing.allocator, value);

    try std.testing.expectEqual(@as(u8, 7), value.id);
    try std.testing.expectEqualStrings("Ada", value.name);
}

test "zon reads comments adjacent to numeric values" {
    const User = struct {
        id: u8,
        next: u8,
    };

    const value = try readSlice(User, std.testing.allocator,
        \\.{
        \\    .id = 7// line comment without separating whitespace
        \\    , .next = 8/* block comment without separating whitespace */,
        \\}
    );

    try std.testing.expectEqual(@as(u8, 7), value.id);
    try std.testing.expectEqual(@as(u8, 8), value.next);
}
