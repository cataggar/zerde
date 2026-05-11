# format

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

Shared format selector for dispatch APIs.

## Types

- [Format](#type-format)

<a id="type-format"></a>

## Format

Formats recognized by Zerde's comptime dispatch APIs.

```zig
pub const Format = enum {
    json,
    toml,
    msgpack,
    cbor,
    zon,
    binary,
    csv,
    human,
};
```

