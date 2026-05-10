# toml

## Navigation

- [API Index](README.md)
- Previous: [number](number.md)
- Next: [datetime](datetime.md)

## Overview

TOML format support.

## Functions

- [write](#fn-write)
- [writeWithOptions](#fn-writewithoptions)
- [encoder](#fn-encoder)
- [encoderWithOptions](#fn-encoderwithoptions)
- [sectionEncoder](#fn-sectionencoder)
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
- [EventEncoder](#type-eventencoder)
- [SectionEncoder](#type-sectionencoder)
- [Decoder](#type-decoder)

<a id="type-writelayout"></a>

## WriteLayout

TOML writer configuration.

```zig
pub const WriteLayout = enum {
    /// Streams directly without allocation. Nested structs are inline tables.
    inline_tables,
    /// Builds a temporary tree to emit `[table]` and `[[array]]` sections.
    sections,
};
```

<a id="type-writeoptions"></a>

## WriteOptions

TOML writer options.

```zig
pub const WriteOptions = struct {
    layout: WriteLayout = .inline_tables,
};
```

<a id="fn-write"></a>

## write

Serializes `value` as TOML to `writer` without heap allocation.

TOML documents are tables, so the root value must be a struct. TOML has no
null value; serializing null optionals returns `error.UnsupportedTomlNull`.

```zig
pub fn write(writer: *std.Io.Writer, value: anytype) !void
```

<a id="fn-writewithoptions"></a>

## writeWithOptions

Serializes `value` as TOML to `writer` with explicit writer options.

Section layout requires `allocator` for a temporary document tree. Inline
`inline_tables` layout ignores `allocator` and streams directly.

```zig
pub fn writeWithOptions(allocator: std.mem.Allocator, writer: *std.Io.Writer, value: anytype, options: WriteOptions) !void
```

References: [`WriteOptions`](#type-writeoptions)

<a id="fn-encoder"></a>

## encoder

Returns a low-level TOML encoder for use with `zerde.serialize` or custom
serialization code.

```zig
pub fn encoder(writer: *std.Io.Writer) Encoder
```

References: [`Encoder`](#type-encoder)

<a id="fn-encoderwithoptions"></a>

## encoderWithOptions

Returns a low-level TOML encoder using explicit writer options.

Section layout buffers into an allocator-backed document tree until
`EventEncoder.finish` is called. Call `EventEncoder.deinit` when done.

```zig
pub fn encoderWithOptions(allocator: std.mem.Allocator, writer: *std.Io.Writer, options: WriteOptions) EventEncoder
```

References: [`WriteOptions`](#type-writeoptions), [`EventEncoder`](#type-eventencoder)

<a id="fn-sectionencoder"></a>

## sectionEncoder

Returns an allocator-backed low-level TOML encoder that emits section layout.
Call `SectionEncoder.deinit` when done.

```zig
pub fn sectionEncoder(allocator: std.mem.Allocator, writer: *std.Io.Writer) SectionEncoder
```

References: [`SectionEncoder`](#type-sectionencoder)

<a id="fn-read"></a>

## read

Deserializes TOML from `reader` into `T`.

```zig
pub fn read(comptime T: type, allocator: std.mem.Allocator, reader: *std.Io.Reader) !T
```

<a id="fn-writealloc"></a>

## writeAlloc

Serializes `value` as TOML and returns allocator-owned bytes.

```zig
pub fn writeAlloc(allocator: std.mem.Allocator, value: anytype) ![]u8
```

<a id="fn-writeallocwithoptions"></a>

## writeAllocWithOptions

Serializes `value` as TOML with explicit writer options and returns
allocator-owned bytes.

```zig
pub fn writeAllocWithOptions(allocator: std.mem.Allocator, value: anytype, options: WriteOptions) ![]u8
```

References: [`WriteOptions`](#type-writeoptions)

<a id="fn-readslice"></a>

## readSlice

Deserializes TOML from `input` into `T`.

```zig
pub fn readSlice(comptime T: type, allocator: std.mem.Allocator, input: []const u8) !T
```

<a id="fn-decoder"></a>

## decoder

Returns a low-level TOML decoder for use with `zerde.deserialize` or custom
deserialization code. Call `Decoder.deinit` when done.

```zig
pub fn decoder(reader: *std.Io.Reader, allocator: std.mem.Allocator) !Decoder
```

References: [`Decoder`](#type-decoder)

<a id="type-kind"></a>

## Kind

TOML value kinds reported by `Decoder.peek`.

```zig
pub const Kind = enum {
    null,
    bool,
    int,
    float,
    datetime,
    string,
    seq,
    struct_,
};
```

<a id="type-encoder"></a>

## Encoder

Low-level TOML encoder used by the generic serializer.

```zig
pub const Encoder = struct {
    writer: *std.Io.Writer,
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
- [emitDateTime](#fn-encoder-emitdatetime)
- [emitDateTimeRaw](#fn-encoder-emitdatetimeraw)
- [beginSeq](#fn-encoder-beginseq)
- [endSeq](#fn-encoder-endseq)
- [beginStruct](#fn-encoder-beginstruct)
- [emitFieldName](#fn-encoder-emitfieldname)
- [endStruct](#fn-encoder-endstruct)
- [emitEnumTag](#fn-encoder-emitenumtag)
- [finish](#fn-encoder-finish)

<a id="fn-encoder-emitnull"></a>

### Encoder.emitNull

Emits a TOML null value when supported.

```zig
pub fn emitNull(self: *Self) !void
```

<a id="fn-encoder-emitbool"></a>

### Encoder.emitBool

Emits a TOML boolean value.

```zig
pub fn emitBool(self: *Self, value: bool) !void
```

<a id="fn-encoder-emitint"></a>

### Encoder.emitInt

Emits a TOML integer value.

```zig
pub fn emitInt(self: *Self, value: anytype) !void
```

<a id="fn-encoder-emitfloat"></a>

### Encoder.emitFloat

Emits a TOML floating-point value.

```zig
pub fn emitFloat(self: *Self, value: anytype) !void
```

<a id="fn-encoder-emitstring"></a>

### Encoder.emitString

Emits a TOML string value.

```zig
pub fn emitString(self: *Self, value: []const u8) !void
```

<a id="fn-encoder-emitbytes"></a>

### Encoder.emitBytes

Emits raw bytes as a base64 TOML string.

```zig
pub fn emitBytes(self: *Self, value: []const u8) !void
```

<a id="fn-encoder-emitdatetime"></a>

### Encoder.emitDateTime

Emits a TOML datetime value.

```zig
pub fn emitDateTime(self: *Self, comptime T: type, value: T) !void
```

<a id="fn-encoder-emitdatetimeraw"></a>

### Encoder.emitDateTimeRaw

Emits a raw TOML datetime token for event-based transcoding.

```zig
pub fn emitDateTimeRaw(self: *Self, value: []const u8) !void
```

<a id="fn-encoder-beginseq"></a>

### Encoder.beginSeq

Begins a TOML array.

```zig
pub fn beginSeq(self: *Self, len: ?usize) !void
```

<a id="fn-encoder-endseq"></a>

### Encoder.endSeq

Ends the current TOML array.

```zig
pub fn endSeq(self: *Self) !void
```

<a id="fn-encoder-beginstruct"></a>

### Encoder.beginStruct

Begins a TOML table or inline table.

```zig
pub fn beginStruct(self: *Self, comptime T: type, field_count: usize) !void
```

<a id="fn-encoder-emitfieldname"></a>

### Encoder.emitFieldName

Emits the next TOML key.

```zig
pub fn emitFieldName(self: *Self, name: []const u8) !void
```

<a id="fn-encoder-endstruct"></a>

### Encoder.endStruct

Ends the current TOML table or inline table.

```zig
pub fn endStruct(self: *Self) !void
```

<a id="fn-encoder-emitenumtag"></a>

### Encoder.emitEnumTag

Emits an enum tag as a TOML string.

```zig
pub fn emitEnumTag(self: *Self, tag: []const u8) !void
```

<a id="fn-encoder-finish"></a>

### Encoder.finish

Verifies that the TOML document was completely written.

```zig
pub fn finish(self: *Self) !void
```

<a id="type-eventencoder"></a>

## EventEncoder

Options-aware low-level TOML encoder used by event-based serialization.

The inline variant streams directly. The section variant buffers values until
`finish`, then renders nested tables as `[table]` and `[[array]]` sections.

```zig
pub const EventEncoder = union(enum) {
    inline_tables: Encoder,
    sections: SectionEncoder,
};
```

### Nested Declarations

- [deinit](#fn-eventencoder-deinit)
- [emitNull](#fn-eventencoder-emitnull)
- [emitBool](#fn-eventencoder-emitbool)
- [emitInt](#fn-eventencoder-emitint)
- [emitFloat](#fn-eventencoder-emitfloat)
- [emitString](#fn-eventencoder-emitstring)
- [emitBytes](#fn-eventencoder-emitbytes)
- [emitDateTime](#fn-eventencoder-emitdatetime)
- [emitDateTimeRaw](#fn-eventencoder-emitdatetimeraw)
- [beginSeq](#fn-eventencoder-beginseq)
- [endSeq](#fn-eventencoder-endseq)
- [beginStruct](#fn-eventencoder-beginstruct)
- [emitFieldName](#fn-eventencoder-emitfieldname)
- [endStruct](#fn-eventencoder-endstruct)
- [emitEnumTag](#fn-eventencoder-emitenumtag)
- [finish](#fn-eventencoder-finish)

<a id="fn-eventencoder-deinit"></a>

### EventEncoder.deinit

Frees memory owned by this event encoder.

```zig
pub fn deinit(self: *Self) void
```

<a id="fn-eventencoder-emitnull"></a>

### EventEncoder.emitNull

Emits a TOML null value when supported.

```zig
pub fn emitNull(self: *Self) !void
```

<a id="fn-eventencoder-emitbool"></a>

### EventEncoder.emitBool

Emits a TOML boolean value.

```zig
pub fn emitBool(self: *Self, value: bool) !void
```

<a id="fn-eventencoder-emitint"></a>

### EventEncoder.emitInt

Emits a TOML integer value.

```zig
pub fn emitInt(self: *Self, value: anytype) !void
```

<a id="fn-eventencoder-emitfloat"></a>

### EventEncoder.emitFloat

Emits a TOML floating-point value.

```zig
pub fn emitFloat(self: *Self, value: anytype) !void
```

<a id="fn-eventencoder-emitstring"></a>

### EventEncoder.emitString

Emits a TOML string value.

```zig
pub fn emitString(self: *Self, value: []const u8) !void
```

<a id="fn-eventencoder-emitbytes"></a>

### EventEncoder.emitBytes

Emits raw bytes as a base64 TOML string.

```zig
pub fn emitBytes(self: *Self, value: []const u8) !void
```

<a id="fn-eventencoder-emitdatetime"></a>

### EventEncoder.emitDateTime

Emits a TOML datetime value.

```zig
pub fn emitDateTime(self: *Self, comptime T: type, value: T) !void
```

<a id="fn-eventencoder-emitdatetimeraw"></a>

### EventEncoder.emitDateTimeRaw

Emits a raw TOML datetime token.

```zig
pub fn emitDateTimeRaw(self: *Self, value: []const u8) !void
```

<a id="fn-eventencoder-beginseq"></a>

### EventEncoder.beginSeq

Begins a TOML array.

```zig
pub fn beginSeq(self: *Self, len: ?usize) !void
```

<a id="fn-eventencoder-endseq"></a>

### EventEncoder.endSeq

Ends the current TOML array.

```zig
pub fn endSeq(self: *Self) !void
```

<a id="fn-eventencoder-beginstruct"></a>

### EventEncoder.beginStruct

Begins a TOML table or inline table.

```zig
pub fn beginStruct(self: *Self, comptime T: type, field_count: usize) !void
```

<a id="fn-eventencoder-emitfieldname"></a>

### EventEncoder.emitFieldName

Emits the next TOML key.

```zig
pub fn emitFieldName(self: *Self, name: []const u8) !void
```

<a id="fn-eventencoder-endstruct"></a>

### EventEncoder.endStruct

Ends the current TOML table or inline table.

```zig
pub fn endStruct(self: *Self) !void
```

<a id="fn-eventencoder-emitenumtag"></a>

### EventEncoder.emitEnumTag

Emits an enum tag as a TOML string.

```zig
pub fn emitEnumTag(self: *Self, tag: []const u8) !void
```

<a id="fn-eventencoder-finish"></a>

### EventEncoder.finish

Verifies that the TOML document was completely written.

```zig
pub fn finish(self: *Self) !void
```

<a id="type-sectionencoder"></a>

## SectionEncoder

Allocator-backed low-level TOML encoder that emits section layout.

```zig
pub const SectionEncoder = struct {
    writer: *std.Io.Writer,
    tree: TreeEncoder,
};
```

### Nested Declarations

- [deinit](#fn-sectionencoder-deinit)
- [emitNull](#fn-sectionencoder-emitnull)
- [emitBool](#fn-sectionencoder-emitbool)
- [emitInt](#fn-sectionencoder-emitint)
- [emitFloat](#fn-sectionencoder-emitfloat)
- [emitString](#fn-sectionencoder-emitstring)
- [emitBytes](#fn-sectionencoder-emitbytes)
- [emitDateTime](#fn-sectionencoder-emitdatetime)
- [emitDateTimeRaw](#fn-sectionencoder-emitdatetimeraw)
- [beginSeq](#fn-sectionencoder-beginseq)
- [endSeq](#fn-sectionencoder-endseq)
- [beginStruct](#fn-sectionencoder-beginstruct)
- [emitFieldName](#fn-sectionencoder-emitfieldname)
- [endStruct](#fn-sectionencoder-endstruct)
- [emitEnumTag](#fn-sectionencoder-emitenumtag)
- [finish](#fn-sectionencoder-finish)

<a id="fn-sectionencoder-deinit"></a>

### SectionEncoder.deinit

Frees memory owned by this section encoder.

```zig
pub fn deinit(self: *Self) void
```

<a id="fn-sectionencoder-emitnull"></a>

### SectionEncoder.emitNull

Emits a TOML null value when supported.

```zig
pub fn emitNull(self: *Self) !void
```

<a id="fn-sectionencoder-emitbool"></a>

### SectionEncoder.emitBool

Emits a TOML boolean value.

```zig
pub fn emitBool(self: *Self, value: bool) !void
```

<a id="fn-sectionencoder-emitint"></a>

### SectionEncoder.emitInt

Emits a TOML integer value.

```zig
pub fn emitInt(self: *Self, value: anytype) !void
```

<a id="fn-sectionencoder-emitfloat"></a>

### SectionEncoder.emitFloat

Emits a TOML floating-point value.

```zig
pub fn emitFloat(self: *Self, value: anytype) !void
```

<a id="fn-sectionencoder-emitstring"></a>

### SectionEncoder.emitString

Emits a TOML string value.

```zig
pub fn emitString(self: *Self, value: []const u8) !void
```

<a id="fn-sectionencoder-emitbytes"></a>

### SectionEncoder.emitBytes

Emits raw bytes as a base64 TOML string.

```zig
pub fn emitBytes(self: *Self, value: []const u8) !void
```

<a id="fn-sectionencoder-emitdatetime"></a>

### SectionEncoder.emitDateTime

Emits a TOML datetime value.

```zig
pub fn emitDateTime(self: *Self, comptime T: type, value: T) !void
```

<a id="fn-sectionencoder-emitdatetimeraw"></a>

### SectionEncoder.emitDateTimeRaw

Emits a raw TOML datetime token.

```zig
pub fn emitDateTimeRaw(self: *Self, value: []const u8) !void
```

<a id="fn-sectionencoder-beginseq"></a>

### SectionEncoder.beginSeq

Begins a TOML array.

```zig
pub fn beginSeq(self: *Self, len: ?usize) !void
```

<a id="fn-sectionencoder-endseq"></a>

### SectionEncoder.endSeq

Ends the current TOML array.

```zig
pub fn endSeq(self: *Self) !void
```

<a id="fn-sectionencoder-beginstruct"></a>

### SectionEncoder.beginStruct

Begins a TOML table.

```zig
pub fn beginStruct(self: *Self, comptime T: type, field_count: usize) !void
```

<a id="fn-sectionencoder-emitfieldname"></a>

### SectionEncoder.emitFieldName

Emits the next TOML key.

```zig
pub fn emitFieldName(self: *Self, name: []const u8) !void
```

<a id="fn-sectionencoder-endstruct"></a>

### SectionEncoder.endStruct

Ends the current TOML table.

```zig
pub fn endStruct(self: *Self) !void
```

<a id="fn-sectionencoder-emitenumtag"></a>

### SectionEncoder.emitEnumTag

Emits an enum tag as a TOML string.

```zig
pub fn emitEnumTag(self: *Self, tag: []const u8) !void
```

<a id="fn-sectionencoder-finish"></a>

### SectionEncoder.finish

Renders the buffered TOML document.

```zig
pub fn finish(self: *Self) !void
```

<a id="type-decoder"></a>

## Decoder

Low-level TOML decoder used by the generic deserializer.

```zig
pub const Decoder = struct {
    allocator: std.mem.Allocator,
    input: []u8,
    root: Value,
    stack: [max_depth]Frame = undefined,
    stack_len: usize = 0,
    pending_value: ?*const Value = null,
    root_used: bool = false,
};
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
- [readDateTimeRaw](#fn-decoder-readdatetimeraw)
- [beginSeq](#fn-decoder-beginseq)
- [hasNextSeqElem](#fn-decoder-hasnextseqelem)
- [endSeq](#fn-decoder-endseq)
- [beginStruct](#fn-decoder-beginstruct)
- [beginStructEvent](#fn-decoder-beginstructevent)
- [nextField](#fn-decoder-nextfield)
- [endStruct](#fn-decoder-endstruct)
- [skipValue](#fn-decoder-skipvalue)
- [finish](#fn-decoder-finish)

<a id="fn-decoder-deinit"></a>

### Decoder.deinit

Frees memory owned by this decoder.

```zig
pub fn deinit(self: *Self) void
```

<a id="fn-decoder-peek"></a>

### Decoder.peek

Returns the kind of the next TOML value.

```zig
pub fn peek(self: *Self) !Kind
```

References: [`Kind`](#type-kind)

<a id="fn-decoder-readnull"></a>

### Decoder.readNull

Reads a TOML null value when supported.

```zig
pub fn readNull(self: *Self) !void
```

<a id="fn-decoder-readbool"></a>

### Decoder.readBool

Reads a TOML boolean value.

```zig
pub fn readBool(self: *Self) !bool
```

<a id="fn-decoder-readint"></a>

### Decoder.readInt

Reads a TOML integer into `T`.

```zig
pub fn readInt(self: *Self, comptime T: type) !T
```

<a id="fn-decoder-readfloat"></a>

### Decoder.readFloat

Reads a TOML number into floating-point type `T`.

```zig
pub fn readFloat(self: *Self, comptime T: type) !T
```

<a id="fn-decoder-readstring"></a>

### Decoder.readString

Reads a TOML string as allocator-owned bytes.

```zig
pub fn readString(self: *Self, allocator: std.mem.Allocator) ![]u8
```

<a id="fn-decoder-readdatetime"></a>

### Decoder.readDateTime

Reads a TOML datetime value into `T`.

```zig
pub fn readDateTime(self: *Self, comptime T: type) !T
```

<a id="fn-decoder-readdatetimeraw"></a>

### Decoder.readDateTimeRaw

Reads a TOML datetime token as allocator-owned bytes for event consumers.

```zig
pub fn readDateTimeRaw(self: *Self, allocator: std.mem.Allocator) ![]u8
```

<a id="fn-decoder-beginseq"></a>

### Decoder.beginSeq

Begins reading a TOML array.

```zig
pub fn beginSeq(self: *Self) !?usize
```

<a id="fn-decoder-hasnextseqelem"></a>

### Decoder.hasNextSeqElem

Returns whether the current TOML array has another element.

```zig
pub fn hasNextSeqElem(self: *Self) !bool
```

<a id="fn-decoder-endseq"></a>

### Decoder.endSeq

Ends the current TOML array.

```zig
pub fn endSeq(self: *Self) !void
```

<a id="fn-decoder-beginstruct"></a>

### Decoder.beginStruct

Begins reading a TOML table.

```zig
pub fn beginStruct(self: *Self, comptime T: type) !void
```

<a id="fn-decoder-beginstructevent"></a>

### Decoder.beginStructEvent

Begins reading a TOML table for event consumers and returns its field
count.

```zig
pub fn beginStructEvent(self: *Self) !?usize
```

<a id="fn-decoder-nextfield"></a>

### Decoder.nextField

Returns the next table key as allocator-owned bytes, or null when done.

```zig
pub fn nextField(self: *Self) !?[]u8
```

<a id="fn-decoder-endstruct"></a>

### Decoder.endStruct

Ends the current TOML table.

```zig
pub fn endStruct(self: *Self) !void
```

<a id="fn-decoder-skipvalue"></a>

### Decoder.skipValue

Skips one TOML value.

```zig
pub fn skipValue(self: *Self) !void
```

<a id="fn-decoder-finish"></a>

### Decoder.finish

Verifies that the TOML document was completely read.

```zig
pub fn finish(self: *Self) !void
```

