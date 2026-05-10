# traits

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

Type trait helpers.

## Functions

- [isString](#fn-isstring)

<a id="fn-isstring"></a>

## isString

Returns whether `T` is one of Zerde's default string slice types.

```zig
pub fn isString(comptime T: type) bool
```

