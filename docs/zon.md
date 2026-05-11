# zon

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
pub fn writeWithOptions(allocator: std.mem.Allocator, writer: *std.Io.Writer, value: anytype, options: WriteOptions) !void
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
pub const Kind = enum {
    null,
    bool,
    int,
    float,
    string,
    enum_,
    seq,
    struct_,
};
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

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [emitNull](#fn-encoder-emitnull) | `self: *Self` | `!void` | Emits a ZON null value. |
| [emitBool](#fn-encoder-emitbool) | `self: *Self, value: bool` | `!void` | Emits a ZON boolean value. |
| [emitInt](#fn-encoder-emitint) | `self: *Self, value: anytype` | `!void` | Emits a ZON integer value. |
| [emitFloat](#fn-encoder-emitfloat) | `self: *Self, value: anytype` | `!void` | Emits a ZON floating-point value. |
| [emitString](#fn-encoder-emitstring) | `self: *Self, value: []const u8` | `!void` | Emits a ZON string value. |
| [emitBytes](#fn-encoder-emitbytes) | `self: *Self, value: []const u8` | `!void` | Emits raw bytes as a base64 ZON string. |
| [emitEnum](#fn-encoder-emitenum) | `self: *Self, comptime T: type, value: T` | `!void` | Emits a ZON enum literal for &#96;value&#96;. |
| [emitEnumTag](#fn-encoder-emitenumtag) | `self: *Self, tag: []const u8` | `!void` | Emits a ZON enum literal by tag name. |
| [beginSeq](#fn-encoder-beginseq) | `self: *Self, len: ?usize` | `!void` | Begins a ZON array literal. |
| [endSeq](#fn-encoder-endseq) | `self: *Self` | `!void` | Ends the current ZON array literal. |
| [beginStruct](#fn-encoder-beginstruct) | `self: *Self, comptime T: type, field_count: usize` | `!void` | Begins a ZON struct literal. |
| [emitFieldName](#fn-encoder-emitfieldname) | `self: *Self, name: []const u8` | `!void` | Emits the next ZON struct field name. |
| [endStruct](#fn-encoder-endstruct) | `self: *Self` | `!void` | Ends the current ZON struct literal. |
| [finish](#fn-encoder-finish) | `self: *Self` | `!void` | Verifies that the ZON document was completely written. |

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

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [peek](#fn-decoder-peek) | `self: *Self` | `!Kind` | Returns the kind of the next ZON value. |
| [readNull](#fn-decoder-readnull) | `self: *Self` | `!void` | Reads a ZON null value. |
| [readBool](#fn-decoder-readbool) | `self: *Self` | `!bool` | Reads a ZON boolean value. |
| [readInt](#fn-decoder-readint) | `self: *Self, comptime T: type` | `!T` | Reads a ZON integer into &#96;T&#96;. |
| [readFloat](#fn-decoder-readfloat) | `self: *Self, comptime T: type` | `!T` | Reads a ZON number into floating-point type &#96;T&#96;. |
| [readString](#fn-decoder-readstring) | `self: *Self, allocator: std.mem.Allocator` | `![]u8` | Reads a ZON string as allocator-owned UTF-8 bytes. |
| [readEnum](#fn-decoder-readenum) | `self: *Self, comptime T: type` | `!T` | Reads a ZON enum literal into &#96;T&#96;. |
| [readEnumTag](#fn-decoder-readenumtag) | `self: *Self, allocator: std.mem.Allocator` | `![]u8` | Reads a ZON enum literal tag as allocator-owned bytes for event consumers. |
| [beginSeq](#fn-decoder-beginseq) | `self: *Self` | `!?usize` | Begins reading a ZON array literal. |
| [hasNextSeqElem](#fn-decoder-hasnextseqelem) | `self: *Self` | `!bool` | Returns whether the current ZON array has another element. |
| [endSeq](#fn-decoder-endseq) | `self: *Self` | `!void` | Ends the current ZON array literal. |
| [beginStruct](#fn-decoder-beginstruct) | `self: *Self, comptime T: type` | `!void` | Begins reading a ZON struct literal. |
| [beginStructEvent](#fn-decoder-beginstructevent) | `self: *Self` | `!?usize` | Begins reading a ZON struct literal for event consumers. ZON does not expose the field count before the literal has been read. |
| [nextField](#fn-decoder-nextfield) | `self: *Self` | `!?[]u8` | Returns the next struct field name as allocator-owned bytes, or null when done. |
| [endStruct](#fn-decoder-endstruct) | `self: *Self` | `!void` | Ends the current ZON struct literal. |
| [skipValue](#fn-decoder-skipvalue) | `self: *Self` | `anyerror!void` | Skips one complete ZON value. |
| [finish](#fn-decoder-finish) | `self: *Self` | `!void` | Verifies that the ZON document was completely read. |

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

