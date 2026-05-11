# serialize

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
- [events](events.md)
- [cbor](cbor.md)
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

Generic type-directed serialization traversal.

## Functions

- [serialize](#fn-serialize)

<a id="fn-serialize"></a>

## serialize

Serializes `value` by walking its Zig type at comptime and calling methods
on `encoder`'s structural protocol.

Supported types currently include bools, integers, floats, strings, arrays,
slices, optionals, enums, plain structs, and tagged unions.

```zig
pub fn serialize(value: anytype, encoder: anytype) !void
```

