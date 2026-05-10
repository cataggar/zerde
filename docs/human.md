# human

## Navigation

- [API Index](README.md)
- Previous: [csv](csv.md)
- Next: [traits](traits.md)

Human-readable serialization format.

## Functions

- [write](#fn-write)
- [writeWithOptions](#fn-writewithoptions)
- [encoder](#fn-encoder)

## Types

- [WriteOptions](#type-writeoptions)
- [Encoder](#type-encoder)

<a id="type-writeoptions"></a>

## WriteOptions

Human writer configuration. Reserved for future formatting options.

```zig
pub const WriteOptions = struct { ... };
```

<a id="fn-write"></a>

## write

Serializes `value` to a compact human-readable representation.

```zig
pub fn write(writer: *std.Io.Writer, value: anytype) !void
```

<a id="fn-writewithoptions"></a>

## writeWithOptions

Serializes `value` to a compact human-readable representation with options.

```zig
pub fn writeWithOptions(writer: *std.Io.Writer, value: anytype, options: WriteOptions) !void
```

References: [`WriteOptions`](#type-writeoptions)

<a id="fn-encoder"></a>

## encoder

Returns a low-level human-readable encoder for use with `zerde.serialize`.

```zig
pub fn encoder(writer: *std.Io.Writer) Encoder
```

References: [`Encoder`](#type-encoder)

<a id="type-encoder"></a>

## Encoder

Low-level human-readable encoder used by the generic serializer.

```zig
pub const Encoder = struct { ... };
```

### Fields

```zig
    writer: *std.Io.Writer
    stack: [max_depth]Frame = undefined
    stack_len: usize = 0
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

<a id="fn-encoder-emitnull"></a>

### Encoder.emitNull

Emits the `null` value.

```zig
pub fn emitNull(self: *Self) !void
```

<a id="fn-encoder-emitbool"></a>

### Encoder.emitBool

Emits a boolean value.

```zig
pub fn emitBool(self: *Self, value: bool) !void
```

<a id="fn-encoder-emitint"></a>

### Encoder.emitInt

Emits an integer value.

```zig
pub fn emitInt(self: *Self, value: anytype) !void
```

<a id="fn-encoder-emitfloat"></a>

### Encoder.emitFloat

Emits a float value.

```zig
pub fn emitFloat(self: *Self, value: anytype) !void
```

<a id="fn-encoder-emitstring"></a>

### Encoder.emitString

Emits a quoted string with common escapes.

```zig
pub fn emitString(self: *Self, value: []const u8) !void
```

<a id="fn-encoder-emitbytes"></a>

### Encoder.emitBytes

Emits raw bytes as a base64 string.

```zig
pub fn emitBytes(self: *Self, value: []const u8) !void
```

<a id="fn-encoder-beginseq"></a>

### Encoder.beginSeq

Begins a sequence.

```zig
pub fn beginSeq(self: *Self, len: ?usize) !void
```

<a id="fn-encoder-endseq"></a>

### Encoder.endSeq

Ends the current sequence.

```zig
pub fn endSeq(self: *Self) !void
```

<a id="fn-encoder-beginstruct"></a>

### Encoder.beginStruct

Begins a struct representation using the short Zig type name.

```zig
pub fn beginStruct(self: *Self, comptime T: type, field_count: usize) !void
```

<a id="fn-encoder-emitfieldname"></a>

### Encoder.emitFieldName

Emits the next struct field name.

```zig
pub fn emitFieldName(self: *Self, name: []const u8) !void
```

<a id="fn-encoder-endstruct"></a>

### Encoder.endStruct

Ends the current struct representation.

```zig
pub fn endStruct(self: *Self) !void
```

<a id="fn-encoder-emitenumtag"></a>

### Encoder.emitEnumTag

Emits an enum tag as a string.

```zig
pub fn emitEnumTag(self: *Self, tag: []const u8) !void
```

