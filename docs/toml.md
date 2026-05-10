# toml

## Navigation

- [API Index](README.md)
- Previous: [number](number.md)
- Next: [datetime](datetime.md)

TOML format support.

## Functions

- [write](#fn-write)
- [writeWithOptions](#fn-writewithoptions)
- [encoder](#fn-encoder)
- [read](#fn-read)
- [writeAlloc](#fn-writealloc)
- [writeAllocWithOptions](#fn-writeallocwithoptions)
- [readSlice](#fn-readslice)
- [decoder](#fn-decoder)

## Types

- [WriteLayout](#type-writelayout)
- [WriteOptions](#type-writeoptions)
- [Kind](#type-kind)
- [Encoder](#type-encoder)
- [Decoder](#type-decoder)

<a id="type-writelayout"></a>

## WriteLayout

```zig
pub const WriteLayout = enum { ... };
```

TOML writer configuration.

<a id="type-writeoptions"></a>

## WriteOptions

```zig
pub const WriteOptions = struct { ... };
```

### Fields

```zig
    layout: WriteLayout = .inline_tables
```


<a id="fn-write"></a>

## write

```zig
pub fn write(writer: *std.Io.Writer, value: anytype) !void
```

Serializes `value` as TOML to `writer` without heap allocation.

TOML documents are tables, so the root value must be a struct. TOML has no
null value; serializing null optionals returns `error.UnsupportedTomlNull`.

<a id="fn-writewithoptions"></a>

## writeWithOptions

```zig
pub fn writeWithOptions(allocator: std.mem.Allocator, writer: *std.Io.Writer, value: anytype, options: WriteOptions) !void
```

References: [`WriteOptions`](#type-writeoptions)

Serializes `value` as TOML to `writer` with explicit writer options.

Section layout requires `allocator` for a temporary document tree. Inline
`inline_tables` layout ignores `allocator` and streams directly.

<a id="fn-encoder"></a>

## encoder

```zig
pub fn encoder(writer: *std.Io.Writer) Encoder
```

References: [`Encoder`](#type-encoder)

Returns a low-level TOML encoder for use with `zerde.serialize` or custom
serialization code.

<a id="fn-read"></a>

## read

```zig
pub fn read(comptime T: type, allocator: std.mem.Allocator, reader: *std.Io.Reader) !T
```

Deserializes TOML from `reader` into `T`.

<a id="fn-writealloc"></a>

## writeAlloc

```zig
pub fn writeAlloc(allocator: std.mem.Allocator, value: anytype) ![]u8
```

Serializes `value` as TOML and returns allocator-owned bytes.

<a id="fn-writeallocwithoptions"></a>

## writeAllocWithOptions

```zig
pub fn writeAllocWithOptions(allocator: std.mem.Allocator, value: anytype, options: WriteOptions) ![]u8
```

References: [`WriteOptions`](#type-writeoptions)

Serializes `value` as TOML with explicit writer options and returns
allocator-owned bytes.

<a id="fn-readslice"></a>

## readSlice

```zig
pub fn readSlice(comptime T: type, allocator: std.mem.Allocator, input: []const u8) !T
```

Deserializes TOML from `input` into `T`.

<a id="fn-decoder"></a>

## decoder

```zig
pub fn decoder(reader: *std.Io.Reader, allocator: std.mem.Allocator) !Decoder
```

References: [`Decoder`](#type-decoder)

Returns a low-level TOML decoder for use with `zerde.deserialize` or custom
deserialization code. Call `Decoder.deinit` when done.

<a id="type-kind"></a>

## Kind

```zig
pub const Kind = enum { ... };
```

TOML value kinds reported by `Decoder.peek`.

<a id="type-encoder"></a>

## Encoder

```zig
pub const Encoder = struct { ... };
```

Low-level TOML encoder used by the generic serializer.

### Fields

```zig
    writer: *std.Io.Writer
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
- [emitDateTime](#fn-encoder-emitdatetime)
- [beginSeq](#fn-encoder-beginseq)
- [endSeq](#fn-encoder-endseq)
- [beginStruct](#fn-encoder-beginstruct)
- [emitFieldName](#fn-encoder-emitfieldname)
- [endStruct](#fn-encoder-endstruct)
- [emitEnumTag](#fn-encoder-emitenumtag)
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

<a id="fn-encoder-emitdatetime"></a>

### Encoder.emitDateTime

```zig
pub fn emitDateTime(self: *Self, comptime T: type, value: T) !void
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

<a id="fn-encoder-emitenumtag"></a>

### Encoder.emitEnumTag

```zig
pub fn emitEnumTag(self: *Self, tag: []const u8) !void
```

<a id="fn-encoder-finish"></a>

### Encoder.finish

```zig
pub fn finish(self: *Self) !void
```

<a id="type-decoder"></a>

## Decoder

```zig
pub const Decoder = struct { ... };
```

Low-level TOML decoder used by the generic deserializer.

### Fields

```zig
    allocator: std.mem.Allocator
    input: []u8
    root: Value
    stack: [max_depth]Frame = undefined
    stack_len: usize = 0
    pending_value: ?*const Value = null
    root_used: bool = false
```


### Nested Declarations

- [deinit](#fn-decoder-deinit)
- [peek](#fn-decoder-peek)
- [readNull](#fn-decoder-readnull)
- [readBool](#fn-decoder-readbool)
- [readInt](#fn-decoder-readint)
- [readFloat](#fn-decoder-readfloat)
- [readString](#fn-decoder-readstring)
- [readDateTime](#fn-decoder-readdatetime)
- [beginSeq](#fn-decoder-beginseq)
- [hasNextSeqElem](#fn-decoder-hasnextseqelem)
- [endSeq](#fn-decoder-endseq)
- [beginStruct](#fn-decoder-beginstruct)
- [nextField](#fn-decoder-nextfield)
- [endStruct](#fn-decoder-endstruct)
- [skipValue](#fn-decoder-skipvalue)
- [finish](#fn-decoder-finish)

<a id="fn-decoder-deinit"></a>

### Decoder.deinit

```zig
pub fn deinit(self: *Self) void
```

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

<a id="fn-decoder-readdatetime"></a>

### Decoder.readDateTime

```zig
pub fn readDateTime(self: *Self, comptime T: type) !T
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

