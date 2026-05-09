//! Generic type-directed deserialization traversal.

const std = @import("std");

const base64 = @import("base64.zig");
const containers = @import("containers.zig");
const deinit_mod = @import("deinit.zig");
const meta = @import("meta.zig");

/// Deserializes a value of type `T` by walking `T` at comptime and calling
/// methods on `decoder`'s structural protocol.
pub fn deserialize(comptime T: type, allocator: std.mem.Allocator, decoder: anytype) !T {
    return try deserializeValue(T, allocator, decoder);
}

fn deserializeValue(comptime T: type, allocator: std.mem.Allocator, decoder: anytype) !T {
    if (comptime hasTypeReadHook(T)) {
        return try T.zerdeRead(allocator, decoder);
    }

    if (comptime T == base64.Bytes) return try deserializeBytesValue(T, allocator, decoder);

    switch (@typeInfo(T)) {
        .bool => return try decoder.readBool(),
        .int => return try decoder.readInt(T),
        .float => return try decoder.readFloat(T),
        .optional => |optional_info| {
            if (comptime hasMethod(@TypeOf(decoder), "readOptionalPresent")) {
                if (!try decoder.readOptionalPresent()) return null;
                return try deserializeValue(optional_info.child, allocator, decoder);
            } else {
                if (try decoder.peek() == .null) {
                    try decoder.readNull();
                    return null;
                }
                return try deserializeValue(optional_info.child, allocator, decoder);
            }
        },
        .@"enum" => |enum_info| {
            if (comptime hasMethod(@TypeOf(decoder), "readEnum")) return try decoder.readEnum(T);

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

            if (comptime hasMethod(@TypeOf(decoder), "beginArray")) {
                _ = try decoder.beginArray(T);
            } else {
                _ = try decoder.beginSeq();
            }
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
            if (comptime containers.isList(T)) return try deserializeList(T, allocator, decoder);
            if (comptime containers.isMap(T)) return try deserializeMap(T, allocator, decoder);

            if (struct_info.is_tuple) unsupported(T);

            const options = comptime meta.optionsFor(T);
            comptime meta.validate(T, options);

            try decoder.beginStruct(T);
            return try deserializeStructFromFields(T, allocator, decoder);
        },
        .@"union" => |union_info| {
            if (union_info.tag_type == null) unsupported(T);

            const options = comptime meta.optionsFor(T);
            comptime meta.validate(T, options);

            return switch (comptime options.union_repr) {
                .external => try deserializeExternalUnion(T, allocator, decoder),
                .adjacent => try deserializeAdjacentUnion(T, allocator, decoder),
                .internal => try deserializeInternalUnion(T, allocator, decoder),
            };
        },
        else => unsupported(T),
    }
}

fn deserializeList(comptime T: type, allocator: std.mem.Allocator, decoder: anytype) !T {
    const Child = comptime containers.listChild(T);
    const len = try decoder.beginSeq();
    var result = try containers.initList(T, allocator, len);
    errdefer deinit_mod.deinit(T, allocator, result);

    while (try decoder.hasNextSeqElem()) {
        const item = try deserializeValue(Child, allocator, decoder);
        errdefer deinit_mod.deinit(Child, allocator, item);
        try containers.appendList(T, &result, allocator, item);
    }
    try decoder.endSeq();

    return result;
}

fn deserializeMap(comptime T: type, allocator: std.mem.Allocator, decoder: anytype) !T {
    const K = comptime containers.mapKey(T);
    const V = comptime containers.mapValue(T);
    const Entry = struct {
        key: K,
        value: V,
    };

    var result = try containers.initMap(T, allocator);
    errdefer deinit_mod.deinit(T, allocator, result);

    _ = try decoder.beginSeq();
    while (try decoder.hasNextSeqElem()) {
        const entry = try deserializeValue(Entry, allocator, decoder);
        errdefer deinit_mod.deinit(Entry, allocator, entry);
        try containers.putMapEntry(T, &result, allocator, entry.key, entry.value);
    }
    try decoder.endSeq();

    return result;
}

fn deserializeStructFromFields(comptime T: type, allocator: std.mem.Allocator, decoder: anytype) !T {
    const struct_info = @typeInfo(T).@"struct";
    const options = comptime meta.optionsFor(T);

    var result: T = undefined;
    var seen = [_]bool{false} ** struct_info.fields.len;
    var initialized = [_]bool{false} ** struct_info.fields.len;
    errdefer {
        inline for (struct_info.fields, 0..) |field, i| {
            if (!field.is_comptime and initialized[i]) {
                deinit_mod.deinit(field.type, allocator, @field(result, field.name));
            }
        }
    }

    while (try decoder.nextField()) |field_name| {
        defer allocator.free(field_name);
        var matched = false;

        inline for (struct_info.fields, 0..) |field, i| {
            if (!field.is_comptime) {
                const field_options = comptime meta.fieldOptionsFor(T, field.name);
                const wire_name = comptime meta.fieldWireName(field.name, field_options, options);
                if (!matched and std.mem.eql(u8, field_name, wire_name)) {
                    if (seen[i]) return error.DuplicateField;
                    seen[i] = true;
                    if (comptime meta.shouldDeserialize(field_options)) {
                        if (comptime meta.readHook(field_options)) |Hook| {
                            @field(result, field.name) = try Hook.read(field.type, allocator, decoder);
                        } else if (comptime field_options.bytes) {
                            @field(result, field.name) = try deserializeBytesValue(field.type, allocator, decoder);
                        } else {
                            @field(result, field.name) = try deserializeValue(field.type, allocator, decoder);
                        }
                        initialized[i] = true;
                    } else {
                        try decoder.skipValue();
                    }
                    matched = true;
                }
            }
        }

        if (!matched) {
            if (options.deny_unknown_fields) return error.UnknownField;
            try decoder.skipValue();
        }
    }
    try decoder.endStruct();

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

fn deserializeExternalUnion(comptime T: type, allocator: std.mem.Allocator, decoder: anytype) !T {
    const union_info = @typeInfo(T).@"union";

    try decoder.beginStruct(T);
    const field_name = (try decoder.nextField()) orelse return error.MissingUnionTag;
    defer allocator.free(field_name);

    inline for (union_info.fields) |field| {
        if (std.mem.eql(u8, field_name, field.name)) {
            const result = try deserializeUnionPayload(T, field, allocator, decoder);
            errdefer deinit_mod.deinit(T, allocator, result);

            if (try decoder.nextField()) |extra_name| {
                defer allocator.free(extra_name);
                try decoder.skipValue();
                return error.DuplicateField;
            }
            try decoder.endStruct();
            return result;
        }
    }

    try decoder.skipValue();
    return error.UnknownUnionTag;
}

fn deserializeAdjacentUnion(comptime T: type, allocator: std.mem.Allocator, decoder: anytype) !T {
    const union_info = @typeInfo(T).@"union";

    try decoder.beginStruct(T);
    const tag_field = (try decoder.nextField()) orelse return error.MissingUnionTag;
    defer allocator.free(tag_field);
    if (!std.mem.eql(u8, tag_field, meta.union_tag_field_name)) {
        try decoder.skipValue();
        return error.MissingUnionTag;
    }

    const tag = try decoder.readString(allocator);
    defer allocator.free(tag);

    const content_field = (try decoder.nextField()) orelse return error.MissingField;
    defer allocator.free(content_field);
    if (!std.mem.eql(u8, content_field, meta.union_content_field_name)) {
        try decoder.skipValue();
        return error.MissingField;
    }

    inline for (union_info.fields) |field| {
        if (std.mem.eql(u8, tag, field.name)) {
            const result = try deserializeUnionPayload(T, field, allocator, decoder);
            errdefer deinit_mod.deinit(T, allocator, result);

            if (try decoder.nextField()) |extra_name| {
                defer allocator.free(extra_name);
                try decoder.skipValue();
                return error.DuplicateField;
            }
            try decoder.endStruct();
            return result;
        }
    }

    try decoder.skipValue();
    return error.UnknownUnionTag;
}

fn deserializeInternalUnion(comptime T: type, allocator: std.mem.Allocator, decoder: anytype) !T {
    const union_info = @typeInfo(T).@"union";

    try decoder.beginStruct(T);
    const tag_field = (try decoder.nextField()) orelse return error.MissingUnionTag;
    defer allocator.free(tag_field);
    if (!std.mem.eql(u8, tag_field, meta.union_tag_field_name)) {
        try decoder.skipValue();
        return error.MissingUnionTag;
    }

    const tag = try decoder.readString(allocator);
    defer allocator.free(tag);

    inline for (union_info.fields) |field| {
        if (std.mem.eql(u8, tag, field.name)) {
            if (field.type == void) {
                if (try decoder.nextField()) |extra_name| {
                    defer allocator.free(extra_name);
                    try decoder.skipValue();
                    return error.UnknownField;
                }
                try decoder.endStruct();
                return @unionInit(T, field.name, {});
            }

            const payload = try deserializeStructFromFields(field.type, allocator, decoder);
            errdefer deinit_mod.deinit(field.type, allocator, payload);
            return @unionInit(T, field.name, payload);
        }
    }

    while (try decoder.nextField()) |extra_name| {
        defer allocator.free(extra_name);
        try decoder.skipValue();
    }
    try decoder.endStruct();
    return error.UnknownUnionTag;
}

fn deserializeBytesValue(comptime T: type, allocator: std.mem.Allocator, decoder: anytype) !T {
    if (comptime hasMethod(@TypeOf(decoder), "readBytes")) {
        const bytes = try decoder.readBytes(allocator);
        errdefer allocator.free(bytes);

        if (T == base64.Bytes) return .{ .value = bytes };

        return switch (@typeInfo(T)) {
            .array => |array_info| blk: {
                if (array_info.child != u8) unsupported(T);
                if (bytes.len != array_info.len) return error.InvalidArrayLength;
                var out: T = undefined;
                @memcpy(out[0..], bytes);
                allocator.free(bytes);
                break :blk out;
            },
            .pointer => |pointer_info| switch (pointer_info.size) {
                .slice => blk: {
                    if (pointer_info.child != u8) unsupported(T);
                    break :blk bytes;
                },
                else => unsupported(T),
            },
            else => unsupported(T),
        };
    }

    const encoded = try decoder.readString(allocator);
    defer allocator.free(encoded);

    if (T == base64.Bytes) return .{ .value = try base64.decodeAlloc(allocator, encoded) };

    return switch (@typeInfo(T)) {
        .array => |array_info| blk: {
            if (array_info.child != u8) unsupported(T);
            break :blk try base64.decodeArray(T, encoded);
        },
        .pointer => |pointer_info| switch (pointer_info.size) {
            .slice => blk: {
                if (pointer_info.child != u8) unsupported(T);
                break :blk try base64.decodeAlloc(allocator, encoded);
            },
            else => unsupported(T),
        },
        else => unsupported(T),
    };
}

fn deserializeUnionPayload(comptime T: type, comptime field: std.builtin.Type.UnionField, allocator: std.mem.Allocator, decoder: anytype) !T {
    if (field.type == void) {
        try decoder.readNull();
        return @unionInit(T, field.name, {});
    }

    const payload = try deserializeValue(field.type, allocator, decoder);
    errdefer deinit_mod.deinit(field.type, allocator, payload);
    return @unionInit(T, field.name, payload);
}

fn hasTypeReadHook(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct", .@"union", .@"enum", .@"opaque" => @hasDecl(T, "zerdeRead"),
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
            errdefer for (result[0..index]) |item| deinit_mod.deinit(array_info.child, allocator, item);

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
                    errdefer for (result[0..index]) |item| deinit_mod.deinit(pointer_info.child, allocator, item);

                    while (index < value.len) : (index += 1) {
                        result[index] = try cloneDefaultValue(pointer_info.child, allocator, value[index]);
                    }
                }
                return result;
            },
            else => unsupported(T),
        },
        .@"struct" => |struct_info| {
            if (comptime containers.isList(T)) return try cloneListValue(T, allocator, value);
            if (comptime containers.isMap(T)) return try cloneMapValue(T, allocator, value);

            if (struct_info.is_tuple) unsupported(T);

            var result: T = undefined;
            var initialized = [_]bool{false} ** struct_info.fields.len;
            errdefer {
                inline for (struct_info.fields, 0..) |field, i| {
                    if (!field.is_comptime and initialized[i]) {
                        deinit_mod.deinit(field.type, allocator, @field(result, field.name));
                    }
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
        .@"union" => |union_info| {
            if (union_info.tag_type == null) unsupported(T);

            const active_name = @tagName(std.meta.activeTag(value));
            inline for (union_info.fields) |field| {
                if (std.mem.eql(u8, active_name, field.name)) {
                    if (field.type == void) return @unionInit(T, field.name, {});

                    const payload = try cloneDefaultValue(field.type, allocator, @field(value, field.name));
                    errdefer deinit_mod.deinit(field.type, allocator, payload);
                    return @unionInit(T, field.name, payload);
                }
            }
            unreachable;
        },
        else => unsupported(T),
    }
}

fn cloneListValue(comptime T: type, allocator: std.mem.Allocator, value: T) !T {
    const Child = comptime containers.listChild(T);
    const len = containers.listLen(T, value);
    var result = try containers.initList(T, allocator, len);
    errdefer deinit_mod.deinit(T, allocator, result);

    for (0..len) |i| {
        const item = try cloneDefaultValue(Child, allocator, containers.listItem(T, value, i));
        errdefer deinit_mod.deinit(Child, allocator, item);
        try containers.appendList(T, &result, allocator, item);
    }

    return result;
}

fn cloneMapValue(comptime T: type, allocator: std.mem.Allocator, value: T) !T {
    const K = comptime containers.mapKey(T);
    const V = comptime containers.mapValue(T);
    var result = try containers.initMap(T, allocator);
    errdefer deinit_mod.deinit(T, allocator, result);

    var copy = value;
    var it = copy.iterator();
    while (it.next()) |entry| {
        const key = try cloneDefaultValue(K, allocator, if (K == void) {} else entry.key_ptr.*);
        errdefer deinit_mod.deinit(K, allocator, key);

        const map_value = try cloneDefaultValue(V, allocator, if (V == void) {} else entry.value_ptr.*);
        errdefer deinit_mod.deinit(V, allocator, map_value);

        try containers.putMapEntry(T, &result, allocator, key, map_value);
    }

    return result;
}

fn isOptional(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .optional => true,
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
    @compileError("zerde deserialization does not support type " ++ @typeName(T));
}
