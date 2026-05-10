# serialize

## Navigation

- [API Index](README.md)
- Previous: [json](json.md)
- Next: [base64](base64.md)

Generic type-directed serialization traversal.

## Functions

- [serialize](#fn-serialize)

<a id="fn-serialize"></a>

## serialize

```zig
pub fn serialize(value: anytype, encoder: anytype) !void
```

Serializes `value` by walking its Zig type at comptime and calling methods
on `encoder`'s structural protocol.

Supported types currently include bools, integers, floats, strings, arrays,
slices, optionals, enums, plain structs, and tagged unions.

