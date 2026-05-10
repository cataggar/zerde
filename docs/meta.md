# meta

## Navigation

- [API Index](README.md)
- Previous: [containers](containers.md)
- Next: [rename](rename.md)

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

```zig
pub const Options = struct { ... };
```

Normalized type-level metadata options.

### Fields

```zig
    rename_all: rename.RenameRule = .none
    deny_unknown_fields: bool = false
    union_repr: UnionRepr = .external
```


<a id="type-unionrepr"></a>

## UnionRepr

```zig
pub const UnionRepr = enum { ... };
```

Supported tagged union wire representations.

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

```zig
pub const FieldOptions = struct { ... };
```

Normalized field-level metadata options.

### Fields

```zig
    rename: ?[]const u8 = null
    skip: bool = false
    skip_writing: bool = false
    skip_reading: bool = false
    with: ?type = null
    write_with: ?type = null
    read_with: ?type = null
    bytes: bool = false
```


<a id="fn-optionsfor"></a>

## optionsFor

```zig
pub fn optionsFor(comptime T: type) Options
```

References: [`Options`](#type-options)

Returns normalized metadata options for `T`.

<a id="fn-validate"></a>

## validate

```zig
pub fn validate(comptime T: type, comptime options: Options) void
```

References: [`Options`](#type-options)

Validates metadata options for `T` at comptime.

<a id="fn-fieldoptionsfor"></a>

## fieldOptionsFor

```zig
pub fn fieldOptionsFor(comptime T: type, comptime field_name: []const u8) FieldOptions
```

References: [`FieldOptions`](#type-fieldoptions)

Returns normalized metadata options for one field of `T`.

<a id="fn-shouldserialize"></a>

## shouldSerialize

```zig
pub fn shouldSerialize(comptime field_options: FieldOptions) bool
```

References: [`FieldOptions`](#type-fieldoptions)

Returns true when a field should be included in serialized output.

<a id="fn-shoulddeserialize"></a>

## shouldDeserialize

```zig
pub fn shouldDeserialize(comptime field_options: FieldOptions) bool
```

References: [`FieldOptions`](#type-fieldoptions)

Returns true when a field should be read from input.

<a id="fn-writehook"></a>

## writeHook

```zig
pub fn writeHook(comptime field_options: FieldOptions) ?type
```

References: [`FieldOptions`](#type-fieldoptions)

Returns the effective field write hook, if configured.

<a id="fn-readhook"></a>

## readHook

```zig
pub fn readHook(comptime field_options: FieldOptions) ?type
```

References: [`FieldOptions`](#type-fieldoptions)

Returns the effective field read hook, if configured.

<a id="fn-fieldwirename"></a>

## fieldWireName

```zig
pub fn fieldWireName(
    comptime field_name: []const u8,
    comptime field_options: FieldOptions,
    comptime options: Options,
) []const u8
```

References: [`FieldOptions`](#type-fieldoptions), [`Options`](#type-options)

Returns the serialized wire name for a field.

