const std = @import("std");

pub const StructField = struct {
    name: [:0]const u8,
    type: type,
    default_value_ptr: ?*const anyopaque,
    is_comptime: bool,

    pub fn defaultValue(comptime field: StructField) ?field.type {
        const ptr: *const field.type = @ptrCast(@alignCast(field.default_value_ptr orelse return null));
        return ptr.*;
    }
};

pub const UnionField = struct {
    name: [:0]const u8,
    type: type,
};

const EnumField = struct {
    name: [:0]const u8,
    value: comptime_int,
};

fn Field(comptime Info: type) type {
    return switch (Info) {
        std.lang.Type.Struct => StructField,
        std.lang.Type.Union => UnionField,
        std.lang.Type.Enum => EnumField,
        else => @compileError("expected container reflection"),
    };
}

pub fn fields(comptime info: anytype) [info.field_names.len]Field(@TypeOf(info)) {
    var result: [info.field_names.len]Field(@TypeOf(info)) = undefined;
    for (info.field_names, 0..) |name, i| {
        result[i] = switch (@TypeOf(info)) {
            std.lang.Type.Struct => .{
                .name = name,
                .type = info.field_types[i],
                .default_value_ptr = info.field_attrs[i].default_value_ptr,
                .is_comptime = info.field_attrs[i].@"comptime",
            },
            std.lang.Type.Union => .{ .name = name, .type = info.field_types[i] },
            std.lang.Type.Enum => .{ .name = name, .value = info.field_values[i] },
            else => unreachable,
        };
    }
    return result;
}
