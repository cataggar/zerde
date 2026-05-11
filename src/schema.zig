//! Schema descriptors for reflected Zig types.

const std = @import("std");

const base64 = @import("base64.zig");
const containers = @import("containers.zig");
const Format = @import("format.zig").Format;
const json = @import("json.zig");
const meta = @import("meta.zig");
const msgpack = @import("msgpack.zig");
const serializeValue = @import("serialize.zig").serialize;
const toml = @import("toml.zig");

const branch_quota = 100_000;

/// Internal inspection-oriented schema descriptor.
pub const Schema = struct {
    /// Fully qualified Zig type name.
    type_name: []const u8,
    shape: Shape,
};

/// High-level shape of a reflected Zig type.
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

/// Integer schema details.
pub const IntInfo = struct {
    signedness: std.builtin.Signedness,
    bits: u16,
};

/// Floating-point schema details.
pub const FloatInfo = struct {
    bits: u16,
};

/// Sequence schema details.
pub const SeqInfo = struct {
    child: *const Schema,
    len: ?usize,
};

/// Map schema details.
pub const MapInfo = struct {
    key: *const Schema,
    value: *const Schema,
};

/// Struct field schema details.
pub const FieldInfo = struct {
    zig_name: []const u8,
    wire_name: []const u8,
    schema: *const Schema,
    required: bool,
    has_default: bool,
    serializes: bool,
    deserializes: bool,
};

/// Struct schema details.
pub const StructInfo = struct {
    fields: []const FieldInfo,
};

/// Enum schema details.
pub const EnumInfo = struct {
    tags: []const []const u8,
};

/// Tagged union variant schema details.
pub const UnionVariantInfo = struct {
    zig_name: []const u8,
    schema: ?*const Schema,
};

/// Tagged union schema details.
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

/// Writes `schema` in the selected comptime-known format.
///
/// The `.human` format emits the compact, indented debug representation.
/// Machine-readable formats use Zerde's normal format writers.
pub fn write(writer: *std.Io.Writer, schema: Schema, comptime format: Format) !void {
    switch (format) {
        .json => try json.write(writer, WireSchema{ .schema = &schema }),
        .toml => try toml.write(writer, WireSchema{ .schema = &schema }),
        .msgpack => try msgpack.write(writer, WireSchema{ .schema = &schema }),
        .human => try writeHuman(writer, schema),
        .zon => @compileError("schema output does not support zon format"),
        .binary => @compileError("schema output does not support binary format"),
        .csv => @compileError("schema output does not support csv format"),
    }
}

fn writeHuman(writer: *std.Io.Writer, schema: Schema) !void {
    try writer.print("{s} = ", .{schema.type_name});
    try writeShapeDebug(writer, &schema, 0);
    try writer.writeByte('\n');
}

const WireSchema = struct {
    schema: *const Schema,

    pub fn zerdeWrite(self: WireSchema, encoder: anytype) anyerror!void {
        try serializeValue(.{
            .type_name = self.schema.type_name,
            .shape = WireShape{ .schema = self.schema },
        }, encoder);
    }
};

const WireShape = struct {
    schema: *const Schema,

    pub fn zerdeWrite(self: WireShape, encoder: anytype) anyerror!void {
        switch (self.schema.shape) {
            .bool => try serializeValue(KindShapeWire{ .kind = "bool" }, encoder),
            .int => |info| try serializeValue(IntShapeWire{
                .kind = "int",
                .signed = info.signedness == .signed,
                .bits = info.bits,
            }, encoder),
            .float => |info| try serializeValue(FloatShapeWire{
                .kind = "float",
                .bits = info.bits,
            }, encoder),
            .string => try serializeValue(KindShapeWire{ .kind = "string" }, encoder),
            .bytes => try serializeValue(KindShapeWire{ .kind = "bytes" }, encoder),
            .optional => |child| try serializeValue(OptionalShapeWire{
                .kind = "optional",
                .child = WireSchema{ .schema = child },
            }, encoder),
            .seq => |info| try serializeValue(SeqShapeWire{ .info = info }, encoder),
            .map => |info| try serializeValue(MapShapeWire{
                .kind = "map",
                .key = WireSchema{ .schema = info.key },
                .value = WireSchema{ .schema = info.value },
            }, encoder),
            .struct_ => |info| try serializeValue(StructShapeWire{
                .kind = "struct",
                .fields = WireFields{ .fields = info.fields },
            }, encoder),
            .enum_ => |info| try serializeValue(EnumShapeWire{
                .kind = "enum",
                .tags = info.tags,
            }, encoder),
            .union_ => |info| try serializeValue(UnionShapeWire{
                .kind = "union",
                .repr = @tagName(info.repr),
                .variants = WireUnionVariants{ .variants = info.variants },
            }, encoder),
        }
    }
};

const KindShapeWire = struct {
    kind: []const u8,
};

const IntShapeWire = struct {
    kind: []const u8,
    signed: bool,
    bits: u16,
};

const FloatShapeWire = struct {
    kind: []const u8,
    bits: u16,
};

const OptionalShapeWire = struct {
    kind: []const u8,
    child: WireSchema,
};

const SeqShapeWire = struct {
    info: SeqInfo,

    pub fn zerdeWrite(self: SeqShapeWire, encoder: anytype) anyerror!void {
        const field_count: usize = if (self.info.len == null) 2 else 3;
        try encoder.beginStruct(SeqShapeWire, field_count);
        try encoder.emitFieldName("kind");
        try serializeValue(@as([]const u8, "seq"), encoder);
        if (self.info.len) |len| {
            try encoder.emitFieldName("len");
            try serializeValue(len, encoder);
        }
        try encoder.emitFieldName("child");
        try serializeValue(WireSchema{ .schema = self.info.child }, encoder);
        try encoder.endStruct();
    }
};

const MapShapeWire = struct {
    kind: []const u8,
    key: WireSchema,
    value: WireSchema,
};

const StructShapeWire = struct {
    kind: []const u8,
    fields: WireFields,
};

const EnumShapeWire = struct {
    kind: []const u8,
    tags: []const []const u8,
};

const UnionShapeWire = struct {
    kind: []const u8,
    repr: []const u8,
    variants: WireUnionVariants,
};

const WireFields = struct {
    fields: []const FieldInfo,

    pub fn zerdeWrite(self: WireFields, encoder: anytype) anyerror!void {
        try encoder.beginSeq(self.fields.len);
        for (self.fields) |*field| try serializeValue(WireField{ .field = field }, encoder);
        try encoder.endSeq();
    }
};

const WireField = struct {
    field: *const FieldInfo,

    pub fn zerdeWrite(self: WireField, encoder: anytype) anyerror!void {
        const field = self.field.*;
        try serializeValue(.{
            .zig_name = field.zig_name,
            .wire_name = field.wire_name,
            .required = field.required,
            .has_default = field.has_default,
            .serializes = field.serializes,
            .deserializes = field.deserializes,
            .schema = WireSchema{ .schema = field.schema },
        }, encoder);
    }
};

const WireUnionVariants = struct {
    variants: []const UnionVariantInfo,

    pub fn zerdeWrite(self: WireUnionVariants, encoder: anytype) anyerror!void {
        try encoder.beginSeq(self.variants.len);
        for (self.variants) |*variant| try serializeValue(WireUnionVariant{ .variant = variant }, encoder);
        try encoder.endSeq();
    }
};

const WireUnionVariant = struct {
    variant: *const UnionVariantInfo,

    pub fn zerdeWrite(self: WireUnionVariant, encoder: anytype) anyerror!void {
        const variant = self.variant.*;
        const field_count: usize = if (variant.schema == null) 2 else 2;
        try encoder.beginStruct(WireUnionVariant, field_count);
        try encoder.emitFieldName("zig_name");
        try serializeValue(variant.zig_name, encoder);
        if (variant.schema) |payload| {
            try encoder.emitFieldName("schema");
            try serializeValue(WireSchema{ .schema = payload }, encoder);
        } else {
            try encoder.emitFieldName("void");
            try serializeValue(true, encoder);
        }
        try encoder.endStruct();
    }
};

fn writeShapeDebug(writer: *std.Io.Writer, schema: *const Schema, indent: usize) !void {
    switch (schema.shape) {
        .bool => try writer.writeAll("bool"),
        .int => |info| try writer.print("{s}{d}", .{ if (info.signedness == .signed) "i" else "u", info.bits }),
        .float => |info| try writer.print("f{d}", .{info.bits}),
        .string => try writer.writeAll("string"),
        .bytes => try writer.writeAll("bytes"),
        .optional => |child| {
            try writer.writeByte('?');
            try writeShapeDebug(writer, child, indent);
        },
        .seq => |info| {
            if (info.len) |len| {
                try writer.print("[{d}]", .{len});
            } else {
                try writer.writeAll("[]");
            }
            try writeShapeDebug(writer, info.child, indent);
        },
        .map => |info| {
            try writer.writeAll("map<");
            try writeShapeDebug(writer, info.key, indent);
            try writer.writeAll(", ");
            try writeShapeDebug(writer, info.value, indent);
            try writer.writeByte('>');
        },
        .struct_ => |info| {
            try writer.writeAll("struct {");
            if (info.fields.len == 0) {
                try writer.writeByte('}');
                return;
            }

            try writer.writeByte('\n');
            for (info.fields) |field| {
                try writeIndent(writer, indent + 2);
                try writer.print("{s}: ", .{field.wire_name});
                try writeShapeDebug(writer, field.schema, indent + 2);
                try writeFieldAttributes(writer, field);
                try writer.writeByte('\n');
            }
            try writeIndent(writer, indent);
            try writer.writeByte('}');
        },
        .enum_ => |info| {
            try writer.writeAll("enum {");
            for (info.tags, 0..) |tag, i| {
                if (i != 0) try writer.writeAll(",");
                try writer.print(" {s}", .{tag});
            }
            if (info.tags.len != 0) try writer.writeByte(' ');
            try writer.writeByte('}');
        },
        .union_ => |info| {
            try writer.print("union({s}) {{", .{@tagName(info.repr)});
            if (info.variants.len == 0) {
                try writer.writeByte('}');
                return;
            }

            try writer.writeByte('\n');
            for (info.variants) |variant| {
                try writeIndent(writer, indent + 2);
                try writer.print("{s}: ", .{variant.zig_name});
                if (variant.schema) |payload| {
                    try writeShapeDebug(writer, payload, indent + 2);
                } else {
                    try writer.writeAll("void");
                }
                try writer.writeByte('\n');
            }
            try writeIndent(writer, indent);
            try writer.writeByte('}');
        },
    }
}

fn writeFieldAttributes(writer: *std.Io.Writer, field: FieldInfo) !void {
    var wrote = false;
    if (!std.mem.eql(u8, field.zig_name, field.wire_name)) {
        try beginFieldAttribute(writer, &wrote);
        try writer.print("zig: {s}", .{field.zig_name});
    }
    if (field.required) try writeFieldAttribute(writer, &wrote, "required");
    if (field.has_default) try writeFieldAttribute(writer, &wrote, "default");
    if (field.serializes and !field.deserializes) try writeFieldAttribute(writer, &wrote, "write-only");
    if (!field.serializes and field.deserializes) try writeFieldAttribute(writer, &wrote, "read-only");
    if (!field.serializes and !field.deserializes) try writeFieldAttribute(writer, &wrote, "ignored");
    if (wrote) try writer.writeByte(')');
}

fn writeFieldAttribute(writer: *std.Io.Writer, wrote: *bool, label: []const u8) !void {
    try beginFieldAttribute(writer, wrote);
    try writer.writeAll(label);
}

fn beginFieldAttribute(writer: *std.Io.Writer, wrote: *bool) !void {
    if (wrote.*) {
        try writer.writeAll(", ");
    } else {
        try writer.writeAll(" (");
        wrote.* = true;
    }
}

fn writeIndent(writer: *std.Io.Writer, count: usize) !void {
    for (0..count) |_| try writer.writeByte(' ');
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

fn expectDebug(schema: Schema, expected: []const u8) !void {
    var buffer: [4096]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);

    try write(&writer, schema, .human);

    try std.testing.expectEqualStrings(expected, writer.buffered());
}

fn expectJson(schema: Schema, expected: []const u8) !void {
    var buffer: [8192]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);

    try write(&writer, schema, .json);

    try std.testing.expectEqualStrings(expected, writer.buffered());
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

test "schema debug writes primitive and container shapes" {
    try expectDebug(forType(i32), "i32 = i32\n");
    try expectDebug(forType([]const u8), "[]const u8 = string\n");
    try expectDebug(forType([2]u8), "[2]u8 = [2]u8\n");
    try expectDebug(forType(std.StringHashMap(u8)), @typeName(std.StringHashMap(u8)) ++ " = map<string, u8>\n");
}

test "schema debug writes structs with field metadata" {
    const User = struct {
        user_id: u64,
        display_name: []const u8,
        nickname: ?[]const u8,
        active: bool = true,
        token: []const u8,
        cache: []const u8 = "",
        secret: []const u8,

        pub const zerde = .{
            .rename_all = .camel_case,
            .fields = .{
                .display_name = .{ .rename = "name" },
                .token = .{ .skip_reading = true },
                .cache = .{ .skip_writing = true },
                .secret = .{ .skip = true },
            },
        };
    };

    var expected_buffer: [2048]u8 = undefined;
    var expected: std.Io.Writer = .fixed(&expected_buffer);
    try expected.print(
        \\{s} = struct {{
        \\  userId: u64 (zig: user_id, required)
        \\  name: string (zig: display_name, required)
        \\  nickname: ?string
        \\  active: bool (default)
        \\  token: string (write-only)
        \\  cache: string (default, read-only)
        \\}}
        \\
    , .{@typeName(User)});

    try expectDebug(forType(User), expected.buffered());
}

test "schema debug writes enums and tagged unions" {
    const Color = enum { red, green };
    const Drawing = union(enum) {
        circle: struct { radius: u8 },
        color: Color,
        point,

        pub const zerde = .{ .union_repr = .adjacent };
    };

    var expected_buffer: [2048]u8 = undefined;
    var expected: std.Io.Writer = .fixed(&expected_buffer);
    try expected.print(
        \\{s} = union(adjacent) {{
        \\  circle: struct {{
        \\    radius: u8 (required)
        \\  }}
        \\  color: enum {{ red, green }}
        \\  point: void
        \\}}
        \\
    , .{@typeName(Drawing)});

    try expectDebug(forType(Drawing), expected.buffered());
}

test "schema json writes primitive and container shapes canonically" {
    try expectJson(forType(i32), "{\"type_name\":\"i32\",\"shape\":{\"kind\":\"int\",\"signed\":true,\"bits\":32}}");
    try expectJson(forType([]const u8), "{\"type_name\":\"[]const u8\",\"shape\":{\"kind\":\"string\"}}");
    try expectJson(forType([2]u8), "{\"type_name\":\"[2]u8\",\"shape\":{\"kind\":\"seq\",\"len\":2,\"child\":{\"type_name\":\"u8\",\"shape\":{\"kind\":\"int\",\"signed\":false,\"bits\":8}}}}");
}

test "schema json writes structs with field metadata canonically" {
    const User = struct {
        user_id: u64,
        display_name: []const u8,
        nickname: ?[]const u8,
        active: bool = true,
        token: []const u8,
        cache: []const u8 = "",
        secret: []const u8,

        pub const zerde = .{
            .rename_all = .camel_case,
            .fields = .{
                .display_name = .{ .rename = "display\nname" },
                .token = .{ .skip_reading = true },
                .cache = .{ .skip_writing = true },
                .secret = .{ .skip = true },
            },
        };
    };

    var expected_buffer: [4096]u8 = undefined;
    var expected: std.Io.Writer = .fixed(&expected_buffer);
    try expected.print(
        "{{\"type_name\":\"{s}\",\"shape\":{{\"kind\":\"struct\",\"fields\":[" ++
            "{{\"zig_name\":\"user_id\",\"wire_name\":\"userId\",\"required\":true,\"has_default\":false,\"serializes\":true,\"deserializes\":true,\"schema\":{{\"type_name\":\"u64\",\"shape\":{{\"kind\":\"int\",\"signed\":false,\"bits\":64}}}}}}," ++
            "{{\"zig_name\":\"display_name\",\"wire_name\":\"display\\nname\",\"required\":true,\"has_default\":false,\"serializes\":true,\"deserializes\":true,\"schema\":{{\"type_name\":\"[]const u8\",\"shape\":{{\"kind\":\"string\"}}}}}}," ++
            "{{\"zig_name\":\"nickname\",\"wire_name\":\"nickname\",\"required\":false,\"has_default\":false,\"serializes\":true,\"deserializes\":true,\"schema\":{{\"type_name\":\"?[]const u8\",\"shape\":{{\"kind\":\"optional\",\"child\":{{\"type_name\":\"[]const u8\",\"shape\":{{\"kind\":\"string\"}}}}}}}}}}," ++
            "{{\"zig_name\":\"active\",\"wire_name\":\"active\",\"required\":false,\"has_default\":true,\"serializes\":true,\"deserializes\":true,\"schema\":{{\"type_name\":\"bool\",\"shape\":{{\"kind\":\"bool\"}}}}}}," ++
            "{{\"zig_name\":\"token\",\"wire_name\":\"token\",\"required\":false,\"has_default\":false,\"serializes\":true,\"deserializes\":false,\"schema\":{{\"type_name\":\"[]const u8\",\"shape\":{{\"kind\":\"string\"}}}}}}," ++
            "{{\"zig_name\":\"cache\",\"wire_name\":\"cache\",\"required\":false,\"has_default\":true,\"serializes\":false,\"deserializes\":true,\"schema\":{{\"type_name\":\"[]const u8\",\"shape\":{{\"kind\":\"string\"}}}}}}]}}}}",
        .{@typeName(User)},
    );

    try expectJson(forType(User), expected.buffered());
}

test "schema json writes enums and tagged unions canonically" {
    const Color = enum { red, green };
    const Circle = struct { radius: u8 };
    const Drawing = union(enum) {
        circle: Circle,
        color: Color,
        point,

        pub const zerde = .{ .union_repr = .adjacent };
    };

    var expected_buffer: [4096]u8 = undefined;
    var expected: std.Io.Writer = .fixed(&expected_buffer);
    try expected.print(
        "{{\"type_name\":\"{s}\",\"shape\":{{\"kind\":\"union\",\"repr\":\"adjacent\",\"variants\":[" ++
            "{{\"zig_name\":\"circle\",\"schema\":{{\"type_name\":\"{s}\",\"shape\":{{\"kind\":\"struct\",\"fields\":[{{\"zig_name\":\"radius\",\"wire_name\":\"radius\",\"required\":true,\"has_default\":false,\"serializes\":true,\"deserializes\":true,\"schema\":{{\"type_name\":\"u8\",\"shape\":{{\"kind\":\"int\",\"signed\":false,\"bits\":8}}}}}}]}}}}}}," ++
            "{{\"zig_name\":\"color\",\"schema\":{{\"type_name\":\"{s}\",\"shape\":{{\"kind\":\"enum\",\"tags\":[\"red\",\"green\"]}}}}}}," ++
            "{{\"zig_name\":\"point\",\"void\":true}}]}}}}",
        .{ @typeName(Drawing), @typeName(Circle), @typeName(Color) },
    );

    try expectJson(forType(Drawing), expected.buffered());
}

test "schema write supports human toml and msgpack formats" {
    const User = struct {
        id: u8,
        name: []const u8,
    };
    const schema = forType(User);

    var human_buffer: [512]u8 = undefined;
    var human_writer: std.Io.Writer = .fixed(&human_buffer);
    try write(&human_writer, schema, .human);
    try std.testing.expect(std.mem.indexOf(u8, human_writer.buffered(), "struct {") != null);

    var toml_buffer: [4096]u8 = undefined;
    var toml_writer: std.Io.Writer = .fixed(&toml_buffer);
    try write(&toml_writer, schema, .toml);
    try std.testing.expect(std.mem.indexOf(u8, toml_writer.buffered(), "type_name = ") != null);
    try std.testing.expect(std.mem.indexOf(u8, toml_writer.buffered(), "kind = \"struct\"") != null);

    var msgpack_buffer: [4096]u8 = undefined;
    var msgpack_writer: std.Io.Writer = .fixed(&msgpack_buffer);
    try write(&msgpack_writer, schema, .msgpack);
    try std.testing.expect(msgpack_writer.buffered().len != 0);
}
