# rename

## Navigation

- [API Index](README.md)
- Previous: [meta](meta.md)
- Next: [deserialize](deserialize.md)

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
pub const RenameRule = enum { ... };
```

<a id="fn-apply"></a>

## apply

Applies a rename rule to a Zig field name at comptime.

```zig
pub fn apply(comptime rule: RenameRule, comptime name: []const u8) []const u8
```

References: [`RenameRule`](#type-renamerule)

