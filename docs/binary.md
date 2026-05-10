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

```zig
pub const Encoder = struct {
    writer: *std.Io.Writer,
    options: Options,
    stack: [max_depth]Frame = undefined,
    stack_len: usize = 0,
};
```

### Nested Declarations

- [emitNull](#fn-encoder-emitnull)
- [emitBool](#fn-encoder-emitbool)
- [emitInt](#fn-encoder-emitint)
- [emitFloat](#fn-encoder-emitfloat)
- [emitString](#fn-encoder-emitstring)
- [emitBytes](#fn-encoder-emitbytes)
- [emitEnum](#fn-encoder-emitenum)
- [emitEnumTag](#fn-encoder-emitenumtag)
- [beginOptional](#fn-encoder-beginoptional)
- [beginArray](#fn-encoder-beginarray)
- [beginSlice](#fn-encoder-beginslice)
- [beginSeq](#fn-encoder-beginseq)
- [endSeq](#fn-encoder-endseq)
- [beginStruct](#fn-encoder-beginstruct)
- [emitFieldName](#fn-encoder-emitfieldname)
- [endStruct](#fn-encoder-endstruct)
- [finish](#fn-encoder-finish)

<a id="fn-encoder-emitnull"></a>

### Encoder.emitNull

```zig
pub fn emitNull(self: *Self) !void
```

<a id="fn-encoder-emitbool"></a>

### Encoder.emitBool

```zig
pub fn emitBool(self: *Self, value: bool) !void
```

<a id="fn-encoder-emitint"></a>

### Encoder.emitInt

```zig
pub fn emitInt(self: *Self, value: anytype) !void
```

<a id="fn-encoder-emitfloat"></a>

### Encoder.emitFloat

```zig
pub fn emitFloat(self: *Self, value: anytype) !void
```

<a id="fn-encoder-emitstring"></a>

### Encoder.emitString

```zig
pub fn emitString(self: *Self, value: []const u8) !void
```

<a id="fn-encoder-emitbytes"></a>

### Encoder.emitBytes

```zig
pub fn emitBytes(self: *Self, value: []const u8) !void
```

<a id="fn-encoder-emitenum"></a>

### Encoder.emitEnum

```zig
pub fn emitEnum(self: *Self, comptime T: type, value: T) !void
```

<a id="fn-encoder-emitenumtag"></a>

### Encoder.emitEnumTag

```zig
pub fn emitEnumTag(self: *Self, tag: []const u8) !void
```

<a id="fn-encoder-beginoptional"></a>

### Encoder.beginOptional

```zig
pub fn beginOptional(self: *Self, present: bool) !void
```

<a id="fn-encoder-beginarray"></a>

### Encoder.beginArray

```zig
pub fn beginArray(self: *Self, comptime T: type, len: usize) !void
```

<a id="fn-encoder-beginslice"></a>

### Encoder.beginSlice

```zig
pub fn beginSlice(self: *Self, comptime Child: type, len: usize) !void
```

<a id="fn-encoder-beginseq"></a>

### Encoder.beginSeq

```zig
pub fn beginSeq(self: *Self, len: ?usize) !void
```

<a id="fn-encoder-endseq"></a>

### Encoder.endSeq

```zig
pub fn endSeq(self: *Self) !void
```

<a id="fn-encoder-beginstruct"></a>

### Encoder.beginStruct

```zig
pub fn beginStruct(self: *Self, comptime T: type, field_count: usize) !void
```

<a id="fn-encoder-emitfieldname"></a>

### Encoder.emitFieldName

```zig
pub fn emitFieldName(self: *Self, name: []const u8) !void
```

<a id="fn-encoder-endstruct"></a>

### Encoder.endStruct

```zig
pub fn endStruct(self: *Self) !void
```

<a id="fn-encoder-finish"></a>

### Encoder.finish

```zig
pub fn finish(self: *Self) !void
```

<a id="type-kind"></a>

## Kind

```zig
pub const Kind = enum {};
```

<a id="type-decoder"></a>

## Decoder

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

- [peek](#fn-decoder-peek)
- [readNull](#fn-decoder-readnull)
- [readBool](#fn-decoder-readbool)
- [readInt](#fn-decoder-readint)
- [readFloat](#fn-decoder-readfloat)
- [readString](#fn-decoder-readstring)
- [readBytes](#fn-decoder-readbytes)
- [readEnum](#fn-decoder-readenum)
- [readOptionalPresent](#fn-decoder-readoptionalpresent)
- [beginArray](#fn-decoder-beginarray)
- [beginSeq](#fn-decoder-beginseq)
- [hasNextSeqElem](#fn-decoder-hasnextseqelem)
- [endSeq](#fn-decoder-endseq)
- [beginStruct](#fn-decoder-beginstruct)
- [nextField](#fn-decoder-nextfield)
- [endStruct](#fn-decoder-endstruct)
- [skipValue](#fn-decoder-skipvalue)
- [finish](#fn-decoder-finish)

<a id="fn-decoder-peek"></a>

### Decoder.peek

```zig
pub fn peek(self: *Self) !Kind
```

References: [`Kind`](#type-kind)

<a id="fn-decoder-readnull"></a>

### Decoder.readNull

```zig
pub fn readNull(self: *Self) !void
```

<a id="fn-decoder-readbool"></a>

### Decoder.readBool

```zig
pub fn readBool(self: *Self) !bool
```

<a id="fn-decoder-readint"></a>

### Decoder.readInt

```zig
pub fn readInt(self: *Self, comptime T: type) !T
```

<a id="fn-decoder-readfloat"></a>

### Decoder.readFloat

```zig
pub fn readFloat(self: *Self, comptime T: type) !T
```

<a id="fn-decoder-readstring"></a>

### Decoder.readString

```zig
pub fn readString(self: *Self, allocator: std.mem.Allocator) ![]u8
```

<a id="fn-decoder-readbytes"></a>

### Decoder.readBytes

```zig
pub fn readBytes(self: *Self, allocator: std.mem.Allocator) ![]u8
```

<a id="fn-decoder-readenum"></a>

### Decoder.readEnum

```zig
pub fn readEnum(self: *Self, comptime T: type) !T
```

<a id="fn-decoder-readoptionalpresent"></a>

### Decoder.readOptionalPresent

```zig
pub fn readOptionalPresent(self: *Self) !bool
```

<a id="fn-decoder-beginarray"></a>

### Decoder.beginArray

```zig
pub fn beginArray(self: *Self, comptime T: type) !?usize
```

<a id="fn-decoder-beginseq"></a>

### Decoder.beginSeq

```zig
pub fn beginSeq(self: *Self) !?usize
```

<a id="fn-decoder-hasnextseqelem"></a>

### Decoder.hasNextSeqElem

```zig
pub fn hasNextSeqElem(self: *Self) !bool
```

<a id="fn-decoder-endseq"></a>

### Decoder.endSeq

```zig
pub fn endSeq(self: *Self) !void
```

<a id="fn-decoder-beginstruct"></a>

### Decoder.beginStruct

```zig
pub fn beginStruct(self: *Self, comptime T: type) !void
```

<a id="fn-decoder-nextfield"></a>

### Decoder.nextField

```zig
pub fn nextField(self: *Self) !?[]u8
```

<a id="fn-decoder-endstruct"></a>

### Decoder.endStruct

```zig
pub fn endStruct(self: *Self) !void
```

<a id="fn-decoder-skipvalue"></a>

### Decoder.skipValue

```zig
pub fn skipValue(self: *Self) !void
```

<a id="fn-decoder-finish"></a>

### Decoder.finish

```zig
pub fn finish(self: *Self) !void
```

