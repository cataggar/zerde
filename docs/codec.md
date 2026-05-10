# codec

## Navigation

- [API Index](README.md)
- Previous: [traits](traits.md)
- Next: [schema](schema.md)

## Overview

Type-specialized codec API.

## Functions

- [Codec](#fn-codec)

## Types

- [Format](#type-format)

<a id="type-format"></a>

## Format

Formats supported by the simple codec dispatch API.

```zig
pub const Format = enum {};
```

<a id="fn-codec"></a>

## Codec

Returns a type-specific namespace for serialization, deserialization,
validation, schema generation, and cleanup.

```zig
pub fn Codec(comptime T: type) type
```

