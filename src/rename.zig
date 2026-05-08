//! Field-name rename rules.

const std = @import("std");

/// Supported field-name rename policies.
pub const RenameRule = enum {
    none,
    snake_case,
    camel_case,
};

/// Applies a rename rule to a Zig field name at comptime.
pub fn apply(comptime rule: RenameRule, comptime name: []const u8) []const u8 {
    return switch (rule) {
        .none, .snake_case => name,
        .camel_case => camelCase(name),
    };
}

fn camelCase(comptime name: []const u8) []const u8 {
    return comptime blk: {
        var result: []const u8 = "";
        var upper_next = false;

        for (name) |char| {
            if (char == '_') {
                upper_next = true;
            } else {
                const renamed_char = if (upper_next) asciiUpper(char) else char;
                result = result ++ [_]u8{renamed_char};
                upper_next = false;
            }
        }

        break :blk result;
    };
}

fn asciiUpper(comptime char: u8) u8 {
    return if (char >= 'a' and char <= 'z') char - ('a' - 'A') else char;
}

test "rename applies supported rules" {
    try std.testing.expectEqualStrings("user_id", apply(.none, "user_id"));
    try std.testing.expectEqualStrings("user_id", apply(.snake_case, "user_id"));
    try std.testing.expectEqualStrings("userId", apply(.camel_case, "user_id"));
    try std.testing.expectEqualStrings("displayName", apply(.camel_case, "display_name"));
}
