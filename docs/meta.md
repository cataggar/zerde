# meta

## Navigation

- [API Index](README.md)
- Previous: [containers](containers.md)
- Next: [rename](rename.md)

## Overview

Metadata parsing and validation helpers.

## Functions

- [optionsFor](#fn-optionsfor)
- [validate](#fn-validate)
- [fieldOptionsFor](#fn-fieldoptionsfor)
- [shouldSerialize](#fn-shouldserialize)
- [shouldDeserialize](#fn-shoulddeserialize)
- [writeHook](#fn-writehook)
- [readHook](#fn-readhook)
- [fieldWireName](#fn-fieldwirename)

## Types

- [Options](#type-options)
- [UnionRepr](#type-unionrepr)
- [FieldOptions](#type-fieldoptions)

## Constants

- [union_tag_field_name](#const-union_tag_field_name)
- [union_content_field_name](#const-union_content_field_name)

<a id="type-options"></a>

## Options

Normalized type-level metadata options.

```zig
pub const Options = struct {
    rename_all: rename.RenameRule = .none,
    deny_unknown_fields: bool = false,
    union_repr: UnionRepr = .external,
};
```

<a id="type-unionrepr"></a>

## UnionRepr

Supported tagged union wire representations.

```zig
pub const UnionRepr = enum {};
```

<a id="const-union_tag_field_name"></a>

## union_tag_field_name

```zig
pub const union_tag_field_name = "tag";
```

<a id="const-union_content_field_name"></a>

## union_content_field_name

```zig
pub const union_content_field_name = "value";
```

<a id="type-fieldoptions"></a>

## FieldOptions

Normalized field-level metadata options.

```zig
pub const FieldOptions = struct {
    rename: ?[]const u8 = null,
    skip: bool = false,
    skip_writing: bool = false,
    skip_reading: bool = false,
    with: ?type = null,
    write_with: ?type = null,
    read_with: ?type = null,
    bytes: bool = false,
};
```

<a id="fn-optionsfor"></a>

## optionsFor

Returns normalized metadata options for `T`.

```zig
pub fn optionsFor(comptime T: type) Options
```

References: [`Options`](#type-options)

<a id="fn-validate"></a>

## validate

Validates metadata options for `T` at comptime.

```zig
pub fn validate(comptime T: type, comptime options: Options) void
```

References: [`Options`](#type-options)

<a id="fn-fieldoptionsfor"></a>

## fieldOptionsFor

Returns normalized metadata options for one field of `T`.

```zig
pub fn fieldOptionsFor(comptime T: type, comptime field_name: []const u8) FieldOptions
```

References: [`FieldOptions`](#type-fieldoptions)

<a id="fn-shouldserialize"></a>

## shouldSerialize

Returns true when a field should be included in serialized output.

```zig
pub fn shouldSerialize(comptime field_options: FieldOptions) bool
```

References: [`FieldOptions`](#type-fieldoptions)

<a id="fn-shoulddeserialize"></a>

## shouldDeserialize

Returns true when a field should be read from input.

```zig
pub fn shouldDeserialize(comptime field_options: FieldOptions) bool
```

References: [`FieldOptions`](#type-fieldoptions)

<a id="fn-writehook"></a>

## writeHook

Returns the effective field write hook, if configured.

```zig
pub fn writeHook(comptime field_options: FieldOptions) ?type
```

References: [`FieldOptions`](#type-fieldoptions)

<a id="fn-readhook"></a>

## readHook

Returns the effective field read hook, if configured.

```zig
pub fn readHook(comptime field_options: FieldOptions) ?type
```

References: [`FieldOptions`](#type-fieldoptions)

<a id="fn-fieldwirename"></a>

## fieldWireName

Returns the serialized wire name for a field.

```zig
pub fn fieldWireName(
    comptime field_name: []const u8,
    comptime field_options: FieldOptions,
    comptime options: Options,
) []const u8
```

References: [`FieldOptions`](#type-fieldoptions), [`Options`](#type-options)

