# Zerde

Zerde is a small Zig 0.16 serialization framework built around comptime reflection, explicit I/O, and type-specialized codecs.

## Features

- Multi-format serialization: JSON, TOML, MessagePack, CBOR, ZON, CSV, compact binary, and human-readable debug output.
- Reflection-driven typed APIs: serialize ordinary Zig structs, enums, unions, slices, arrays, optionals, and std containers without runtime schema registration.
- Type-specialized `Codec(T)`: one generated namespace for format dispatch, validation, schema inspection, cleanup, and option-aware reads/writes.
- Structural event pipeline: consume or transcode self-describing formats without defining an application Zig struct.
- Metadata-driven wire control: rename fields, apply `rename_all`, skip fields, deny unknown fields, mark raw byte fields, and attach custom hooks.
- Tagged union support: external, adjacent, and internal representations.
- Explicit ownership: allocator-backed reads pair with `zerde.deinit` for predictable cleanup.
- No external dependencies.

## Status

The current version is `0.3.1` and targets Zig `0.16.0` or newer. The API is usable, but still early.

## Quick Start

1. Add `zerde` to your Zig package dependencies:

```sh
zig fetch --save git+https://codeberg.org/gron/zerde#v0.3.1
```

2. Wire the dependency into your executable in `build.zig`:

```zig
const zerde_dep = b.dependency("zerde", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("zerde", zerde_dep.module("zerde"));
```

3. Import and use `zerde`

```zig
const std = @import("std");
const zerde = @import("zerde");

const User = struct {
    user_id: u64,
    display_name: []const u8,
    active: bool = true,
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    const user = User{
        .user_id = 1,
        .display_name = "Ada",
    };

    const json = try zerde.json.writeAlloc(allocator, user);
    defer allocator.free(json);

    std.debug.print("{s}\n", .{json});
    // {"user_id":1,"display_name":"Ada","active":true}

    const parsed = try zerde.json.readSlice(User, allocator, json);
    defer zerde.deinit(User, allocator, parsed);

    std.debug.print("parsed user: {s}\n", .{parsed.display_name});
    // parsed user: Ada
}
```

More `zerde` examples can be found in the [examples](examples/) folder.

## Format APIs

Each format exposes direct helpers for writing to `std.Io.Writer`, reading from `std.Io.Reader`, and working with allocator-owned slices.

```zig
const bytes = try zerde.json.writeAlloc(allocator, value);
defer allocator.free(bytes);

const value2 = try zerde.json.readSlice(MyType, allocator, bytes);
defer zerde.deinit(MyType, allocator, value2);
```

Available format modules:

- `zerde.json` - [Docs](docs/json.md)
- `zerde.toml` - [Docs](docs/toml.md)
- `zerde.msgpack` - [Docs](docs/msgpack.md)
- `zerde.cbor` - [Docs](docs/cbor.md)
- `zerde.zon` - [Docs](docs/zon.md)
- `zerde.binary` - [Docs](docs/binary.md)
- `zerde.csv` - [Docs](docs/csv.md)
- `zerde.human` - [Docs](docs/human.md), no read/readSlice API

Common helpers:

```zig
pub fn write(writer: *std.Io.Writer, value: anytype) !void;
pub fn writeWithOptions(allocator: std.mem.Allocator, writer: *std.Io.Writer, value: anytype, options: Options) !void;
pub fn writeAlloc(allocator: std.mem.Allocator, value: anytype) ![]u8;
pub fn writeAllocWithOptions(allocator: std.mem.Allocator, value: anytype, options: Options) ![]u8;

pub fn read(comptime T: type, allocator: std.mem.Allocator, reader: *std.Io.Reader) !T;
pub fn readSlice(comptime T: type, allocator: std.mem.Allocator, input: []const u8) !T;

pub fn encoder(writer: *std.Io.Writer) Encoder;
pub fn encoderWithOptions(writer: *std.Io.Writer, options: Options) Encoder;
pub fn decoder(reader: *std.Io.Reader, allocator: std.mem.Allocator) Decoder;
```

The option type is format-specific, usually named `WriteOptions` or `Options`. Low-level encoder and decoder helpers integrate with `zerde.serialize` and `zerde.deserialize`; some formats expose format-specific variants such as `eventEncoder`, allocator-backed encoders, or option-bearing decoders.

## Structural Events

Structural events are Zerde's untyped path for data whose shape is not represented by an application Zig type. Use them to build your own value tree, validate or count a stream, transform data, or transcode between formats.

A decoder is a structural source, and an encoder or custom sink is a structural target. The same protocol backs both the typed APIs and the event APIs:

```zig
try zerde.serialize(value, &encoder);                         // typed value -> sink
const value2 = try zerde.deserialize(T, allocator, &decoder); // source -> typed value
try zerde.consume(allocator, &decoder, &sink);                // source -> custom sink
try zerde.pipe(allocator, &decoder, &encoder);                // source -> encoder
```

Custom sinks implement callbacks such as `emitNull`, `emitBool`, `emitInt`, `emitString`, `beginSeq`, `endSeq`, `beginStruct`, `emitFieldName`, and `endStruct`. String and field-name slices passed to a sink are temporary; copy them if your representation retains them.

```zig
var reader: std.Io.Reader = .fixed("{\"id\":42,\"name\":\"Ada\"}");
var decoder = zerde.json.decoder(&reader, allocator);

var builder = MyValueBuilder.init(allocator);
defer builder.deinit();

try zerde.consume(allocator, &decoder, &builder);
try decoder.finish();

const my_value = try builder.finish();
```

For dynamic in-memory data, `zerde.events.readAlloc` returns an allocator-owned `zerde.events.Value` tree:

```zig
var value = try zerde.events.readAlloc(allocator, &decoder);
defer value.deinit(allocator);

try decoder.finish();
```

For direct transcoding, pipe a decoder into a format encoder:

```zig
var in = zerde.json.decoder(&reader, allocator);
var out = zerde.msgpack.encoder(&writer);

try zerde.pipe(allocator, &in, &out);
try in.finish();
try out.finish();
```

Event sources are intended for self-describing data streams such as JSON, TOML, MessagePack, CBOR, and ZON. CSV participates as a row stream; binary remains type-directed. See the [feature matrix](#feature-support-matrix) for source and target constraints.

## Type Codecs

`zerde.Codec(T)` returns a comptime-generated namespace for one Zig type.

```zig
const UserCodec = zerde.Codec(User);

try UserCodec.write(&writer, user, .json);
const user2 = try UserCodec.read(allocator, &reader, .json);
defer UserCodec.deinit(allocator, user2);

try UserCodec.validate(user);
const schema = comptime UserCodec.schema();
_ = schema;

try zerde.schema.write(&writer, schema, .human);
try zerde.schema.write(&writer, schema, .json);
```

Codecs dispatch through `zerde.Format`. The human format is write-only, so codec reads from `.human` fail at compile time.

Use `writeWithOptions` when a format has write options. Binary and CSV also support `readWithOptions`.

```zig
try UserCodec.writeWithOptions(allocator, &writer, user, .json, .{
    .pretty = true,
    .indent = 2,
});

try UserCodec.writeWithOptions(allocator, &writer, user, .binary, .{
    .endian = .big,
});

const UsersCodec = zerde.Codec([]const User);
try UsersCodec.writeWithOptions(allocator, &writer, users, .csv, .{
    .delimiter = .tab,
});
```

## Metadata

Add `pub const zerde = .{ ... };` to a type to customize serialization.

```zig
const ApiUser = struct {
    user_id: u64,
    display_name: []const u8,
    password_hash: []const u8 = "redacted",

    pub const zerde = .{
        .rename_all = .camel_case,
        .deny_unknown_fields = true,
        .fields = .{
            .display_name = .{ .rename = "name" },
            .password_hash = .{ .skip_writing = true },
        },
    };
};
```

Type-level options:

- `rename_all`: `.none`, `.snake_case`, or `.camel_case`
- `deny_unknown_fields`: reject unknown fields while deserializing structs
- `union_repr`: `.external`, `.adjacent`, or `.internal`
- `fields`: field-level metadata

Field-level options:

- `rename`: explicit wire name
- `skip`: skip both writing and reading
- `skip_writing`: omit during writing only
- `skip_reading`: ignore during reading only
- `with`: use one hook type for writing and reading
- `write_with`: use a write-only hook
- `read_with`: use a read-only hook
- `bytes`: treat `Bytes`, `[N]u8`, `[]u8`, or `[]const u8` as raw bytes instead of UTF-8 strings

Metadata is validated at comptime. Unknown metadata options, unknown field names, invalid hooks, and invalid internal tagged union layouts produce compile errors.

## Tagged Unions

Externally tagged unions are the default.

```zig
const Shape = union(enum) {
    circle: struct { radius: u8 },
    point,
};
```

JSON output:

```json
{"circle":{"radius":10}}
{"point":null}
```

Adjacent tagging uses `tag` and `value` fields.

```zig
const Shape = union(enum) {
    circle: struct { radius: u8 },
    point,

    pub const zerde = .{ .union_repr = .adjacent };
};
```

JSON output:

```json
{"tag":"circle","value":{"radius":10}}
{"tag":"point","value":null}
```

Internal tagging flattens struct payload fields beside `tag`. Non-void payload variants must be structs, and payload fields cannot map to the wire name `tag`.

```zig
const Shape = union(enum) {
    circle: struct { radius: u8 },
    point,

    pub const zerde = .{ .union_repr = .internal };
};
```

JSON output:

```json
{"tag":"circle","radius":10}
{"tag":"point"}
```

## Raw Bytes

Plain `[]const u8` is treated as a UTF-8 string by formats with a distinct string representation. Use `zerde.Bytes` or `.bytes = true` when the bytes are arbitrary binary data.

```zig
const Blob = struct {
    name: []const u8,
    data: []const u8,

    pub const zerde = .{
        .fields = .{
            .data = .{ .bytes = true },
        },
    };
};
```

```zig
const Blob = struct {
    name: []const u8,
    data: zerde.Bytes,
}
```

Raw byte wire representations are format-specific and documented in each format module.


## Custom Hooks

Field hooks let a type customize how a specific field is represented.

```zig
const BoolAsYesNo = struct {
    pub fn write(value: bool, encoder: anytype) !void {
        try encoder.emitString(if (value) "yes" else "no");
    }

    pub fn read(comptime T: type, allocator: std.mem.Allocator, decoder: anytype) !T {
        const value = try decoder.readString(allocator);
        defer allocator.free(value);

        if (std.ascii.eqlIgnoreCase(value, "yes")) return true;
        if (std.ascii.eqlIgnoreCase(value, "no")) return false;
        return error.InvalidValue;
    }
};

const Account = struct {
    username: []const u8,
    active: bool,

    pub const zerde = .{
        .fields = .{
            .active = .{ .with = BoolAsYesNo },
        },
    };
};
```

With this hook, `active` stays a `bool` in Zig but is encoded as a string such as `"yes"` or `"no"` on the wire.

A type can also take over its own wire representation by defining native hooks. When Zerde reaches a type that has `zerdeWrite` or `zerdeRead`, it calls those functions instead of reflecting over that type's fields.

```zig
const UserId = struct {
    value: u64,

    pub fn zerdeWrite(self: UserId, encoder: anytype) !void {
        try encoder.emitInt(self.value);
    }

    pub fn zerdeRead(allocator: std.mem.Allocator, decoder: anytype) !UserId {
        _ = allocator;
        return .{ .value = try decoder.readInt(u64) };
    }
};

const User = struct {
    id: UserId,
    name: []const u8,
};
```

With those hooks, this value:

```zig
User{
    .id = .{ .value = 42 },
    .name = "Ada",
}
```

serializes as:

```json
{"id":42,"name":"Ada"}
```

not as:

```json
{"id":{"value":42},"name":"Ada"}
```

The write hook emits the wire representation for `UserId` directly. The read hook must read the same representation and rebuild the type. In this example, `zerdeWrite` writes an integer, so `zerdeRead` reads an integer and wraps it back into `UserId`.

Native hooks take precedence over field traversal for that type.

## Supported Types

Zerde supports the usual Zig data shapes you can describe with comptime reflection:

| Shape | Zig types |
| --- | --- |
| Scalars | `bool`, integers, floats, `null`, optionals, enums |
| Text | `[]u8`, `[]const u8`, and string literals as UTF-8 strings by default |
| Raw bytes | `zerde.Bytes`, `[N]u8`, `[]u8`, or `[]const u8` with `.bytes = true` |
| Sequences | arrays, slices, `std.ArrayList`, and `std.MultiArrayList` families |
| Maps | `std.HashMap` and `std.ArrayHashMap` families |
| Records | plain non-tuple structs |
| Variants | tagged unions |
| Custom wire shapes | types with native `zerdeWrite` or `zerdeRead` hooks |

Std list containers serialize as sequences. Std map containers serialize as sequences of `{ key, value }` entries, so the same representation works for string and non-string keys across JSON, TOML, MessagePack, CBOR, ZON, and binary formats.

Values returned by read APIs own allocator-backed strings, slices, lists, maps, and hook-owned data; release them with `zerde.deinit` when done. Unsupported types fail at compile time when used through the generic traversal or `Codec(T)` schema validation.

## Feature Support Matrix

| Format | Direct write | Direct read | Alloc write | Slice read | Options | Low-level API | `Codec(T)` | Events source |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| JSON | yes | yes | yes | yes | write | encoder, decoder | yes | yes |
| TOML | yes | yes | yes | yes | write | encoder, decoder | yes | yes |
| MessagePack | yes | yes | yes | yes | write | encoder, decoder | yes | yes |
| CBOR | yes | yes | yes | yes | write | encoder, decoder | yes | yes |
| ZON | yes | yes | yes | yes | write | encoder, decoder | yes | yes |
| Binary | yes | yes | yes | yes | read, write | encoder, decoder | yes | no |
| CSV | yes | yes | yes | yes | read, write | encoder, decoder | yes | yes, as rows |
| Human | yes | no | no | no | write | encoder only | write only | no |

Direct, alloc, and slice columns refer to the standard `write`, `read`, `writeAlloc`, and `readSlice` helper families, including `*WithOptions` variants when a format supports options. Low-level API lists encoder/decoder entry points for integration with `zerde.serialize`, `zerde.deserialize`, custom hooks, and structural events.

Structural event targets are more format dependent than sources. JSON, MessagePack, CBOR, ZON, and Human can generally receive `events.Value.write` output. TOML can receive object-shaped values that satisfy TOML's root-table and no-null constraints. CSV can receive a sequence of row structs, using the first row as the fixed schema. Binary should be treated as a type-directed target rather than a dynamic event target.

## Development

Run the full test suite:

```sh
zig build test
```

Build all example binaries:

```sh
zig build examples
```

Run an example:

```sh
./zig-out/bin/events-api
```

See `examples/README.md` for the full example list.

Generate docs:

```sh
zig build docs
```

Serve docs locally:

```sh
zig build docs-serve
```

By default, docs are served from `zig-out/docs` at `127.0.0.1:8000`. Override the host and port after `--`:

```sh
zig build docs-serve -- 0.0.0.0 9000
```

## License

MIT License. See `LICENSE` for details.
