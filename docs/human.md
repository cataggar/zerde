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

```zig
pub const WriteOptions = struct { ... };
```

Human writer configuration. Reserved for future formatting options.

<a id="fn-write"></a>

## write

```zig
pub fn write(writer: *std.Io.Writer, value: anytype) !void
```

Serializes `value` to a compact human-readable representation.

<a id="fn-writewithoptions"></a>

## writeWithOptions

```zig
pub fn writeWithOptions(writer: *std.Io.Writer, value: anytype, options: WriteOptions) !void
```

References: [`WriteOptions`](#type-writeoptions)

Serializes `value` to a compact human-readable representation with options.

<a id="fn-encoder"></a>

## encoder

```zig
pub fn encoder(writer: *std.Io.Writer) Encoder
```

References: [`Encoder`](#type-encoder)

Returns a low-level human-readable encoder for use with `zerde.serialize`.

<a id="type-encoder"></a>

## Encoder

```zig
pub const Encoder = struct { ... };
```

Low-level human-readable encoder used by the generic serializer.

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

```zig
pub fn emitNull(self: *Self) !void
```

Emits the `null` value.

<a id="fn-encoder-emitbool"></a>

### Encoder.emitBool

```zig
pub fn emitBool(self: *Self, value: bool) !void
```

Emits a boolean value.

<a id="fn-encoder-emitint"></a>

### Encoder.emitInt

```zig
pub fn emitInt(self: *Self, value: anytype) !void
```

Emits an integer value.

<a id="fn-encoder-emitfloat"></a>

### Encoder.emitFloat

```zig
pub fn emitFloat(self: *Self, value: anytype) !void
```

Emits a float value.

<a id="fn-encoder-emitstring"></a>

### Encoder.emitString

```zig
pub fn emitString(self: *Self, value: []const u8) !void
```

Emits a quoted string with common escapes.

<a id="fn-encoder-emitbytes"></a>

### Encoder.emitBytes

```zig
pub fn emitBytes(self: *Self, value: []const u8) !void
```

Emits raw bytes as a base64 string.

<a id="fn-encoder-beginseq"></a>

### Encoder.beginSeq

```zig
pub fn beginSeq(self: *Self, len: ?usize) !void
```

Begins a sequence.

<a id="fn-encoder-endseq"></a>

### Encoder.endSeq

```zig
pub fn endSeq(self: *Self) !void
```

Ends the current sequence.

<a id="fn-encoder-beginstruct"></a>

### Encoder.beginStruct

```zig
pub fn beginStruct(self: *Self, comptime T: type, field_count: usize) !void
```

Begins a struct representation using the short Zig type name.

<a id="fn-encoder-emitfieldname"></a>

### Encoder.emitFieldName

```zig
pub fn emitFieldName(self: *Self, name: []const u8) !void
```

Emits the next struct field name.

<a id="fn-encoder-endstruct"></a>

### Encoder.endStruct

```zig
pub fn endStruct(self: *Self) !void
```

Ends the current struct representation.

<a id="fn-encoder-emitenumtag"></a>

### Encoder.emitEnumTag

```zig
pub fn emitEnumTag(self: *Self, tag: []const u8) !void
```

Emits an enum tag as a string.

