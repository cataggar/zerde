# codec

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
- [zon](zon.md)
- [binary](binary.md)
- [csv](csv.md)
- [events](events.md)
- [human](human.md)
- [traits](traits.md)
- [codec](codec.md)
- [schema](schema.md)

</details>

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
pub const Format = enum {
    json,
    toml,
    msgpack,
    zon,
    binary,
    csv,
    human,
};
```

<a id="fn-codec"></a>

## Codec

Returns a type-specific namespace for serialization, deserialization,
validation, schema generation, and cleanup.

```zig
pub fn Codec(comptime T: type) type
```

