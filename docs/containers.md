# containers

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

Traits and helpers for std container types supported by Zerde.

## Functions

- [isList](#fn-islist)
- [isMap](#fn-ismap)
- [listChild](#fn-listchild)
- [mapKey](#fn-mapkey)
- [mapValue](#fn-mapvalue)
- [initList](#fn-initlist)
- [appendList](#fn-appendlist)
- [deinitListStorage](#fn-deinitliststorage)
- [listLen](#fn-listlen)
- [listItem](#fn-listitem)
- [initMap](#fn-initmap)
- [putMapEntry](#fn-putmapentry)
- [deinitMapStorage](#fn-deinitmapstorage)

<a id="fn-islist"></a>

## isList

Returns whether `T` is a supported std list container.

```zig
pub fn isList(comptime T: type) bool
```

<a id="fn-ismap"></a>

## isMap

Returns whether `T` is a supported std map container.

```zig
pub fn isMap(comptime T: type) bool
```

<a id="fn-listchild"></a>

## listChild

Returns the element type stored by a supported list container.

```zig
pub fn listChild(comptime T: type) type
```

<a id="fn-mapkey"></a>

## mapKey

Returns the key type stored by a supported map container.

```zig
pub fn mapKey(comptime T: type) type
```

<a id="fn-mapvalue"></a>

## mapValue

Returns the value type stored by a supported map container.

```zig
pub fn mapValue(comptime T: type) type
```

<a id="fn-initlist"></a>

## initList

Initializes a supported list container, using `len` as a capacity hint when possible.

```zig
pub fn initList(comptime T: type, allocator: std.mem.Allocator, len: ?usize) !T
```

<a id="fn-appendlist"></a>

## appendList

Appends one item to a supported list container.

```zig
pub fn appendList(comptime T: type, list: *T, allocator: std.mem.Allocator, item: listChild(T)) !void
```

<a id="fn-deinitliststorage"></a>

## deinitListStorage

Deinitializes storage owned by a supported list container.

```zig
pub fn deinitListStorage(comptime T: type, allocator: std.mem.Allocator, value: T) void
```

<a id="fn-listlen"></a>

## listLen

Returns the number of items in a supported list container.

```zig
pub fn listLen(comptime T: type, value: T) usize
```

<a id="fn-listitem"></a>

## listItem

Returns the item at `index` from a supported list container.

```zig
pub fn listItem(comptime T: type, value: T, index: usize) listChild(T)
```

<a id="fn-initmap"></a>

## initMap

Initializes a supported map container.

```zig
pub fn initMap(comptime T: type, allocator: std.mem.Allocator) !T
```

<a id="fn-putmapentry"></a>

## putMapEntry

Inserts one key-value pair into a supported map container.

```zig
pub fn putMapEntry(
    comptime T: type,
    map: *T,
    allocator: std.mem.Allocator,
    key: mapKey(T),
    value: mapValue(T),
) !void
```

<a id="fn-deinitmapstorage"></a>

## deinitMapStorage

Deinitializes storage owned by a supported map container.

```zig
pub fn deinitMapStorage(comptime T: type, allocator: std.mem.Allocator, value: T) void
```

