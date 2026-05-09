//! Generic type-directed serialization traversal.

const std = @import("std");

const base64 = @import("base64.zig");
const containers = @import("containers.zig");
const meta = @import("meta.zig");

/// Serializes `value` by walking its Zig type at comptime and calling methods
/// on `encoder`'s structural protocol.
///
/// Supported types currently include bools, integers, floats, strings, arrays,
/// slices, optionals, enums, plain structs, and tagged unions.
pub fn serialize(value: anytype, encoder: anytype) !void {
    try serializeValue(@TypeOf(value), value, encoder);
}

fn serializeValue(comptime T: type, value: T, encoder: anytype) !void {
    if (comptime hasTypeWriteHook(T)) {
        try T.zerdeWrite(value, encoder);
        return;
    }

    if (comptime T == base64.Bytes) {
        try encoder.emitBytes(value.value);
        return;
    }

    switch (@typeInfo(T)) {
        .bool => try encoder.emitBool(value),
        .int, .comptime_int => try encoder.emitInt(value),
        .float, .comptime_float => try encoder.emitFloat(value),
        .null => try encoder.emitNull(),
        .optional => |optional_info| {
            if (comptime hasMethod(@TypeOf(encoder), "beginOptional")) {
                if (value) |child_value| {
                    try encoder.beginOptional(true);
                    try serializeValue(optional_info.child, child_value, encoder);
                } else {
                    try encoder.beginOptional(false);
                }
            } else if (value) |child_value| {
                try serializeValue(optional_info.child, child_value, encoder);
            } else {
                try encoder.emitNull();
            }
        },
        .@"enum" => {
            if (comptime hasMethod(@TypeOf(encoder), "emitEnum")) {
                try encoder.emitEnum(T, value);
            } else {
                try encoder.emitEnumTag(@tagName(value));
            }
        },
        .enum_literal => try encoder.emitEnumTag(@tagName(value)),
        .array => |array_info| {
            if (comptime hasMethod(@TypeOf(encoder), "beginArray")) {
                try encoder.beginArray(T, array_info.len);
            } else {
                try encoder.beginSeq(array_info.len);
            }
            for (value) |item| {
                try serializeValue(array_info.child, item, encoder);
            }
            try encoder.endSeq();
        },
        .pointer => |pointer_info| switch (pointer_info.size) {
            .slice => {
                if (pointer_info.child == u8) {
                    try encoder.emitString(value);
                } else {
                    if (comptime hasMethod(@TypeOf(encoder), "beginSlice")) {
                        try encoder.beginSlice(pointer_info.child, value.len);
                    } else {
                        try encoder.beginSeq(value.len);
                    }
                    for (value) |item| {
                        try serializeValue(pointer_info.child, item, encoder);
                    }
                    try encoder.endSeq();
                }
            },
            .one => switch (@typeInfo(pointer_info.child)) {
                .array => |array_info| {
                    if (array_info.child == u8 and
                        (array_info.sentinel() == null or array_info.sentinel() == 0) and
                        (pointer_info.sentinel() == null or pointer_info.sentinel() == 0))
                    {
                        try encoder.emitString(value[0..array_info.len]);
                    } else {
                        unsupported(T);
                    }
                },
                else => unsupported(T),
            },
            else => unsupported(T),
        },
        .@"struct" => |struct_info| {
            if (comptime containers.isList(T)) {
                try serializeList(T, value, encoder);
                return;
            }
            if (comptime containers.isMap(T)) {
                try serializeMap(T, value, encoder);
                return;
            }

            if (struct_info.is_tuple) unsupported(T);

            const field_count = comptime serializableStructFieldCount(T);
            try encoder.beginStruct(T, field_count);
            try serializeStructFields(T, value, encoder);
            try encoder.endStruct();
        },
        .@"union" => |union_info| {
            if (union_info.tag_type == null) unsupported(T);

            const options = comptime meta.optionsFor(T);
            comptime meta.validate(T, options);

            const active_name = @tagName(std.meta.activeTag(value));
            switch (comptime options.union_repr) {
                .external => try serializeExternalUnion(T, value, active_name, encoder),
                .adjacent => try serializeAdjacentUnion(T, value, active_name, encoder),
                .internal => try serializeInternalUnion(T, value, active_name, encoder),
            }
        },
        else => unsupported(T),
    }
}

fn serializeList(comptime T: type, value: T, encoder: anytype) !void {
    const Child = comptime containers.listChild(T);
    const len = containers.listLen(T, value);

    try encoder.beginSeq(len);
    for (0..len) |i| {
        try serializeValue(Child, containers.listItem(T, value, i), encoder);
    }
    try encoder.endSeq();
}

fn serializeMap(comptime T: type, value: T, encoder: anytype) !void {
    const K = comptime containers.mapKey(T);
    const V = comptime containers.mapValue(T);
    const Entry = struct {
        key: K,
        value: V,
    };

    const len: usize = @intCast(value.count());
    try encoder.beginSeq(len);

    var copy = value;
    var it = copy.iterator();
    while (it.next()) |entry| {
        try encoder.beginStruct(Entry, 2);
        try encoder.emitFieldName("key");
        try serializeValue(K, if (K == void) {} else entry.key_ptr.*, encoder);
        try encoder.emitFieldName("value");
        try serializeValue(V, if (V == void) {} else entry.value_ptr.*, encoder);
        try encoder.endStruct();
    }

    try encoder.endSeq();
}

fn serializeExternalUnion(comptime T: type, value: T, active_name: []const u8, encoder: anytype) !void {
    const union_info = @typeInfo(T).@"union";

    try encoder.beginStruct(T, 1);
    inline for (union_info.fields) |field| {
        if (std.mem.eql(u8, active_name, field.name)) {
            try encoder.emitFieldName(field.name);
            try serializeUnionPayload(field.type, @field(value, field.name), encoder);
            try encoder.endStruct();
            return;
        }
    }
    unreachable;
}

fn serializeAdjacentUnion(comptime T: type, value: T, active_name: []const u8, encoder: anytype) !void {
    const union_info = @typeInfo(T).@"union";

    try encoder.beginStruct(T, 2);
    try encoder.emitFieldName(meta.union_tag_field_name);
    try encoder.emitString(active_name);

    inline for (union_info.fields) |field| {
        if (std.mem.eql(u8, active_name, field.name)) {
            try encoder.emitFieldName(meta.union_content_field_name);
            try serializeUnionPayload(field.type, @field(value, field.name), encoder);
            try encoder.endStruct();
            return;
        }
    }
    unreachable;
}

fn serializeInternalUnion(comptime T: type, value: T, active_name: []const u8, encoder: anytype) !void {
    const union_info = @typeInfo(T).@"union";

    inline for (union_info.fields) |field| {
        if (std.mem.eql(u8, active_name, field.name)) {
            const field_count = 1 + comptime if (field.type == void) 0 else serializableStructFieldCount(field.type);
            try encoder.beginStruct(T, field_count);
            try encoder.emitFieldName(meta.union_tag_field_name);
            try encoder.emitString(active_name);

            if (field.type != void) try serializeStructFields(field.type, @field(value, field.name), encoder);
            try encoder.endStruct();
            return;
        }
    }
    unreachable;
}

fn serializeUnionPayload(comptime T: type, value: T, encoder: anytype) !void {
    if (T == void) {
        try encoder.emitNull();
    } else {
        try serializeValue(T, value, encoder);
    }
}

fn serializableStructFieldCount(comptime T: type) usize {
    const struct_info = @typeInfo(T).@"struct";
    const options = comptime meta.optionsFor(T);
    comptime meta.validate(T, options);

    comptime var field_count: usize = 0;
    inline for (struct_info.fields) |field| {
        if (!field.is_comptime) {
            const field_options = comptime meta.fieldOptionsFor(T, field.name);
            if (comptime meta.shouldSerialize(field_options)) field_count += 1;
        }
    }
    return field_count;
}

fn serializeStructFields(comptime T: type, value: T, encoder: anytype) !void {
    const struct_info = @typeInfo(T).@"struct";
    const options = comptime meta.optionsFor(T);

    inline for (struct_info.fields) |field| {
        if (!field.is_comptime) {
            const field_options = comptime meta.fieldOptionsFor(T, field.name);
            if (comptime !meta.shouldSerialize(field_options)) continue;

            const wire_name = comptime meta.fieldWireName(field.name, field_options, options);
            try encoder.emitFieldName(wire_name);
            if (comptime meta.writeHook(field_options)) |Hook| {
                try Hook.write(@field(value, field.name), encoder);
            } else if (comptime field_options.bytes) {
                try serializeBytesValue(field.type, @field(value, field.name), encoder);
            } else {
                try serializeValue(field.type, @field(value, field.name), encoder);
            }
        }
    }
}

fn serializeBytesValue(comptime T: type, value: T, encoder: anytype) !void {
    if (T == base64.Bytes) {
        try encoder.emitBytes(value.value);
        return;
    }

    switch (@typeInfo(T)) {
        .array => |array_info| {
            if (array_info.child != u8) unsupported(T);
            try encoder.emitBytes(value[0..]);
        },
        .pointer => |pointer_info| switch (pointer_info.size) {
            .slice => {
                if (pointer_info.child != u8) unsupported(T);
                try encoder.emitBytes(value);
            },
            else => unsupported(T),
        },
        else => unsupported(T),
    }
}

fn hasTypeWriteHook(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct", .@"union", .@"enum", .@"opaque" => @hasDecl(T, "zerdeWrite"),
        else => false,
    };
}

fn hasMethod(comptime MaybePtr: type, comptime name: []const u8) bool {
    const T = switch (@typeInfo(MaybePtr)) {
        .pointer => |pointer_info| pointer_info.child,
        else => MaybePtr,
    };

    return switch (@typeInfo(T)) {
        .@"struct", .@"union", .@"enum", .@"opaque" => @hasDecl(T, name),
        else => false,
    };
}

fn unsupported(comptime T: type) noreturn {
    @compileError("zerde serialization does not support type " ++ @typeName(T));
}

test "serialize calls primitive encoder methods" {
    const Encoder = struct {
        seen_bool: bool = false,
        seen_int: bool = false,

        fn emitBool(self: *@This(), value: bool) !void {
            try std.testing.expect(value);
            self.seen_bool = true;
        }

        fn emitInt(self: *@This(), value: anytype) !void {
            try std.testing.expectEqual(@as(i32, 42), value);
            self.seen_int = true;
        }
    };

    var encoder = Encoder{};
    try serialize(true, &encoder);
    try serialize(@as(i32, 42), &encoder);

    try std.testing.expect(encoder.seen_bool);
    try std.testing.expect(encoder.seen_int);
}
