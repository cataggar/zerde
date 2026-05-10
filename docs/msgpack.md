# msgpack

## Navigation

- [API Index](README.md)
- Previous: [datetime](datetime.md)
- Next: [zon](zon.md)

## Overview

MessagePack format support.

## Functions

- [write](#fn-write)
- [writeWithOptions](#fn-writewithoptions)
- [writeAlloc](#fn-writealloc)
- [writeAllocWithOptions](#fn-writeallocwithoptions)
- [read](#fn-read)
- [readSlice](#fn-readslice)
- [encoder](#fn-encoder)
- [decoder](#fn-decoder)

## Types

- [WriteOptions](#type-writeoptions)
- [Extension](#type-extension)
- [Kind](#type-kind)
- [Encoder](#type-encoder)
- [Decoder](#type-decoder)

<a id="type-writeoptions"></a>

## WriteOptions

MessagePack writer configuration. Reserved for future profile options.

```zig
pub const WriteOptions = struct {};
```

<a id="type-extension"></a>

## Extension

Opaque MessagePack extension value for low-level custom hooks.

```zig
pub const Extension = struct {
    /// Application or predefined extension type identifier.
    type_id: i8,
    /// Allocator-owned extension payload bytes.
    data: []u8,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [deinit](#fn-extension-deinit) | `self: Extension, allocator: std.mem.Allocator` | `void` | Frees the extension payload returned by &#96;Decoder.readExtension&#96;. |

<a id="fn-extension-deinit"></a>

### Extension.deinit

Frees the extension payload returned by `Decoder.readExtension`.

```zig
pub fn deinit(self: Extension, allocator: std.mem.Allocator) void
```

References: [`Extension`](#type-extension)

<a id="fn-write"></a>

## write

Serializes `value` as MessagePack to `writer`.

```zig
pub fn write(writer: *std.Io.Writer, value: anytype) !void
```

<a id="fn-writewithoptions"></a>

## writeWithOptions

Serializes `value` as MessagePack to `writer` with explicit options.

```zig
pub fn writeWithOptions(writer: *std.Io.Writer, value: anytype, options: WriteOptions) !void
```

References: [`WriteOptions`](#type-writeoptions)

<a id="fn-writealloc"></a>

## writeAlloc

Serializes `value` as MessagePack and returns allocator-owned bytes.

```zig
pub fn writeAlloc(allocator: std.mem.Allocator, value: anytype) ![]u8
```

<a id="fn-writeallocwithoptions"></a>

## writeAllocWithOptions

Serializes `value` as MessagePack with explicit options and returns allocator-owned bytes.

```zig
pub fn writeAllocWithOptions(allocator: std.mem.Allocator, value: anytype, options: WriteOptions) ![]u8
```

References: [`WriteOptions`](#type-writeoptions)

<a id="fn-read"></a>

## read

Deserializes MessagePack from `reader` into `T`.

```zig
pub fn read(comptime T: type, allocator: std.mem.Allocator, reader: *std.Io.Reader) !T
```

<a id="fn-readslice"></a>

## readSlice

Deserializes MessagePack from `input` into `T`.

```zig
pub fn readSlice(comptime T: type, allocator: std.mem.Allocator, input: []const u8) !T
```

<a id="fn-encoder"></a>

## encoder

Returns a low-level MessagePack encoder for use with `zerde.serialize`.

```zig
pub fn encoder(writer: *std.Io.Writer) Encoder
```

References: [`Encoder`](#type-encoder)

<a id="fn-decoder"></a>

## decoder

Returns a low-level MessagePack decoder for use with `zerde.deserialize`.

```zig
pub fn decoder(reader: *std.Io.Reader, allocator: std.mem.Allocator) Decoder
```

References: [`Decoder`](#type-decoder)

<a id="type-kind"></a>

## Kind

MessagePack value kinds reported by `Decoder.peek`.

```zig
pub const Kind = enum {
    /// MessagePack nil.
    null,
    /// MessagePack boolean.
    bool,
    /// MessagePack integer.
    int,
    /// MessagePack 32-bit or 64-bit float.
    float,
    /// MessagePack str value.
    string,
    /// MessagePack bin value.
    binary,
    /// MessagePack array value.
    seq,
    /// MessagePack map value.
    struct_,
    /// MessagePack extension value.
    extension,
};
```

<a id="type-encoder"></a>

## Encoder

Low-level MessagePack encoder used by the generic serializer.

```zig
pub const Encoder = struct {
    /// Destination writer receiving encoded MessagePack bytes.
    writer: *std.Io.Writer,
    /// Container stack used to validate nested arrays and maps.
    stack: [max_depth]Frame = undefined,
    /// Number of active container frames in `stack`.
    stack_len: usize = 0,
    /// Number of root values emitted so far.
    root_count: usize = 0,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [emitNull](#fn-encoder-emitnull) | `self: *Self` | `!void` | Emits the MessagePack nil value. |
| [emitBool](#fn-encoder-emitbool) | `self: *Self, value: bool` | `!void` | Emits a MessagePack boolean value. |
| [emitInt](#fn-encoder-emitint) | `self: *Self, value: anytype` | `!void` | Emits an integer using the smallest valid MessagePack integer format. |
| [emitFloat](#fn-encoder-emitfloat) | `self: *Self, value: anytype` | `!void` | Emits a 32-bit or 64-bit MessagePack float. |
| [emitString](#fn-encoder-emitstring) | `self: *Self, value: []const u8` | `!void` | Emits a UTF-8 string with the MessagePack str family. |
| [emitBytes](#fn-encoder-emitbytes) | `self: *Self, value: []const u8` | `!void` | Emits raw bytes with the MessagePack bin family. |
| [emitEnumTag](#fn-encoder-emitenumtag) | `self: *Self, tag: []const u8` | `!void` | Emits an enum tag as a MessagePack string. |
| [beginSeq](#fn-encoder-beginseq) | `self: *Self, len: ?usize` | `!void` | Begins a MessagePack array with a known element count. |
| [endSeq](#fn-encoder-endseq) | `self: *Self` | `!void` | Ends the current MessagePack array. |
| [beginStruct](#fn-encoder-beginstruct) | `self: *Self, comptime T: type, field_count: usize` | `!void` | Begins a MessagePack map for a struct value. |
| [emitFieldName](#fn-encoder-emitfieldname) | `self: *Self, name: []const u8` | `!void` | Emits the next MessagePack map key for a struct field. |
| [endStruct](#fn-encoder-endstruct) | `self: *Self` | `!void` | Ends the current MessagePack map for a struct value. |
| [emitExtension](#fn-encoder-emitextension) | `self: *Self, type_id: i8, data: []const u8` | `!void` | Emits a low-level MessagePack extension value for custom hooks. |
| [emitTimestamp](#fn-encoder-emittimestamp) | `self: *Self, value: Timestamp` | `!void` | Emits the predefined MessagePack timestamp extension type (-1). |
| [finish](#fn-encoder-finish) | `self: *Self` | `!void` | Verifies that exactly one complete MessagePack root value was emitted. |

<a id="fn-encoder-emitnull"></a>

### Encoder.emitNull

Emits the MessagePack nil value.

```zig
pub fn emitNull(self: *Self) !void
```

<a id="fn-encoder-emitbool"></a>

### Encoder.emitBool

Emits a MessagePack boolean value.

```zig
pub fn emitBool(self: *Self, value: bool) !void
```

<a id="fn-encoder-emitint"></a>

### Encoder.emitInt

Emits an integer using the smallest valid MessagePack integer format.

```zig
pub fn emitInt(self: *Self, value: anytype) !void
```

<a id="fn-encoder-emitfloat"></a>

### Encoder.emitFloat

Emits a 32-bit or 64-bit MessagePack float.

```zig
pub fn emitFloat(self: *Self, value: anytype) !void
```

<a id="fn-encoder-emitstring"></a>

### Encoder.emitString

Emits a UTF-8 string with the MessagePack str family.

```zig
pub fn emitString(self: *Self, value: []const u8) !void
```

<a id="fn-encoder-emitbytes"></a>

### Encoder.emitBytes

Emits raw bytes with the MessagePack bin family.

```zig
pub fn emitBytes(self: *Self, value: []const u8) !void
```

<a id="fn-encoder-emitenumtag"></a>

### Encoder.emitEnumTag

Emits an enum tag as a MessagePack string.

```zig
pub fn emitEnumTag(self: *Self, tag: []const u8) !void
```

<a id="fn-encoder-beginseq"></a>

### Encoder.beginSeq

Begins a MessagePack array with a known element count.

```zig
pub fn beginSeq(self: *Self, len: ?usize) !void
```

<a id="fn-encoder-endseq"></a>

### Encoder.endSeq

Ends the current MessagePack array.

```zig
pub fn endSeq(self: *Self) !void
```

<a id="fn-encoder-beginstruct"></a>

### Encoder.beginStruct

Begins a MessagePack map for a struct value.

```zig
pub fn beginStruct(self: *Self, comptime T: type, field_count: usize) !void
```

<a id="fn-encoder-emitfieldname"></a>

### Encoder.emitFieldName

Emits the next MessagePack map key for a struct field.

```zig
pub fn emitFieldName(self: *Self, name: []const u8) !void
```

<a id="fn-encoder-endstruct"></a>

### Encoder.endStruct

Ends the current MessagePack map for a struct value.

```zig
pub fn endStruct(self: *Self) !void
```

<a id="fn-encoder-emitextension"></a>

### Encoder.emitExtension

Emits a low-level MessagePack extension value for custom hooks.

```zig
pub fn emitExtension(self: *Self, type_id: i8, data: []const u8) !void
```

<a id="fn-encoder-emittimestamp"></a>

### Encoder.emitTimestamp

Emits the predefined MessagePack timestamp extension type (-1).

```zig
pub fn emitTimestamp(self: *Self, value: Timestamp) !void
```

<a id="fn-encoder-finish"></a>

### Encoder.finish

Verifies that exactly one complete MessagePack root value was emitted.

```zig
pub fn finish(self: *Self) !void
```

<a id="type-decoder"></a>

## Decoder

Low-level MessagePack decoder used by the generic deserializer.

```zig
pub const Decoder = struct {
    /// Source reader providing encoded MessagePack bytes.
    reader: *std.Io.Reader,
    /// Allocator used for owned strings, byte slices, and field names.
    allocator: std.mem.Allocator,
    /// Container stack used to validate nested arrays and maps.
    stack: [max_depth]Frame = undefined,
    /// Number of active container frames in `stack`.
    stack_len: usize = 0,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [peek](#fn-decoder-peek) | `self: *Self` | `!Kind` | Returns the kind of the next MessagePack value without consuming it. |
| [readNull](#fn-decoder-readnull) | `self: *Self` | `!void` | Reads a MessagePack nil value. |
| [readBool](#fn-decoder-readbool) | `self: *Self` | `!bool` | Reads a MessagePack boolean value. |
| [readInt](#fn-decoder-readint) | `self: *Self, comptime T: type` | `!T` | Reads a MessagePack integer and converts it to &#96;T&#96;. |
| [readFloat](#fn-decoder-readfloat) | `self: *Self, comptime T: type` | `!T` | Reads a MessagePack float, or an integer coerced to &#96;T&#96;. |
| [readString](#fn-decoder-readstring) | `self: *Self, allocator: std.mem.Allocator` | `![]u8` | Reads a MessagePack str value as allocator-owned UTF-8 bytes. |
| [readBytes](#fn-decoder-readbytes) | `self: *Self, allocator: std.mem.Allocator` | `![]u8` | Reads a MessagePack bin value, or a str value for compatibility, as owned bytes. |
| [beginSeq](#fn-decoder-beginseq) | `self: *Self` | `!?usize` | Begins reading a MessagePack array and returns its element count. |
| [hasNextSeqElem](#fn-decoder-hasnextseqelem) | `self: *Self` | `!bool` | Returns whether the current MessagePack array has another element. |
| [endSeq](#fn-decoder-endseq) | `self: *Self` | `!void` | Ends the current MessagePack array. |
| [beginStruct](#fn-decoder-beginstruct) | `self: *Self, comptime T: type` | `!void` | Begins reading a MessagePack map for a struct value. |
| [beginStructEvent](#fn-decoder-beginstructevent) | `self: *Self` | `!?usize` | Begins reading a MessagePack map for event consumers and returns its field count. |
| [nextField](#fn-decoder-nextfield) | `self: *Self` | `!?[]u8` | Reads the next MessagePack map key as an allocator-owned field name. |
| [endStruct](#fn-decoder-endstruct) | `self: *Self` | `!void` | Ends the current MessagePack map for a struct value. |
| [skipValue](#fn-decoder-skipvalue) | `self: *Self` | `!void` | Skips the next complete MessagePack value, including nested containers. |
| [readExtension](#fn-decoder-readextension) | `self: *Self, allocator: std.mem.Allocator` | `!Extension` | Reads a low-level MessagePack extension value. Caller owns &#96;data&#96;. |
| [readTimestamp](#fn-decoder-readtimestamp) | `self: *Self` | `!Timestamp` | Reads the predefined MessagePack timestamp extension type (-1). |
| [finish](#fn-decoder-finish) | `self: *Self` | `!void` | Verifies that the reader is at the end of a complete MessagePack document. |

<a id="fn-decoder-peek"></a>

### Decoder.peek

Returns the kind of the next MessagePack value without consuming it.

```zig
pub fn peek(self: *Self) !Kind
```

References: [`Kind`](#type-kind)

<a id="fn-decoder-readnull"></a>

### Decoder.readNull

Reads a MessagePack nil value.

```zig
pub fn readNull(self: *Self) !void
```

<a id="fn-decoder-readbool"></a>

### Decoder.readBool

Reads a MessagePack boolean value.

```zig
pub fn readBool(self: *Self) !bool
```

<a id="fn-decoder-readint"></a>

### Decoder.readInt

Reads a MessagePack integer and converts it to `T`.

```zig
pub fn readInt(self: *Self, comptime T: type) !T
```

<a id="fn-decoder-readfloat"></a>

### Decoder.readFloat

Reads a MessagePack float, or an integer coerced to `T`.

```zig
pub fn readFloat(self: *Self, comptime T: type) !T
```

<a id="fn-decoder-readstring"></a>

### Decoder.readString

Reads a MessagePack str value as allocator-owned UTF-8 bytes.

```zig
pub fn readString(self: *Self, allocator: std.mem.Allocator) ![]u8
```

<a id="fn-decoder-readbytes"></a>

### Decoder.readBytes

Reads a MessagePack bin value, or a str value for compatibility, as owned bytes.

```zig
pub fn readBytes(self: *Self, allocator: std.mem.Allocator) ![]u8
```

<a id="fn-decoder-beginseq"></a>

### Decoder.beginSeq

Begins reading a MessagePack array and returns its element count.

```zig
pub fn beginSeq(self: *Self) !?usize
```

<a id="fn-decoder-hasnextseqelem"></a>

### Decoder.hasNextSeqElem

Returns whether the current MessagePack array has another element.

```zig
pub fn hasNextSeqElem(self: *Self) !bool
```

<a id="fn-decoder-endseq"></a>

### Decoder.endSeq

Ends the current MessagePack array.

```zig
pub fn endSeq(self: *Self) !void
```

<a id="fn-decoder-beginstruct"></a>

### Decoder.beginStruct

Begins reading a MessagePack map for a struct value.

```zig
pub fn beginStruct(self: *Self, comptime T: type) !void
```

<a id="fn-decoder-beginstructevent"></a>

### Decoder.beginStructEvent

Begins reading a MessagePack map for event consumers and returns its
field count.

```zig
pub fn beginStructEvent(self: *Self) !?usize
```

<a id="fn-decoder-nextfield"></a>

### Decoder.nextField

Reads the next MessagePack map key as an allocator-owned field name.

```zig
pub fn nextField(self: *Self) !?[]u8
```

<a id="fn-decoder-endstruct"></a>

### Decoder.endStruct

Ends the current MessagePack map for a struct value.

```zig
pub fn endStruct(self: *Self) !void
```

<a id="fn-decoder-skipvalue"></a>

### Decoder.skipValue

Skips the next complete MessagePack value, including nested containers.

```zig
pub fn skipValue(self: *Self) !void
```

<a id="fn-decoder-readextension"></a>

### Decoder.readExtension

Reads a low-level MessagePack extension value. Caller owns `data`.

```zig
pub fn readExtension(self: *Self, allocator: std.mem.Allocator) !Extension
```

References: [`Extension`](#type-extension)

<a id="fn-decoder-readtimestamp"></a>

### Decoder.readTimestamp

Reads the predefined MessagePack timestamp extension type (-1).

```zig
pub fn readTimestamp(self: *Self) !Timestamp
```

<a id="fn-decoder-finish"></a>

### Decoder.finish

Verifies that the reader is at the end of a complete MessagePack document.

```zig
pub fn finish(self: *Self) !void
```

