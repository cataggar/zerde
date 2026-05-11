# base64

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

Base64 helpers used by byte-oriented serialization.

## Functions

- [writeEncoded](#fn-writeencoded)
- [encodeAlloc](#fn-encodealloc)
- [decodeAlloc](#fn-decodealloc)
- [decodeArray](#fn-decodearray)
- [isByteType](#fn-isbytetype)

## Types

- [Bytes](#type-bytes)

<a id="type-bytes"></a>

## Bytes

Wrapper type for serializing raw bytes distinctly from UTF-8 strings.

```zig
pub const Bytes = struct {
    value: []const u8,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [slice](#fn-bytes-slice) | `self: Bytes` | `[]const u8` | Returns the wrapped byte slice. |
| [len](#fn-bytes-len) | `self: Bytes` | `usize` | Returns the number of wrapped bytes. |
| [isEmpty](#fn-bytes-isempty) | `self: Bytes` | `bool` | Returns true when no bytes are wrapped. |

<a id="fn-bytes-slice"></a>

### Bytes.slice

Returns the wrapped byte slice.

```zig
pub fn slice(self: Bytes) []const u8
```

References: [`Bytes`](#type-bytes)

<a id="fn-bytes-len"></a>

### Bytes.len

Returns the number of wrapped bytes.

```zig
pub fn len(self: Bytes) usize
```

References: [`Bytes`](#type-bytes)

<a id="fn-bytes-isempty"></a>

### Bytes.isEmpty

Returns true when no bytes are wrapped.

```zig
pub fn isEmpty(self: Bytes) bool
```

References: [`Bytes`](#type-bytes)

<a id="fn-writeencoded"></a>

## writeEncoded

Writes standard padded RFC 4648 base64 for `bytes`.

```zig
pub fn writeEncoded(writer: *std.Io.Writer, bytes: []const u8) !void
```

<a id="fn-encodealloc"></a>

## encodeAlloc

Returns allocator-owned standard padded RFC 4648 base64 for `bytes`.

```zig
pub fn encodeAlloc(allocator: std.mem.Allocator, bytes: []const u8) ![]u8
```

<a id="fn-decodealloc"></a>

## decodeAlloc

Decodes standard padded RFC 4648 base64 into allocator-owned bytes.

```zig
pub fn decodeAlloc(allocator: std.mem.Allocator, encoded: []const u8) ![]u8
```

<a id="fn-decodearray"></a>

## decodeArray

Decodes standard padded RFC 4648 base64 into an exact fixed byte array type.

```zig
pub fn decodeArray(comptime T: type, encoded: []const u8) !T
```

<a id="fn-isbytetype"></a>

## isByteType

Returns true when `T` is a supported byte value for wrapper or metadata use.

```zig
pub fn isByteType(comptime T: type) bool
```

