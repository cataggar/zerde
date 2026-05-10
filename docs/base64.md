# base64

## Navigation

- [API Index](README.md)
- Previous: [serialize](serialize.md)
- Next: [containers](containers.md)

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
pub const Bytes = struct { ... };
```

### Fields

```zig
    value: []const u8
```


### Nested Declarations

- [slice](#fn-bytes-slice)
- [len](#fn-bytes-len)
- [isEmpty](#fn-bytes-isempty)

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

