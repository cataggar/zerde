# Zerde

Zerde is a small Zig 0.16 serialization framework built around comptime reflection, explicit I/O, and type-specialized codecs.

## Features

- JSON read/write with compact and pretty output.
- TOML read/write with inline-table or section-oriented output.
- Compact binary read/write with configurable endianness.
- Type-specialized `Codec(T)` namespaces for format dispatch, schema inspection, validation, and cleanup.
- Field metadata for renaming, `rename_all`, skipping, unknown-field denial, byte fields, and custom hooks.
- Tagged unions with external, adjacent, and internal representations.
- No external dependencies.

## Status

The current version is `0.1.0` and targets Zig `0.16.0` or newer. The API is usable, but still early.

## Quick Start

1. Add `zerde` to your Zig package dependencies:

```sh
zig fetch --save git+https://codeberg.org/gron/zerde#v0.1.0
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

## Format APIs

Each format exposes direct helpers for writing to `std.Io.Writer`, reading from `std.Io.Reader`, and working with allocator-owned slices.

```zig
const bytes = try zerde.json.writeAlloc(allocator, value);
defer allocator.free(bytes);

const value2 = try zerde.json.readSlice(MyType, allocator, bytes);
defer zerde.deinit(MyType, allocator, value2);
```

Available format modules:

- `zerde.json`
- `zerde.toml`
- `zerde.zon`
- `zerde.binary`
- `zerde.human` no read/readSlice API

Common helpers:

- `write(writer, value)`
- `writeWithOptions(...)`
- `writeAlloc(allocator, value)`
- `writeAllocWithOptions(...)`
- `read(T, allocator, reader)`
- `readSlice(T, allocator, input)`
- `encoder(...)` and `decoder(...)` for low-level integration with `zerde.serialize` and `zerde.deserialize`

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
```

Supported `zerde.Format` values are `.json`, `.toml`, `.zon`, `.binary`, and `.human`. The human format is write-only, so codec reads from `.human` fail at compile time.

Use `writeWithOptions` when a format has write options. Binary also supports `readWithOptions` for endianness.

```zig
try UserCodec.writeWithOptions(allocator, &writer, user, .json, .{
    .pretty = true,
    .indent = 2,
});

try UserCodec.writeWithOptions(allocator, &writer, user, .binary, .{
    .endian = .big,
});
```

## Supported Types

Zerde currently supports:

- `bool`
- integers
- floats
- `null` and optionals
- enums
- arrays and slices
- `[]u8`, `[]const u8`, and string literals as strings by default
- plain non-tuple structs
- tagged unions
- `zerde.Bytes` and fields marked `.bytes = true` for raw byte payloads
- custom types that implement native Zerde hooks

Unsupported types fail at compile time when used through the generic traversal or `Codec(T)` schema validation.

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

Plain `[]const u8` is treated as a UTF-8 string in JSON, TOML, ZON, and human output. Use `zerde.Bytes` or `.bytes = true` when the bytes are arbitrary binary data.

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

JSON, TOML, ZON, and human encoders emit raw bytes as standard padded RFC 4648 base64 strings. The binary format writes raw bytes directly with its normal length-prefix rules for slices.


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

## Format Notes

JSON:

- Strings must be valid UTF-8.
- Non-finite floats are rejected.
- Pretty output is controlled with `json.WriteOptions{ .pretty = true, .indent = 2 }`.
- The decoder rejects trailing input and malformed syntax.

TOML:

- The root value must be a struct because TOML documents are tables.
- TOML has no null value, so serializing null optionals returns `error.UnsupportedTomlNull`.
- Integers are limited to TOML's signed 64-bit range.
- Writer layout can be `.inline_tables` or `.sections`.
- Date/time helpers are exposed as `zerde.LocalDate`, `zerde.LocalTime`, `zerde.LocalDateTime`, and `zerde.OffsetDateTime`.

ZON:

- Structs and sequences are emitted with Zig object notation syntax such as `.{ .id = 1 }` and `.{ 1, 2, 3 }`.
- Enums are emitted as enum literals such as `.green`; renamed fields or tags that are not bare identifiers use escaped identifier syntax such as `.@"display-name"`.
- Numeric input accepts Zig-style separators, `0b`/`0o`/`0x` integer prefixes, and `inf`/`nan` float tokens.
- Line and block comments are accepted while reading, and trailing commas are accepted in structs and sequences.
- Pretty output is controlled with `zon.WriteOptions{ .pretty = true, .indent = 4 }`.

Binary:

- Default endianness is little-endian.
- Fixed arrays are encoded without a length prefix.
- Slices and strings are length-prefixed with `u64`.
- Optionals use a one-byte presence marker.
- Struct fields are encoded in declaration order using the effective serializable field set.
- The decoder rejects trailing data.

Human:

- Write-only compact output intended for debugging.
- Uses reflected type names for structs.

## Memory Ownership

Values returned by deserialization own their strings and slices. Always deinitialize them when done.

```zig
const parsed = try zerde.toml.readSlice(Config, allocator, input);
defer zerde.deinit(Config, allocator, parsed);
```

## Development

Run the test suite:

```sh
zig build test
```

Generate Zig documentation:

```sh
zig build docs
```

Generate and serve the documentation locally:

```sh
zig build docs-serve
```

The server listens on `127.0.0.1:8000` by default and serves `zig-out/docs`. You can override the host and port after `--`:

```sh
zig build docs-serve -- 0.0.0.0 9000
```

## License

MIT License. See `LICENSE` for details.
