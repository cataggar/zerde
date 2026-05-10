//! Traits and helpers for std container types supported by Zerde.

const std = @import("std");

/// Returns whether `T` is a supported std list container.
pub fn isList(comptime T: type) bool {
    return isArrayList(T) or isMultiArrayList(T);
}

/// Returns whether `T` is a supported std map container.
pub fn isMap(comptime T: type) bool {
    return isHashMap(T) or isArrayHashMap(T);
}

/// Returns the element type stored by a supported list container.
pub fn listChild(comptime T: type) type {
    if (comptime isArrayList(T)) {
        const items_info = @typeInfo(fieldType(T, "items")).pointer;
        return items_info.child;
    }
    if (comptime isMultiArrayList(T)) return appendItemType(T);
    unsupported(T, "list");
}

/// Returns the key type stored by a supported map container.
pub fn mapKey(comptime T: type) type {
    if (!comptime isMap(T)) unsupported(T, "map");
    return fieldType(T.KV, "key");
}

/// Returns the value type stored by a supported map container.
pub fn mapValue(comptime T: type) type {
    if (!comptime isMap(T)) unsupported(T, "map");
    return fieldType(T.KV, "value");
}

/// Initializes a supported list container, using `len` as a capacity hint when possible.
pub fn initList(comptime T: type, allocator: std.mem.Allocator, len: ?usize) !T {
    if (comptime @hasDecl(T, "initCapacity")) {
        if (len) |actual_len| return try T.initCapacity(allocator, actual_len);
    }
    if (comptime @hasDecl(T, "init")) return T.init(allocator);
    if (comptime @hasDecl(T, "empty")) return T.empty;
    return .{};
}

/// Appends one item to a supported list container.
pub fn appendList(comptime T: type, list: *T, allocator: std.mem.Allocator, item: listChild(T)) !void {
    const append_info = @typeInfo(@TypeOf(T.append)).@"fn";
    switch (append_info.params.len) {
        2 => try list.append(item),
        3 => try list.append(allocator, item),
        else => @compileError("unsupported std list append signature for " ++ @typeName(T)),
    }
}

/// Deinitializes storage owned by a supported list container.
pub fn deinitListStorage(comptime T: type, allocator: std.mem.Allocator, value: T) void {
    var copy = value;
    const deinit_info = @typeInfo(@TypeOf(T.deinit)).@"fn";
    switch (deinit_info.params.len) {
        1 => copy.deinit(),
        2 => copy.deinit(allocator),
        else => @compileError("unsupported std list deinit signature for " ++ @typeName(T)),
    }
}

/// Returns the number of items in a supported list container.
pub fn listLen(comptime T: type, value: T) usize {
    if (comptime isArrayList(T)) return value.items.len;
    if (comptime isMultiArrayList(T)) return value.len;
    unsupported(T, "list");
}

/// Returns the item at `index` from a supported list container.
pub fn listItem(comptime T: type, value: T, index: usize) listChild(T) {
    if (comptime isArrayList(T)) return value.items[index];
    if (comptime isMultiArrayList(T)) return value.get(index);
    unsupported(T, "list");
}

/// Initializes a supported map container.
pub fn initMap(comptime T: type, allocator: std.mem.Allocator) !T {
    if (!comptime isMap(T)) unsupported(T, "map");

    if (comptime isStoredAllocatorHashMap(T)) {
        if (@sizeOf(fieldType(T, "ctx")) != 0) unsupported(T, "map with non-empty context");
        return T.init(allocator);
    }

    if (comptime @hasDecl(T, "empty")) return T.empty;
    return .{};
}

/// Inserts one key-value pair into a supported map container.
pub fn putMapEntry(
    comptime T: type,
    map: *T,
    allocator: std.mem.Allocator,
    key: mapKey(T),
    value: mapValue(T),
) !void {
    const get_or_put_info = @typeInfo(@TypeOf(T.getOrPut)).@"fn";
    const gop = switch (get_or_put_info.params.len) {
        2 => try map.getOrPut(key),
        3 => try map.getOrPut(allocator, key),
        else => @compileError("unsupported std map getOrPut signature for " ++ @typeName(T)),
    };
    if (gop.found_existing) return error.DuplicateField;
    gop.value_ptr.* = value;
}

/// Deinitializes storage owned by a supported map container.
pub fn deinitMapStorage(comptime T: type, allocator: std.mem.Allocator, value: T) void {
    var copy = value;
    const deinit_info = @typeInfo(@TypeOf(T.deinit)).@"fn";
    switch (deinit_info.params.len) {
        1 => copy.deinit(),
        2 => copy.deinit(allocator),
        else => @compileError("unsupported std map deinit signature for " ++ @typeName(T)),
    }
}

fn isArrayList(comptime T: type) bool {
    if (!comptime typeNameContains(T, "array_list.")) return false;
    if (@typeInfo(T) != .@"struct") return false;
    if (!@hasField(T, "items") or !@hasField(T, "capacity")) return false;
    if (!@hasDecl(T, "append") or !@hasDecl(T, "deinit")) return false;

    return switch (@typeInfo(fieldType(T, "items"))) {
        .pointer => |pointer_info| pointer_info.size == .slice,
        else => false,
    };
}

fn isMultiArrayList(comptime T: type) bool {
    if (!comptime typeNameContains(T, "multi_array_list.")) return false;
    if (@typeInfo(T) != .@"struct") return false;
    return @hasField(T, "len") and @hasField(T, "capacity") and
        @hasDecl(T, "append") and @hasDecl(T, "get") and @hasDecl(T, "deinit");
}

fn isHashMap(comptime T: type) bool {
    if (@typeInfo(T) != .@"struct") return false;
    if (!@hasDecl(T, "KV") or !@hasDecl(T, "iterator") or !@hasDecl(T, "count") or !@hasDecl(T, "getOrPut")) return false;
    return comptime typeNameContains(T, "hash_map.HashMap(") or typeNameContains(T, "hash_map.HashMapUnmanaged(");
}

fn isArrayHashMap(comptime T: type) bool {
    if (@typeInfo(T) != .@"struct") return false;
    if (!@hasDecl(T, "KV") or !@hasDecl(T, "iterator") or !@hasDecl(T, "count") or !@hasDecl(T, "getOrPut")) return false;
    return comptime typeNameContains(T, "array_hash_map.");
}

fn isStoredAllocatorHashMap(comptime T: type) bool {
    return isHashMap(T) and @hasField(T, "allocator") and @hasField(T, "ctx");
}

fn appendItemType(comptime T: type) type {
    const append_info = @typeInfo(@TypeOf(T.append)).@"fn";
    return append_info.params[append_info.params.len - 1].type.?;
}

fn fieldType(comptime T: type, comptime name: []const u8) type {
    inline for (@typeInfo(T).@"struct".fields) |field| {
        if (comptime std.mem.eql(u8, field.name, name)) return field.type;
    }
    @compileError(@typeName(T) ++ " has no field named '" ++ name ++ "'");
}

fn typeNameContains(comptime T: type, comptime needle: []const u8) bool {
    const haystack = @typeName(T);
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;

    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        var j: usize = 0;
        while (j < needle.len and haystack[i + j] == needle[j]) : (j += 1) {}
        if (j == needle.len) return true;
    }
    return false;
}

fn unsupported(comptime T: type, comptime label: []const u8) noreturn {
    @compileError("zerde does not support std " ++ label ++ " type " ++ @typeName(T));
}
