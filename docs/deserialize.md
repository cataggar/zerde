# deserialize

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

Generic type-directed deserialization traversal.

## Functions

- [deserialize](#fn-deserialize)

<a id="fn-deserialize"></a>

## deserialize

Deserializes a value of type `T` by walking `T` at comptime and calling
methods on `decoder`'s structural protocol.

```zig
pub fn deserialize(comptime T: type, allocator: std.mem.Allocator, decoder: anytype) !T
```

