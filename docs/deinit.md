# deinit

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

Type-directed cleanup for values produced by Zerde deserialization.

## Functions

- [deinit](#fn-deinit)

<a id="fn-deinit"></a>

## deinit

Releases allocations owned by `value` when it was produced by Zerde
deserialization.

```zig
pub fn deinit(comptime T: type, allocator: std.mem.Allocator, value: T) void
```

