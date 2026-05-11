# schema

## Navigation

- [API Index](README.md)

<details>
<summary>All documents</summary>

- [root](root.md)
- [json](json.md)
- [serialize](serialize.md)
- [base64](base64.md)
- [containers](containers.md)
- [meta](meta.md)
- [rename](rename.md)
- [deserialize](deserialize.md)
- [deinit](deinit.md)
- [number](number.md)
- [toml](toml.md)
- [datetime](datetime.md)
- [msgpack](msgpack.md)
- [cbor](cbor.md)
- [events](events.md)
- [zon](zon.md)
- [binary](binary.md)
- [csv](csv.md)
- [human](human.md)
- [traits](traits.md)
- [schema](schema.md)
- [format](format.md)
- [codec](codec.md)

</details>

## Overview

[Schema](#type-schema) descriptors for reflected Zig types.

## Functions

- [forType](#fn-fortype)
- [validateType](#fn-validatetype)
- [write](#fn-write)

## Types

- [Schema](#type-schema)
- [Shape](#type-shape)
- [IntInfo](#type-intinfo)
- [FloatInfo](#type-floatinfo)
- [SeqInfo](#type-seqinfo)
- [MapInfo](#type-mapinfo)
- [FieldInfo](#type-fieldinfo)
- [StructInfo](#type-structinfo)
- [EnumInfo](#type-enuminfo)
- [UnionVariantInfo](#type-unionvariantinfo)
- [UnionInfo](#type-unioninfo)

<a id="type-schema"></a>

## Schema

Internal inspection-oriented schema descriptor.

```zig
pub const Schema = struct {
    /// Fully qualified Zig type name.
    type_name: []const u8,
    shape: Shape,
};
```

<a id="type-shape"></a>

## Shape

High-level shape of a reflected Zig type.

```zig
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
```

<a id="type-intinfo"></a>

## IntInfo

[Integer](number.md#type-integer) schema details.

```zig
pub const IntInfo = struct {
    signedness: std.builtin.Signedness,
    bits: u16,
};
```

<a id="type-floatinfo"></a>

## FloatInfo

Floating-point schema details.

```zig
pub const FloatInfo = struct {
    bits: u16,
};
```

<a id="type-seqinfo"></a>

## SeqInfo

Sequence schema details.

```zig
pub const SeqInfo = struct {
    child: *const Schema,
    len: ?usize,
};
```

<a id="type-mapinfo"></a>

## MapInfo

Map schema details.

```zig
pub const MapInfo = struct {
    key: *const Schema,
    value: *const Schema,
};
```

<a id="type-fieldinfo"></a>

## FieldInfo

Struct field schema details.

```zig
pub const FieldInfo = struct {
    zig_name: []const u8,
    wire_name: []const u8,
    schema: *const Schema,
    required: bool,
    has_default: bool,
    serializes: bool,
    deserializes: bool,
};
```

<a id="type-structinfo"></a>

## StructInfo

Struct schema details.

```zig
pub const StructInfo = struct {
    fields: []const FieldInfo,
};
```

<a id="type-enuminfo"></a>

## EnumInfo

Enum schema details.

```zig
pub const EnumInfo = struct {
    tags: []const []const u8,
};
```

<a id="type-unionvariantinfo"></a>

## UnionVariantInfo

Tagged union variant schema details.

```zig
pub const UnionVariantInfo = struct {
    zig_name: []const u8,
    schema: ?*const Schema,
};
```

<a id="type-unioninfo"></a>

## UnionInfo

Tagged union schema details.

```zig
pub const UnionInfo = struct {
    repr: meta.UnionRepr,
    variants: []const UnionVariantInfo,
};
```

<a id="fn-fortype"></a>

## forType

Builds the internal schema descriptor for `T`.

```zig
pub fn forType(comptime T: type) Schema
```

References: [`Schema`](#type-schema)

<a id="fn-validatetype"></a>

## validateType

Validates that `T` is representable by Zerde's current traversal.

```zig
pub fn validateType(comptime T: type) void
```

<a id="fn-write"></a>

## write

Writes `schema` in the selected comptime-known format.

The `.human` format emits the compact, indented debug representation.
Machine-readable formats use Zerde's normal format writers.

```zig
pub fn write(writer: *std.Io.Writer, schema: Schema, comptime format: Format) !void
```

References: [`Schema`](#type-schema)

