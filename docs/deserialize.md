# deserialize

## Navigation

- [API Index](README.md)
- Previous: [rename](rename.md)
- Next: [deinit](deinit.md)

Generic type-directed deserialization traversal.

## Functions

- [deserialize](#fn-deserialize)

<a id="fn-deserialize"></a>

## deserialize

```zig
pub fn deserialize(comptime T: type, allocator: std.mem.Allocator, decoder: anytype) !T
```

Deserializes a value of type `T` by walking `T` at comptime and calling
methods on `decoder`'s structural protocol.

