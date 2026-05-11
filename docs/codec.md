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

Type-specialized codec API.

## Functions

- [Codec](#fn-codec)

## Imports

- [Format](#import-format) `@import("format.zig")`

<a id="import-format"></a>

## Format

Formats supported by the simple codec dispatch API.

```zig
pub const Format = @import("format.zig").Format;
```

<a id="fn-codec"></a>

## Codec

Returns a type-specific namespace for serialization, deserialization,
validation, schema generation, and cleanup.

```zig
pub fn Codec(comptime T: type) type
```

