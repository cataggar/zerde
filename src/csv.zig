//! CSV and delimiter-separated tabular text support.

const std = @import("std");

const base64 = @import("base64.zig");
const containers = @import("containers.zig");
const deinitValue = @import("deinit.zig").deinit;
const deserialize = @import("deserialize.zig").deserialize;
const datetime = @import("datetime.zig");
const events = @import("events.zig");
const meta = @import("meta.zig");
const number = @import("number.zig");

const CsvNumber = number.Parser(.{
    .decimal_float = true,
    .exponent = true,
    .sign = .positive_and_negative,
    .integer_to_float = true,
    .finite_float_emission = true,
});

/// Supported delimiter-separated dialects.
pub const Delimiter = enum {
    comma,
    tab,

    fn byte(self: Delimiter) u8 {
        return switch (self) {
            .comma => ',',
            .tab => '\t',
        };
    }
};

/// Record terminators emitted by the writer.
pub const RecordTerminator = enum {
    lf,
    crlf,
};

/// CSV format configuration. Use `.delimiter = .tab` for TSV.
pub const Options = struct {
    delimiter: Delimiter = .comma,
    header: bool = true,
    record_terminator: RecordTerminator = .crlf,
    final_record_terminator: bool = false,
};

/// Serializes a sequence of flat structs as CSV.
pub fn write(writer: *std.Io.Writer, value: anytype) !void {
    try writeWithOptions(writer, value, .{});
}

/// Serializes a sequence of flat structs as CSV with explicit options.
pub fn writeWithOptions(writer: *std.Io.Writer, value: anytype, options: Options) !void {
    try writeRows(@TypeOf(value), writer, value, options);
}

/// Deserializes CSV from `reader` into `T`.
pub fn read(comptime T: type, allocator: std.mem.Allocator, reader: *std.Io.Reader) !T {
    return try readWithOptions(T, allocator, reader, .{});
}

/// Deserializes CSV from `reader` into `T` with explicit options.
pub fn readWithOptions(comptime T: type, allocator: std.mem.Allocator, reader: *std.Io.Reader, options: Options) !T {
    comptime validateRoot(T);

    const records = try readRecords(reader, allocator, options);
    defer deinitRecords(allocator, records);

    return try readRows(T, allocator, records, options);
}

/// Serializes `value` as CSV and returns allocator-owned bytes.
pub fn writeAlloc(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    return try writeAllocWithOptions(allocator, value, .{});
}

/// Serializes `value` as CSV with explicit options and returns allocator-owned bytes.
pub fn writeAllocWithOptions(allocator: std.mem.Allocator, value: anytype, options: Options) ![]u8 {
    var allocating = std.Io.Writer.Allocating.init(allocator);
    errdefer allocating.deinit();

    try writeWithOptions(&allocating.writer, value, options);
    return try allocating.toOwnedSlice();
}

/// Deserializes CSV from `input` into `T`.
pub fn readSlice(comptime T: type, allocator: std.mem.Allocator, input: []const u8) !T {
    return try readSliceWithOptions(T, allocator, input, .{});
}

/// Deserializes CSV from `input` into `T` with explicit options.
pub fn readSliceWithOptions(comptime T: type, allocator: std.mem.Allocator, input: []const u8, options: Options) !T {
    var reader: std.Io.Reader = .fixed(input);
    return try readWithOptions(T, allocator, &reader, options);
}

/// Returns a low-level CSV encoder for use with `zerde.serialize`.
pub fn encoder(writer: *std.Io.Writer) Encoder {
    return encoderWithOptions(writer, .{});
}

/// Returns a low-level CSV encoder with explicit options.
pub fn encoderWithOptions(writer: *std.Io.Writer, options: Options) Encoder {
    return .{ .writer = writer, .options = options };
}

/// Returns a low-level CSV decoder for use with `zerde.deserialize`.
/// Call `Decoder.deinit` when done.
pub fn decoder(reader: *std.Io.Reader, allocator: std.mem.Allocator, options: Options) !Decoder {
    const records = try readRecords(reader, allocator, options);
    errdefer deinitRecords(allocator, records);

    return .{ .allocator = allocator, .options = options, .records = records };
}

/// CSV value kinds reported by `Decoder.peek`.
pub const Kind = enum {
    null,
    bool,
    int,
    float,
    string,
    seq,
    struct_,
};

/// Low-level CSV encoder used by the generic serializer.
///
/// This can also receive `zerde.events.Value.write` output when the event value
/// is a sequence of row structs. For event writes, the first row defines the
/// fixed schema, nested structs are flattened with dot-separated headers,
/// missing later fields become empty cells, and extra later fields are rejected.
pub const Encoder = struct {
    const Self = @This();
    const max_depth = 64;

    const Frame = struct {
        entries: []const FieldEntry,
        is_row: bool,
    };

    writer: *std.Io.Writer,
    options: Options,
    stack: [max_depth]Frame = undefined,
    stack_len: usize = 0,
    root_started: bool = false,
    seq_done: bool = false,
    row_count: usize = 0,
    row_field_index: usize = 0,
    expecting_cell: bool = false,
    header_written: bool = false,
    pending_path: []const u8 = "",
    pending_leaf_count: usize = 0,
    pending_nested_entries: []const FieldEntry = &.{},

    pub fn emitNull(self: *Self) !void {
        const count = try self.beforeNullCell();
        try writeEmptyCells(count, self.writer, self.options, &self.row_field_index);
    }

    pub fn emitBool(self: *Self, value: bool) !void {
        try self.beforeCell();
        try self.writer.writeAll(if (value) "true" else "false");
    }

    pub fn emitInt(self: *Self, value: anytype) !void {
        try self.beforeCell();
        try self.writer.print("{d}", .{value});
    }

    pub fn emitFloat(self: *Self, value: anytype) !void {
        try CsvNumber.emitFloat(value);
        try self.beforeCell();
        try self.writer.print("{d}", .{value});
    }

    pub fn emitString(self: *Self, value: []const u8) !void {
        if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidUtf8;
        try self.beforeCell();
        try writeEscapedCell(self.writer, value, self.options.delimiter.byte());
    }

    pub fn emitBytes(self: *Self, value: []const u8) !void {
        try self.beforeCell();
        try base64.writeEncoded(self.writer, value);
    }

    pub fn emitEnumTag(self: *Self, tag: []const u8) !void {
        try self.emitString(tag);
    }

    /// Writes a buffered structural event value as CSV.
    ///
    /// The value must be a sequence of row structs, and the first row defines
    /// the fixed schema.
    pub fn emitEventValue(self: *Self, value: events.Value) !void {
        if (self.root_started or self.stack_len != 0 or self.seq_done) return error.InvalidCsvEncoderState;
        self.root_started = true;

        const rows = switch (value) {
            .seq => |rows| rows,
            else => return error.InvalidCsvEventShape,
        };

        if (rows.len == 0) {
            self.seq_done = true;
            return;
        }

        const schema = switch (rows[0]) {
            .struct_ => |fields| fields,
            else => return error.InvalidCsvEventShape,
        };
        try validateEventSchema(schema);

        var wrote_record = false;
        if (self.options.header) {
            var header_index: usize = 0;
            var path_parts: [max_depth][]const u8 = undefined;
            try writeEventHeaderFields(schema, &path_parts, 0, self.writer, self.options, &header_index);
            self.header_written = true;
            wrote_record = true;
        }

        for (rows) |row| {
            const fields = switch (row) {
                .struct_ => |fields| fields,
                else => return error.InvalidCsvEventShape,
            };

            if (wrote_record) try writeRecordTerminator(self.writer, self.options.record_terminator);
            var field_index: usize = 0;
            try writeEventRowFields(schema, fields, self.writer, self.options, &field_index);
            self.row_count += 1;
            wrote_record = true;
        }

        if (self.options.final_record_terminator and (self.header_written or self.row_count != 0)) {
            try writeRecordTerminator(self.writer, self.options.record_terminator);
        }
        self.seq_done = true;
    }

    pub fn beginArray(self: *Self, comptime T: type, len: usize) !void {
        _ = len;
        try self.beginTypedSeq(arrayChild(T));
    }

    pub fn beginSlice(self: *Self, comptime Child: type, len: usize) !void {
        _ = len;
        try self.beginTypedSeq(Child);
    }

    pub fn beginSeq(self: *Self, len: ?usize) !void {
        _ = len;
        if (self.root_started) return error.InvalidCsvEncoderState;
        self.root_started = true;
    }

    pub fn hasNextSeqElem(self: *Self) !bool {
        _ = self;
        return error.UnsupportedCsvOperation;
    }

    pub fn endSeq(self: *Self) !void {
        if (!self.root_started or self.in_row() or self.seq_done) return error.InvalidCsvEncoderState;
        if (self.options.final_record_terminator and (self.header_written or self.row_count != 0)) {
            try writeRecordTerminator(self.writer, self.options.record_terminator);
        }
        self.seq_done = true;
    }

    pub fn beginStruct(self: *Self, comptime T: type, field_count: usize) !void {
        _ = field_count;
        comptime validateRow(T);

        if (self.expecting_cell) {
            if (self.pending_nested_entries.len == 0) return error.InvalidCsvEncoderState;
            try self.push(.{ .entries = self.pending_nested_entries, .is_row = false });
            self.expecting_cell = false;
            self.pending_path = "";
            self.pending_leaf_count = 0;
            self.pending_nested_entries = &.{};
            return;
        }

        if (!self.root_started or self.stack_len != 0 or self.seq_done) return error.InvalidCsvEncoderState;
        if (self.options.header and !self.header_written) {
            try writeHeader(T, self.writer, self.options);
            self.header_written = true;
        }
        if (self.header_written or self.row_count != 0) try writeRecordTerminator(self.writer, self.options.record_terminator);

        try self.push(.{ .entries = directFieldEntries(T), .is_row = true });
        self.row_field_index = 0;
        self.expecting_cell = false;
    }

    pub fn emitFieldName(self: *Self, name: []const u8) !void {
        if (!self.in_row() or self.expecting_cell) return error.InvalidCsvEncoderState;
        const entry = findFieldEntry(self.currentFrame().entries, name) orelse return error.InvalidCsvEncoderState;
        self.pending_path = entry.path;
        self.pending_leaf_count = entry.leaf_count;
        self.pending_nested_entries = entry.nested_entries;
        self.expecting_cell = true;
    }

    pub fn endStruct(self: *Self) !void {
        if (self.stack_len == 0 or self.expecting_cell) return error.InvalidCsvEncoderState;
        const frame = self.pop();
        if (frame.is_row) self.row_count += 1;
    }

    pub fn finish(self: *Self) !void {
        if (!self.root_started or !self.seq_done or self.stack_len != 0) return error.IncompleteCsvDocument;
    }

    pub fn beginOptional(self: *Self, present: bool) !void {
        if (!present) try self.emitNull();
    }

    fn beginTypedSeq(self: *Self, comptime Row: type) !void {
        comptime validateRow(Row);
        try self.beginSeq(null);
        if (self.options.header) {
            try writeHeader(Row, self.writer, self.options);
            self.header_written = true;
        }
    }

    fn beforeCell(self: *Self) !void {
        if (!self.in_row() or !self.expecting_cell) return error.InvalidCsvEncoderState;
        if (self.pending_leaf_count != 1 or self.pending_nested_entries.len != 0) return error.InvalidCsvEncoderState;
        if (self.row_field_index != 0) try self.writer.writeByte(self.options.delimiter.byte());
        self.row_field_index += 1;
        self.expecting_cell = false;
        self.pending_path = "";
        self.pending_leaf_count = 0;
        self.pending_nested_entries = &.{};
    }

    fn beforeNullCell(self: *Self) !usize {
        if (!self.in_row() or !self.expecting_cell) return error.InvalidCsvEncoderState;
        const count = self.pending_leaf_count;
        self.expecting_cell = false;
        self.pending_path = "";
        self.pending_leaf_count = 0;
        self.pending_nested_entries = &.{};
        return count;
    }

    fn in_row(self: Self) bool {
        return self.stack_len != 0;
    }

    fn push(self: *Self, frame: Frame) !void {
        if (self.stack_len == self.stack.len) return error.NestingTooDeep;
        self.stack[self.stack_len] = frame;
        self.stack_len += 1;
    }

    fn pop(self: *Self) Frame {
        std.debug.assert(self.stack_len != 0);
        self.stack_len -= 1;
        return self.stack[self.stack_len];
    }

    fn currentFrame(self: *Self) Frame {
        std.debug.assert(self.stack_len != 0);
        return self.stack[self.stack_len - 1];
    }
};

/// Low-level CSV decoder used by the generic deserializer.
pub const Decoder = struct {
    const Self = @This();
    const max_depth = 64;

    const Frame = struct {
        entries: []const FieldEntry,
        index: usize = 0,
        is_row: bool,
        dynamic: bool = false,
    };

    allocator: std.mem.Allocator,
    options: Options,
    records: []Record,
    stack: [max_depth]Frame = undefined,
    stack_len: usize = 0,
    in_seq: bool = false,
    seq_done: bool = false,
    row_index: usize = 0,
    current_record_index: ?usize = null,
    current_cell: ?[]const u8 = null,
    pending_nested_entries: []const FieldEntry = &.{},
    pending_path: []const u8 = "",
    current_lookup_names: []const []const u8 = &.{},

    pub fn deinit(self: *Self) void {
        deinitRecords(self.allocator, self.records);
        self.* = undefined;
    }

    pub fn peek(self: *Self) !Kind {
        const cell = self.current_cell orelse {
            if (!self.in_seq and !self.seq_done and self.current_record_index == null) return .seq;
            if (self.in_seq and self.current_record_index == null and self.row_index < self.dataRecordCount()) return .struct_;
            return error.InvalidCsvDecoderState;
        };
        if (cell.len == 0) return .null;
        if (self.inDynamicRow()) return .string;
        if (std.mem.eql(u8, cell, "true") or std.mem.eql(u8, cell, "false")) return .bool;
        if (std.mem.indexOfAny(u8, cell, ".eE") != null) return .float;
        return .string;
    }

    pub fn readNull(self: *Self) !void {
        const cell = try self.takeCell();
        if (cell.len != 0) return error.InvalidType;
    }

    pub fn readBool(self: *Self) !bool {
        const cell = try self.takeCell();
        if (std.mem.eql(u8, cell, "true")) return true;
        if (std.mem.eql(u8, cell, "false")) return false;
        return error.InvalidType;
    }

    pub fn readInt(self: *Self, comptime T: type) !T {
        const cell = try self.takeCell();
        const token = try CsvNumber.parseAlloc(self.allocator, cell);
        defer token.deinit(self.allocator);

        return switch (token) {
            .int => |integer| try CsvNumber.readInt(T, integer),
            .float => error.InvalidType,
        };
    }

    pub fn readFloat(self: *Self, comptime T: type) !T {
        const cell = try self.takeCell();
        const token = try CsvNumber.parseAlloc(self.allocator, cell);
        defer token.deinit(self.allocator);
        return try CsvNumber.readFloat(T, token);
    }

    pub fn readString(self: *Self, allocator: std.mem.Allocator) ![]u8 {
        const cell = try self.takeCell();
        if (!std.unicode.utf8ValidateSlice(cell)) return error.InvalidUtf8;
        return try allocator.dupe(u8, cell);
    }

    pub fn readBytes(self: *Self, allocator: std.mem.Allocator) ![]u8 {
        const cell = try self.takeCell();
        return try base64.decodeAlloc(allocator, cell);
    }

    pub fn readOptionalPresent(self: *Self) !bool {
        if (self.pending_nested_entries.len != 0) {
            const record_index = self.current_record_index orelse return error.InvalidCsvDecoderState;
            if (entriesCellsEmpty(self.pending_nested_entries, self.records[record_index], self.lookup())) {
                self.pending_nested_entries = &.{};
                self.pending_path = "";
                return false;
            }
            return true;
        }

        const cell = self.current_cell orelse return error.InvalidCsvDecoderState;
        if (cell.len == 0) {
            self.current_cell = null;
            return false;
        }
        return true;
    }

    pub fn beginSeq(self: *Self) !?usize {
        if (self.in_seq or self.seq_done) return error.InvalidCsvDecoderState;
        self.in_seq = true;
        return self.dataRecordCount();
    }

    pub fn hasNextSeqElem(self: *Self) !bool {
        if (!self.in_seq or self.current_record_index != null) return error.InvalidCsvDecoderState;
        return self.row_index < self.dataRecordCount();
    }

    pub fn endSeq(self: *Self) !void {
        if (!self.in_seq or self.current_record_index != null) return error.InvalidCsvDecoderState;
        self.in_seq = false;
        self.seq_done = true;
    }

    pub fn beginStruct(self: *Self, comptime T: type) !void {
        comptime validateRow(T);
        if (self.pending_nested_entries.len != 0) {
            try self.push(.{ .entries = self.pending_nested_entries, .is_row = false });
            self.pending_nested_entries = &.{};
            return;
        }

        if (!self.in_seq or self.current_record_index != null) return error.InvalidCsvDecoderState;

        const record_index = self.dataStart() + self.row_index;
        if (record_index >= self.records.len) return error.InvalidCsvDecoderState;

        const record = self.records[record_index];
        const expected_len = if (self.options.header) self.records[0].cells.len else csvFieldCount(T);
        if (record.cells.len != expected_len) return error.InvalidCsvRecordLength;

        self.current_record_index = record_index;
        self.current_cell = null;
        self.current_lookup_names = if (self.options.header) &.{} else fieldNames(T);
        try self.push(.{ .entries = directFieldEntries(T), .is_row = true });
        if (self.options.header) try validateHeader(T, self.records[0]);
    }

    pub fn beginStructEvent(self: *Self) !?usize {
        if (!self.in_seq or self.current_record_index != null) return error.InvalidCsvDecoderState;

        const record_index = self.dataStart() + self.row_index;
        if (record_index >= self.records.len) return error.InvalidCsvDecoderState;

        const record = self.records[record_index];
        const field_count = if (self.options.header) self.records[0].cells.len else record.cells.len;
        self.current_record_index = record_index;
        self.current_cell = null;
        self.current_lookup_names = &.{};
        try self.push(.{ .entries = &.{}, .is_row = true, .dynamic = true });
        return field_count;
    }

    pub fn nextField(self: *Self) !?[]u8 {
        const record_index = self.current_record_index orelse return error.InvalidCsvDecoderState;
        if (self.current_cell != null) return error.InvalidCsvDecoderState;
        if (self.stack_len == 0) return error.InvalidCsvDecoderState;

        const frame = &self.stack[self.stack_len - 1];
        if (frame.dynamic) {
            const record = self.records[record_index];
            const field_count = if (self.options.header) self.records[0].cells.len else record.cells.len;
            if (frame.index == field_count) return null;

            const column = frame.index;
            frame.index += 1;
            self.current_cell = record.cells[column];
            if (self.options.header) return try self.allocator.dupe(u8, self.records[0].cells[column]);
            return try std.fmt.allocPrint(self.allocator, "{d}", .{column});
        }

        const columns = self.lookup();
        while (frame.index < frame.entries.len) {
            const entry = frame.entries[frame.index];
            frame.index += 1;

            if (entry.nested_entries.len != 0) {
                if (hasColumnWithPrefix(columns, entry.path)) {
                    self.pending_nested_entries = entry.nested_entries;
                    self.pending_path = entry.path;
                    return try self.allocator.dupe(u8, entry.name);
                }
            } else if (findColumn(columns, entry.path)) |column| {
                self.current_cell = self.records[record_index].cells[column];
                return try self.allocator.dupe(u8, entry.name);
            }
        }

        return null;
    }

    pub fn endStruct(self: *Self) !void {
        const record_index = self.current_record_index orelse return error.InvalidCsvDecoderState;
        _ = record_index;
        if (self.current_cell != null or self.stack_len == 0) return error.InvalidCsvDecoderState;

        const frame = self.pop();
        if (frame.is_row) {
            self.current_record_index = null;
            self.current_lookup_names = &.{};
            self.row_index += 1;
        }
    }

    pub fn skipValue(self: *Self) !void {
        if (self.pending_nested_entries.len != 0) {
            self.pending_nested_entries = &.{};
            self.pending_path = "";
            return;
        }
        _ = try self.takeCell();
    }

    pub fn finish(self: *Self) !void {
        if (!self.seq_done or self.in_seq or self.current_record_index != null or self.current_cell != null) return error.IncompleteCsvDocument;
        if (self.row_index != self.dataRecordCount()) return error.IncompleteCsvDocument;
    }

    fn takeCell(self: *Self) ![]const u8 {
        const cell = self.current_cell orelse return error.InvalidCsvDecoderState;
        self.current_cell = null;
        return cell;
    }

    fn dataStart(self: Self) usize {
        return if (self.options.header) 1 else 0;
    }

    fn dataRecordCount(self: Self) usize {
        return self.records.len - self.dataStart();
    }

    fn lookup(self: *Self) ColumnLookup {
        return if (self.options.header)
            .{ .header = self.records[0] }
        else
            .{ .generated = self.current_lookup_names };
    }

    fn inDynamicRow(self: *Self) bool {
        if (self.stack_len == 0) return false;
        return self.stack[self.stack_len - 1].dynamic;
    }

    fn push(self: *Self, frame: Frame) !void {
        if (self.stack_len == self.stack.len) return error.NestingTooDeep;
        self.stack[self.stack_len] = frame;
        self.stack_len += 1;
    }

    fn pop(self: *Self) Frame {
        std.debug.assert(self.stack_len != 0);
        self.stack_len -= 1;
        return self.stack[self.stack_len];
    }
};

const Record = struct {
    cells: [][]u8,

    fn deinit(self: Record, allocator: std.mem.Allocator) void {
        for (self.cells) |cell| allocator.free(cell);
        allocator.free(self.cells);
    }
};

fn writeRows(comptime T: type, writer: *std.Io.Writer, value: T, options: Options) !void {
    comptime validateRoot(T);
    const Row = rowType(T);

    var wrote_record = false;
    if (options.header) {
        try writeHeader(Row, writer, options);
        wrote_record = true;
    }

    switch (@typeInfo(T)) {
        .array => {
            for (value) |row| {
                if (wrote_record) try writeRecordTerminator(writer, options.record_terminator);
                try writeRow(Row, writer, row, options);
                wrote_record = true;
            }
        },
        .pointer => |pointer_info| switch (pointer_info.size) {
            .slice => {
                for (value) |row| {
                    if (wrote_record) try writeRecordTerminator(writer, options.record_terminator);
                    try writeRow(Row, writer, row, options);
                    wrote_record = true;
                }
            },
            .one => switch (@typeInfo(pointer_info.child)) {
                .array => {
                    for (value) |row| {
                        if (wrote_record) try writeRecordTerminator(writer, options.record_terminator);
                        try writeRow(Row, writer, row, options);
                        wrote_record = true;
                    }
                },
                else => unreachable,
            },
            else => unreachable,
        },
        .@"struct" => {
            const len = containers.listLen(T, value);
            for (0..len) |i| {
                if (wrote_record) try writeRecordTerminator(writer, options.record_terminator);
                try writeRow(Row, writer, containers.listItem(T, value, i), options);
                wrote_record = true;
            }
        },
        else => unreachable,
    }

    if (options.final_record_terminator and wrote_record) try writeRecordTerminator(writer, options.record_terminator);
}

fn writeHeader(comptime Row: type, writer: *std.Io.Writer, options: Options) !void {
    var index: usize = 0;
    try writeHeaderFields(Row, "", writer, options, &index);
}

fn writeHeaderFields(comptime Row: type, comptime prefix: []const u8, writer: *std.Io.Writer, options: Options, index: *usize) !void {
    const row_info = @typeInfo(Row).@"struct";
    const row_options = comptime meta.optionsFor(Row);

    inline for (row_info.fields) |field| {
        if (!field.is_comptime) {
            const field_options = comptime meta.fieldOptionsFor(Row, field.name);
            if (comptime !meta.shouldSerialize(field_options)) continue;

            const wire_name = comptime meta.fieldWireName(field.name, field_options, row_options);
            const path = comptime joinPath(prefix, wire_name);
            if (comptime flattenedStructType(field.type, field_options)) |Nested| {
                try writeHeaderFields(Nested, path, writer, options, index);
            } else {
                if (index.* != 0) try writer.writeByte(options.delimiter.byte());
                try writeEscapedCell(writer, path, options.delimiter.byte());
                index.* += 1;
            }
        }
    }
}

fn writeRow(comptime Row: type, writer: *std.Io.Writer, row: Row, options: Options) !void {
    var index: usize = 0;
    try writeRowFields(Row, writer, row, options, &index);
}

fn writeRowFields(comptime Row: type, writer: *std.Io.Writer, row: Row, options: Options, index: *usize) !void {
    const row_info = @typeInfo(Row).@"struct";

    inline for (row_info.fields) |field| {
        if (!field.is_comptime) {
            const field_options = comptime meta.fieldOptionsFor(Row, field.name);
            if (comptime !meta.shouldSerialize(field_options)) continue;

            if (comptime flattenedStructType(field.type, field_options)) |Nested| {
                const value = @field(row, field.name);
                if (comptime isOptional(field.type)) {
                    if (value) |nested_value| {
                        try writeRowFields(Nested, writer, nested_value, options, index);
                    } else {
                        try writeEmptyCells(csvFieldCount(Nested), writer, options, index);
                    }
                } else {
                    try writeRowFields(Nested, writer, value, options, index);
                }
            } else {
                if (index.* != 0) try writer.writeByte(options.delimiter.byte());
                try writeCellValue(field.type, writer, @field(row, field.name), field_options, options.delimiter.byte());
                index.* += 1;
            }
        }
    }
}

fn writeEmptyCells(count: usize, writer: *std.Io.Writer, options: Options, index: *usize) !void {
    for (0..count) |_| {
        if (index.* != 0) try writer.writeByte(options.delimiter.byte());
        index.* += 1;
    }
}

fn writeCellValue(comptime T: type, writer: *std.Io.Writer, value: T, comptime field_options: meta.FieldOptions, delimiter: u8) !void {
    if (comptime field_options.bytes) {
        try writeBytesCell(T, writer, value);
        return;
    }
    if (comptime T == base64.Bytes) {
        try base64.writeEncoded(writer, value.value);
        return;
    }

    switch (@typeInfo(T)) {
        .bool => try writer.writeAll(if (value) "true" else "false"),
        .int => try writer.print("{d}", .{value}),
        .float => {
            try CsvNumber.emitFloat(value);
            try writer.print("{d}", .{value});
        },
        .optional => |optional_info| {
            if (value) |child_value| {
                try writeCellValue(optional_info.child, writer, child_value, .{}, delimiter);
            }
        },
        .@"enum" => try writeEscapedCell(writer, @tagName(value), delimiter),
        .pointer => |pointer_info| switch (pointer_info.size) {
            .slice => {
                if (pointer_info.child != u8) unsupportedScalar(T);
                if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidUtf8;
                try writeEscapedCell(writer, value, delimiter);
            },
            .one => switch (@typeInfo(pointer_info.child)) {
                .array => |array_info| {
                    if (array_info.child != u8 or
                        (array_info.sentinel() != null and array_info.sentinel() != 0) or
                        (pointer_info.sentinel() != null and pointer_info.sentinel() != 0)) unsupportedScalar(T);
                    const bytes = value[0..array_info.len];
                    if (!std.unicode.utf8ValidateSlice(bytes)) return error.InvalidUtf8;
                    try writeEscapedCell(writer, bytes, delimiter);
                },
                else => unsupportedScalar(T),
            },
            else => unsupportedScalar(T),
        },
        else => unsupportedScalar(T),
    }
}

fn writeBytesCell(comptime T: type, writer: *std.Io.Writer, value: T) !void {
    if (T == base64.Bytes) {
        try base64.writeEncoded(writer, value.value);
        return;
    }

    switch (@typeInfo(T)) {
        .array => |array_info| {
            if (array_info.child != u8) unsupportedScalar(T);
            try base64.writeEncoded(writer, value[0..]);
        },
        .pointer => |pointer_info| switch (pointer_info.size) {
            .slice => {
                if (pointer_info.child != u8) unsupportedScalar(T);
                try base64.writeEncoded(writer, value);
            },
            else => unsupportedScalar(T),
        },
        else => unsupportedScalar(T),
    }
}

fn writeEscapedCell(writer: *std.Io.Writer, value: []const u8, delimiter: u8) !void {
    const specials = [_]u8{ delimiter, '"', '\r', '\n' };
    const must_quote = std.mem.indexOfAny(u8, value, &specials) != null;
    if (!must_quote) {
        try writer.writeAll(value);
        return;
    }

    try writer.writeByte('"');
    for (value) |byte| {
        if (byte == '"') try writer.writeByte('"');
        try writer.writeByte(byte);
    }
    try writer.writeByte('"');
}

fn validateEventSchema(schema: []const events.ObjectField) !void {
    for (schema, 0..) |field, i| {
        if (!std.unicode.utf8ValidateSlice(field.name)) return error.InvalidUtf8;
        for (schema[0..i]) |previous| {
            if (std.mem.eql(u8, field.name, previous.name)) return error.DuplicateField;
        }
        switch (field.value) {
            .struct_ => |nested| try validateEventSchema(nested),
            else => {},
        }
    }
}

fn writeEventHeaderFields(schema: []const events.ObjectField, path_parts: *[Encoder.max_depth][]const u8, path_len: usize, writer: *std.Io.Writer, options: Options, index: *usize) !void {
    if (path_len == path_parts.len) return error.NestingTooDeep;

    for (schema) |field| {
        path_parts[path_len] = field.name;
        switch (field.value) {
            .struct_ => |nested| try writeEventHeaderFields(nested, path_parts, path_len + 1, writer, options, index),
            else => {
                if (index.* != 0) try writer.writeByte(options.delimiter.byte());
                try writeEscapedPathCell(writer, path_parts[0 .. path_len + 1], options.delimiter.byte());
                index.* += 1;
            },
        }
    }
}

fn writeEventRowFields(schema: []const events.ObjectField, fields: []const events.ObjectField, writer: *std.Io.Writer, options: Options, index: *usize) !void {
    for (schema) |schema_field| {
        const row_field = findEventField(fields, schema_field.name);
        switch (schema_field.value) {
            .struct_ => |nested_schema| {
                if (row_field) |field| {
                    switch (field.value) {
                        .null => try writeEmptyCells(countEventLeaves(nested_schema), writer, options, index),
                        .struct_ => |nested_fields| try writeEventRowFields(nested_schema, nested_fields, writer, options, index),
                        else => return error.InvalidCsvEventShape,
                    }
                } else {
                    try writeEmptyCells(countEventLeaves(nested_schema), writer, options, index);
                }
            },
            else => {
                if (index.* != 0) try writer.writeByte(options.delimiter.byte());
                if (row_field) |field| try writeEventCellValue(field.value, writer, options.delimiter.byte());
                index.* += 1;
            },
        }
    }

    for (fields) |field| {
        if (findEventField(schema, field.name) == null) return error.UnknownField;
    }
}

fn writeEventCellValue(value: events.Value, writer: *std.Io.Writer, delimiter: u8) !void {
    switch (value) {
        .null => {},
        .bool => |cell| try writer.writeAll(if (cell) "true" else "false"),
        .int => |cell| try writer.print("{d}", .{cell}),
        .float => |cell| {
            try CsvNumber.emitFloat(cell);
            try writer.print("{d}", .{cell});
        },
        .string, .enum_tag, .datetime => |cell| {
            if (!std.unicode.utf8ValidateSlice(cell)) return error.InvalidUtf8;
            try writeEscapedCell(writer, cell, delimiter);
        },
        .bytes => |cell| try base64.writeEncoded(writer, cell),
        .extension, .seq, .struct_ => return error.InvalidCsvEventShape,
    }
}

fn writeEscapedPathCell(writer: *std.Io.Writer, parts: []const []const u8, delimiter: u8) !void {
    const specials = [_]u8{ delimiter, '"', '\r', '\n' };
    var must_quote = false;
    for (parts) |part| {
        if (std.mem.indexOfAny(u8, part, &specials) != null) {
            must_quote = true;
            break;
        }
    }

    if (!must_quote) {
        for (parts, 0..) |part, i| {
            if (i != 0) try writer.writeByte('.');
            try writer.writeAll(part);
        }
        return;
    }

    try writer.writeByte('"');
    for (parts, 0..) |part, i| {
        if (i != 0) try writer.writeByte('.');
        for (part) |byte| {
            if (byte == '"') try writer.writeByte('"');
            try writer.writeByte(byte);
        }
    }
    try writer.writeByte('"');
}

fn findEventField(fields: []const events.ObjectField, name: []const u8) ?events.ObjectField {
    for (fields) |field| {
        if (std.mem.eql(u8, field.name, name)) return field;
    }
    return null;
}

fn countEventLeaves(schema: []const events.ObjectField) usize {
    var count: usize = 0;
    for (schema) |field| {
        count += switch (field.value) {
            .struct_ => |nested| countEventLeaves(nested),
            else => 1,
        };
    }
    return count;
}

fn writeRecordTerminator(writer: *std.Io.Writer, terminator: RecordTerminator) !void {
    switch (terminator) {
        .lf => try writer.writeByte('\n'),
        .crlf => try writer.writeAll("\r\n"),
    }
}

fn readRecords(reader: *std.Io.Reader, allocator: std.mem.Allocator, options: Options) ![]Record {
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
    defer allocator.free(bytes);

    const records = try parseRecords(allocator, bytes, options.delimiter.byte());
    errdefer deinitRecords(allocator, records);

    if (options.header and records.len == 0) return error.MissingCsvHeader;
    if (options.header) try validateRecordLengths(records);
    return records;
}

fn parseRecords(allocator: std.mem.Allocator, input: []const u8, delimiter: u8) ![]Record {
    var records: std.ArrayList(Record) = .empty;
    errdefer {
        for (records.items) |record| record.deinit(allocator);
        records.deinit(allocator);
    }

    var index: usize = 0;
    while (index < input.len) {
        const record = try parseRecord(allocator, input, &index, delimiter);
        records.append(allocator, record) catch |err| {
            record.deinit(allocator);
            return err;
        };
    }

    return try records.toOwnedSlice(allocator);
}

fn parseRecord(allocator: std.mem.Allocator, input: []const u8, index: *usize, delimiter: u8) !Record {
    var cells: std.ArrayList([]u8) = .empty;
    errdefer {
        for (cells.items) |cell| allocator.free(cell);
        cells.deinit(allocator);
    }

    while (true) {
        const cell = try parseCell(allocator, input, index, delimiter);
        cells.append(allocator, cell) catch |err| {
            allocator.free(cell);
            return err;
        };

        if (index.* >= input.len) break;
        if (input[index.*] == delimiter) {
            index.* += 1;
        } else switch (input[index.*]) {
            '\n' => {
                index.* += 1;
                break;
            },
            '\r' => {
                index.* += 1;
                if (index.* >= input.len or input[index.*] != '\n') return error.InvalidCsvSyntax;
                index.* += 1;
                break;
            },
            else => return error.InvalidCsvSyntax,
        }
    }

    return .{ .cells = try cells.toOwnedSlice(allocator) };
}

fn parseCell(allocator: std.mem.Allocator, input: []const u8, index: *usize, delimiter: u8) ![]u8 {
    var out = std.Io.Writer.Allocating.init(allocator);
    errdefer out.deinit();

    if (index.* < input.len and input[index.*] == '"') {
        index.* += 1;
        while (index.* < input.len) {
            const byte = input[index.*];
            index.* += 1;
            if (byte == '"') {
                if (index.* < input.len and input[index.*] == '"') {
                    index.* += 1;
                    try out.writer.writeByte('"');
                    continue;
                }
                if (index.* < input.len and input[index.*] != delimiter and input[index.*] != '\r' and input[index.*] != '\n') {
                    return error.InvalidCsvSyntax;
                }
                return try out.toOwnedSlice();
            }
            try out.writer.writeByte(byte);
        }
        return error.InvalidCsvSyntax;
    }

    while (index.* < input.len) {
        const byte = input[index.*];
        if (byte == delimiter or byte == '\r' or byte == '\n') break;
        if (byte == '"') return error.InvalidCsvSyntax;
        try out.writer.writeByte(byte);
        index.* += 1;
    }

    return try out.toOwnedSlice();
}

fn validateRecordLengths(records: []const Record) !void {
    if (records.len == 0) return;
    const width = records[0].cells.len;
    for (records[1..]) |record| {
        if (record.cells.len != width) return error.InvalidCsvRecordLength;
    }
}

fn deinitRecords(allocator: std.mem.Allocator, records: []Record) void {
    for (records) |record| record.deinit(allocator);
    allocator.free(records);
}

const ColumnLookup = union(enum) {
    header: Record,
    generated: []const []const u8,

    fn len(self: ColumnLookup) usize {
        return switch (self) {
            .header => |record| record.cells.len,
            .generated => |names| names.len,
        };
    }

    fn name(self: ColumnLookup, index: usize) []const u8 {
        return switch (self) {
            .header => |record| record.cells[index],
            .generated => |names| names[index],
        };
    }
};

const FieldEntry = struct {
    name: []const u8,
    path: []const u8,
    leaf_count: usize,
    nested_entries: []const FieldEntry = &.{},
};

fn directFieldEntries(comptime Row: type) []const FieldEntry {
    const Holder = struct {
        const entries = buildDirectFieldEntries(Row, "");
    };
    return &Holder.entries;
}

fn directFieldEntriesWithPrefix(comptime Row: type, comptime prefix: []const u8) []const FieldEntry {
    const Holder = struct {
        const entries = buildDirectFieldEntries(Row, prefix);
    };
    return &Holder.entries;
}

fn buildDirectFieldEntries(comptime Row: type, comptime prefix: []const u8) [directFieldCount(Row)]FieldEntry {
    const row_info = @typeInfo(Row).@"struct";
    const row_options = comptime meta.optionsFor(Row);
    var entries: [directFieldCount(Row)]FieldEntry = undefined;
    var out: usize = 0;

    inline for (row_info.fields) |field| {
        if (!field.is_comptime) {
            const field_options = comptime meta.fieldOptionsFor(Row, field.name);
            if (comptime !meta.shouldSerialize(field_options)) continue;

            const wire_name = comptime meta.fieldWireName(field.name, field_options, row_options);
            const path = comptime joinPath(prefix, wire_name);
            if (comptime flattenedStructType(field.type, field_options)) |Nested| {
                entries[out] = .{
                    .name = wire_name,
                    .path = path,
                    .leaf_count = csvFieldCount(Nested),
                    .nested_entries = directFieldEntriesWithPrefix(Nested, path),
                };
            } else {
                entries[out] = .{ .name = wire_name, .path = path, .leaf_count = 1 };
            }
            out += 1;
        }
    }

    return entries;
}

fn directFieldCount(comptime Row: type) usize {
    const row_info = @typeInfo(Row).@"struct";
    comptime var count: usize = 0;
    inline for (row_info.fields) |field| {
        if (!field.is_comptime) {
            const field_options = comptime meta.fieldOptionsFor(Row, field.name);
            if (comptime meta.shouldSerialize(field_options)) count += 1;
        }
    }
    return count;
}

fn findFieldEntry(entries: []const FieldEntry, name: []const u8) ?FieldEntry {
    for (entries) |entry| {
        if (std.mem.eql(u8, entry.name, name)) return entry;
    }
    return null;
}

fn entriesCellsEmpty(entries: []const FieldEntry, record: Record, lookup: ColumnLookup) bool {
    for (entries) |entry| {
        if (entry.nested_entries.len != 0) {
            if (!entriesCellsEmpty(entry.nested_entries, record, lookup)) return false;
        } else if (findColumn(lookup, entry.path)) |column| {
            if (record.cells[column].len != 0) return false;
        }
    }
    return true;
}

fn readRows(comptime T: type, allocator: std.mem.Allocator, records: []const Record, options: Options) !T {
    const Row = comptime rowType(T);
    const data_start: usize = if (options.header) 1 else 0;
    const data_count = records.len - data_start;
    const lookup: ColumnLookup = if (options.header) blk: {
        try validateHeader(Row, records[0]);
        break :blk .{ .header = records[0] };
    } else .{ .generated = fieldNames(Row) };

    for (records[data_start..]) |record| {
        if (record.cells.len != lookup.len()) return error.InvalidCsvRecordLength;
    }

    switch (@typeInfo(T)) {
        .array => |array_info| {
            if (data_count != array_info.len) return error.InvalidArrayLength;
            var result: T = undefined;
            var initialized: usize = 0;
            errdefer for (result[0..initialized]) |item| deinitValue(Row, allocator, item);

            for (records[data_start..], 0..) |record, i| {
                result[i] = try readStruct(Row, allocator, record, lookup, "");
                initialized += 1;
            }
            return result;
        },
        .pointer => |pointer_info| switch (pointer_info.size) {
            .slice => {
                var list: std.ArrayList(Row) = .empty;
                errdefer {
                    for (list.items) |item| deinitValue(Row, allocator, item);
                    list.deinit(allocator);
                }

                try list.ensureTotalCapacity(allocator, data_count);
                for (records[data_start..]) |record| {
                    const row = try readStruct(Row, allocator, record, lookup, "");
                    errdefer deinitValue(Row, allocator, row);
                    list.appendAssumeCapacity(row);
                }
                return try list.toOwnedSlice(allocator);
            },
            else => unreachable,
        },
        .@"struct" => {
            var result = try containers.initList(T, allocator, data_count);
            errdefer deinitValue(T, allocator, result);

            for (records[data_start..]) |record| {
                const row = try readStruct(Row, allocator, record, lookup, "");
                errdefer deinitValue(Row, allocator, row);
                try containers.appendList(T, &result, allocator, row);
            }
            return result;
        },
        else => unreachable,
    }
}

fn readStruct(comptime T: type, allocator: std.mem.Allocator, record: Record, lookup: ColumnLookup, comptime prefix: []const u8) !T {
    const struct_info = @typeInfo(T).@"struct";
    const options = comptime meta.optionsFor(T);
    comptime meta.validate(T, options);

    var result: T = undefined;
    var initialized = [_]bool{false} ** struct_info.fields.len;
    errdefer {
        inline for (struct_info.fields, 0..) |field, i| {
            if (!field.is_comptime and initialized[i]) deinitValue(field.type, allocator, @field(result, field.name));
        }
    }

    inline for (struct_info.fields, 0..) |field, i| {
        if (!field.is_comptime) {
            const field_options = comptime meta.fieldOptionsFor(T, field.name);
            const wire_name = comptime meta.fieldWireName(field.name, field_options, options);
            const path = comptime joinPath(prefix, wire_name);

            if (comptime meta.shouldDeserialize(field_options)) {
                if (comptime flattenedStructType(field.type, field_options)) |Nested| {
                    if (comptime isOptional(field.type)) {
                        if (!hasColumnWithPrefix(lookup, path) or try flattenedCellsEmpty(Nested, record, lookup, path)) {
                            @field(result, field.name) = null;
                        } else {
                            @field(result, field.name) = try readStruct(Nested, allocator, record, lookup, path);
                        }
                        initialized[i] = true;
                    } else if (hasColumnWithPrefix(lookup, path)) {
                        @field(result, field.name) = try readStruct(Nested, allocator, record, lookup, path);
                        initialized[i] = true;
                    }
                } else if (findColumn(lookup, path)) |column| {
                    @field(result, field.name) = try readCellValue(field.type, allocator, record.cells[column], field_options);
                    initialized[i] = true;
                }
            }
        }
    }

    inline for (struct_info.fields, 0..) |field, i| {
        if (!field.is_comptime and !initialized[i]) {
            if (field.defaultValue()) |default| {
                @field(result, field.name) = try cloneDefaultValue(field.type, allocator, default);
                initialized[i] = true;
            } else if (comptime isOptional(field.type)) {
                @field(result, field.name) = null;
                initialized[i] = true;
            } else {
                return error.MissingField;
            }
        }
    }

    return result;
}

fn readCellValue(comptime T: type, allocator: std.mem.Allocator, cell: []const u8, comptime field_options: meta.FieldOptions) !T {
    if (comptime field_options.bytes) return try readBytesCell(T, allocator, cell);
    if (comptime T == base64.Bytes) return .{ .value = try base64.decodeAlloc(allocator, cell) };

    switch (@typeInfo(T)) {
        .bool => {
            if (std.mem.eql(u8, cell, "true")) return true;
            if (std.mem.eql(u8, cell, "false")) return false;
            return error.InvalidType;
        },
        .int => {
            const token = try CsvNumber.parseAlloc(allocator, cell);
            defer token.deinit(allocator);
            return switch (token) {
                .int => |integer| try CsvNumber.readInt(T, integer),
                .float => error.InvalidType,
            };
        },
        .float => {
            const token = try CsvNumber.parseAlloc(allocator, cell);
            defer token.deinit(allocator);
            return try CsvNumber.readFloat(T, token);
        },
        .optional => |optional_info| {
            if (cell.len == 0) return null;
            return try readCellValue(optional_info.child, allocator, cell, .{});
        },
        .@"enum" => |enum_info| {
            inline for (enum_info.fields) |field| {
                if (std.mem.eql(u8, cell, field.name)) return @field(T, field.name);
            }
            return error.InvalidEnumTag;
        },
        .pointer => |pointer_info| switch (pointer_info.size) {
            .slice => {
                if (pointer_info.child != u8) unsupportedScalar(T);
                if (!std.unicode.utf8ValidateSlice(cell)) return error.InvalidUtf8;
                return try allocator.dupe(u8, cell);
            },
            .one => switch (@typeInfo(pointer_info.child)) {
                .array => |array_info| {
                    if (array_info.child != u8 or
                        (array_info.sentinel() != null and array_info.sentinel() != 0) or
                        (pointer_info.sentinel() != null and pointer_info.sentinel() != 0)) unsupportedScalar(T);
                    if (!std.unicode.utf8ValidateSlice(cell)) return error.InvalidUtf8;
                    return try allocator.dupeZ(u8, cell);
                },
                else => unsupportedScalar(T),
            },
            else => unsupportedScalar(T),
        },
        else => unsupportedScalar(T),
    }
}

fn readBytesCell(comptime T: type, allocator: std.mem.Allocator, cell: []const u8) !T {
    if (T == base64.Bytes) return .{ .value = try base64.decodeAlloc(allocator, cell) };

    switch (@typeInfo(T)) {
        .array => |array_info| {
            if (array_info.child != u8) unsupportedScalar(T);
            return try base64.decodeArray(T, cell);
        },
        .pointer => |pointer_info| switch (pointer_info.size) {
            .slice => {
                if (pointer_info.child != u8) unsupportedScalar(T);
                return try base64.decodeAlloc(allocator, cell);
            },
            else => unsupportedScalar(T),
        },
        else => unsupportedScalar(T),
    }
}

fn validateHeader(comptime Row: type, header: Record) !void {
    for (header.cells, 0..) |name, i| {
        for (header.cells[0..i]) |previous| {
            if (std.mem.eql(u8, name, previous)) return error.DuplicateField;
        }
    }

    const options = comptime meta.optionsFor(Row);
    if (!options.deny_unknown_fields) return;

    const names = comptime fieldNames(Row);
    for (header.cells) |name| {
        var matched = false;
        for (names) |known| {
            if (std.mem.eql(u8, name, known)) {
                matched = true;
                break;
            }
        }
        if (!matched) return error.UnknownField;
    }
}

fn findColumn(lookup: ColumnLookup, name: []const u8) ?usize {
    for (0..lookup.len()) |i| {
        if (std.mem.eql(u8, lookup.name(i), name)) return i;
    }
    return null;
}

fn hasColumnWithPrefix(lookup: ColumnLookup, prefix: []const u8) bool {
    for (0..lookup.len()) |i| {
        const name = lookup.name(i);
        if (name.len > prefix.len and std.mem.startsWith(u8, name, prefix) and name[prefix.len] == '.') return true;
    }
    return false;
}

fn flattenedCellsEmpty(comptime T: type, record: Record, lookup: ColumnLookup, comptime prefix: []const u8) !bool {
    const names = comptime fieldNamesWithPrefix(T, prefix);
    for (names) |name| {
        if (findColumn(lookup, name)) |column| {
            if (record.cells[column].len != 0) return false;
        }
    }
    return true;
}

fn validateRoot(comptime T: type) void {
    validateRow(rowType(T));
}

fn rowType(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .array => |array_info| array_info.child,
        .pointer => |pointer_info| switch (pointer_info.size) {
            .slice => if (pointer_info.child == u8) unsupportedRoot(T) else pointer_info.child,
            .one => switch (@typeInfo(pointer_info.child)) {
                .array => |array_info| array_info.child,
                else => unsupportedRoot(T),
            },
            else => unsupportedRoot(T),
        },
        .@"struct" => if (comptime containers.isList(T)) containers.listChild(T) else unsupportedRoot(T),
        else => unsupportedRoot(T),
    };
}

fn arrayChild(comptime T: type) type {
    return @typeInfo(T).array.child;
}

fn validateRow(comptime Row: type) void {
    if (@typeInfo(Row) != .@"struct") @compileError("zerde csv rows must be structs");
    const row_info = @typeInfo(Row).@"struct";
    if (row_info.is_tuple) @compileError("zerde csv rows must be non-tuple structs");

    const options = comptime meta.optionsFor(Row);
    comptime meta.validate(Row, options);

    inline for (row_info.fields) |field| {
        if (!field.is_comptime) {
            const field_options = comptime meta.fieldOptionsFor(Row, field.name);
            if (!field_options.skip) validateFieldType(field.type, field_options);
        }
    }
}

fn validateFieldType(comptime T: type, comptime field_options: meta.FieldOptions) void {
    if (comptime flattenedStructType(T, field_options)) |Nested| {
        validateRow(Nested);
    } else {
        validateScalar(T, field_options);
    }
}

fn validateScalar(comptime T: type, comptime field_options: meta.FieldOptions) void {
    if (field_options.bytes) {
        if (!base64.isByteType(T)) @compileError("zerde csv bytes fields require Bytes, [N]u8, []u8, or []const u8");
        return;
    }
    if (T == base64.Bytes) return;

    switch (@typeInfo(T)) {
        .bool, .int, .float, .@"enum" => return,
        .optional => |optional_info| validateFieldType(optional_info.child, .{}),
        .pointer => |pointer_info| switch (pointer_info.size) {
            .slice => if (pointer_info.child == u8) return else unsupportedScalar(T),
            .one => switch (@typeInfo(pointer_info.child)) {
                .array => |array_info| if (array_info.child == u8 and
                    (array_info.sentinel() == null or array_info.sentinel() == 0) and
                    (pointer_info.sentinel() == null or pointer_info.sentinel() == 0)) return else unsupportedScalar(T),
                else => unsupportedScalar(T),
            },
            else => unsupportedScalar(T),
        },
        else => unsupportedScalar(T),
    }
}

fn csvFieldCount(comptime Row: type) usize {
    const row_info = @typeInfo(Row).@"struct";
    comptime var count: usize = 0;
    inline for (row_info.fields) |field| {
        if (!field.is_comptime) {
            const field_options = comptime meta.fieldOptionsFor(Row, field.name);
            if (comptime meta.shouldSerialize(field_options)) {
                const NestedOpt = comptime flattenedStructType(field.type, field_options);
                if (NestedOpt) |Nested| {
                    count += comptime csvFieldCount(Nested);
                } else {
                    count += 1;
                }
            }
        }
    }
    return count;
}

fn fieldNames(comptime Row: type) []const []const u8 {
    const Holder = struct {
        const names = buildFieldNames(Row);
    };
    return &Holder.names;
}

fn buildFieldNames(comptime Row: type) [csvFieldCount(Row)][]const u8 {
    return buildFieldNamesWithPrefix(Row, "");
}

fn fieldNamesWithPrefix(comptime Row: type, comptime prefix: []const u8) []const []const u8 {
    const Holder = struct {
        const names = buildFieldNamesWithPrefix(Row, prefix);
    };
    return &Holder.names;
}

fn buildFieldNamesWithPrefix(comptime Row: type, comptime prefix: []const u8) [csvFieldCount(Row)][]const u8 {
    const row_info = @typeInfo(Row).@"struct";
    const row_options = comptime meta.optionsFor(Row);
    var names: [csvFieldCount(Row)][]const u8 = undefined;
    var current: usize = 0;

    inline for (row_info.fields) |field| {
        if (!field.is_comptime) {
            const field_options = comptime meta.fieldOptionsFor(Row, field.name);
            if (comptime !meta.shouldSerialize(field_options)) continue;
            const wire_name = comptime meta.fieldWireName(field.name, field_options, row_options);
            const path = comptime joinPath(prefix, wire_name);
            if (comptime flattenedStructType(field.type, field_options)) |Nested| {
                const nested_names = comptime fieldNamesWithPrefix(Nested, path);
                inline for (nested_names) |nested_name| {
                    names[current] = nested_name;
                    current += 1;
                }
            } else {
                names[current] = path;
                current += 1;
            }
        }
    }

    return names;
}

fn flattenedStructType(comptime T: type, comptime field_options: meta.FieldOptions) ?type {
    if (field_options.bytes or T == base64.Bytes) return null;

    const Actual = switch (@typeInfo(T)) {
        .optional => |optional_info| optional_info.child,
        else => T,
    };

    return switch (@typeInfo(Actual)) {
        .@"struct" => |struct_info| blk: {
            if (struct_info.is_tuple) break :blk null;
            if (comptime containers.isList(Actual) or containers.isMap(Actual)) break :blk null;
            break :blk Actual;
        },
        else => null,
    };
}

fn joinPath(comptime prefix: []const u8, comptime name: []const u8) []const u8 {
    if (prefix.len == 0) return name;
    return prefix ++ "." ++ name;
}

fn isOptional(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .optional => true,
        else => false,
    };
}

fn cloneDefaultValue(comptime T: type, allocator: std.mem.Allocator, value: T) !T {
    switch (@typeInfo(T)) {
        .bool, .int, .comptime_int, .float, .comptime_float, .null, .@"enum", .enum_literal => return value,
        .optional => |optional_info| {
            if (value) |child_value| return try cloneDefaultValue(optional_info.child, allocator, child_value);
            return null;
        },
        .array => |array_info| {
            var result: T = undefined;
            var index: usize = 0;
            errdefer for (result[0..index]) |item| deinitValue(array_info.child, allocator, item);

            while (index < array_info.len) : (index += 1) {
                result[index] = try cloneDefaultValue(array_info.child, allocator, value[index]);
            }
            return result;
        },
        .pointer => |pointer_info| switch (pointer_info.size) {
            .slice => {
                var result = try allocator.alloc(pointer_info.child, value.len);
                errdefer allocator.free(result);
                if (pointer_info.child == u8) {
                    @memcpy(result, value);
                } else {
                    var index: usize = 0;
                    errdefer for (result[0..index]) |item| deinitValue(pointer_info.child, allocator, item);
                    while (index < value.len) : (index += 1) {
                        result[index] = try cloneDefaultValue(pointer_info.child, allocator, value[index]);
                    }
                }
                return result;
            },
            else => unsupportedScalar(T),
        },
        .@"struct" => |struct_info| {
            if (struct_info.is_tuple) unsupportedScalar(T);
            var result: T = undefined;
            var initialized = [_]bool{false} ** struct_info.fields.len;
            errdefer {
                inline for (struct_info.fields, 0..) |field, i| {
                    if (!field.is_comptime and initialized[i]) deinitValue(field.type, allocator, @field(result, field.name));
                }
            }

            inline for (struct_info.fields, 0..) |field, i| {
                if (!field.is_comptime) {
                    @field(result, field.name) = try cloneDefaultValue(field.type, allocator, @field(value, field.name));
                    initialized[i] = true;
                }
            }
            return result;
        },
        else => unsupportedScalar(T),
    }
}

fn unsupportedRoot(comptime T: type) noreturn {
    @compileError("zerde csv root must be an array, slice, or std list of flat structs, found " ++ @typeName(T));
}

fn unsupportedScalar(comptime T: type) noreturn {
    @compileError("zerde csv fields must be scalar values, strings, enums, optionals, bytes, or nested structs, found " ++ @typeName(T));
}

test "csv writes headers and escaped cells" {
    const Row = struct {
        id: u8,
        name: []const u8,
        active: bool,
    };
    const rows = [_]Row{
        .{ .id = 1, .name = "Ada, \"Countess\"", .active = true },
        .{ .id = 2, .name = "line\nbreak", .active = false },
    };

    const out = try writeAlloc(std.testing.allocator, rows[0..]);
    defer std.testing.allocator.free(out);

    try std.testing.expectEqualStrings("id,name,active\r\n1,\"Ada, \"\"Countess\"\"\",true\r\n2,\"line\nbreak\",false", out);
}

test "csv roundtrips scalar rows with optionals enums and bytes" {
    const Role = enum { user, admin };
    const Row = struct {
        id: u16,
        name: []const u8,
        role: Role,
        score: ?f64,
        data: base64.Bytes,
    };

    const input = "id,name,role,score,data\r\n1,Ada,admin,3.5,SGk=\r\n2,Bob,user,,AAE=\r\n";
    const rows = try readSlice([]Row, std.testing.allocator, input);
    defer deinitValue([]Row, std.testing.allocator, rows);

    try std.testing.expectEqual(@as(usize, 2), rows.len);
    try std.testing.expectEqual(@as(u16, 1), rows[0].id);
    try std.testing.expectEqualStrings("Ada", rows[0].name);
    try std.testing.expectEqual(Role.admin, rows[0].role);
    try std.testing.expectEqual(@as(?f64, 3.5), rows[0].score);
    try std.testing.expectEqualSlices(u8, "Hi", rows[0].data.value);
    try std.testing.expectEqual(@as(u16, 2), rows[1].id);
    try std.testing.expectEqual(@as(?f64, null), rows[1].score);
    try std.testing.expectEqualSlices(u8, &.{ 0, 1 }, rows[1].data.value);
}

test "csv supports tab delimiter through options" {
    const Row = struct {
        id: u8,
        text: []const u8,
    };
    const rows = [_]Row{.{ .id = 1, .text = "has\ttab" }};

    const out = try writeAllocWithOptions(std.testing.allocator, rows[0..], .{
        .delimiter = .tab,
        .record_terminator = .lf,
    });
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("id\ttext\n1\t\"has\ttab\"", out);

    const parsed = try readSliceWithOptions([]Row, std.testing.allocator, out, .{ .delimiter = .tab });
    defer deinitValue([]Row, std.testing.allocator, parsed);
    try std.testing.expectEqual(@as(usize, 1), parsed.len);
    try std.testing.expectEqual(@as(u8, 1), parsed[0].id);
    try std.testing.expectEqualStrings("has\ttab", parsed[0].text);
}

test "csv honors metadata for headers and skipped fields" {
    const Row = struct {
        user_id: u64,
        display_name: []const u8,
        password_hash: []const u8 = "redacted",

        pub const zerde = .{
            .rename_all = .camel_case,
            .fields = .{
                .display_name = .{ .rename = "name" },
                .password_hash = .{ .skip = true },
            },
        };
    };
    const rows = [_]Row{.{ .user_id = 1, .display_name = "Grant", .password_hash = "secret" }};

    const out = try writeAlloc(std.testing.allocator, rows[0..]);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("userId,name\r\n1,Grant", out);

    const parsed = try readSlice([]Row, std.testing.allocator, out);
    defer deinitValue([]Row, std.testing.allocator, parsed);
    try std.testing.expectEqual(@as(u64, 1), parsed[0].user_id);
    try std.testing.expectEqualStrings("Grant", parsed[0].display_name);
    try std.testing.expectEqualStrings("redacted", parsed[0].password_hash);
}

test "csv roundtrips std ArrayList values" {
    const Row = struct {
        id: u8,
        name: []const u8,
    };
    const allocator = std.testing.allocator;

    var list: std.ArrayList(Row) = .empty;
    defer list.deinit(allocator);
    try list.append(allocator, .{ .id = 1, .name = "one" });
    try list.append(allocator, .{ .id = 2, .name = "two" });

    const out = try writeAlloc(allocator, list);
    defer allocator.free(out);
    try std.testing.expectEqualStrings("id,name\r\n1,one\r\n2,two", out);

    const parsed = try readSlice(std.ArrayList(Row), allocator, out);
    defer deinitValue(std.ArrayList(Row), allocator, parsed);
    try std.testing.expectEqual(@as(usize, 2), parsed.items.len);
    try std.testing.expectEqual(@as(u8, 1), parsed.items[0].id);
    try std.testing.expectEqualStrings("one", parsed.items[0].name);
}

test "csv roundtrips std MultiArrayList values" {
    const Row = struct {
        id: u8,
        name: []const u8,
    };
    const List = std.MultiArrayList(Row);
    const allocator = std.testing.allocator;

    var list: List = .empty;
    defer list.deinit(allocator);
    try list.append(allocator, .{ .id = 1, .name = "one" });
    try list.append(allocator, .{ .id = 2, .name = "two" });

    const out = try writeAlloc(allocator, list);
    defer allocator.free(out);
    try std.testing.expectEqualStrings("id,name\r\n1,one\r\n2,two", out);

    const parsed = try readSlice(List, allocator, out);
    defer deinitValue(List, allocator, parsed);
    try std.testing.expectEqual(@as(usize, 2), parsed.len);
    const item = parsed.get(1);
    try std.testing.expectEqual(@as(u8, 2), item.id);
    try std.testing.expectEqualStrings("two", item.name);
}

test "csv supports headerless documents and fixed array roots" {
    const Row = struct {
        id: u8,
        name: []const u8,
    };
    const rows = [_]Row{
        .{ .id = 1, .name = "one" },
        .{ .id = 2, .name = "two" },
    };

    const out = try writeAllocWithOptions(std.testing.allocator, rows, .{ .header = false });
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("1,one\r\n2,two", out);

    const parsed = try readSliceWithOptions([2]Row, std.testing.allocator, out, .{ .header = false });
    defer deinitValue([2]Row, std.testing.allocator, parsed);
    try std.testing.expectEqual(@as(u8, 1), parsed[0].id);
    try std.testing.expectEqualStrings("one", parsed[0].name);
    try std.testing.expectEqual(@as(u8, 2), parsed[1].id);
    try std.testing.expectEqualStrings("two", parsed[1].name);
}

test "csv supports final record terminators and lf input" {
    const Row = struct {
        id: u8,
        note: []const u8,
    };
    const rows = [_]Row{.{ .id = 1, .note = "ok" }};

    const out = try writeAllocWithOptions(std.testing.allocator, rows, .{
        .record_terminator = .lf,
        .final_record_terminator = true,
    });
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("id,note\n1,ok\n", out);

    const parsed = try readSlice([]Row, std.testing.allocator, out);
    defer deinitValue([]Row, std.testing.allocator, parsed);
    try std.testing.expectEqual(@as(usize, 1), parsed.len);
    try std.testing.expectEqualStrings("ok", parsed[0].note);
}

test "csv skips unknown columns unless denied" {
    const Loose = struct {
        id: u8,
        name: []const u8,
    };
    const Strict = struct {
        id: u8,
        name: []const u8,

        pub const zerde = .{ .deny_unknown_fields = true };
    };
    const input = "id,extra,name\r\n1,ignored,Ada";

    const loose = try readSlice([]Loose, std.testing.allocator, input);
    defer deinitValue([]Loose, std.testing.allocator, loose);
    try std.testing.expectEqual(@as(usize, 1), loose.len);
    try std.testing.expectEqual(@as(u8, 1), loose[0].id);
    try std.testing.expectEqualStrings("Ada", loose[0].name);

    try std.testing.expectError(error.UnknownField, readSlice([]Strict, std.testing.allocator, input));
}

test "csv rejects duplicate headers" {
    const Row = struct {
        id: u8,
    };

    try std.testing.expectError(error.DuplicateField, readSlice([]Row, std.testing.allocator, "id,id\r\n1,2"));
}

test "csv handles empty strings distinctly from optional nulls" {
    const Row = struct {
        name: []const u8,
        nickname: ?[]const u8,
    };

    const rows = try readSlice([]Row, std.testing.allocator, "name,nickname\r\n,");
    defer deinitValue([]Row, std.testing.allocator, rows);
    try std.testing.expectEqual(@as(usize, 1), rows.len);
    try std.testing.expectEqualStrings("", rows[0].name);
    try std.testing.expectEqual(@as(?[]const u8, null), rows[0].nickname);
}

test "csv roundtrips fixed byte arrays with bytes metadata" {
    const Row = struct {
        digest: [3]u8,

        pub const zerde = .{
            .fields = .{ .digest = .{ .bytes = true } },
        };
    };
    const rows = [_]Row{.{ .digest = .{ 0, 1, 2 } }};

    const out = try writeAlloc(std.testing.allocator, rows[0..]);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("digest\r\nAAEC", out);

    const parsed = try readSlice([]Row, std.testing.allocator, out);
    defer deinitValue([]Row, std.testing.allocator, parsed);
    try std.testing.expectEqualSlices(u8, &.{ 0, 1, 2 }, parsed[0].digest[0..]);
}

test "csv flattens nested structs and reads them back into trees" {
    const Address = struct {
        street: []const u8,
        zip_code: u32,

        pub const zerde = .{ .rename_all = .camel_case };
    };
    const Row = struct {
        id: u8,
        address: Address,
        created: datetime.Timestamp,
    };
    const rows = [_]Row{.{
        .id = 1,
        .address = .{ .street = "Main", .zip_code = 12345 },
        .created = .{ .seconds = 1_700_000_000, .nanoseconds = 123 },
    }};

    const out = try writeAlloc(std.testing.allocator, rows[0..]);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("id,address.street,address.zipCode,created.seconds,created.nanoseconds\r\n1,Main,12345,1700000000,123", out);

    const parsed = try readSlice([]Row, std.testing.allocator, out);
    defer deinitValue([]Row, std.testing.allocator, parsed);
    try std.testing.expectEqual(@as(usize, 1), parsed.len);
    try std.testing.expectEqual(@as(u8, 1), parsed[0].id);
    try std.testing.expectEqualStrings("Main", parsed[0].address.street);
    try std.testing.expectEqual(@as(u32, 12345), parsed[0].address.zip_code);
    try std.testing.expectEqual(@as(i64, 1_700_000_000), parsed[0].created.seconds);
    try std.testing.expectEqual(@as(u32, 123), parsed[0].created.nanoseconds);
}

test "csv handles optional flattened structs" {
    const Detail = struct {
        code: u8,
        label: []const u8,
    };
    const Row = struct {
        id: u8,
        detail: ?Detail,
    };
    const rows = [_]Row{
        .{ .id = 1, .detail = null },
        .{ .id = 2, .detail = .{ .code = 7, .label = "ok" } },
    };

    const out = try writeAlloc(std.testing.allocator, rows[0..]);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("id,detail.code,detail.label\r\n1,,\r\n2,7,ok", out);

    const parsed = try readSlice([]Row, std.testing.allocator, out);
    defer deinitValue([]Row, std.testing.allocator, parsed);
    try std.testing.expectEqual(@as(usize, 2), parsed.len);
    try std.testing.expectEqual(@as(?Detail, null), parsed[0].detail);
    try std.testing.expectEqual(@as(u8, 7), parsed[1].detail.?.code);
    try std.testing.expectEqualStrings("ok", parsed[1].detail.?.label);
}

test "csv reads flattened structs with defaulted nested fields" {
    const Detail = struct {
        code: u8,
        label: []const u8 = "default",
    };
    const Row = struct {
        id: u8,
        detail: Detail,
    };

    const parsed = try readSlice([]Row, std.testing.allocator, "id,detail.code\r\n1,7");
    defer deinitValue([]Row, std.testing.allocator, parsed);
    try std.testing.expectEqual(@as(usize, 1), parsed.len);
    try std.testing.expectEqual(@as(u8, 7), parsed[0].detail.code);
    try std.testing.expectEqualStrings("default", parsed[0].detail.label);
}

test "csv low-level encoder flattens nested structs" {
    const Detail = struct {
        code: u8,
        label: []const u8,
    };
    const Row = struct {
        id: u8,
        detail: Detail,
        timestamp: datetime.Timestamp,
    };
    const rows = [_]Row{.{
        .id = 1,
        .detail = .{ .code = 7, .label = "ok" },
        .timestamp = .{ .seconds = 10, .nanoseconds = 20 },
    }};

    var buffer: [256]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    var enc = encoder(&writer);
    const slice: []const Row = rows[0..];
    try @import("serialize.zig").serialize(slice, &enc);
    try enc.finish();

    try std.testing.expectEqualStrings("id,detail.code,detail.label,timestamp.seconds,timestamp.nanoseconds\r\n1,7,ok,10,20", writer.buffered());

    var tab_buffer: [256]u8 = undefined;
    var tab_writer: std.Io.Writer = .fixed(&tab_buffer);
    var tab_enc = encoderWithOptions(&tab_writer, .{ .delimiter = .tab });
    try @import("serialize.zig").serialize(slice, &tab_enc);
    try tab_enc.finish();

    try std.testing.expectEqualStrings("id\tdetail.code\tdetail.label\ttimestamp.seconds\ttimestamp.nanoseconds\r\n1\t7\tok\t10\t20", tab_writer.buffered());
}

test "csv low-level decoder reads flattened structs into trees" {
    const Detail = struct {
        code: u8,
        label: []const u8,
    };
    const Row = struct {
        id: u8,
        detail: ?Detail,
        timestamp: datetime.Timestamp,
    };
    const input = "id,detail.code,detail.label,timestamp.seconds,timestamp.nanoseconds\r\n1,,,10,20\r\n2,7,ok,30,40";

    var reader: std.Io.Reader = .fixed(input);
    var dec = try decoder(&reader, std.testing.allocator, .{});
    defer dec.deinit();

    const rows = try deserialize([]Row, std.testing.allocator, &dec);
    defer deinitValue([]Row, std.testing.allocator, rows);
    try dec.finish();

    try std.testing.expectEqual(@as(usize, 2), rows.len);
    try std.testing.expectEqual(@as(?Detail, null), rows[0].detail);
    try std.testing.expectEqual(@as(i64, 10), rows[0].timestamp.seconds);
    try std.testing.expectEqual(@as(u8, 7), rows[1].detail.?.code);
    try std.testing.expectEqualStrings("ok", rows[1].detail.?.label);
    try std.testing.expectEqual(@as(u32, 40), rows[1].timestamp.nanoseconds);
}

test "csv rejects invalid scalar cells" {
    const NumberRow = struct {
        id: u8,
    };
    const BoolRow = struct {
        active: bool,
    };
    const BytesRow = struct {
        data: base64.Bytes,
    };

    try std.testing.expectError(error.InvalidNumberSyntax, readSlice([]NumberRow, std.testing.allocator, "id\r\nnot-number"));
    try std.testing.expectError(error.InvalidType, readSlice([]BoolRow, std.testing.allocator, "active\r\nyes"));
    try std.testing.expectError(error.InvalidBase64, readSlice([]BytesRow, std.testing.allocator, "data\r\nnot base64!"));
}

test "csv writes headers for empty slices" {
    const Row = struct {
        id: u8,
        name: []const u8,
    };
    const rows: []const Row = &.{};

    const out = try writeAlloc(std.testing.allocator, rows);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("id,name", out);
}

test "csv rejects malformed documents" {
    const Row = struct {
        id: u8,
        name: []const u8,
    };

    try std.testing.expectError(error.InvalidCsvSyntax, readSlice([]Row, std.testing.allocator, "id,name\r\n1,\"bad"));
    try std.testing.expectError(error.InvalidCsvRecordLength, readSlice([]Row, std.testing.allocator, "id,name\r\n1"));
}
