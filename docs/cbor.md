# cbor

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

CBOR format support.

## Functions

- [write](#fn-write)
- [writeWithOptions](#fn-writewithoptions)
- [writeAlloc](#fn-writealloc)
- [writeAllocWithOptions](#fn-writeallocwithoptions)
- [read](#fn-read)
- [readSlice](#fn-readslice)
- [encoder](#fn-encoder)
- [eventEncoder](#fn-eventencoder)
- [eventEncoderWithOptions](#fn-eventencoderwithoptions)
- [decoder](#fn-decoder)

## Types

- [WriteOptions](#type-writeoptions)
- [Tag](#type-tag)
- [Kind](#type-kind)
- [Encoder](#type-encoder)
- [EventEncoder](#type-eventencoder)
- [Decoder](#type-decoder)

<a id="type-writeoptions"></a>

## WriteOptions

CBOR writer configuration.

```zig
pub const WriteOptions = struct {
    /// Buffer output and sort map entries by the bytewise order of their encoded keys.
    deterministic: bool = false,
};
```

<a id="type-tag"></a>

## Tag

CBOR semantic tag value for low-level/custom event use.

```zig
pub const Tag = struct {
    number: u64,
    value: events.Value,
};
```

<a id="fn-write"></a>

## write

Serializes `value` as CBOR to `writer`.

```zig
pub fn write(writer: *std.Io.Writer, value: anytype) !void
```

<a id="fn-writewithoptions"></a>

## writeWithOptions

Serializes `value` as CBOR to `writer` with explicit options.

```zig
pub fn writeWithOptions(allocator: std.mem.Allocator, writer: *std.Io.Writer, value: anytype, options: WriteOptions) !void
```

References: [`WriteOptions`](#type-writeoptions)

<a id="fn-writealloc"></a>

## writeAlloc

Serializes `value` as CBOR and returns allocator-owned bytes.

```zig
pub fn writeAlloc(allocator: std.mem.Allocator, value: anytype) ![]u8
```

<a id="fn-writeallocwithoptions"></a>

## writeAllocWithOptions

Serializes `value` as CBOR with explicit options and returns allocator-owned bytes.

```zig
pub fn writeAllocWithOptions(allocator: std.mem.Allocator, value: anytype, options: WriteOptions) ![]u8
```

References: [`WriteOptions`](#type-writeoptions)

<a id="fn-read"></a>

## read

Deserializes CBOR from `reader` into `T`.

```zig
pub fn read(comptime T: type, allocator: std.mem.Allocator, reader: *std.Io.Reader) !T
```

<a id="fn-readslice"></a>

## readSlice

Deserializes CBOR from `input` into `T`.

```zig
pub fn readSlice(comptime T: type, allocator: std.mem.Allocator, input: []const u8) !T
```

<a id="fn-encoder"></a>

## encoder

Returns a low-level CBOR encoder for use with `zerde.serialize`.

```zig
pub fn encoder(writer: *std.Io.Writer) Encoder
```

References: [`Encoder`](#type-encoder)

<a id="fn-eventencoder"></a>

## eventEncoder

Returns an allocator-backed event encoder for dynamic CBOR output.

```zig
pub fn eventEncoder(writer: *std.Io.Writer, allocator: std.mem.Allocator) EventEncoder
```

References: [`EventEncoder`](#type-eventencoder)

<a id="fn-eventencoderwithoptions"></a>

## eventEncoderWithOptions

Returns an allocator-backed event encoder with explicit options.

```zig
pub fn eventEncoderWithOptions(writer: *std.Io.Writer, allocator: std.mem.Allocator, options: WriteOptions) EventEncoder
```

References: [`WriteOptions`](#type-writeoptions), [`EventEncoder`](#type-eventencoder)

<a id="fn-decoder"></a>

## decoder

Returns a low-level CBOR decoder for use with `zerde.deserialize`.

```zig
pub fn decoder(reader: *std.Io.Reader, allocator: std.mem.Allocator) Decoder
```

References: [`Decoder`](#type-decoder)

<a id="type-kind"></a>

## Kind

CBOR value kinds reported by `Decoder.peek`.

```zig
pub const Kind = enum {
    null,
    bool,
    int,
    float,
    string,
    binary,
    extension,
    seq,
    struct_,
};
```

<a id="type-encoder"></a>

## Encoder

Low-level CBOR encoder used by the generic serializer.

```zig
pub const Encoder = struct {
    /// Destination writer receiving encoded CBOR bytes.
    writer: *std.Io.Writer,
    /// Container stack used to validate nested arrays and maps.
    stack: [max_depth]Frame = undefined,
    /// Number of active container frames in `stack`.
    stack_len: usize = 0,
    /// Number of root values emitted so far.
    root_count: usize = 0,
    /// Number of semantic tag heads emitted before the next value.
    pending_tags: usize = 0,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [emitNull](#fn-encoder-emitnull) | `self: *Self` | `!void` | Emits the CBOR null simple value. |
| [emitBool](#fn-encoder-emitbool) | `self: *Self, value: bool` | `!void` | Emits a CBOR boolean value. |
| [emitInt](#fn-encoder-emitint) | `self: *Self, value: anytype` | `!void` | Emits an integer using the shortest valid CBOR integer head. |
| [emitFloat](#fn-encoder-emitfloat) | `self: *Self, value: anytype` | `!void` | Emits a CBOR half, single, or double precision float. |
| [emitString](#fn-encoder-emitstring) | `self: *Self, value: []const u8` | `!void` | Emits a UTF-8 text string. |
| [emitBytes](#fn-encoder-emitbytes) | `self: *Self, value: []const u8` | `!void` | Emits raw bytes as a CBOR byte string. |
| [emitEnumTag](#fn-encoder-emitenumtag) | `self: *Self, tag: []const u8` | `!void` | Emits an enum tag as a CBOR text string. |
| [emitTag](#fn-encoder-emittag) | `self: *Self, tag: u64` | `!void` | Emits a CBOR semantic tag head. The next emitted value is the tagged value. |
| [emitSimple](#fn-encoder-emitsimple) | `self: *Self, value: u8` | `!void` | Emits an unmodeled CBOR simple value such as &#96;undefined&#96; (23). |
| [emitEventExtension](#fn-encoder-emiteventextension) | `self: *Self, extension: events.Extension` | `!void` | Emits a CBOR-compatible event extension value. |
| [beginSeq](#fn-encoder-beginseq) | `self: *Self, len: ?usize` | `!void` | Begins a definite-length CBOR array. |
| [beginArray](#fn-encoder-beginarray) | `self: *Self, comptime T: type, len: usize` | `!void` | Begins a definite-length CBOR array for a fixed Zig array. |
| [beginSlice](#fn-encoder-beginslice) | `self: *Self, comptime Child: type, len: usize` | `!void` | Begins a definite-length CBOR array for a Zig slice. |
| [endSeq](#fn-encoder-endseq) | `self: *Self` | `!void` | Ends the current CBOR array. |
| [beginStruct](#fn-encoder-beginstruct) | `self: *Self, comptime T: type, field_count: usize` | `!void` | Begins a definite-length CBOR map for a struct value. |
| [emitFieldName](#fn-encoder-emitfieldname) | `self: *Self, name: []const u8` | `!void` | Emits the next CBOR text map key for a struct field. |
| [endStruct](#fn-encoder-endstruct) | `self: *Self` | `!void` | Ends the current CBOR map for a struct value. |
| [finish](#fn-encoder-finish) | `self: *Self` | `!void` | Verifies that exactly one complete CBOR root value was emitted. |

<a id="fn-encoder-emitnull"></a>

### Encoder.emitNull

Emits the CBOR null simple value.

```zig
pub fn emitNull(self: *Self) !void
```

<a id="fn-encoder-emitbool"></a>

### Encoder.emitBool

Emits a CBOR boolean value.

```zig
pub fn emitBool(self: *Self, value: bool) !void
```

<a id="fn-encoder-emitint"></a>

### Encoder.emitInt

Emits an integer using the shortest valid CBOR integer head.

```zig
pub fn emitInt(self: *Self, value: anytype) !void
```

<a id="fn-encoder-emitfloat"></a>

### Encoder.emitFloat

Emits a CBOR half, single, or double precision float.

```zig
pub fn emitFloat(self: *Self, value: anytype) !void
```

<a id="fn-encoder-emitstring"></a>

### Encoder.emitString

Emits a UTF-8 text string.

```zig
pub fn emitString(self: *Self, value: []const u8) !void
```

<a id="fn-encoder-emitbytes"></a>

### Encoder.emitBytes

Emits raw bytes as a CBOR byte string.

```zig
pub fn emitBytes(self: *Self, value: []const u8) !void
```

<a id="fn-encoder-emitenumtag"></a>

### Encoder.emitEnumTag

Emits an enum tag as a CBOR text string.

```zig
pub fn emitEnumTag(self: *Self, tag: []const u8) !void
```

<a id="fn-encoder-emittag"></a>

### Encoder.emitTag

Emits a CBOR semantic tag head. The next emitted value is the tagged value.

```zig
pub fn emitTag(self: *Self, tag: u64) !void
```

<a id="fn-encoder-emitsimple"></a>

### Encoder.emitSimple

Emits an unmodeled CBOR simple value such as `undefined` (23).

```zig
pub fn emitSimple(self: *Self, value: u8) !void
```

<a id="fn-encoder-emiteventextension"></a>

### Encoder.emitEventExtension

Emits a CBOR-compatible event extension value.

```zig
pub fn emitEventExtension(self: *Self, extension: events.Extension) !void
```

References: [`events.Extension`](events.md#type-extension)

<a id="fn-encoder-beginseq"></a>

### Encoder.beginSeq

Begins a definite-length CBOR array.

```zig
pub fn beginSeq(self: *Self, len: ?usize) !void
```

<a id="fn-encoder-beginarray"></a>

### Encoder.beginArray

Begins a definite-length CBOR array for a fixed Zig array.

```zig
pub fn beginArray(self: *Self, comptime T: type, len: usize) !void
```

<a id="fn-encoder-beginslice"></a>

### Encoder.beginSlice

Begins a definite-length CBOR array for a Zig slice.

```zig
pub fn beginSlice(self: *Self, comptime Child: type, len: usize) !void
```

<a id="fn-encoder-endseq"></a>

### Encoder.endSeq

Ends the current CBOR array.

```zig
pub fn endSeq(self: *Self) !void
```

<a id="fn-encoder-beginstruct"></a>

### Encoder.beginStruct

Begins a definite-length CBOR map for a struct value.

```zig
pub fn beginStruct(self: *Self, comptime T: type, field_count: usize) !void
```

<a id="fn-encoder-emitfieldname"></a>

### Encoder.emitFieldName

Emits the next CBOR text map key for a struct field.

```zig
pub fn emitFieldName(self: *Self, name: []const u8) !void
```

<a id="fn-encoder-endstruct"></a>

### Encoder.endStruct

Ends the current CBOR map for a struct value.

```zig
pub fn endStruct(self: *Self) !void
```

<a id="fn-encoder-finish"></a>

### Encoder.finish

Verifies that exactly one complete CBOR root value was emitted.

```zig
pub fn finish(self: *Self) !void
```

<a id="type-eventencoder"></a>

## EventEncoder

Allocator-backed event encoder for dynamic CBOR output.

```zig
pub const EventEncoder = struct {
    writer: *std.Io.Writer,
    allocator: std.mem.Allocator,
    options: WriteOptions = .{},
    stack: [max_depth]Frame = undefined,
    stack_len: usize = 0,
    root: ?events.Value = null,
    pending_tags: std.ArrayList(u64) = .empty,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [deinit](#fn-eventencoder-deinit) | `self: *Self` | `void` | Frees any buffered event state not consumed by &#96;finish&#96;. |
| [emitNull](#fn-eventencoder-emitnull) | `self: *Self` | `!void` |  |
| [emitBool](#fn-eventencoder-emitbool) | `self: *Self, value: bool` | `!void` |  |
| [emitInt](#fn-eventencoder-emitint) | `self: *Self, value: anytype` | `!void` |  |
| [emitFloat](#fn-eventencoder-emitfloat) | `self: *Self, value: anytype` | `!void` |  |
| [emitString](#fn-eventencoder-emitstring) | `self: *Self, value: []const u8` | `!void` |  |
| [emitBytes](#fn-eventencoder-emitbytes) | `self: *Self, value: []const u8` | `!void` |  |
| [emitEnumTag](#fn-eventencoder-emitenumtag) | `self: *Self, tag: []const u8` | `!void` |  |
| [emitEventExtension](#fn-eventencoder-emiteventextension) | `self: *Self, extension: events.Extension` | `!void` |  |
| [emitTag](#fn-eventencoder-emittag) | `self: *Self, tag: u64` | `!void` |  |
| [emitSimple](#fn-eventencoder-emitsimple) | `self: *Self, value: u8` | `!void` |  |
| [beginSeq](#fn-eventencoder-beginseq) | `self: *Self, len: ?usize` | `!void` |  |
| [beginArray](#fn-eventencoder-beginarray) | `self: *Self, comptime T: type, len: usize` | `!void` |  |
| [beginSlice](#fn-eventencoder-beginslice) | `self: *Self, comptime Child: type, len: usize` | `!void` |  |
| [endSeq](#fn-eventencoder-endseq) | `self: *Self` | `!void` |  |
| [beginStruct](#fn-eventencoder-beginstruct) | `self: *Self, comptime T: type, field_count: usize` | `!void` |  |
| [beginStructEvent](#fn-eventencoder-beginstructevent) | `self: *Self, field_count: ?usize` | `!void` |  |
| [emitFieldName](#fn-eventencoder-emitfieldname) | `self: *Self, name: []const u8` | `!void` |  |
| [endStruct](#fn-eventencoder-endstruct) | `self: *Self` | `!void` |  |
| [finish](#fn-eventencoder-finish) | `self: *Self` | `!void` | Writes the buffered root value as definite-length CBOR. |

<a id="fn-eventencoder-deinit"></a>

### EventEncoder.deinit

Frees any buffered event state not consumed by `finish`.

```zig
pub fn deinit(self: *Self) void
```

<a id="fn-eventencoder-emitnull"></a>

### EventEncoder.emitNull

```zig
pub fn emitNull(self: *Self) !void
```

<a id="fn-eventencoder-emitbool"></a>

### EventEncoder.emitBool

```zig
pub fn emitBool(self: *Self, value: bool) !void
```

<a id="fn-eventencoder-emitint"></a>

### EventEncoder.emitInt

```zig
pub fn emitInt(self: *Self, value: anytype) !void
```

<a id="fn-eventencoder-emitfloat"></a>

### EventEncoder.emitFloat

```zig
pub fn emitFloat(self: *Self, value: anytype) !void
```

<a id="fn-eventencoder-emitstring"></a>

### EventEncoder.emitString

```zig
pub fn emitString(self: *Self, value: []const u8) !void
```

<a id="fn-eventencoder-emitbytes"></a>

### EventEncoder.emitBytes

```zig
pub fn emitBytes(self: *Self, value: []const u8) !void
```

<a id="fn-eventencoder-emitenumtag"></a>

### EventEncoder.emitEnumTag

```zig
pub fn emitEnumTag(self: *Self, tag: []const u8) !void
```

<a id="fn-eventencoder-emiteventextension"></a>

### EventEncoder.emitEventExtension

```zig
pub fn emitEventExtension(self: *Self, extension: events.Extension) !void
```

References: [`events.Extension`](events.md#type-extension)

<a id="fn-eventencoder-emittag"></a>

### EventEncoder.emitTag

```zig
pub fn emitTag(self: *Self, tag: u64) !void
```

<a id="fn-eventencoder-emitsimple"></a>

### EventEncoder.emitSimple

```zig
pub fn emitSimple(self: *Self, value: u8) !void
```

<a id="fn-eventencoder-beginseq"></a>

### EventEncoder.beginSeq

```zig
pub fn beginSeq(self: *Self, len: ?usize) !void
```

<a id="fn-eventencoder-beginarray"></a>

### EventEncoder.beginArray

```zig
pub fn beginArray(self: *Self, comptime T: type, len: usize) !void
```

<a id="fn-eventencoder-beginslice"></a>

### EventEncoder.beginSlice

```zig
pub fn beginSlice(self: *Self, comptime Child: type, len: usize) !void
```

<a id="fn-eventencoder-endseq"></a>

### EventEncoder.endSeq

```zig
pub fn endSeq(self: *Self) !void
```

<a id="fn-eventencoder-beginstruct"></a>

### EventEncoder.beginStruct

```zig
pub fn beginStruct(self: *Self, comptime T: type, field_count: usize) !void
```

<a id="fn-eventencoder-beginstructevent"></a>

### EventEncoder.beginStructEvent

```zig
pub fn beginStructEvent(self: *Self, field_count: ?usize) !void
```

<a id="fn-eventencoder-emitfieldname"></a>

### EventEncoder.emitFieldName

```zig
pub fn emitFieldName(self: *Self, name: []const u8) !void
```

<a id="fn-eventencoder-endstruct"></a>

### EventEncoder.endStruct

```zig
pub fn endStruct(self: *Self) !void
```

<a id="fn-eventencoder-finish"></a>

### EventEncoder.finish

Writes the buffered root value as definite-length CBOR.

```zig
pub fn finish(self: *Self) !void
```

<a id="type-decoder"></a>

## Decoder

Low-level CBOR decoder used by the generic deserializer.

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
| [peek](#fn-decoder-peek) | `self: *Self` | `!Kind` | Returns the kind of the next CBOR value without consuming it. |
| [readNull](#fn-decoder-readnull) | `self: *Self` | `!void` | Reads a CBOR null value. |
| [readBool](#fn-decoder-readbool) | `self: *Self` | `!bool` | Reads a CBOR boolean value. |
| [readInt](#fn-decoder-readint) | `self: *Self, comptime T: type` | `!T` | Reads a CBOR integer and converts it to &#96;T&#96;. |
| [readFloat](#fn-decoder-readfloat) | `self: *Self, comptime T: type` | `!T` | Reads a CBOR float, or an integer coerced to &#96;T&#96;. |
| [readString](#fn-decoder-readstring) | `self: *Self, allocator: std.mem.Allocator` | `![]u8` | Reads a CBOR text string as allocator-owned UTF-8 bytes. |
| [readBytes](#fn-decoder-readbytes) | `self: *Self, allocator: std.mem.Allocator` | `![]u8` | Reads a CBOR byte string as allocator-owned bytes. |
| [readTag](#fn-decoder-readtag) | `self: *Self` | `!u64` | Reads a CBOR semantic tag head and leaves the tagged value unread. |
| [readSimple](#fn-decoder-readsimple) | `self: *Self` | `!u8` | Reads an unmodeled CBOR simple value such as &#96;undefined&#96; (23). |
| [readEventExtension](#fn-decoder-readeventextension) | `self: *Self, allocator: std.mem.Allocator` | `anyerror!events.Extension` | Reads a CBOR tag or simple value as an event extension. |
| [beginSeq](#fn-decoder-beginseq) | `self: *Self` | `!?usize` | Begins reading a CBOR array and returns its element count when definite. |
| [hasNextSeqElem](#fn-decoder-hasnextseqelem) | `self: *Self` | `!bool` | Returns whether the current CBOR array has another element. |
| [endSeq](#fn-decoder-endseq) | `self: *Self` | `!void` | Ends the current CBOR array. |
| [beginStruct](#fn-decoder-beginstruct) | `self: *Self, comptime T: type` | `!void` | Begins reading a CBOR map for a struct value. |
| [beginStructEvent](#fn-decoder-beginstructevent) | `self: *Self` | `!?usize` | Begins reading a CBOR map for event consumers and returns its field count when definite. |
| [nextField](#fn-decoder-nextfield) | `self: *Self` | `!?[]u8` | Reads the next CBOR text map key as an allocator-owned field name. |
| [endStruct](#fn-decoder-endstruct) | `self: *Self` | `!void` | Ends the current CBOR map for a struct value. |
| [skipValue](#fn-decoder-skipvalue) | `self: *Self` | `anyerror!void` | Skips the next complete CBOR value, including nested containers and tags. |
| [finish](#fn-decoder-finish) | `self: *Self` | `!void` | Verifies that the reader is at the end of a complete CBOR document. |

<a id="fn-decoder-peek"></a>

### Decoder.peek

Returns the kind of the next CBOR value without consuming it.

```zig
pub fn peek(self: *Self) !Kind
```

References: [`Kind`](#type-kind)

<a id="fn-decoder-readnull"></a>

### Decoder.readNull

Reads a CBOR null value.

```zig
pub fn readNull(self: *Self) !void
```

<a id="fn-decoder-readbool"></a>

### Decoder.readBool

Reads a CBOR boolean value.

```zig
pub fn readBool(self: *Self) !bool
```

<a id="fn-decoder-readint"></a>

### Decoder.readInt

Reads a CBOR integer and converts it to `T`.

```zig
pub fn readInt(self: *Self, comptime T: type) !T
```

<a id="fn-decoder-readfloat"></a>

### Decoder.readFloat

Reads a CBOR float, or an integer coerced to `T`.

```zig
pub fn readFloat(self: *Self, comptime T: type) !T
```

<a id="fn-decoder-readstring"></a>

### Decoder.readString

Reads a CBOR text string as allocator-owned UTF-8 bytes.

```zig
pub fn readString(self: *Self, allocator: std.mem.Allocator) ![]u8
```

<a id="fn-decoder-readbytes"></a>

### Decoder.readBytes

Reads a CBOR byte string as allocator-owned bytes.

```zig
pub fn readBytes(self: *Self, allocator: std.mem.Allocator) ![]u8
```

<a id="fn-decoder-readtag"></a>

### Decoder.readTag

Reads a CBOR semantic tag head and leaves the tagged value unread.

```zig
pub fn readTag(self: *Self) !u64
```

<a id="fn-decoder-readsimple"></a>

### Decoder.readSimple

Reads an unmodeled CBOR simple value such as `undefined` (23).

```zig
pub fn readSimple(self: *Self) !u8
```

<a id="fn-decoder-readeventextension"></a>

### Decoder.readEventExtension

Reads a CBOR tag or simple value as an event extension.

```zig
pub fn readEventExtension(self: *Self, allocator: std.mem.Allocator) anyerror!events.Extension
```

References: [`events.Extension`](events.md#type-extension)

<a id="fn-decoder-beginseq"></a>

### Decoder.beginSeq

Begins reading a CBOR array and returns its element count when definite.

```zig
pub fn beginSeq(self: *Self) !?usize
```

<a id="fn-decoder-hasnextseqelem"></a>

### Decoder.hasNextSeqElem

Returns whether the current CBOR array has another element.

```zig
pub fn hasNextSeqElem(self: *Self) !bool
```

<a id="fn-decoder-endseq"></a>

### Decoder.endSeq

Ends the current CBOR array.

```zig
pub fn endSeq(self: *Self) !void
```

<a id="fn-decoder-beginstruct"></a>

### Decoder.beginStruct

Begins reading a CBOR map for a struct value.

```zig
pub fn beginStruct(self: *Self, comptime T: type) !void
```

<a id="fn-decoder-beginstructevent"></a>

### Decoder.beginStructEvent

Begins reading a CBOR map for event consumers and returns its field count when definite.

```zig
pub fn beginStructEvent(self: *Self) !?usize
```

<a id="fn-decoder-nextfield"></a>

### Decoder.nextField

Reads the next CBOR text map key as an allocator-owned field name.

```zig
pub fn nextField(self: *Self) !?[]u8
```

<a id="fn-decoder-endstruct"></a>

### Decoder.endStruct

Ends the current CBOR map for a struct value.

```zig
pub fn endStruct(self: *Self) !void
```

<a id="fn-decoder-skipvalue"></a>

### Decoder.skipValue

Skips the next complete CBOR value, including nested containers and tags.

```zig
pub fn skipValue(self: *Self) anyerror!void
```

<a id="fn-decoder-finish"></a>

### Decoder.finish

Verifies that the reader is at the end of a complete CBOR document.

```zig
pub fn finish(self: *Self) !void
```

