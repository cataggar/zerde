//! Type-directed cleanup for values produced by Zerde deserialization.

const std = @import("std");

/// Releases allocations owned by `value` when it was produced by Zerde
/// deserialization.
pub fn deinit(comptime T: type, allocator: std.mem.Allocator, value: T) void {
    switch (@typeInfo(T)) {
        .bool, .int, .comptime_int, .float, .comptime_float, .null, .@"enum", .enum_literal => {},
        .optional => |optional_info| {
            if (value) |child_value| deinit(optional_info.child, allocator, child_value);
        },
        .array => |array_info| {
            for (value) |item| deinit(array_info.child, allocator, item);
        },
        .pointer => |pointer_info| switch (pointer_info.size) {
            .slice => {
                if (pointer_info.child != u8) {
                    for (value) |item| deinit(pointer_info.child, allocator, item);
                }
                allocator.free(value);
            },
            else => {},
        },
        .@"struct" => |struct_info| {
            inline for (struct_info.fields) |field| {
                if (!field.is_comptime) deinit(field.type, allocator, @field(value, field.name));
            }
        },
        else => {},
    }
}

test "deinit frees owned string and slice fields" {
    const Value = struct {
        name: []const u8,
        scores: []const u16,
    };

    const allocator = std.testing.allocator;
    const name = try allocator.dupe(u8, "Ada");
    errdefer allocator.free(name);
    const scores = try allocator.dupe(u16, &.{ 10, 20, 30 });
    errdefer allocator.free(scores);

    deinit(Value, allocator, .{
        .name = name,
        .scores = scores,
    });
}

test "deinit frees nested structs arrays and optional owned fields" {
    const Child = struct {
        label: []const u8,
        aliases: []const []const u8,
    };
    const Parent = struct {
        child: Child,
        children: [2]Child,
        maybe_child: ?Child,
    };

    const allocator = std.testing.allocator;

    var value = Parent{
        .child = undefined,
        .children = undefined,
        .maybe_child = null,
    };
    var initialized_child = false;
    var initialized_children = [_]bool{false} ** 2;
    var initialized_maybe_child = false;
    errdefer {
        if (initialized_child) deinit(Child, allocator, value.child);
        inline for (0..2) |i| {
            if (initialized_children[i]) deinit(Child, allocator, value.children[i]);
        }
        if (initialized_maybe_child) deinit(Child, allocator, value.maybe_child.?);
    }

    value.child = try ownedChild(Child, allocator, "primary", &.{ "one", "two" });
    initialized_child = true;
    value.children[0] = try ownedChild(Child, allocator, "first", &.{"alpha"});
    initialized_children[0] = true;
    value.children[1] = try ownedChild(Child, allocator, "second", &.{ "beta", "gamma" });
    initialized_children[1] = true;
    value.maybe_child = try ownedChild(Child, allocator, "optional", &.{"maybe"});
    initialized_maybe_child = true;

    deinit(Parent, allocator, value);
}

test "deinit frees slices of owned structs" {
    const Item = struct {
        name: []const u8,
    };
    const Value = struct {
        items: []const Item,
    };

    const allocator = std.testing.allocator;
    const items = try allocator.alloc(Item, 2);
    var initialized: usize = 0;
    errdefer {
        for (items[0..initialized]) |item| deinit(Item, allocator, item);
        allocator.free(items);
    }

    items[0] = .{ .name = try allocator.dupe(u8, "one") };
    initialized += 1;
    items[1] = .{ .name = try allocator.dupe(u8, "two") };
    initialized += 1;

    deinit(Value, allocator, .{ .items = items });
}

fn ownedChild(
    comptime Child: type,
    allocator: std.mem.Allocator,
    label: []const u8,
    aliases: []const []const u8,
) !Child {
    const owned_label = try allocator.dupe(u8, label);
    errdefer allocator.free(owned_label);

    const owned_aliases = try allocator.alloc([]const u8, aliases.len);
    errdefer allocator.free(owned_aliases);
    var initialized: usize = 0;
    errdefer for (owned_aliases[0..initialized]) |alias| allocator.free(alias);

    for (aliases) |alias| {
        owned_aliases[initialized] = try allocator.dupe(u8, alias);
        initialized += 1;
    }

    return Child{
        .label = owned_label,
        .aliases = owned_aliases,
    };
}
