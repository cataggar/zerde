//! Internal schema descriptors for reflected Zig types.

const std = @import("std");

const base64 = @import("base64.zig");
const containers = @import("containers.zig");
const meta = @import("meta.zig");

const branch_quota = 100_000;

/// Internal inspection-oriented schema descriptor.
pub const Schema = struct {
    /// Fully qualified Zig type name.
    type_name: []const u8,
    shape: Shape,
};

pub const Shape = union(enum) {
    bool,
    int: IntInfo,
    float: FloatInfo,
    string,
    bytes,
    optional: *const Schema,
    seq: SeqInfo,
    map: MapInfo,
    struct_: StructInfo,
    enum_: EnumInfo,
    union_: UnionInfo,
};

pub const IntInfo = struct {
    signedness: std.builtin.Signedness,
    bits: u16,
};

pub const FloatInfo = struct {
    bits: u16,
};

pub const SeqInfo = struct {
    child: *const Schema,
    len: ?usize,
};

pub const MapInfo = struct {
    key: *const Schema,
    value: *const Schema,
};

pub const FieldInfo = struct {
    zig_name: []const u8,
    wire_name: []const u8,
    schema: *const Schema,
    required: bool,
    has_default: bool,
    serializes: bool,
    deserializes: bool,
};

pub const StructInfo = struct {
    fields: []const FieldInfo,
};

pub const EnumInfo = struct {
    tags: []const []const u8,
};

pub const UnionVariantInfo = struct {
    zig_name: []const u8,
    schema: ?*const Schema,
};

pub const UnionInfo = struct {
    repr: meta.UnionRepr,
    variants: []const UnionVariantInfo,
};

/// Builds the internal schema descriptor for `T`.
pub fn forType(comptime T: type) Schema {
    return schemaFor(T).*;
}

/// Validates that `T` is representable by Zerde's current traversal.
pub fn validateType(comptime T: type) void {
    _ = schemaFor(T);
}

fn schemaFor(comptime T: type) *const Schema {
    const Holder = struct {
        const value = buildSchema(T);
    };
    return &Holder.value;
}

fn buildSchema(comptime T: type) Schema {
    @setEvalBranchQuota(branch_quota);
    return .{
        .type_name = @typeName(T),
        .shape = buildShape(T),
    };
}

fn buildShape(comptime T: type) Shape {
    if (T == base64.Bytes) return .bytes;

    return switch (@typeInfo(T)) {
        .bool => .bool,
        .int => |int_info| .{ .int = .{
            .signedness = int_info.signedness,
            .bits = int_info.bits,
        } },
        .float => |float_info| .{ .float = .{ .bits = float_info.bits } },
        .optional => |optional_info| .{ .optional = schemaFor(optional_info.child) },
        .@"enum" => .{ .enum_ = .{ .tags = enumTags(T) } },
        .array => |array_info| .{ .seq = .{ .child = schemaFor(array_info.child), .len = array_info.len } },
        .pointer => |pointer_info| switch (pointer_info.size) {
            .slice => if (pointer_info.child == u8)
                .string
            else
                .{ .seq = .{ .child = schemaFor(pointer_info.child), .len = null } },
            .one => switch (@typeInfo(pointer_info.child)) {
                .array => |array_info| if (array_info.child == u8 and
                    (array_info.sentinel() == null or array_info.sentinel() == 0) and
                    (pointer_info.sentinel() == null or pointer_info.sentinel() == 0))
                    .string
                else
                    unsupported(T),
                else => unsupported(T),
            },
            else => unsupported(T),
        },
        .@"struct" => |struct_info| blk: {
            if (comptime containers.isList(T)) {
                break :blk .{ .seq = .{ .child = schemaFor(containers.listChild(T)), .len = null } };
            }
            if (comptime containers.isMap(T)) {
                break :blk .{ .map = .{
                    .key = schemaFor(containers.mapKey(T)),
                    .value = schemaFor(containers.mapValue(T)),
                } };
            }

            if (struct_info.is_tuple) unsupported(T);
            comptime meta.validate(T, meta.optionsFor(T));
            break :blk .{ .struct_ = .{ .fields = structFields(T) } };
        },
        .@"union" => |union_info| blk: {
            if (union_info.tag_type == null) unsupported(T);
            const options = meta.optionsFor(T);
            comptime meta.validate(T, options);
            break :blk .{ .union_ = .{ .repr = options.union_repr, .variants = unionVariants(T) } };
        },
        else => unsupported(T),
    };
}

fn structFields(comptime T: type) []const FieldInfo {
    const Holder = struct {
        const fields = buildStructFields(T);
    };
    return &Holder.fields;
}

fn buildStructFields(comptime T: type) [fieldCount(T)]FieldInfo {
    @setEvalBranchQuota(branch_quota);
    const struct_info = @typeInfo(T).@"struct";
    const options = meta.optionsFor(T);

    var fields: [fieldCount(T)]FieldInfo = undefined;
    var out: usize = 0;

    inline for (struct_info.fields) |field| {
        if (!field.is_comptime) {
            const field_options = meta.fieldOptionsFor(T, field.name);
            if (!field_options.skip) {
                fields[out] = .{
                    .zig_name = field.name,
                    .wire_name = meta.fieldWireName(field.name, field_options, options),
                    .schema = if (field_options.bytes) bytesSchemaFor(field.type) else schemaFor(field.type),
                    .required = isRequiredField(field, field_options),
                    .has_default = field.defaultValue() != null,
                    .serializes = meta.shouldSerialize(field_options),
                    .deserializes = meta.shouldDeserialize(field_options),
                };
                out += 1;
            }
        }
    }

    return fields;
}

fn bytesSchemaFor(comptime T: type) *const Schema {
    const Holder = struct {
        const value = Schema{
            .type_name = @typeName(T),
            .shape = .bytes,
        };
    };
    return &Holder.value;
}

fn fieldCount(comptime T: type) usize {
    const struct_info = @typeInfo(T).@"struct";
    var count: usize = 0;

    inline for (struct_info.fields) |field| {
        if (!field.is_comptime) {
            const field_options = meta.fieldOptionsFor(T, field.name);
            if (!field_options.skip) count += 1;
        }
    }

    return count;
}

fn enumTags(comptime T: type) []const []const u8 {
    const Holder = struct {
        const tags = buildEnumTags(T);
    };
    return &Holder.tags;
}

fn buildEnumTags(comptime T: type) [@typeInfo(T).@"enum".fields.len][]const u8 {
    const enum_info = @typeInfo(T).@"enum";
    var tags: [enum_info.fields.len][]const u8 = undefined;

    inline for (enum_info.fields, 0..) |field, i| {
        tags[i] = field.name;
    }

    return tags;
}

fn unionVariants(comptime T: type) []const UnionVariantInfo {
    const Holder = struct {
        const variants = buildUnionVariants(T);
    };
    return &Holder.variants;
}

fn buildUnionVariants(comptime T: type) [@typeInfo(T).@"union".fields.len]UnionVariantInfo {
    const union_info = @typeInfo(T).@"union";
    var variants: [union_info.fields.len]UnionVariantInfo = undefined;

    inline for (union_info.fields, 0..) |field, i| {
        variants[i] = .{
            .zig_name = field.name,
            .schema = if (field.type == void) null else schemaFor(field.type),
        };
    }

    return variants;
}

fn isRequiredField(comptime field: std.builtin.Type.StructField, comptime field_options: meta.FieldOptions) bool {
    if (!meta.shouldDeserialize(field_options)) return false;
    if (field.defaultValue() != null) return false;
    return switch (@typeInfo(field.type)) {
        .optional => false,
        else => true,
    };
}

fn unsupported(comptime T: type) noreturn {
    @compileError("zerde schema does not support type " ++ @typeName(T));
}

test "schema describes primitive shapes" {
    const int_schema = forType(i32);
    try std.testing.expectEqualStrings("i32", int_schema.type_name);
    try std.testing.expectEqual(std.builtin.Signedness.signed, int_schema.shape.int.signedness);
    try std.testing.expectEqual(@as(u16, 32), int_schema.shape.int.bits);

    const string_schema = forType([]const u8);
    try std.testing.expectEqual(.string, string_schema.shape);

    const bytes_schema = forType(base64.Bytes);
    try std.testing.expectEqual(.bytes, bytes_schema.shape);
}

test "schema describes byte metadata fields as bytes" {
    const Blob = struct {
        data: []const u8,

        pub const zerde = .{
            .fields = .{
                .data = .{ .bytes = true },
            },
        };
    };

    const blob_schema = forType(Blob);
    try std.testing.expectEqual(.bytes, blob_schema.shape.struct_.fields[0].schema.shape);
}

test "schema describes structs with metadata and nested fields" {
    const User = struct {
        user_id: u64,
        display_name: []const u8,
        nickname: ?[]const u8,
        active: bool = true,
        secret: []const u8,

        pub const zerde = .{
            .rename_all = .camel_case,
            .fields = .{
                .display_name = .{ .rename = "name" },
                .secret = .{ .skip = true },
            },
        };
    };

    const user_schema = forType(User);
    const struct_schema = user_schema.shape.struct_;

    try std.testing.expectEqual(@as(usize, 4), struct_schema.fields.len);
    try std.testing.expectEqualStrings("user_id", struct_schema.fields[0].zig_name);
    try std.testing.expectEqualStrings("userId", struct_schema.fields[0].wire_name);
    try std.testing.expect(struct_schema.fields[0].required);
    try std.testing.expectEqualStrings("name", struct_schema.fields[1].wire_name);
    try std.testing.expectEqual(.string, struct_schema.fields[1].schema.shape);
    try std.testing.expect(!struct_schema.fields[2].required);
    try std.testing.expect(struct_schema.fields[3].has_default);
}

test "schema describes sequences and enums" {
    const Color = enum { red, green };
    const Value = struct {
        bytes: [2]u8,
        colors: []const Color,
    };

    const value_schema = forType(Value);
    const bytes_schema = value_schema.shape.struct_.fields[0].schema;
    const colors_schema = value_schema.shape.struct_.fields[1].schema;

    try std.testing.expectEqual(@as(?usize, 2), bytes_schema.shape.seq.len);
    try std.testing.expectEqual(@as(?usize, null), colors_schema.shape.seq.len);
    try std.testing.expectEqualStrings("red", colors_schema.shape.seq.child.shape.enum_.tags[0]);
    try std.testing.expectEqualStrings("green", colors_schema.shape.seq.child.shape.enum_.tags[1]);
}

test "schema describes std containers" {
    const list_schema = forType(std.ArrayList(u16));
    try std.testing.expectEqual(@as(?usize, null), list_schema.shape.seq.len);
    try std.testing.expectEqual(@as(u16, 16), list_schema.shape.seq.child.shape.int.bits);

    const multi_schema = forType(std.MultiArrayList(struct { name: []const u8 }));
    try std.testing.expectEqual(std.meta.Tag(Shape).struct_, std.meta.activeTag(multi_schema.shape.seq.child.shape));

    const map_schema = forType(std.StringHashMap(u8));
    try std.testing.expectEqual(.string, map_schema.shape.map.key.shape);
    try std.testing.expectEqual(@as(u16, 8), map_schema.shape.map.value.shape.int.bits);

    const unmanaged_schema = forType(std.AutoHashMapUnmanaged(u16, []const u8));
    try std.testing.expectEqual(@as(u16, 16), unmanaged_schema.shape.map.key.shape.int.bits);
    try std.testing.expectEqual(.string, unmanaged_schema.shape.map.value.shape);
}

test "schema describes tagged unions" {
    const Circle = struct { radius: u8 };
    const Tagged = union(enum) {
        circle: Circle,
        point,

        pub const zerde = .{ .union_repr = .adjacent };
    };

    const shape_schema = forType(Tagged);
    const union_schema = shape_schema.shape.union_;

    try std.testing.expectEqual(meta.UnionRepr.adjacent, union_schema.repr);
    try std.testing.expectEqual(@as(usize, 2), union_schema.variants.len);
    try std.testing.expectEqualStrings("circle", union_schema.variants[0].zig_name);
    try std.testing.expectEqual(std.meta.Tag(Shape).struct_, std.meta.activeTag(union_schema.variants[0].schema.?.shape));
    try std.testing.expectEqualStrings("point", union_schema.variants[1].zig_name);
    try std.testing.expect(union_schema.variants[1].schema == null);
}
