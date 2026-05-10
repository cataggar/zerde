# csv

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
- [zon](zon.md)
- [binary](binary.md)
- [csv](csv.md)
- [events](events.md)
- [human](human.md)
- [traits](traits.md)
- [codec](codec.md)
- [schema](schema.md)

</details>

## Overview

CSV and delimiter-separated tabular text support.

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
- [eventEncoder](#fn-eventencoder)
- [eventEncoderWithOptions](#fn-eventencoderwithoptions)
- [decoder](#fn-decoder)

## Types

- [Delimiter](#type-delimiter)
- [RecordTerminator](#type-recordterminator)
- [Options](#type-options)
- [Kind](#type-kind)
- [Encoder](#type-encoder)
- [Decoder](#type-decoder)

<a id="type-delimiter"></a>

## Delimiter

Supported delimiter-separated dialects.

```zig
pub const Delimiter = enum {
    comma,
    tab,
};
```

<a id="type-recordterminator"></a>

## RecordTerminator

Record terminators emitted by the writer.

```zig
pub const RecordTerminator = enum {
    lf,
    crlf,
};
```

<a id="type-options"></a>

## Options

CSV format configuration. Use `.delimiter = .tab` for TSV.

```zig
pub const Options = struct {
    delimiter: Delimiter = .comma,
    header: bool = true,
    record_terminator: RecordTerminator = .crlf,
    final_record_terminator: bool = false,
};
```

<a id="fn-write"></a>

## write

Serializes a sequence of flat structs as CSV.

```zig
pub fn write(writer: *std.Io.Writer, value: anytype) !void
```

<a id="fn-writewithoptions"></a>

## writeWithOptions

Serializes a sequence of flat structs as CSV with explicit options.

```zig
pub fn writeWithOptions(writer: *std.Io.Writer, value: anytype, options: Options) !void
```

References: [`Options`](#type-options)

<a id="fn-read"></a>

## read

Deserializes CSV from `reader` into `T`.

```zig
pub fn read(comptime T: type, allocator: std.mem.Allocator, reader: *std.Io.Reader) !T
```

<a id="fn-readwithoptions"></a>

## readWithOptions

Deserializes CSV from `reader` into `T` with explicit options.

```zig
pub fn readWithOptions(comptime T: type, allocator: std.mem.Allocator, reader: *std.Io.Reader, options: Options) !T
```

References: [`Options`](#type-options)

<a id="fn-writealloc"></a>

## writeAlloc

Serializes `value` as CSV and returns allocator-owned bytes.

```zig
pub fn writeAlloc(allocator: std.mem.Allocator, value: anytype) ![]u8
```

<a id="fn-writeallocwithoptions"></a>

## writeAllocWithOptions

Serializes `value` as CSV with explicit options and returns allocator-owned bytes.

```zig
pub fn writeAllocWithOptions(allocator: std.mem.Allocator, value: anytype, options: Options) ![]u8
```

References: [`Options`](#type-options)

<a id="fn-readslice"></a>

## readSlice

Deserializes CSV from `input` into `T`.

```zig
pub fn readSlice(comptime T: type, allocator: std.mem.Allocator, input: []const u8) !T
```

<a id="fn-readslicewithoptions"></a>

## readSliceWithOptions

Deserializes CSV from `input` into `T` with explicit options.

```zig
pub fn readSliceWithOptions(comptime T: type, allocator: std.mem.Allocator, input: []const u8, options: Options) !T
```

References: [`Options`](#type-options)

<a id="fn-encoder"></a>

## encoder

Returns a low-level CSV encoder for use with `zerde.serialize`.

```zig
pub fn encoder(writer: *std.Io.Writer) Encoder
```

References: [`Encoder`](#type-encoder)

<a id="fn-encoderwithoptions"></a>

## encoderWithOptions

Returns a low-level CSV encoder with explicit options.

```zig
pub fn encoderWithOptions(writer: *std.Io.Writer, options: Options) Encoder
```

References: [`Options`](#type-options), [`Encoder`](#type-encoder)

<a id="fn-eventencoder"></a>

## eventEncoder

Returns an allocator-backed CSV encoder that can consume streaming dynamic events.

```zig
pub fn eventEncoder(writer: *std.Io.Writer, allocator: std.mem.Allocator) Encoder
```

References: [`Encoder`](#type-encoder)

<a id="fn-eventencoderwithoptions"></a>

## eventEncoderWithOptions

Returns an allocator-backed CSV encoder with explicit options for streaming dynamic events.

```zig
pub fn eventEncoderWithOptions(writer: *std.Io.Writer, allocator: std.mem.Allocator, options: Options) Encoder
```

References: [`Options`](#type-options), [`Encoder`](#type-encoder)

<a id="fn-decoder"></a>

## decoder

Returns a low-level CSV decoder for use with `zerde.deserialize`.
Call `Decoder.deinit` when done.

```zig
pub fn decoder(reader: *std.Io.Reader, allocator: std.mem.Allocator, options: Options) !Decoder
```

References: [`Options`](#type-options), [`Decoder`](#type-decoder)

<a id="type-kind"></a>

## Kind

CSV value kinds reported by `Decoder.peek`.

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

<a id="type-encoder"></a>

## Encoder

Low-level CSV encoder used by the generic serializer.

This can also receive `zerde.events.Value.write` output when the event value
is a sequence of row structs. For event writes, the first row defines the
fixed schema, nested structs are flattened with dot-separated headers,
missing later fields become empty cells, and extra later fields are rejected.

```zig
pub const Encoder = struct {
    writer: *std.Io.Writer,
    options: Options,
    allocator: ?std.mem.Allocator = null,
    stack: [max_depth]Frame = undefined,
    stack_len: usize = 0,
    dynamic_stack: [max_depth]DynamicFrame = undefined,
    dynamic_stack_len: usize = 0,
    dynamic_schema: std.ArrayList(DynamicColumn) = .empty,
    dynamic_row: std.ArrayList(DynamicCell) = .empty,
    dynamic_pending_field_name: ?[]u8 = null,
    root_started: bool = false,
    seq_done: bool = false,
    row_count: usize = 0,
    row_field_index: usize = 0,
    expecting_cell: bool = false,
    header_written: bool = false,
    pending_path: []const u8 = "",
    pending_leaf_count: usize = 0,
    pending_nested_entries: []const FieldEntry = &.{},
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [emitNull](#fn-encoder-emitnull) | `self: *Self` | `!void` | Emits an empty CSV cell for a null value. |
| [emitBool](#fn-encoder-emitbool) | `self: *Self, value: bool` | `!void` | Emits a boolean cell as &#96;true&#96; or &#96;false&#96;. |
| [emitInt](#fn-encoder-emitint) | `self: *Self, value: anytype` | `!void` | Emits an integer cell. |
| [emitFloat](#fn-encoder-emitfloat) | `self: *Self, value: anytype` | `!void` | Emits a floating-point cell. |
| [emitString](#fn-encoder-emitstring) | `self: *Self, value: []const u8` | `!void` | Emits a UTF-8 string cell with CSV escaping. |
| [emitBytes](#fn-encoder-emitbytes) | `self: *Self, value: []const u8` | `!void` | Emits raw bytes as base64 text. |
| [emitEnumTag](#fn-encoder-emitenumtag) | `self: *Self, tag: []const u8` | `!void` | Emits an enum tag cell by name. |
| [emitEventValue](#fn-encoder-emiteventvalue) | `self: *Self, value: events.Value` | `!void` | Writes a buffered structural event value as CSV. |
| [beginArray](#fn-encoder-beginarray) | `self: *Self, comptime T: type, len: usize` | `!void` | Begins writing an array of CSV rows. |
| [beginSlice](#fn-encoder-beginslice) | `self: *Self, comptime Child: type, len: usize` | `!void` | Begins writing a slice of CSV rows. |
| [beginSeq](#fn-encoder-beginseq) | `self: *Self, len: ?usize` | `!void` | Begins writing a sequence of CSV rows. |
| [hasNextSeqElem](#fn-encoder-hasnextseqelem) | `self: *Self` | `!bool` | Returns whether sequence pull-style writing is supported. |
| [endSeq](#fn-encoder-endseq) | `self: *Self` | `!void` | Ends the CSV row sequence. |
| [beginStruct](#fn-encoder-beginstruct) | `self: *Self, comptime T: type, field_count: usize` | `!void` | Begins writing a row struct or nested flat struct. |
| [beginStructEvent](#fn-encoder-beginstructevent) | `self: *Self, field_count: ?usize` | `!void` | Begins a dynamic event row struct or nested struct. |
| [emitFieldName](#fn-encoder-emitfieldname) | `self: *Self, name: []const u8` | `!void` | Selects the next CSV column by struct field name. |
| [endStruct](#fn-encoder-endstruct) | `self: *Self` | `!void` | Ends the current row struct or nested flat struct. |
| [finish](#fn-encoder-finish) | `self: *Self` | `!void` | Verifies that the CSV document was completely written. |
| [deinit](#fn-encoder-deinit) | `self: *Self` | `void` | Frees allocator-owned dynamic event state. |
| [beginOptional](#fn-encoder-beginoptional) | `self: *Self, present: bool` | `!void` | Emits an empty cell for absent optional values. |

<a id="fn-encoder-emitnull"></a>

### Encoder.emitNull

Emits an empty CSV cell for a null value.

```zig
pub fn emitNull(self: *Self) !void
```

<a id="fn-encoder-emitbool"></a>

### Encoder.emitBool

Emits a boolean cell as `true` or `false`.

```zig
pub fn emitBool(self: *Self, value: bool) !void
```

<a id="fn-encoder-emitint"></a>

### Encoder.emitInt

Emits an integer cell.

```zig
pub fn emitInt(self: *Self, value: anytype) !void
```

<a id="fn-encoder-emitfloat"></a>

### Encoder.emitFloat

Emits a floating-point cell.

```zig
pub fn emitFloat(self: *Self, value: anytype) !void
```

<a id="fn-encoder-emitstring"></a>

### Encoder.emitString

Emits a UTF-8 string cell with CSV escaping.

```zig
pub fn emitString(self: *Self, value: []const u8) !void
```

<a id="fn-encoder-emitbytes"></a>

### Encoder.emitBytes

Emits raw bytes as base64 text.

```zig
pub fn emitBytes(self: *Self, value: []const u8) !void
```

<a id="fn-encoder-emitenumtag"></a>

### Encoder.emitEnumTag

Emits an enum tag cell by name.

```zig
pub fn emitEnumTag(self: *Self, tag: []const u8) !void
```

<a id="fn-encoder-emiteventvalue"></a>

### Encoder.emitEventValue

Writes a buffered structural event value as CSV.

The value must be a sequence of row structs, and the first row defines
the fixed schema.

```zig
pub fn emitEventValue(self: *Self, value: events.Value) !void
```

References: [`events.Value`](events.md#type-value)

<a id="fn-encoder-beginarray"></a>

### Encoder.beginArray

Begins writing an array of CSV rows.

```zig
pub fn beginArray(self: *Self, comptime T: type, len: usize) !void
```

<a id="fn-encoder-beginslice"></a>

### Encoder.beginSlice

Begins writing a slice of CSV rows.

```zig
pub fn beginSlice(self: *Self, comptime Child: type, len: usize) !void
```

<a id="fn-encoder-beginseq"></a>

### Encoder.beginSeq

Begins writing a sequence of CSV rows.

```zig
pub fn beginSeq(self: *Self, len: ?usize) !void
```

<a id="fn-encoder-hasnextseqelem"></a>

### Encoder.hasNextSeqElem

Returns whether sequence pull-style writing is supported.

```zig
pub fn hasNextSeqElem(self: *Self) !bool
```

<a id="fn-encoder-endseq"></a>

### Encoder.endSeq

Ends the CSV row sequence.

```zig
pub fn endSeq(self: *Self) !void
```

<a id="fn-encoder-beginstruct"></a>

### Encoder.beginStruct

Begins writing a row struct or nested flat struct.

```zig
pub fn beginStruct(self: *Self, comptime T: type, field_count: usize) !void
```

<a id="fn-encoder-beginstructevent"></a>

### Encoder.beginStructEvent

Begins a dynamic event row struct or nested struct.

```zig
pub fn beginStructEvent(self: *Self, field_count: ?usize) !void
```

<a id="fn-encoder-emitfieldname"></a>

### Encoder.emitFieldName

Selects the next CSV column by struct field name.

```zig
pub fn emitFieldName(self: *Self, name: []const u8) !void
```

<a id="fn-encoder-endstruct"></a>

### Encoder.endStruct

Ends the current row struct or nested flat struct.

```zig
pub fn endStruct(self: *Self) !void
```

<a id="fn-encoder-finish"></a>

### Encoder.finish

Verifies that the CSV document was completely written.

```zig
pub fn finish(self: *Self) !void
```

<a id="fn-encoder-deinit"></a>

### Encoder.deinit

Frees allocator-owned dynamic event state.

```zig
pub fn deinit(self: *Self) void
```

<a id="fn-encoder-beginoptional"></a>

### Encoder.beginOptional

Emits an empty cell for absent optional values.

```zig
pub fn beginOptional(self: *Self, present: bool) !void
```

<a id="type-decoder"></a>

## Decoder

Low-level CSV decoder used by the generic deserializer.

```zig
pub const Decoder = struct {
    allocator: std.mem.Allocator,
    options: Options,
    records: []Record,
    stack: [max_depth]Frame = undefined,
    stack_len: usize = 0,
    in_seq: bool = false,
    seq_done: bool = false,
    row_index: usize = 0,
    current_record_index: ?usize = null,
    current_cell: ?[]const u8 = null,
    pending_nested_entries: []const FieldEntry = &.{},
    pending_path: []const u8 = "",
    current_lookup_names: []const []const u8 = &.{},
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [deinit](#fn-decoder-deinit) | `self: *Self` | `void` | Frees memory owned by this decoder. |
| [peek](#fn-decoder-peek) | `self: *Self` | `!Kind` | Returns the kind of the next CSV value. |
| [readNull](#fn-decoder-readnull) | `self: *Self` | `!void` | Reads an empty cell as null. |
| [readBool](#fn-decoder-readbool) | `self: *Self` | `!bool` | Reads a boolean cell. |
| [readInt](#fn-decoder-readint) | `self: *Self, comptime T: type` | `!T` | Reads an integer cell into &#96;T&#96;. |
| [readFloat](#fn-decoder-readfloat) | `self: *Self, comptime T: type` | `!T` | Reads a numeric cell into floating-point type &#96;T&#96;. |
| [readString](#fn-decoder-readstring) | `self: *Self, allocator: std.mem.Allocator` | `![]u8` | Reads a string cell as allocator-owned bytes. |
| [readBytes](#fn-decoder-readbytes) | `self: *Self, allocator: std.mem.Allocator` | `![]u8` | Reads a base64 cell into allocator-owned bytes. |
| [readOptionalPresent](#fn-decoder-readoptionalpresent) | `self: *Self` | `!bool` | Returns whether the current optional field is present. |
| [beginSeq](#fn-decoder-beginseq) | `self: *Self` | `!?usize` | Begins reading the sequence of CSV rows. |
| [hasNextSeqElem](#fn-decoder-hasnextseqelem) | `self: *Self` | `!bool` | Returns whether another CSV row is available. |
| [endSeq](#fn-decoder-endseq) | `self: *Self` | `!void` | Ends the CSV row sequence. |
| [beginStruct](#fn-decoder-beginstruct) | `self: *Self, comptime T: type` | `!void` | Begins reading a row struct or nested flat struct. |
| [beginStructEvent](#fn-decoder-beginstructevent) | `self: *Self` | `!?usize` | Begins reading a dynamic CSV row for event consumers. |
| [nextField](#fn-decoder-nextfield) | `self: *Self` | `!?[]u8` | Returns the next field name as allocator-owned bytes, or null when done. |
| [endStruct](#fn-decoder-endstruct) | `self: *Self` | `!void` | Ends the current row struct or nested flat struct. |
| [skipValue](#fn-decoder-skipvalue) | `self: *Self` | `!void` | Skips the current cell or nested field group. |
| [finish](#fn-decoder-finish) | `self: *Self` | `!void` | Verifies that the CSV document was completely read. |

<a id="fn-decoder-deinit"></a>

### Decoder.deinit

Frees memory owned by this decoder.

```zig
pub fn deinit(self: *Self) void
```

<a id="fn-decoder-peek"></a>

### Decoder.peek

Returns the kind of the next CSV value.

```zig
pub fn peek(self: *Self) !Kind
```

References: [`Kind`](#type-kind)

<a id="fn-decoder-readnull"></a>

### Decoder.readNull

Reads an empty cell as null.

```zig
pub fn readNull(self: *Self) !void
```

<a id="fn-decoder-readbool"></a>

### Decoder.readBool

Reads a boolean cell.

```zig
pub fn readBool(self: *Self) !bool
```

<a id="fn-decoder-readint"></a>

### Decoder.readInt

Reads an integer cell into `T`.

```zig
pub fn readInt(self: *Self, comptime T: type) !T
```

<a id="fn-decoder-readfloat"></a>

### Decoder.readFloat

Reads a numeric cell into floating-point type `T`.

```zig
pub fn readFloat(self: *Self, comptime T: type) !T
```

<a id="fn-decoder-readstring"></a>

### Decoder.readString

Reads a string cell as allocator-owned bytes.

```zig
pub fn readString(self: *Self, allocator: std.mem.Allocator) ![]u8
```

<a id="fn-decoder-readbytes"></a>

### Decoder.readBytes

Reads a base64 cell into allocator-owned bytes.

```zig
pub fn readBytes(self: *Self, allocator: std.mem.Allocator) ![]u8
```

<a id="fn-decoder-readoptionalpresent"></a>

### Decoder.readOptionalPresent

Returns whether the current optional field is present.

```zig
pub fn readOptionalPresent(self: *Self) !bool
```

<a id="fn-decoder-beginseq"></a>

### Decoder.beginSeq

Begins reading the sequence of CSV rows.

```zig
pub fn beginSeq(self: *Self) !?usize
```

<a id="fn-decoder-hasnextseqelem"></a>

### Decoder.hasNextSeqElem

Returns whether another CSV row is available.

```zig
pub fn hasNextSeqElem(self: *Self) !bool
```

<a id="fn-decoder-endseq"></a>

### Decoder.endSeq

Ends the CSV row sequence.

```zig
pub fn endSeq(self: *Self) !void
```

<a id="fn-decoder-beginstruct"></a>

### Decoder.beginStruct

Begins reading a row struct or nested flat struct.

```zig
pub fn beginStruct(self: *Self, comptime T: type) !void
```

<a id="fn-decoder-beginstructevent"></a>

### Decoder.beginStructEvent

Begins reading a dynamic CSV row for event consumers.

```zig
pub fn beginStructEvent(self: *Self) !?usize
```

<a id="fn-decoder-nextfield"></a>

### Decoder.nextField

Returns the next field name as allocator-owned bytes, or null when done.

```zig
pub fn nextField(self: *Self) !?[]u8
```

<a id="fn-decoder-endstruct"></a>

### Decoder.endStruct

Ends the current row struct or nested flat struct.

```zig
pub fn endStruct(self: *Self) !void
```

<a id="fn-decoder-skipvalue"></a>

### Decoder.skipValue

Skips the current cell or nested field group.

```zig
pub fn skipValue(self: *Self) !void
```

<a id="fn-decoder-finish"></a>

### Decoder.finish

Verifies that the CSV document was completely read.

```zig
pub fn finish(self: *Self) !void
```

