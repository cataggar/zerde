# zon

## Navigation

- [API Index](README.md)
- Previous: [msgpack](msgpack.md)
- Next: [binary](binary.md)

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
pub const WriteOptions = struct { ... };
```

### Fields

```zig
    pretty: bool = false
    indent: usize = 4
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
pub const Kind = enum { ... };
```

<a id="type-encoder"></a>

## Encoder

Low-level ZON encoder used by the generic serializer.

```zig
pub const Encoder = struct { ... };
```

### Fields

```zig
    writer: *std.Io.Writer
    options: WriteOptions = .{}
    stack: [max_depth]Frame = undefined
    stack_len: usize = 0
    root_count: usize = 0
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

<a id="type-decoder"></a>

## Decoder

Low-level ZON decoder used by the generic deserializer.

```zig
pub const Decoder = struct { ... };
```

### Fields

```zig
    reader: *std.Io.Reader
    allocator: std.mem.Allocator
    stack: [max_depth]Frame = undefined
    stack_len: usize = 0
```


### Nested Declarations

- [peek](#fn-decoder-peek)
- [readNull](#fn-decoder-readnull)
- [readBool](#fn-decoder-readbool)
- [readInt](#fn-decoder-readint)
- [readFloat](#fn-decoder-readfloat)
- [readString](#fn-decoder-readstring)
- [readEnum](#fn-decoder-readenum)
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

<a id="fn-decoder-readenum"></a>

### Decoder.readEnum

```zig
pub fn readEnum(self: *Self, comptime T: type) !T
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
pub fn skipValue(self: *Self) anyerror!void
```

<a id="fn-decoder-finish"></a>

### Decoder.finish

```zig
pub fn finish(self: *Self) !void
```

