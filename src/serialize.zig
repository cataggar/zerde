//! Generic type-directed serialization traversal.

const std = @import("std");

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
    if (comptime hasTypeSerializeHook(T)) {
        try T.zerdeSerialize(value, encoder);
        return;
    }

    switch (@typeInfo(T)) {
        .bool => try encoder.emitBool(value),
        .int, .comptime_int => try encoder.emitInt(value),
        .float, .comptime_float => try encoder.emitFloat(value),
        .null => try encoder.emitNull(),
        .optional => |optional_info| {
            if (value) |child_value| {
                try serializeValue(optional_info.child, child_value, encoder);
            } else {
                try encoder.emitNull();
            }
        },
        .@"enum", .enum_literal => try encoder.emitEnumTag(@tagName(value)),
        .array => |array_info| {
            try encoder.beginSeq(array_info.len);
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
                    try encoder.beginSeq(value.len);
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
            if (comptime meta.serializeHook(field_options)) |Hook| {
                try Hook.serialize(@field(value, field.name), encoder);
            } else {
                try serializeValue(field.type, @field(value, field.name), encoder);
            }
        }
    }
}

fn hasTypeSerializeHook(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct", .@"union", .@"enum", .@"opaque" => @hasDecl(T, "zerdeSerialize"),
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
