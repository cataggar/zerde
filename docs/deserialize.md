# deserialize

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

Generic type-directed deserialization traversal.

`deserialize` walks a requested Zig type at comptime and pulls the matching
shape from a structural source. Format decoders are structural sources when
they can expose enough shape information for typed traversal.

A source used with all supported Zerde type shapes should expose this core
interface:

```zig
pub fn peek(self: *Self) !Kind;
pub fn readNull(self: *Self) !void;
pub fn readBool(self: *Self) !bool;
pub fn readInt(self: *Self, comptime T: type) !T;
pub fn readFloat(self: *Self, comptime T: type) !T;
pub fn readString(self: *Self, allocator: std.mem.Allocator) ![]u8;

pub fn beginSeq(self: *Self) !?usize;
pub fn hasNextSeqElem(self: *Self) !bool;
pub fn endSeq(self: *Self) !void;

pub fn beginStruct(self: *Self, comptime T: type) !void;
pub fn nextField(self: *Self) !?[]u8;
pub fn endStruct(self: *Self) !void;

pub fn skipValue(self: *Self) !void;
```

`readString`, `readBytes`, and `nextField` return allocator-owned slices;
`deserialize` frees field names after matching them and transfers string or
byte values into the returned Zig value. `beginSeq` may return a known length
or `null`; callers still use `hasNextSeqElem` to consume elements. `peek`
only needs to expose the tags required by the decoder's behavior, but
sources without `readOptionalPresent` must be able to report `.null` for
null optionals.

These optional methods let a source use type-directed encodings when the
format benefits from them:

```zig
pub fn readOptionalPresent(self: *Self) !bool;
pub fn readEnum(self: *Self, comptime T: type) !T;
pub fn readBytes(self: *Self, allocator: std.mem.Allocator) ![]u8;
pub fn beginArray(self: *Self, comptime T: type) !?usize;
```

If `readOptionalPresent` is absent, optionals use `peek` and `readNull`. If
`readEnum` is absent, enums read an allocator-owned string tag with
`readString`. If `readBytes` is absent, byte fields read a base64 string and
decode it. If `beginArray` is absent, arrays call `beginSeq`.

Custom type hooks participate in the same protocol:

```zig
pub fn zerdeRead(allocator: std.mem.Allocator, decoder: anytype) !T;
pub fn read(comptime T: type, allocator: std.mem.Allocator, decoder: anytype) !T;
```

`deserialize` does not call `finish`; callers that use a format decoder
should call that decoder's `finish` after the root value has been read.

## Functions

- [deserialize](#fn-deserialize)

<a id="fn-deserialize"></a>

## deserialize

Deserializes a value of type `T` by walking `T` at comptime and calling
methods on `decoder`'s structural protocol.

```zig
pub fn deserialize(comptime T: type, allocator: std.mem.Allocator, decoder: anytype) !T
```

