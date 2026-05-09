//! TOML format support.

const std = @import("std");

const serialize = @import("serialize.zig").serialize;
const deserialize = @import("deserialize.zig").deserialize;
const base64 = @import("base64.zig");
const deinitValue = @import("deinit.zig").deinit;
const datetime = @import("datetime.zig");
const number = @import("number.zig");

const TomlNumber = number.Parser(.{
    .decimal_float = true,
    .exponent = true,
    .sign = .positive_and_negative,
    .digit_separator = '_',
    .prefixed_integers = .{ .binary = true, .octal = true, .hex = true },
    .special_floats = true,
    .integer_bounds = .{ .min = std.math.minInt(i64), .max = @intCast(std.math.maxInt(i64)) },
    .integer_to_float = true,
});

/// TOML writer configuration.
pub const WriteLayout = enum {
    /// Streams directly without allocation. Nested structs are inline tables.
    inline_tables,
    /// Builds a temporary tree to emit `[table]` and `[[array]]` sections.
    sections,
};

pub const WriteOptions = struct {
    layout: WriteLayout = .inline_tables,
};

/// Serializes `value` as TOML to `writer` without heap allocation.
///
/// TOML documents are tables, so the root value must be a struct. TOML has no
/// null value; serializing null optionals returns `error.UnsupportedTomlNull`.
pub fn write(writer: *std.Io.Writer, value: anytype) !void {
    var enc = encoder(writer);
    try serialize(value, &enc);
    try enc.finish();
}

/// Serializes `value` as TOML to `writer` with explicit writer options.
///
/// Section layout requires `allocator` for a temporary document tree. Inline
/// `inline_tables` layout ignores `allocator` and streams directly.
pub fn writeWithOptions(allocator: std.mem.Allocator, writer: *std.Io.Writer, value: anytype, options: WriteOptions) !void {
    switch (options.layout) {
        .inline_tables => {
            try write(writer, value);
        },
        .sections => {
            var enc = TreeEncoder.init(allocator);
            defer enc.deinit();

            try serialize(value, &enc);
            const root = try enc.finish();
            if (root.* != .table) return error.TomlRootMustBeStruct;
            try renderDocument(writer, root.table);
        },
    }
}

/// Returns a low-level TOML encoder for use with `zerde.serialize` or custom
/// serialization code.
pub fn encoder(writer: *std.Io.Writer) Encoder {
    return .{ .writer = writer };
}

/// Deserializes TOML from `reader` into `T`.
pub fn read(comptime T: type, allocator: std.mem.Allocator, reader: *std.Io.Reader) !T {
    var dec = try decoder(reader, allocator);
    defer dec.deinit();

    const value = try deserialize(T, allocator, &dec);
    errdefer deinitValue(T, allocator, value);
    try dec.finish();
    return value;
}

/// Serializes `value` as TOML and returns allocator-owned bytes.
pub fn writeAlloc(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    return try writeAllocWithOptions(allocator, value, .{});
}

/// Serializes `value` as TOML with explicit writer options and returns
/// allocator-owned bytes.
pub fn writeAllocWithOptions(allocator: std.mem.Allocator, value: anytype, options: WriteOptions) ![]u8 {
    var allocating = std.Io.Writer.Allocating.init(allocator);
    errdefer allocating.deinit();

    try writeWithOptions(allocator, &allocating.writer, value, options);
    return try allocating.toOwnedSlice();
}

/// Deserializes TOML from `input` into `T`.
pub fn readSlice(comptime T: type, allocator: std.mem.Allocator, input: []const u8) !T {
    var reader: std.Io.Reader = .fixed(input);
    return try read(T, allocator, &reader);
}

/// Returns a low-level TOML decoder for use with `zerde.deserialize` or custom
/// deserialization code. Call `Decoder.deinit` when done.
pub fn decoder(reader: *std.Io.Reader, allocator: std.mem.Allocator) !Decoder {
    var input = std.Io.Writer.Allocating.init(allocator);
    errdefer input.deinit();

    while (true) {
        const byte = reader.takeByte() catch |err| switch (err) {
            error.EndOfStream => break,
            else => |e| return e,
        };
        try input.writer.writeByte(byte);
    }

    const bytes = try input.toOwnedSlice();
    errdefer allocator.free(bytes);

    var parser = Parser{ .allocator = allocator, .input = bytes };
    const root = try parser.parseDocument();
    errdefer {
        var root_copy = root;
        root_copy.deinit(allocator);
    }

    return .{ .allocator = allocator, .input = bytes, .root = root };
}

/// TOML value kinds reported by `Decoder.peek`.
pub const Kind = enum {
    null,
    bool,
    int,
    float,
    datetime,
    string,
    seq,
    struct_,
};

/// TOML local date: `YYYY-MM-DD`.
pub const LocalDate = datetime.LocalDate;
/// TOML local time: `HH:MM:SS[.fraction]`.
pub const LocalTime = datetime.LocalTime;
/// TOML local date-time: `YYYY-MM-DDTHH:MM:SS[.fraction]`.
pub const LocalDateTime = datetime.LocalDateTime;
/// TOML offset date-time: `YYYY-MM-DDTHH:MM:SS[.fraction]Z` or with `+/-HH:MM`.
pub const OffsetDateTime = datetime.OffsetDateTime;

/// Low-level TOML encoder used by the generic serializer.
pub const Encoder = struct {
    const Self = @This();
    const max_depth = 64;

    const Container = enum {
        root_table,
        inline_table,
        seq,
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

    pub fn emitNull(self: *Self) !void {
        _ = self;
        return error.UnsupportedTomlNull;
    }

    pub fn emitBool(self: *Self, value: bool) !void {
        try self.beforeValue();
        try self.writer.writeAll(if (value) "true" else "false");
    }

    pub fn emitInt(self: *Self, value: anytype) !void {
        const toml_value = try tomlInteger(value);
        try self.beforeValue();
        try self.writer.print("{d}", .{toml_value});
    }

    pub fn emitFloat(self: *Self, value: anytype) !void {
        try self.beforeValue();
        try self.writer.print("{d}", .{value});
    }

    pub fn emitString(self: *Self, value: []const u8) !void {
        if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidUtf8;
        try self.beforeValue();
        try self.writeEscapedString(value);
    }

    pub fn emitBytes(self: *Self, value: []const u8) !void {
        try self.beforeValue();
        try self.writer.writeByte('"');
        try base64.writeEncoded(self.writer, value);
        try self.writer.writeByte('"');
    }

    pub fn emitTomlDateTime(self: *Self, value: []const u8) !void {
        try self.beforeValue();
        try self.writer.writeAll(value);
    }

    pub fn beginSeq(self: *Self, len: ?usize) !void {
        _ = len;
        try self.ensureCanPush();
        try self.beforeValue();
        try self.writer.writeAll("[");
        self.push(.seq);
    }

    pub fn endSeq(self: *Self) !void {
        self.pop(.seq);
        try self.writer.writeAll("]");
    }

    pub fn beginStruct(self: *Self, comptime T: type, field_count: usize) !void {
        _ = T;
        _ = field_count;

        try self.ensureCanPush();
        if (self.stack_len == 0) {
            if (self.root_count != 0) return error.InvalidTomlEncoderState;
            self.root_count = 1;
            self.push(.root_table);
            return;
        }

        try self.beforeValue();
        try self.writer.writeAll("{ ");
        self.push(.inline_table);
    }

    pub fn emitFieldName(self: *Self, name: []const u8) !void {
        const frame = self.currentTableFrame();
        if (frame.expecting_field_value) return error.InvalidTomlEncoderState;

        switch (frame.container) {
            .root_table => {
                if (frame.count != 0) try self.writer.writeByte('\n');
            },
            .inline_table => {
                if (frame.count != 0) try self.writer.writeAll(", ");
            },
            .seq => unreachable,
        }

        try self.writeKey(name);
        try self.writer.writeAll(" = ");
        frame.count += 1;
        frame.expecting_field_value = true;
    }

    pub fn endStruct(self: *Self) !void {
        const frame = self.currentTableFrame();
        if (frame.expecting_field_value) return error.InvalidTomlEncoderState;

        const container = frame.container;
        self.pop(container);
        if (container == .inline_table) try self.writer.writeAll(" }");
    }

    pub fn emitEnumTag(self: *Self, tag: []const u8) !void {
        try self.emitString(tag);
    }

    pub fn finish(self: *Self) !void {
        if (self.root_count == 0) return error.IncompleteTomlDocument;
        if (self.stack_len != 0) return error.IncompleteTomlDocument;
    }

    fn beforeValue(self: *Self) !void {
        if (self.stack_len == 0) return error.TomlRootMustBeStruct;

        const frame = &self.stack[self.stack_len - 1];
        switch (frame.container) {
            .seq => {
                if (frame.count != 0) try self.writer.writeAll(", ");
                frame.count += 1;
            },
            .root_table, .inline_table => {
                if (!frame.expecting_field_value) return error.InvalidTomlEncoderState;
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

    fn currentTableFrame(self: *Self) *Frame {
        std.debug.assert(self.stack_len != 0);
        const frame = &self.stack[self.stack_len - 1];
        std.debug.assert(frame.container == .root_table or frame.container == .inline_table);
        return frame;
    }

    fn writeKey(self: *Self, key: []const u8) !void {
        if (isBareKey(key)) {
            try self.writer.writeAll(key);
        } else {
            try self.writeEscapedString(key);
        }
    }

    fn writeEscapedString(self: *Self, value: []const u8) !void {
        try self.writer.writeByte('"');
        var run_start: usize = 0;
        for (value, 0..) |byte, i| {
            switch (byte) {
                0x08 => try self.writeEscapedByte(value, &run_start, i, "\\b"),
                '\t' => try self.writeEscapedByte(value, &run_start, i, "\\t"),
                '\n' => try self.writeEscapedByte(value, &run_start, i, "\\n"),
                0x0c => try self.writeEscapedByte(value, &run_start, i, "\\f"),
                '\r' => try self.writeEscapedByte(value, &run_start, i, "\\r"),
                '"' => try self.writeEscapedByte(value, &run_start, i, "\\\""),
                '\\' => try self.writeEscapedByte(value, &run_start, i, "\\\\"),
                0x00...0x07, 0x0b, 0x0e...0x1f, 0x7f => {
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
        try self.writer.writeByte('"');
    }

    fn writeEscapedByte(self: *Self, value: []const u8, run_start: *usize, index: usize, escaped: []const u8) !void {
        try self.writer.writeAll(value[run_start.*..index]);
        try self.writer.writeAll(escaped);
        run_start.* = index + 1;
    }
};

const TreeEncoder = struct {
    const Self = @This();
    const max_depth = 64;

    const Frame = struct {
        value: *Value,
        pending_field_name: ?[]u8 = null,
    };

    allocator: std.mem.Allocator,
    root: ?Value = null,
    stack: [max_depth]Frame = undefined,
    stack_len: usize = 0,

    fn init(allocator: std.mem.Allocator) Self {
        return .{ .allocator = allocator };
    }

    fn deinit(self: *Self) void {
        if (self.root) |*root| root.deinit(self.allocator);
        for (self.stack[0..self.stack_len]) |*frame| {
            if (frame.pending_field_name) |name| self.allocator.free(name);
        }
        self.* = undefined;
    }

    pub fn emitNull(self: *Self) !void {
        _ = self;
        return error.UnsupportedTomlNull;
    }

    pub fn emitBool(self: *Self, value: bool) !void {
        try self.appendValue(.{ .bool = value });
    }

    pub fn emitInt(self: *Self, value: anytype) !void {
        const bytes = try std.fmt.allocPrint(self.allocator, "{d}", .{try tomlInteger(value)});
        errdefer self.allocator.free(bytes);
        try self.appendValue(.{ .int = .{ .bytes = bytes, .base = 10 } });
    }

    pub fn emitFloat(self: *Self, value: anytype) !void {
        const bytes = try std.fmt.allocPrint(self.allocator, "{d}", .{value});
        errdefer self.allocator.free(bytes);
        try self.appendValue(.{ .float = bytes });
    }

    pub fn emitString(self: *Self, value: []const u8) !void {
        if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidUtf8;
        const bytes = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(bytes);
        try self.appendValue(.{ .string = bytes });
    }

    pub fn emitBytes(self: *Self, value: []const u8) !void {
        const bytes = try base64.encodeAlloc(self.allocator, value);
        errdefer self.allocator.free(bytes);
        try self.appendValue(.{ .string = bytes });
    }

    pub fn emitTomlDateTime(self: *Self, value: []const u8) !void {
        const bytes = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(bytes);
        try self.appendValue(.{ .datetime = bytes });
    }

    pub fn beginSeq(self: *Self, len: ?usize) !void {
        _ = len;
        try self.appendAndPush(.{ .array = .empty });
    }

    pub fn endSeq(self: *Self) !void {
        self.pop(.array);
    }

    pub fn beginStruct(self: *Self, comptime T: type, field_count: usize) !void {
        _ = T;
        _ = field_count;
        try self.appendAndPush(.{ .table = .{} });
    }

    pub fn emitFieldName(self: *Self, name: []const u8) !void {
        const frame = self.currentFrame();
        if (frame.value.* != .table) return error.InvalidTomlEncoderState;
        if (frame.pending_field_name) |old| {
            self.allocator.free(old);
            frame.pending_field_name = null;
            return error.InvalidTomlEncoderState;
        }
        frame.pending_field_name = try self.allocator.dupe(u8, name);
    }

    pub fn endStruct(self: *Self) !void {
        const frame = self.currentFrame();
        if (frame.pending_field_name) |name| {
            self.allocator.free(name);
            frame.pending_field_name = null;
            return error.InvalidTomlEncoderState;
        }
        self.pop(.table);
    }

    pub fn emitEnumTag(self: *Self, tag: []const u8) !void {
        try self.emitString(tag);
    }

    fn finish(self: *Self) !*const Value {
        if (self.root == null) return error.IncompleteTomlDocument;
        if (self.stack_len != 0) return error.IncompleteTomlDocument;
        return &self.root.?;
    }

    fn appendAndPush(self: *Self, value: Value) !void {
        const ptr = try self.appendValuePtr(value);
        if (self.stack_len == self.stack.len) return error.NestingTooDeep;
        self.stack[self.stack_len] = .{ .value = ptr };
        self.stack_len += 1;
    }

    fn appendValue(self: *Self, value: Value) !void {
        _ = try self.appendValuePtr(value);
    }

    fn appendValuePtr(self: *Self, value: Value) !*Value {
        if (self.stack_len == 0) {
            if (self.root != null) return error.InvalidTomlEncoderState;
            self.root = value;
            return &self.root.?;
        }

        const frame = self.currentFrame();
        switch (frame.value.*) {
            .array => |*array| {
                try array.append(self.allocator, value);
                return &array.items[array.items.len - 1];
            },
            .table => |*table| {
                const name = frame.pending_field_name orelse return error.InvalidTomlEncoderState;
                try table.fields.append(self.allocator, .{ .name = name, .value = value });
                frame.pending_field_name = null;
                return &table.fields.items[table.fields.items.len - 1].value;
            },
            else => return error.InvalidTomlEncoderState,
        }
    }

    fn pop(self: *Self, comptime expected: std.meta.Tag(Value)) void {
        std.debug.assert(self.stack_len != 0);
        std.debug.assert(std.meta.activeTag(self.stack[self.stack_len - 1].value.*) == expected);
        self.stack_len -= 1;
    }

    fn currentFrame(self: *Self) *Frame {
        std.debug.assert(self.stack_len != 0);
        return &self.stack[self.stack_len - 1];
    }
};

/// Low-level TOML decoder used by the generic deserializer.
pub const Decoder = struct {
    const Self = @This();
    const max_depth = 64;

    const SeqFrame = struct {
        elems: []const Value,
        index: usize = 0,
    };

    const TableFrame = struct {
        fields: []const Field,
        index: usize = 0,
    };

    const Frame = union(enum) {
        seq: SeqFrame,
        table: TableFrame,
    };

    allocator: std.mem.Allocator,
    input: []u8,
    root: Value,
    stack: [max_depth]Frame = undefined,
    stack_len: usize = 0,
    pending_value: ?*const Value = null,
    root_used: bool = false,

    pub fn deinit(self: *Self) void {
        self.root.deinit(self.allocator);
        self.allocator.free(self.input);
        self.* = undefined;
    }

    pub fn peek(self: *Self) !Kind {
        return kindOf(try self.currentValue());
    }

    pub fn readNull(self: *Self) !void {
        _ = self;
        return error.InvalidType;
    }

    pub fn readBool(self: *Self) !bool {
        const value = try self.consumeValue();
        return switch (value.*) {
            .bool => |v| v,
            else => error.InvalidType,
        };
    }

    pub fn readInt(self: *Self, comptime T: type) !T {
        const value = try self.consumeValue();
        return switch (value.*) {
            .int => |integer| try TomlNumber.readInt(T, integer),
            else => error.InvalidType,
        };
    }

    pub fn readFloat(self: *Self, comptime T: type) !T {
        const value = try self.consumeValue();
        return switch (value.*) {
            .float => |bytes| try TomlNumber.readFloat(T, .{ .float = bytes }),
            .int => |integer| try TomlNumber.readFloat(T, .{ .int = integer }),
            else => error.InvalidType,
        };
    }

    pub fn readString(self: *Self, allocator: std.mem.Allocator) ![]u8 {
        const value = try self.consumeValue();
        return switch (value.*) {
            .string => |bytes| try allocator.dupe(u8, bytes),
            else => error.InvalidType,
        };
    }

    pub fn readTomlDateTime(self: *Self, allocator: std.mem.Allocator) ![]u8 {
        const value = try self.consumeValue();
        return switch (value.*) {
            .datetime => |bytes| try allocator.dupe(u8, bytes),
            else => error.InvalidType,
        };
    }

    pub fn beginSeq(self: *Self) !?usize {
        const value = try self.consumeValue();
        return switch (value.*) {
            .array => |list| blk: {
                try self.push(.{ .seq = .{ .elems = list.items } });
                break :blk list.items.len;
            },
            else => error.InvalidType,
        };
    }

    pub fn hasNextSeqElem(self: *Self) !bool {
        if (self.pending_value != null) return error.InvalidTomlDecoderState;
        const frame = self.currentSeqFrame();
        if (frame.index == frame.elems.len) return false;
        self.pending_value = &frame.elems[frame.index];
        frame.index += 1;
        return true;
    }

    pub fn endSeq(self: *Self) !void {
        if (self.pending_value != null) return error.InvalidTomlDecoderState;
        self.pop(.seq);
    }

    pub fn beginStruct(self: *Self, comptime T: type) !void {
        _ = T;
        const value = try self.consumeValue();
        switch (value.*) {
            .table => |table| try self.push(.{ .table = .{ .fields = table.fields.items } }),
            else => return error.InvalidType,
        }
    }

    pub fn nextField(self: *Self) !?[]u8 {
        if (self.pending_value != null) return error.InvalidTomlDecoderState;
        const frame = self.currentTableFrame();
        if (frame.index == frame.fields.len) return null;

        const field = &frame.fields[frame.index];
        frame.index += 1;
        self.pending_value = &field.value;
        return try self.allocator.dupe(u8, field.name);
    }

    pub fn endStruct(self: *Self) !void {
        if (self.pending_value != null) return error.InvalidTomlDecoderState;
        self.pop(.table);
    }

    pub fn skipValue(self: *Self) !void {
        _ = try self.consumeValue();
    }

    pub fn finish(self: *Self) !void {
        if (self.pending_value != null) return error.InvalidTomlDecoderState;
        if (self.stack_len != 0) return error.InvalidTomlDecoderState;
        if (!self.root_used) return error.IncompleteTomlDocument;
    }

    fn currentValue(self: *Self) !*const Value {
        if (self.pending_value) |value| return value;
        if (!self.root_used) return &self.root;
        return error.InvalidTomlDecoderState;
    }

    fn consumeValue(self: *Self) !*const Value {
        if (self.pending_value) |value| {
            self.pending_value = null;
            return value;
        }
        if (!self.root_used) {
            self.root_used = true;
            return &self.root;
        }
        return error.InvalidTomlDecoderState;
    }

    fn push(self: *Self, frame: Frame) !void {
        if (self.stack_len == self.stack.len) return error.NestingTooDeep;
        self.stack[self.stack_len] = frame;
        self.stack_len += 1;
    }

    fn pop(self: *Self, comptime expected: std.meta.Tag(Frame)) void {
        std.debug.assert(self.stack_len != 0);
        std.debug.assert(std.meta.activeTag(self.stack[self.stack_len - 1]) == expected);
        self.stack_len -= 1;
    }

    fn currentSeqFrame(self: *Self) *SeqFrame {
        std.debug.assert(self.stack_len != 0);
        return &self.stack[self.stack_len - 1].seq;
    }

    fn currentTableFrame(self: *Self) *TableFrame {
        std.debug.assert(self.stack_len != 0);
        return &self.stack[self.stack_len - 1].table;
    }
};

const Field = struct {
    name: []u8,
    value: Value,

    fn deinit(self: *Field, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        self.value.deinit(allocator);
    }
};

const Table = struct {
    fields: std.ArrayList(Field) = .empty,
    explicit: bool = false,
    is_inline: bool = false,
    is_array_item: bool = false,

    fn deinit(self: *Table, allocator: std.mem.Allocator) void {
        for (self.fields.items) |*field| field.deinit(allocator);
        self.fields.deinit(allocator);
    }

    fn findField(self: *Table, name: []const u8) ?*Field {
        for (self.fields.items) |*field| {
            if (std.mem.eql(u8, field.name, name)) return field;
        }
        return null;
    }
};

const Integer = number.Integer;

const Value = union(enum) {
    bool: bool,
    int: Integer,
    float: []u8,
    datetime: []u8,
    string: []u8,
    array: std.ArrayList(Value),
    table: Table,

    fn deinit(self: *Value, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .bool => {},
            .int => |integer| allocator.free(integer.bytes),
            .float, .datetime, .string => |bytes| allocator.free(bytes),
            .array => |*list| {
                for (list.items) |*item| item.deinit(allocator);
                list.deinit(allocator);
            },
            .table => |*table| table.deinit(allocator),
        }
    }
};

const Parser = struct {
    const Header = struct {
        path: [][]u8,
        array: bool,
    };

    allocator: std.mem.Allocator,
    input: []const u8,
    index: usize = 0,

    fn parseDocument(self: *Parser) !Value {
        var root = Table{};
        errdefer root.deinit(self.allocator);

        var current_path = try self.allocator.alloc([]u8, 0);
        defer freeKeyPath(self.allocator, current_path);

        while (true) {
            try self.skipWhitespaceAndComments();
            if (self.eof()) break;

            if (self.peekByte() == '[') {
                const header = try self.parseTableHeader();
                errdefer freeKeyPath(self.allocator, header.path);
                if (header.array) {
                    _ = try self.appendArrayTableAtPath(&root, header.path);
                } else {
                    _ = try self.defineTableAtPath(&root, header.path);
                }
                freeKeyPath(self.allocator, current_path);
                current_path = header.path;
            } else {
                try self.parseKeyValue(&root, current_path);
            }

            try self.skipSpaceNoNewline();
            try self.skipComment();
            if (!self.eof() and self.peekByte() != '\n' and self.peekByte() != '\r') return error.InvalidTomlSyntax;
        }

        return .{ .table = root };
    }

    fn parseTableHeader(self: *Parser) !Header {
        try self.expectByte('[');
        const array = self.consumeIf('[');

        const path = try self.parseKeyPath(']');
        errdefer freeKeyPath(self.allocator, path);
        try self.skipSpaceNoNewline();
        try self.expectByte(']');
        if (array) try self.expectByte(']');
        return .{ .path = path, .array = array };
    }

    fn parseKeyValue(self: *Parser, root: *Table, current_path: []const []const u8) !void {
        const key = try self.parseKeyPath('=');
        defer freeKeyPath(self.allocator, key);
        try self.skipSpaceNoNewline();
        try self.expectByte('=');

        var value = try self.parseValue();
        var transferred = false;
        errdefer if (!transferred) value.deinit(self.allocator);

        try self.setValueAtPath(root, current_path, key, value);
        transferred = true;
    }

    fn parseKeyPath(self: *Parser, terminator: u8) ![][]u8 {
        var segments: std.ArrayList([]u8) = .empty;
        errdefer {
            for (segments.items) |segment| self.allocator.free(segment);
            segments.deinit(self.allocator);
        }

        while (true) {
            try self.skipSpaceNoNewline();
            try segments.append(self.allocator, try self.parseKeyPart());
            try self.skipSpaceNoNewline();

            const byte = self.peekByteOrNull() orelse return error.InvalidTomlSyntax;
            if (byte == '.') {
                _ = try self.takeByte();
                continue;
            }
            if (byte == terminator) break;
            return error.InvalidTomlSyntax;
        }

        if (segments.items.len == 0) return error.InvalidTomlSyntax;
        return try segments.toOwnedSlice(self.allocator);
    }

    fn parseKeyPart(self: *Parser) ![]u8 {
        return switch (self.peekByteOrNull() orelse return error.InvalidTomlSyntax) {
            '"' => blk: {
                if (self.startsWith("\"\"\"")) return error.InvalidTomlSyntax;
                break :blk try self.parseBasicString();
            },
            '\'' => blk: {
                if (self.startsWith("'''")) return error.InvalidTomlSyntax;
                break :blk try self.parseLiteralString();
            },
            else => try self.parseBareKey(),
        };
    }

    fn parseBareKey(self: *Parser) ![]u8 {
        const start = self.index;
        while (!self.eof() and isBareKeyByte(self.peekByte())) self.index += 1;
        if (self.index == start) return error.InvalidTomlSyntax;
        return try self.allocator.dupe(u8, self.input[start..self.index]);
    }

    fn parseValue(self: *Parser) anyerror!Value {
        try self.skipSpaceNoNewline();
        const byte = self.peekByteOrNull() orelse return error.InvalidTomlSyntax;
        return switch (byte) {
            '"' => .{ .string = try self.parseBasicString() },
            '\'' => .{ .string = try self.parseLiteralString() },
            '[' => try self.parseArray(),
            '{' => try self.parseInlineTable(),
            't' => blk: {
                try self.expectLiteral("true");
                break :blk .{ .bool = true };
            },
            'f' => blk: {
                try self.expectLiteral("false");
                break :blk .{ .bool = false };
            },
            '+', '-', '0'...'9', 'i', 'n' => try self.parseNumber(),
            else => error.InvalidTomlSyntax,
        };
    }

    fn parseArray(self: *Parser) anyerror!Value {
        try self.expectByte('[');
        var values: std.ArrayList(Value) = .empty;
        errdefer {
            for (values.items) |*value| value.deinit(self.allocator);
            values.deinit(self.allocator);
        }

        try self.skipWhitespaceAndComments();
        if (self.consumeIf(']')) return .{ .array = values };

        while (true) {
            try values.append(self.allocator, try self.parseValue());
            try self.skipWhitespaceAndComments();
            if (self.consumeIf(']')) break;
            try self.expectByte(',');
            try self.skipWhitespaceAndComments();
            if (self.consumeIf(']')) break;
        }

        return .{ .array = values };
    }

    fn parseInlineTable(self: *Parser) anyerror!Value {
        try self.expectByte('{');
        var table = Table{};
        errdefer table.deinit(self.allocator);

        try self.skipSpaceNoNewline();
        if (self.consumeIf('}')) {
            markInlineTable(&table);
            return .{ .table = table };
        }

        while (true) {
            const key = try self.parseKeyPath('=');
            defer freeKeyPath(self.allocator, key);
            try self.skipSpaceNoNewline();
            try self.expectByte('=');

            var value = try self.parseValue();
            var transferred = false;
            errdefer if (!transferred) value.deinit(self.allocator);
            try self.setValueAtPath(&table, &.{}, key, value);
            transferred = true;

            try self.skipSpaceNoNewline();
            if (self.consumeIf('}')) break;
            try self.expectByte(',');
            try self.skipSpaceNoNewline();
        }

        markInlineTable(&table);
        return .{ .table = table };
    }

    fn parseNumber(self: *Parser) !Value {
        const start = self.index;
        while (!self.eof()) {
            const byte = self.peekByte();
            if (isValueDelimiter(byte)) {
                if (byte == ' ' and self.index == start + 10 and looksLikeDatePrefix(self.input[start..self.index])) {
                    self.index += 1;
                    continue;
                }
                break;
            }
            self.index += 1;
        }
        const raw = std.mem.trim(u8, self.input[start..self.index], " \t");
        if (raw.len == 0) return error.InvalidTomlSyntax;

        if (parseDateTimeValue(self.allocator, raw)) |value| return value else |err| switch (err) {
            error.InvalidTomlDateTime => {},
            else => |e| return e,
        }

        return try self.parseNumberToken(raw);
    }

    fn parseNumberToken(self: *Parser, raw: []const u8) !Value {
        const token = TomlNumber.parseAlloc(self.allocator, raw) catch |err| switch (err) {
            error.InvalidNumberSyntax => return error.InvalidTomlSyntax,
            else => |e| return e,
        };
        return switch (token) {
            .int => |integer| .{ .int = integer },
            .float => |bytes| .{ .float = bytes },
        };
    }

    fn parseDateTimeValue(allocator: std.mem.Allocator, raw: []const u8) !Value {
        if (OffsetDateTime.parse(raw)) |_| {
            return .{ .datetime = try allocator.dupe(u8, raw) };
        } else |_| {}

        if (LocalDateTime.parse(raw)) |_| {
            return .{ .datetime = try allocator.dupe(u8, raw) };
        } else |_| {}

        if (LocalDate.parse(raw)) |_| {
            return .{ .datetime = try allocator.dupe(u8, raw) };
        } else |_| {}

        if (LocalTime.parse(raw)) |_| {
            return .{ .datetime = try allocator.dupe(u8, raw) };
        } else |_| {}

        return error.InvalidTomlDateTime;
    }

    fn parseBasicString(self: *Parser) ![]u8 {
        try self.expectByte('"');
        if (self.startsWith("\"\"")) {
            self.index += 2;
            return try self.parseMultilineBasicString();
        }

        var out = std.Io.Writer.Allocating.init(self.allocator);
        errdefer out.deinit();

        while (true) {
            const byte = try self.takeByte();
            switch (byte) {
                '"' => {
                    const result = try out.toOwnedSlice();
                    errdefer self.allocator.free(result);
                    if (!std.unicode.utf8ValidateSlice(result)) return error.InvalidUtf8;
                    return result;
                },
                '\\' => try self.parseEscape(&out.writer),
                0x00...0x08, 0x0a...0x1f, 0x7f => return error.InvalidTomlSyntax,
                else => try out.writer.writeByte(byte),
            }
        }
    }

    fn parseMultilineBasicString(self: *Parser) ![]u8 {
        self.trimFirstMultilineNewline();
        var out = std.Io.Writer.Allocating.init(self.allocator);
        errdefer out.deinit();

        while (true) {
            if (try self.consumeMultilineStringEnd('"', &out.writer)) {
                const result = try out.toOwnedSlice();
                errdefer self.allocator.free(result);
                if (!std.unicode.utf8ValidateSlice(result)) return error.InvalidUtf8;
                return result;
            }

            const byte = try self.takeByte();
            switch (byte) {
                '\\' => try self.parseMultilineEscape(&out.writer),
                0x00...0x08, 0x0b...0x0c, 0x0e...0x1f, 0x7f => return error.InvalidTomlSyntax,
                else => try out.writer.writeByte(byte),
            }
        }
    }

    fn parseLiteralString(self: *Parser) ![]u8 {
        try self.expectByte('\'');
        if (self.startsWith("''")) {
            self.index += 2;
            return try self.parseMultilineLiteralString();
        }

        const start = self.index;
        while (true) {
            const byte = try self.takeByte();
            if (byte == '\'') {
                const result = try self.allocator.dupe(u8, self.input[start .. self.index - 1]);
                errdefer self.allocator.free(result);
                if (!std.unicode.utf8ValidateSlice(result)) return error.InvalidUtf8;
                return result;
            }
            if ((byte < 0x20 and byte != '\t') or byte == 0x7f) return error.InvalidTomlSyntax;
        }
    }

    fn parseMultilineLiteralString(self: *Parser) ![]u8 {
        self.trimFirstMultilineNewline();
        var out = std.Io.Writer.Allocating.init(self.allocator);
        errdefer out.deinit();

        while (true) {
            if (try self.consumeMultilineStringEnd('\'', &out.writer)) {
                const result = try out.toOwnedSlice();
                errdefer self.allocator.free(result);
                if (!std.unicode.utf8ValidateSlice(result)) return error.InvalidUtf8;
                return result;
            }

            const byte = try self.takeByte();
            if ((byte < 0x20 and byte != '\t' and byte != '\n' and byte != '\r') or byte == 0x7f) return error.InvalidTomlSyntax;
            try out.writer.writeByte(byte);
        }
    }

    fn parseEscape(self: *Parser, writer: *std.Io.Writer) !void {
        const escape = try self.takeByte();
        switch (escape) {
            'b' => try writer.writeByte(0x08),
            't' => try writer.writeByte('\t'),
            'n' => try writer.writeByte('\n'),
            'f' => try writer.writeByte(0x0c),
            'r' => try writer.writeByte('\r'),
            '"' => try writer.writeByte('"'),
            '\\' => try writer.writeByte('\\'),
            'u' => try self.parseUnicodeEscape(writer, 4),
            'U' => try self.parseUnicodeEscape(writer, 8),
            else => return error.InvalidTomlSyntax,
        }
    }

    fn parseMultilineEscape(self: *Parser, writer: *std.Io.Writer) !void {
        if (try self.consumeEscapedNewline()) return;
        try self.parseEscape(writer);
    }

    fn consumeEscapedNewline(self: *Parser) !bool {
        const saved = self.index;
        while (!self.eof() and (self.peekByte() == ' ' or self.peekByte() == '\t')) self.index += 1;

        if (self.consumeNewline()) {
            while (!self.eof()) {
                switch (self.peekByte()) {
                    ' ', '\t' => self.index += 1,
                    '\n' => self.index += 1,
                    '\r' => {
                        self.index += 1;
                        if (!self.eof() and self.peekByte() == '\n') self.index += 1;
                    },
                    else => return true,
                }
            }
            return true;
        }

        self.index = saved;
        return false;
    }

    fn consumeMultilineStringEnd(self: *Parser, quote: u8, writer: *std.Io.Writer) !bool {
        if (self.eof() or self.peekByte() != quote) return false;

        var count: usize = 0;
        while (self.index + count < self.input.len and self.input[self.index + count] == quote) count += 1;
        if (count < 3) return false;
        if (count > 5) return error.InvalidTomlSyntax;

        for (0..count - 3) |_| try writer.writeByte(quote);
        self.index += count;
        return true;
    }

    fn trimFirstMultilineNewline(self: *Parser) void {
        _ = self.consumeNewline();
    }

    fn consumeNewline(self: *Parser) bool {
        if (self.eof()) return false;
        if (self.peekByte() == '\n') {
            self.index += 1;
            return true;
        }
        if (self.peekByte() == '\r') {
            self.index += 1;
            if (!self.eof() and self.peekByte() == '\n') self.index += 1;
            return true;
        }
        return false;
    }

    fn parseUnicodeEscape(self: *Parser, writer: *std.Io.Writer, digits_len: usize) !void {
        var codepoint: u21 = 0;
        for (0..digits_len) |_| {
            const digit = hexValue(try self.takeByte()) orelse return error.InvalidTomlSyntax;
            codepoint = (codepoint << 4) | digit;
        }

        var buffer: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(codepoint, &buffer) catch return error.InvalidUtf8;
        try writer.writeAll(buffer[0..len]);
    }

    fn setValueAtPath(self: *Parser, root: *Table, current_path: []const []const u8, key: []const []const u8, value: Value) !void {
        if (key.len == 0) return error.InvalidTomlSyntax;

        var table = try self.resolveCurrentTable(root, current_path);
        for (key[0 .. key.len - 1]) |segment| table = try self.getOrCreateImplicitTable(table, segment);
        if (table.is_inline) return error.InvalidTomlSyntax;
        if (table.findField(key[key.len - 1]) != null) return error.DuplicateField;

        const field_name = try self.allocator.dupe(u8, key[key.len - 1]);
        errdefer self.allocator.free(field_name);
        try table.fields.append(self.allocator, .{ .name = field_name, .value = value });
    }

    fn defineTableAtPath(self: *Parser, root: *Table, path: []const []const u8) !*Table {
        if (path.len == 0) return error.InvalidTomlSyntax;
        var table = root;
        for (path[0 .. path.len - 1]) |segment| table = try self.getOrCreateImplicitTable(table, segment);

        const result = try self.getOrCreateImplicitTable(table, path[path.len - 1]);
        if (result.is_inline or result.explicit) return error.DuplicateField;
        result.explicit = true;
        return result;
    }

    fn appendArrayTableAtPath(self: *Parser, root: *Table, path: []const []const u8) !*Table {
        if (path.len == 0) return error.InvalidTomlSyntax;
        var table = root;
        for (path[0 .. path.len - 1]) |segment| table = try self.getOrCreateImplicitTable(table, segment);
        if (table.is_inline) return error.InvalidTomlSyntax;

        const name = path[path.len - 1];
        if (table.findField(name)) |field| {
            switch (field.value) {
                .array => |*array| {
                    if (!isArrayTable(array)) return error.InvalidTomlSyntax;
                    var new_value = Value{ .table = .{ .explicit = true, .is_array_item = true } };
                    errdefer new_value.deinit(self.allocator);
                    try array.append(self.allocator, new_value);
                    return &array.items[array.items.len - 1].table;
                },
                else => return error.DuplicateField,
            }
        }

        const field_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(field_name);
        var array: std.ArrayList(Value) = .empty;
        errdefer {
            for (array.items) |*item| item.deinit(self.allocator);
            array.deinit(self.allocator);
        }
        try array.append(self.allocator, .{ .table = .{ .explicit = true, .is_array_item = true } });
        try table.fields.append(self.allocator, .{ .name = field_name, .value = .{ .array = array } });
        return &table.fields.items[table.fields.items.len - 1].value.array.items[0].table;
    }

    fn resolveCurrentTable(self: *Parser, root: *Table, path: []const []const u8) !*Table {
        var table = root;
        for (path) |segment| table = try self.getExistingCurrentTable(table, segment);
        return table;
    }

    fn getExistingCurrentTable(self: *Parser, table: *Table, name: []const u8) !*Table {
        _ = self;
        const field = table.findField(name) orelse return error.InvalidTomlSyntax;
        return switch (field.value) {
            .table => |*nested| nested,
            .array => |*array| blk: {
                if (array.items.len == 0) return error.InvalidTomlSyntax;
                const last = &array.items[array.items.len - 1];
                if (last.* != .table) return error.InvalidTomlSyntax;
                break :blk &last.table;
            },
            else => error.InvalidTomlSyntax,
        };
    }

    fn getOrCreateImplicitTable(self: *Parser, table: *Table, name: []const u8) !*Table {
        if (table.is_inline) return error.InvalidTomlSyntax;
        if (table.findField(name)) |field| {
            return switch (field.value) {
                .table => |*nested| if (nested.is_inline) error.InvalidTomlSyntax else nested,
                .array => |*array| blk: {
                    if (array.items.len == 0) return error.InvalidTomlSyntax;
                    const last = &array.items[array.items.len - 1];
                    if (last.* != .table) return error.InvalidTomlSyntax;
                    break :blk &last.table;
                },
                else => error.DuplicateField,
            };
        }

        const field_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(field_name);
        try table.fields.append(self.allocator, .{ .name = field_name, .value = .{ .table = .{} } });
        return &table.fields.items[table.fields.items.len - 1].value.table;
    }

    fn expectLiteral(self: *Parser, literal: []const u8) !void {
        for (literal) |expected| try self.expectByte(expected);
        if (!self.eof() and !isValueDelimiter(self.peekByte())) return error.InvalidTomlSyntax;
    }

    fn skipWhitespaceAndComments(self: *Parser) !void {
        while (!self.eof()) {
            switch (self.peekByte()) {
                ' ', '\t', '\n', '\r' => _ = try self.takeByte(),
                '#' => try self.skipComment(),
                else => return,
            }
        }
    }

    fn skipSpaceNoNewline(self: *Parser) !void {
        while (!self.eof()) {
            switch (self.peekByte()) {
                ' ', '\t' => _ = try self.takeByte(),
                else => return,
            }
        }
    }

    fn skipComment(self: *Parser) !void {
        if (self.eof() or self.peekByte() != '#') return;
        while (!self.eof()) {
            const byte = try self.takeByte();
            if (byte == '\n' or byte == '\r') break;
        }
    }

    fn expectByte(self: *Parser, expected: u8) !void {
        const actual = try self.takeByte();
        if (actual != expected) return error.InvalidTomlSyntax;
    }

    fn consumeIf(self: *Parser, expected: u8) bool {
        if (!self.eof() and self.peekByte() == expected) {
            self.index += 1;
            return true;
        }
        return false;
    }

    fn takeByte(self: *Parser) !u8 {
        if (self.eof()) return error.EndOfStream;
        const byte = self.input[self.index];
        self.index += 1;
        return byte;
    }

    fn peekByte(self: *Parser) u8 {
        std.debug.assert(!self.eof());
        return self.input[self.index];
    }

    fn peekByteOrNull(self: *Parser) ?u8 {
        if (self.eof()) return null;
        return self.input[self.index];
    }

    fn startsWith(self: *Parser, bytes: []const u8) bool {
        return self.index + bytes.len <= self.input.len and std.mem.eql(u8, self.input[self.index .. self.index + bytes.len], bytes);
    }

    fn eof(self: *Parser) bool {
        return self.index >= self.input.len;
    }
};

fn freeKeyPath(allocator: std.mem.Allocator, path: []const []u8) void {
    for (path) |segment| allocator.free(segment);
    allocator.free(path);
}

fn markInlineTable(table: *Table) void {
    table.is_inline = true;
    table.explicit = true;
    for (table.fields.items) |*field| {
        switch (field.value) {
            .table => |*nested| markInlineTable(nested),
            .array => |*array| for (array.items) |*item| {
                if (item.* == .table) markInlineTable(&item.table);
            },
            else => {},
        }
    }
}

fn isArrayTable(array: *const std.ArrayList(Value)) bool {
    if (array.items.len == 0) return false;
    for (array.items) |item| {
        switch (item) {
            .table => |table| if (!table.is_array_item) return false,
            else => return false,
        }
    }
    return true;
}

fn kindOf(value: *const Value) Kind {
    return switch (value.*) {
        .bool => .bool,
        .int => .int,
        .float => .float,
        .datetime => .datetime,
        .string => .string,
        .array => .seq,
        .table => .struct_,
    };
}

fn isBareKey(key: []const u8) bool {
    if (key.len == 0) return false;
    for (key) |byte| if (!isBareKeyByte(byte)) return false;
    return true;
}

fn isBareKeyByte(byte: u8) bool {
    return switch (byte) {
        'a'...'z', 'A'...'Z', '0'...'9', '_', '-' => true,
        else => false,
    };
}

fn isValueDelimiter(byte: u8) bool {
    return switch (byte) {
        ' ', '\t', '\n', '\r', ',', ']', '}', '#' => true,
        else => false,
    };
}

fn looksLikeDatePrefix(bytes: []const u8) bool {
    return bytes.len == 10 and
        std.ascii.isDigit(bytes[0]) and
        std.ascii.isDigit(bytes[1]) and
        std.ascii.isDigit(bytes[2]) and
        std.ascii.isDigit(bytes[3]) and
        bytes[4] == '-' and
        std.ascii.isDigit(bytes[5]) and
        std.ascii.isDigit(bytes[6]) and
        bytes[7] == '-' and
        std.ascii.isDigit(bytes[8]) and
        std.ascii.isDigit(bytes[9]);
}

fn hexValue(byte: u8) ?u21 {
    return switch (byte) {
        '0'...'9' => byte - '0',
        'a'...'f' => byte - 'a' + 10,
        'A'...'F' => byte - 'A' + 10,
        else => null,
    };
}

fn renderDocument(writer: *std.Io.Writer, root: Table) !void {
    var path: [64][]const u8 = undefined;
    var wrote_any = try renderTableBody(writer, root);
    try renderTableSections(writer, root, &path, 0, &wrote_any);
}

fn renderTableBody(writer: *std.Io.Writer, table: Table) !bool {
    var wrote = false;
    for (table.fields.items) |field| {
        if (field.value == .table) continue;
        if (isArrayOfTables(field.value)) continue;
        if (wrote) try writer.writeByte('\n');
        try writeTomlKey(writer, field.name);
        try writer.writeAll(" = ");
        try renderInlineValue(writer, field.value);
        wrote = true;
    }
    return wrote;
}

fn renderTableSections(writer: *std.Io.Writer, table: Table, path: *[64][]const u8, depth: usize, wrote_any: *bool) anyerror!void {
    for (table.fields.items) |field| {
        if (isArrayOfTables(field.value)) {
            try renderArrayTableSections(writer, field, path, depth, wrote_any);
            continue;
        }
        if (field.value != .table) continue;
        if (depth == path.len) return error.NestingTooDeep;

        path[depth] = field.name;
        if (wrote_any.*) try writer.writeAll("\n\n");
        try writer.writeByte('[');
        for (path[0 .. depth + 1], 0..) |part, i| {
            if (i != 0) try writer.writeByte('.');
            try writeTomlKey(writer, part);
        }
        try writer.writeAll("]\n");
        _ = try renderTableBody(writer, field.value.table);
        wrote_any.* = true;
        try renderTableSections(writer, field.value.table, path, depth + 1, wrote_any);
    }
}

fn renderArrayTableSections(writer: *std.Io.Writer, field: Field, path: *[64][]const u8, depth: usize, wrote_any: *bool) anyerror!void {
    if (depth == path.len) return error.NestingTooDeep;
    path[depth] = field.name;
    for (field.value.array.items) |item| {
        if (wrote_any.*) try writer.writeAll("\n\n");
        try writer.writeAll("[[");
        for (path[0 .. depth + 1], 0..) |part, i| {
            if (i != 0) try writer.writeByte('.');
            try writeTomlKey(writer, part);
        }
        try writer.writeAll("]]\n");
        _ = try renderTableBody(writer, item.table);
        wrote_any.* = true;
        try renderTableSections(writer, item.table, path, depth + 1, wrote_any);
    }
}

fn isArrayOfTables(value: Value) bool {
    return switch (value) {
        .array => |array| array.items.len != 0 and blk: {
            for (array.items) |item| {
                if (item != .table) break :blk false;
            }
            break :blk true;
        },
        else => false,
    };
}

fn renderInlineValue(writer: *std.Io.Writer, value: Value) !void {
    switch (value) {
        .bool => |v| try writer.writeAll(if (v) "true" else "false"),
        .int => |integer| {
            if (integer.base == 10) {
                try writer.writeAll(integer.bytes);
            } else {
                try writer.writeAll(switch (integer.base) {
                    16 => "0x",
                    8 => "0o",
                    2 => "0b",
                    else => return error.InvalidValue,
                });
                try writer.writeAll(integer.bytes);
            }
        },
        .float, .datetime => |bytes| try writer.writeAll(bytes),
        .string => |bytes| try writeTomlString(writer, bytes),
        .array => |list| {
            try writer.writeByte('[');
            for (list.items, 0..) |item, i| {
                if (i != 0) try writer.writeAll(", ");
                try renderInlineValue(writer, item);
            }
            try writer.writeByte(']');
        },
        .table => |table| {
            try writer.writeAll("{ ");
            for (table.fields.items, 0..) |field, i| {
                if (i != 0) try writer.writeAll(", ");
                try writeTomlKey(writer, field.name);
                try writer.writeAll(" = ");
                try renderInlineValue(writer, field.value);
            }
            try writer.writeAll(" }");
        },
    }
}

fn writeTomlKey(writer: *std.Io.Writer, key: []const u8) !void {
    if (isBareKey(key)) {
        try writer.writeAll(key);
    } else {
        try writeTomlString(writer, key);
    }
}

fn writeTomlString(writer: *std.Io.Writer, value: []const u8) !void {
    try writer.writeByte('"');
    var run_start: usize = 0;
    for (value, 0..) |byte, i| {
        switch (byte) {
            0x08 => try writeEscapedTomlByte(writer, value, &run_start, i, "\\b"),
            '\t' => try writeEscapedTomlByte(writer, value, &run_start, i, "\\t"),
            '\n' => try writeEscapedTomlByte(writer, value, &run_start, i, "\\n"),
            0x0c => try writeEscapedTomlByte(writer, value, &run_start, i, "\\f"),
            '\r' => try writeEscapedTomlByte(writer, value, &run_start, i, "\\r"),
            '"' => try writeEscapedTomlByte(writer, value, &run_start, i, "\\\""),
            '\\' => try writeEscapedTomlByte(writer, value, &run_start, i, "\\\\"),
            0x00...0x07, 0x0b, 0x0e...0x1f, 0x7f => {
                const digits = "0123456789abcdef";
                try writer.writeAll(value[run_start..i]);
                try writer.writeAll("\\u00");
                try writer.writeByte(digits[byte >> 4]);
                try writer.writeByte(digits[byte & 0x0f]);
                run_start = i + 1;
            },
            else => {},
        }
    }
    try writer.writeAll(value[run_start..]);
    try writer.writeByte('"');
}

fn writeEscapedTomlByte(writer: *std.Io.Writer, value: []const u8, run_start: *usize, index: usize, escaped: []const u8) !void {
    try writer.writeAll(value[run_start.*..index]);
    try writer.writeAll(escaped);
    run_start.* = index + 1;
}

fn tomlInteger(value: anytype) !i64 {
    return std.math.cast(i64, value) orelse error.IntegerOverflow;
}

fn expectToml(value: anytype, expected: []const u8) !void {
    var buffer: [2048]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);

    try write(&writer, value);

    try std.testing.expectEqualStrings(expected, writer.buffered());
}

fn expectTomlWithOptions(value: anytype, options: WriteOptions, expected: []const u8) !void {
    var buffer: [4096]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);

    try writeWithOptions(std.testing.allocator, &writer, value, options);

    try std.testing.expectEqualStrings(expected, writer.buffered());
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

test "toml writes root structs" {
    const User = struct {
        id: u64,
        name: []const u8,
        active: bool,
    };

    try expectToml(User{ .id = 1, .name = "Grant", .active = true },
        \\id = 1
        \\name = "Grant"
        \\active = true
    );
}

test "toml writes strings arrays and nested structs" {
    const Profile = struct {
        bio: []const u8,
        tags: []const []const u8,
    };
    const User = struct {
        name: []const u8,
        scores: [2]u8,
        profile: Profile,
    };
    const tags = [_][]const u8{ "admin", "ops" };

    try expectToml(User{
        .name = "quote: \" slash: \\ newline:\n",
        .scores = .{ 9, 10 },
        .profile = .{ .bio = "Zig", .tags = tags[0..] },
    },
        \\name = "quote: \" slash: \\ newline:\n"
        \\scores = [9, 10]
        \\profile = { bio = "Zig", tags = ["admin", "ops"] }
    );
}

test "toml escapes DEL control character" {
    const Document = struct { value: []const u8 };

    try expectToml(Document{ .value = "a\x7fb" }, "value = \"a\\u007fb\"");
    try expectTomlWithOptions(Document{ .value = "a\x7fb" }, .{ .layout = .sections }, "value = \"a\\u007fb\"");
}

test "toml rejects integers outside signed 64-bit range" {
    const Document = struct { value: u64 };

    var buffer: [128]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    try std.testing.expectError(error.IntegerOverflow, write(&writer, Document{ .value = std.math.maxInt(u64) }));

    var sections_buffer: [128]u8 = undefined;
    var sections_writer: std.Io.Writer = .fixed(&sections_buffer);
    try std.testing.expectError(error.IntegerOverflow, writeWithOptions(std.testing.allocator, &sections_writer, Document{ .value = std.math.maxInt(u64) }, .{ .layout = .sections }));

    const Max = struct { value: i64 };
    try expectToml(Max{ .value = std.math.maxInt(i64) }, "value = 9223372036854775807");
}

test "toml writes and reads Bytes wrapper as base64" {
    const Blob = struct {
        data: base64.Bytes,
    };
    const bytes = [_]u8{ 'H', 'e', 'l', 'l', 'o' };

    try expectToml(Blob{ .data = .{ .value = bytes[0..] } }, "data = \"SGVsbG8=\"");

    const parsed = try readSlice(Blob, std.testing.allocator, "data = \"SGVsbG8=\"");
    defer deinitValue(Blob, std.testing.allocator, parsed);
    try std.testing.expectEqualSlices(u8, bytes[0..], parsed.data.value);
}

test "toml writes and reads bytes metadata as base64" {
    const Blob = struct {
        name: []const u8,
        data: []const u8,

        pub const zerde = .{
            .fields = .{
                .data = .{ .bytes = true },
            },
        };
    };
    const bytes = [_]u8{ 0, 1, 2, 3 };

    try expectToml(Blob{ .name = "raw", .data = bytes[0..] },
        \\name = "raw"
        \\data = "AAECAw=="
    );

    const parsed = try readSlice(Blob, std.testing.allocator,
        \\name = "raw"
        \\data = "AAECAw=="
    );
    defer deinitValue(Blob, std.testing.allocator, parsed);
    try std.testing.expectEqualStrings("raw", parsed.name);
    try std.testing.expectEqualSlices(u8, bytes[0..], parsed.data);
}

test "toml roundtrips fixed byte arrays with bytes metadata" {
    const Packet = struct {
        data: [4]u8,

        pub const zerde = .{
            .fields = .{
                .data = .{ .bytes = true },
            },
        };
    };
    const packet = Packet{ .data = .{ 1, 2, 3, 4 } };

    const encoded = try writeAlloc(std.testing.allocator, packet);
    defer std.testing.allocator.free(encoded);
    try std.testing.expectEqualStrings("data = \"AQIDBA==\"", encoded);

    const parsed = try readSlice(Packet, std.testing.allocator, encoded);
    try std.testing.expectEqualDeep(packet, parsed);
}

test "toml rejects invalid base64 bytes" {
    const Blob = struct {
        data: base64.Bytes,
    };

    try std.testing.expectError(error.InvalidBase64, readSlice(Blob, std.testing.allocator, "data = \"not base64!\""));
}

test "toml writes metadata renamed and skipped fields" {
    const ApiUser = struct {
        user_id: u64,
        display_name: []const u8,
        password_hash: []const u8,

        pub const zerde = .{
            .rename_all = .camel_case,
            .fields = .{
                .display_name = .{ .rename = "name" },
                .password_hash = .{ .skip_serializing = true },
            },
        };
    };

    try expectToml(ApiUser{ .user_id = 1, .display_name = "Grant", .password_hash = "secret" },
        \\userId = 1
        \\name = "Grant"
    );
}

test "toml rejects unsupported root values and nulls" {
    var buffer: [128]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    try std.testing.expectError(error.TomlRootMustBeStruct, write(&writer, @as(u8, 1)));

    const ValueWithNull = struct { nickname: ?[]const u8 };
    var null_buffer: [128]u8 = undefined;
    var null_writer: std.Io.Writer = .fixed(&null_buffer);
    try std.testing.expectError(error.UnsupportedTomlNull, write(&null_writer, ValueWithNull{ .nickname = null }));
}

test "toml reads primitive fields" {
    const User = struct {
        id: u64,
        name: []const u8,
        active: bool,
        score: f64,
    };

    const value = try readSlice(User, std.testing.allocator,
        \\id = 1_000
        \\name = "Ada"
        \\active = true
        \\score = 1.25e1
    );
    defer deinitValue(User, std.testing.allocator, value);

    try std.testing.expectEqual(@as(u64, 1000), value.id);
    try std.testing.expectEqualStrings("Ada", value.name);
    try std.testing.expect(value.active);
    try std.testing.expectEqual(@as(f64, 12.5), value.score);
}

test "toml reads arrays inline tables and table headers" {
    const Profile = struct {
        bio: []const u8,
        tags: []const []const u8,
    };
    const User = struct {
        name: []const u8,
        scores: []const u16,
        profile: Profile,
    };

    const value = try readSlice(User, std.testing.allocator,
        \\name = "Ada"
        \\scores = [9, 10, 11]
        \\
        \\[profile]
        \\bio = "systems"
        \\tags = ["admin", 'ops']
    );
    defer deinitValue(User, std.testing.allocator, value);

    try std.testing.expectEqualStrings("Ada", value.name);
    try std.testing.expectEqualDeep(&[_]u16{ 9, 10, 11 }, value.scores);
    try std.testing.expectEqualStrings("systems", value.profile.bio);
    try std.testing.expectEqual(@as(usize, 2), value.profile.tags.len);
    try std.testing.expectEqualStrings("admin", value.profile.tags[0]);
    try std.testing.expectEqualStrings("ops", value.profile.tags[1]);
}

test "toml reads metadata renamed skipped and defaulted fields" {
    const ApiUser = struct {
        user_id: u64,
        display_name: []const u8,
        token: []const u8 = "default-token",
        nickname: ?[]const u8,

        pub const zerde = .{
            .rename_all = .camel_case,
            .fields = .{
                .display_name = .{ .rename = "name" },
                .token = .{ .skip_deserializing = true },
            },
        };
    };

    const value = try readSlice(ApiUser, std.testing.allocator,
        \\userId = 1
        \\name = "Ada"
        \\token = "ignored"
    );
    defer deinitValue(ApiUser, std.testing.allocator, value);

    try std.testing.expectEqual(@as(u64, 1), value.user_id);
    try std.testing.expectEqualStrings("Ada", value.display_name);
    try std.testing.expectEqualStrings("default-token", value.token);
    try std.testing.expect(value.nickname == null);
}

test "toml roundtrips basic structs" {
    const Profile = struct {
        tags: []const []const u8,
    };
    const User = struct {
        id: u64,
        name: []const u8,
        scores: []const u16,
        profile: Profile,
    };

    const scores = [_]u16{ 9, 10, 11 };
    const tags = [_][]const u8{ "admin", "ops" };
    const user = User{ .id = 1, .name = "Grant", .scores = scores[0..], .profile = .{ .tags = tags[0..] } };

    const bytes = try writeAlloc(std.testing.allocator, user);
    defer std.testing.allocator.free(bytes);

    const parsed = try readSlice(User, std.testing.allocator, bytes);
    defer deinitValue(User, std.testing.allocator, parsed);

    try std.testing.expectEqualDeep(user, parsed);
}

test "toml skips unknown fields and reports duplicate known fields" {
    const User = struct {
        id: u8,
        name: []const u8,
    };

    const value = try readSlice(User, std.testing.allocator,
        \\extra = { nested = [1, 2, 3] }
        \\id = 7
        \\name = "Ada"
    );
    defer deinitValue(User, std.testing.allocator, value);

    try std.testing.expectEqual(@as(u8, 7), value.id);
    try std.testing.expectEqualStrings("Ada", value.name);

    try std.testing.expectError(error.DuplicateField, readSlice(User, std.testing.allocator,
        \\id = 1
        \\id = 2
        \\name = "Ada"
    ));
}

test "toml rejects duplicate keys and invalid table redefinitions" {
    const User = struct { id: u8 };
    const Nested = struct {
        owner: struct { name: []const u8 },
    };

    try std.testing.expectError(error.DuplicateField, readSlice(User, std.testing.allocator,
        \\id = 1
        \\id = 2
    ));
    try std.testing.expectError(error.DuplicateField, readSlice(Nested, std.testing.allocator,
        \\[owner]
        \\name = "Ada"
        \\[owner]
        \\name = "Grace"
    ));
    try std.testing.expectError(error.InvalidTomlSyntax, readSlice(Nested, std.testing.allocator,
        \\owner = { name = "Ada" }
        \\[owner]
        \\name = "Grace"
    ));
    try std.testing.expectError(error.DuplicateField, readSlice(Nested, std.testing.allocator,
        \\owner.name = "Ada"
        \\owner.name = "Grace"
    ));
}

test "toml rejects array table headers after ordinary arrays" {
    const Empty = struct {};

    try std.testing.expectError(error.InvalidTomlSyntax, readSlice(Empty, std.testing.allocator,
        \\x = [1]
        \\[[x]]
        \\a = 1
    ));
    try std.testing.expectError(error.InvalidTomlSyntax, readSlice(Empty, std.testing.allocator,
        \\x = []
        \\[[x]]
        \\a = 1
    ));
    try std.testing.expectError(error.InvalidTomlSyntax, readSlice(Empty, std.testing.allocator,
        \\x = [{ a = 1 }]
        \\[[x]]
        \\a = 2
    ));
}

test "toml writes and reads arrays of tables" {
    const Server = struct {
        host: []const u8,
        port: u16,
    };
    const Config = struct {
        name: []const u8,
        servers: []const Server,
    };
    const servers = [_]Server{
        .{ .host = "one.example.com", .port = 8001 },
        .{ .host = "two.example.com", .port = 8002 },
    };
    const config = Config{ .name = "prod", .servers = servers[0..] };

    try expectTomlWithOptions(config, .{ .layout = .sections },
        \\name = "prod"
        \\
        \\[[servers]]
        \\host = "one.example.com"
        \\port = 8001
        \\
        \\[[servers]]
        \\host = "two.example.com"
        \\port = 8002
    );

    const parsed = try readSlice(Config, std.testing.allocator,
        \\name = "prod"
        \\[[servers]]
        \\host = "one.example.com"
        \\port = 8001
        \\[[servers]]
        \\host = "two.example.com"
        \\port = 8002
    );
    defer deinitValue(Config, std.testing.allocator, parsed);

    try std.testing.expectEqualStrings("prod", parsed.name);
    try std.testing.expectEqual(@as(usize, 2), parsed.servers.len);
    try std.testing.expectEqualStrings("one.example.com", parsed.servers[0].host);
    try std.testing.expectEqual(@as(u16, 8001), parsed.servers[0].port);
    try std.testing.expectEqualStrings("two.example.com", parsed.servers[1].host);
    try std.testing.expectEqual(@as(u16, 8002), parsed.servers[1].port);
}

test "toml reads nested tables inside arrays of tables" {
    const Meta = struct { zone: []const u8 };
    const Server = struct {
        host: []const u8,
        meta: Meta,
    };
    const Config = struct { servers: []const Server };

    const parsed = try readSlice(Config, std.testing.allocator,
        \\[[servers]]
        \\host = "one"
        \\[servers.meta]
        \\zone = "a"
        \\[[servers]]
        \\host = "two"
        \\[servers.meta]
        \\zone = "b"
    );
    defer deinitValue(Config, std.testing.allocator, parsed);

    try std.testing.expectEqual(@as(usize, 2), parsed.servers.len);
    try std.testing.expectEqualStrings("one", parsed.servers[0].host);
    try std.testing.expectEqualStrings("a", parsed.servers[0].meta.zone);
    try std.testing.expectEqualStrings("two", parsed.servers[1].host);
    try std.testing.expectEqualStrings("b", parsed.servers[1].meta.zone);
}

test "toml reads multiline basic and literal strings" {
    const Document = struct {
        basic: []const u8,
        folded: []const u8,
        literal: []const u8,
    };

    const parsed = try readSlice(Document, std.testing.allocator,
        \\basic = """
        \\first line
        \\second\nline"""
        \\folded = """one \
        \\  two"""
        \\literal = '''
        \\raw \ stays raw
        \\and ' quotes are fine'''
    );
    defer deinitValue(Document, std.testing.allocator, parsed);

    try std.testing.expectEqualStrings(
        \\first line
        \\second
        \\line
    ,
        parsed.basic,
    );
    try std.testing.expectEqualStrings("one two", parsed.folded);
    try std.testing.expectEqualStrings(
        \\raw \ stays raw
        \\and ' quotes are fine
    ,
        parsed.literal,
    );
}

test "toml reads multiline strings ending with quote characters" {
    const Document = struct { value: []const u8 };

    try expectRead(Document,
        \\value = """ends with quote """"
    , .{ .value = "ends with quote \"" });
    try expectRead(Document,
        \\value = """ends with two quotes """""
    , .{ .value = "ends with two quotes \"\"" });
    try expectRead(Document,
        \\value = '''ends with quote ''''
    , .{ .value = "ends with quote '" });
    try expectRead(Document,
        \\value = '''ends with two quotes '''''
    , .{ .value = "ends with two quotes ''" });
}

test "toml rejects malformed multiline strings" {
    const Document = struct { value: []const u8 };

    try expectReadFails(Document, "value = \"\"\"unterminated");
    try expectReadFails(Document, "value = '''unterminated");
    try expectReadFails(Document, "value = \"\"\"bad\\q\"\"\"");
    try expectReadFails(Document, "\"\"\"bad\"\"\" = 1");
}

test "toml rejects raw DEL in strings" {
    const Document = struct { value: []const u8 };

    try expectReadFails(Document, "value = \"a\x7fb\"");
    try expectReadFails(Document, "value = \"\"\"a\x7fb\"\"\"");
    try expectReadFails(Document, "value = 'a\x7fb'");
    try expectReadFails(Document, "value = '''a\x7fb'''");
}

test "toml reads all integer number formats" {
    const Values = struct {
        decimal: i64,
        positive: i64,
        grouped: i64,
        hex: u64,
        octal: u16,
        binary: u8,
    };

    const value = try readSlice(Values, std.testing.allocator,
        \\decimal = -42
        \\positive = +42
        \\grouped = 1_000_000
        \\hex = 0xdead_beef
        \\octal = 0o755
        \\binary = 0b1101_0010
    );

    try std.testing.expectEqual(@as(i64, -42), value.decimal);
    try std.testing.expectEqual(@as(i64, 42), value.positive);
    try std.testing.expectEqual(@as(i64, 1_000_000), value.grouped);
    try std.testing.expectEqual(@as(u64, 0xdead_beef), value.hex);
    try std.testing.expectEqual(@as(u16, 0o755), value.octal);
    try std.testing.expectEqual(@as(u8, 0b1101_0010), value.binary);
}

test "toml reads all float number formats" {
    const Values = struct {
        fractional: f64,
        exponent: f64,
        signed_exponent: f64,
        grouped: f64,
        positive_inf: f64,
        negative_inf: f64,
        nan: f64,
        positive_nan: f64,
        negative_nan: f64,
    };

    const value = try readSlice(Values, std.testing.allocator,
        \\fractional = 1.5
        \\exponent = 5e+22
        \\signed_exponent = -2E-2
        \\grouped = 224_617.445_991_228
        \\positive_inf = +inf
        \\negative_inf = -inf
        \\nan = nan
        \\positive_nan = +nan
        \\negative_nan = -nan
    );

    try std.testing.expectEqual(@as(f64, 1.5), value.fractional);
    try std.testing.expectEqual(@as(f64, 5e22), value.exponent);
    try std.testing.expectEqual(@as(f64, -0.02), value.signed_exponent);
    try std.testing.expectEqual(@as(f64, 224617.445991228), value.grouped);
    try std.testing.expect(std.math.isPositiveInf(value.positive_inf));
    try std.testing.expect(std.math.isNegativeInf(value.negative_inf));
    try std.testing.expect(std.math.isNan(value.nan));
    try std.testing.expect(std.math.isNan(value.positive_nan));
    try std.testing.expect(std.math.isNan(value.negative_nan));
}

test "toml rejects invalid number formats" {
    const IntValue = struct { value: i64 };
    const FloatValue = struct { value: f64 };

    try expectReadFails(IntValue, "value = 01");
    try expectReadFails(IntValue, "value = 1_");
    try expectReadFails(IntValue, "value = 1__0");
    try expectReadFails(IntValue, "value = 0x_dead");
    try expectReadFails(IntValue, "value = +0x1");
    try expectReadFails(FloatValue, "value = 1.");
    try expectReadFails(FloatValue, "value = .5");
    try expectReadFails(FloatValue, "value = 1e");
    try expectReadFails(FloatValue, "value = 1e_2");
}

test "toml writes nested structs as table sections" {
    const Database = struct {
        host: []const u8,
        port: u16,
    };
    const Logging = struct {
        level: []const u8,
    };
    const Config = struct {
        name: []const u8,
        database: Database,
        logging: Logging,
    };

    try expectTomlWithOptions(Config{
        .name = "app",
        .database = .{ .host = "localhost", .port = 5432 },
        .logging = .{ .level = "debug" },
    }, .{ .layout = .sections },
        \\name = "app"
        \\
        \\[database]
        \\host = "localhost"
        \\port = 5432
        \\
        \\[logging]
        \\level = "debug"
    );
}

test "toml write streams arrays of structs inline" {
    const Server = struct {
        host: []const u8,
        port: u16,
    };
    const Config = struct {
        servers: []const Server,
    };
    const servers = [_]Server{
        .{ .host = "one", .port = 1 },
        .{ .host = "two", .port = 2 },
    };

    try expectToml(Config{ .servers = servers[0..] }, "servers = [{ host = \"one\", port = 1 }, { host = \"two\", port = 2 }]");
}

test "toml serializes and deserializes first-class date time values" {
    const Event = struct {
        date: LocalDate,
        time: LocalTime,
        local: LocalDateTime,
        offset: OffsetDateTime,
    };

    const event = Event{
        .date = .{ .year = 1979, .month = 5, .day = 27 },
        .time = .{ .hour = 7, .minute = 32, .second = 0, .nanosecond = 999_000_000 },
        .local = .{ .date = .{ .year = 1979, .month = 5, .day = 27 }, .time = .{ .hour = 7, .minute = 32, .second = 0 } },
        .offset = .{ .date = .{ .year = 1979, .month = 5, .day = 27 }, .time = .{ .hour = 7, .minute = 32, .second = 0 }, .offset_minutes = -7 * 60 },
    };

    try expectToml(event,
        \\date = 1979-05-27
        \\time = 07:32:00.999
        \\local = 1979-05-27T07:32:00
        \\offset = 1979-05-27T07:32:00-07:00
    );

    const parsed = try readSlice(Event, std.testing.allocator,
        \\date = 1979-05-27
        \\time = 07:32:00.999
        \\local = 1979-05-27 07:32:00
        \\offset = 1979-05-27T07:32:00Z
    );

    try std.testing.expectEqual(LocalDate{ .year = 1979, .month = 5, .day = 27 }, parsed.date);
    try std.testing.expectEqual(LocalTime{ .hour = 7, .minute = 32, .second = 0, .nanosecond = 999_000_000 }, parsed.time);
    try std.testing.expectEqual(LocalDateTime{ .date = .{ .year = 1979, .month = 5, .day = 27 }, .time = .{ .hour = 7, .minute = 32, .second = 0 } }, parsed.local);
    try std.testing.expectEqual(@as(i16, 0), parsed.offset.offset_minutes);
}

test "toml low-level decoder works with deserialize" {
    const User = struct {
        id: u8,
        name: []const u8,
    };

    var reader: std.Io.Reader = .fixed(
        \\id = 7
        \\name = "Ada"
    );
    var dec = try decoder(&reader, std.testing.allocator);
    defer dec.deinit();

    const value = try deserialize(User, std.testing.allocator, &dec);
    defer deinitValue(User, std.testing.allocator, value);
    try dec.finish();

    try std.testing.expectEqual(@as(u8, 7), value.id);
    try std.testing.expectEqualStrings("Ada", value.name);
}

test "toml field hook serializes and deserializes" {
    const BoolAsYesNo = struct {
        pub fn serialize(value: bool, enc: anytype) !void {
            try enc.emitString(if (value) "yes" else "no");
        }

        pub fn deserialize(comptime T: type, allocator: std.mem.Allocator, dec: anytype) !T {
            const value = try dec.readString(allocator);
            defer allocator.free(value);
            if (std.mem.eql(u8, value, "yes")) return true;
            if (std.mem.eql(u8, value, "no")) return false;
            return error.InvalidValue;
        }
    };

    const User = struct {
        active: bool,

        pub const zerde = .{
            .fields = .{
                .active = .{ .with = BoolAsYesNo },
            },
        };
    };

    try expectToml(User{ .active = true }, "active = \"yes\"");
    try expectRead(User, "active = \"no\"", .{ .active = false });
}

test "toml reader rejects malformed input" {
    const User = struct { id: u8 };

    try expectReadFails(User, "id 1");
    try expectReadFails(User, "id = [1,,2]");
    try expectReadFails(User, "id = \"unterminated");
    try std.testing.expectError(error.UnknownField, readSlice(struct {
        id: u8,
        pub const zerde = .{ .deny_unknown_fields = true };
    }, std.testing.allocator,
        \\id = 1
        \\extra = true
    ));
}
