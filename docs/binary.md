# binary

## Navigation

- [API Index](README.md)
- Previous: [zon](zon.md)
- Next: [csv](csv.md)

## Overview

Compact binary format support.

## Functions

- [write](#fn-write)
- [writeWithOptions](#fn-writewithoptions)
- [read](#fn-read)
- [readWithOptions](#fn-readwithoptions)
- [writeAlloc](#fn-writealloc)
- [writeAllocWithOptions](#fn-writeallocwithoptions)
- [readSlice](#fn-readslice)
- [readSliceWithOptions](#fn-readslicewithoptions)
- [encoder](#fn-encoder)
- [encoderWithOptions](#fn-encoderwithoptions)
- [decoder](#fn-decoder)

## Types

- [Options](#type-options)
- [Encoder](#type-encoder)
- [Kind](#type-kind)
- [Decoder](#type-decoder)

<a id="type-options"></a>

## Options

Binary format configuration.

```zig
pub const Options = struct {
    endian: std.builtin.Endian = .little,
};
```

<a id="fn-write"></a>

## write

Serializes `value` as compact binary to `writer`.

```zig
pub fn write(writer: *std.Io.Writer, value: anytype) !void
```

<a id="fn-writewithoptions"></a>

## writeWithOptions

Serializes `value` as compact binary to `writer` with explicit options.

```zig
pub fn writeWithOptions(writer: *std.Io.Writer, value: anytype, options: Options) !void
```

References: [`Options`](#type-options)

<a id="fn-read"></a>

## read

Deserializes binary data from `reader` into `T`.

```zig
pub fn read(comptime T: type, allocator: std.mem.Allocator, reader: *std.Io.Reader) !T
```

<a id="fn-readwithoptions"></a>

## readWithOptions

Deserializes binary data from `reader` into `T` with explicit options.

```zig
pub fn readWithOptions(comptime T: type, allocator: std.mem.Allocator, reader: *std.Io.Reader, options: Options) !T
```

References: [`Options`](#type-options)

<a id="fn-writealloc"></a>

## writeAlloc

Serializes `value` as binary and returns allocator-owned bytes.

```zig
pub fn writeAlloc(allocator: std.mem.Allocator, value: anytype) ![]u8
```

<a id="fn-writeallocwithoptions"></a>

## writeAllocWithOptions

Serializes `value` as binary with explicit options and returns allocator-owned bytes.

```zig
pub fn writeAllocWithOptions(allocator: std.mem.Allocator, value: anytype, options: Options) ![]u8
```

References: [`Options`](#type-options)

<a id="fn-readslice"></a>

## readSlice

Deserializes binary data from `input` into `T`.

```zig
pub fn readSlice(comptime T: type, allocator: std.mem.Allocator, input: []const u8) !T
```

<a id="fn-readslicewithoptions"></a>

## readSliceWithOptions

Deserializes binary data from `input` into `T` with explicit options.

```zig
pub fn readSliceWithOptions(comptime T: type, allocator: std.mem.Allocator, input: []const u8, options: Options) !T
```

References: [`Options`](#type-options)

<a id="fn-encoder"></a>

## encoder

Returns a low-level binary encoder for use with `zerde.serialize`.

```zig
pub fn encoder(writer: *std.Io.Writer) Encoder
```

References: [`Encoder`](#type-encoder)

<a id="fn-encoderwithoptions"></a>

## encoderWithOptions

Returns a low-level binary encoder with explicit options.

```zig
pub fn encoderWithOptions(writer: *std.Io.Writer, options: Options) Encoder
```

References: [`Options`](#type-options), [`Encoder`](#type-encoder)

<a id="fn-decoder"></a>

## decoder

Returns a low-level binary decoder for use with `zerde.deserialize`.

```zig
pub fn decoder(reader: *std.Io.Reader, allocator: std.mem.Allocator, options: Options) Decoder
```

References: [`Options`](#type-options), [`Decoder`](#type-decoder)

<a id="type-encoder"></a>

## Encoder

Low-level binary encoder used by the generic serializer.

```zig
pub const Encoder = struct {
    writer: *std.Io.Writer,
    options: Options,
    stack: [max_depth]Frame = undefined,
    stack_len: usize = 0,
};
```

### Nested Declarations

| Name | Signature | Return Type | Description |
| --- | --- | --- | --- |
| [emitNull](#fn-encoder-emitnull) | `pub fn emitNull(self: *Self) !void` | `!void` | Emits a null marker when required by the current binary context. |
| [emitBool](#fn-encoder-emitbool) | `pub fn emitBool(self: *Self, value: bool) !void` | `!void` | Emits a boolean as one byte. |
| [emitInt](#fn-encoder-emitint) | `pub fn emitInt(self: *Self, value: anytype) !void` | `!void` | Emits an integer using the configured byte order. |
| [emitFloat](#fn-encoder-emitfloat) | `pub fn emitFloat(self: *Self, value: anytype) !void` | `!void` | Emits a floating-point value as its raw IEEE bits. |
| [emitString](#fn-encoder-emitstring) | `pub fn emitString(self: *Self, value: []const u8) !void` | `!void` | Emits a length-prefixed UTF-8 string. |
| [emitBytes](#fn-encoder-emitbytes) | `pub fn emitBytes(self: *Self, value: []const u8) !void` | `!void` | Emits length-prefixed raw bytes. |
| [emitEnum](#fn-encoder-emitenum) | `pub fn emitEnum(self: *Self, comptime T: type, value: T) !void` | `!void` | Emits an enum value using the enum tag's integer storage size. |
| [emitEnumTag](#fn-encoder-emitenumtag) | `pub fn emitEnumTag(self: *Self, tag: []const u8) !void` | `!void` | Emits an enum tag by name. |
| [beginOptional](#fn-encoder-beginoptional) | `pub fn beginOptional(self: *Self, present: bool) !void` | `!void` | Emits the presence marker for an optional value. |
| [beginArray](#fn-encoder-beginarray) | `pub fn beginArray(self: *Self, comptime T: type, len: usize) !void` | `!void` | Begins a fixed-length array. |
| [beginSlice](#fn-encoder-beginslice) | `pub fn beginSlice(self: *Self, comptime Child: type, len: usize) !void` | `!void` | Begins a length-prefixed slice. |
| [beginSeq](#fn-encoder-beginseq) | `pub fn beginSeq(self: *Self, len: ?usize) !void` | `!void` | Begins a length-prefixed sequence. |
| [endSeq](#fn-encoder-endseq) | `pub fn endSeq(self: *Self) !void` | `!void` | Ends the current sequence. |
| [beginStruct](#fn-encoder-beginstruct) | `pub fn beginStruct(self: *Self, comptime T: type, field_count: usize) !void` | `!void` | Begins a struct or tagged union value. |
| [emitFieldName](#fn-encoder-emitfieldname) | `pub fn emitFieldName(self: *Self, name: []const u8) !void` | `!void` | Emits or handles the next struct field name. |
| [endStruct](#fn-encoder-endstruct) | `pub fn endStruct(self: *Self) !void` | `!void` | Ends the current struct or tagged union value. |
| [finish](#fn-encoder-finish) | `pub fn finish(self: *Self) !void` | `!void` | Verifies that the binary document was completely written. |

<a id="fn-encoder-emitnull"></a>

### Encoder.emitNull

Emits a null marker when required by the current binary context.

```zig
pub fn emitNull(self: *Self) !void
```

<a id="fn-encoder-emitbool"></a>

### Encoder.emitBool

Emits a boolean as one byte.

```zig
pub fn emitBool(self: *Self, value: bool) !void
```

<a id="fn-encoder-emitint"></a>

### Encoder.emitInt

Emits an integer using the configured byte order.

```zig
pub fn emitInt(self: *Self, value: anytype) !void
```

<a id="fn-encoder-emitfloat"></a>

### Encoder.emitFloat

Emits a floating-point value as its raw IEEE bits.

```zig
pub fn emitFloat(self: *Self, value: anytype) !void
```

<a id="fn-encoder-emitstring"></a>

### Encoder.emitString

Emits a length-prefixed UTF-8 string.

```zig
pub fn emitString(self: *Self, value: []const u8) !void
```

<a id="fn-encoder-emitbytes"></a>

### Encoder.emitBytes

Emits length-prefixed raw bytes.

```zig
pub fn emitBytes(self: *Self, value: []const u8) !void
```

<a id="fn-encoder-emitenum"></a>

### Encoder.emitEnum

Emits an enum value using the enum tag's integer storage size.

```zig
pub fn emitEnum(self: *Self, comptime T: type, value: T) !void
```

<a id="fn-encoder-emitenumtag"></a>

### Encoder.emitEnumTag

Emits an enum tag by name.

```zig
pub fn emitEnumTag(self: *Self, tag: []const u8) !void
```

<a id="fn-encoder-beginoptional"></a>

### Encoder.beginOptional

Emits the presence marker for an optional value.

```zig
pub fn beginOptional(self: *Self, present: bool) !void
```

<a id="fn-encoder-beginarray"></a>

### Encoder.beginArray

Begins a fixed-length array.

```zig
pub fn beginArray(self: *Self, comptime T: type, len: usize) !void
```

<a id="fn-encoder-beginslice"></a>

### Encoder.beginSlice

Begins a length-prefixed slice.

```zig
pub fn beginSlice(self: *Self, comptime Child: type, len: usize) !void
```

<a id="fn-encoder-beginseq"></a>

### Encoder.beginSeq

Begins a length-prefixed sequence.

```zig
pub fn beginSeq(self: *Self, len: ?usize) !void
```

<a id="fn-encoder-endseq"></a>

### Encoder.endSeq

Ends the current sequence.

```zig
pub fn endSeq(self: *Self) !void
```

<a id="fn-encoder-beginstruct"></a>

### Encoder.beginStruct

Begins a struct or tagged union value.

```zig
pub fn beginStruct(self: *Self, comptime T: type, field_count: usize) !void
```

<a id="fn-encoder-emitfieldname"></a>

### Encoder.emitFieldName

Emits or handles the next struct field name.

```zig
pub fn emitFieldName(self: *Self, name: []const u8) !void
```

<a id="fn-encoder-endstruct"></a>

### Encoder.endStruct

Ends the current struct or tagged union value.

```zig
pub fn endStruct(self: *Self) !void
```

<a id="fn-encoder-finish"></a>

### Encoder.finish

Verifies that the binary document was completely written.

```zig
pub fn finish(self: *Self) !void
```

<a id="type-kind"></a>

## Kind

Binary value kinds reported by `Decoder.peek`.

```zig
pub const Kind = enum {
    null,
    bool,
    int,
    float,
    string,
    seq,
    struct_,
};
```

<a id="type-decoder"></a>

## Decoder

Low-level binary decoder used by the generic deserializer.

```zig
pub const Decoder = struct {
    reader: *std.Io.Reader,
    allocator: std.mem.Allocator,
    options: Options,
    stack: [max_depth]Frame = undefined,
    stack_len: usize = 0,
    pending_string: ?[]const u8 = null,
};
```

### Nested Declarations

| Name | Signature | Return Type | Description |
| --- | --- | --- | --- |
| [peek](#fn-decoder-peek) | `pub fn peek(self: *Self) !Kind` | `!Kind` | Returns the next value kind when supported by the binary format. |
| [readNull](#fn-decoder-readnull) | `pub fn readNull(self: *Self) !void` | `!void` | Reads a null value. |
| [readBool](#fn-decoder-readbool) | `pub fn readBool(self: *Self) !bool` | `!bool` | Reads a boolean value. |
| [readInt](#fn-decoder-readint) | `pub fn readInt(self: *Self, comptime T: type) !T` | `!T` | Reads an integer using the configured byte order. |
| [readFloat](#fn-decoder-readfloat) | `pub fn readFloat(self: *Self, comptime T: type) !T` | `!T` | Reads a floating-point value from its raw IEEE bits. |
| [readString](#fn-decoder-readstring) | `pub fn readString(self: *Self, allocator: std.mem.Allocator) ![]u8` | `![]u8` | Reads a UTF-8 string as allocator-owned bytes. |
| [readBytes](#fn-decoder-readbytes) | `pub fn readBytes(self: *Self, allocator: std.mem.Allocator) ![]u8` | `![]u8` | Reads raw bytes into an allocator-owned slice. |
| [readEnum](#fn-decoder-readenum) | `pub fn readEnum(self: *Self, comptime T: type) !T` | `!T` | Reads an enum value using the enum tag's integer storage size. |
| [readOptionalPresent](#fn-decoder-readoptionalpresent) | `pub fn readOptionalPresent(self: *Self) !bool` | `!bool` | Reads and returns the optional presence marker. |
| [beginArray](#fn-decoder-beginarray) | `pub fn beginArray(self: *Self, comptime T: type) !?usize` | `!?usize` | Begins reading a fixed-length array. |
| [beginSeq](#fn-decoder-beginseq) | `pub fn beginSeq(self: *Self) !?usize` | `!?usize` | Begins reading a length-prefixed sequence. |
| [hasNextSeqElem](#fn-decoder-hasnextseqelem) | `pub fn hasNextSeqElem(self: *Self) !bool` | `!bool` | Returns whether the current sequence has another element. |
| [endSeq](#fn-decoder-endseq) | `pub fn endSeq(self: *Self) !void` | `!void` | Ends the current sequence. |
| [beginStruct](#fn-decoder-beginstruct) | `pub fn beginStruct(self: *Self, comptime T: type) !void` | `!void` | Begins reading a struct or tagged union value. |
| [nextField](#fn-decoder-nextfield) | `pub fn nextField(self: *Self) !?[]u8` | `!?[]u8` | Returns the next field name as allocator-owned bytes, or null when done. |
| [endStruct](#fn-decoder-endstruct) | `pub fn endStruct(self: *Self) !void` | `!void` | Ends the current struct or tagged union value. |
| [skipValue](#fn-decoder-skipvalue) | `pub fn skipValue(self: *Self) !void` | `!void` | Skips the next value when supported by the binary format. |
| [finish](#fn-decoder-finish) | `pub fn finish(self: *Self) !void` | `!void` | Verifies that the binary document was completely read. |

<a id="fn-decoder-peek"></a>

### Decoder.peek

Returns the next value kind when supported by the binary format.

```zig
pub fn peek(self: *Self) !Kind
```

References: [`Kind`](#type-kind)

<a id="fn-decoder-readnull"></a>

### Decoder.readNull

Reads a null value.

```zig
pub fn readNull(self: *Self) !void
```

<a id="fn-decoder-readbool"></a>

### Decoder.readBool

Reads a boolean value.

```zig
pub fn readBool(self: *Self) !bool
```

<a id="fn-decoder-readint"></a>

### Decoder.readInt

Reads an integer using the configured byte order.

```zig
pub fn readInt(self: *Self, comptime T: type) !T
```

<a id="fn-decoder-readfloat"></a>

### Decoder.readFloat

Reads a floating-point value from its raw IEEE bits.

```zig
pub fn readFloat(self: *Self, comptime T: type) !T
```

<a id="fn-decoder-readstring"></a>

### Decoder.readString

Reads a UTF-8 string as allocator-owned bytes.

```zig
pub fn readString(self: *Self, allocator: std.mem.Allocator) ![]u8
```

<a id="fn-decoder-readbytes"></a>

### Decoder.readBytes

Reads raw bytes into an allocator-owned slice.

```zig
pub fn readBytes(self: *Self, allocator: std.mem.Allocator) ![]u8
```

<a id="fn-decoder-readenum"></a>

### Decoder.readEnum

Reads an enum value using the enum tag's integer storage size.

```zig
pub fn readEnum(self: *Self, comptime T: type) !T
```

<a id="fn-decoder-readoptionalpresent"></a>

### Decoder.readOptionalPresent

Reads and returns the optional presence marker.

```zig
pub fn readOptionalPresent(self: *Self) !bool
```

<a id="fn-decoder-beginarray"></a>

### Decoder.beginArray

Begins reading a fixed-length array.

```zig
pub fn beginArray(self: *Self, comptime T: type) !?usize
```

<a id="fn-decoder-beginseq"></a>

### Decoder.beginSeq

Begins reading a length-prefixed sequence.

```zig
pub fn beginSeq(self: *Self) !?usize
```

<a id="fn-decoder-hasnextseqelem"></a>

### Decoder.hasNextSeqElem

Returns whether the current sequence has another element.

```zig
pub fn hasNextSeqElem(self: *Self) !bool
```

<a id="fn-decoder-endseq"></a>

### Decoder.endSeq

Ends the current sequence.

```zig
pub fn endSeq(self: *Self) !void
```

<a id="fn-decoder-beginstruct"></a>

### Decoder.beginStruct

Begins reading a struct or tagged union value.

```zig
pub fn beginStruct(self: *Self, comptime T: type) !void
```

<a id="fn-decoder-nextfield"></a>

### Decoder.nextField

Returns the next field name as allocator-owned bytes, or null when done.

```zig
pub fn nextField(self: *Self) !?[]u8
```

<a id="fn-decoder-endstruct"></a>

### Decoder.endStruct

Ends the current struct or tagged union value.

```zig
pub fn endStruct(self: *Self) !void
```

<a id="fn-decoder-skipvalue"></a>

### Decoder.skipValue

Skips the next value when supported by the binary format.

```zig
pub fn skipValue(self: *Self) !void
```

<a id="fn-decoder-finish"></a>

### Decoder.finish

Verifies that the binary document was completely read.

```zig
pub fn finish(self: *Self) !void
```

