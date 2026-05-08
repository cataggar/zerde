const std = @import("std");

pub fn serialize(value: anytype, encoder: anytype) !void {
    try serializeValue(@TypeOf(value), value, encoder);
}

fn serializeValue(comptime T: type, value: T, encoder: anytype) !void {
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

            comptime var field_count: usize = 0;
            inline for (struct_info.fields) |field| {
                if (!field.is_comptime) field_count += 1;
            }

            try encoder.beginStruct(T, field_count);
            inline for (struct_info.fields) |field| {
                if (!field.is_comptime) {
                    try encoder.emitFieldName(field.name);
                    try serializeValue(field.type, @field(value, field.name), encoder);
                }
            }
            try encoder.endStruct();
        },
        else => unsupported(T),
    }
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
