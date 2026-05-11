//! MessagePack format support.

const std = @import("std");

const serialize = @import("serialize.zig").serialize;
const deserialize = @import("deserialize.zig").deserialize;
const deinitValue = @import("deinit.zig").deinit;
const events = @import("events.zig");
const Timestamp = @import("datetime.zig").Timestamp;

/// MessagePack writer configuration. Reserved for future profile options.
pub const WriteOptions = struct {};

/// Opaque MessagePack extension value for low-level custom hooks.
pub const Extension = struct {
    /// Application or predefined extension type identifier.
    type_id: i8,
    /// Allocator-owned extension payload bytes.
    data: []u8,

    /// Frees the extension payload returned by `Decoder.readExtension`.
    pub fn deinit(self: Extension, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
    }
};

/// Serializes `value` as MessagePack to `writer`.
pub fn write(writer: *std.Io.Writer, value: anytype) !void {
    var enc = encoder(writer);
    try serialize(value, &enc);
    try enc.finish();
}

/// Serializes `value` as MessagePack to `writer` with explicit options.
pub fn writeWithOptions(allocator: std.mem.Allocator, writer: *std.Io.Writer, value: anytype, options: WriteOptions) !void {
    _ = allocator;
    _ = options;
    var enc = encoder(writer);
    try serialize(value, &enc);
    try enc.finish();
}

/// Serializes `value` as MessagePack and returns allocator-owned bytes.
pub fn writeAlloc(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    return try writeAllocWithOptions(allocator, value, .{});
}

/// Serializes `value` as MessagePack with explicit options and returns allocator-owned bytes.
pub fn writeAllocWithOptions(allocator: std.mem.Allocator, value: anytype, options: WriteOptions) ![]u8 {
    var allocating = std.Io.Writer.Allocating.init(allocator);
    errdefer allocating.deinit();

    try writeWithOptions(allocator, &allocating.writer, value, options);
    return try allocating.toOwnedSlice();
}

/// Deserializes MessagePack from `reader` into `T`.
pub fn read(comptime T: type, allocator: std.mem.Allocator, reader: *std.Io.Reader) !T {
    var dec = decoder(reader, allocator);
    const value = try deserialize(T, allocator, &dec);
    errdefer deinitValue(T, allocator, value);
    try dec.finish();
    return value;
}

/// Deserializes MessagePack from `input` into `T`.
pub fn readSlice(comptime T: type, allocator: std.mem.Allocator, input: []const u8) !T {
    var reader: std.Io.Reader = .fixed(input);
    return try read(T, allocator, &reader);
}

/// Returns a low-level MessagePack encoder for use with `zerde.serialize`.
pub fn encoder(writer: *std.Io.Writer) Encoder {
    return .{ .writer = writer };
}

/// Returns a low-level MessagePack decoder for use with `zerde.deserialize`.
pub fn decoder(reader: *std.Io.Reader, allocator: std.mem.Allocator) Decoder {
    return .{ .reader = reader, .allocator = allocator };
}

/// MessagePack value kinds reported by `Decoder.peek`.
pub const Kind = enum {
    /// MessagePack nil.
    null,
    /// MessagePack boolean.
    bool,
    /// MessagePack integer.
    int,
    /// MessagePack 32-bit or 64-bit float.
    float,
    /// MessagePack str value.
    string,
    /// MessagePack bin value.
    binary,
    /// MessagePack array value.
    seq,
    /// MessagePack map value.
    struct_,
    /// MessagePack extension value.
    extension,
};

/// Low-level MessagePack encoder used by the generic serializer.
pub const Encoder = struct {
    const Self = @This();
    const max_depth = 64;

    const Container = enum {
        seq,
        map,
    };

    const Frame = struct {
        container: Container,
        len: usize,
        count: usize = 0,
        expecting_field_value: bool = false,
    };

    /// Destination writer receiving encoded MessagePack bytes.
    writer: *std.Io.Writer,
    /// Container stack used to validate nested arrays and maps.
    stack: [max_depth]Frame = undefined,
    /// Number of active container frames in `stack`.
    stack_len: usize = 0,
    /// Number of root values emitted so far.
    root_count: usize = 0,

    /// Emits the MessagePack nil value.
    pub fn emitNull(self: *Self) !void {
        try self.beforeValue();
        try self.writer.writeByte(0xc0);
    }

    /// Emits a MessagePack boolean value.
    pub fn emitBool(self: *Self, value: bool) !void {
        try self.beforeValue();
        try self.writer.writeByte(if (value) 0xc3 else 0xc2);
    }

    /// Emits an integer using the smallest valid MessagePack integer format.
    pub fn emitInt(self: *Self, value: anytype) !void {
        try self.beforeValue();
        try self.writeInteger(value);
    }

    /// Emits a 32-bit or 64-bit MessagePack float.
    pub fn emitFloat(self: *Self, value: anytype) !void {
        try self.beforeValue();

        const T = @TypeOf(value);
        const Float = switch (@typeInfo(T)) {
            .comptime_float => f64,
            .float => if (@bitSizeOf(T) <= 32) f32 else f64,
            else => @compileError("MessagePack floats require a float value"),
        };
        const float_value: Float = value;
        const Int = std.meta.Int(.unsigned, @bitSizeOf(Float));
        const raw: Int = @bitCast(float_value);

        try self.writer.writeByte(if (Float == f32) 0xca else 0xcb);
        try writeBig(self.writer, Int, raw);
    }

    /// Emits a UTF-8 string with the MessagePack str family.
    pub fn emitString(self: *Self, value: []const u8) !void {
        if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidUtf8;
        try self.beforeValue();
        try self.writeStrHeader(value.len);
        try self.writer.writeAll(value);
    }

    /// Emits raw bytes with the MessagePack bin family.
    pub fn emitBytes(self: *Self, value: []const u8) !void {
        try self.beforeValue();
        try self.writeBinHeader(value.len);
        try self.writer.writeAll(value);
    }

    /// Emits an enum tag as a MessagePack string.
    pub fn emitEnumTag(self: *Self, tag: []const u8) !void {
        try self.emitString(tag);
    }

    /// Begins a MessagePack array with a known element count.
    pub fn beginSeq(self: *Self, len: ?usize) !void {
        const actual_len = len orelse return error.MissingMessagePackLength;
        try self.ensureCanPush();
        try self.beforeValue();
        try self.writeArrayHeader(actual_len);
        self.push(.{ .container = .seq, .len = actual_len });
    }

    /// Ends the current MessagePack array.
    pub fn endSeq(self: *Self) !void {
        const frame = self.current(.seq);
        if (frame.count != frame.len) return error.InvalidMessagePackEncoderState;
        self.pop(.seq);
    }

    /// Begins a MessagePack map for a struct value.
    pub fn beginStruct(self: *Self, comptime T: type, field_count: usize) !void {
        _ = T;
        try self.ensureCanPush();
        try self.beforeValue();
        try self.writeMapHeader(field_count);
        self.push(.{ .container = .map, .len = field_count });
    }

    /// Emits the next MessagePack map key for a struct field.
    pub fn emitFieldName(self: *Self, name: []const u8) !void {
        const frame = self.current(.map);
        if (frame.expecting_field_value) return error.InvalidMessagePackEncoderState;
        if (frame.count == frame.len) return error.InvalidMessagePackEncoderState;
        if (!std.unicode.utf8ValidateSlice(name)) return error.InvalidUtf8;

        try self.writeStrHeader(name.len);
        try self.writer.writeAll(name);
        frame.count += 1;
        frame.expecting_field_value = true;
    }

    /// Ends the current MessagePack map for a struct value.
    pub fn endStruct(self: *Self) !void {
        const frame = self.current(.map);
        if (frame.expecting_field_value or frame.count != frame.len) return error.InvalidMessagePackEncoderState;
        self.pop(.map);
    }

    /// Emits a low-level MessagePack extension value for custom hooks.
    pub fn emitExtension(self: *Self, type_id: i8, data: []const u8) !void {
        try self.beforeValue();
        try self.writeExtHeader(type_id, data.len);
        try self.writer.writeAll(data);
    }

    /// Emits a MessagePack-compatible event extension value.
    pub fn emitEventExtension(self: *Self, extension: events.Extension) !void {
        switch (extension) {
            .opaque_ => |raw| {
                if (raw.namespace != .msgpack) return error.UnsupportedEventKind;
                const type_id = switch (raw.id) {
                    .signed => |value| std.math.cast(i8, value) orelse return error.IntegerOverflow,
                    .unsigned => |value| std.math.cast(i8, value) orelse return error.IntegerOverflow,
                };
                try self.emitExtension(type_id, raw.data);
            },
            else => return error.UnsupportedEventKind,
        }
    }

    /// Emits the predefined MessagePack timestamp extension type (-1).
    pub fn emitTimestamp(self: *Self, value: Timestamp) !void {
        if (value.nanoseconds > 999_999_999) return error.InvalidMessagePackTimestamp;
        try self.beforeValue();

        if (value.seconds >= 0 and value.seconds < (@as(i64, 1) << 34)) {
            const seconds: u64 = @intCast(value.seconds);
            const data64 = (@as(u64, value.nanoseconds) << 34) | seconds;
            if ((data64 & 0xffffffff00000000) == 0) {
                try self.writer.writeByte(0xd6);
                try self.writer.writeByte(0xff);
                try writeBig(self.writer, u32, @intCast(data64));
            } else {
                try self.writer.writeByte(0xd7);
                try self.writer.writeByte(0xff);
                try writeBig(self.writer, u64, data64);
            }
            return;
        }

        try self.writer.writeByte(0xc7);
        try self.writer.writeByte(12);
        try self.writer.writeByte(0xff);
        try writeBig(self.writer, u32, value.nanoseconds);
        try writeBig(self.writer, i64, value.seconds);
    }

    /// Verifies that exactly one complete MessagePack root value was emitted.
    pub fn finish(self: *Self) !void {
        if (self.root_count == 0) return error.IncompleteMessagePackDocument;
        if (self.stack_len == 0) return;

        const frame = &self.stack[self.stack_len - 1];
        if (frame.container == .map and frame.expecting_field_value) return error.InvalidMessagePackEncoderState;
        return error.IncompleteMessagePackDocument;
    }

    fn beforeValue(self: *Self) !void {
        if (self.stack_len == 0) {
            if (self.root_count != 0) return error.InvalidMessagePackEncoderState;
            self.root_count += 1;
            return;
        }

        const frame = &self.stack[self.stack_len - 1];
        switch (frame.container) {
            .seq => {
                if (frame.count == frame.len) return error.InvalidMessagePackEncoderState;
                frame.count += 1;
            },
            .map => {
                if (!frame.expecting_field_value) return error.InvalidMessagePackEncoderState;
                frame.expecting_field_value = false;
            },
        }
    }

    fn writeInteger(self: *Self, value: anytype) !void {
        const T = @TypeOf(value);
        switch (@typeInfo(T)) {
            .comptime_int => {
                if (value >= 0) {
                    try self.writeUnsigned(std.math.cast(u64, value) orelse return error.IntegerOverflow);
                } else {
                    try self.writeSigned(std.math.cast(i64, value) orelse return error.IntegerOverflow);
                }
            },
            .int => |int_info| switch (int_info.signedness) {
                .signed => try self.writeSigned(std.math.cast(i64, value) orelse return error.IntegerOverflow),
                .unsigned => try self.writeUnsigned(std.math.cast(u64, value) orelse return error.IntegerOverflow),
            },
            else => @compileError("MessagePack integers require an integer value"),
        }
    }

    fn writeUnsigned(self: *Self, value: u64) !void {
        if (value <= 0x7f) {
            try self.writer.writeByte(@intCast(value));
        } else if (value <= std.math.maxInt(u8)) {
            try self.writer.writeByte(0xcc);
            try self.writer.writeByte(@intCast(value));
        } else if (value <= std.math.maxInt(u16)) {
            try self.writer.writeByte(0xcd);
            try writeBig(self.writer, u16, @intCast(value));
        } else if (value <= std.math.maxInt(u32)) {
            try self.writer.writeByte(0xce);
            try writeBig(self.writer, u32, @intCast(value));
        } else {
            try self.writer.writeByte(0xcf);
            try writeBig(self.writer, u64, value);
        }
    }

    fn writeSigned(self: *Self, value: i64) !void {
        if (value >= 0) return try self.writeUnsigned(@intCast(value));

        if (value >= -32) {
            try self.writer.writeByte(@bitCast(@as(i8, @intCast(value))));
        } else if (value >= std.math.minInt(i8)) {
            try self.writer.writeByte(0xd0);
            try self.writer.writeByte(@bitCast(@as(i8, @intCast(value))));
        } else if (value >= std.math.minInt(i16)) {
            try self.writer.writeByte(0xd1);
            try writeBig(self.writer, i16, @intCast(value));
        } else if (value >= std.math.minInt(i32)) {
            try self.writer.writeByte(0xd2);
            try writeBig(self.writer, i32, @intCast(value));
        } else {
            try self.writer.writeByte(0xd3);
            try writeBig(self.writer, i64, value);
        }
    }

    fn writeStrHeader(self: *Self, len: usize) !void {
        if (len <= 31) {
            try self.writer.writeByte(0xa0 | @as(u8, @intCast(len)));
        } else if (len <= std.math.maxInt(u8)) {
            try self.writer.writeByte(0xd9);
            try self.writer.writeByte(@intCast(len));
        } else if (len <= std.math.maxInt(u16)) {
            try self.writer.writeByte(0xda);
            try writeBig(self.writer, u16, @intCast(len));
        } else if (len <= std.math.maxInt(u32)) {
            try self.writer.writeByte(0xdb);
            try writeBig(self.writer, u32, @intCast(len));
        } else return error.IntegerOverflow;
    }

    fn writeBinHeader(self: *Self, len: usize) !void {
        if (len <= std.math.maxInt(u8)) {
            try self.writer.writeByte(0xc4);
            try self.writer.writeByte(@intCast(len));
        } else if (len <= std.math.maxInt(u16)) {
            try self.writer.writeByte(0xc5);
            try writeBig(self.writer, u16, @intCast(len));
        } else if (len <= std.math.maxInt(u32)) {
            try self.writer.writeByte(0xc6);
            try writeBig(self.writer, u32, @intCast(len));
        } else return error.IntegerOverflow;
    }

    fn writeArrayHeader(self: *Self, len: usize) !void {
        if (len <= 15) {
            try self.writer.writeByte(0x90 | @as(u8, @intCast(len)));
        } else if (len <= std.math.maxInt(u16)) {
            try self.writer.writeByte(0xdc);
            try writeBig(self.writer, u16, @intCast(len));
        } else if (len <= std.math.maxInt(u32)) {
            try self.writer.writeByte(0xdd);
            try writeBig(self.writer, u32, @intCast(len));
        } else return error.IntegerOverflow;
    }

    fn writeMapHeader(self: *Self, len: usize) !void {
        if (len <= 15) {
            try self.writer.writeByte(0x80 | @as(u8, @intCast(len)));
        } else if (len <= std.math.maxInt(u16)) {
            try self.writer.writeByte(0xde);
            try writeBig(self.writer, u16, @intCast(len));
        } else if (len <= std.math.maxInt(u32)) {
            try self.writer.writeByte(0xdf);
            try writeBig(self.writer, u32, @intCast(len));
        } else return error.IntegerOverflow;
    }

    fn writeExtHeader(self: *Self, type_id: i8, len: usize) !void {
        switch (len) {
            1 => try self.writer.writeByte(0xd4),
            2 => try self.writer.writeByte(0xd5),
            4 => try self.writer.writeByte(0xd6),
            8 => try self.writer.writeByte(0xd7),
            16 => try self.writer.writeByte(0xd8),
            else => if (len <= std.math.maxInt(u8)) {
                try self.writer.writeByte(0xc7);
                try self.writer.writeByte(@intCast(len));
            } else if (len <= std.math.maxInt(u16)) {
                try self.writer.writeByte(0xc8);
                try writeBig(self.writer, u16, @intCast(len));
            } else if (len <= std.math.maxInt(u32)) {
                try self.writer.writeByte(0xc9);
                try writeBig(self.writer, u32, @intCast(len));
            } else return error.IntegerOverflow,
        }
        try self.writer.writeByte(@bitCast(type_id));
    }

    fn ensureCanPush(self: *Self) !void {
        if (self.stack_len == self.stack.len) return error.NestingTooDeep;
    }

    fn push(self: *Self, frame: Frame) void {
        std.debug.assert(self.stack_len != self.stack.len);
        self.stack[self.stack_len] = frame;
        self.stack_len += 1;
    }

    fn pop(self: *Self, expected: Container) void {
        std.debug.assert(self.stack_len != 0);
        std.debug.assert(self.stack[self.stack_len - 1].container == expected);
        self.stack_len -= 1;
    }

    fn current(self: *Self, expected: Container) *Frame {
        std.debug.assert(self.stack_len != 0);
        const frame = &self.stack[self.stack_len - 1];
        std.debug.assert(frame.container == expected);
        return frame;
    }
};

/// Low-level MessagePack decoder used by the generic deserializer.
pub const Decoder = struct {
    const Self = @This();
    const max_depth = 64;

    const Container = enum {
        seq,
        map,
    };

    const Frame = struct {
        container: Container,
        len: usize,
        index: usize = 0,
    };

    const Integer = union(enum) {
        unsigned: u64,
        signed: i64,
    };

    const RawKind = enum { string, binary, string_or_binary };

    const ExtHeader = struct {
        type_id: i8,
        len: usize,
    };

    /// Source reader providing encoded MessagePack bytes.
    reader: *std.Io.Reader,
    /// Allocator used for owned strings, byte slices, and field names.
    allocator: std.mem.Allocator,
    /// Container stack used to validate nested arrays and maps.
    stack: [max_depth]Frame = undefined,
    /// Number of active container frames in `stack`.
    stack_len: usize = 0,

    /// Returns the kind of the next MessagePack value without consuming it.
    pub fn peek(self: *Self) !Kind {
        const byte = (try self.peekByte()) orelse return error.EndOfStream;
        return kindFromByte(byte) orelse error.InvalidMessagePackSyntax;
    }

    /// Reads a MessagePack nil value.
    pub fn readNull(self: *Self) !void {
        const byte = try self.reader.takeByte();
        if (byte != 0xc0) return error.InvalidType;
    }

    /// Reads a MessagePack boolean value.
    pub fn readBool(self: *Self) !bool {
        return switch (try self.reader.takeByte()) {
            0xc2 => false,
            0xc3 => true,
            else => error.InvalidType,
        };
    }

    /// Reads a MessagePack integer and converts it to `T`.
    pub fn readInt(self: *Self, comptime T: type) !T {
        const integer = try self.readInteger();
        return switch (integer) {
            .unsigned => |value| std.math.cast(T, value) orelse error.IntegerOverflow,
            .signed => |value| std.math.cast(T, value) orelse error.IntegerOverflow,
        };
    }

    /// Reads a MessagePack float, or an integer coerced to `T`.
    pub fn readFloat(self: *Self, comptime T: type) !T {
        switch (try self.peek()) {
            .float => {},
            .int => {
                const integer = try self.readInteger();
                return switch (integer) {
                    .unsigned => |value| @floatFromInt(value),
                    .signed => |value| @floatFromInt(value),
                };
            },
            else => return error.InvalidType,
        }

        const tag = try self.reader.takeByte();
        return switch (tag) {
            0xca => @floatCast(@as(f32, @bitCast(try readBig(self.reader, u32)))),
            0xcb => @floatCast(@as(f64, @bitCast(try readBig(self.reader, u64)))),
            else => error.InvalidType,
        };
    }

    /// Reads a MessagePack str value as allocator-owned UTF-8 bytes.
    pub fn readString(self: *Self, allocator: std.mem.Allocator) ![]u8 {
        const bytes = try self.readRaw(allocator, .string);
        errdefer allocator.free(bytes);
        if (!std.unicode.utf8ValidateSlice(bytes)) return error.InvalidUtf8;
        return bytes;
    }

    /// Reads a MessagePack bin value, or a str value for compatibility, as owned bytes.
    pub fn readBytes(self: *Self, allocator: std.mem.Allocator) ![]u8 {
        return try self.readRaw(allocator, .string_or_binary);
    }

    /// Begins reading a MessagePack array and returns its element count.
    pub fn beginSeq(self: *Self) !?usize {
        const len = try self.readArrayHeader();
        try self.push(.{ .container = .seq, .len = len });
        return len;
    }

    /// Returns whether the current MessagePack array has another element.
    pub fn hasNextSeqElem(self: *Self) !bool {
        const frame = self.current(.seq);
        if (frame.index == frame.len) return false;
        frame.index += 1;
        return true;
    }

    /// Ends the current MessagePack array.
    pub fn endSeq(self: *Self) !void {
        const frame = self.current(.seq);
        if (frame.index != frame.len) return error.InvalidMessagePackDecoderState;
        self.pop(.seq);
    }

    /// Begins reading a MessagePack map for a struct value.
    pub fn beginStruct(self: *Self, comptime T: type) !void {
        _ = T;
        _ = try self.beginStructEvent();
    }

    /// Begins reading a MessagePack map for event consumers and returns its
    /// field count.
    pub fn beginStructEvent(self: *Self) !?usize {
        const len = try self.readMapHeader();
        try self.push(.{ .container = .map, .len = len });
        return len;
    }

    /// Reads the next MessagePack map key as an allocator-owned field name.
    pub fn nextField(self: *Self) !?[]u8 {
        const frame = self.current(.map);
        if (frame.index == frame.len) return null;
        frame.index += 1;
        return try self.readString(self.allocator);
    }

    /// Ends the current MessagePack map for a struct value.
    pub fn endStruct(self: *Self) !void {
        const frame = self.current(.map);
        if (frame.index != frame.len) return error.InvalidMessagePackDecoderState;
        self.pop(.map);
    }

    /// Skips the next complete MessagePack value, including nested containers.
    pub fn skipValue(self: *Self) !void {
        switch (try self.peek()) {
            .null => try self.readNull(),
            .bool => _ = try self.readBool(),
            .int => _ = try self.readInteger(),
            .float => _ = try self.readFloat(f64),
            .string => {
                const value = try self.readRaw(self.allocator, .string);
                self.allocator.free(value);
            },
            .binary => {
                const value = try self.readRaw(self.allocator, .binary);
                self.allocator.free(value);
            },
            .seq => {
                _ = try self.beginSeq();
                while (try self.hasNextSeqElem()) try self.skipValue();
                try self.endSeq();
            },
            .struct_ => {
                const len = try self.readMapHeader();
                for (0..len) |_| {
                    try self.skipValue();
                    try self.skipValue();
                }
            },
            .extension => try self.skipExtension(),
        }
    }

    /// Reads a low-level MessagePack extension value. Caller owns `data`.
    pub fn readExtension(self: *Self, allocator: std.mem.Allocator) !Extension {
        const header = try self.readExtHeader();
        const data = try allocator.alloc(u8, header.len);
        errdefer allocator.free(data);
        try self.readExact(data);
        return .{ .type_id = header.type_id, .data = data };
    }

    /// Reads a MessagePack extension value as an event extension.
    pub fn readEventExtension(self: *Self, allocator: std.mem.Allocator) !events.Extension {
        const extension = try self.readExtension(allocator);
        return events.Extension.msgpack(extension.type_id, extension.data);
    }

    /// Reads the predefined MessagePack timestamp extension type (-1).
    pub fn readTimestamp(self: *Self) !Timestamp {
        const header = try self.readExtHeader();
        if (header.type_id != -1) return error.InvalidMessagePackTimestamp;

        return switch (header.len) {
            4 => .{ .seconds = try readBig(self.reader, u32), .nanoseconds = 0 },
            8 => blk: {
                const data = try readBig(self.reader, u64);
                const nanoseconds: u32 = @intCast(data >> 34);
                if (nanoseconds > 999_999_999) return error.InvalidMessagePackTimestamp;
                break :blk .{
                    .seconds = @intCast(data & 0x00000003ffffffff),
                    .nanoseconds = nanoseconds,
                };
            },
            12 => blk: {
                const nanoseconds = try readBig(self.reader, u32);
                if (nanoseconds > 999_999_999) return error.InvalidMessagePackTimestamp;
                break :blk .{
                    .seconds = try readBig(self.reader, i64),
                    .nanoseconds = nanoseconds,
                };
            },
            else => error.InvalidMessagePackTimestamp,
        };
    }

    /// Verifies that the reader is at the end of a complete MessagePack document.
    pub fn finish(self: *Self) !void {
        if (self.stack_len != 0) return error.InvalidMessagePackDecoderState;
        if ((try self.peekByte()) != null) return error.InvalidMessagePackTrailingData;
    }

    fn readInteger(self: *Self) !Integer {
        const first = try self.reader.takeByte();
        return switch (first) {
            0x00...0x7f => .{ .unsigned = first },
            0xe0...0xff => .{ .signed = @as(i8, @bitCast(first)) },
            0xcc => .{ .unsigned = try self.reader.takeByte() },
            0xcd => .{ .unsigned = try readBig(self.reader, u16) },
            0xce => .{ .unsigned = try readBig(self.reader, u32) },
            0xcf => .{ .unsigned = try readBig(self.reader, u64) },
            0xd0 => .{ .signed = @as(i8, @bitCast(try self.reader.takeByte())) },
            0xd1 => .{ .signed = try readBig(self.reader, i16) },
            0xd2 => .{ .signed = try readBig(self.reader, i32) },
            0xd3 => .{ .signed = try readBig(self.reader, i64) },
            else => error.InvalidType,
        };
    }

    fn readRaw(self: *Self, allocator: std.mem.Allocator, expected: RawKind) ![]u8 {
        const first = try self.reader.takeByte();
        const len = switch (first) {
            0xa0...0xbf => blk: {
                if (expected == .binary) return error.InvalidType;
                break :blk @as(usize, first & 0x1f);
            },
            0xd9 => blk: {
                if (expected == .binary) return error.InvalidType;
                break :blk @as(usize, try self.reader.takeByte());
            },
            0xda => blk: {
                if (expected == .binary) return error.InvalidType;
                break :blk @as(usize, try readBig(self.reader, u16));
            },
            0xdb => blk: {
                if (expected == .binary) return error.InvalidType;
                break :blk try lengthToUsize(try readBig(self.reader, u32));
            },
            0xc4 => blk: {
                if (expected == .string) return error.InvalidType;
                break :blk @as(usize, try self.reader.takeByte());
            },
            0xc5 => blk: {
                if (expected == .string) return error.InvalidType;
                break :blk @as(usize, try readBig(self.reader, u16));
            },
            0xc6 => blk: {
                if (expected == .string) return error.InvalidType;
                break :blk try lengthToUsize(try readBig(self.reader, u32));
            },
            else => return error.InvalidType,
        };

        const out = try allocator.alloc(u8, len);
        errdefer allocator.free(out);
        try self.readExact(out);
        return out;
    }

    fn readArrayHeader(self: *Self) !usize {
        const first = try self.reader.takeByte();
        return switch (first) {
            0x90...0x9f => first & 0x0f,
            0xdc => try lengthToUsize(try readBig(self.reader, u16)),
            0xdd => try lengthToUsize(try readBig(self.reader, u32)),
            else => error.InvalidType,
        };
    }

    fn readMapHeader(self: *Self) !usize {
        const first = try self.reader.takeByte();
        return switch (first) {
            0x80...0x8f => first & 0x0f,
            0xde => try lengthToUsize(try readBig(self.reader, u16)),
            0xdf => try lengthToUsize(try readBig(self.reader, u32)),
            else => error.InvalidType,
        };
    }

    fn readExtHeader(self: *Self) !ExtHeader {
        const first = try self.reader.takeByte();
        const len: usize = switch (first) {
            0xd4 => 1,
            0xd5 => 2,
            0xd6 => 4,
            0xd7 => 8,
            0xd8 => 16,
            0xc7 => try self.reader.takeByte(),
            0xc8 => try lengthToUsize(try readBig(self.reader, u16)),
            0xc9 => try lengthToUsize(try readBig(self.reader, u32)),
            else => return error.InvalidType,
        };
        return .{ .type_id = @bitCast(try self.reader.takeByte()), .len = len };
    }

    fn skipExtension(self: *Self) !void {
        const header = try self.readExtHeader();
        try self.skipBytes(header.len);
    }

    fn skipBytes(self: *Self, len: usize) !void {
        for (0..len) |_| _ = try self.reader.takeByte();
    }

    fn readExact(self: *Self, out: []u8) !void {
        for (out) |*byte| byte.* = try self.reader.takeByte();
    }

    fn peekByte(self: *Self) !?u8 {
        return self.reader.peekByte() catch |err| switch (err) {
            error.EndOfStream => null,
            else => |e| return e,
        };
    }

    fn push(self: *Self, frame: Frame) !void {
        if (self.stack_len == self.stack.len) return error.NestingTooDeep;
        self.stack[self.stack_len] = frame;
        self.stack_len += 1;
    }

    fn pop(self: *Self, expected: Container) void {
        std.debug.assert(self.stack_len != 0);
        std.debug.assert(self.stack[self.stack_len - 1].container == expected);
        self.stack_len -= 1;
    }

    fn current(self: *Self, expected: Container) *Frame {
        std.debug.assert(self.stack_len != 0);
        const frame = &self.stack[self.stack_len - 1];
        std.debug.assert(frame.container == expected);
        return frame;
    }
};

fn kindFromByte(byte: u8) ?Kind {
    return switch (byte) {
        0x00...0x7f, 0xcc...0xd3, 0xe0...0xff => .int,
        0x80...0x8f, 0xde, 0xdf => .struct_,
        0x90...0x9f, 0xdc, 0xdd => .seq,
        0xa0...0xbf, 0xd9...0xdb => .string,
        0xc0 => .null,
        0xc2, 0xc3 => .bool,
        0xc4...0xc6 => .binary,
        0xc7...0xc9, 0xd4...0xd8 => .extension,
        0xca, 0xcb => .float,
        else => null,
    };
}

fn writeBig(writer: *std.Io.Writer, comptime T: type, value: T) !void {
    const Unsigned = std.meta.Int(.unsigned, @bitSizeOf(T));
    const raw: Unsigned = @bitCast(value);
    var bytes: [@sizeOf(T)]u8 = undefined;
    std.mem.writeInt(Unsigned, &bytes, raw, .big);
    try writer.writeAll(&bytes);
}

fn readBig(reader: *std.Io.Reader, comptime T: type) !T {
    const Unsigned = std.meta.Int(.unsigned, @bitSizeOf(T));
    var bytes: [@sizeOf(T)]u8 = undefined;
    for (&bytes) |*byte| byte.* = try reader.takeByte();
    const raw = std.mem.readInt(Unsigned, &bytes, .big);
    return @bitCast(raw);
}

fn lengthToUsize(value: anytype) !usize {
    return std.math.cast(usize, value) orelse error.IntegerOverflow;
}

fn expectMsgpack(value: anytype, expected: []const u8) !void {
    const bytes = try writeAlloc(std.testing.allocator, value);
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualSlices(u8, expected, bytes);
}

test "msgpack writes primitive values with compact formats" {
    try expectMsgpack(null, &.{0xc0});
    try expectMsgpack(true, &.{0xc3});
    try expectMsgpack(false, &.{0xc2});
    try expectMsgpack(@as(u7, 0x7f), &.{0x7f});
    try expectMsgpack(@as(u8, 0x80), &.{ 0xcc, 0x80 });
    try expectMsgpack(@as(u16, 0x1234), &.{ 0xcd, 0x12, 0x34 });
    try expectMsgpack(@as(u32, 0x12345678), &.{ 0xce, 0x12, 0x34, 0x56, 0x78 });
    try expectMsgpack(@as(i8, -1), &.{0xff});
    try expectMsgpack(@as(i8, -33), &.{ 0xd0, 0xdf });
    try expectMsgpack(@as(i16, -129), &.{ 0xd1, 0xff, 0x7f });
    try expectMsgpack(@as(u64, 0x0102030405060708), &.{ 0xcf, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08 });
    try expectMsgpack(@as(i64, -0x0102030405060708), &.{ 0xd3, 0xfe, 0xfd, 0xfc, 0xfb, 0xfa, 0xf9, 0xf8, 0xf8 });
    try expectMsgpack(@as(f32, 1.5), &.{ 0xca, 0x3f, 0xc0, 0x00, 0x00 });
    try expectMsgpack(@as(f64, 1.5), &.{ 0xcb, 0x3f, 0xf8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 });
}

test "msgpack reads all integer format families" {
    try std.testing.expectEqual(@as(u8, 0x7f), try readSlice(u8, std.testing.allocator, &.{0x7f}));
    try std.testing.expectEqual(@as(i8, -1), try readSlice(i8, std.testing.allocator, &.{0xff}));
    try std.testing.expectEqual(@as(u8, 0x80), try readSlice(u8, std.testing.allocator, &.{ 0xcc, 0x80 }));
    try std.testing.expectEqual(@as(u16, 0x1234), try readSlice(u16, std.testing.allocator, &.{ 0xcd, 0x12, 0x34 }));
    try std.testing.expectEqual(@as(u32, 0x12345678), try readSlice(u32, std.testing.allocator, &.{ 0xce, 0x12, 0x34, 0x56, 0x78 }));
    try std.testing.expectEqual(@as(u64, 0x0102030405060708), try readSlice(u64, std.testing.allocator, &.{ 0xcf, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08 }));
    try std.testing.expectEqual(@as(i8, -33), try readSlice(i8, std.testing.allocator, &.{ 0xd0, 0xdf }));
    try std.testing.expectEqual(@as(i16, -129), try readSlice(i16, std.testing.allocator, &.{ 0xd1, 0xff, 0x7f }));
    try std.testing.expectEqual(@as(i32, -32769), try readSlice(i32, std.testing.allocator, &.{ 0xd2, 0xff, 0xff, 0x7f, 0xff }));
    try std.testing.expectEqual(@as(i64, -0x0102030405060708), try readSlice(i64, std.testing.allocator, &.{ 0xd3, 0xfe, 0xfd, 0xfc, 0xfb, 0xfa, 0xf9, 0xf8, 0xf8 }));

    try std.testing.expectError(error.IntegerOverflow, readSlice(u8, std.testing.allocator, &.{0xff}));
    try std.testing.expectError(error.IntegerOverflow, readSlice(u8, std.testing.allocator, &.{ 0xcd, 0x01, 0x00 }));
    try std.testing.expectError(error.IntegerOverflow, readSlice(i64, std.testing.allocator, &.{ 0xcf, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff }));
}

test "msgpack reads float families and integer floats" {
    try std.testing.expectEqual(@as(f32, 1.5), try readSlice(f32, std.testing.allocator, &.{ 0xca, 0x3f, 0xc0, 0x00, 0x00 }));
    try std.testing.expectEqual(@as(f64, 1.5), try readSlice(f64, std.testing.allocator, &.{ 0xcb, 0x3f, 0xf8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 }));
    try std.testing.expectEqual(@as(f64, 42), try readSlice(f64, std.testing.allocator, &.{0x2a}));
}

test "msgpack writes boundary headers" {
    var string_bytes = [_]u8{'x'} ** 32;
    try expectMsgpack(string_bytes[0..], &.{
        0xd9, 0x20,
        'x',  'x',
        'x',  'x',
        'x',  'x',
        'x',  'x',
        'x',  'x',
        'x',  'x',
        'x',  'x',
        'x',  'x',
        'x',  'x',
        'x',  'x',
        'x',  'x',
        'x',  'x',
        'x',  'x',
        'x',  'x',
        'x',  'x',
        'x',  'x',
    });

    const sixteen = [16]u8{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15 };
    try expectMsgpack(sixteen, &.{
        0xdc, 0x00, 0x10,
        0x00, 0x01, 0x02,
        0x03, 0x04, 0x05,
        0x06, 0x07, 0x08,
        0x09, 0x0a, 0x0b,
        0x0c, 0x0d, 0x0e,
        0x0f,
    });

    var buffer: [512]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    var enc = encoder(&writer);
    try enc.emitBytes(&([_]u8{0xaa} ** 256));
    try enc.finish();

    const encoded = writer.buffered();
    try std.testing.expectEqual(@as(usize, 259), encoded.len);
    try std.testing.expectEqualSlices(u8, &.{ 0xc5, 0x01, 0x00 }, encoded[0..3]);
    try std.testing.expectEqual(@as(u8, 0xaa), encoded[3]);
    try std.testing.expectEqual(@as(u8, 0xaa), encoded[258]);
}

test "msgpack reads non-minimal length headers" {
    const str8 = try readSlice([]const u8, std.testing.allocator, &.{ 0xd9, 0x01, 'a' });
    defer std.testing.allocator.free(str8);
    try std.testing.expectEqualStrings("a", str8);

    const str16 = try readSlice([]const u8, std.testing.allocator, &.{ 0xda, 0x00, 0x01, 'b' });
    defer std.testing.allocator.free(str16);
    try std.testing.expectEqualStrings("b", str16);

    const str32 = try readSlice([]const u8, std.testing.allocator, &.{ 0xdb, 0x00, 0x00, 0x00, 0x01, 'c' });
    defer std.testing.allocator.free(str32);
    try std.testing.expectEqualStrings("c", str32);

    const Blob = struct {
        data: []const u8,

        pub const zerde = .{
            .fields = .{
                .data = .{ .bytes = true },
            },
        };
    };

    const bin16 = try readSlice(Blob, std.testing.allocator, &.{ 0x81, 0xa4, 'd', 'a', 't', 'a', 0xc5, 0x00, 0x01, 0xff });
    defer deinitValue(Blob, std.testing.allocator, bin16);
    try std.testing.expectEqualSlices(u8, &.{0xff}, bin16.data);

    const one_item = try readSlice([1]u8, std.testing.allocator, &.{ 0xdc, 0x00, 0x01, 0x07 });
    try std.testing.expectEqualSlices(u8, &.{7}, &one_item);

    const User = struct { id: u8 };
    const user = try readSlice(User, std.testing.allocator, &.{ 0xde, 0x00, 0x01, 0xa2, 'i', 'd', 0x09 });
    try std.testing.expectEqual(@as(u8, 9), user.id);
}

test "msgpack writes strings arrays and maps" {
    try expectMsgpack("Ada", &.{ 0xa3, 'A', 'd', 'a' });
    try expectMsgpack([3]u8{ 1, 2, 3 }, &.{ 0x93, 0x01, 0x02, 0x03 });

    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(std.testing.allocator);
    try list.append(std.testing.allocator, 4);
    try list.append(std.testing.allocator, 5);
    try expectMsgpack(list, &.{ 0x92, 0x04, 0x05 });

    var ordered: std.array_hash_map.Auto(u8, u8) = .empty;
    defer ordered.deinit(std.testing.allocator);
    try ordered.put(std.testing.allocator, 1, 2);
    try ordered.put(std.testing.allocator, 3, 4);
    try expectMsgpack(ordered, &.{
        0x92,
        0x82,
        0xa3,
        'k',
        'e',
        'y',
        0x01,
        0xa5,
        'v',
        'a',
        'l',
        'u',
        'e',
        0x02,
        0x82,
        0xa3,
        'k',
        'e',
        'y',
        0x03,
        0xa5,
        'v',
        'a',
        'l',
        'u',
        'e',
        0x04,
    });

    const User = struct {
        id: u8,
        name: []const u8,
    };
    try expectMsgpack(User{ .id = 1, .name = "Ada" }, &.{
        0x82,
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
    });
}

test "msgpack roundtrips std containers" {
    const Value = struct {
        items: std.ArrayList([]const u8),
        names: std.array_hash_map.String(u8),
    };
    const allocator = std.testing.allocator;

    var original = Value{
        .items = .empty,
        .names = .empty,
    };
    defer original.items.deinit(allocator);
    defer original.names.deinit(allocator);
    try original.items.append(allocator, "alpha");
    try original.items.append(allocator, "beta");
    try original.names.put(allocator, "one", 1);
    try original.names.put(allocator, "two", 2);

    const bytes = try writeAlloc(allocator, original);
    defer allocator.free(bytes);

    const parsed = try readSlice(Value, allocator, bytes);
    defer deinitValue(Value, allocator, parsed);

    try std.testing.expectEqual(@as(usize, 2), parsed.items.items.len);
    try std.testing.expectEqualStrings("alpha", parsed.items.items[0]);
    try std.testing.expectEqualStrings("beta", parsed.items.items[1]);
    try std.testing.expectEqualStrings("one", parsed.names.keys()[0]);
    try std.testing.expectEqualStrings("two", parsed.names.keys()[1]);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2 }, parsed.names.values());
}

test "msgpack roundtrips structs with owned slices and optionals" {
    const User = struct {
        id: u32,
        name: []const u8,
        scores: []const u16,
        nickname: ?[]const u8,
    };

    const scores = [_]u16{ 10, 20, 30 };
    const original = User{ .id = 7, .name = "Ada", .scores = scores[0..], .nickname = null };
    const bytes = try writeAlloc(std.testing.allocator, original);
    defer std.testing.allocator.free(bytes);

    const parsed = try readSlice(User, std.testing.allocator, bytes);
    defer deinitValue(User, std.testing.allocator, parsed);

    try std.testing.expectEqual(original.id, parsed.id);
    try std.testing.expectEqualStrings(original.name, parsed.name);
    try std.testing.expectEqualSlices(u16, original.scores, parsed.scores);
    try std.testing.expect(parsed.nickname == null);
}

test "msgpack roundtrips raw bytes as bin" {
    const Blob = struct {
        data: []const u8,

        pub const zerde = .{
            .fields = .{
                .data = .{ .bytes = true },
            },
        };
    };
    const raw = [_]u8{ 0, 1, 2, 3 };

    const bytes = try writeAlloc(std.testing.allocator, Blob{ .data = raw[0..] });
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualSlices(u8, &.{ 0x81, 0xa4, 'd', 'a', 't', 'a', 0xc4, 0x04, 0x00, 0x01, 0x02, 0x03 }, bytes);

    const parsed = try readSlice(Blob, std.testing.allocator, bytes);
    defer deinitValue(Blob, std.testing.allocator, parsed);
    try std.testing.expectEqualSlices(u8, raw[0..], parsed.data);
}

test "msgpack reads bytes from str for compatibility" {
    const Blob = struct {
        data: []const u8,

        pub const zerde = .{
            .fields = .{
                .data = .{ .bytes = true },
            },
        };
    };

    const parsed = try readSlice(Blob, std.testing.allocator, &.{ 0x81, 0xa4, 'd', 'a', 't', 'a', 0xa3, 0xff, 0x00, 0x01 });
    defer deinitValue(Blob, std.testing.allocator, parsed);
    try std.testing.expectEqualSlices(u8, &.{ 0xff, 0x00, 0x01 }, parsed.data);
}

test "msgpack rejects invalid string utf8" {
    try std.testing.expectError(error.InvalidUtf8, readSlice([]const u8, std.testing.allocator, &.{ 0xa1, 0xff }));
    try std.testing.expectError(error.InvalidUtf8, writeAlloc(std.testing.allocator, @as([]const u8, &.{0xff})));
}

test "msgpack rejects malformed and trailing input" {
    try std.testing.expectError(error.InvalidType, readSlice(bool, std.testing.allocator, &.{0xc0}));
    try std.testing.expectError(error.EndOfStream, readSlice([]const u8, std.testing.allocator, &.{ 0xa3, 'a' }));
    try std.testing.expectError(error.EndOfStream, readSlice([2]u8, std.testing.allocator, &.{ 0x92, 0x01 }));
    try std.testing.expectError(error.InvalidType, readSlice(struct { id: u8 }, std.testing.allocator, &.{ 0x81, 0x01, 0x02 }));
    try std.testing.expectError(error.InvalidMessagePackTrailingData, readSlice(u8, std.testing.allocator, &.{ 0x01, 0x02 }));
    try std.testing.expectError(error.InvalidMessagePackSyntax, readSlice(?u8, std.testing.allocator, &.{0xc1}));
}

test "msgpack skips unknown nested fields" {
    const User = struct {
        id: u8,
    };

    const parsed = try readSlice(User, std.testing.allocator, &.{
        0x82,
        0xa2,
        'i',
        'd',
        0x01,
        0xa5,
        'e',
        'x',
        't',
        'r',
        'a',
        0x92,
        0xc0,
        0x81,
        0xa1,
        'x',
        0x02,
    });
    try std.testing.expectEqual(@as(u8, 1), parsed.id);
}

test "msgpack skips unknown extension fields" {
    const User = struct {
        id: u8,
    };

    const parsed = try readSlice(User, std.testing.allocator, &.{
        0x82,
        0xa2,
        'i',
        'd',
        0x01,
        0xa3,
        'e',
        'x',
        't',
        0xd4,
        0x07,
        0x2a,
    });
    try std.testing.expectEqual(@as(u8, 1), parsed.id);
}

test "msgpack honors deny_unknown_fields" {
    const User = struct {
        id: u8,

        pub const zerde = .{ .deny_unknown_fields = true };
    };

    try std.testing.expectError(error.UnknownField, readSlice(User, std.testing.allocator, &.{
        0x82,
        0xa2,
        'i',
        'd',
        0x01,
        0xa5,
        'e',
        'x',
        't',
        'r',
        'a',
        0xc3,
    }));
}

test "msgpack roundtrips enums and tagged unions" {
    const Color = enum { red, green, blue };
    const Shape = union(enum) {
        point,
        circle: struct { radius: u16 },
    };
    const Value = struct {
        color: Color,
        shape: Shape,
    };

    const original = Value{ .color = .green, .shape = .{ .circle = .{ .radius = 10 } } };
    const bytes = try writeAlloc(std.testing.allocator, original);
    defer std.testing.allocator.free(bytes);

    const parsed = try readSlice(Value, std.testing.allocator, bytes);
    defer deinitValue(Value, std.testing.allocator, parsed);

    try std.testing.expectEqual(original.color, parsed.color);
    switch (parsed.shape) {
        .circle => |circle| try std.testing.expectEqual(@as(u16, 10), circle.radius),
        .point => return error.InvalidValue,
    }
}

test "msgpack supports low-level extension values" {
    var buffer: [64]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    var enc = encoder(&writer);
    try enc.emitExtension(7, &.{ 1, 2, 3 });
    try enc.finish();

    try std.testing.expectEqualSlices(u8, &.{ 0xc7, 0x03, 0x07, 0x01, 0x02, 0x03 }, writer.buffered());

    var reader: std.Io.Reader = .fixed(writer.buffered());
    var dec = decoder(&reader, std.testing.allocator);
    const ext = try dec.readExtension(std.testing.allocator);
    defer ext.deinit(std.testing.allocator);
    try dec.finish();

    try std.testing.expectEqual(@as(i8, 7), ext.type_id);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3 }, ext.data);
}

test "msgpack events preserve extension values" {
    var buffer: [64]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    var enc = encoder(&writer);
    try enc.emitExtension(7, &.{ 1, 2, 3 });
    try enc.finish();

    var reader: std.Io.Reader = .fixed(writer.buffered());
    var dec = decoder(&reader, std.testing.allocator);
    var value = try events.readAlloc(std.testing.allocator, &dec);
    defer value.deinit(std.testing.allocator);
    try dec.finish();

    switch (value.extension) {
        .opaque_ => |raw| {
            try std.testing.expectEqual(events.Extension.Namespace.msgpack, raw.namespace);
            try std.testing.expectEqual(@as(i64, 7), raw.id.signed);
            try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3 }, raw.data);
        },
        else => return error.InvalidValue,
    }

    var out_buffer: [64]u8 = undefined;
    var out_writer: std.Io.Writer = .fixed(&out_buffer);
    var out_enc = encoder(&out_writer);
    try value.write(&out_enc);
    try out_enc.finish();
    try std.testing.expectEqualSlices(u8, writer.buffered(), out_writer.buffered());
}

test "msgpack writes fixed extension headers" {
    var buffer: [64]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    var enc = encoder(&writer);
    try enc.emitExtension(-2, &.{ 1, 2, 3, 4 });
    try enc.finish();

    try std.testing.expectEqualSlices(u8, &.{ 0xd6, 0xfe, 0x01, 0x02, 0x03, 0x04 }, writer.buffered());

    var reader: std.Io.Reader = .fixed(writer.buffered());
    var dec = decoder(&reader, std.testing.allocator);
    const ext = try dec.readExtension(std.testing.allocator);
    defer ext.deinit(std.testing.allocator);
    try dec.finish();

    try std.testing.expectEqual(@as(i8, -2), ext.type_id);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4 }, ext.data);
}

test "msgpack supports timestamp extension formats" {
    var buffer: [64]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    var enc = encoder(&writer);
    try enc.emitTimestamp(.{ .seconds = 1, .nanoseconds = 2 });
    try enc.finish();

    try std.testing.expectEqualSlices(u8, &.{ 0xd7, 0xff, 0x00, 0x00, 0x00, 0x08, 0x00, 0x00, 0x00, 0x01 }, writer.buffered());

    var reader: std.Io.Reader = .fixed(writer.buffered());
    var dec = decoder(&reader, std.testing.allocator);
    const timestamp = try dec.readTimestamp();
    try dec.finish();

    try std.testing.expectEqual(@as(i64, 1), timestamp.seconds);
    try std.testing.expectEqual(@as(u32, 2), timestamp.nanoseconds);

    var timestamp32_reader: std.Io.Reader = .fixed(&.{ 0xd6, 0xff, 0x00, 0x00, 0x00, 0x2a });
    var timestamp32_dec = decoder(&timestamp32_reader, std.testing.allocator);
    const timestamp32 = try timestamp32_dec.readTimestamp();
    try timestamp32_dec.finish();
    try std.testing.expectEqual(@as(i64, 42), timestamp32.seconds);
    try std.testing.expectEqual(@as(u32, 0), timestamp32.nanoseconds);

    var timestamp96_reader: std.Io.Reader = .fixed(&.{
        0xc7, 0x0c, 0xff,
        0x00, 0x00, 0x00,
        0x2a, 0xff, 0xff,
        0xff, 0xff, 0xff,
        0xff, 0xff, 0xff,
    });
    var timestamp96_dec = decoder(&timestamp96_reader, std.testing.allocator);
    const timestamp96 = try timestamp96_dec.readTimestamp();
    try timestamp96_dec.finish();
    try std.testing.expectEqual(@as(i64, -1), timestamp96.seconds);
    try std.testing.expectEqual(@as(u32, 42), timestamp96.nanoseconds);
}

test "msgpack roundtrips first-class timestamp values" {
    const original = Timestamp{ .seconds = 1, .nanoseconds = 2 };
    const bytes = try writeAlloc(std.testing.allocator, original);
    defer std.testing.allocator.free(bytes);

    try std.testing.expectEqualSlices(u8, &.{ 0xd7, 0xff, 0x00, 0x00, 0x00, 0x08, 0x00, 0x00, 0x00, 0x01 }, bytes);

    const parsed = try readSlice(Timestamp, std.testing.allocator, bytes);
    try std.testing.expectEqual(original.seconds, parsed.seconds);
    try std.testing.expectEqual(original.nanoseconds, parsed.nanoseconds);
}

test "msgpack rejects invalid timestamp extensions" {
    var timestamp64_buffer: [10]u8 = undefined;
    var timestamp64_writer: std.Io.Writer = .fixed(&timestamp64_buffer);
    try timestamp64_writer.writeAll(&.{ 0xd7, 0xff });
    try writeBig(&timestamp64_writer, u64, @as(u64, 1_000_000_000) << 34);

    var timestamp64_reader: std.Io.Reader = .fixed(timestamp64_writer.buffered());
    var timestamp64_dec = decoder(&timestamp64_reader, std.testing.allocator);
    try std.testing.expectError(error.InvalidMessagePackTimestamp, timestamp64_dec.readTimestamp());

    var timestamp96_reader: std.Io.Reader = .fixed(&.{
        0xc7, 0x0c, 0xff,
        0x3b, 0x9a, 0xca,
        0x00, 0x00, 0x00,
        0x00, 0x00, 0x00,
        0x00, 0x00, 0x00,
    });
    var timestamp96_dec = decoder(&timestamp96_reader, std.testing.allocator);
    try std.testing.expectError(error.InvalidMessagePackTimestamp, timestamp96_dec.readTimestamp());

    var wrong_type_reader: std.Io.Reader = .fixed(&.{ 0xd6, 0x00, 0x00, 0x00, 0x00, 0x00 });
    var wrong_type_dec = decoder(&wrong_type_reader, std.testing.allocator);
    try std.testing.expectError(error.InvalidMessagePackTimestamp, wrong_type_dec.readTimestamp());
}
