//! Metadata parsing and validation helpers.

const std = @import("std");

const rename = @import("rename.zig");

/// Normalized type-level metadata options.
pub const Options = struct {
    rename_all: rename.RenameRule = .none,
    deny_unknown_fields: bool = false,
};

/// Normalized field-level metadata options.
pub const FieldOptions = struct {
    rename: ?[]const u8 = null,
    skip: bool = false,
    skip_serializing: bool = false,
    skip_deserializing: bool = false,
};

/// Returns normalized metadata options for `T`.
pub fn optionsFor(comptime T: type) Options {
    var options = Options{};

    if (!@hasDecl(T, "zerde")) return options;

    const metadata = T.zerde;
    validateMetadataStruct(@TypeOf(metadata), "type metadata");
    validateKnownOptions(@TypeOf(metadata), .type_metadata, "type metadata");

    if (@hasField(@TypeOf(metadata), "rename_all")) {
        options.rename_all = @field(metadata, "rename_all");
    }
    if (@hasField(@TypeOf(metadata), "deny_unknown_fields")) {
        options.deny_unknown_fields = @field(metadata, "deny_unknown_fields");
    }

    return options;
}

/// Validates metadata options for `T` at comptime.
pub fn validate(comptime T: type, comptime options: Options) void {
    _ = options;

    if (!@hasDecl(T, "zerde")) return;

    const metadata = T.zerde;
    validateMetadataStruct(@TypeOf(metadata), "type metadata");
    validateKnownOptions(@TypeOf(metadata), .type_metadata, "type metadata");

    if (@hasField(@TypeOf(metadata), "fields")) {
        const fields_metadata = @field(metadata, "fields");
        validateMetadataStruct(@TypeOf(fields_metadata), "field metadata set");

        inline for (@typeInfo(@TypeOf(fields_metadata)).@"struct".fields) |field_metadata| {
            if (!hasField(T, field_metadata.name)) {
                @compileError("zerde metadata references unknown field '" ++ field_metadata.name ++ "' on " ++ @typeName(T));
            }

            const field_value = @field(fields_metadata, field_metadata.name);
            validateMetadataStruct(@TypeOf(field_value), "metadata for field '" ++ field_metadata.name ++ "'");
            validateKnownOptions(@TypeOf(field_value), .field_metadata, "metadata for field '" ++ field_metadata.name ++ "'");

            _ = parseFieldOptions(field_value);
        }
    }
}

/// Returns normalized metadata options for one field of `T`.
pub fn fieldOptionsFor(comptime T: type, comptime field_name: []const u8) FieldOptions {
    if (!@hasDecl(T, "zerde")) return .{};

    const metadata = T.zerde;
    if (!@hasField(@TypeOf(metadata), "fields")) return .{};

    const fields_metadata = @field(metadata, "fields");
    if (!@hasField(@TypeOf(fields_metadata), field_name)) return .{};

    return parseFieldOptions(@field(fields_metadata, field_name));
}

/// Returns true when a field should be included in serialized output.
pub fn shouldSerialize(comptime field_options: FieldOptions) bool {
    return !field_options.skip and !field_options.skip_serializing;
}

/// Returns true when a field should be read from input.
pub fn shouldDeserialize(comptime field_options: FieldOptions) bool {
    return !field_options.skip and !field_options.skip_deserializing;
}

/// Returns the serialized wire name for a field.
pub fn fieldWireName(
    comptime field_name: []const u8,
    comptime field_options: FieldOptions,
    comptime options: Options,
) []const u8 {
    if (field_options.rename) |explicit_name| return explicit_name;
    return rename.apply(options.rename_all, field_name);
}

fn parseFieldOptions(comptime metadata: anytype) FieldOptions {
    var options = FieldOptions{};
    const Metadata = @TypeOf(metadata);

    if (@hasField(Metadata, "rename")) options.rename = @field(metadata, "rename");
    if (@hasField(Metadata, "skip")) options.skip = @field(metadata, "skip");
    if (@hasField(Metadata, "skip_serializing")) options.skip_serializing = @field(metadata, "skip_serializing");
    if (@hasField(Metadata, "skip_deserializing")) options.skip_deserializing = @field(metadata, "skip_deserializing");

    return options;
}

fn validateMetadataStruct(comptime T: type, comptime label: []const u8) void {
    switch (@typeInfo(T)) {
        .@"struct" => |struct_info| {
            if (!struct_info.is_tuple) return;
        },
        else => {},
    }

    @compileError("zerde " ++ label ++ " must be a struct literal");
}

const MetadataOptionSet = enum {
    type_metadata,
    field_metadata,
};

fn validateKnownOptions(comptime T: type, comptime allowed: MetadataOptionSet, comptime label: []const u8) void {
    const actual_count = comptime @typeInfo(T).@"struct".fields.len;
    const known_count = comptime countKnownOptions(T, allowed);

    if (actual_count != known_count) @compileError("unknown zerde " ++ label ++ " option");
}

fn countKnownOptions(comptime T: type, comptime allowed: MetadataOptionSet) usize {
    comptime var count: usize = 0;

    inline for (@typeInfo(T).@"struct".fields) |field| {
        if (comptime isKnownOptionName(allowed, field.name)) count += 1;
    }

    return count;
}

fn isKnownOptionName(comptime allowed: MetadataOptionSet, comptime name: []const u8) bool {
    return switch (allowed) {
        .type_metadata => comptimeEql(name, "rename_all") or comptimeEql(name, "deny_unknown_fields") or comptimeEql(name, "fields"),
        .field_metadata => comptimeEql(name, "rename") or comptimeEql(name, "skip") or comptimeEql(name, "skip_serializing") or comptimeEql(name, "skip_deserializing"),
    };
}

fn comptimeEql(comptime a: []const u8, comptime b: []const u8) bool {
    return comptime std.mem.eql(u8, a, b);
}

fn hasField(comptime T: type, comptime field_name: []const u8) bool {
    switch (@typeInfo(T)) {
        .@"struct" => |struct_info| {
            inline for (struct_info.fields) |field| {
                if (std.mem.eql(u8, field.name, field_name)) return true;
            }
            return false;
        },
        else => return false,
    }
}

test "metadata returns defaults without zerde decl" {
    const User = struct {
        id: u64,
    };

    const options = optionsFor(User);
    try std.testing.expectEqual(rename.RenameRule.none, options.rename_all);
    try std.testing.expect(!options.deny_unknown_fields);
    try std.testing.expectEqual(FieldOptions{}, fieldOptionsFor(User, "id"));
}

test "metadata parses type and field options" {
    const User = struct {
        user_id: u64,
        password_hash: []const u8,

        pub const zerde = .{
            .rename_all = .camel_case,
            .deny_unknown_fields = true,
            .fields = .{
                .password_hash = .{
                    .rename = "password",
                    .skip_serializing = true,
                    .skip_deserializing = true,
                },
            },
        };
    };

    const options = optionsFor(User);
    const password_options = comptime fieldOptionsFor(User, "password_hash");

    try std.testing.expectEqual(rename.RenameRule.camel_case, options.rename_all);
    try std.testing.expect(options.deny_unknown_fields);
    try std.testing.expectEqualStrings("password", password_options.rename.?);
    try std.testing.expect(password_options.skip_serializing);
    try std.testing.expect(password_options.skip_deserializing);
    try std.testing.expectEqualStrings("userId", comptime fieldWireName("user_id", fieldOptionsFor(User, "user_id"), optionsFor(User)));
    try std.testing.expectEqualStrings("password", comptime fieldWireName("password_hash", password_options, optionsFor(User)));
}

test "metadata parses skip and skip_serializing separately" {
    const User = struct {
        token: []const u8,
        password_hash: []const u8,

        pub const zerde = .{
            .fields = .{
                .token = .{ .skip = true },
                .password_hash = .{ .skip_serializing = true },
            },
        };
    };

    const token_options = comptime fieldOptionsFor(User, "token");
    const password_options = comptime fieldOptionsFor(User, "password_hash");

    try std.testing.expect(token_options.skip);
    try std.testing.expect(!token_options.skip_serializing);
    try std.testing.expect(!password_options.skip);
    try std.testing.expect(password_options.skip_serializing);
    try std.testing.expect(!password_options.skip_deserializing);
    try std.testing.expect(!shouldSerialize(token_options));
    try std.testing.expect(!shouldSerialize(password_options));
    try std.testing.expect(!shouldDeserialize(token_options));
    try std.testing.expect(shouldDeserialize(password_options));
}

test "metadata declarations do not affect value layout" {
    const Plain = struct {
        user_id: u64,
        display_name: []const u8,
    };
    const WithMetadata = struct {
        user_id: u64,
        display_name: []const u8,

        pub const zerde = .{
            .rename_all = .camel_case,
            .fields = .{
                .display_name = .{ .rename = "name" },
            },
        };
    };

    try std.testing.expectEqual(@sizeOf(Plain), @sizeOf(WithMetadata));
    try std.testing.expectEqual(@alignOf(Plain), @alignOf(WithMetadata));
}
