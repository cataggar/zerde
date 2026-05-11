# events

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

Structural event APIs for consuming and producing Zerde-compatible values
without deserializing into an application Zig struct.

## Functions

- [consume](#fn-consume)
- [readAlloc](#fn-readalloc)
- [pipe](#fn-pipe)
- [beginStruct](#fn-beginstruct)

## Types

- [Extension](#type-extension)
- [ObjectField](#type-objectfield)
- [Value](#type-value)

<a id="type-extension"></a>

## Extension

Format-specific extension value used by self-describing formats.

```zig
pub const Extension = union(enum) {
    /// Opaque extension payload, such as MessagePack ext data.
    opaque_: Opaque,
    /// Tag wrapping another event value, such as CBOR semantic tags.
    tagged: Tagged,
    /// Tagless simple extension value, such as CBOR simple values.
    simple: Simple,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [Namespace](#type-extension-namespace) |  |  |  |
| [Id](#type-extension-id) |  |  |  |
| [Opaque](#type-extension-opaque) |  |  |  |
| [Tagged](#type-extension-tagged) |  |  |  |
| [Simple](#type-extension-simple) |  |  |  |
| [msgpack](#fn-extension-msgpack) | `type_id: i8, data: []u8` | `Extension` |  |
| [cborTag](#fn-extension-cbortag) | `tag: u64, value: *Value` | `Extension` |  |
| [cborSimple](#fn-extension-cborsimple) | `code: u8` | `Extension` |  |
| [deinit](#fn-extension-deinit) | `self: Extension, allocator: std.mem.Allocator` | `void` |  |

<a id="type-extension-namespace"></a>

### Extension.Namespace

```zig
pub const Namespace = enum {
    msgpack,
    cbor,
};
```

<a id="type-extension-id"></a>

### Extension.Id

```zig
pub const Id = union(enum) {
    signed: i64,
    unsigned: u64,
};
```

<a id="type-extension-opaque"></a>

### Extension.Opaque

```zig
pub const Opaque = struct {
    namespace: Namespace,
    id: Id,
    data: []u8,
};
```

<a id="type-extension-tagged"></a>

### Extension.Tagged

```zig
pub const Tagged = struct {
    namespace: Namespace,
    id: Id,
    value: *Value,
};
```

<a id="type-extension-simple"></a>

### Extension.Simple

```zig
pub const Simple = struct {
    namespace: Namespace,
    id: Id,
};
```

<a id="fn-extension-msgpack"></a>

### Extension.msgpack

```zig
pub fn msgpack(type_id: i8, data: []u8) Extension
```

References: [`Extension`](#type-extension)

<a id="fn-extension-cbortag"></a>

### Extension.cborTag

```zig
pub fn cborTag(tag: u64, value: *Value) Extension
```

References: [`Value`](#type-value), [`Extension`](#type-extension)

<a id="fn-extension-cborsimple"></a>

### Extension.cborSimple

```zig
pub fn cborSimple(code: u8) Extension
```

References: [`Extension`](#type-extension)

<a id="fn-extension-deinit"></a>

### Extension.deinit

```zig
pub fn deinit(self: Extension, allocator: std.mem.Allocator) void
```

References: [`Extension`](#type-extension)

<a id="type-objectfield"></a>

## ObjectField

Allocator-owned field in a structural object value.

```zig
pub const ObjectField = struct {
    name: []u8,
    value: Value,
};
```

<a id="type-value"></a>

## Value

Allocator-owned self-describing value tree.

This is a convenience representation for transcoding or tests. Users with an
existing representation can avoid this tree and implement a streaming sink
for `consume` instead.

```zig
pub const Value = union(enum) {
    null,
    bool: bool,
    int: i128,
    float: f64,
    string: []u8,
    bytes: []u8,
    enum_tag: []u8,
    datetime: []u8,
    extension: Extension,
    seq: []Value,
    struct_: []ObjectField,
};
```

### Nested Declarations

| Name | Parameters | Return Type | Description |
| --- | --- | --- | --- |
| [deinit](#fn-value-deinit) | `self: *Value, allocator: std.mem.Allocator` | `void` | Frees memory owned by this value and all nested values. |
| [write](#fn-value-write) | `self: Value, encoder: anytype` | `!void` | Emits this value into any Zerde encoder. |

<a id="fn-value-deinit"></a>

### Value.deinit

Frees memory owned by this value and all nested values.

```zig
pub fn deinit(self: *Value, allocator: std.mem.Allocator) void
```

References: [`Value`](#type-value)

<a id="fn-value-write"></a>

### Value.write

Emits this value into any Zerde encoder.

```zig
pub fn write(self: Value, encoder: anytype) !void
```

References: [`Value`](#type-value)

<a id="fn-consume"></a>

## consume

Consumes one complete value from `decoder` and forwards structural events to
`sink`.

A sink implements methods such as `emitNull`, `emitBool`, `beginSeq`,
`emitFieldName`, and `endStruct`. String, byte, field-name, enum-tag, and
datetime slices passed to the sink are temporary; the sink must copy them if
it needs to retain them after the callback returns.

```zig
pub fn consume(allocator: std.mem.Allocator, decoder: anytype, sink: anytype) !void
```

<a id="fn-readalloc"></a>

## readAlloc

Reads one complete self-describing value from `decoder` into an
allocator-owned `Value` tree.

```zig
pub fn readAlloc(allocator: std.mem.Allocator, decoder: anytype) !Value
```

References: [`Value`](#type-value)

<a id="fn-pipe"></a>

## pipe

Reads one value from `decoder` and writes it to `encoder` without requiring an
application Zig struct. This buffers the value so encoders that require known
sequence or object lengths can still be targeted.

CSV targets require the buffered value to be a sequence of row structs. The
first row defines the fixed CSV schema; later rows may omit those fields but
may not add fields outside that schema.

```zig
pub fn pipe(allocator: std.mem.Allocator, decoder: anytype, encoder: anytype) !void
```

<a id="fn-beginstruct"></a>

## beginStruct

Begins a struct/object on an event target or encoder.

Targets that expose `beginStructEvent` receive the field count as-is, which
allows `null` when the count is unknown. Event sinks that expose
`beginStruct(?usize)` are also supported. Type-directed encoders that only
expose `beginStruct(comptime T, field_count)` receive `void` as the marker
type and require a known field count.

```zig
pub fn beginStruct(target: anytype, field_count: ?usize) !void
```

