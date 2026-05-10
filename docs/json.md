# json

## Navigation

- [API Index](README.md)
- Previous: [root](root.md)
- Next: [serialize](serialize.md)

JSON format support.

## Functions

- [write](#fn-write)
- [writeWithOptions](#fn-writewithoptions)
- [encoder](#fn-encoder)
- [encoderWithOptions](#fn-encoderwithoptions)
- [read](#fn-read)
- [writeAlloc](#fn-writealloc)
- [writeAllocWithOptions](#fn-writeallocwithoptions)
- [readSlice](#fn-readslice)
- [decoder](#fn-decoder)

## Types

- [WriteOptions](#type-writeoptions)
- [Kind](#type-kind)
- [Decoder](#type-decoder)
- [Encoder](#type-encoder)

<a id="type-writeoptions"></a>

## WriteOptions

```zig
pub const WriteOptions = struct { ... };
```

JSON writer configuration.

### Fields

```zig
    pretty: bool = false
    indent: usize = 2
```


<a id="fn-write"></a>

## write

```zig
pub fn write(writer: *std.Io.Writer, value: anytype) !void
```

Serializes `value` as compact JSON to `writer`.

Strings must be valid UTF-8. Non-finite floats are rejected because JSON has
no representation for NaN or infinity.

<a id="fn-writewithoptions"></a>

## writeWithOptions

```zig
pub fn writeWithOptions(writer: *std.Io.Writer, value: anytype, options: WriteOptions) !void
```

References: [`WriteOptions`](#type-writeoptions)

Serializes `value` as JSON to `writer` with explicit writer options.

<a id="fn-encoder"></a>

## encoder

```zig
pub fn encoder(writer: *std.Io.Writer) Encoder
```

References: [`Encoder`](#type-encoder)

Returns a low-level JSON encoder for use with `zerde.serialize` or custom
serialization code.

Call `Encoder.finish` after writing the root value to validate that a
complete JSON document was produced.

<a id="fn-encoderwithoptions"></a>

## encoderWithOptions

```zig
pub fn encoderWithOptions(writer: *std.Io.Writer, options: WriteOptions) Encoder
```

References: [`WriteOptions`](#type-writeoptions), [`Encoder`](#type-encoder)

Returns a low-level JSON encoder with explicit writer options.

<a id="fn-read"></a>

## read

```zig
pub fn read(comptime T: type, allocator: std.mem.Allocator, reader: *std.Io.Reader) !T
```

Deserializes JSON from `reader` into `T`.

<a id="fn-writealloc"></a>

## writeAlloc

```zig
pub fn writeAlloc(allocator: std.mem.Allocator, value: anytype) ![]u8
```

Serializes `value` as compact JSON and returns allocator-owned bytes.

The caller owns the returned slice and must free it with `allocator.free`.

<a id="fn-writeallocwithoptions"></a>

## writeAllocWithOptions

```zig
pub fn writeAllocWithOptions(allocator: std.mem.Allocator, value: anytype, options: WriteOptions) ![]u8
```

References: [`WriteOptions`](#type-writeoptions)

Serializes `value` as JSON with explicit writer options and returns
allocator-owned bytes.

<a id="fn-readslice"></a>

## readSlice

```zig
pub fn readSlice(comptime T: type, allocator: std.mem.Allocator, input: []const u8) !T
```

Deserializes JSON from `input` into `T`.

<a id="fn-decoder"></a>

## decoder

```zig
pub fn decoder(reader: *std.Io.Reader, allocator: std.mem.Allocator) Decoder
```

References: [`Decoder`](#type-decoder)

Returns a low-level JSON decoder for use with `zerde.deserialize` or custom
deserialization code.

<a id="type-kind"></a>

## Kind

```zig
pub const Kind = enum { ... };
```

JSON value kinds reported by `Decoder.peek`.

<a id="type-decoder"></a>

## Decoder

```zig
pub const Decoder = struct { ... };
```

Low-level JSON decoder used by the generic deserializer.

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

<a id="type-encoder"></a>

## Encoder

```zig
pub const Encoder = struct { ... };
```

Low-level JSON encoder used by the generic serializer.

The encoder owns no memory. It writes directly to the supplied
`std.Io.Writer`, tracks container state for comma insertion, validates UTF-8
strings, rejects non-finite floats, and enforces a fixed nesting limit.

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

Emits the JSON `null` value.

<a id="fn-encoder-emitbool"></a>

### Encoder.emitBool

```zig
pub fn emitBool(self: *Self, value: bool) !void
```

Emits a JSON boolean value.

<a id="fn-encoder-emitint"></a>

### Encoder.emitInt

```zig
pub fn emitInt(self: *Self, value: anytype) !void
```

Emits a JSON integer value.

<a id="fn-encoder-emitfloat"></a>

### Encoder.emitFloat

```zig
pub fn emitFloat(self: *Self, value: anytype) !void
```

Emits a JSON number from a finite float.

<a id="fn-encoder-emitstring"></a>

### Encoder.emitString

```zig
pub fn emitString(self: *Self, value: []const u8) !void
```

Emits a JSON string after validating that `value` is valid UTF-8.

<a id="fn-encoder-emitbytes"></a>

### Encoder.emitBytes

```zig
pub fn emitBytes(self: *Self, value: []const u8) !void
```

Emits raw bytes as a base64 JSON string.

<a id="fn-encoder-beginseq"></a>

### Encoder.beginSeq

```zig
pub fn beginSeq(self: *Self, len: ?usize) !void
```

Begins a JSON array.

`len` is accepted for the generic encoder protocol but is not required
by JSON output.

<a id="fn-encoder-endseq"></a>

### Encoder.endSeq

```zig
pub fn endSeq(self: *Self) !void
```

Ends the current JSON array.

<a id="fn-encoder-beginstruct"></a>

### Encoder.beginStruct

```zig
pub fn beginStruct(self: *Self, comptime T: type, field_count: usize) !void
```

Begins a JSON object for a Zig struct.

`T` and `field_count` are accepted for the generic encoder protocol but
are not required by JSON output.

<a id="fn-encoder-emitfieldname"></a>

### Encoder.emitFieldName

```zig
pub fn emitFieldName(self: *Self, name: []const u8) !void
```

Emits a JSON object field name after validating that `name` is valid UTF-8.

<a id="fn-encoder-endstruct"></a>

### Encoder.endStruct

```zig
pub fn endStruct(self: *Self) !void
```

Ends the current JSON object.

<a id="fn-encoder-emitenumtag"></a>

### Encoder.emitEnumTag

```zig
pub fn emitEnumTag(self: *Self, tag: []const u8) !void
```

Emits an enum tag as a JSON string.

<a id="fn-encoder-finish"></a>

### Encoder.finish

```zig
pub fn finish(self: *Self) !void
```

Verifies that exactly one complete JSON root value has been emitted.

This catches incomplete custom encoder usage, such as an unclosed array
or an object field name without a following value.

