# schema

## Navigation

- [API Index](README.md)
- Previous: [codec](codec.md)

## Overview

Internal schema descriptors for reflected Zig types.

## Functions

- [forType](#fn-fortype)
- [validateType](#fn-validatetype)

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
pub const Schema = struct { ... };
```

### Fields

```zig
    type_name: []const u8
    shape: Shape
```

`type_name`: Fully qualified Zig type name.

<a id="type-shape"></a>

## Shape

```zig
pub const Shape = union(enum) { ... };
```

### Fields

```zig
    int: IntInfo
    float: FloatInfo
    optional: *const Schema
    seq: SeqInfo
    map: MapInfo
    struct_: StructInfo
    enum_: EnumInfo
    union_: UnionInfo
```


<a id="type-intinfo"></a>

## IntInfo

```zig
pub const IntInfo = struct { ... };
```

### Fields

```zig
    signedness: std.builtin.Signedness
    bits: u16
```


<a id="type-floatinfo"></a>

## FloatInfo

```zig
pub const FloatInfo = struct { ... };
```

### Fields

```zig
    bits: u16
```


<a id="type-seqinfo"></a>

## SeqInfo

```zig
pub const SeqInfo = struct { ... };
```

### Fields

```zig
    child: *const Schema
    len: ?usize
```


<a id="type-mapinfo"></a>

## MapInfo

```zig
pub const MapInfo = struct { ... };
```

### Fields

```zig
    key: *const Schema
    value: *const Schema
```


<a id="type-fieldinfo"></a>

## FieldInfo

```zig
pub const FieldInfo = struct { ... };
```

### Fields

```zig
    zig_name: []const u8
    wire_name: []const u8
    schema: *const Schema
    required: bool
    has_default: bool
    serializes: bool
    deserializes: bool
```


<a id="type-structinfo"></a>

## StructInfo

```zig
pub const StructInfo = struct { ... };
```

### Fields

```zig
    fields: []const FieldInfo
```


<a id="type-enuminfo"></a>

## EnumInfo

```zig
pub const EnumInfo = struct { ... };
```

### Fields

```zig
    tags: []const []const u8
```


<a id="type-unionvariantinfo"></a>

## UnionVariantInfo

```zig
pub const UnionVariantInfo = struct { ... };
```

### Fields

```zig
    zig_name: []const u8
    schema: ?*const Schema
```


<a id="type-unioninfo"></a>

## UnionInfo

```zig
pub const UnionInfo = struct { ... };
```

### Fields

```zig
    repr: meta.UnionRepr
    variants: []const UnionVariantInfo
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

