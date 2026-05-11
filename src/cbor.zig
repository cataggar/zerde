//! CBOR format support.

const std = @import("std");

const serialize = @import("serialize.zig").serialize;
const deserialize = @import("deserialize.zig").deserialize;
const deinitValue = @import("deinit.zig").deinit;
const events = @import("events.zig");

/// CBOR writer configuration.
pub const WriteOptions = struct {
    /// Buffer output and sort map entries by the bytewise order of their encoded keys.
    deterministic: bool = false,
};

/// CBOR semantic tag value for low-level/custom event use.
pub const Tag = struct {
    number: u64,
    value: events.Value,
};

/// Serializes `value` as CBOR to `writer`.
pub fn write(writer: *std.Io.Writer, value: anytype) !void {
    var enc = encoder(writer);
    try serialize(value, &enc);
    try enc.finish();
}

/// Serializes `value` as CBOR to `writer` with explicit options.
pub fn writeWithOptions(allocator: std.mem.Allocator, writer: *std.Io.Writer, value: anytype, options: WriteOptions) !void {
    if (options.deterministic) {
        var enc = DeterministicEncoder.init(allocator, writer);
        defer enc.deinit();
        try serialize(value, &enc);
        try enc.finish();
        return;
    }

    var enc = encoder(writer);
    try serialize(value, &enc);
    try enc.finish();
}

/// Serializes `value` as CBOR and returns allocator-owned bytes.
pub fn writeAlloc(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    return try writeAllocWithOptions(allocator, value, .{});
}

/// Serializes `value` as CBOR with explicit options and returns allocator-owned bytes.
pub fn writeAllocWithOptions(allocator: std.mem.Allocator, value: anytype, options: WriteOptions) ![]u8 {
    var allocating = std.Io.Writer.Allocating.init(allocator);
    errdefer allocating.deinit();

    try writeWithOptions(allocator, &allocating.writer, value, options);
    return try allocating.toOwnedSlice();
}

/// Deserializes CBOR from `reader` into `T`.
pub fn read(comptime T: type, allocator: std.mem.Allocator, reader: *std.Io.Reader) !T {
    var dec = decoder(reader, allocator);
    const value = try deserialize(T, allocator, &dec);
    errdefer deinitValue(T, allocator, value);
    try dec.finish();
    return value;
}

/// Deserializes CBOR from `input` into `T`.
pub fn readSlice(comptime T: type, allocator: std.mem.Allocator, input: []const u8) !T {
    var reader: std.Io.Reader = .fixed(input);
    return try read(T, allocator, &reader);
}

/// Returns a low-level CBOR encoder for use with `zerde.serialize`.
pub fn encoder(writer: *std.Io.Writer) Encoder {
    return .{ .writer = writer };
}

/// Returns an allocator-backed event encoder for dynamic CBOR output.
pub fn eventEncoder(writer: *std.Io.Writer, allocator: std.mem.Allocator) EventEncoder {
    return eventEncoderWithOptions(writer, allocator, .{});
}

/// Returns an allocator-backed event encoder with explicit options.
pub fn eventEncoderWithOptions(writer: *std.Io.Writer, allocator: std.mem.Allocator, options: WriteOptions) EventEncoder {
    return .{ .writer = writer, .allocator = allocator, .options = options };
}

/// Returns a low-level CBOR decoder for use with `zerde.deserialize`.
pub fn decoder(reader: *std.Io.Reader, allocator: std.mem.Allocator) Decoder {
    return .{ .reader = reader, .allocator = allocator };
}

/// CBOR value kinds reported by `Decoder.peek`.
pub const Kind = enum {
    null,
    bool,
    int,
    float,
    string,
    binary,
    extension,
    seq,
    struct_,
};

/// Low-level CBOR encoder used by the generic serializer.
pub const Encoder = struct {
    const Self = @This();
    const max_depth = 64;

    const Container = enum { seq, map };

    const Frame = struct {
        container: Container,
        len: usize,
        count: usize = 0,
        expecting_field_value: bool = false,
    };

    /// Destination writer receiving encoded CBOR bytes.
    writer: *std.Io.Writer,
    /// Container stack used to validate nested arrays and maps.
    stack: [max_depth]Frame = undefined,
    /// Number of active container frames in `stack`.
    stack_len: usize = 0,
    /// Number of root values emitted so far.
    root_count: usize = 0,
    /// Number of semantic tag heads emitted before the next value.
    pending_tags: usize = 0,

    /// Emits the CBOR null simple value.
    pub fn emitNull(self: *Self) !void {
        try self.beforeValue();
        try self.writer.writeByte(0xf6);
    }

    /// Emits a CBOR boolean value.
    pub fn emitBool(self: *Self, value: bool) !void {
        try self.beforeValue();
        try self.writer.writeByte(if (value) 0xf5 else 0xf4);
    }

    /// Emits an integer using the shortest valid CBOR integer head.
    pub fn emitInt(self: *Self, value: anytype) !void {
        try self.beforeValue();
        try self.writeInteger(value);
    }

    /// Emits a CBOR half, single, or double precision float.
    pub fn emitFloat(self: *Self, value: anytype) !void {
        try self.beforeValue();
        try self.writeFloat(value);
    }

    /// Emits a UTF-8 text string.
    pub fn emitString(self: *Self, value: []const u8) !void {
        try self.beforeValue();
        try self.writeString(value);
    }

    /// Emits raw bytes as a CBOR byte string.
    pub fn emitBytes(self: *Self, value: []const u8) !void {
        try self.beforeValue();
        try self.writeBytes(value);
    }

    /// Emits an enum tag as a CBOR text string.
    pub fn emitEnumTag(self: *Self, tag: []const u8) !void {
        try self.emitString(tag);
    }

    /// Emits a CBOR semantic tag head. The next emitted value is the tagged value.
    pub fn emitTag(self: *Self, tag: u64) !void {
        try self.ensureValueSlotAvailable();
        try writeHead(self.writer, 6, tag);
        self.pending_tags += 1;
    }

    /// Emits an unmodeled CBOR simple value such as `undefined` (23).
    pub fn emitSimple(self: *Self, value: u8) !void {
        try self.beforeValue();
        try writeCborSimple(self.writer, value);
    }

    /// Emits a CBOR-compatible event extension value.
    pub fn emitEventExtension(self: *Self, extension: events.Extension) !void {
        try self.beforeValue();
        try self.writeEventExtension(extension);
    }

    fn writeFloat(self: *Self, value: anytype) !void {

        const T = @TypeOf(value);
        const Float = switch (@typeInfo(T)) {
            .comptime_float => f64,
            .float => if (@bitSizeOf(T) <= 16) f16 else if (@bitSizeOf(T) <= 32) f32 else f64,
            else => @compileError("CBOR floats require a float value"),
        };
        const float_value: Float = value;
        const Int = std.meta.Int(.unsigned, @bitSizeOf(Float));
        const raw: Int = @bitCast(float_value);

        try self.writer.writeByte(switch (Float) {
            f16 => 0xf9,
            f32 => 0xfa,
            f64 => 0xfb,
            else => unreachable,
        });
        try writeBig(self.writer, Int, raw);
    }

    fn writeString(self: *Self, value: []const u8) !void {
        if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidUtf8;
        try writeHead(self.writer, 3, value.len);
        try self.writer.writeAll(value);
    }

    fn writeBytes(self: *Self, value: []const u8) !void {
        try writeHead(self.writer, 2, value.len);
        try self.writer.writeAll(value);
    }

    /// Begins a definite-length CBOR array.
    pub fn beginSeq(self: *Self, len: ?usize) !void {
        const actual_len = len orelse return error.MissingCborLength;
        try self.ensureCanPush();
        try self.beforeValue();
        try writeHead(self.writer, 4, actual_len);
        self.push(.{ .container = .seq, .len = actual_len });
    }

    /// Begins a definite-length CBOR array for a fixed Zig array.
    pub fn beginArray(self: *Self, comptime T: type, len: usize) !void {
        _ = T;
        try self.beginSeq(len);
    }

    /// Begins a definite-length CBOR array for a Zig slice.
    pub fn beginSlice(self: *Self, comptime Child: type, len: usize) !void {
        _ = Child;
        try self.beginSeq(len);
    }

    /// Ends the current CBOR array.
    pub fn endSeq(self: *Self) !void {
        const frame = self.current(.seq);
        if (frame.count != frame.len) return error.InvalidCborEncoderState;
        self.pop(.seq);
    }

    /// Begins a definite-length CBOR map for a struct value.
    pub fn beginStruct(self: *Self, comptime T: type, field_count: usize) !void {
        _ = T;
        try self.ensureCanPush();
        try self.beforeValue();
        try writeHead(self.writer, 5, field_count);
        self.push(.{ .container = .map, .len = field_count });
    }

    /// Emits the next CBOR text map key for a struct field.
    pub fn emitFieldName(self: *Self, name: []const u8) !void {
        const frame = self.current(.map);
        if (frame.expecting_field_value) return error.InvalidCborEncoderState;
        if (frame.count == frame.len) return error.InvalidCborEncoderState;
        if (!std.unicode.utf8ValidateSlice(name)) return error.InvalidUtf8;

        try writeHead(self.writer, 3, name.len);
        try self.writer.writeAll(name);
        frame.count += 1;
        frame.expecting_field_value = true;
    }

    /// Ends the current CBOR map for a struct value.
    pub fn endStruct(self: *Self) !void {
        const frame = self.current(.map);
        if (frame.expecting_field_value or frame.count != frame.len) return error.InvalidCborEncoderState;
        self.pop(.map);
    }

    /// Verifies that exactly one complete CBOR root value was emitted.
    pub fn finish(self: *Self) !void {
        if (self.pending_tags != 0) return error.IncompleteCborDocument;
        if (self.root_count == 0) return error.IncompleteCborDocument;
        if (self.stack_len == 0) return;

        const frame = &self.stack[self.stack_len - 1];
        if (frame.container == .map and frame.expecting_field_value) return error.InvalidCborEncoderState;
        return error.IncompleteCborDocument;
    }

    fn beforeValue(self: *Self) !void {
        try self.accountValue();
        self.pending_tags = 0;
    }

    fn ensureValueSlotAvailable(self: *Self) !void {
        if (self.stack_len == 0) {
            if (self.root_count != 0) return error.InvalidCborEncoderState;
            return;
        }

        const frame = &self.stack[self.stack_len - 1];
        switch (frame.container) {
            .seq => if (frame.count == frame.len) return error.InvalidCborEncoderState,
            .map => if (!frame.expecting_field_value) return error.InvalidCborEncoderState,
        }
    }

    fn accountValue(self: *Self) !void {
        if (self.stack_len == 0) {
            if (self.root_count != 0) return error.InvalidCborEncoderState;
            self.root_count += 1;
            return;
        }

        const frame = &self.stack[self.stack_len - 1];
        switch (frame.container) {
            .seq => {
                if (frame.count == frame.len) return error.InvalidCborEncoderState;
                frame.count += 1;
            },
            .map => {
                if (!frame.expecting_field_value) return error.InvalidCborEncoderState;
                frame.expecting_field_value = false;
            },
        }
    }

    fn writeInteger(self: *Self, value: anytype) !void {
        const T = @TypeOf(value);
        switch (@typeInfo(T)) {
            .comptime_int => {
                if (value >= 0) {
                    try writeHead(self.writer, 0, std.math.cast(u64, value) orelse return error.IntegerOverflow);
                } else {
                    try writeHead(self.writer, 1, std.math.cast(u64, -1 - value) orelse return error.IntegerOverflow);
                }
            },
            .int => |int_info| switch (int_info.signedness) {
                .unsigned => try writeHead(self.writer, 0, std.math.cast(u64, value) orelse return error.IntegerOverflow),
                .signed => {
                    const signed = std.math.cast(i128, value) orelse return error.IntegerOverflow;
                    if (signed >= 0) {
                        try writeHead(self.writer, 0, @intCast(signed));
                    } else {
                        const arg = std.math.cast(u64, -1 - signed) orelse return error.IntegerOverflow;
                        try writeHead(self.writer, 1, arg);
                    }
                },
            },
            else => @compileError("CBOR integers require an integer value"),
        }
    }

    fn writeEventValue(self: *Self, value: events.Value) anyerror!void {
        switch (value) {
            .null => try self.writer.writeByte(0xf6),
            .bool => |actual| try self.writer.writeByte(if (actual) 0xf5 else 0xf4),
            .int => |actual| try self.writeInteger(actual),
            .float => |actual| try self.writeFloat(actual),
            .string, .enum_tag, .datetime => |actual| try self.writeString(actual),
            .bytes => |actual| try self.writeBytes(actual),
            .extension => |actual| try self.writeEventExtension(actual),
            .seq => |items| {
                try writeHead(self.writer, 4, items.len);
                for (items) |item| try self.writeEventValue(item);
            },
            .struct_ => |fields| {
                try writeHead(self.writer, 5, fields.len);
                for (fields) |field| {
                    try self.writeString(field.name);
                    try self.writeEventValue(field.value);
                }
            },
        }
    }

    fn writeEventExtension(self: *Self, extension: events.Extension) anyerror!void {
        switch (extension) {
            .tagged => |tagged| {
                if (tagged.namespace != .cbor) return error.UnsupportedEventKind;
                try writeHead(self.writer, 6, try extensionIdUnsigned(tagged.id));
                try self.writeEventValue(tagged.value.*);
            },
            .simple => |simple| {
                if (simple.namespace != .cbor) return error.UnsupportedEventKind;
                try writeCborSimple(self.writer, try extensionIdU8(simple.id));
            },
            .opaque_ => return error.UnsupportedEventKind,
        }
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

const DeterministicEncoder = struct {
    const Self = @This();
    const max_depth = 64;

    const Container = enum { seq, map };

    const EncodedField = struct {
        key: []u8,
        value: []u8,
    };

    const Frame = struct {
        container: Container,
        len: usize,
        count: usize = 0,
        expecting_field_value: bool = false,
        prefix: []u8,
        items: std.ArrayList([]u8) = .empty,
        fields: std.ArrayList(EncodedField) = .empty,
        pending_key: ?[]u8 = null,
    };

    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    stack: [max_depth]Frame = undefined,
    stack_len: usize = 0,
    root: ?[]u8 = null,
    pending_prefix: std.ArrayList(u8) = .empty,

    fn init(allocator: std.mem.Allocator, writer: *std.Io.Writer) Self {
        return .{ .allocator = allocator, .writer = writer };
    }

    fn deinit(self: *Self) void {
        if (self.root) |bytes| self.allocator.free(bytes);
        self.root = null;
        self.pending_prefix.deinit(self.allocator);
        while (self.stack_len != 0) {
            self.stack_len -= 1;
            self.deinitFrame(&self.stack[self.stack_len]);
        }
    }

    pub fn emitNull(self: *Self) !void {
        try self.appendEncodedValue(try encodeNullAlloc(self.allocator));
    }

    pub fn emitBool(self: *Self, value: bool) !void {
        try self.appendEncodedValue(try encodeBoolAlloc(self.allocator, value));
    }

    pub fn emitInt(self: *Self, value: anytype) !void {
        try self.appendEncodedValue(try encodeIntegerAlloc(self.allocator, value));
    }

    pub fn emitFloat(self: *Self, value: anytype) !void {
        try self.appendEncodedValue(try encodeFloatAlloc(self.allocator, value));
    }

    pub fn emitString(self: *Self, value: []const u8) !void {
        try self.appendEncodedValue(try encodeStringAlloc(self.allocator, value));
    }

    pub fn emitBytes(self: *Self, value: []const u8) !void {
        try self.appendEncodedValue(try encodeBytesAlloc(self.allocator, value));
    }

    pub fn emitEnumTag(self: *Self, tag: []const u8) !void {
        try self.emitString(tag);
    }

    pub fn emitTag(self: *Self, tag: u64) !void {
        try self.ensureValueSlotAvailable();
        var allocating = std.Io.Writer.Allocating.init(self.allocator);
        defer allocating.deinit();
        try writeHead(&allocating.writer, 6, tag);
        try self.pending_prefix.appendSlice(self.allocator, allocating.writer.buffered());
    }

    pub fn emitSimple(self: *Self, value: u8) !void {
        try self.appendEncodedValue(try encodeSimpleAlloc(self.allocator, value));
    }

    pub fn emitEventExtension(self: *Self, extension: events.Extension) !void {
        try self.appendEncodedValue(try encodeDeterministicExtensionAlloc(self.allocator, extension));
    }

    pub fn beginSeq(self: *Self, len: ?usize) !void {
        const actual_len = len orelse return error.MissingCborLength;
        try self.push(.{ .container = .seq, .len = actual_len, .prefix = try self.takePendingPrefix() });
    }

    pub fn beginArray(self: *Self, comptime T: type, len: usize) !void {
        _ = T;
        try self.beginSeq(len);
    }

    pub fn beginSlice(self: *Self, comptime Child: type, len: usize) !void {
        _ = Child;
        try self.beginSeq(len);
    }

    pub fn endSeq(self: *Self) !void {
        var frame = self.pop(.seq);
        defer self.deinitFrame(&frame);
        if (frame.count != frame.len) return error.InvalidCborEncoderState;

        var allocating = std.Io.Writer.Allocating.init(self.allocator);
        errdefer allocating.deinit();
        try allocating.writer.writeAll(frame.prefix);
        try writeHead(&allocating.writer, 4, frame.len);
        for (frame.items.items) |item| try allocating.writer.writeAll(item);
        try self.appendEncodedValue(try allocating.toOwnedSlice());
    }

    pub fn beginStruct(self: *Self, comptime T: type, field_count: usize) !void {
        _ = T;
        try self.push(.{ .container = .map, .len = field_count, .prefix = try self.takePendingPrefix() });
    }

    pub fn emitFieldName(self: *Self, name: []const u8) !void {
        const frame = self.current(.map);
        if (frame.expecting_field_value) return error.InvalidCborEncoderState;
        if (frame.count == frame.len) return error.InvalidCborEncoderState;
        frame.pending_key = try encodeStringAlloc(self.allocator, name);
        frame.expecting_field_value = true;
    }

    pub fn endStruct(self: *Self) !void {
        var frame = self.pop(.map);
        defer self.deinitFrame(&frame);
        if (frame.expecting_field_value or frame.count != frame.len) return error.InvalidCborEncoderState;

        sortEncodedFields(frame.fields.items);

        var allocating = std.Io.Writer.Allocating.init(self.allocator);
        errdefer allocating.deinit();
        try allocating.writer.writeAll(frame.prefix);
        try writeHead(&allocating.writer, 5, frame.len);
        for (frame.fields.items) |field| {
            try allocating.writer.writeAll(field.key);
            try allocating.writer.writeAll(field.value);
        }
        try self.appendEncodedValue(try allocating.toOwnedSlice());
    }

    pub fn finish(self: *Self) !void {
        if (self.pending_prefix.items.len != 0) return error.IncompleteCborDocument;
        if (self.stack_len != 0) return error.IncompleteCborDocument;
        const bytes = self.root orelse return error.IncompleteCborDocument;
        try self.writer.writeAll(bytes);
    }

    fn appendEncodedValue(self: *Self, encoded: []u8) !void {
        var owned = encoded;
        errdefer self.allocator.free(owned);
        try self.ensureValueSlotAvailable();

        if (self.pending_prefix.items.len != 0) {
            var allocating = std.Io.Writer.Allocating.init(self.allocator);
            errdefer allocating.deinit();
            try allocating.writer.writeAll(self.pending_prefix.items);
            try allocating.writer.writeAll(owned);
            const combined = try allocating.toOwnedSlice();
            self.allocator.free(owned);
            owned = combined;
            self.pending_prefix.clearRetainingCapacity();
        }

        if (self.stack_len == 0) {
            if (self.root != null) return error.InvalidCborEncoderState;
            self.root = owned;
            return;
        }

        const frame = &self.stack[self.stack_len - 1];
        switch (frame.container) {
            .seq => {
                if (frame.count == frame.len) return error.InvalidCborEncoderState;
                try frame.items.append(self.allocator, owned);
                frame.count += 1;
            },
            .map => {
                if (!frame.expecting_field_value) return error.InvalidCborEncoderState;
                const key = frame.pending_key orelse return error.InvalidCborEncoderState;
                errdefer self.allocator.free(key);
                try frame.fields.append(self.allocator, .{ .key = key, .value = owned });
                frame.pending_key = null;
                frame.expecting_field_value = false;
                frame.count += 1;
            },
        }
    }

    fn ensureValueSlotAvailable(self: *Self) !void {
        if (self.stack_len == 0) {
            if (self.root != null) return error.InvalidCborEncoderState;
            return;
        }

        const frame = &self.stack[self.stack_len - 1];
        switch (frame.container) {
            .seq => if (frame.count == frame.len) return error.InvalidCborEncoderState,
            .map => if (!frame.expecting_field_value) return error.InvalidCborEncoderState,
        }
    }

    fn takePendingPrefix(self: *Self) ![]u8 {
        const prefix = try self.pending_prefix.toOwnedSlice(self.allocator);
        self.pending_prefix = .empty;
        return prefix;
    }

    fn push(self: *Self, frame: Frame) !void {
        errdefer if (frame.prefix.len != 0) self.allocator.free(frame.prefix);
        if (self.stack_len == self.stack.len) return error.NestingTooDeep;
        try self.ensureValueSlotAvailable();
        self.stack[self.stack_len] = frame;
        self.stack_len += 1;
    }

    fn pop(self: *Self, expected: Container) Frame {
        std.debug.assert(self.stack_len != 0);
        self.stack_len -= 1;
        const frame = self.stack[self.stack_len];
        std.debug.assert(frame.container == expected);
        return frame;
    }

    fn current(self: *Self, expected: Container) *Frame {
        std.debug.assert(self.stack_len != 0);
        const frame = &self.stack[self.stack_len - 1];
        std.debug.assert(frame.container == expected);
        return frame;
    }

    fn deinitFrame(self: *Self, frame: *Frame) void {
        if (frame.prefix.len != 0) self.allocator.free(frame.prefix);
        for (frame.items.items) |item| self.allocator.free(item);
        frame.items.deinit(self.allocator);
        for (frame.fields.items) |field| {
            self.allocator.free(field.key);
            self.allocator.free(field.value);
        }
        frame.fields.deinit(self.allocator);
        if (frame.pending_key) |key| self.allocator.free(key);
        frame.* = undefined;
    }
};

/// Allocator-backed event encoder for dynamic CBOR output.
pub const EventEncoder = struct {
    const Self = @This();
    const max_depth = 64;

    const Container = enum { seq, struct_ };

    const Frame = struct {
        container: Container,
        expected_len: ?usize,
        count: usize = 0,
        values: std.ArrayList(events.Value) = .empty,
        fields: std.ArrayList(events.ObjectField) = .empty,
        pending_field_name: ?[]u8 = null,
        tags: []u64 = &.{},
    };

    writer: *std.Io.Writer,
    allocator: std.mem.Allocator,
    options: WriteOptions = .{},
    stack: [max_depth]Frame = undefined,
    stack_len: usize = 0,
    root: ?events.Value = null,
    pending_tags: std.ArrayList(u64) = .empty,

    /// Frees any buffered event state not consumed by `finish`.
    pub fn deinit(self: *Self) void {
        if (self.root) |*value| value.deinit(self.allocator);
        self.root = null;
        self.pending_tags.deinit(self.allocator);
        while (self.stack_len != 0) {
            self.stack_len -= 1;
            self.deinitFrame(&self.stack[self.stack_len]);
        }
    }

    pub fn emitNull(self: *Self) !void {
        try self.appendValue(.null);
    }

    pub fn emitBool(self: *Self, value: bool) !void {
        try self.appendValue(.{ .bool = value });
    }

    pub fn emitInt(self: *Self, value: anytype) !void {
        try self.appendValue(.{ .int = std.math.cast(i128, value) orelse return error.IntegerOverflow });
    }

    pub fn emitFloat(self: *Self, value: anytype) !void {
        try self.appendValue(.{ .float = @floatCast(value) });
    }

    pub fn emitString(self: *Self, value: []const u8) !void {
        if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidUtf8;
        const owned = try self.allocator.dupe(u8, value);
        try self.appendValue(.{ .string = owned });
    }

    pub fn emitBytes(self: *Self, value: []const u8) !void {
        const owned = try self.allocator.dupe(u8, value);
        try self.appendValue(.{ .bytes = owned });
    }

    pub fn emitEnumTag(self: *Self, tag: []const u8) !void {
        try self.emitString(tag);
    }

    pub fn emitEventExtension(self: *Self, extension: events.Extension) !void {
        const owned = try self.cloneExtension(extension);
        try self.appendValue(.{ .extension = owned });
    }

    pub fn emitTag(self: *Self, tag: u64) !void {
        try self.ensureValueSlotAvailable();
        try self.pending_tags.append(self.allocator, tag);
    }

    pub fn emitSimple(self: *Self, value: u8) !void {
        switch (value) {
            0...19, 23, 32...255 => {},
            20...22, 24...31 => return error.InvalidType,
        }
        try self.appendValue(.{ .extension = events.Extension.cborSimple(value) });
    }

    pub fn beginSeq(self: *Self, len: ?usize) !void {
        try self.push(.{ .container = .seq, .expected_len = len });
    }

    pub fn beginArray(self: *Self, comptime T: type, len: usize) !void {
        _ = T;
        try self.beginSeq(len);
    }

    pub fn beginSlice(self: *Self, comptime Child: type, len: usize) !void {
        _ = Child;
        try self.beginSeq(len);
    }

    pub fn endSeq(self: *Self) !void {
        if (self.stack_len == 0) return error.InvalidCborEncoderState;
        var frame = self.pop(.seq);
        errdefer self.deinitFrame(&frame);
        if (frame.expected_len) |len| if (frame.count != len) return error.InvalidCborEncoderState;

        const values = try frame.values.toOwnedSlice(self.allocator);
        frame.values = .empty;
        var value: events.Value = .{ .seq = values };
        value = try self.wrapTags(value, frame.tags);
        if (frame.tags.len != 0) self.allocator.free(frame.tags);
        frame.tags = &.{};
        try self.appendValue(value);
    }

    pub fn beginStruct(self: *Self, comptime T: type, field_count: usize) !void {
        _ = T;
        try self.beginStructEvent(field_count);
    }

    pub fn beginStructEvent(self: *Self, field_count: ?usize) !void {
        try self.push(.{ .container = .struct_, .expected_len = field_count });
    }

    pub fn emitFieldName(self: *Self, name: []const u8) !void {
        if (!std.unicode.utf8ValidateSlice(name)) return error.InvalidUtf8;
        if (self.stack_len == 0) return error.InvalidCborEncoderState;
        const frame = &self.stack[self.stack_len - 1];
        if (frame.container != .struct_ or frame.pending_field_name != null) return error.InvalidCborEncoderState;
        if (frame.expected_len) |len| if (frame.count == len) return error.InvalidCborEncoderState;
        frame.pending_field_name = try self.allocator.dupe(u8, name);
    }

    pub fn endStruct(self: *Self) !void {
        if (self.stack_len == 0) return error.InvalidCborEncoderState;
        var frame = self.pop(.struct_);
        errdefer self.deinitFrame(&frame);
        if (frame.pending_field_name != null) return error.InvalidCborEncoderState;
        if (frame.expected_len) |len| if (frame.count != len) return error.InvalidCborEncoderState;

        const fields = try frame.fields.toOwnedSlice(self.allocator);
        frame.fields = .empty;
        var value: events.Value = .{ .struct_ = fields };
        value = try self.wrapTags(value, frame.tags);
        if (frame.tags.len != 0) self.allocator.free(frame.tags);
        frame.tags = &.{};
        try self.appendValue(value);
    }

    /// Writes the buffered root value as definite-length CBOR.
    pub fn finish(self: *Self) !void {
        if (self.pending_tags.items.len != 0) return error.IncompleteCborDocument;
        if (self.stack_len != 0) return error.IncompleteCborDocument;
        var value = self.root orelse return error.IncompleteCborDocument;
        self.root = null;
        defer value.deinit(self.allocator);

        if (self.options.deterministic) {
            try writeDeterministicValue(self.allocator, self.writer, value);
        } else {
            var enc = encoder(self.writer);
            try value.write(&enc);
            try enc.finish();
        }
    }

    fn appendValue(self: *Self, value: events.Value) !void {
        var owned = value;
        self.ensureValueSlotAvailable() catch |err| {
            owned.deinit(self.allocator);
            return err;
        };
        owned = self.wrapPendingTags(owned) catch |err| return err;
        errdefer owned.deinit(self.allocator);

        if (self.stack_len == 0) {
            if (self.root != null) return error.InvalidCborEncoderState;
            self.root = owned;
            self.pending_tags.clearRetainingCapacity();
            return;
        }

        const frame = &self.stack[self.stack_len - 1];
        switch (frame.container) {
            .seq => {
                if (frame.expected_len) |len| if (frame.count == len) return error.InvalidCborEncoderState;
                try frame.values.append(self.allocator, owned);
                frame.count += 1;
                self.pending_tags.clearRetainingCapacity();
            },
            .struct_ => {
                const name = frame.pending_field_name orelse return error.InvalidCborEncoderState;
                frame.pending_field_name = null;
                errdefer self.allocator.free(name);
                try frame.fields.append(self.allocator, .{ .name = name, .value = owned });
                frame.count += 1;
                self.pending_tags.clearRetainingCapacity();
            },
        }
    }

    fn wrapPendingTags(self: *Self, value: events.Value) !events.Value {
        return try self.wrapTags(value, self.pending_tags.items);
    }

    fn wrapTags(self: *Self, value: events.Value, tags: []const u64) !events.Value {
        var owned = value;
        errdefer owned.deinit(self.allocator);

        var index = tags.len;
        while (index != 0) {
            index -= 1;
            const child = try self.allocator.create(events.Value);
            errdefer self.allocator.destroy(child);
            child.* = owned;
            owned = .{ .extension = events.Extension.cborTag(tags[index], child) };
        }

        return owned;
    }

    fn ensureValueSlotAvailable(self: *Self) !void {
        if (self.stack_len == 0) {
            if (self.root != null) return error.InvalidCborEncoderState;
            return;
        }

        const frame = &self.stack[self.stack_len - 1];
        switch (frame.container) {
            .seq => if (frame.expected_len) |len| if (frame.count == len) return error.InvalidCborEncoderState,
            .struct_ => if (frame.pending_field_name == null) return error.InvalidCborEncoderState,
        }
    }

    fn cloneExtension(self: *Self, extension: events.Extension) anyerror!events.Extension {
        return switch (extension) {
            .opaque_ => |raw| blk: {
                const data = try self.allocator.dupe(u8, raw.data);
                break :blk .{ .opaque_ = .{ .namespace = raw.namespace, .id = raw.id, .data = data } };
            },
            .tagged => |tagged| blk: {
                const value = try self.allocator.create(events.Value);
                errdefer self.allocator.destroy(value);
                value.* = try self.cloneValue(tagged.value.*);
                break :blk .{ .tagged = .{ .namespace = tagged.namespace, .id = tagged.id, .value = value } };
            },
            .simple => |simple| .{ .simple = simple },
        };
    }

    fn cloneValue(self: *Self, value: events.Value) anyerror!events.Value {
        return switch (value) {
            .null => .null,
            .bool => |actual| .{ .bool = actual },
            .int => |actual| .{ .int = actual },
            .float => |actual| .{ .float = actual },
            .string => |actual| .{ .string = try self.allocator.dupe(u8, actual) },
            .bytes => |actual| .{ .bytes = try self.allocator.dupe(u8, actual) },
            .enum_tag => |actual| .{ .enum_tag = try self.allocator.dupe(u8, actual) },
            .datetime => |actual| .{ .datetime = try self.allocator.dupe(u8, actual) },
            .extension => |actual| .{ .extension = try self.cloneExtension(actual) },
            .seq => |items| .{ .seq = try self.cloneValues(items) },
            .struct_ => |fields| .{ .struct_ = try self.cloneFields(fields) },
        };
    }

    fn cloneValues(self: *Self, items: []const events.Value) anyerror![]events.Value {
        const out = try self.allocator.alloc(events.Value, items.len);
        errdefer self.allocator.free(out);

        var initialized: usize = 0;
        errdefer for (out[0..initialized]) |*item| item.deinit(self.allocator);

        for (items, 0..) |item, i| {
            out[i] = try self.cloneValue(item);
            initialized += 1;
        }
        return out;
    }

    fn cloneFields(self: *Self, fields: []const events.ObjectField) anyerror![]events.ObjectField {
        const out = try self.allocator.alloc(events.ObjectField, fields.len);
        errdefer self.allocator.free(out);

        var initialized: usize = 0;
        errdefer for (out[0..initialized]) |*field| {
            self.allocator.free(field.name);
            field.value.deinit(self.allocator);
        };

        for (fields, 0..) |field, i| {
            const name = try self.allocator.dupe(u8, field.name);
            errdefer self.allocator.free(name);
            const value = try self.cloneValue(field.value);
            out[i] = .{ .name = name, .value = value };
            initialized += 1;
        }
        return out;
    }

    fn push(self: *Self, frame: Frame) !void {
        if (self.stack_len == self.stack.len) return error.NestingTooDeep;
        try self.ensureValueSlotAvailable();
        var actual = frame;
        actual.tags = try self.pending_tags.toOwnedSlice(self.allocator);
        self.pending_tags = .empty;
        errdefer self.allocator.free(actual.tags);
        self.stack[self.stack_len] = actual;
        self.stack_len += 1;
    }

    fn pop(self: *Self, expected: Container) Frame {
        std.debug.assert(self.stack_len != 0);
        self.stack_len -= 1;
        const frame = self.stack[self.stack_len];
        std.debug.assert(frame.container == expected);
        return frame;
    }

    fn deinitFrame(self: *Self, frame: *Frame) void {
        if (frame.pending_field_name) |name| self.allocator.free(name);
        if (frame.tags.len != 0) self.allocator.free(frame.tags);
        for (frame.values.items) |*value| value.deinit(self.allocator);
        frame.values.deinit(self.allocator);
        for (frame.fields.items) |*field| {
            self.allocator.free(field.name);
            field.value.deinit(self.allocator);
        }
        frame.fields.deinit(self.allocator);
        frame.* = undefined;
    }
};

/// Low-level CBOR decoder used by the generic deserializer.
pub const Decoder = struct {
    const Self = @This();
    const max_depth = 64;

    const Container = enum { seq, map };

    const Frame = struct {
        container: Container,
        len: ?usize,
        index: usize = 0,
    };

    const Integer = union(enum) {
        unsigned: u64,
        signed: i128,
    };

    const Head = struct {
        major: u3,
        ai: u5,
    };

    reader: *std.Io.Reader,
    allocator: std.mem.Allocator,
    stack: [max_depth]Frame = undefined,
    stack_len: usize = 0,

    /// Returns the kind of the next CBOR value without consuming it.
    pub fn peek(self: *Self) !Kind {
        const byte = (try self.peekByte()) orelse return error.EndOfStream;
        if (byte == 0xff) return error.InvalidCborBreak;
        const head = parseHead(byte);
        if (head.ai == 28 or head.ai == 29 or head.ai == 30) return error.InvalidCborSyntax;
        return switch (head.major) {
            0, 1 => if (head.ai == 31) error.InvalidCborSyntax else .int,
            2 => .binary,
            3 => .string,
            4 => .seq,
            5 => .struct_,
            6 => .extension,
            7 => switch (head.ai) {
                0...19, 23, 24 => .extension,
                20, 21 => .bool,
                22 => .null,
                25, 26, 27 => .float,
                31 => error.InvalidCborBreak,
                else => error.UnsupportedCborSimpleValue,
            },
        };
    }

    /// Reads a CBOR null value.
    pub fn readNull(self: *Self) !void {
        const byte = try self.reader.takeByte();
        if (byte != 0xf6) return error.InvalidType;
    }

    /// Reads a CBOR boolean value.
    pub fn readBool(self: *Self) !bool {
        return switch (try self.reader.takeByte()) {
            0xf4 => false,
            0xf5 => true,
            else => error.InvalidType,
        };
    }

    /// Reads a CBOR integer and converts it to `T`.
    pub fn readInt(self: *Self, comptime T: type) !T {
        const integer = try self.readInteger();
        return switch (integer) {
            .unsigned => |value| std.math.cast(T, value) orelse error.IntegerOverflow,
            .signed => |value| std.math.cast(T, value) orelse error.IntegerOverflow,
        };
    }

    /// Reads a CBOR float, or an integer coerced to `T`.
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

        const head = parseHead(try self.reader.takeByte());
        if (head.major != 7) return error.InvalidType;
        return switch (head.ai) {
            25 => @floatCast(@as(f16, @bitCast(try readBig(self.reader, u16)))),
            26 => @floatCast(@as(f32, @bitCast(try readBig(self.reader, u32)))),
            27 => @floatCast(@as(f64, @bitCast(try readBig(self.reader, u64)))),
            else => error.InvalidType,
        };
    }

    /// Reads a CBOR text string as allocator-owned UTF-8 bytes.
    pub fn readString(self: *Self, allocator: std.mem.Allocator) ![]u8 {
        const bytes = try self.readRaw(allocator, 3);
        errdefer allocator.free(bytes);
        if (!std.unicode.utf8ValidateSlice(bytes)) return error.InvalidUtf8;
        return bytes;
    }

    /// Reads a CBOR byte string as allocator-owned bytes.
    pub fn readBytes(self: *Self, allocator: std.mem.Allocator) ![]u8 {
        return try self.readRaw(allocator, 2);
    }

    /// Reads a CBOR semantic tag head and leaves the tagged value unread.
    pub fn readTag(self: *Self) !u64 {
        const head = parseHead(try self.reader.takeByte());
        if (head.major != 6) return error.InvalidType;
        return try self.readArgNoIndef(head.ai);
    }

    /// Reads an unmodeled CBOR simple value such as `undefined` (23).
    pub fn readSimple(self: *Self) !u8 {
        const head = parseHead(try self.reader.takeByte());
        if (head.major != 7) return error.InvalidType;
        return try self.readSimpleCodeAfterHead(head);
    }

    /// Reads a CBOR tag or simple value as an event extension.
    pub fn readEventExtension(self: *Self, allocator: std.mem.Allocator) anyerror!events.Extension {
        const head = parseHead(try self.reader.takeByte());
        return switch (head.major) {
            6 => blk: {
                const tag = try self.readArgNoIndef(head.ai);
                const value = try allocator.create(events.Value);
                errdefer allocator.destroy(value);
                value.* = try events.readAlloc(allocator, self);
                break :blk events.Extension.cborTag(tag, value);
            },
            7 => events.Extension.cborSimple(try self.readSimpleCodeAfterHead(head)),
            else => error.InvalidType,
        };
    }

    /// Begins reading a CBOR array and returns its element count when definite.
    pub fn beginSeq(self: *Self) !?usize {
        const len = try self.readContainerHeader(4);
        try self.push(.{ .container = .seq, .len = len });
        return len;
    }

    /// Returns whether the current CBOR array has another element.
    pub fn hasNextSeqElem(self: *Self) !bool {
        const frame = self.current(.seq);
        if (frame.len) |len| {
            if (frame.index == len) return false;
            frame.index += 1;
            return true;
        }

        if (try self.consumeBreak()) return false;
        return true;
    }

    /// Ends the current CBOR array.
    pub fn endSeq(self: *Self) !void {
        const frame = self.current(.seq);
        if (frame.len) |len| if (frame.index != len) return error.InvalidCborDecoderState;
        self.pop(.seq);
    }

    /// Begins reading a CBOR map for a struct value.
    pub fn beginStruct(self: *Self, comptime T: type) !void {
        _ = T;
        _ = try self.beginStructEvent();
    }

    /// Begins reading a CBOR map for event consumers and returns its field count when definite.
    pub fn beginStructEvent(self: *Self) !?usize {
        const len = try self.readContainerHeader(5);
        try self.push(.{ .container = .map, .len = len });
        return len;
    }

    /// Reads the next CBOR text map key as an allocator-owned field name.
    pub fn nextField(self: *Self) !?[]u8 {
        const frame = self.current(.map);
        if (frame.len) |len| {
            if (frame.index == len) return null;
            frame.index += 1;
        } else if (try self.consumeBreak()) {
            return null;
        }

        if (try self.peek() != .string) return error.InvalidType;
        return try self.readString(self.allocator);
    }

    /// Ends the current CBOR map for a struct value.
    pub fn endStruct(self: *Self) !void {
        const frame = self.current(.map);
        if (frame.len) |len| if (frame.index != len) return error.InvalidCborDecoderState;
        self.pop(.map);
    }

    /// Skips the next complete CBOR value, including nested containers and tags.
    pub fn skipValue(self: *Self) anyerror!void {
        const first = try self.reader.takeByte();
        if (first == 0xff) return error.InvalidCborBreak;
        const head = parseHead(first);
        switch (head.major) {
            0, 1 => {
                if (head.ai == 31) return error.InvalidCborSyntax;
                _ = try self.readArg(head.ai);
            },
            2, 3 => try self.skipRawAfterHead(head),
            4 => try self.skipArrayAfterHead(head),
            5 => try self.skipMapAfterHead(head),
            6 => {
                if (head.ai == 31) return error.InvalidCborSyntax;
                _ = try self.readArg(head.ai);
                try self.skipValue();
            },
            7 => try self.skipSimpleAfterHead(head),
        }
    }

    /// Verifies that the reader is at the end of a complete CBOR document.
    pub fn finish(self: *Self) !void {
        if (self.stack_len != 0) return error.InvalidCborDecoderState;
        if ((try self.peekByte()) != null) return error.InvalidCborTrailingData;
    }

    fn readInteger(self: *Self) !Integer {
        const first = try self.reader.takeByte();
        const head = parseHead(first);
        return switch (head.major) {
            0 => .{ .unsigned = try self.readArgNoIndef(head.ai) },
            1 => blk: {
                const arg = try self.readArgNoIndef(head.ai);
                break :blk .{ .signed = -1 - @as(i128, arg) };
            },
            6 => error.UnsupportedCborTag,
            7 => error.UnsupportedCborSimpleValue,
            else => error.InvalidType,
        };
    }

    fn readRaw(self: *Self, allocator: std.mem.Allocator, expected_major: u3) ![]u8 {
        const first = try self.reader.takeByte();
        const head = parseHead(first);
        if (head.major != expected_major) return error.InvalidType;

        if (head.ai == 31) {
            var out = std.Io.Writer.Allocating.init(allocator);
            errdefer out.deinit();

            while (true) {
                if (try self.consumeBreak()) break;
                const chunk_first = try self.reader.takeByte();
                const chunk_head = parseHead(chunk_first);
                if (chunk_head.major != expected_major or chunk_head.ai == 31) return error.InvalidCborSyntax;
                const len = try lengthToUsize(try self.readArgNoIndef(chunk_head.ai));
                if (expected_major == 3) {
                    const chunk = try allocator.alloc(u8, len);
                    defer allocator.free(chunk);
                    try self.readExact(chunk);
                    if (!std.unicode.utf8ValidateSlice(chunk)) return error.InvalidUtf8;
                    try out.writer.writeAll(chunk);
                } else {
                    try self.copyBytes(&out.writer, len);
                }
            }
            return try out.toOwnedSlice();
        }

        const len = try lengthToUsize(try self.readArgNoIndef(head.ai));
        const out = try allocator.alloc(u8, len);
        errdefer allocator.free(out);
        try self.readExact(out);
        return out;
    }

    fn readContainerHeader(self: *Self, expected_major: u3) !?usize {
        const head = parseHead(try self.reader.takeByte());
        if (head.major != expected_major) return error.InvalidType;
        if (head.ai == 31) return null;
        return try lengthToUsize(try self.readArgNoIndef(head.ai));
    }

    fn readArgNoIndef(self: *Self, ai: u5) !u64 {
        if (ai == 31) return error.InvalidCborSyntax;
        return try self.readArg(ai);
    }

    fn readArg(self: *Self, ai: u5) !u64 {
        return switch (ai) {
            0...23 => ai,
            24 => try self.reader.takeByte(),
            25 => try readBig(self.reader, u16),
            26 => try readBig(self.reader, u32),
            27 => try readBig(self.reader, u64),
            28...30 => error.InvalidCborSyntax,
            31 => error.InvalidCborSyntax,
        };
    }

    fn readSimpleCodeAfterHead(self: *Self, head: Head) !u8 {
        std.debug.assert(head.major == 7);
        return switch (head.ai) {
            0...19, 23 => @intCast(head.ai),
            24 => blk: {
                const code = try self.reader.takeByte();
                if (code < 32) return error.InvalidCborSyntax;
                break :blk code;
            },
            20, 21, 22, 25, 26, 27 => error.InvalidType,
            28...30 => error.InvalidCborSyntax,
            31 => error.InvalidCborBreak,
        };
    }

    fn skipRawAfterHead(self: *Self, head: Head) anyerror!void {
        if (head.ai == 31) {
            while (true) {
                if (try self.consumeBreak()) break;
                const chunk_head = parseHead(try self.reader.takeByte());
                if (chunk_head.major != head.major or chunk_head.ai == 31) return error.InvalidCborSyntax;
                try self.skipBytes(try lengthToUsize(try self.readArgNoIndef(chunk_head.ai)));
            }
            return;
        }
        try self.skipBytes(try lengthToUsize(try self.readArgNoIndef(head.ai)));
    }

    fn skipArrayAfterHead(self: *Self, head: Head) anyerror!void {
        if (head.ai == 31) {
            while (true) {
                if (try self.consumeBreak()) break;
                try self.skipValue();
            }
            return;
        }
        const len = try lengthToUsize(try self.readArgNoIndef(head.ai));
        for (0..len) |_| try self.skipValue();
    }

    fn skipMapAfterHead(self: *Self, head: Head) anyerror!void {
        if (head.ai == 31) {
            while (true) {
                if (try self.consumeBreak()) break;
                try self.skipValue();
                if (try self.consumeBreak()) return error.InvalidCborSyntax;
                try self.skipValue();
            }
            return;
        }
        const len = try lengthToUsize(try self.readArgNoIndef(head.ai));
        for (0..len) |_| {
            try self.skipValue();
            try self.skipValue();
        }
    }

    fn skipSimpleAfterHead(self: *Self, head: Head) anyerror!void {
        switch (head.ai) {
            20...23 => {},
            24 => {
                const value = try self.reader.takeByte();
                if (value < 32) return error.InvalidCborSyntax;
            },
            25 => try self.skipBytes(2),
            26 => try self.skipBytes(4),
            27 => try self.skipBytes(8),
            28...30 => return error.InvalidCborSyntax,
            31 => return error.InvalidCborBreak,
            else => {},
        }
    }

    fn consumeBreak(self: *Self) !bool {
        if ((try self.peekByte()) == 0xff) {
            _ = try self.reader.takeByte();
            return true;
        }
        return false;
    }

    fn copyBytes(self: *Self, writer: *std.Io.Writer, len: usize) !void {
        for (0..len) |_| try writer.writeByte(try self.reader.takeByte());
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

fn parseHead(byte: u8) Decoder.Head {
    return .{ .major = @intCast(byte >> 5), .ai = @intCast(byte & 0x1f) };
}

fn writeHead(writer: *std.Io.Writer, major: u3, value: u64) !void {
    const prefix: u8 = @as(u8, major) << 5;
    if (value <= 23) {
        try writer.writeByte(prefix | @as(u8, @intCast(value)));
    } else if (value <= std.math.maxInt(u8)) {
        try writer.writeByte(prefix | 24);
        try writer.writeByte(@intCast(value));
    } else if (value <= std.math.maxInt(u16)) {
        try writer.writeByte(prefix | 25);
        try writeBig(writer, u16, @intCast(value));
    } else if (value <= std.math.maxInt(u32)) {
        try writer.writeByte(prefix | 26);
        try writeBig(writer, u32, @intCast(value));
    } else {
        try writer.writeByte(prefix | 27);
        try writeBig(writer, u64, value);
    }
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

fn extensionIdUnsigned(id: events.Extension.Id) !u64 {
    return switch (id) {
        .unsigned => |value| value,
        .signed => |value| std.math.cast(u64, value) orelse error.IntegerOverflow,
    };
}

fn extensionIdU8(id: events.Extension.Id) !u8 {
    return std.math.cast(u8, try extensionIdUnsigned(id)) orelse error.IntegerOverflow;
}

fn writeCborSimple(writer: *std.Io.Writer, code: u8) !void {
    switch (code) {
        0...19, 23 => try writer.writeByte(0xe0 | code),
        20...22, 24...31 => return error.InvalidType,
        else => {
            try writer.writeByte(0xf8);
            try writer.writeByte(code);
        },
    }
}

fn encodeNullAlloc(allocator: std.mem.Allocator) ![]u8 {
    const out = try allocator.alloc(u8, 1);
    out[0] = 0xf6;
    return out;
}

fn encodeBoolAlloc(allocator: std.mem.Allocator, value: bool) ![]u8 {
    const out = try allocator.alloc(u8, 1);
    out[0] = if (value) 0xf5 else 0xf4;
    return out;
}

fn encodeIntegerAlloc(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    var allocating = std.Io.Writer.Allocating.init(allocator);
    errdefer allocating.deinit();

    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .comptime_int => {
            if (value >= 0) {
                try writeHead(&allocating.writer, 0, std.math.cast(u64, value) orelse return error.IntegerOverflow);
            } else {
                try writeHead(&allocating.writer, 1, std.math.cast(u64, -1 - value) orelse return error.IntegerOverflow);
            }
        },
        .int => |int_info| switch (int_info.signedness) {
            .unsigned => try writeHead(&allocating.writer, 0, std.math.cast(u64, value) orelse return error.IntegerOverflow),
            .signed => {
                const signed = std.math.cast(i128, value) orelse return error.IntegerOverflow;
                if (signed >= 0) {
                    try writeHead(&allocating.writer, 0, @intCast(signed));
                } else {
                    try writeHead(&allocating.writer, 1, std.math.cast(u64, -1 - signed) orelse return error.IntegerOverflow);
                }
            },
        },
        else => @compileError("CBOR integers require an integer value"),
    }

    return try allocating.toOwnedSlice();
}

fn encodeFloatAlloc(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    var allocating = std.Io.Writer.Allocating.init(allocator);
    errdefer allocating.deinit();

    const T = @TypeOf(value);
    const Float = switch (@typeInfo(T)) {
        .comptime_float => f64,
        .float => if (@bitSizeOf(T) <= 16) f16 else if (@bitSizeOf(T) <= 32) f32 else f64,
        else => @compileError("CBOR floats require a float value"),
    };
    const float_value: Float = value;
    const Int = std.meta.Int(.unsigned, @bitSizeOf(Float));
    const raw: Int = @bitCast(float_value);

    try allocating.writer.writeByte(switch (Float) {
        f16 => 0xf9,
        f32 => 0xfa,
        f64 => 0xfb,
        else => unreachable,
    });
    try writeBig(&allocating.writer, Int, raw);
    return try allocating.toOwnedSlice();
}

fn encodeStringAlloc(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidUtf8;
    var allocating = std.Io.Writer.Allocating.init(allocator);
    errdefer allocating.deinit();
    try writeHead(&allocating.writer, 3, value.len);
    try allocating.writer.writeAll(value);
    return try allocating.toOwnedSlice();
}

fn encodeBytesAlloc(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    var allocating = std.Io.Writer.Allocating.init(allocator);
    errdefer allocating.deinit();
    try writeHead(&allocating.writer, 2, value.len);
    try allocating.writer.writeAll(value);
    return try allocating.toOwnedSlice();
}

fn encodeSimpleAlloc(allocator: std.mem.Allocator, value: u8) ![]u8 {
    var allocating = std.Io.Writer.Allocating.init(allocator);
    errdefer allocating.deinit();
    try writeCborSimple(&allocating.writer, value);
    return try allocating.toOwnedSlice();
}

fn encodeDeterministicExtensionAlloc(allocator: std.mem.Allocator, extension: events.Extension) ![]u8 {
    var allocating = std.Io.Writer.Allocating.init(allocator);
    errdefer allocating.deinit();
    try writeDeterministicExtension(allocator, &allocating.writer, extension);
    return try allocating.toOwnedSlice();
}

fn writeDeterministicValue(allocator: std.mem.Allocator, writer: *std.Io.Writer, value: events.Value) anyerror!void {
    switch (value) {
        .null => try writer.writeByte(0xf6),
        .bool => |actual| try writer.writeByte(if (actual) 0xf5 else 0xf4),
        .int => |actual| {
            const encoded = try encodeIntegerAlloc(allocator, actual);
            defer allocator.free(encoded);
            try writer.writeAll(encoded);
        },
        .float => |actual| {
            const encoded = try encodeFloatAlloc(allocator, actual);
            defer allocator.free(encoded);
            try writer.writeAll(encoded);
        },
        .string, .enum_tag, .datetime => |actual| {
            const encoded = try encodeStringAlloc(allocator, actual);
            defer allocator.free(encoded);
            try writer.writeAll(encoded);
        },
        .bytes => |actual| {
            const encoded = try encodeBytesAlloc(allocator, actual);
            defer allocator.free(encoded);
            try writer.writeAll(encoded);
        },
        .extension => |actual| try writeDeterministicExtension(allocator, writer, actual),
        .seq => |items| {
            try writeHead(writer, 4, items.len);
            for (items) |item| try writeDeterministicValue(allocator, writer, item);
        },
        .struct_ => |fields| {
            var sorted = try allocator.alloc(DeterministicValueField, fields.len);
            defer allocator.free(sorted);

            var initialized: usize = 0;
            errdefer for (sorted[0..initialized]) |field| allocator.free(field.key);

            for (fields, 0..) |*field, i| {
                sorted[i] = .{ .key = try encodeStringAlloc(allocator, field.name), .field = field };
                initialized += 1;
            }

            sortDeterministicValueFields(sorted);
            defer for (sorted) |field| allocator.free(field.key);

            try writeHead(writer, 5, fields.len);
            for (sorted) |entry| {
                try writer.writeAll(entry.key);
                try writeDeterministicValue(allocator, writer, entry.field.value);
            }
        },
    }
}

const DeterministicValueField = struct {
    key: []u8,
    field: *const events.ObjectField,
};

fn writeDeterministicExtension(allocator: std.mem.Allocator, writer: *std.Io.Writer, extension: events.Extension) anyerror!void {
    switch (extension) {
        .tagged => |tagged| {
            if (tagged.namespace != .cbor) return error.UnsupportedEventKind;
            try writeHead(writer, 6, try extensionIdUnsigned(tagged.id));
            try writeDeterministicValue(allocator, writer, tagged.value.*);
        },
        .simple => |simple| {
            if (simple.namespace != .cbor) return error.UnsupportedEventKind;
            try writeCborSimple(writer, try extensionIdU8(simple.id));
        },
        .opaque_ => return error.UnsupportedEventKind,
    }
}

fn sortEncodedFields(fields: []DeterministicEncoder.EncodedField) void {
    var index: usize = 1;
    while (index < fields.len) : (index += 1) {
        var inner = index;
        while (inner != 0 and std.mem.lessThan(u8, fields[inner].key, fields[inner - 1].key)) : (inner -= 1) {
            std.mem.swap(DeterministicEncoder.EncodedField, &fields[inner], &fields[inner - 1]);
        }
    }
}

fn sortDeterministicValueFields(fields: []DeterministicValueField) void {
    var index: usize = 1;
    while (index < fields.len) : (index += 1) {
        var inner = index;
        while (inner != 0 and std.mem.lessThan(u8, fields[inner].key, fields[inner - 1].key)) : (inner -= 1) {
            std.mem.swap(DeterministicValueField, &fields[inner], &fields[inner - 1]);
        }
    }
}

fn expectCbor(value: anytype, expected: []const u8) !void {
    const bytes = try writeAlloc(std.testing.allocator, value);
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualSlices(u8, expected, bytes);
}

fn expectCborWithOptions(value: anytype, options: WriteOptions, expected: []const u8) !void {
    const bytes = try writeAllocWithOptions(std.testing.allocator, value, options);
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualSlices(u8, expected, bytes);
}

fn expectReadValue(comptime T: type, input: []const u8, expected: T) !void {
    const actual = try readSlice(T, std.testing.allocator, input);
    try std.testing.expectEqual(expected, actual);
}

fn expectReadString(input: []const u8, expected: []const u8) !void {
    const actual = try readSlice([]const u8, std.testing.allocator, input);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings(expected, actual);
}

fn expectReadBytes(input: []const u8, expected: []const u8) !void {
    var reader: std.Io.Reader = .fixed(input);
    var dec = decoder(&reader, std.testing.allocator);
    const actual = try dec.readBytes(std.testing.allocator);
    defer std.testing.allocator.free(actual);
    try dec.finish();
    try std.testing.expectEqualSlices(u8, expected, actual);
}

fn expectSkips(input: []const u8) !void {
    var reader: std.Io.Reader = .fixed(input);
    var dec = decoder(&reader, std.testing.allocator);
    try dec.skipValue();
    try dec.finish();
}

fn expectMalformed(input: []const u8) !void {
    expectSkips(input) catch return;
    return error.ExpectedMalformedCbor;
}

test "cbor writes primitive values with shortest heads" {
    try expectCbor(null, &.{0xf6});
    try expectCbor(true, &.{0xf5});
    try expectCbor(false, &.{0xf4});
    try expectCbor(@as(u8, 23), &.{0x17});
    try expectCbor(@as(u8, 24), &.{ 0x18, 0x18 });
    try expectCbor(@as(u16, 256), &.{ 0x19, 0x01, 0x00 });
    try expectCbor(@as(u32, 65536), &.{ 0x1a, 0x00, 0x01, 0x00, 0x00 });
    try expectCbor(@as(i8, -1), &.{0x20});
    try expectCbor(@as(i8, -24), &.{0x37});
    try expectCbor(@as(i8, -25), &.{ 0x38, 0x18 });
    try expectCbor(@as(f32, 1.5), &.{ 0xfa, 0x3f, 0xc0, 0x00, 0x00 });
    try expectCbor(@as(f64, 1.5), &.{ 0xfb, 0x3f, 0xf8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 });
}

test "cbor writes strings bytes arrays and maps" {
    try expectCbor("Ada", &.{ 0x63, 'A', 'd', 'a' });
    try expectCbor([3]u8{ 1, 2, 3 }, &.{ 0x83, 0x01, 0x02, 0x03 });

    const User = struct {
        id: u8,
        name: []const u8,
    };
    try expectCbor(User{ .id = 1, .name = "Ada" }, &.{
        0xa2,
        0x62, 'i', 'd', 0x01,
        0x64, 'n', 'a', 'm', 'e', 0x63, 'A', 'd', 'a',
    });

    const Blob = struct {
        data: []const u8,

        pub const zerde = .{ .fields = .{ .data = .{ .bytes = true } } };
    };
    try expectCbor(Blob{ .data = &.{ 0, 1, 2 } }, &.{ 0xa1, 0x64, 'd', 'a', 't', 'a', 0x43, 0x00, 0x01, 0x02 });
}

test "cbor deterministic write sorts map keys by encoded bytes" {
    const Value = struct {
        z: u8,
        aa: u8,
        a: u8,
    };

    const value = Value{ .z = 1, .aa = 2, .a = 3 };

    try expectCbor(value, &.{
        0xa3,
        0x61, 'z', 0x01,
        0x62, 'a', 'a', 0x02,
        0x61, 'a', 0x03,
    });
    try expectCborWithOptions(value, .{ .deterministic = true }, &.{
        0xa3,
        0x61, 'a', 0x03,
        0x61, 'z', 0x01,
        0x62, 'a', 'a', 0x02,
    });
}

test "cbor deterministic write sorts by encoded key not text order" {
    const Value = struct {
        @"aaaaaaaaaaaaaaaaaaaaaaaa": u8,
        b: u8,
    };

    try expectCborWithOptions(Value{ .@"aaaaaaaaaaaaaaaaaaaaaaaa" = 1, .b = 2 }, .{ .deterministic = true }, &.{
        0xa2,
        0x61, 'b', 0x02,
        0x78, 0x18,
        'a',  'a',  'a',  'a',  'a',  'a',  'a',  'a',
        'a',  'a',  'a',  'a',  'a',  'a',  'a',  'a',
        'a',  'a',  'a',  'a',  'a',  'a',  'a',  'a',
        0x01,
    });
}

test "cbor deterministic write sorts nested maps and preserves scalar encodings" {
    const Inner = struct {
        b: f32,
        a: i8,
    };
    const Outer = struct {
        z: Inner,
        a: u8,
    };

    try expectCborWithOptions(Outer{ .z = .{ .b = 1.5, .a = -1 }, .a = 7 }, .{ .deterministic = true }, &.{
        0xa2,
        0x61, 'a', 0x07,
        0x61, 'z', 0xa2,
        0x61, 'a', 0x20,
        0x61, 'b', 0xfa, 0x3f, 0xc0, 0x00, 0x00,
    });
}

test "cbor deterministic write preserves low-level tags around sorted maps" {
    const Tagged = struct {
        z: u8,
        a: u8,

        pub fn zerdeWrite(value: @This(), enc: anytype) !void {
            try enc.emitTag(42);
            try enc.beginStruct(@This(), 2);
            try enc.emitFieldName("z");
            try enc.emitInt(value.z);
            try enc.emitFieldName("a");
            try enc.emitInt(value.a);
            try enc.endStruct();
        }
    };

    try expectCborWithOptions(Tagged{ .z = 1, .a = 2 }, .{ .deterministic = true }, &.{
        0xd8, 0x2a,
        0xa2,
        0x61, 'a', 0x02,
        0x61, 'z', 0x01,
    });
}

test "cbor deterministic event encoder sorts maps and preserves tags" {
    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    var enc = eventEncoderWithOptions(&out.writer, std.testing.allocator, .{ .deterministic = true });
    defer enc.deinit();
    try enc.emitTag(1);
    try enc.beginStructEvent(3);
    try enc.emitFieldName("z");
    try enc.emitInt(1);
    try enc.emitFieldName("aa");
    try enc.emitInt(2);
    try enc.emitFieldName("a");
    try enc.emitInt(3);
    try enc.endStruct();
    try enc.finish();

    try std.testing.expectEqualSlices(u8, &.{
        0xc1,
        0xa3,
        0x61, 'a', 0x03,
        0x61, 'z', 0x01,
        0x62, 'a', 'a', 0x02,
    }, out.writer.buffered());
}

test "cbor deterministic event encoder sorts maps containing extensions" {
    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();

    var enc = eventEncoderWithOptions(&out.writer, std.testing.allocator, .{ .deterministic = true });
    defer enc.deinit();
    try enc.beginStructEvent(2);
    try enc.emitFieldName("z");
    try enc.emitSimple(23);
    try enc.emitFieldName("a");
    try enc.emitTag(24);
    try enc.emitBytes(&.{0});
    try enc.endStruct();
    try enc.finish();

    try std.testing.expectEqualSlices(u8, &.{
        0xa2,
        0x61, 'a', 0xd8, 0x18, 0x41, 0x00,
        0x61, 'z', 0xf7,
    }, out.writer.buffered());
}

test "cbor deterministic event value write sorts buffered object fields" {
    const allocator = std.testing.allocator;

    var fields = try allocator.alloc(events.ObjectField, 3);
    errdefer allocator.free(fields);
    fields[0] = .{ .name = try allocator.dupe(u8, "z"), .value = .{ .int = 1 } };
    errdefer allocator.free(fields[0].name);
    fields[1] = .{ .name = try allocator.dupe(u8, "aa"), .value = .{ .int = 2 } };
    errdefer allocator.free(fields[1].name);
    fields[2] = .{ .name = try allocator.dupe(u8, "a"), .value = .{ .int = 3 } };
    errdefer allocator.free(fields[2].name);

    var value: events.Value = .{ .struct_ = fields };
    defer value.deinit(allocator);

    var out = std.Io.Writer.Allocating.init(allocator);
    defer out.deinit();

    var enc = eventEncoderWithOptions(&out.writer, allocator, .{ .deterministic = true });
    defer enc.deinit();
    try value.write(&enc);
    try enc.finish();

    try std.testing.expectEqualSlices(u8, &.{
        0xa3,
        0x61, 'a', 0x03,
        0x61, 'z', 0x01,
        0x62, 'a', 'a', 0x02,
    }, out.writer.buffered());
}

test "cbor roundtrips supported reflected shapes" {
    const Color = enum { red, green, blue };
    const Shape = union(enum) {
        point,
        circle: struct { radius: u16 },
    };
    const Value = struct {
        name: []const u8,
        scores: []const u16,
        color: Color,
        shape: Shape,
        nickname: ?[]const u8,
    };

    const scores = [_]u16{ 10, 20, 30 };
    const original = Value{
        .name = "Ada",
        .scores = scores[0..],
        .color = .green,
        .shape = .{ .circle = .{ .radius = 7 } },
        .nickname = null,
    };

    const bytes = try writeAlloc(std.testing.allocator, original);
    defer std.testing.allocator.free(bytes);

    const parsed = try readSlice(Value, std.testing.allocator, bytes);
    defer deinitValue(Value, std.testing.allocator, parsed);

    try std.testing.expectEqualStrings(original.name, parsed.name);
    try std.testing.expectEqualSlices(u16, original.scores, parsed.scores);
    try std.testing.expectEqual(original.color, parsed.color);
    try std.testing.expect(parsed.nickname == null);
    switch (parsed.shape) {
        .circle => |circle| try std.testing.expectEqual(@as(u16, 7), circle.radius),
        .point => return error.InvalidValue,
    }
}

test "cbor roundtrips metadata hooks and std containers" {
    const BoolAsYesNo = struct {
        pub fn write(value: bool, enc: anytype) !void {
            try enc.emitString(if (value) "yes" else "no");
        }

        pub fn read(comptime T: type, allocator: std.mem.Allocator, dec: anytype) !T {
            const value = try dec.readString(allocator);
            defer allocator.free(value);
            if (std.mem.eql(u8, value, "yes")) return true;
            if (std.mem.eql(u8, value, "no")) return false;
            return error.InvalidValue;
        }
    };

    const Value = struct {
        user_id: u64,
        password_hash: []const u8 = "secret",
        active: bool,
        list: std.ArrayList([]const u8),
        map: std.array_hash_map.String(u8),

        pub const zerde = .{
            .rename_all = .camel_case,
            .fields = .{
                .password_hash = .{ .skip = true },
                .active = .{ .with = BoolAsYesNo },
            },
        };
    };

    const allocator = std.testing.allocator;
    var original = Value{
        .user_id = 42,
        .password_hash = "secret",
        .active = true,
        .list = .empty,
        .map = .empty,
    };
    defer original.list.deinit(allocator);
    defer original.map.deinit(allocator);
    try original.list.append(allocator, "alpha");
    try original.list.append(allocator, "beta");
    try original.map.put(allocator, "one", 1);
    try original.map.put(allocator, "two", 2);

    const bytes = try writeAlloc(allocator, original);
    defer allocator.free(bytes);

    const parsed = try readSlice(Value, allocator, bytes);
    defer deinitValue(Value, allocator, parsed);

    try std.testing.expectEqual(@as(u64, 42), parsed.user_id);
    try std.testing.expectEqualStrings("secret", parsed.password_hash);
    try std.testing.expect(parsed.active);
    try std.testing.expectEqualStrings("alpha", parsed.list.items[0]);
    try std.testing.expectEqualStrings("beta", parsed.list.items[1]);
    try std.testing.expectEqual(@as(u8, 1), parsed.map.get("one").?);
    try std.testing.expectEqual(@as(u8, 2), parsed.map.get("two").?);
}

test "cbor roundtrips alternate tagged union representations" {
    const Adjacent = union(enum) {
        point,
        circle: struct { radius: u8 },

        pub const zerde = .{ .union_repr = .adjacent };
    };
    const Internal = union(enum) {
        point,
        circle: struct { radius: u8 },

        pub const zerde = .{ .union_repr = .internal };
    };

    const adjacent_bytes = try writeAlloc(std.testing.allocator, Adjacent{ .circle = .{ .radius = 4 } });
    defer std.testing.allocator.free(adjacent_bytes);
    const adjacent = try readSlice(Adjacent, std.testing.allocator, adjacent_bytes);
    switch (adjacent) {
        .circle => |circle| try std.testing.expectEqual(@as(u8, 4), circle.radius),
        .point => return error.InvalidValue,
    }

    const internal_bytes = try writeAlloc(std.testing.allocator, Internal{ .circle = .{ .radius = 5 } });
    defer std.testing.allocator.free(internal_bytes);
    const internal = try readSlice(Internal, std.testing.allocator, internal_bytes);
    switch (internal) {
        .circle => |circle| try std.testing.expectEqual(@as(u8, 5), circle.radius),
        .point => return error.InvalidValue,
    }
}

test "cbor reads indefinite strings arrays and maps" {
    const text = try readSlice([]const u8, std.testing.allocator, &.{ 0x7f, 0x61, 'a', 0x62, 'b', 'c', 0xff });
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("abc", text);

    const list = try readSlice([]const u16, std.testing.allocator, &.{ 0x9f, 0x01, 0x02, 0x03, 0xff });
    defer std.testing.allocator.free(list);
    try std.testing.expectEqualSlices(u16, &.{ 1, 2, 3 }, list);

    const User = struct { id: u8, name: []const u8 };
    const user = try readSlice(User, std.testing.allocator, &.{
        0xbf,
        0x62, 'i', 'd', 0x01,
        0x64, 'n', 'a', 'm', 'e', 0x63, 'A', 'd', 'a',
        0xff,
    });
    defer deinitValue(User, std.testing.allocator, user);
    try std.testing.expectEqual(@as(u8, 1), user.id);
    try std.testing.expectEqualStrings("Ada", user.name);
}

test "cbor reads RFC 8949 Appendix A integer vectors" {
    try expectReadValue(u8, &.{0x00}, 0);
    try expectReadValue(u8, &.{0x01}, 1);
    try expectReadValue(u8, &.{0x0a}, 10);
    try expectReadValue(u8, &.{0x17}, 23);
    try expectReadValue(u8, &.{ 0x18, 0x18 }, 24);
    try expectReadValue(u8, &.{ 0x18, 0x19 }, 25);
    try expectReadValue(u8, &.{ 0x18, 0x64 }, 100);
    try expectReadValue(u16, &.{ 0x19, 0x03, 0xe8 }, 1000);
    try expectReadValue(u32, &.{ 0x1a, 0x00, 0x0f, 0x42, 0x40 }, 1000000);
    try expectReadValue(u64, &.{ 0x1b, 0x00, 0x00, 0x00, 0xe8, 0xd4, 0xa5, 0x10, 0x00 }, 1000000000000);
    try expectReadValue(u64, &.{ 0x1b, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff }, std.math.maxInt(u64));

    try expectReadValue(i8, &.{0x20}, -1);
    try expectReadValue(i8, &.{0x29}, -10);
    try expectReadValue(i8, &.{ 0x38, 0x63 }, -100);
    try expectReadValue(i16, &.{ 0x39, 0x03, 0xe7 }, -1000);
    try expectReadValue(i128, &.{ 0x3b, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff }, -18446744073709551616);
}

test "cbor reads RFC 8949 Appendix A simple and float vectors" {
    try expectReadValue(bool, &.{0xf4}, false);
    try expectReadValue(bool, &.{0xf5}, true);
    try std.testing.expectEqual(null, try readSlice(?u8, std.testing.allocator, &.{0xf6}));
    try std.testing.expectError(error.UnsupportedCborSimpleValue, readSlice(?u8, std.testing.allocator, &.{0xf7}));

    const User = struct { id: u8 };
    const user = try readSlice(User, std.testing.allocator, &.{
        0xa2,
        0x62, 'i', 'd', 0x01,
        0x69, 'u', 'n', 'd', 'e', 'f', 'i', 'n', 'e', 'd', 0xf7,
    });
    try std.testing.expectEqual(@as(u8, 1), user.id);

    try expectReadValue(f64, &.{ 0xf9, 0x00, 0x00 }, 0.0);
    const negative_zero = try readSlice(f64, std.testing.allocator, &.{ 0xf9, 0x80, 0x00 });
    try std.testing.expectEqual(@as(u64, 0x8000000000000000), @as(u64, @bitCast(negative_zero)));
    try expectReadValue(f64, &.{ 0xf9, 0x3c, 0x00 }, 1.0);
    try expectReadValue(f64, &.{ 0xfb, 0x3f, 0xf1, 0x99, 0x99, 0x99, 0x99, 0x99, 0x9a }, 1.1);
    try expectReadValue(f64, &.{ 0xf9, 0x3e, 0x00 }, 1.5);
    try expectReadValue(f64, &.{ 0xf9, 0x7b, 0xff }, 65504.0);
    try expectReadValue(f64, &.{ 0xfa, 0x47, 0xc3, 0x50, 0x00 }, 100000.0);
    try expectReadValue(f32, &.{ 0xfa, 0x7f, 0x7f, 0xff, 0xff }, 3.4028234663852886e+38);
    try expectReadValue(f64, &.{ 0xfb, 0x7e, 0x37, 0xe4, 0x3c, 0x88, 0x00, 0x75, 0x9c }, 1.0e+300);
    try expectReadValue(f64, &.{ 0xf9, 0x00, 0x01 }, 5.960464477539063e-8);
    try expectReadValue(f64, &.{ 0xf9, 0x04, 0x00 }, 0.00006103515625);
    try expectReadValue(f64, &.{ 0xf9, 0xc4, 0x00 }, -4.0);
    try expectReadValue(f64, &.{ 0xfb, 0xc0, 0x10, 0x66, 0x66, 0x66, 0x66, 0x66, 0x66 }, -4.1);
    try std.testing.expect(std.math.isPositiveInf(try readSlice(f64, std.testing.allocator, &.{ 0xf9, 0x7c, 0x00 })));
    try std.testing.expect(std.math.isNan(try readSlice(f64, std.testing.allocator, &.{ 0xf9, 0x7e, 0x00 })));
    try std.testing.expect(std.math.isNegativeInf(try readSlice(f64, std.testing.allocator, &.{ 0xf9, 0xfc, 0x00 })));
    try std.testing.expect(std.math.isPositiveInf(try readSlice(f64, std.testing.allocator, &.{ 0xfa, 0x7f, 0x80, 0x00, 0x00 })));
    try std.testing.expect(std.math.isNan(try readSlice(f64, std.testing.allocator, &.{ 0xfa, 0x7f, 0xc0, 0x00, 0x00 })));
    try std.testing.expect(std.math.isNegativeInf(try readSlice(f64, std.testing.allocator, &.{ 0xfa, 0xff, 0x80, 0x00, 0x00 })));
    try std.testing.expect(std.math.isPositiveInf(try readSlice(f64, std.testing.allocator, &.{ 0xfb, 0x7f, 0xf0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 })));
    try std.testing.expect(std.math.isNan(try readSlice(f64, std.testing.allocator, &.{ 0xfb, 0x7f, 0xf8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 })));
    try std.testing.expect(std.math.isNegativeInf(try readSlice(f64, std.testing.allocator, &.{ 0xfb, 0xff, 0xf0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 })));
}

test "cbor reads RFC 8949 Appendix A string vectors" {
    try expectReadBytes(&.{0x40}, "");
    try expectReadBytes(&.{ 0x44, 0x01, 0x02, 0x03, 0x04 }, &.{ 0x01, 0x02, 0x03, 0x04 });
    try expectReadString(&.{0x60}, "");
    try expectReadString(&.{ 0x61, 'a' }, "a");
    try expectReadString(&.{ 0x64, 'I', 'E', 'T', 'F' }, "IETF");
    try expectReadString(&.{ 0x62, '"', '\\' }, "\"\\");
    try expectReadString(&.{ 0x62, 0xc3, 0xbc }, "\xc3\xbc");
    try expectReadString(&.{ 0x63, 0xe6, 0xb0, 0xb4 }, "\xe6\xb0\xb4");
    try expectReadString(&.{ 0x64, 0xf0, 0x90, 0x85, 0x91 }, "\xf0\x90\x85\x91");
}

test "cbor reads RFC 8949 Appendix A array and map vectors" {
    const empty = try readSlice([]const u16, std.testing.allocator, &.{0x80});
    defer std.testing.allocator.free(empty);
    try std.testing.expectEqual(@as(usize, 0), empty.len);

    const values = try readSlice([]const u16, std.testing.allocator, &.{ 0x83, 0x01, 0x02, 0x03 });
    defer std.testing.allocator.free(values);
    try std.testing.expectEqualSlices(u16, &.{ 1, 2, 3 }, values);

    const twenty_five = try readSlice([]const u16, std.testing.allocator, &.{
        0x98, 0x19, 0x01, 0x02, 0x03, 0x04, 0x05,
        0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c,
        0x0d, 0x0e, 0x0f, 0x10, 0x11, 0x12, 0x13,
        0x14, 0x15, 0x16, 0x17, 0x18, 0x18, 0x18, 0x19,
    });
    defer std.testing.allocator.free(twenty_five);
    try std.testing.expectEqualSlices(u16, &.{
        1, 2, 3, 4, 5,
        6, 7, 8, 9, 10,
        11, 12, 13, 14, 15,
        16, 17, 18, 19, 20,
        21, 22, 23, 24, 25,
    }, twenty_five);

    const Pair = struct { a: u8, b: []const u8 };
    const pair = try readSlice(Pair, std.testing.allocator, &.{ 0xa2, 0x61, 'a', 0x01, 0x61, 'b', 0x61, 'B' });
    defer deinitValue(Pair, std.testing.allocator, pair);
    try std.testing.expectEqual(@as(u8, 1), pair.a);
    try std.testing.expectEqualStrings("B", pair.b);

    const Nested = struct { b: []const u8 };
    const nested = try readSlice(Nested, std.testing.allocator, &.{ 0xa1, 0x61, 'b', 0x61, 'c' });
    defer deinitValue(Nested, std.testing.allocator, nested);
    try std.testing.expectEqualStrings("c", nested.b);

    try expectSkips(&.{ 0x83, 0x01, 0x82, 0x02, 0x03, 0x82, 0x04, 0x05 });
    try expectSkips(&.{ 0xa0 });
    try expectSkips(&.{ 0xa2, 0x01, 0x02, 0x03, 0x04 });
    try expectSkips(&.{ 0x82, 0x61, 'a', 0xa1, 0x61, 'b', 0x61, 'c' });
    try expectSkips(&.{ 0xa5, 0x61, 'a', 0x61, 'A', 0x61, 'b', 0x61, 'B', 0x61, 'c', 0x61, 'C', 0x61, 'd', 0x61, 'D', 0x61, 'e', 0x61, 'E' });
}

test "cbor reads RFC 8949 Appendix A indefinite vectors" {
    try expectReadBytes(&.{ 0x5f, 0x42, 0x01, 0x02, 0x43, 0x03, 0x04, 0x05, 0xff }, &.{ 0x01, 0x02, 0x03, 0x04, 0x05 });
    try expectReadString(&.{ 0x7f, 0x65, 's', 't', 'r', 'e', 'a', 0x64, 'm', 'i', 'n', 'g', 0xff }, "streaming");

    const empty = try readSlice([]const u16, std.testing.allocator, &.{ 0x9f, 0xff });
    defer std.testing.allocator.free(empty);
    try std.testing.expectEqual(@as(usize, 0), empty.len);

    const values = try readSlice([]const u16, std.testing.allocator, &.{
        0x9f, 0x01, 0x02, 0x03, 0x04, 0x05,
        0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c,
        0x0d, 0x0e, 0x0f, 0x10, 0x11, 0x12, 0x13,
        0x14, 0x15, 0x16, 0x17, 0x18, 0x18, 0x18, 0x19, 0xff,
    });
    defer std.testing.allocator.free(values);
    try std.testing.expectEqualSlices(u16, &.{
        1, 2, 3, 4, 5,
        6, 7, 8, 9, 10,
        11, 12, 13, 14, 15,
        16, 17, 18, 19, 20,
        21, 22, 23, 24, 25,
    }, values);

    const Pair = struct { a: u8, b: []const u8 };
    const pair = try readSlice(Pair, std.testing.allocator, &.{ 0xbf, 0x61, 'a', 0x01, 0x61, 'b', 0x61, 'B', 0xff });
    defer deinitValue(Pair, std.testing.allocator, pair);
    try std.testing.expectEqual(@as(u8, 1), pair.a);
    try std.testing.expectEqualStrings("B", pair.b);

    try expectSkips(&.{ 0x9f, 0x01, 0x82, 0x02, 0x03, 0x9f, 0x04, 0x05, 0xff, 0xff });
    try expectSkips(&.{ 0x9f, 0x01, 0x82, 0x02, 0x03, 0x82, 0x04, 0x05, 0xff });
    try expectSkips(&.{ 0x83, 0x01, 0x82, 0x02, 0x03, 0x9f, 0x04, 0x05, 0xff });
    try expectSkips(&.{ 0x83, 0x01, 0x9f, 0x02, 0x03, 0xff, 0x82, 0x04, 0x05 });
    try expectSkips(&.{ 0xbf, 0x61, 'a', 0x01, 0x61, 'b', 0x9f, 0x02, 0x03, 0xff, 0xff });
    try expectSkips(&.{ 0x82, 0x61, 'a', 0xbf, 0x61, 'b', 0x61, 'c', 0xff });
    try expectSkips(&.{ 0xbf, 0x63, 'F', 'u', 'n', 0xf5, 0x63, 'A', 'm', 't', 0x21, 0xff });
}

test "cbor rejects RFC 8949 Appendix F truncated input" {
    const cases = [_][]const u8{
        &.{0x18},
        &.{0x19},
        &.{0x1a},
        &.{0x1b},
        &.{ 0x19, 0x01 },
        &.{ 0x1a, 0x01, 0x02 },
        &.{ 0x1b, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07 },
        &.{0x38},
        &.{0x58},
        &.{0x78},
        &.{0x98},
        &.{ 0x9a, 0x01, 0xff, 0x00 },
        &.{0xb8},
        &.{0xd8},
        &.{0xf8},
        &.{ 0xf9, 0x00 },
        &.{ 0xfa, 0x00, 0x00 },
        &.{ 0xfb, 0x00, 0x00, 0x00 },
        &.{0x41},
        &.{0x61},
        &.{ 0x5a, 0xff, 0xff, 0xff, 0xff, 0x00 },
        &.{ 0x5b, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01, 0x02, 0x03 },
        &.{ 0x7a, 0xff, 0xff, 0xff, 0xff, 0x00 },
        &.{ 0x7b, 0x7f, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x01, 0x02, 0x03 },
        &.{0x81},
        &.{ 0x81, 0x81, 0x81, 0x81, 0x81, 0x81, 0x81, 0x81, 0x81, 0x81 },
        &.{ 0x82, 0x00 },
        &.{0xa1},
        &.{ 0xa2, 0x01, 0x02 },
        &.{ 0xa1, 0x00 },
        &.{ 0xa2, 0x00, 0x00, 0x00 },
        &.{0xc0},
        &.{ 0x5f, 0x41, 0x00 },
        &.{ 0x7f, 0x61, 0x00 },
        &.{0x9f},
        &.{ 0x9f, 0x01, 0x02 },
        &.{0xbf},
        &.{ 0xbf, 0x01, 0x02, 0x01, 0x02 },
        &.{ 0x81, 0x9f },
        &.{ 0x9f, 0x80, 0x00 },
        &.{ 0x9f, 0x9f, 0x9f, 0x9f, 0x9f, 0xff, 0xff, 0xff, 0xff },
        &.{ 0x9f, 0x81, 0x9f, 0x81, 0x9f, 0x9f, 0xff, 0xff, 0xff },
    };
    for (cases) |input| try expectMalformed(input);
}

test "cbor rejects RFC 8949 Appendix F syntax errors" {
    const reserved_ai = [_][]const u8{
        &.{0x1c}, &.{0x1d}, &.{0x1e},
        &.{0x3c}, &.{0x3d}, &.{0x3e},
        &.{0x5c}, &.{0x5d}, &.{0x5e},
        &.{0x7c}, &.{0x7d}, &.{0x7e},
        &.{0x9c}, &.{0x9d}, &.{0x9e},
        &.{0xbc}, &.{0xbd}, &.{0xbe},
        &.{0xdc}, &.{0xdd}, &.{0xde},
        &.{0xfc}, &.{0xfd}, &.{0xfe},
    };
    for (reserved_ai) |input| try expectMalformed(input);

    const invalid_simple = [_][]const u8{
        &.{ 0xf8, 0x00 },
        &.{ 0xf8, 0x01 },
        &.{ 0xf8, 0x18 },
        &.{ 0xf8, 0x1f },
    };
    for (invalid_simple) |input| try expectMalformed(input);

    const invalid_string_chunks = [_][]const u8{
        &.{ 0x5f, 0x00, 0xff },
        &.{ 0x5f, 0x21, 0xff },
        &.{ 0x5f, 0x61, 0x00, 0xff },
        &.{ 0x5f, 0x80, 0xff },
        &.{ 0x5f, 0xa0, 0xff },
        &.{ 0x5f, 0xc0, 0x00, 0xff },
        &.{ 0x5f, 0xe0, 0xff },
        &.{ 0x7f, 0x41, 0x00, 0xff },
        &.{ 0x5f, 0x5f, 0x41, 0x00, 0xff, 0xff },
        &.{ 0x7f, 0x7f, 0x61, 0x00, 0xff, 0xff },
    };
    for (invalid_string_chunks) |input| try expectMalformed(input);

    const invalid_breaks = [_][]const u8{
        &.{0xff},
        &.{ 0x81, 0xff },
        &.{ 0x82, 0x00, 0xff },
        &.{ 0xa1, 0xff },
        &.{ 0xa1, 0xff, 0x00 },
        &.{ 0xa1, 0x00, 0xff },
        &.{ 0xa2, 0x00, 0x00, 0xff },
        &.{ 0x9f, 0x81, 0xff },
        &.{ 0x9f, 0x82, 0x9f, 0x81, 0x9f, 0x9f, 0xff, 0xff, 0xff, 0xff },
        &.{ 0xbf, 0x00, 0xff },
        &.{ 0xbf, 0x00, 0x00, 0x00, 0xff },
    };
    for (invalid_breaks) |input| try expectMalformed(input);

    const invalid_indefinite_major = [_][]const u8{
        &.{0x1f},
        &.{0x3f},
        &.{0xdf},
    };
    for (invalid_indefinite_major) |input| try expectMalformed(input);
}

test "cbor rejects RFC 8949 Appendix F trailing input" {
    try expectMalformed(&.{ 0x00, 0x00 });
    try std.testing.expectError(error.InvalidCborTrailingData, readSlice(u8, std.testing.allocator, &.{ 0x00, 0x00 }));
}

test "cbor rejects typed values outside the Zerde data model" {
    try std.testing.expectError(error.UnsupportedCborTag, readSlice(u8, std.testing.allocator, &.{ 0xc0, 0x00 }));
    try std.testing.expectError(error.UnsupportedCborTag, readSlice(u8, std.testing.allocator, &.{ 0xd8, 0x18, 0x41, 0x00 }));
    try std.testing.expectError(error.UnsupportedCborSimpleValue, readSlice(?u8, std.testing.allocator, &.{0xe0}));
    try std.testing.expectError(error.UnsupportedCborSimpleValue, readSlice(?u8, std.testing.allocator, &.{ 0xf8, 0xff }));

    var reader: std.Io.Reader = .fixed(&.{ 0xd8, 0x18, 0x41, 0x00 });
    var dec = decoder(&reader, std.testing.allocator);
    var value = try events.readAlloc(std.testing.allocator, &dec);
    defer value.deinit(std.testing.allocator);
    try dec.finish();

    switch (value.extension) {
        .tagged => |tagged| {
            try std.testing.expectEqual(events.Extension.Namespace.cbor, tagged.namespace);
            try std.testing.expectEqual(@as(u64, 24), tagged.id.unsigned);
            try std.testing.expectEqualSlices(u8, &.{0}, tagged.value.bytes);
        },
        else => return error.InvalidValue,
    }
}

test "cbor low-level encoder and decoder support tags and simple values" {
    var tagged_out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer tagged_out.deinit();
    var tagged_enc = encoder(&tagged_out.writer);
    try tagged_enc.emitTag(1);
    try tagged_enc.emitString("time");
    try tagged_enc.finish();
    try std.testing.expectEqualSlices(u8, &.{ 0xc1, 0x64, 't', 'i', 'm', 'e' }, tagged_out.writer.buffered());

    var tagged_reader: std.Io.Reader = .fixed(tagged_out.writer.buffered());
    var tagged_dec = decoder(&tagged_reader, std.testing.allocator);
    try std.testing.expectEqual(Kind.extension, try tagged_dec.peek());
    try std.testing.expectEqual(@as(u64, 1), try tagged_dec.readTag());
    const tagged_value = try tagged_dec.readString(std.testing.allocator);
    defer std.testing.allocator.free(tagged_value);
    try std.testing.expectEqualStrings("time", tagged_value);
    try tagged_dec.finish();

    var simple_out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer simple_out.deinit();
    var simple_enc = encoder(&simple_out.writer);
    try simple_enc.emitSimple(23);
    try simple_enc.finish();
    try std.testing.expectEqualSlices(u8, &.{0xf7}, simple_out.writer.buffered());

    var simple_reader: std.Io.Reader = .fixed(simple_out.writer.buffered());
    var simple_dec = decoder(&simple_reader, std.testing.allocator);
    try std.testing.expectEqual(Kind.extension, try simple_dec.peek());
    try std.testing.expectEqual(@as(u8, 23), try simple_dec.readSimple());
    try simple_dec.finish();
}

test "cbor low-level supports stacked tags and extended simple codes" {
    var tagged_out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer tagged_out.deinit();
    var tagged_enc = encoder(&tagged_out.writer);
    try tagged_enc.emitTag(55799);
    try tagged_enc.emitTag(24);
    try tagged_enc.emitBytes(&.{0x01});
    try tagged_enc.finish();
    try std.testing.expectEqualSlices(u8, &.{ 0xd9, 0xd9, 0xf7, 0xd8, 0x18, 0x41, 0x01 }, tagged_out.writer.buffered());

    var tagged_reader: std.Io.Reader = .fixed(tagged_out.writer.buffered());
    var tagged_dec = decoder(&tagged_reader, std.testing.allocator);
    try std.testing.expectEqual(@as(u64, 55799), try tagged_dec.readTag());
    try std.testing.expectEqual(@as(u64, 24), try tagged_dec.readTag());
    const tagged_bytes = try tagged_dec.readBytes(std.testing.allocator);
    defer std.testing.allocator.free(tagged_bytes);
    try std.testing.expectEqualSlices(u8, &.{0x01}, tagged_bytes);
    try tagged_dec.finish();

    var simple_out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer simple_out.deinit();
    var simple_enc = encoder(&simple_out.writer);
    try simple_enc.beginSeq(5);
    try simple_enc.emitSimple(0);
    try simple_enc.emitSimple(19);
    try simple_enc.emitSimple(23);
    try simple_enc.emitSimple(32);
    try simple_enc.emitSimple(255);
    try simple_enc.endSeq();
    try simple_enc.finish();
    try std.testing.expectEqualSlices(u8, &.{ 0x85, 0xe0, 0xf3, 0xf7, 0xf8, 0x20, 0xf8, 0xff }, simple_out.writer.buffered());

    var simple_reader: std.Io.Reader = .fixed(simple_out.writer.buffered());
    var simple_dec = decoder(&simple_reader, std.testing.allocator);
    try std.testing.expectEqual(@as(?usize, 5), try simple_dec.beginSeq());
    try std.testing.expect(try simple_dec.hasNextSeqElem());
    try std.testing.expectEqual(@as(u8, 0), try simple_dec.readSimple());
    try std.testing.expect(try simple_dec.hasNextSeqElem());
    try std.testing.expectEqual(@as(u8, 19), try simple_dec.readSimple());
    try std.testing.expect(try simple_dec.hasNextSeqElem());
    try std.testing.expectEqual(@as(u8, 23), try simple_dec.readSimple());
    try std.testing.expect(try simple_dec.hasNextSeqElem());
    try std.testing.expectEqual(@as(u8, 32), try simple_dec.readSimple());
    try std.testing.expect(try simple_dec.hasNextSeqElem());
    try std.testing.expectEqual(@as(u8, 255), try simple_dec.readSimple());
    try std.testing.expect(!try simple_dec.hasNextSeqElem());
    try simple_dec.endSeq();
    try simple_dec.finish();
}

test "cbor low-level rejects invalid tag and simple operations" {
    var simple_writer = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer simple_writer.deinit();
    var simple_enc = encoder(&simple_writer.writer);
    try std.testing.expectError(error.InvalidType, simple_enc.emitSimple(20));

    var tag_wrong_type_reader: std.Io.Reader = .fixed(&.{0xf7});
    var tag_wrong_type_dec = decoder(&tag_wrong_type_reader, std.testing.allocator);
    try std.testing.expectError(error.InvalidType, tag_wrong_type_dec.readTag());

    var tag_indef_reader: std.Io.Reader = .fixed(&.{0xdf});
    var tag_indef_dec = decoder(&tag_indef_reader, std.testing.allocator);
    try std.testing.expectError(error.InvalidCborSyntax, tag_indef_dec.readTag());

    var simple_bool_reader: std.Io.Reader = .fixed(&.{0xf4});
    var simple_bool_dec = decoder(&simple_bool_reader, std.testing.allocator);
    try std.testing.expectError(error.InvalidType, simple_bool_dec.readSimple());

    var simple_non_minimal_reader: std.Io.Reader = .fixed(&.{ 0xf8, 0x1f });
    var simple_non_minimal_dec = decoder(&simple_non_minimal_reader, std.testing.allocator);
    try std.testing.expectError(error.InvalidCborSyntax, simple_non_minimal_dec.readSimple());
}

test "cbor low-level tags wrap the next value in containers" {
    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();
    var enc = encoder(&out.writer);
    try enc.beginSeq(1);
    try enc.emitTag(42);
    try enc.emitInt(7);
    try enc.endSeq();
    try enc.finish();

    try std.testing.expectEqualSlices(u8, &.{ 0x81, 0xd8, 0x2a, 0x07 }, out.writer.buffered());

    var dangling_out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer dangling_out.deinit();
    var dangling_enc = encoder(&dangling_out.writer);
    try dangling_enc.emitTag(1);
    try std.testing.expectError(error.IncompleteCborDocument, dangling_enc.finish());
}

test "cbor custom hooks can use low-level tags" {
    const TaggedText = struct {
        value: []const u8,

        pub fn zerdeWrite(self: @This(), enc: anytype) !void {
            try enc.emitTag(0);
            try enc.emitString(self.value);
        }

        pub fn zerdeRead(allocator: std.mem.Allocator, dec: anytype) !@This() {
            if (try dec.readTag() != 0) return error.InvalidValue;
            return .{ .value = try dec.readString(allocator) };
        }
    };

    const bytes = try writeAlloc(std.testing.allocator, TaggedText{ .value = "2026-05-10T00:00:00Z" });
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualSlices(u8, &.{
        0xc0, 0x74, '2', '0', '2', '6', '-', '0', '5', '-', '1', '0', 'T', '0', '0', ':', '0', '0', ':', '0', '0', 'Z',
    }, bytes);

    const parsed = try readSlice(TaggedText, std.testing.allocator, bytes);
    defer deinitValue(TaggedText, std.testing.allocator, parsed);
    try std.testing.expectEqualStrings("2026-05-10T00:00:00Z", parsed.value);
}

test "cbor rejects numeric overflow and non-text struct keys" {
    try std.testing.expectError(error.IntegerOverflow, readSlice(u8, std.testing.allocator, &.{ 0x19, 0x01, 0x00 }));
    try std.testing.expectError(error.IntegerOverflow, readSlice(i8, std.testing.allocator, &.{ 0x18, 0x80 }));
    try std.testing.expectError(error.IntegerOverflow, readSlice(i8, std.testing.allocator, &.{ 0x38, 0x80 }));

    const User = struct { id: u8 };
    try std.testing.expectError(error.InvalidType, readSlice(User, std.testing.allocator, &.{ 0xa1, 0x01, 0x02 }));
}

test "cbor validates UTF-8 text and indefinite text chunks" {
    try std.testing.expectError(error.InvalidUtf8, readSlice([]const u8, std.testing.allocator, &.{ 0x61, 0xff }));
    try std.testing.expectError(error.InvalidUtf8, readSlice([]const u8, std.testing.allocator, &.{ 0x7f, 0x61, 0xc3, 0x61, 0xbc, 0xff }));

    const value = try readSlice([]const u8, std.testing.allocator, &.{ 0x7f, 0x62, 0xc3, 0xbc, 0xff });
    defer std.testing.allocator.free(value);
    try std.testing.expectEqualStrings("\xc3\xbc", value);
}

test "cbor skips unknown fields including tags and simple values" {
    const User = struct { id: u8 };
    const parsed = try readSlice(User, std.testing.allocator, &.{
        0xa3,
        0x62, 'i', 'd', 0x01,
        0x63, 't', 'a', 'g', 0xc1, 0x18, 0x2a,
        0x66, 's', 'i', 'm', 'p', 'l', 'e', 0xf7,
    });
    try std.testing.expectEqual(@as(u8, 1), parsed.id);
}

test "cbor rejects malformed and trailing input" {
    try std.testing.expectError(error.InvalidCborTrailingData, readSlice(u8, std.testing.allocator, &.{ 0x01, 0x02 }));
    try std.testing.expectError(error.EndOfStream, readSlice([]const u8, std.testing.allocator, &.{ 0x63, 'a' }));
    try std.testing.expectError(error.InvalidCborSyntax, readSlice([]const u8, std.testing.allocator, &.{ 0x7f, 0x41, 0x00, 0xff }));
    try std.testing.expectError(error.UnsupportedCborTag, readSlice(u8, std.testing.allocator, &.{ 0xc1, 0x01 }));
    try std.testing.expectError(error.UnsupportedCborSimpleValue, readSlice(?u8, std.testing.allocator, &.{0xf7}));
}

test "cbor event support preserves byte strings" {
    var reader: std.Io.Reader = .fixed(&.{ 0xa2, 0x64, 'n', 'a', 'm', 'e', 0x63, 'A', 'd', 'a', 0x64, 'd', 'a', 't', 'a', 0x42, 0x00, 0x01 });
    var dec = decoder(&reader, std.testing.allocator);
    var value = try events.readAlloc(std.testing.allocator, &dec);
    defer value.deinit(std.testing.allocator);
    try dec.finish();

    try std.testing.expectEqual(@as(usize, 2), value.struct_.len);
    try std.testing.expectEqualStrings("name", value.struct_[0].name);
    try std.testing.expectEqualStrings("Ada", value.struct_[0].value.string);
    try std.testing.expectEqualStrings("data", value.struct_[1].name);
    try std.testing.expectEqualSlices(u8, &.{ 0, 1 }, value.struct_[1].value.bytes);
}

test "cbor event support preserves tags and simple values" {
    const tagged_input = &.{ 0xc1, 0x63, 'a', 'b', 'c' };

    var tagged_reader: std.Io.Reader = .fixed(tagged_input);
    var tagged_dec = decoder(&tagged_reader, std.testing.allocator);
    var tagged_value = try events.readAlloc(std.testing.allocator, &tagged_dec);
    defer tagged_value.deinit(std.testing.allocator);
    try tagged_dec.finish();

    switch (tagged_value.extension) {
        .tagged => |tagged| {
            try std.testing.expectEqual(events.Extension.Namespace.cbor, tagged.namespace);
            try std.testing.expectEqual(@as(u64, 1), tagged.id.unsigned);
            try std.testing.expectEqualStrings("abc", tagged.value.string);
        },
        else => return error.InvalidValue,
    }

    var tagged_out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer tagged_out.deinit();
    var tagged_enc = encoder(&tagged_out.writer);
    try tagged_value.write(&tagged_enc);
    try tagged_enc.finish();
    try std.testing.expectEqualSlices(u8, tagged_input, tagged_out.writer.buffered());

    var simple_reader: std.Io.Reader = .fixed(&.{0xf7});
    var simple_dec = decoder(&simple_reader, std.testing.allocator);
    var simple_value = try events.readAlloc(std.testing.allocator, &simple_dec);
    defer simple_value.deinit(std.testing.allocator);
    try simple_dec.finish();

    switch (simple_value.extension) {
        .simple => |simple| {
            try std.testing.expectEqual(events.Extension.Namespace.cbor, simple.namespace);
            try std.testing.expectEqual(@as(u64, 23), simple.id.unsigned);
        },
        else => return error.InvalidValue,
    }

    var simple_out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer simple_out.deinit();
    var simple_enc = encoder(&simple_out.writer);
    try simple_value.write(&simple_enc);
    try simple_enc.finish();
    try std.testing.expectEqualSlices(u8, &.{0xf7}, simple_out.writer.buffered());
}

test "cbor event support preserves nested tags" {
    const input = &.{ 0xc1, 0xc2, 0x01 };

    var reader: std.Io.Reader = .fixed(input);
    var dec = decoder(&reader, std.testing.allocator);
    var value = try events.readAlloc(std.testing.allocator, &dec);
    defer value.deinit(std.testing.allocator);
    try dec.finish();

    switch (value.extension) {
        .tagged => |outer| {
            try std.testing.expectEqual(events.Extension.Namespace.cbor, outer.namespace);
            try std.testing.expectEqual(@as(u64, 1), outer.id.unsigned);
            switch (outer.value.extension) {
                .tagged => |inner| {
                    try std.testing.expectEqual(events.Extension.Namespace.cbor, inner.namespace);
                    try std.testing.expectEqual(@as(u64, 2), inner.id.unsigned);
                    try std.testing.expectEqual(@as(i128, 1), inner.value.int);
                },
                else => return error.InvalidValue,
            }
        },
        else => return error.InvalidValue,
    }

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();
    var enc = encoder(&out.writer);
    try value.write(&enc);
    try enc.finish();
    try std.testing.expectEqualSlices(u8, input, out.writer.buffered());
}

test "cbor event encoder clones extension values" {
    const input = &.{ 0xc1, 0x63, 'a', 'b', 'c' };
    var reader: std.Io.Reader = .fixed(input);
    var dec = decoder(&reader, std.testing.allocator);

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();
    var enc = eventEncoder(&out.writer, std.testing.allocator);
    defer enc.deinit();

    try events.consume(std.testing.allocator, &dec, &enc);
    try dec.finish();
    try enc.finish();

    try std.testing.expectEqualSlices(u8, input, out.writer.buffered());
}

test "cbor event encoder buffers unknown dynamic lengths" {
    var reader: std.Io.Reader = .fixed("{\"id\":42,\"tags\":[\"a\",\"b\"]}");
    var dec = @import("json.zig").decoder(&reader, std.testing.allocator);

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();
    var enc = eventEncoder(&out.writer, std.testing.allocator);
    defer enc.deinit();

    try events.consume(std.testing.allocator, &dec, &enc);
    try dec.finish();
    try enc.finish();

    const Parsed = struct { id: u8, tags: []const []const u8 };
    const parsed = try readSlice(Parsed, std.testing.allocator, out.writer.buffered());
    defer deinitValue(Parsed, std.testing.allocator, parsed);
    try std.testing.expectEqual(@as(u8, 42), parsed.id);
    try std.testing.expectEqual(@as(usize, 2), parsed.tags.len);
    try std.testing.expectEqualStrings("a", parsed.tags[0]);
    try std.testing.expectEqualStrings("b", parsed.tags[1]);
}

test "cbor events pipe to json msgpack zon and toml targets" {
    const json = @import("json.zig");
    const msgpack = @import("msgpack.zig");
    const zon = @import("zon.zig");
    const toml = @import("toml.zig");

    const binary_input = &.{
        0xa3,
        0x64,
        'n',
        'a',
        'm',
        'e',
        0x63,
        'A',
        'd',
        'a',
        0x64,
        'd',
        'a',
        't',
        'a',
        0x42,
        0x00,
        0x01,
        0x66,
        'a',
        'c',
        't',
        'i',
        'v',
        'e',
        0xf5,
    };

    var json_reader: std.Io.Reader = .fixed(binary_input);
    var json_dec = decoder(&json_reader, std.testing.allocator);
    var json_out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer json_out.deinit();
    var json_enc = json.encoder(&json_out.writer);
    try events.pipe(std.testing.allocator, &json_dec, &json_enc);
    try json_dec.finish();
    try json_enc.finish();
    try std.testing.expectEqualStrings("{\"name\":\"Ada\",\"data\":\"AAE=\",\"active\":true}", json_out.writer.buffered());

    var msgpack_reader: std.Io.Reader = .fixed(binary_input);
    var msgpack_dec = decoder(&msgpack_reader, std.testing.allocator);
    var msgpack_out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer msgpack_out.deinit();
    var msgpack_enc = msgpack.encoder(&msgpack_out.writer);
    try events.pipe(std.testing.allocator, &msgpack_dec, &msgpack_enc);
    try msgpack_dec.finish();
    try msgpack_enc.finish();

    var msgpack_value_reader: std.Io.Reader = .fixed(msgpack_out.writer.buffered());
    var msgpack_value_dec = msgpack.decoder(&msgpack_value_reader, std.testing.allocator);
    var msgpack_value = try events.readAlloc(std.testing.allocator, &msgpack_value_dec);
    defer msgpack_value.deinit(std.testing.allocator);
    try msgpack_value_dec.finish();
    try std.testing.expectEqualStrings("name", msgpack_value.struct_[0].name);
    try std.testing.expectEqualStrings("Ada", msgpack_value.struct_[0].value.string);
    try std.testing.expectEqualStrings("data", msgpack_value.struct_[1].name);
    try std.testing.expectEqualSlices(u8, &.{ 0x00, 0x01 }, msgpack_value.struct_[1].value.bytes);

    var zon_reader: std.Io.Reader = .fixed(binary_input);
    var zon_dec = decoder(&zon_reader, std.testing.allocator);
    var zon_out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer zon_out.deinit();
    var zon_enc = zon.encoder(&zon_out.writer);
    try events.pipe(std.testing.allocator, &zon_dec, &zon_enc);
    try zon_dec.finish();
    try zon_enc.finish();
    try std.testing.expectEqualStrings(".{ .name = \"Ada\", .data = \"AAE=\", .active = true }", zon_out.writer.buffered());

    const toml_input = &.{
        0xa2,
        0x64,
        'n',
        'a',
        'm',
        'e',
        0x63,
        'A',
        'd',
        'a',
        0x64,
        't',
        'a',
        'g',
        's',
        0x82,
        0x65,
        'a',
        'd',
        'm',
        'i',
        'n',
        0x63,
        'o',
        'p',
        's',
    };
    var toml_reader: std.Io.Reader = .fixed(toml_input);
    var toml_dec = decoder(&toml_reader, std.testing.allocator);
    var toml_out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer toml_out.deinit();
    var toml_enc = toml.encoder(&toml_out.writer);
    try events.pipe(std.testing.allocator, &toml_dec, &toml_enc);
    try toml_dec.finish();
    try toml_enc.finish();
    try std.testing.expectEqualStrings("name = \"Ada\"\ntags = [\"admin\", \"ops\"]", toml_out.writer.buffered());
}

test "cbor events pipe row streams to csv" {
    const input = &.{
        0x82,
        0xa2,
        0x62,
        'i',
        'd',
        0x01,
        0x64,
        'n',
        'a',
        'm',
        'e',
        0x63,
        'A',
        'd',
        'a',
        0xa2,
        0x62,
        'i',
        'd',
        0x02,
        0x64,
        'n',
        'a',
        'm',
        'e',
        0x63,
        'B',
        'o',
        'b',
    };
    var reader: std.Io.Reader = .fixed(input);
    var dec = decoder(&reader, std.testing.allocator);

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();
    var enc = @import("csv.zig").encoder(&out.writer);

    try events.pipe(std.testing.allocator, &dec, &enc);
    try dec.finish();
    try enc.finish();

    try std.testing.expectEqualStrings("id,name\r\n1,Ada\r\n2,Bob", out.writer.buffered());
}

test "json and toml event streams encode to cbor" {
    const Document = struct {
        name: []const u8,
        tags: []const []const u8,
    };

    var json_reader: std.Io.Reader = .fixed("{\"name\":\"Ada\",\"tags\":[\"admin\",\"ops\"]}");
    var json_dec = @import("json.zig").decoder(&json_reader, std.testing.allocator);
    var json_out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer json_out.deinit();
    var json_enc = eventEncoder(&json_out.writer, std.testing.allocator);
    defer json_enc.deinit();
    try events.consume(std.testing.allocator, &json_dec, &json_enc);
    try json_dec.finish();
    try json_enc.finish();

    const from_json = try readSlice(Document, std.testing.allocator, json_out.writer.buffered());
    defer deinitValue(Document, std.testing.allocator, from_json);
    try std.testing.expectEqualStrings("Ada", from_json.name);
    try std.testing.expectEqual(@as(usize, 2), from_json.tags.len);
    try std.testing.expectEqualStrings("admin", from_json.tags[0]);
    try std.testing.expectEqualStrings("ops", from_json.tags[1]);

    var toml_reader: std.Io.Reader = .fixed("name = \"Grace\"\ntags = [\"compiler\", \"navy\"]");
    var toml_dec = try @import("toml.zig").decoder(&toml_reader, std.testing.allocator);
    defer toml_dec.deinit();
    var toml_out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer toml_out.deinit();
    var toml_enc = eventEncoder(&toml_out.writer, std.testing.allocator);
    defer toml_enc.deinit();
    try events.consume(std.testing.allocator, &toml_dec, &toml_enc);
    try toml_dec.finish();
    try toml_enc.finish();

    const from_toml = try readSlice(Document, std.testing.allocator, toml_out.writer.buffered());
    defer deinitValue(Document, std.testing.allocator, from_toml);
    try std.testing.expectEqualStrings("Grace", from_toml.name);
    try std.testing.expectEqual(@as(usize, 2), from_toml.tags.len);
    try std.testing.expectEqualStrings("compiler", from_toml.tags[0]);
    try std.testing.expectEqualStrings("navy", from_toml.tags[1]);
}

test "msgpack event bytes encode to cbor byte strings" {
    const msgpack = @import("msgpack.zig");

    var msgpack_out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer msgpack_out.deinit();
    var msgpack_enc = msgpack.encoder(&msgpack_out.writer);
    try msgpack_enc.beginStruct(void, 2);
    try msgpack_enc.emitFieldName("name");
    try msgpack_enc.emitString("Ada");
    try msgpack_enc.emitFieldName("data");
    try msgpack_enc.emitBytes(&.{ 0xde, 0xad, 0xbe, 0xef });
    try msgpack_enc.endStruct();
    try msgpack_enc.finish();

    var msgpack_reader: std.Io.Reader = .fixed(msgpack_out.writer.buffered());
    var msgpack_dec = msgpack.decoder(&msgpack_reader, std.testing.allocator);
    var cbor_out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer cbor_out.deinit();
    var cbor_enc = eventEncoder(&cbor_out.writer, std.testing.allocator);
    defer cbor_enc.deinit();

    try events.consume(std.testing.allocator, &msgpack_dec, &cbor_enc);
    try msgpack_dec.finish();
    try cbor_enc.finish();

    var cbor_reader: std.Io.Reader = .fixed(cbor_out.writer.buffered());
    var cbor_dec = decoder(&cbor_reader, std.testing.allocator);
    var value = try events.readAlloc(std.testing.allocator, &cbor_dec);
    defer value.deinit(std.testing.allocator);
    try cbor_dec.finish();

    try std.testing.expectEqualStrings("name", value.struct_[0].name);
    try std.testing.expectEqualStrings("Ada", value.struct_[0].value.string);
    try std.testing.expectEqualStrings("data", value.struct_[1].name);
    try std.testing.expectEqualSlices(u8, &.{ 0xde, 0xad, 0xbe, 0xef }, value.struct_[1].value.bytes);
}
