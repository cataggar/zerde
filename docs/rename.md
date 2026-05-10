# rename

## Navigation

- [API Index](README.md)
- Previous: [meta](meta.md)
- Next: [deserialize](deserialize.md)

Field-name rename rules.

## Functions

- [apply](#fn-apply)

## Types

- [RenameRule](#type-renamerule)

<a id="type-renamerule"></a>

## RenameRule

```zig
pub const RenameRule = enum { ... };
```

Supported field-name rename policies.

<a id="fn-apply"></a>

## apply

```zig
pub fn apply(comptime rule: RenameRule, comptime name: []const u8) []const u8
```

References: [`RenameRule`](#type-renamerule)

Applies a rename rule to a Zig field name at comptime.

