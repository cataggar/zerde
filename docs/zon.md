# zon

## Navigation

- [API Index](README.md)
- Previous: [msgpack](msgpack.md)
- Next: [binary](binary.md)

## Overview

Zig Object Notation format support.

## Functions

- [write](#fn-write)
- [writeWithOptions](#fn-writewithoptions)
- [writeAlloc](#fn-writealloc)
- [writeAllocWithOptions](#fn-writeallocwithoptions)
- [encoder](#fn-encoder)
- [encoderWithOptions](#fn-encoderwithoptions)
- [read](#fn-read)
- [readSlice](#fn-readslice)
- [decoder](#fn-decoder)

## Types

- [WriteOptions](#type-writeoptions)
- [Kind](#type-kind)
- [Encoder](#type-encoder)
- [Decoder](#type-decoder)

<a id="type-writeoptions"></a>

## WriteOptions

ZON writer configuration.

```zig
pub const WriteOptions = struct {
    pretty: bool = false,
    indent: usize = 4,
};
```

<a id="fn-write"></a>

## write

Serializes `value` as compact ZON to `writer`.

```zig
pub fn write(writer: *std.Io.Writer, value: anytype) !void
```

<a id="fn-writewithoptions"></a>

## writeWithOptions

Serializes `value` as ZON to `writer` with explicit writer options.

```zig
pub fn writeWithOptions(writer: *std.Io.Writer, value: anytype, options: WriteOptions) !void
```

References: [`WriteOptions`](#type-writeoptions)

<a id="fn-writealloc"></a>

## writeAlloc

Serializes `value` as ZON and returns allocator-owned bytes.

```zig
pub fn writeAlloc(allocator: std.mem.Allocator, value: anytype) ![]u8
```

<a id="fn-writeallocwithoptions"></a>

## writeAllocWithOptions

Serializes `value` as ZON with explicit writer options and returns allocator-owned bytes.

```zig
pub fn writeAllocWithOptions(allocator: std.mem.Allocator, value: anytype, options: WriteOptions) ![]u8
```

References: [`WriteOptions`](#type-writeoptions)

<a id="fn-encoder"></a>

## encoder

Returns a low-level ZON encoder for use with `zerde.serialize`.

```zig
pub fn encoder(writer: *std.Io.Writer) Encoder
```

References: [`Encoder`](#type-encoder)

<a id="fn-encoderwithoptions"></a>

## encoderWithOptions

Returns a low-level ZON encoder with explicit writer options.

```zig
pub fn encoderWithOptions(writer: *std.Io.Writer, options: WriteOptions) Encoder
```

References: [`WriteOptions`](#type-writeoptions), [`Encoder`](#type-encoder)

<a id="fn-read"></a>

## read

Deserializes ZON from `reader` into `T`.

```zig
pub fn read(comptime T: type, allocator: std.mem.Allocator, reader: *std.Io.Reader) !T
```

<a id="fn-readslice"></a>

## readSlice

Deserializes ZON from `input` into `T`.

```zig
pub fn readSlice(comptime T: type, allocator: std.mem.Allocator, input: []const u8) !T
```

<a id="fn-decoder"></a>

## decoder

Returns a low-level ZON decoder for use with `zerde.deserialize`.

```zig
pub fn decoder(reader: *std.Io.Reader, allocator: std.mem.Allocator) Decoder
```

References: [`Decoder`](#type-decoder)

<a id="type-kind"></a>

## Kind

ZON value kinds reported by `Decoder.peek`.

```zig
pub const Kind = enum {};
```

<a id="type-encoder"></a>

## Encoder

Low-level ZON encoder used by the generic serializer.

```zig
pub const Encoder = struct {
    writer: *std.Io.Writer,
    options: WriteOptions = .{},
    stack: [max_depth]Frame = undefined,
    stack_len: usize = 0,
    root_count: usize = 0,
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
- [beginSeq](#fn-encoder-beginseq)
- [endSeq](#fn-encoder-endseq)
- [beginStruct](#fn-encoder-beginstruct)
- [emitFieldName](#fn-encoder-emitfieldname)
- [endStruct](#fn-encoder-endstruct)
- [finish](#fn-encoder-finish)

<a id="fn-encoder-emitnull"></a>

### Encoder.emitNull

Emits a ZON null value.

```zig
pub fn emitNull(self: *Self) !void
```

<a id="fn-encoder-emitbool"></a>

### Encoder.emitBool

Emits a ZON boolean value.

```zig
pub fn emitBool(self: *Self, value: bool) !void
```

<a id="fn-encoder-emitint"></a>

### Encoder.emitInt

Emits a ZON integer value.

```zig
pub fn emitInt(self: *Self, value: anytype) !void
```

<a id="fn-encoder-emitfloat"></a>

### Encoder.emitFloat

Emits a ZON floating-point value.

```zig
pub fn emitFloat(self: *Self, value: anytype) !void
```

<a id="fn-encoder-emitstring"></a>

### Encoder.emitString

Emits a ZON string value.

```zig
pub fn emitString(self: *Self, value: []const u8) !void
```

<a id="fn-encoder-emitbytes"></a>

### Encoder.emitBytes

Emits raw bytes as a base64 ZON string.

```zig
pub fn emitBytes(self: *Self, value: []const u8) !void
```

<a id="fn-encoder-emitenum"></a>

### Encoder.emitEnum

Emits a ZON enum literal for `value`.

```zig
pub fn emitEnum(self: *Self, comptime T: type, value: T) !void
```

<a id="fn-encoder-emitenumtag"></a>

### Encoder.emitEnumTag

Emits a ZON enum literal by tag name.

```zig
pub fn emitEnumTag(self: *Self, tag: []const u8) !void
```

<a id="fn-encoder-beginseq"></a>

### Encoder.beginSeq

Begins a ZON array literal.

```zig
pub fn beginSeq(self: *Self, len: ?usize) !void
```

<a id="fn-encoder-endseq"></a>

### Encoder.endSeq

Ends the current ZON array literal.

```zig
pub fn endSeq(self: *Self) !void
```

<a id="fn-encoder-beginstruct"></a>

### Encoder.beginStruct

Begins a ZON struct literal.

```zig
pub fn beginStruct(self: *Self, comptime T: type, field_count: usize) !void
```

<a id="fn-encoder-emitfieldname"></a>

### Encoder.emitFieldName

Emits the next ZON struct field name.

```zig
pub fn emitFieldName(self: *Self, name: []const u8) !void
```

<a id="fn-encoder-endstruct"></a>

### Encoder.endStruct

Ends the current ZON struct literal.

```zig
pub fn endStruct(self: *Self) !void
```

<a id="fn-encoder-finish"></a>

### Encoder.finish

Verifies that the ZON document was completely written.

```zig
pub fn finish(self: *Self) !void
```

<a id="type-decoder"></a>

## Decoder

Low-level ZON decoder used by the generic deserializer.

```zig
pub const Decoder = struct {
    reader: *std.Io.Reader,
    allocator: std.mem.Allocator,
    stack: [max_depth]Frame = undefined,
    stack_len: usize = 0,
};
```

### Nested Declarations

- [peek](#fn-decoder-peek)
- [readNull](#fn-decoder-readnull)
- [readBool](#fn-decoder-readbool)
- [readInt](#fn-decoder-readint)
- [readFloat](#fn-decoder-readfloat)
- [readString](#fn-decoder-readstring)
- [readEnum](#fn-decoder-readenum)
- [readEnumTag](#fn-decoder-readenumtag)
- [beginSeq](#fn-decoder-beginseq)
- [hasNextSeqElem](#fn-decoder-hasnextseqelem)
- [endSeq](#fn-decoder-endseq)
- [beginStruct](#fn-decoder-beginstruct)
- [beginStructEvent](#fn-decoder-beginstructevent)
- [nextField](#fn-decoder-nextfield)
- [endStruct](#fn-decoder-endstruct)
- [skipValue](#fn-decoder-skipvalue)
- [finish](#fn-decoder-finish)

<a id="fn-decoder-peek"></a>

### Decoder.peek

Returns the kind of the next ZON value.

```zig
pub fn peek(self: *Self) !Kind
```

References: [`Kind`](#type-kind)

<a id="fn-decoder-readnull"></a>

### Decoder.readNull

Reads a ZON null value.

```zig
pub fn readNull(self: *Self) !void
```

<a id="fn-decoder-readbool"></a>

### Decoder.readBool

Reads a ZON boolean value.

```zig
pub fn readBool(self: *Self) !bool
```

<a id="fn-decoder-readint"></a>

### Decoder.readInt

Reads a ZON integer into `T`.

```zig
pub fn readInt(self: *Self, comptime T: type) !T
```

<a id="fn-decoder-readfloat"></a>

### Decoder.readFloat

Reads a ZON number into floating-point type `T`.

```zig
pub fn readFloat(self: *Self, comptime T: type) !T
```

<a id="fn-decoder-readstring"></a>

### Decoder.readString

Reads a ZON string as allocator-owned UTF-8 bytes.

```zig
pub fn readString(self: *Self, allocator: std.mem.Allocator) ![]u8
```

<a id="fn-decoder-readenum"></a>

### Decoder.readEnum

Reads a ZON enum literal into `T`.

```zig
pub fn readEnum(self: *Self, comptime T: type) !T
```

<a id="fn-decoder-readenumtag"></a>

### Decoder.readEnumTag

Reads a ZON enum literal tag as allocator-owned bytes for event consumers.

```zig
pub fn readEnumTag(self: *Self, allocator: std.mem.Allocator) ![]u8
```

<a id="fn-decoder-beginseq"></a>

### Decoder.beginSeq

Begins reading a ZON array literal.

```zig
pub fn beginSeq(self: *Self) !?usize
```

<a id="fn-decoder-hasnextseqelem"></a>

### Decoder.hasNextSeqElem

Returns whether the current ZON array has another element.

```zig
pub fn hasNextSeqElem(self: *Self) !bool
```

<a id="fn-decoder-endseq"></a>

### Decoder.endSeq

Ends the current ZON array literal.

```zig
pub fn endSeq(self: *Self) !void
```

<a id="fn-decoder-beginstruct"></a>

### Decoder.beginStruct

Begins reading a ZON struct literal.

```zig
pub fn beginStruct(self: *Self, comptime T: type) !void
```

<a id="fn-decoder-beginstructevent"></a>

### Decoder.beginStructEvent

Begins reading a ZON struct literal for event consumers. ZON does not
expose the field count before the literal has been read.

```zig
pub fn beginStructEvent(self: *Self) !?usize
```

<a id="fn-decoder-nextfield"></a>

### Decoder.nextField

Returns the next struct field name as allocator-owned bytes, or null when done.

```zig
pub fn nextField(self: *Self) !?[]u8
```

<a id="fn-decoder-endstruct"></a>

### Decoder.endStruct

Ends the current ZON struct literal.

```zig
pub fn endStruct(self: *Self) !void
```

<a id="fn-decoder-skipvalue"></a>

### Decoder.skipValue

Skips one complete ZON value.

```zig
pub fn skipValue(self: *Self) anyerror!void
```

<a id="fn-decoder-finish"></a>

### Decoder.finish

Verifies that the ZON document was completely read.

```zig
pub fn finish(self: *Self) !void
```

