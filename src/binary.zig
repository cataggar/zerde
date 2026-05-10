//! Compact binary format support.

const std = @import("std");

const base64 = @import("base64.zig");
const deserialize = @import("deserialize.zig").deserialize;
const meta = @import("meta.zig");
const serialize = @import("serialize.zig").serialize;
const deinitValue = @import("deinit.zig").deinit;

/// Binary format configuration.
pub const Options = struct {
    endian: std.builtin.Endian = .little,
};

/// Serializes `value` as compact binary to `writer`.
pub fn write(writer: *std.Io.Writer, value: anytype) !void {
    try writeWithOptions(writer, value, .{});
}

/// Serializes `value` as compact binary to `writer` with explicit options.
pub fn writeWithOptions(writer: *std.Io.Writer, value: anytype, options: Options) !void {
    var enc = encoderWithOptions(writer, options);
    try serialize(value, &enc);
    try enc.finish();
}

/// Deserializes binary data from `reader` into `T`.
pub fn read(comptime T: type, allocator: std.mem.Allocator, reader: *std.Io.Reader) !T {
    return try readWithOptions(T, allocator, reader, .{});
}

/// Deserializes binary data from `reader` into `T` with explicit options.
pub fn readWithOptions(comptime T: type, allocator: std.mem.Allocator, reader: *std.Io.Reader, options: Options) !T {
    var dec = decoder(reader, allocator, options);
    const value = try deserialize(T, allocator, &dec);
    errdefer deinitValue(T, allocator, value);
    try dec.finish();
    return value;
}

/// Serializes `value` as binary and returns allocator-owned bytes.
pub fn writeAlloc(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    return try writeAllocWithOptions(allocator, value, .{});
}

/// Serializes `value` as binary with explicit options and returns allocator-owned bytes.
pub fn writeAllocWithOptions(allocator: std.mem.Allocator, value: anytype, options: Options) ![]u8 {
    var allocating = std.Io.Writer.Allocating.init(allocator);
    errdefer allocating.deinit();

    try writeWithOptions(&allocating.writer, value, options);
    return try allocating.toOwnedSlice();
}

/// Deserializes binary data from `input` into `T`.
pub fn readSlice(comptime T: type, allocator: std.mem.Allocator, input: []const u8) !T {
    return try readSliceWithOptions(T, allocator, input, .{});
}

/// Deserializes binary data from `input` into `T` with explicit options.
pub fn readSliceWithOptions(comptime T: type, allocator: std.mem.Allocator, input: []const u8, options: Options) !T {
    var reader: std.Io.Reader = .fixed(input);
    return try readWithOptions(T, allocator, &reader, options);
}

/// Returns a low-level binary encoder for use with `zerde.serialize`.
pub fn encoder(writer: *std.Io.Writer) Encoder {
    return encoderWithOptions(writer, .{});
}

/// Returns a low-level binary encoder with explicit options.
pub fn encoderWithOptions(writer: *std.Io.Writer, options: Options) Encoder {
    return .{ .writer = writer, .options = options };
}

/// Returns a low-level binary decoder for use with `zerde.deserialize`.
pub fn decoder(reader: *std.Io.Reader, allocator: std.mem.Allocator, options: Options) Decoder {
    return .{ .reader = reader, .allocator = allocator, .options = options };
}

const TagEntry = struct {
    name: []const u8,
    value: u64,
    is_void: bool,
    payload_field_names: []const []const u8,
};

/// Low-level binary encoder used by the generic serializer.
pub const Encoder = struct {
    const Self = @This();
    const max_depth = 64;

    const Container = enum {
        seq,
        struct_,
        union_external,
        union_adjacent,
        union_internal,
    };

    const Frame = struct {
        container: Container,
        len: usize = 0,
        index: usize = 0,
        tags: []const TagEntry = &.{},
        tag_bytes: usize = 0,
        pending_tag_string: bool = false,
        suppress_next_null: bool = false,
    };

    writer: *std.Io.Writer,
    options: Options,
    stack: [max_depth]Frame = undefined,
    stack_len: usize = 0,

    /// Emits a null marker when required by the current binary context.
    pub fn emitNull(self: *Self) !void {
        if (self.stack_len != 0) {
            const frame = &self.stack[self.stack_len - 1];
            if (frame.suppress_next_null) {
                frame.suppress_next_null = false;
                return;
            }
        }
    }

    /// Emits a boolean as one byte.
    pub fn emitBool(self: *Self, value: bool) !void {
        try self.writer.writeByte(if (value) 1 else 0);
    }

    /// Emits an integer using the configured byte order.
    pub fn emitInt(self: *Self, value: anytype) !void {
        try self.writeInt(@TypeOf(value), value);
    }

    /// Emits a floating-point value as its raw IEEE bits.
    pub fn emitFloat(self: *Self, value: anytype) !void {
        const T = @TypeOf(value);
        const Float = if (@typeInfo(T) == .comptime_float) f64 else T;
        const float_value: Float = value;
        const bits = @bitSizeOf(Float);
        const Int = std.meta.Int(.unsigned, bits);
        const raw: Int = @bitCast(float_value);
        try self.writeInt(Int, raw);
    }

    /// Emits a length-prefixed UTF-8 string.
    pub fn emitString(self: *Self, value: []const u8) !void {
        if (self.stack_len != 0) {
            const frame = &self.stack[self.stack_len - 1];
            if (frame.pending_tag_string) {
                const entry = self.tagEntryByName(frame, value) orelse return error.InvalidEnumTag;
                try self.writeTagValue(frame.tag_bytes, entry.value);
                frame.pending_tag_string = false;
                frame.suppress_next_null = entry.is_void;
                return;
            }
        }

        try self.writeBytes(value);
    }

    /// Emits length-prefixed raw bytes.
    pub fn emitBytes(self: *Self, value: []const u8) !void {
        try self.writeBytes(value);
    }

    /// Emits an enum value using the enum tag's integer storage size.
    pub fn emitEnum(self: *Self, comptime T: type, value: T) !void {
        try self.writeEnumTag(T, @intFromEnum(value));
    }

    /// Emits an enum tag by name.
    pub fn emitEnumTag(self: *Self, tag: []const u8) !void {
        try self.emitString(tag);
    }

    /// Emits the presence marker for an optional value.
    pub fn beginOptional(self: *Self, present: bool) !void {
        try self.writer.writeByte(if (present) 1 else 0);
    }

    /// Begins a fixed-length array.
    pub fn beginArray(self: *Self, comptime T: type, len: usize) !void {
        _ = T;
        try self.push(.{ .container = .seq, .len = len });
    }

    /// Begins a length-prefixed slice.
    pub fn beginSlice(self: *Self, comptime Child: type, len: usize) !void {
        _ = Child;
        try self.writeLength(len);
        try self.push(.{ .container = .seq, .len = len });
    }

    /// Begins a length-prefixed sequence.
    pub fn beginSeq(self: *Self, len: ?usize) !void {
        const actual_len = len orelse return error.MissingBinaryLength;
        try self.writeLength(actual_len);
        try self.push(.{ .container = .seq, .len = actual_len });
    }

    /// Ends the current sequence.
    pub fn endSeq(self: *Self) !void {
        _ = self.current(.seq);
        self.pop(.seq);
    }

    /// Begins a struct or tagged union value.
    pub fn beginStruct(self: *Self, comptime T: type, field_count: usize) !void {
        _ = field_count;

        switch (@typeInfo(T)) {
            .@"union" => |union_info| {
                if (union_info.tag_type == null) return error.InvalidBinaryType;

                const options = comptime meta.optionsFor(T);
                const tags = comptime unionTagEntries(T);
                const tag_bytes = comptime tagByteCount(union_info.tag_type.?);
                const container: Container = switch (options.union_repr) {
                    .external => .union_external,
                    .adjacent => .union_adjacent,
                    .internal => .union_internal,
                };
                try self.push(.{ .container = container, .tags = tags, .tag_bytes = tag_bytes });
            },
            else => try self.push(.{ .container = .struct_ }),
        }
    }

    /// Emits or handles the next struct field name.
    pub fn emitFieldName(self: *Self, name: []const u8) !void {
        const frame = &self.stack[self.stack_len - 1];
        switch (frame.container) {
            .seq => return error.InvalidBinaryEncoderState,
            .struct_ => {},
            .union_external => {
                const entry = self.tagEntryByName(frame, name) orelse return error.InvalidEnumTag;
                try self.writeTagValue(frame.tag_bytes, entry.value);
                frame.suppress_next_null = entry.is_void;
            },
            .union_adjacent, .union_internal => {
                if (std.mem.eql(u8, name, meta.union_tag_field_name)) frame.pending_tag_string = true;
            },
        }
    }

    /// Ends the current struct or tagged union value.
    pub fn endStruct(self: *Self) !void {
        const frame = &self.stack[self.stack_len - 1];
        switch (frame.container) {
            .struct_, .union_external, .union_adjacent, .union_internal => self.stack_len -= 1,
            .seq => return error.InvalidBinaryEncoderState,
        }
    }

    /// Verifies that the binary document was completely written.
    pub fn finish(self: *Self) !void {
        if (self.stack_len != 0) return error.InvalidBinaryEncoderState;
    }

    fn writeBytes(self: *Self, value: []const u8) !void {
        try self.writeLength(value.len);
        try self.writer.writeAll(value);
    }

    fn writeLength(self: *Self, len: usize) !void {
        try self.writeInt(u64, @as(u64, @intCast(len)));
    }

    fn writeInt(self: *Self, comptime T: type, value: T) !void {
        const byte_count = comptime intByteCount(T);
        if (comptime byte_count == 0) return;

        const Unsigned = std.meta.Int(.unsigned, @bitSizeOf(T));
        const Storage = std.meta.Int(.unsigned, byte_count * 8);
        const raw: Unsigned = @bitCast(value);
        const storage: Storage = @intCast(raw);
        var bytes: [byte_count]u8 = undefined;
        std.mem.writeInt(Storage, &bytes, storage, self.options.endian);
        try self.writer.writeAll(&bytes);
    }

    fn writeEnumTag(self: *Self, comptime T: type, value: anytype) !void {
        try self.writeTagValue(comptime tagByteCount(T), tagRawValue(T, value));
    }

    fn writeTagValue(self: *Self, bytes: usize, value: u64) !void {
        var buf: [8]u8 = undefined;
        std.mem.writeInt(u64, &buf, value, self.options.endian);
        if (self.options.endian == .little) {
            try self.writer.writeAll(buf[0..bytes]);
        } else {
            try self.writer.writeAll(buf[8 - bytes .. 8]);
        }
    }

    fn tagEntryByName(self: *Self, frame: *const Frame, name: []const u8) ?TagEntry {
        _ = self;
        for (frame.tags) |entry| {
            if (std.mem.eql(u8, entry.name, name)) return entry;
        }
        return null;
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

/// Binary value kinds reported by `Decoder.peek`.
pub const Kind = enum {
    null,
    bool,
    int,
    float,
    string,
    seq,
    struct_,
};

/// Low-level binary decoder used by the generic deserializer.
pub const Decoder = struct {
    const Self = @This();
    const max_depth = 64;

    const Container = enum {
        seq,
        struct_,
        union_external,
        union_adjacent,
        union_internal,
    };

    const Frame = struct {
        container: Container,
        len: usize = 0,
        index: usize = 0,
        field_names: []const []const u8 = &.{},
        active_tag: []const u8 = "",
        payload_field_names: []const []const u8 = &.{},
    };

    reader: *std.Io.Reader,
    allocator: std.mem.Allocator,
    options: Options,
    stack: [max_depth]Frame = undefined,
    stack_len: usize = 0,
    pending_string: ?[]const u8 = null,

    /// Returns the next value kind when supported by the binary format.
    pub fn peek(self: *Self) !Kind {
        _ = self;
        return error.UnsupportedBinaryPeek;
    }

    /// Reads a null value.
    pub fn readNull(self: *Self) !void {
        _ = self;
    }

    /// Reads a boolean value.
    pub fn readBool(self: *Self) !bool {
        return switch (try self.reader.takeByte()) {
            0 => false,
            1 => true,
            else => error.InvalidValue,
        };
    }

    /// Reads an integer using the configured byte order.
    pub fn readInt(self: *Self, comptime T: type) !T {
        const byte_count = comptime intByteCount(T);
        if (comptime byte_count == 0) return @intCast(0);

        const Storage = std.meta.Int(.unsigned, byte_count * 8);
        const Unsigned = std.meta.Int(.unsigned, @bitSizeOf(T));
        var bytes: [byte_count]u8 = undefined;
        try self.readExact(&bytes);
        const storage = std.mem.readInt(Storage, &bytes, self.options.endian);
        const raw: Unsigned = @truncate(storage);
        return @bitCast(raw);
    }

    /// Reads a floating-point value from its raw IEEE bits.
    pub fn readFloat(self: *Self, comptime T: type) !T {
        const Int = std.meta.Int(.unsigned, @bitSizeOf(T));
        const raw = try self.readInt(Int);
        return @bitCast(raw);
    }

    /// Reads a UTF-8 string as allocator-owned bytes.
    pub fn readString(self: *Self, allocator: std.mem.Allocator) ![]u8 {
        if (self.pending_string) |value| {
            self.pending_string = null;
            return try allocator.dupe(u8, value);
        }

        return try self.readBytes(allocator);
    }

    /// Reads raw bytes into an allocator-owned slice.
    pub fn readBytes(self: *Self, allocator: std.mem.Allocator) ![]u8 {
        const len = try self.readLength();
        const out = try allocator.alloc(u8, len);
        errdefer allocator.free(out);
        try self.readExact(out);
        return out;
    }

    /// Reads an enum value using the enum tag's integer storage size.
    pub fn readEnum(self: *Self, comptime T: type) !T {
        const value = try self.readTagValue(comptime tagByteCount(T));
        const enum_info = @typeInfo(T).@"enum";
        inline for (enum_info.fields) |field| {
            if ((comptime tagRawValue(T, field.value)) == value) return @enumFromInt(field.value);
        }
        return error.InvalidEnumTag;
    }

    /// Reads and returns the optional presence marker.
    pub fn readOptionalPresent(self: *Self) !bool {
        return switch (try self.reader.takeByte()) {
            0 => false,
            1 => true,
            else => error.InvalidValue,
        };
    }

    /// Begins reading a fixed-length array.
    pub fn beginArray(self: *Self, comptime T: type) !?usize {
        const array_info = @typeInfo(T).array;
        try self.push(.{ .container = .seq, .len = array_info.len });
        return array_info.len;
    }

    /// Begins reading a length-prefixed sequence.
    pub fn beginSeq(self: *Self) !?usize {
        const len = try self.readLength();
        try self.push(.{ .container = .seq, .len = len });
        return len;
    }

    /// Returns whether the current sequence has another element.
    pub fn hasNextSeqElem(self: *Self) !bool {
        const frame = self.current(.seq);
        if (frame.index == frame.len) return false;
        frame.index += 1;
        return true;
    }

    /// Ends the current sequence.
    pub fn endSeq(self: *Self) !void {
        const frame = self.current(.seq);
        if (frame.index != frame.len) return error.InvalidArrayLength;
        self.pop(.seq);
    }

    /// Begins reading a struct or tagged union value.
    pub fn beginStruct(self: *Self, comptime T: type) !void {
        switch (@typeInfo(T)) {
            .@"union" => |union_info| {
                if (union_info.tag_type == null) return error.InvalidBinaryType;

                const options = comptime meta.optionsFor(T);
                const tags = comptime unionTagEntries(T);
                const tag_bytes = comptime tagByteCount(union_info.tag_type.?);
                const tag_value = try self.readTagValue(tag_bytes);
                const entry = tagEntryByValue(tags, tag_value) orelse return error.UnknownUnionTag;
                const container: Container = switch (options.union_repr) {
                    .external => .union_external,
                    .adjacent => .union_adjacent,
                    .internal => .union_internal,
                };
                try self.push(.{
                    .container = container,
                    .active_tag = entry.name,
                    .payload_field_names = entry.payload_field_names,
                });
            },
            .@"struct" => try self.push(.{ .container = .struct_, .field_names = comptime structFieldNames(T) }),
            else => return error.InvalidBinaryType,
        }
    }

    /// Returns the next field name as allocator-owned bytes, or null when done.
    pub fn nextField(self: *Self) !?[]u8 {
        const frame = &self.stack[self.stack_len - 1];
        const name = switch (frame.container) {
            .seq => return error.InvalidBinaryDecoderState,
            .struct_ => blk: {
                if (frame.index == frame.field_names.len) return null;
                const field_name = frame.field_names[frame.index];
                frame.index += 1;
                break :blk field_name;
            },
            .union_external => blk: {
                if (frame.index != 0) return null;
                frame.index = 1;
                break :blk frame.active_tag;
            },
            .union_adjacent => blk: {
                if (frame.index == 0) {
                    frame.index = 1;
                    self.pending_string = frame.active_tag;
                    break :blk meta.union_tag_field_name;
                }
                if (frame.index == 1) {
                    frame.index = 2;
                    break :blk meta.union_content_field_name;
                }
                return null;
            },
            .union_internal => blk: {
                if (frame.index == 0) {
                    frame.index = 1;
                    self.pending_string = frame.active_tag;
                    break :blk meta.union_tag_field_name;
                }
                const payload_index = frame.index - 1;
                if (payload_index == frame.payload_field_names.len) return null;
                frame.index += 1;
                break :blk frame.payload_field_names[payload_index];
            },
        };

        return try self.allocator.dupe(u8, name);
    }

    /// Ends the current struct or tagged union value.
    pub fn endStruct(self: *Self) !void {
        const frame = &self.stack[self.stack_len - 1];
        switch (frame.container) {
            .struct_, .union_external, .union_adjacent, .union_internal => self.stack_len -= 1,
            .seq => return error.InvalidBinaryDecoderState,
        }
    }

    /// Skips the next value when supported by the binary format.
    pub fn skipValue(self: *Self) !void {
        _ = self;
        return error.UnsupportedBinarySkip;
    }

    /// Verifies that the binary document was completely read.
    pub fn finish(self: *Self) !void {
        if (self.stack_len != 0) return error.InvalidBinaryDecoderState;
        _ = self.reader.peekByte() catch |err| switch (err) {
            error.EndOfStream => return,
            else => |e| return e,
        };
        return error.InvalidBinaryTrailingData;
    }

    fn readLength(self: *Self) !usize {
        const len = try self.readInt(u64);
        return std.math.cast(usize, len) orelse error.IntegerOverflow;
    }

    fn readTagValue(self: *Self, bytes: usize) !u64 {
        var buf = [_]u8{0} ** 8;
        if (self.options.endian == .little) {
            try self.readExact(buf[0..bytes]);
        } else {
            try self.readExact(buf[8 - bytes .. 8]);
        }
        return std.mem.readInt(u64, &buf, self.options.endian);
    }

    fn readExact(self: *Self, out: []u8) !void {
        for (out) |*byte| byte.* = try self.reader.takeByte();
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

fn structFieldNames(comptime T: type) []const []const u8 {
    const struct_info = @typeInfo(T).@"struct";
    const options = comptime meta.optionsFor(T);
    const count = comptime serializableStructFieldCount(T);

    comptime var names: [count][]const u8 = undefined;
    comptime var index: usize = 0;
    inline for (struct_info.fields) |field| {
        if (!field.is_comptime) {
            const field_options = comptime meta.fieldOptionsFor(T, field.name);
            if (comptime meta.shouldSerialize(field_options)) {
                names[index] = comptime meta.fieldWireName(field.name, field_options, options);
                index += 1;
            }
        }
    }

    const final = names;
    return &final;
}

fn serializableStructFieldCount(comptime T: type) usize {
    const struct_info = @typeInfo(T).@"struct";

    comptime var field_count: usize = 0;
    inline for (struct_info.fields) |field| {
        if (!field.is_comptime) {
            const field_options = comptime meta.fieldOptionsFor(T, field.name);
            if (comptime meta.shouldSerialize(field_options)) field_count += 1;
        }
    }
    return field_count;
}

fn unionTagEntries(comptime T: type) []const TagEntry {
    const union_info = @typeInfo(T).@"union";
    const Tag = union_info.tag_type.?;
    const enum_info = @typeInfo(Tag).@"enum";

    comptime var entries: [union_info.fields.len]TagEntry = undefined;
    inline for (union_info.fields, 0..) |field, i| {
        var value: u64 = 0;
        inline for (enum_info.fields) |enum_field| {
            if (std.mem.eql(u8, enum_field.name, field.name)) value = comptime tagRawValue(Tag, enum_field.value);
        }
        entries[i] = .{
            .name = field.name,
            .value = value,
            .is_void = field.type == void,
            .payload_field_names = switch (@typeInfo(field.type)) {
                .@"struct" => comptime structFieldNames(field.type),
                else => &.{},
            },
        };
    }

    const final = entries;
    return &final;
}

fn tagEntryByValue(entries: []const TagEntry, value: u64) ?TagEntry {
    for (entries) |entry| {
        if (entry.value == value) return entry;
    }
    return null;
}

fn tagByteCount(comptime T: type) usize {
    const bits = switch (@typeInfo(T)) {
        .@"enum" => |enum_info| @bitSizeOf(enum_info.tag_type),
        .int => @bitSizeOf(T),
        else => @compileError("binary tags require enum or integer types"),
    };
    return @max(1, (bits + 7) / 8);
}

fn intByteCount(comptime T: type) usize {
    return (@bitSizeOf(T) + 7) / 8;
}

fn tagRawValue(comptime T: type, value: anytype) u64 {
    const Int = switch (@typeInfo(T)) {
        .@"enum" => |enum_info| enum_info.tag_type,
        .int => T,
        else => @compileError("binary tags require enum or integer types"),
    };
    const Unsigned = std.meta.Int(.unsigned, @bitSizeOf(Int));
    const typed: Int = @intCast(value);
    const raw: Unsigned = @bitCast(typed);
    return @intCast(raw);
}

test "binary writes known primitive bytes" {
    const bytes = try writeAlloc(std.testing.allocator, @as(u16, 0x1234));
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualSlices(u8, &.{ 0x34, 0x12 }, bytes);

    const float_bytes = try writeAlloc(std.testing.allocator, @as(f32, 1.5));
    defer std.testing.allocator.free(float_bytes);
    try std.testing.expectEqualSlices(u8, &.{ 0x00, 0x00, 0xc0, 0x3f }, float_bytes);

    const bool_bytes = try writeAlloc(std.testing.allocator, true);
    defer std.testing.allocator.free(bool_bytes);
    try std.testing.expectEqualSlices(u8, &.{1}, bool_bytes);
}

test "binary rounds integer fields up to whole bytes" {
    const unsigned_bytes = try writeAlloc(std.testing.allocator, @as(u12, 0xabc));
    defer std.testing.allocator.free(unsigned_bytes);
    try std.testing.expectEqualSlices(u8, &.{ 0xbc, 0x0a }, unsigned_bytes);
    try std.testing.expectEqual(@as(u12, 0xabc), try readSlice(u12, std.testing.allocator, unsigned_bytes));

    const signed_bytes = try writeAlloc(std.testing.allocator, @as(i12, -2));
    defer std.testing.allocator.free(signed_bytes);
    try std.testing.expectEqualSlices(u8, &.{ 0xfe, 0x0f }, signed_bytes);
    try std.testing.expectEqual(@as(i12, -2), try readSlice(i12, std.testing.allocator, signed_bytes));
}

test "binary roundtrips mixed non-byte-aligned integer fields" {
    const Packed = struct {
        a: u1,
        b: u3,
        c: i5,
        d: u9,
        e: i12,
        f: u17,
        g: i20,
    };

    const original = Packed{
        .a = 1,
        .b = 0b101,
        .c = -7,
        .d = 0x101,
        .e = -33,
        .f = 0x1ffff,
        .g = -0x1234,
    };
    const bytes = try writeAlloc(std.testing.allocator, original);
    defer std.testing.allocator.free(bytes);

    try std.testing.expectEqualSlices(u8, &.{
        0x01,
        0x05,
        0x19,
        0x01,
        0x01,
        0xdf,
        0x0f,
        0xff,
        0xff,
        0x01,
        0xcc,
        0xed,
        0x0f,
    }, bytes);

    const parsed = try readSlice(Packed, std.testing.allocator, bytes);
    try std.testing.expectEqual(original.a, parsed.a);
    try std.testing.expectEqual(original.b, parsed.b);
    try std.testing.expectEqual(original.c, parsed.c);
    try std.testing.expectEqual(original.d, parsed.d);
    try std.testing.expectEqual(original.e, parsed.e);
    try std.testing.expectEqual(original.f, parsed.f);
    try std.testing.expectEqual(original.g, parsed.g);

    const big_bytes = try writeAllocWithOptions(std.testing.allocator, original, .{ .endian = .big });
    defer std.testing.allocator.free(big_bytes);

    try std.testing.expectEqualSlices(u8, &.{
        0x01,
        0x05,
        0x19,
        0x01,
        0x01,
        0x0f,
        0xdf,
        0x01,
        0xff,
        0xff,
        0x0f,
        0xed,
        0xcc,
    }, big_bytes);

    const parsed_big = try readSliceWithOptions(Packed, std.testing.allocator, big_bytes, .{ .endian = .big });
    try std.testing.expectEqual(original.a, parsed_big.a);
    try std.testing.expectEqual(original.b, parsed_big.b);
    try std.testing.expectEqual(original.c, parsed_big.c);
    try std.testing.expectEqual(original.d, parsed_big.d);
    try std.testing.expectEqual(original.e, parsed_big.e);
    try std.testing.expectEqual(original.f, parsed_big.f);
    try std.testing.expectEqual(original.g, parsed_big.g);
}

test "binary writes arrays without length prefix" {
    const bytes = try writeAlloc(std.testing.allocator, [2]u16{ 0x1234, 0x5678 });
    defer std.testing.allocator.free(bytes);

    try std.testing.expectEqualSlices(u8, &.{ 0x34, 0x12, 0x78, 0x56 }, bytes);
}

test "binary honors endian differences" {
    const little = try writeAlloc(std.testing.allocator, @as(u32, 0x12345678));
    defer std.testing.allocator.free(little);
    const big = try writeAllocWithOptions(std.testing.allocator, @as(u32, 0x12345678), .{ .endian = .big });
    defer std.testing.allocator.free(big);

    var buffer: [4]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    var enc = encoderWithOptions(&writer, .{ .endian = .big });
    try serialize(@as(u32, 0x12345678), &enc);
    try enc.finish();

    try std.testing.expectEqualSlices(u8, &.{ 0x78, 0x56, 0x34, 0x12 }, little);
    try std.testing.expectEqualSlices(u8, &.{ 0x12, 0x34, 0x56, 0x78 }, big);
    try std.testing.expectEqualSlices(u8, &.{ 0x12, 0x34, 0x56, 0x78 }, writer.buffered());
}

test "binary writes struct output in declaration order" {
    const User = struct {
        id: u16,
        active: bool,
    };

    const bytes = try writeAlloc(std.testing.allocator, User{ .id = 0x1234, .active = true });
    defer std.testing.allocator.free(bytes);

    try std.testing.expectEqualSlices(u8, &.{ 0x34, 0x12, 0x01 }, bytes);
}

test "binary roundtrips structs with owned slices" {
    const User = struct {
        id: u32,
        name: []const u8,
        scores: []const u16,
        nickname: ?[]const u8,
    };

    const scores = [_]u16{ 10, 20, 30 };
    const original = User{ .id = 7, .name = "Ada", .scores = scores[0..], .nickname = "a" };
    const bytes = try writeAlloc(std.testing.allocator, original);
    defer std.testing.allocator.free(bytes);

    const parsed = try readSlice(User, std.testing.allocator, bytes);
    defer deinitValue(User, std.testing.allocator, parsed);

    try std.testing.expectEqual(original.id, parsed.id);
    try std.testing.expectEqualStrings(original.name, parsed.name);
    try std.testing.expectEqualSlices(u16, original.scores, parsed.scores);
    try std.testing.expectEqualStrings(original.nickname.?, parsed.nickname.?);
}

test "binary roundtrips std list containers" {
    const Value = struct {
        numbers: std.ArrayList(u16),
        names: std.ArrayList([]const u8),
    };
    const allocator = std.testing.allocator;

    var original = Value{
        .numbers = .empty,
        .names = .empty,
    };
    defer original.numbers.deinit(allocator);
    defer original.names.deinit(allocator);
    try original.numbers.append(allocator, 10);
    try original.numbers.append(allocator, 20);
    try original.names.append(allocator, "Ada");
    try original.names.append(allocator, "Zig");

    const bytes = try writeAlloc(allocator, original);
    defer allocator.free(bytes);

    const parsed = try readSlice(Value, allocator, bytes);
    defer deinitValue(Value, allocator, parsed);

    try std.testing.expectEqualSlices(u16, &.{ 10, 20 }, parsed.numbers.items);
    try std.testing.expectEqualStrings("Ada", parsed.names.items[0]);
    try std.testing.expectEqualStrings("Zig", parsed.names.items[1]);
}

test "binary roundtrips std map containers" {
    const Map = std.array_hash_map.Auto(u8, []const u8);
    const allocator = std.testing.allocator;

    var original: Map = .empty;
    defer original.deinit(allocator);
    try original.put(allocator, 1, "one");
    try original.put(allocator, 2, "two");

    const bytes = try writeAlloc(allocator, original);
    defer allocator.free(bytes);

    const parsed = try readSlice(Map, allocator, bytes);
    defer deinitValue(Map, allocator, parsed);

    try std.testing.expectEqualSlices(u8, &.{ 1, 2 }, parsed.keys());
    try std.testing.expectEqualStrings("one", parsed.values()[0]);
    try std.testing.expectEqualStrings("two", parsed.values()[1]);
}

test "binary encodes slice length prefix and optional presence" {
    const Value = struct {
        items: []const u8,
        maybe: ?u16,
        absent: ?u16,
    };

    const value = Value{ .items = "abc", .maybe = 0x1234, .absent = null };
    const bytes = try writeAlloc(std.testing.allocator, value);
    defer std.testing.allocator.free(bytes);

    try std.testing.expectEqualSlices(u8, &.{
        0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        'a',  'b',  'c',  0x01, 0x34, 0x12, 0x00,
    }, bytes);
}

test "binary roundtrips raw bytes" {
    const Blob = struct {
        data: base64.Bytes,
    };
    const raw = [_]u8{ 0, 1, 2, 3 };

    const bytes = try writeAlloc(std.testing.allocator, Blob{ .data = .{ .value = raw[0..] } });
    defer std.testing.allocator.free(bytes);

    const parsed = try readSlice(Blob, std.testing.allocator, bytes);
    defer deinitValue(Blob, std.testing.allocator, parsed);

    try std.testing.expectEqualSlices(u8, &raw, parsed.data.value);
}

test "binary rejects malformed primitive input" {
    try std.testing.expectError(error.InvalidValue, readSlice(bool, std.testing.allocator, &.{2}));
    try std.testing.expectError(error.InvalidValue, readSlice(?u8, std.testing.allocator, &.{2}));
    try std.testing.expectError(error.EndOfStream, readSlice(u16, std.testing.allocator, &.{0x01}));
    try std.testing.expectError(error.InvalidBinaryTrailingData, readSlice(u8, std.testing.allocator, &.{ 1, 2 }));
}

test "binary rejects truncated string payload" {
    try std.testing.expectError(error.EndOfStream, readSlice([]const u8, std.testing.allocator, &.{
        0x03, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
        'a',  'b',
    }));
}

test "binary frees owned values when trailing data is rejected" {
    const User = struct { name: []const u8 };

    try std.testing.expectError(error.InvalidBinaryTrailingData, readSlice(User, std.testing.allocator, &.{
        0x03, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
        'A',  'd',  'a',  0xff,
    }));
}

test "binary roundtrips enums and tagged unions" {
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

test "binary roundtrips signed negative enum tags" {
    const Signed = enum(i8) { neg = -1, zero = 0, pos = 1 };

    const bytes = try writeAlloc(std.testing.allocator, Signed.neg);
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualSlices(u8, &.{0xff}, bytes);

    const parsed = try readSlice(Signed, std.testing.allocator, bytes);
    try std.testing.expectEqual(Signed.neg, parsed);
}

test "binary roundtrips signed negative tagged union tags" {
    const Tag = enum(i8) { neg = -1, pos = 1 };
    const Value = union(Tag) {
        neg,
        pos: u8,
    };

    const neg_bytes = try writeAlloc(std.testing.allocator, Value{ .neg = {} });
    defer std.testing.allocator.free(neg_bytes);
    try std.testing.expectEqualSlices(u8, &.{0xff}, neg_bytes);

    const parsed_neg = try readSlice(Value, std.testing.allocator, neg_bytes);
    switch (parsed_neg) {
        .neg => {},
        .pos => return error.InvalidValue,
    }

    const pos_bytes = try writeAlloc(std.testing.allocator, Value{ .pos = 7 });
    defer std.testing.allocator.free(pos_bytes);
    try std.testing.expectEqualSlices(u8, &.{ 0x01, 0x07 }, pos_bytes);

    const parsed_pos = try readSlice(Value, std.testing.allocator, pos_bytes);
    switch (parsed_pos) {
        .pos => |pos| try std.testing.expectEqual(@as(u8, 7), pos),
        .neg => return error.InvalidValue,
    }
}

test "binary roundtrips adjacent and internal tagged unions" {
    const Circle = struct { radius: u16 };
    const Adjacent = union(enum) {
        point,
        circle: Circle,

        pub const zerde = .{ .union_repr = .adjacent };
    };
    const Internal = union(enum) {
        point,
        circle: Circle,

        pub const zerde = .{ .union_repr = .internal };
    };

    const adjacent_bytes = try writeAlloc(std.testing.allocator, Adjacent{ .point = {} });
    defer std.testing.allocator.free(adjacent_bytes);
    const adjacent = try readSlice(Adjacent, std.testing.allocator, adjacent_bytes);
    defer deinitValue(Adjacent, std.testing.allocator, adjacent);
    switch (adjacent) {
        .point => {},
        .circle => return error.InvalidValue,
    }

    const internal_bytes = try writeAlloc(std.testing.allocator, Internal{ .circle = .{ .radius = 99 } });
    defer std.testing.allocator.free(internal_bytes);
    const internal = try readSlice(Internal, std.testing.allocator, internal_bytes);
    defer deinitValue(Internal, std.testing.allocator, internal);
    switch (internal) {
        .circle => |circle| try std.testing.expectEqual(@as(u16, 99), circle.radius),
        .point => return error.InvalidValue,
    }
}
