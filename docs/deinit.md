# deinit

## Navigation

- [API Index](README.md)
- Previous: [deserialize](deserialize.md)
- Next: [number](number.md)

Type-directed cleanup for values produced by Zerde deserialization.

## Functions

- [deinit](#fn-deinit)

<a id="fn-deinit"></a>

## deinit

```zig
pub fn deinit(comptime T: type, allocator: std.mem.Allocator, value: T) void
```

Releases allocations owned by `value` when it was produced by Zerde
deserialization.

