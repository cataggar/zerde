# serialize

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

Generic type-directed serialization traversal.

`serialize` walks a Zig value at comptime and forwards the shape of that
value into a structural sink. Format encoders are structural sinks, but a
custom sink can also validate, count, transform, or build another
representation.

A sink used with all supported Zerde type shapes should expose this core
interface:

```zig
pub fn emitNull(self: *Self) !void;
pub fn emitBool(self: *Self, value: bool) !void;
pub fn emitInt(self: *Self, value: anytype) !void;
pub fn emitFloat(self: *Self, value: anytype) !void;
pub fn emitString(self: *Self, value: []const u8) !void;
pub fn emitBytes(self: *Self, value: []const u8) !void;
pub fn emitEnumTag(self: *Self, tag: []const u8) !void;

pub fn beginSeq(self: *Self, len: ?usize) !void;
pub fn endSeq(self: *Self) !void;

pub fn beginStruct(self: *Self, comptime T: type, field_count: usize) !void;
pub fn emitFieldName(self: *Self, name: []const u8) !void;
pub fn endStruct(self: *Self) !void;
```

These optional methods let a sink use type-directed encodings when the
format benefits from them:

```zig
pub fn beginOptional(self: *Self, present: bool) !void;
pub fn emitEnum(self: *Self, comptime T: type, value: T) !void;
pub fn beginArray(self: *Self, comptime T: type, len: usize) !void;
pub fn beginSlice(self: *Self, comptime Child: type, len: usize) !void;
```

If `beginOptional` is absent, non-null optionals are serialized as their
child value and null optionals call `emitNull`. If `emitEnum` is absent,
enum values call `emitEnumTag`. If `beginArray` or `beginSlice` are absent,
arrays and non-string slices call `beginSeq`.

Custom type hooks participate in the same protocol. A type-level hook has
the shape `pub fn zerdeWrite(value: T, encoder: anytype) !void`; a field hook
has the shape `pub fn write(value: FieldType, encoder: anytype) !void`.
`serialize` does not call `finish`; callers that use a format encoder should
call that encoder's `finish` after the root value has been written.

## Functions

- [serialize](#fn-serialize)

<a id="fn-serialize"></a>

## serialize

Serializes `value` by walking its Zig type at comptime and calling methods
on `encoder`'s structural protocol.

Supported types currently include bools, integers, floats, strings, arrays,
slices, optionals, enums, plain structs, and tagged unions.

```zig
pub fn serialize(value: anytype, encoder: anytype) !void
```

