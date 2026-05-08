//! Generic type-directed deserialization traversal.

const std = @import("std");

const deinit_mod = @import("deinit.zig");
const meta = @import("meta.zig");

/// Deserializes a value of type `T` by walking `T` at comptime and calling
/// methods on `decoder`'s structural protocol.
pub fn deserialize(comptime T: type, allocator: std.mem.Allocator, decoder: anytype) !T {
    return try deserializeValue(T, allocator, decoder);
}

fn deserializeValue(comptime T: type, allocator: std.mem.Allocator, decoder: anytype) !T {
    switch (@typeInfo(T)) {
        .bool => return try decoder.readBool(),
        .int => return try decoder.readInt(T),
        .float => return try decoder.readFloat(T),
        .optional => |optional_info| {
            if (try decoder.peek() == .null) {
                try decoder.readNull();
                return null;
            }
            return try deserializeValue(optional_info.child, allocator, decoder);
        },
        .@"enum" => |enum_info| {
            const tag = try decoder.readString(allocator);
            defer allocator.free(tag);

            inline for (enum_info.fields) |field| {
                if (std.mem.eql(u8, tag, field.name)) return @field(T, field.name);
            }
            return error.InvalidEnumTag;
        },
        .array => |array_info| {
            var result: T = undefined;
            var index: usize = 0;
            errdefer for (result[0..index]) |item| deinit_mod.deinit(array_info.child, allocator, item);

            _ = try decoder.beginSeq();
            while (try decoder.hasNextSeqElem()) {
                if (index == array_info.len) return error.InvalidArrayLength;
                result[index] = try deserializeValue(array_info.child, allocator, decoder);
                index += 1;
            }
            try decoder.endSeq();

            if (index != array_info.len) return error.InvalidArrayLength;
            return result;
        },
        .pointer => |pointer_info| switch (pointer_info.size) {
            .slice => {
                if (pointer_info.child == u8) return try decoder.readString(allocator);

                var list: std.ArrayList(pointer_info.child) = .empty;
                errdefer {
                    for (list.items) |item| deinit_mod.deinit(pointer_info.child, allocator, item);
                    list.deinit(allocator);
                }

                _ = try decoder.beginSeq();
                while (try decoder.hasNextSeqElem()) {
                    const item = try deserializeValue(pointer_info.child, allocator, decoder);
                    errdefer deinit_mod.deinit(pointer_info.child, allocator, item);
                    try list.append(allocator, item);
                }
                try decoder.endSeq();

                return try list.toOwnedSlice(allocator);
            },
            else => unsupported(T),
        },
        .@"struct" => |struct_info| {
            if (struct_info.is_tuple) unsupported(T);

            const options = comptime meta.optionsFor(T);
            comptime meta.validate(T, options);

            var result: T = undefined;
            var seen = [_]bool{false} ** struct_info.fields.len;
            errdefer {
                inline for (struct_info.fields, 0..) |field, i| {
                    if (!field.is_comptime and seen[i]) {
                        deinit_mod.deinit(field.type, allocator, @field(result, field.name));
                    }
                }
            }

            try decoder.beginStruct(T);
            while (try decoder.nextField()) |field_name| {
                defer allocator.free(field_name);
                var matched = false;

                inline for (struct_info.fields, 0..) |field, i| {
                    if (!field.is_comptime) {
                        const field_options = comptime meta.fieldOptionsFor(T, field.name);
                        const wire_name = comptime meta.fieldWireName(field.name, field_options, options);
                        if (!matched and std.mem.eql(u8, field_name, wire_name)) {
                            if (seen[i]) return error.DuplicateField;
                            @field(result, field.name) = try deserializeValue(field.type, allocator, decoder);
                            seen[i] = true;
                            matched = true;
                        }
                    }
                }

                if (!matched) try decoder.skipValue();
            }
            try decoder.endStruct();

            inline for (struct_info.fields, 0..) |field, i| {
                if (!field.is_comptime and !seen[i]) return error.MissingField;
            }

            return result;
        },
        else => unsupported(T),
    }
}

fn unsupported(comptime T: type) noreturn {
    @compileError("zerde deserialization does not support type " ++ @typeName(T));
}
