//! Structural event APIs for consuming and producing Zerde-compatible values
//! without deserializing into an application Zig struct.
//!
//! Zerde's low-level format encoders and decoders already implement the same
//! structural protocol used by these event helpers. A decoder acts as a
//! structural source: it exposes methods such as `peek`, `readBool`,
//! `beginSeq`, `nextField`, and `skipValue`. An encoder acts as a structural
//! sink: it exposes methods such as `emitBool`, `emitString`, `beginSeq`,
//! `emitFieldName`, and `endStruct`.
//!
//! The generic typed APIs and event APIs are different traversals over that
//! shared protocol:
//!
//! ```zig
//! try zerde.serialize(value, &encoder);        // typed value -> sink
//! const value2 = try zerde.deserialize(T, allocator, &decoder); // source -> typed value
//! try zerde.consume(allocator, &decoder, &sink);        // source -> sink
//! try zerde.pipe(allocator, &decoder, &encoder);        // source -> encoder sink
//! ```
//!
//! Custom event sinks can build an application value tree, validate a stream,
//! count events, or transform data. Format encoders are just one kind of sink,
//! namely a sink that writes bytes. Format decoders are structural sources when
//! the format is self-describing enough to drive `peek`; binary remains
//! type-directed and is not a dynamic event source.

const std = @import("std");

/// Format-specific extension value used by self-describing formats.
pub const Extension = union(enum) {
    /// Opaque extension payload, such as MessagePack ext data.
    opaque_: Opaque,
    /// Tag wrapping another event value, such as CBOR semantic tags.
    tagged: Tagged,
    /// Tagless simple extension value, such as CBOR simple values.
    simple: Simple,

    pub const Namespace = enum {
        msgpack,
        cbor,
    };

    pub const Id = union(enum) {
        signed: i64,
        unsigned: u64,
    };

    pub const Opaque = struct {
        namespace: Namespace,
        id: Id,
        data: []u8,
    };

    pub const Tagged = struct {
        namespace: Namespace,
        id: Id,
        value: *Value,
    };

    pub const Simple = struct {
        namespace: Namespace,
        id: Id,
    };

    pub fn msgpack(type_id: i8, data: []u8) Extension {
        return .{ .opaque_ = .{ .namespace = .msgpack, .id = .{ .signed = type_id }, .data = data } };
    }

    pub fn cborTag(tag: u64, value: *Value) Extension {
        return .{ .tagged = .{ .namespace = .cbor, .id = .{ .unsigned = tag }, .value = value } };
    }

    pub fn cborSimple(code: u8) Extension {
        return .{ .simple = .{ .namespace = .cbor, .id = .{ .unsigned = code } } };
    }

    pub fn deinit(self: Extension, allocator: std.mem.Allocator) void {
        switch (self) {
            .opaque_ => |raw| allocator.free(raw.data),
            .tagged => |tagged| {
                tagged.value.deinit(allocator);
                allocator.destroy(tagged.value);
            },
            .simple => {},
        }
    }
};

/// Allocator-owned field in a structural object value.
pub const ObjectField = struct {
    name: []u8,
    value: Value,
};

/// Allocator-owned self-describing value tree.
///
/// This is a convenience representation for transcoding or tests. Users with an
/// existing representation can avoid this tree and implement a streaming sink
/// for `consume` instead.
pub const Value = union(enum) {
    null,
    bool: bool,
    int: i128,
    float: f64,
    string: []u8,
    bytes: []u8,
    enum_tag: []u8,
    datetime: []u8,
    extension: Extension,
    seq: []Value,
    struct_: []ObjectField,

    /// Frees memory owned by this value and all nested values.
    pub fn deinit(self: *Value, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .null, .bool, .int, .float => {},
            .string, .bytes, .enum_tag, .datetime => |bytes| allocator.free(bytes),
            .extension => |extension| extension.deinit(allocator),
            .seq => |items| {
                for (items) |*item| item.deinit(allocator);
                allocator.free(items);
            },
            .struct_ => |fields| {
                for (fields) |*field| {
                    allocator.free(field.name);
                    field.value.deinit(allocator);
                }
                allocator.free(fields);
            },
        }
        self.* = undefined;
    }

    /// Emits this value into any Zerde encoder.
    pub fn write(self: Value, encoder: anytype) !void {
        if (comptime hasMethod(@TypeOf(encoder), "emitEventValue")) {
            try encoder.emitEventValue(self);
            return;
        }

        switch (self) {
            .null => try encoder.emitNull(),
            .bool => |value| try encoder.emitBool(value),
            .int => |value| try encoder.emitInt(value),
            .float => |value| try encoder.emitFloat(value),
            .string => |value| try encoder.emitString(value),
            .bytes => |value| try encoder.emitBytes(value),
            .enum_tag => |tag| try emitEnumTag(encoder, tag),
            .datetime => |bytes| try emitDateTimeRaw(encoder, bytes),
            .extension => |extension| try emitExtension(encoder, extension),
            .seq => |items| {
                try encoder.beginSeq(items.len);
                for (items) |item| try item.write(encoder);
                try encoder.endSeq();
            },
            .struct_ => |fields| {
                try encoder.beginStruct(Value, fields.len);
                for (fields) |field| {
                    try encoder.emitFieldName(field.name);
                    try field.value.write(encoder);
                }
                try encoder.endStruct();
            },
        }
    }
};

/// Consumes one complete value from structural source `decoder` and forwards
/// structural events to `sink`.
///
/// A sink implements methods such as `emitNull`, `emitBool`, `beginSeq`,
/// `emitFieldName`, and `endStruct`. String, byte, field-name, enum-tag, and
/// datetime slices passed to the sink are temporary; the sink must copy them if
/// it needs to retain them after the callback returns.
pub fn consume(allocator: std.mem.Allocator, decoder: anytype, sink: anytype) !void {
    try consumeValue(allocator, decoder, sink);
}

/// Reads one complete self-describing value from `decoder` into an
/// allocator-owned `Value` tree.
pub fn readAlloc(allocator: std.mem.Allocator, decoder: anytype) !Value {
    return try readValueAlloc(allocator, decoder);
}

/// Reads one value from `decoder` and writes it to `encoder` without requiring an
/// application Zig struct. This buffers the value so encoders that require known
/// sequence or object lengths can still be targeted.
///
/// CSV targets require the buffered value to be a sequence of row structs. The
/// first row defines the fixed CSV schema; later rows may omit those fields but
/// may not add fields outside that schema.
pub fn pipe(allocator: std.mem.Allocator, decoder: anytype, encoder: anytype) !void {
    var value = try readAlloc(allocator, decoder);
    defer value.deinit(allocator);
    try value.write(encoder);
}

/// Begins a struct/object on an event target or encoder.
///
/// Targets that expose `beginStructEvent` receive the field count as-is, which
/// allows `null` when the count is unknown. Event sinks that expose
/// `beginStruct(?usize)` are also supported. Type-directed encoders that only
/// expose `beginStruct(comptime T, field_count)` receive `void` as the marker
/// type and require a known field count.
pub fn beginStruct(target: anytype, field_count: ?usize) !void {
    if (comptime hasMethod(@TypeOf(target), "beginStructEvent")) {
        try target.beginStructEvent(field_count);
    } else if (comptime hasMethod(@TypeOf(target), "beginStruct")) {
        if (comptime methodParamCount(@TypeOf(target), "beginStruct") == 2) {
            try target.beginStruct(field_count);
        } else if (comptime methodParamCount(@TypeOf(target), "beginStruct") == 3) {
            const actual_field_count = field_count orelse return error.MissingStructFieldCount;
            try target.beginStruct(void, actual_field_count);
        } else {
            @compileError("beginStruct must accept (?usize) or (comptime type, usize)");
        }
    } else {
        @compileError("target must expose beginStructEvent or beginStruct");
    }
}

fn consumeValue(allocator: std.mem.Allocator, decoder: anytype, sink: anytype) !void {
    const kind = @tagName(try decoder.peek());
    if (std.mem.eql(u8, kind, "null")) {
        try decoder.readNull();
        try sink.emitNull();
    } else if (std.mem.eql(u8, kind, "bool")) {
        try sink.emitBool(try decoder.readBool());
    } else if (std.mem.eql(u8, kind, "int")) {
        try sink.emitInt(try decoder.readInt(i128));
    } else if (std.mem.eql(u8, kind, "float")) {
        try sink.emitFloat(try decoder.readFloat(f64));
    } else if (std.mem.eql(u8, kind, "string")) {
        const value = try decoder.readString(allocator);
        defer allocator.free(value);
        try sink.emitString(value);
    } else if (std.mem.eql(u8, kind, "binary")) {
        if (comptime !hasMethod(@TypeOf(decoder), "readBytes")) return error.UnsupportedEventKind;
        const value = try decoder.readBytes(allocator);
        defer allocator.free(value);
        try sink.emitBytes(value);
    } else if (std.mem.eql(u8, kind, "enum_")) {
        const tag = try readEnumTag(allocator, decoder);
        defer allocator.free(tag);
        try emitEnumTag(sink, tag);
    } else if (std.mem.eql(u8, kind, "datetime")) {
        const value = try readDateTimeRaw(allocator, decoder);
        defer allocator.free(value);
        try emitDateTimeRaw(sink, value);
    } else if (std.mem.eql(u8, kind, "extension")) {
        const extension = try readExtension(allocator, decoder);
        defer extension.deinit(allocator);
        try emitExtension(sink, extension);
    } else if (std.mem.eql(u8, kind, "seq")) {
        const len = try decoder.beginSeq();
        try sink.beginSeq(len);
        while (try decoder.hasNextSeqElem()) try consumeValue(allocator, decoder, sink);
        try decoder.endSeq();
        try sink.endSeq();
    } else if (std.mem.eql(u8, kind, "struct_")) {
        const len = try beginStructEvent(decoder);
        try beginStruct(sink, len);
        while (try decoder.nextField()) |field_name| {
            defer allocator.free(field_name);
            try sink.emitFieldName(field_name);
            try consumeValue(allocator, decoder, sink);
        }
        try decoder.endStruct();
        try sink.endStruct();
    } else {
        return error.UnsupportedEventKind;
    }
}

fn readValueAlloc(allocator: std.mem.Allocator, decoder: anytype) !Value {
    const kind = @tagName(try decoder.peek());
    if (std.mem.eql(u8, kind, "null")) {
        try decoder.readNull();
        return .null;
    } else if (std.mem.eql(u8, kind, "bool")) {
        return .{ .bool = try decoder.readBool() };
    } else if (std.mem.eql(u8, kind, "int")) {
        return .{ .int = try decoder.readInt(i128) };
    } else if (std.mem.eql(u8, kind, "float")) {
        return .{ .float = try decoder.readFloat(f64) };
    } else if (std.mem.eql(u8, kind, "string")) {
        return .{ .string = try decoder.readString(allocator) };
    } else if (std.mem.eql(u8, kind, "binary")) {
        if (comptime !hasMethod(@TypeOf(decoder), "readBytes")) return error.UnsupportedEventKind;
        return .{ .bytes = try decoder.readBytes(allocator) };
    } else if (std.mem.eql(u8, kind, "enum_")) {
        return .{ .enum_tag = try readEnumTag(allocator, decoder) };
    } else if (std.mem.eql(u8, kind, "datetime")) {
        return .{ .datetime = try readDateTimeRaw(allocator, decoder) };
    } else if (std.mem.eql(u8, kind, "extension")) {
        return .{ .extension = try readExtension(allocator, decoder) };
    } else if (std.mem.eql(u8, kind, "seq")) {
        _ = try decoder.beginSeq();
        var items: std.ArrayList(Value) = .empty;
        errdefer {
            deinitValueList(allocator, items.items);
            items.deinit(allocator);
        }

        while (try decoder.hasNextSeqElem()) {
            const item = try readValueAlloc(allocator, decoder);
            errdefer {
                var copy = item;
                copy.deinit(allocator);
            }
            try items.append(allocator, item);
        }
        try decoder.endSeq();

        return .{ .seq = try items.toOwnedSlice(allocator) };
    } else if (std.mem.eql(u8, kind, "struct_")) {
        _ = try beginStructEvent(decoder);
        var fields: std.ArrayList(ObjectField) = .empty;
        errdefer {
            deinitFieldList(allocator, fields.items);
            fields.deinit(allocator);
        }

        while (try decoder.nextField()) |field_name| {
            errdefer allocator.free(field_name);
            const field_value = try readValueAlloc(allocator, decoder);
            errdefer {
                var copy = field_value;
                copy.deinit(allocator);
            }
            try fields.append(allocator, .{ .name = field_name, .value = field_value });
        }
        try decoder.endStruct();

        return .{ .struct_ = try fields.toOwnedSlice(allocator) };
    }

    return error.UnsupportedEventKind;
}

fn deinitValueList(allocator: std.mem.Allocator, values: []Value) void {
    for (values) |*value| value.deinit(allocator);
}

fn deinitFieldList(allocator: std.mem.Allocator, fields: []ObjectField) void {
    for (fields) |*field| {
        allocator.free(field.name);
        field.value.deinit(allocator);
    }
}

fn beginStructEvent(decoder: anytype) !?usize {
    if (comptime hasMethod(@TypeOf(decoder), "beginStructEvent")) return try decoder.beginStructEvent();
    try decoder.beginStruct(void);
    return null;
}

fn readEnumTag(allocator: std.mem.Allocator, decoder: anytype) ![]u8 {
    if (comptime hasMethod(@TypeOf(decoder), "readEnumTag")) return try decoder.readEnumTag(allocator);
    return error.UnsupportedEventKind;
}

fn readDateTimeRaw(allocator: std.mem.Allocator, decoder: anytype) ![]u8 {
    if (comptime hasMethod(@TypeOf(decoder), "readDateTimeRaw")) return try decoder.readDateTimeRaw(allocator);
    return error.UnsupportedEventKind;
}

fn readExtension(allocator: std.mem.Allocator, decoder: anytype) !Extension {
    if (comptime hasMethod(@TypeOf(decoder), "readEventExtension")) return try decoder.readEventExtension(allocator);
    if (comptime hasMethod(@TypeOf(decoder), "readExtension")) {
        const extension = try decoder.readExtension(allocator);
        return Extension.msgpack(extension.type_id, extension.data);
    }
    return error.UnsupportedEventKind;
}

fn emitEnumTag(target: anytype, tag: []const u8) !void {
    if (comptime hasMethod(@TypeOf(target), "emitEnumTag")) {
        try target.emitEnumTag(tag);
    } else {
        try target.emitString(tag);
    }
}

fn emitDateTimeRaw(target: anytype, bytes: []const u8) !void {
    if (comptime hasMethod(@TypeOf(target), "emitDateTimeRaw")) {
        try target.emitDateTimeRaw(bytes);
    } else {
        try target.emitString(bytes);
    }
}

fn emitExtension(target: anytype, extension: Extension) !void {
    if (comptime hasMethod(@TypeOf(target), "emitEventExtension")) {
        try target.emitEventExtension(extension);
        return;
    }

    if (comptime hasMethod(@TypeOf(target), "emitExtension")) {
        switch (extension) {
            .opaque_ => |raw| {
                if (raw.namespace != .msgpack) return error.UnsupportedEventKind;
                const type_id = switch (raw.id) {
                    .signed => |value| std.math.cast(i8, value) orelse return error.IntegerOverflow,
                    .unsigned => |value| std.math.cast(i8, value) orelse return error.IntegerOverflow,
                };
                try target.emitExtension(type_id, raw.data);
                return;
            },
            else => {},
        }
    }

    return error.UnsupportedEventKind;
}

fn hasMethod(comptime T: type, comptime name: []const u8) bool {
    const Target = switch (@typeInfo(T)) {
        .pointer => |pointer| pointer.child,
        else => T,
    };
    return @hasDecl(Target, name);
}

fn methodParamCount(comptime T: type, comptime name: []const u8) comptime_int {
    const Target = switch (@typeInfo(T)) {
        .pointer => |pointer| pointer.child,
        else => T,
    };
    return @typeInfo(@TypeOf(@field(Target, name))).@"fn".params.len;
}

test "events consume json into custom sink" {
    const Sink = struct {
        allocator: std.mem.Allocator,
        out: std.ArrayList(u8) = .empty,

        fn deinit(self: *@This()) void {
            self.out.deinit(self.allocator);
        }

        fn appendPrint(self: *@This(), comptime fmt: []const u8, args: anytype) !void {
            const bytes = try std.fmt.allocPrint(self.allocator, fmt, args);
            defer self.allocator.free(bytes);
            try self.out.appendSlice(self.allocator, bytes);
        }

        pub fn emitNull(self: *@This()) !void {
            try self.out.appendSlice(self.allocator, "null");
        }

        pub fn emitBool(self: *@This(), value: bool) !void {
            try self.out.appendSlice(self.allocator, if (value) "bool:true" else "bool:false");
        }

        pub fn emitInt(self: *@This(), value: i128) !void {
            try self.appendPrint("int:{d}", .{value});
        }

        pub fn emitFloat(self: *@This(), value: f64) !void {
            try self.appendPrint("float:{d}", .{value});
        }

        pub fn emitString(self: *@This(), value: []const u8) !void {
            try self.out.appendSlice(self.allocator, "string:");
            try self.out.appendSlice(self.allocator, value);
        }

        pub fn emitBytes(self: *@This(), value: []const u8) !void {
            try self.appendPrint("bytes:{d}", .{value.len});
        }

        pub fn beginSeq(self: *@This(), len: ?usize) !void {
            try self.appendPrint("seq:{?d}[", .{len});
        }

        pub fn endSeq(self: *@This()) !void {
            try self.out.append(self.allocator, ']');
        }

        pub fn beginStruct(self: *@This(), len: ?usize) !void {
            try self.appendPrint("struct:{?d}{{", .{len});
        }

        pub fn emitFieldName(self: *@This(), name: []const u8) !void {
            try self.out.appendSlice(self.allocator, name);
            try self.out.append(self.allocator, '=');
        }

        pub fn endStruct(self: *@This()) !void {
            try self.out.append(self.allocator, '}');
        }
    };

    var reader: std.Io.Reader = .fixed("{\"id\":42,\"tags\":[\"a\",\"b\"]}");
    var dec = @import("json.zig").decoder(&reader, std.testing.allocator);
    var sink = Sink{ .allocator = std.testing.allocator };
    defer sink.deinit();

    try consume(std.testing.allocator, &dec, &sink);
    try dec.finish();

    try std.testing.expectEqualStrings("struct:null{id=int:42tags=seq:null[string:astring:b]}", sink.out.items);
}

test "events beginStruct prefers beginStructEvent" {
    const Target = struct {
        called_event: bool = false,
        len: ?usize = null,

        pub fn beginStructEvent(self: *@This(), field_count: ?usize) !void {
            self.called_event = true;
            self.len = field_count;
        }

        pub fn beginStruct(self: *@This(), comptime T: type, field_count: usize) !void {
            _ = self;
            _ = T;
            _ = field_count;
            return error.WrongBeginStruct;
        }
    };

    var target = Target{};
    try beginStruct(&target, 3);

    try std.testing.expect(target.called_event);
    try std.testing.expectEqual(@as(?usize, 3), target.len);
}

test "events beginStruct supports event sinks" {
    const Sink = struct {
        len: ?usize = undefined,

        pub fn beginStruct(self: *@This(), field_count: ?usize) !void {
            self.len = field_count;
        }
    };

    var sink = Sink{};
    try beginStruct(&sink, null);

    try std.testing.expectEqual(@as(?usize, null), sink.len);
}

test "events beginStruct supports type-directed encoders" {
    const Encoder = struct {
        received_void: bool = false,
        field_count: usize = 0,

        pub fn beginStruct(self: *@This(), comptime T: type, field_count: usize) !void {
            self.received_void = T == void;
            self.field_count = field_count;
        }
    };

    var encoder = Encoder{};
    try beginStruct(&encoder, 2);

    try std.testing.expect(encoder.received_void);
    try std.testing.expectEqual(@as(usize, 2), encoder.field_count);
    try std.testing.expectError(error.MissingStructFieldCount, beginStruct(&encoder, null));
}

test "events pipe json to msgpack without application struct" {
    const msgpack = @import("msgpack.zig");

    var reader: std.Io.Reader = .fixed("{\"id\":42,\"name\":\"Ada\"}");
    var dec = @import("json.zig").decoder(&reader, std.testing.allocator);

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();
    var enc = msgpack.encoder(&out.writer);

    try pipe(std.testing.allocator, &dec, &enc);
    try dec.finish();
    try enc.finish();

    var msg_reader: std.Io.Reader = .fixed(out.writer.buffered());
    var msg_dec = msgpack.decoder(&msg_reader, std.testing.allocator);
    var value = try readAlloc(std.testing.allocator, &msg_dec);
    defer value.deinit(std.testing.allocator);
    try msg_dec.finish();

    const fields = value.struct_;
    try std.testing.expectEqual(@as(usize, 2), fields.len);
    try std.testing.expectEqualStrings("id", fields[0].name);
    try std.testing.expectEqual(@as(i128, 42), fields[0].value.int);
    try std.testing.expectEqualStrings("name", fields[1].name);
    try std.testing.expectEqualStrings("Ada", fields[1].value.string);
}

test "events preserve toml datetime tokens when writing toml" {
    const toml = @import("toml.zig");

    var reader: std.Io.Reader = .fixed("when = 1979-05-27T07:32:00Z\n");
    var dec = try toml.decoder(&reader, std.testing.allocator);
    defer dec.deinit();

    var value = try readAlloc(std.testing.allocator, &dec);
    defer value.deinit(std.testing.allocator);
    try dec.finish();

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();
    var enc = toml.encoder(&out.writer);
    try value.write(&enc);
    try enc.finish();

    try std.testing.expectEqualStrings("when = 1979-05-27T07:32:00Z", out.writer.buffered());
}

test "events read zon enum tags dynamically" {
    var reader: std.Io.Reader = .fixed(".ready");
    var dec = @import("zon.zig").decoder(&reader, std.testing.allocator);

    var value = try readAlloc(std.testing.allocator, &dec);
    defer value.deinit(std.testing.allocator);
    try dec.finish();

    try std.testing.expectEqualStrings("ready", value.enum_tag);

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();
    var enc = @import("json.zig").encoder(&out.writer);
    try value.write(&enc);
    try enc.finish();

    try std.testing.expectEqualStrings("\"ready\"", out.writer.buffered());
}

test "events consume csv rows dynamically" {
    const Sink = struct {
        allocator: std.mem.Allocator,
        out: std.ArrayList(u8) = .empty,

        fn deinit(self: *@This()) void {
            self.out.deinit(self.allocator);
        }

        fn appendPrint(self: *@This(), comptime fmt: []const u8, args: anytype) !void {
            const bytes = try std.fmt.allocPrint(self.allocator, fmt, args);
            defer self.allocator.free(bytes);
            try self.out.appendSlice(self.allocator, bytes);
        }

        pub fn emitNull(self: *@This()) !void {
            try self.out.appendSlice(self.allocator, "null");
        }

        pub fn emitBool(self: *@This(), value: bool) !void {
            try self.appendPrint("bool:{any}", .{value});
        }

        pub fn emitInt(self: *@This(), value: i128) !void {
            try self.appendPrint("int:{d}", .{value});
        }

        pub fn emitFloat(self: *@This(), value: f64) !void {
            try self.appendPrint("float:{d}", .{value});
        }

        pub fn emitString(self: *@This(), value: []const u8) !void {
            try self.out.appendSlice(self.allocator, "string:");
            try self.out.appendSlice(self.allocator, value);
        }

        pub fn emitBytes(self: *@This(), value: []const u8) !void {
            try self.appendPrint("bytes:{d}", .{value.len});
        }

        pub fn beginSeq(self: *@This(), len: ?usize) !void {
            try self.appendPrint("seq:{?d}[", .{len});
        }

        pub fn endSeq(self: *@This()) !void {
            try self.out.append(self.allocator, ']');
        }

        pub fn beginStruct(self: *@This(), len: ?usize) !void {
            try self.appendPrint("struct:{?d}{{", .{len});
        }

        pub fn emitFieldName(self: *@This(), name: []const u8) !void {
            try self.out.appendSlice(self.allocator, name);
            try self.out.append(self.allocator, '=');
        }

        pub fn endStruct(self: *@This()) !void {
            try self.out.append(self.allocator, '}');
        }
    };

    var reader: std.Io.Reader = .fixed("id,name,note\r\n1,Ada,\r\n2,Bob,ok");
    var dec = try @import("csv.zig").decoder(&reader, std.testing.allocator, .{});
    defer dec.deinit();
    var sink = Sink{ .allocator = std.testing.allocator };
    defer sink.deinit();

    try consume(std.testing.allocator, &dec, &sink);
    try dec.finish();

    try std.testing.expectEqualStrings("seq:2[struct:3{id=string:1name=string:Adanote=null}struct:3{id=string:2name=string:Bobnote=string:ok}]", sink.out.items);
}

test "events read csv rows into value tree" {
    var reader: std.Io.Reader = .fixed("id,name\r\n1,Ada\r\n2,Bob");
    var dec = try @import("csv.zig").decoder(&reader, std.testing.allocator, .{});
    defer dec.deinit();

    var value = try readAlloc(std.testing.allocator, &dec);
    defer value.deinit(std.testing.allocator);
    try dec.finish();

    const rows = value.seq;
    try std.testing.expectEqual(@as(usize, 2), rows.len);
    try std.testing.expectEqualStrings("id", rows[0].struct_[0].name);
    try std.testing.expectEqualStrings("1", rows[0].struct_[0].value.string);
    try std.testing.expectEqualStrings("name", rows[1].struct_[1].name);
    try std.testing.expectEqualStrings("Bob", rows[1].struct_[1].value.string);
}

test "events pipe csv to json without application struct" {
    var reader: std.Io.Reader = .fixed("id,name\r\n1,Ada\r\n2,Bob");
    var dec = try @import("csv.zig").decoder(&reader, std.testing.allocator, .{});
    defer dec.deinit();

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();
    var enc = @import("json.zig").encoder(&out.writer);

    try pipe(std.testing.allocator, &dec, &enc);
    try dec.finish();
    try enc.finish();

    try std.testing.expectEqualStrings("[{\"id\":\"1\",\"name\":\"Ada\"},{\"id\":\"2\",\"name\":\"Bob\"}]", out.writer.buffered());
}

test "events pipe json rows to csv using first row schema" {
    var reader: std.Io.Reader = .fixed(
        \\[{"id":1,"name":"Ada, \"Countess\"","note":null},{"id":2,"name":"Bob","note":"ok"}]
    );
    var dec = @import("json.zig").decoder(&reader, std.testing.allocator);

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();
    var enc = @import("csv.zig").encoder(&out.writer);

    try pipe(std.testing.allocator, &dec, &enc);
    try dec.finish();
    try enc.finish();

    try std.testing.expectEqualStrings("id,name,note\r\n1,\"Ada, \"\"Countess\"\"\",\r\n2,Bob,ok", out.writer.buffered());
}

test "events consume json rows directly into streaming csv encoder" {
    var reader: std.Io.Reader = .fixed(
        \\[{"id":1,"name":"Ada, \"Countess\"","note":null},{"id":2,"name":"Bob","note":"ok"}]
    );
    var dec = @import("json.zig").decoder(&reader, std.testing.allocator);

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();
    var enc = @import("csv.zig").eventEncoder(&out.writer, std.testing.allocator);
    defer enc.deinit();

    try consume(std.testing.allocator, &dec, &enc);
    try dec.finish();
    try enc.finish();

    try std.testing.expectEqualStrings("id,name,note\r\n1,\"Ada, \"\"Countess\"\"\",\r\n2,Bob,ok", out.writer.buffered());
}

test "events streaming csv writer flattens nested rows and fills missing cells" {
    var reader: std.Io.Reader = .fixed(
        \\[{"id":1,"detail":{"code":7,"label":"ok"}},{"id":2,"detail":null},{"id":3}]
    );
    var dec = @import("json.zig").decoder(&reader, std.testing.allocator);

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();
    var enc = @import("csv.zig").eventEncoderWithOptions(&out.writer, std.testing.allocator, .{ .record_terminator = .lf });
    defer enc.deinit();

    try consume(std.testing.allocator, &dec, &enc);
    try dec.finish();
    try enc.finish();

    try std.testing.expectEqualStrings("id,detail.code,detail.label\n1,7,ok\n2,,\n3,,", out.writer.buffered());
}

test "events streaming csv writer rejects fields outside first row schema" {
    var reader: std.Io.Reader = .fixed(
        \\[{"id":1},{"id":2,"extra":"nope"}]
    );
    var dec = @import("json.zig").decoder(&reader, std.testing.allocator);

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();
    var enc = @import("csv.zig").eventEncoder(&out.writer, std.testing.allocator);
    defer enc.deinit();

    try std.testing.expectError(error.UnknownField, consume(std.testing.allocator, &dec, &enc));
}

test "events streaming csv writer rejects nested sequences" {
    var reader: std.Io.Reader = .fixed(
        \\[{"id":1,"tags":["a"]}]
    );
    var dec = @import("json.zig").decoder(&reader, std.testing.allocator);

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();
    var enc = @import("csv.zig").eventEncoder(&out.writer, std.testing.allocator);
    defer enc.deinit();

    try std.testing.expectError(error.InvalidCsvEventShape, consume(std.testing.allocator, &dec, &enc));
}

test "events streaming csv writer rejects non row shapes" {
    var object_reader: std.Io.Reader = .fixed(
        \\{"id":1}
    );
    var object_dec = @import("json.zig").decoder(&object_reader, std.testing.allocator);
    var object_out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer object_out.deinit();
    var object_enc = @import("csv.zig").eventEncoder(&object_out.writer, std.testing.allocator);
    defer object_enc.deinit();

    try std.testing.expectError(error.InvalidCsvEventShape, consume(std.testing.allocator, &object_dec, &object_enc));

    var scalar_row_reader: std.Io.Reader = .fixed(
        \\[1]
    );
    var scalar_row_dec = @import("json.zig").decoder(&scalar_row_reader, std.testing.allocator);
    var scalar_row_out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer scalar_row_out.deinit();
    var scalar_row_enc = @import("csv.zig").eventEncoder(&scalar_row_out.writer, std.testing.allocator);
    defer scalar_row_enc.deinit();

    try std.testing.expectError(error.InvalidCsvEventShape, consume(std.testing.allocator, &scalar_row_dec, &scalar_row_enc));
}

test "events csv writer leaves missing first row fields empty" {
    var reader: std.Io.Reader = .fixed(
        \\[{"id":1,"name":"Ada"},{"id":2}]
    );
    var dec = @import("json.zig").decoder(&reader, std.testing.allocator);

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();
    var enc = @import("csv.zig").encoder(&out.writer);

    try pipe(std.testing.allocator, &dec, &enc);
    try dec.finish();
    try enc.finish();

    try std.testing.expectEqualStrings("id,name\r\n1,Ada\r\n2,", out.writer.buffered());
}

test "events csv writer rejects fields outside first row schema" {
    var reader: std.Io.Reader = .fixed(
        \\[{"id":1},{"id":2,"extra":"nope"}]
    );
    var dec = @import("json.zig").decoder(&reader, std.testing.allocator);

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();
    var enc = @import("csv.zig").encoder(&out.writer);

    try std.testing.expectError(error.UnknownField, pipe(std.testing.allocator, &dec, &enc));
}

test "events csv writer flattens nested first row objects" {
    var reader: std.Io.Reader = .fixed(
        \\[{"id":1,"detail":{"code":7,"label":"ok"}},{"id":2,"detail":null}]
    );
    var dec = @import("json.zig").decoder(&reader, std.testing.allocator);

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();
    var enc = @import("csv.zig").encoderWithOptions(&out.writer, .{ .record_terminator = .lf });

    try pipe(std.testing.allocator, &dec, &enc);
    try dec.finish();
    try enc.finish();

    try std.testing.expectEqualStrings("id,detail.code,detail.label\n1,7,ok\n2,,", out.writer.buffered());
}

test "events csv writer keeps null first row fields scalar" {
    var reader: std.Io.Reader = .fixed(
        \\[{"id":1,"detail":null},{"id":2,"detail":{"code":7}}]
    );
    var dec = @import("json.zig").decoder(&reader, std.testing.allocator);

    var out = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer out.deinit();
    var enc = @import("csv.zig").encoder(&out.writer);

    try std.testing.expectError(error.InvalidCsvEventShape, pipe(std.testing.allocator, &dec, &enc));
}
