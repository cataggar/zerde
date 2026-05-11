# rename

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
- [schema](schema.md)
- [format](format.md)
- [codec](codec.md)

</details>

## Overview

Field-name rename rules.

## Functions

- [apply](#fn-apply)

## Types

- [RenameRule](#type-renamerule)

<a id="type-renamerule"></a>

## RenameRule

Supported field-name rename policies.

```zig
pub const RenameRule = enum {
    none,
    snake_case,
    camel_case,
};
```

<a id="fn-apply"></a>

## apply

Applies a rename rule to a Zig field name at comptime.

```zig
pub fn apply(comptime rule: RenameRule, comptime name: []const u8) []const u8
```

References: [`RenameRule`](#type-renamerule)

