# codec

## Navigation

- [API Index](README.md)
- Previous: [traits](traits.md)
- Next: [schema](schema.md)

Type-specialized codec API.

## Functions

- [Codec](#fn-codec)

## Types

- [Format](#type-format)

<a id="type-format"></a>

## Format

```zig
pub const Format = enum { ... };
```

Formats supported by the simple codec dispatch API.

<a id="fn-codec"></a>

## Codec

```zig
pub fn Codec(comptime T: type) type
```

Returns a type-specific namespace for serialization, deserialization,
validation, schema generation, and cleanup.

