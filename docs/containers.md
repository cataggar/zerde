# containers

## Navigation

- [API Index](README.md)
- Previous: [base64](base64.md)
- Next: [meta](meta.md)

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

```zig
pub fn isList(comptime T: type) bool
```

<a id="fn-ismap"></a>

## isMap

```zig
pub fn isMap(comptime T: type) bool
```

<a id="fn-listchild"></a>

## listChild

```zig
pub fn listChild(comptime T: type) type
```

<a id="fn-mapkey"></a>

## mapKey

```zig
pub fn mapKey(comptime T: type) type
```

<a id="fn-mapvalue"></a>

## mapValue

```zig
pub fn mapValue(comptime T: type) type
```

<a id="fn-initlist"></a>

## initList

```zig
pub fn initList(comptime T: type, allocator: std.mem.Allocator, len: ?usize) !T
```

<a id="fn-appendlist"></a>

## appendList

```zig
pub fn appendList(comptime T: type, list: *T, allocator: std.mem.Allocator, item: listChild(T)) !void
```

<a id="fn-deinitliststorage"></a>

## deinitListStorage

```zig
pub fn deinitListStorage(comptime T: type, allocator: std.mem.Allocator, value: T) void
```

<a id="fn-listlen"></a>

## listLen

```zig
pub fn listLen(comptime T: type, value: T) usize
```

<a id="fn-listitem"></a>

## listItem

```zig
pub fn listItem(comptime T: type, value: T, index: usize) listChild(T)
```

<a id="fn-initmap"></a>

## initMap

```zig
pub fn initMap(comptime T: type, allocator: std.mem.Allocator) !T
```

<a id="fn-putmapentry"></a>

## putMapEntry

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

```zig
pub fn deinitMapStorage(comptime T: type, allocator: std.mem.Allocator, value: T) void
```

