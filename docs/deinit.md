# deinit

## Navigation

- [API Index](README.md)
- Previous: [deserialize](deserialize.md)
- Next: [number](number.md)

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

