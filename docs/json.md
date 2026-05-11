# json

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

JSON writer configuration.

```zig
pub const WriteOptions = struct {
    pretty: bool = false,
    indent: usize = 2,
};
```

<a id="fn-write"></a>

## write

Serializes `value` as compact JSON to `writer`.

Strings must be valid UTF-8. Non-finite floats are rejected because JSON has
no representation for NaN or infinity.

```zig
pub fn write(writer: *std.Io.Writer, value: anytype) !void
```

<a id="fn-writewithoptions"></a>

## writeWithOptions

Serializes `value` as JSON to `writer` with explicit writer options.

```zig
pub fn writeWithOptions(allocator: std.mem.Allocator, writer: *std.Io.Writer, value: anytype, options: WriteOptions) !void
```

References: [`WriteOptions`](#type-writeoptions)

<a id="fn-encoder"></a>

## encoder

Returns a low-level JSON encoder for use with `zerde.serialize` or custom
serialization code.

Call `Encoder.finish` after writing the root value to validate that a
complete JSON document was produced.

```zig
pub fn encoder(writer: *std.Io.Writer) Encoder
```

References: [`Encoder`](#type-encoder)

<a id="fn-encoderwithoptions"></a>

## encoderWithOptions

Returns a low-level JSON encoder with explicit writer options.

```zig
pub fn encoderWithOptions(writer: *std.Io.Writer, options: WriteOptions) Encoder
```

References: [`WriteOptions`](#type-writeoptions), [`Encoder`](#type-encoder)

<a id="fn-read"></a>

## read

Deserializes JSON from `reader` into `T`.

```zig
pub fn read(comptime T: type, allocator: std.mem.Allocator, reader: *std.Io.Reader) !T
```

<a id="fn-writealloc"></a>

## writeAlloc

Serializes `value` as compact JSON and returns allocator-owned bytes.

The caller owns the returned slice and must free it with `allocator.free`.

```zig
pub fn writeAlloc(allocator: std.mem.Allocator, value: anytype) ![]u8
```

<a id="fn-writeallocwithoptions"></a>

## writeAllocWithOptions

Serializes `value` as JSON with explicit writer options and returns
allocator-owned bytes.

```zig
pub fn writeAllocWithOptions(allocator: std.mem.Allocator, value: anytype, options: WriteOptions) ![]u8
```

References: [`WriteOptions`](#type-writeoptions)

<a id="fn-readslice"></a>

## readSlice

Deserializes JSON from `input` into `T`.

```zig
pub fn readSlice(comptime T: type, allocator: std.mem.Allocator, input: []const u8) !T
```

<a id="fn-decoder"></a>

## decoder

Returns a low-level JSON decoder for use with `zerde.deserialize` or custom
deserialization code.

```zig
pub fn decoder(reader: *std.Io.Reader, allocator: std.mem.Allocator) Decoder
```

References: [`Decoder`](#type-decoder)

<a id="type-kind"></a>

## Kind

JSON value kinds reported by `Decoder.peek`.

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

Low-level JSON decoder used by the generic deserializer.

```zig
pub const Decoder = struct {
    reader: *std.Io.Reader,
    allocator: std.mem.Allocator,
    stack: [max_depth]Frame = undefined,
    stack_len: usize = 0,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [peek](#fn-decoder-peek) | `self: *Self` | `!Kind` | Returns the kind of the next JSON value. |
| [readNull](#fn-decoder-readnull) | `self: *Self` | `!void` | Reads a JSON null value. |
| [readBool](#fn-decoder-readbool) | `self: *Self` | `!bool` | Reads a JSON boolean value. |
| [readInt](#fn-decoder-readint) | `self: *Self, comptime T: type` | `!T` | Reads a JSON integer into &#96;T&#96;. |
| [readFloat](#fn-decoder-readfloat) | `self: *Self, comptime T: type` | `!T` | Reads a JSON number into floating-point type &#96;T&#96;. |
| [readString](#fn-decoder-readstring) | `self: *Self, allocator: std.mem.Allocator` | `![]u8` | Reads a JSON string as allocator-owned UTF-8 bytes. |
| [beginSeq](#fn-decoder-beginseq) | `self: *Self` | `!?usize` | Begins reading a JSON array. |
| [hasNextSeqElem](#fn-decoder-hasnextseqelem) | `self: *Self` | `!bool` | Returns whether the current JSON array has another element. |
| [endSeq](#fn-decoder-endseq) | `self: *Self` | `!void` | Ends the current JSON array. |
| [beginStruct](#fn-decoder-beginstruct) | `self: *Self, comptime T: type` | `!void` | Begins reading a JSON object. |
| [beginStructEvent](#fn-decoder-beginstructevent) | `self: *Self` | `!?usize` | Begins reading a JSON object for event consumers. JSON does not expose the object field count before the object has been read. |
| [nextField](#fn-decoder-nextfield) | `self: *Self` | `!?[]u8` | Returns the next object field name as allocator-owned bytes, or null when done. |
| [endStruct](#fn-decoder-endstruct) | `self: *Self` | `!void` | Ends the current JSON object. |
| [skipValue](#fn-decoder-skipvalue) | `self: *Self` | `!void` | Skips one complete JSON value. |
| [finish](#fn-decoder-finish) | `self: *Self` | `!void` | Verifies that the JSON document was completely read. |

<a id="fn-decoder-peek"></a>

### Decoder.peek

Returns the kind of the next JSON value.

```zig
pub fn peek(self: *Self) !Kind
```

References: [`Kind`](#type-kind)

<a id="fn-decoder-readnull"></a>

### Decoder.readNull

Reads a JSON null value.

```zig
pub fn readNull(self: *Self) !void
```

<a id="fn-decoder-readbool"></a>

### Decoder.readBool

Reads a JSON boolean value.

```zig
pub fn readBool(self: *Self) !bool
```

<a id="fn-decoder-readint"></a>

### Decoder.readInt

Reads a JSON integer into `T`.

```zig
pub fn readInt(self: *Self, comptime T: type) !T
```

<a id="fn-decoder-readfloat"></a>

### Decoder.readFloat

Reads a JSON number into floating-point type `T`.

```zig
pub fn readFloat(self: *Self, comptime T: type) !T
```

<a id="fn-decoder-readstring"></a>

### Decoder.readString

Reads a JSON string as allocator-owned UTF-8 bytes.

```zig
pub fn readString(self: *Self, allocator: std.mem.Allocator) ![]u8
```

<a id="fn-decoder-beginseq"></a>

### Decoder.beginSeq

Begins reading a JSON array.

```zig
pub fn beginSeq(self: *Self) !?usize
```

<a id="fn-decoder-hasnextseqelem"></a>

### Decoder.hasNextSeqElem

Returns whether the current JSON array has another element.

```zig
pub fn hasNextSeqElem(self: *Self) !bool
```

<a id="fn-decoder-endseq"></a>

### Decoder.endSeq

Ends the current JSON array.

```zig
pub fn endSeq(self: *Self) !void
```

<a id="fn-decoder-beginstruct"></a>

### Decoder.beginStruct

Begins reading a JSON object.

```zig
pub fn beginStruct(self: *Self, comptime T: type) !void
```

<a id="fn-decoder-beginstructevent"></a>

### Decoder.beginStructEvent

Begins reading a JSON object for event consumers. JSON does not expose
the object field count before the object has been read.

```zig
pub fn beginStructEvent(self: *Self) !?usize
```

<a id="fn-decoder-nextfield"></a>

### Decoder.nextField

Returns the next object field name as allocator-owned bytes, or null when done.

```zig
pub fn nextField(self: *Self) !?[]u8
```

<a id="fn-decoder-endstruct"></a>

### Decoder.endStruct

Ends the current JSON object.

```zig
pub fn endStruct(self: *Self) !void
```

<a id="fn-decoder-skipvalue"></a>

### Decoder.skipValue

Skips one complete JSON value.

```zig
pub fn skipValue(self: *Self) !void
```

<a id="fn-decoder-finish"></a>

### Decoder.finish

Verifies that the JSON document was completely read.

```zig
pub fn finish(self: *Self) !void
```

<a id="type-encoder"></a>

## Encoder

Low-level JSON encoder used by the generic serializer.

The encoder owns no memory. It writes directly to the supplied
`std.Io.Writer`, tracks container state for comma insertion, validates UTF-8
strings, rejects non-finite floats, and enforces a fixed nesting limit.

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

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [emitNull](#fn-encoder-emitnull) | `self: *Self` | `!void` | Emits the JSON &#96;null&#96; value. |
| [emitBool](#fn-encoder-emitbool) | `self: *Self, value: bool` | `!void` | Emits a JSON boolean value. |
| [emitInt](#fn-encoder-emitint) | `self: *Self, value: anytype` | `!void` | Emits a JSON integer value. |
| [emitFloat](#fn-encoder-emitfloat) | `self: *Self, value: anytype` | `!void` | Emits a JSON number from a finite float. |
| [emitString](#fn-encoder-emitstring) | `self: *Self, value: []const u8` | `!void` | Emits a JSON string after validating that &#96;value&#96; is valid UTF-8. |
| [emitBytes](#fn-encoder-emitbytes) | `self: *Self, value: []const u8` | `!void` | Emits raw bytes as a base64 JSON string. |
| [beginSeq](#fn-encoder-beginseq) | `self: *Self, len: ?usize` | `!void` | Begins a JSON array. |
| [endSeq](#fn-encoder-endseq) | `self: *Self` | `!void` | Ends the current JSON array. |
| [beginStruct](#fn-encoder-beginstruct) | `self: *Self, comptime T: type, field_count: usize` | `!void` | Begins a JSON object for a Zig struct. |
| [emitFieldName](#fn-encoder-emitfieldname) | `self: *Self, name: []const u8` | `!void` | Emits a JSON object field name after validating that &#96;name&#96; is valid UTF-8. |
| [endStruct](#fn-encoder-endstruct) | `self: *Self` | `!void` | Ends the current JSON object. |
| [emitEnumTag](#fn-encoder-emitenumtag) | `self: *Self, tag: []const u8` | `!void` | Emits an enum tag as a JSON string. |
| [finish](#fn-encoder-finish) | `self: *Self` | `!void` | Verifies that exactly one complete JSON root value has been emitted. |

<a id="fn-encoder-emitnull"></a>

### Encoder.emitNull

Emits the JSON `null` value.

```zig
pub fn emitNull(self: *Self) !void
```

<a id="fn-encoder-emitbool"></a>

### Encoder.emitBool

Emits a JSON boolean value.

```zig
pub fn emitBool(self: *Self, value: bool) !void
```

<a id="fn-encoder-emitint"></a>

### Encoder.emitInt

Emits a JSON integer value.

```zig
pub fn emitInt(self: *Self, value: anytype) !void
```

<a id="fn-encoder-emitfloat"></a>

### Encoder.emitFloat

Emits a JSON number from a finite float.

```zig
pub fn emitFloat(self: *Self, value: anytype) !void
```

<a id="fn-encoder-emitstring"></a>

### Encoder.emitString

Emits a JSON string after validating that `value` is valid UTF-8.

```zig
pub fn emitString(self: *Self, value: []const u8) !void
```

<a id="fn-encoder-emitbytes"></a>

### Encoder.emitBytes

Emits raw bytes as a base64 JSON string.

```zig
pub fn emitBytes(self: *Self, value: []const u8) !void
```

<a id="fn-encoder-beginseq"></a>

### Encoder.beginSeq

Begins a JSON array.

`len` is accepted for the generic encoder protocol but is not required
by JSON output.

```zig
pub fn beginSeq(self: *Self, len: ?usize) !void
```

<a id="fn-encoder-endseq"></a>

### Encoder.endSeq

Ends the current JSON array.

```zig
pub fn endSeq(self: *Self) !void
```

<a id="fn-encoder-beginstruct"></a>

### Encoder.beginStruct

Begins a JSON object for a Zig struct.

`T` and `field_count` are accepted for the generic encoder protocol but
are not required by JSON output.

```zig
pub fn beginStruct(self: *Self, comptime T: type, field_count: usize) !void
```

<a id="fn-encoder-emitfieldname"></a>

### Encoder.emitFieldName

Emits a JSON object field name after validating that `name` is valid UTF-8.

```zig
pub fn emitFieldName(self: *Self, name: []const u8) !void
```

<a id="fn-encoder-endstruct"></a>

### Encoder.endStruct

Ends the current JSON object.

```zig
pub fn endStruct(self: *Self) !void
```

<a id="fn-encoder-emitenumtag"></a>

### Encoder.emitEnumTag

Emits an enum tag as a JSON string.

```zig
pub fn emitEnumTag(self: *Self, tag: []const u8) !void
```

<a id="fn-encoder-finish"></a>

### Encoder.finish

Verifies that exactly one complete JSON root value has been emitted.

This catches incomplete custom encoder usage, such as an unclosed array
or an object field name without a following value.

```zig
pub fn finish(self: *Self) !void
```

