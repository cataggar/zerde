//! Metadata parsing and validation helpers.

const std = @import("std");

const base64 = @import("base64.zig");
const rename = @import("rename.zig");

/// Normalized type-level metadata options.
pub const Options = struct {
    rename_all: rename.RenameRule = .none,
    deny_unknown_fields: bool = false,
    union_repr: UnionRepr = .external,
};

/// Supported tagged union wire representations.
pub const UnionRepr = enum {
    external,
    internal,
    adjacent,
};

pub const union_tag_field_name = "tag";
pub const union_content_field_name = "value";

/// Normalized field-level metadata options.
pub const FieldOptions = struct {
    rename: ?[]const u8 = null,
    skip: bool = false,
    skip_serializing: bool = false,
    skip_deserializing: bool = false,
    with: ?type = null,
    serialize_with: ?type = null,
    deserialize_with: ?type = null,
    bytes: bool = false,
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
    if (@hasField(@TypeOf(metadata), "union_repr")) {
        options.union_repr = @field(metadata, "union_repr");
    }

    return options;
}

/// Validates metadata options for `T` at comptime.
pub fn validate(comptime T: type, comptime options: Options) void {
    @setEvalBranchQuota(100_000);
    _ = options;

    if (!@hasDecl(T, "zerde")) return;

    const metadata = T.zerde;
    validateMetadataStruct(@TypeOf(metadata), "type metadata");
    validateKnownOptions(@TypeOf(metadata), .type_metadata, "type metadata");
    validateUnionOptions(T, metadata);

    if (@hasField(@TypeOf(metadata), "fields")) {
        const fields_metadata = @field(metadata, "fields");
        validateMetadataStruct(@TypeOf(fields_metadata), "field metadata set");

        inline for (@typeInfo(@TypeOf(fields_metadata)).@"struct".fields) |field_metadata| {
            if (!hasField(T, field_metadata.name)) {
                @compileError("zerde metadata references unknown field '" ++ field_metadata.name ++ "' on " ++ @typeName(T));
            }

            const field = fieldByName(T, field_metadata.name);
            const field_value = @field(fields_metadata, field_metadata.name);
            validateMetadataStruct(@TypeOf(field_value), "metadata for field '" ++ field_metadata.name ++ "'");
            validateKnownOptions(@TypeOf(field_value), .field_metadata, "metadata for field '" ++ field_metadata.name ++ "'");

            const field_options = parseFieldOptions(field_value);
            validateFieldHooks(field_options, "metadata for field '" ++ field_metadata.name ++ "'");
            validateBytesField(field.type, field_options, "metadata for field '" ++ field_metadata.name ++ "'");
        }
    }
}

fn validateUnionOptions(comptime T: type, comptime metadata: anytype) void {
    if (!@hasField(@TypeOf(metadata), "union_repr")) return;

    switch (@typeInfo(T)) {
        .@"union" => |union_info| {
            if (union_info.tag_type == null) {
                @compileError("zerde union_repr requires a tagged union on " ++ @typeName(T));
            }

            const repr = @field(metadata, "union_repr");
            if (repr == .internal) {
                inline for (union_info.fields) |field| {
                    if (field.type != void and @typeInfo(field.type) != .@"struct") {
                        @compileError("zerde internal union_repr requires struct or void variants on " ++ @typeName(T));
                    }
                    validateInternalUnionPayload(T, field);
                }
            }
        },
        else => @compileError("zerde union_repr is only valid on tagged unions"),
    }
}

fn validateInternalUnionPayload(comptime Union: type, comptime variant: std.builtin.Type.UnionField) void {
    if (variant.type == void) return;

    const Payload = variant.type;
    const payload_info = @typeInfo(Payload).@"struct";
    const payload_options = optionsFor(Payload);

    inline for (payload_info.fields) |field| {
        if (!field.is_comptime) {
            const field_options = fieldOptionsFor(Payload, field.name);
            if (shouldSerialize(field_options) or shouldDeserialize(field_options)) {
                const wire_name = fieldWireName(field.name, field_options, payload_options);
                if (comptime std.mem.eql(u8, wire_name, union_tag_field_name)) {
                    @compileError("zerde internal union_repr payload field '" ++ field.name ++ "' conflicts with tag field on " ++ @typeName(Union));
                }
            }
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

/// Returns the effective field serialization hook, if configured.
pub fn serializeHook(comptime field_options: FieldOptions) ?type {
    if (field_options.serialize_with) |Hook| return Hook;
    return field_options.with;
}

/// Returns the effective field deserialization hook, if configured.
pub fn deserializeHook(comptime field_options: FieldOptions) ?type {
    if (field_options.deserialize_with) |Hook| return Hook;
    return field_options.with;
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
    if (@hasField(Metadata, "with")) options.with = @field(metadata, "with");
    if (@hasField(Metadata, "serialize_with")) options.serialize_with = @field(metadata, "serialize_with");
    if (@hasField(Metadata, "deserialize_with")) options.deserialize_with = @field(metadata, "deserialize_with");
    if (@hasField(Metadata, "bytes")) options.bytes = @field(metadata, "bytes");

    return options;
}

fn validateFieldHooks(comptime options: FieldOptions, comptime label: []const u8) void {
    if (options.with) |Hook| {
        validateHookMethod(Hook, "serialize", label);
        validateHookMethod(Hook, "deserialize", label);
    }
    if (options.serialize_with) |Hook| validateHookMethod(Hook, "serialize", label);
    if (options.deserialize_with) |Hook| validateHookMethod(Hook, "deserialize", label);
}

fn validateHookMethod(comptime Hook: type, comptime method_name: []const u8, comptime label: []const u8) void {
    switch (@typeInfo(Hook)) {
        .@"struct", .@"union", .@"enum", .@"opaque" => {},
        else => @compileError("zerde " ++ label ++ " custom hook must be a container type"),
    }

    if (!@hasDecl(Hook, method_name)) {
        @compileError("zerde " ++ label ++ " custom hook " ++ @typeName(Hook) ++ " is missing '" ++ method_name ++ "'");
    }

    switch (@typeInfo(@TypeOf(@field(Hook, method_name)))) {
        .@"fn" => |fn_info| {
            const expected_params = if (comptimeEql(method_name, "serialize")) 2 else 3;
            if (fn_info.params.len != expected_params) {
                @compileError("zerde " ++ label ++ " custom hook '" ++ method_name ++ "' has the wrong number of parameters");
            }
        },
        else => @compileError("zerde " ++ label ++ " custom hook '" ++ method_name ++ "' must be a function"),
    }
}

fn validateBytesField(comptime T: type, comptime options: FieldOptions, comptime label: []const u8) void {
    if (!options.bytes) return;
    if (!base64.isByteType(T)) @compileError("zerde " ++ label ++ " bytes option requires Bytes, [N]u8, []u8, or []const u8");
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
        .type_metadata => comptimeEql(name, "rename_all") or comptimeEql(name, "deny_unknown_fields") or comptimeEql(name, "union_repr") or comptimeEql(name, "fields"),
        .field_metadata => comptimeEql(name, "rename") or comptimeEql(name, "skip") or comptimeEql(name, "skip_serializing") or comptimeEql(name, "skip_deserializing") or comptimeEql(name, "with") or comptimeEql(name, "serialize_with") or comptimeEql(name, "deserialize_with") or comptimeEql(name, "bytes"),
    };
}

fn comptimeEql(comptime a: []const u8, comptime b: []const u8) bool {
    return comptime std.mem.eql(u8, a, b);
}

fn hasField(comptime T: type, comptime field_name: []const u8) bool {
    switch (@typeInfo(T)) {
        .@"struct" => |struct_info| {
            inline for (struct_info.fields) |field| {
                if (comptime std.mem.eql(u8, field.name, field_name)) return true;
            }
            return false;
        },
        else => return false,
    }
}

fn fieldByName(comptime T: type, comptime field_name: []const u8) std.builtin.Type.StructField {
    const struct_info = @typeInfo(T).@"struct";
    inline for (struct_info.fields) |field| {
        if (comptime std.mem.eql(u8, field.name, field_name)) return field;
    }
    unreachable;
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
    const UnixTimestamp = struct {
        pub fn serialize(value: i64, encoder: anytype) !void {
            try encoder.emitInt(value);
        }

        pub fn deserialize(comptime T: type, allocator: std.mem.Allocator, decoder: anytype) !T {
            _ = allocator;
            return try decoder.readInt(T);
        }
    };

    const User = struct {
        user_id: u64,
        password_hash: []const u8,
        created_at: i64,

        pub const zerde = .{
            .rename_all = .camel_case,
            .deny_unknown_fields = true,
            .fields = .{
                .password_hash = .{
                    .rename = "password",
                    .skip_serializing = true,
                    .skip_deserializing = true,
                },
                .created_at = .{ .with = UnixTimestamp },
            },
        };
    };

    const options = optionsFor(User);
    const password_options = comptime fieldOptionsFor(User, "password_hash");
    const timestamp_options = comptime fieldOptionsFor(User, "created_at");

    try std.testing.expectEqual(rename.RenameRule.camel_case, options.rename_all);
    try std.testing.expect(options.deny_unknown_fields);
    try std.testing.expectEqualStrings("password", password_options.rename.?);
    try std.testing.expect(password_options.skip_serializing);
    try std.testing.expect(password_options.skip_deserializing);
    try std.testing.expectEqual(UnixTimestamp, timestamp_options.with.?);
    try std.testing.expectEqual(UnixTimestamp, serializeHook(timestamp_options).?);
    try std.testing.expectEqual(UnixTimestamp, deserializeHook(timestamp_options).?);
    try std.testing.expectEqualStrings("userId", comptime fieldWireName("user_id", fieldOptionsFor(User, "user_id"), optionsFor(User)));
    try std.testing.expectEqualStrings("password", comptime fieldWireName("password_hash", password_options, optionsFor(User)));
}

test "metadata parses union representation" {
    const Event = union(enum) {
        started: struct { at: u64 },
        stopped,

        pub const zerde = .{ .union_repr = .internal };
    };

    try std.testing.expectEqual(UnionRepr.internal, optionsFor(Event).union_repr);
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
