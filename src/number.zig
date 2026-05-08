//! Shared numeric token parsing, normalization, and typed conversion helpers.

const std = @import("std");

pub const SignPolicy = enum {
    none,
    negative,
    positive_and_negative,
};

pub const IntegerPrefixes = struct {
    binary: bool = false,
    octal: bool = false,
    hex: bool = false,
};

pub const IntegerBounds = struct {
    min: ?i128 = null,
    max: ?u128 = null,
};

pub const Syntax = struct {
    integer: bool = true,
    decimal_float: bool = false,
    exponent: bool = false,
    sign: SignPolicy = .negative,
    exponent_sign: SignPolicy = .positive_and_negative,
    digit_separator: ?u8 = null,
    prefixed_integers: IntegerPrefixes = .{},
    special_floats: bool = false,
    reject_leading_zero_decimal: bool = true,
    strip_leading_positive_sign: bool = true,
    integer_bounds: IntegerBounds = .{},
    integer_to_float: bool = false,
    finite_float_emission: bool = false,
};

pub const Integer = struct {
    bytes: []u8,
    base: u8,
};

pub const Token = union(enum) {
    int: Integer,
    float: []u8,

    pub fn deinit(self: Token, allocator: std.mem.Allocator) void {
        switch (self) {
            .int => |integer| allocator.free(integer.bytes),
            .float => |bytes| allocator.free(bytes),
        }
    }

    pub fn isFloat(self: Token) bool {
        return self == .float;
    }
};

pub fn Parser(comptime syntax: Syntax) type {
    return struct {
        const Self = @This();

        pub fn parseAlloc(allocator: std.mem.Allocator, raw: []const u8) !Token {
            if (syntax.special_floats and isSpecialFloat(raw)) {
                try validateSpecialFloatSyntax(raw);
                const normalized = try normalizeSpecialFloat(allocator, raw);
                errdefer allocator.free(normalized);
                try validateFloatBytes(normalized);
                return .{ .float = normalized };
            }

            if (raw.len >= 3 and raw[0] == '0') {
                if (raw[1] == 'x' and syntax.prefixed_integers.hex) return try parsePrefixedInteger(allocator, raw[2..], 16);
                if (raw[1] == 'o' and syntax.prefixed_integers.octal) return try parsePrefixedInteger(allocator, raw[2..], 8);
                if (raw[1] == 'b' and syntax.prefixed_integers.binary) return try parsePrefixedInteger(allocator, raw[2..], 2);
            }

            if (std.mem.indexOfAny(u8, raw, ".eE") != null) return try parseDecimalFloat(allocator, raw);
            return try parseDecimalInteger(allocator, raw);
        }

        pub fn parseOwned(allocator: std.mem.Allocator, raw: []u8) !Token {
            if (!needsNormalization()) {
                errdefer allocator.free(raw);
                const kind = try validateDecimal(raw);
                return switch (kind) {
                    .int => .{ .int = .{ .bytes = raw, .base = 10 } },
                    .float => .{ .float = raw },
                };
            }

            errdefer allocator.free(raw);
            const token = try Self.parseAlloc(allocator, raw);
            allocator.free(raw);
            return token;
        }

        pub fn readInt(comptime T: type, integer: Integer) !T {
            return try readInteger(T, integer);
        }

        pub fn readFloat(comptime T: type, token: Token) !T {
            return switch (token) {
                .float => |bytes| try readFloatBytes(T, bytes),
                .int => |integer| if (syntax.integer_to_float) try readFloatFromInteger(T, integer) else error.InvalidType,
            };
        }

        pub fn emitFloat(value: anytype) !void {
            if (syntax.finite_float_emission) try ensureFiniteFloat(value);
        }

        const DecimalKind = enum { int, float };

        fn parsePrefixedInteger(allocator: std.mem.Allocator, digits: []const u8, base: u8) !Token {
            if (!validDigitRun(digits, base)) return error.InvalidNumberSyntax;
            const normalized = try removeSeparators(allocator, digits);
            errdefer allocator.free(normalized);
            try validateIntegerBounds(normalized, base);
            return .{ .int = .{ .bytes = normalized, .base = base } };
        }

        fn parseDecimalInteger(allocator: std.mem.Allocator, raw: []const u8) !Token {
            if (!syntax.integer) return error.InvalidType;
            try validateDecimalIntegerSyntax(raw);
            const normalized = try normalizeDecimalNumber(allocator, raw);
            errdefer allocator.free(normalized);
            try validateIntegerBounds(normalized, 10);
            return .{ .int = .{ .bytes = normalized, .base = 10 } };
        }

        fn parseDecimalFloat(allocator: std.mem.Allocator, raw: []const u8) !Token {
            if (!syntax.decimal_float) return error.InvalidType;
            try validateDecimalFloatSyntax(raw);
            const normalized = try normalizeDecimalNumber(allocator, raw);
            errdefer allocator.free(normalized);
            try validateFloatBytes(normalized);
            return .{ .float = normalized };
        }

        fn validateDecimal(raw: []const u8) !DecimalKind {
            if (std.mem.indexOfAny(u8, raw, ".eE") != null) {
                if (!syntax.decimal_float) return error.InvalidType;
                try validateDecimalFloatSyntax(raw);
                return .float;
            }
            if (!syntax.integer) return error.InvalidType;
            try validateDecimalIntegerSyntax(raw);
            try validateIntegerBounds(raw, 10);
            return .int;
        }

        fn validateDecimalIntegerSyntax(raw: []const u8) !void {
            var index: usize = 0;
            try consumeLeadingSign(raw, &index, syntax.sign);
            if (index == raw.len) return error.InvalidNumberSyntax;
            if (!validDigitRun(raw[index..], 10)) return error.InvalidNumberSyntax;
            if (syntax.reject_leading_zero_decimal and hasInvalidLeadingZero(raw[index..])) return error.InvalidNumberSyntax;
        }

        fn validateDecimalFloatSyntax(raw: []const u8) !void {
            var index: usize = 0;
            try consumeLeadingSign(raw, &index, syntax.sign);
            if (index == raw.len) return error.InvalidNumberSyntax;

            const int_start = index;
            if (!consumeDigitRun(raw, &index, 10)) return error.InvalidNumberSyntax;
            if (syntax.reject_leading_zero_decimal and hasInvalidLeadingZero(raw[int_start..index])) return error.InvalidNumberSyntax;

            var saw_dot_or_exp = false;
            if (index < raw.len and raw[index] == '.') {
                saw_dot_or_exp = true;
                index += 1;
                if (!consumeDigitRun(raw, &index, 10)) return error.InvalidNumberSyntax;
            }

            if (index < raw.len and (raw[index] == 'e' or raw[index] == 'E')) {
                if (!syntax.exponent) return error.InvalidNumberSyntax;
                saw_dot_or_exp = true;
                index += 1;
                try consumeLeadingSign(raw, &index, syntax.exponent_sign);
                if (!consumeDigitRun(raw, &index, 10)) return error.InvalidNumberSyntax;
            }

            if (!saw_dot_or_exp or index != raw.len) return error.InvalidNumberSyntax;
        }

        fn validateSpecialFloatSyntax(raw: []const u8) !void {
            var index: usize = 0;
            try consumeLeadingSign(raw, &index, syntax.sign);
            const body = raw[index..];
            if (!std.mem.eql(u8, body, "inf") and !std.mem.eql(u8, body, "nan")) return error.InvalidNumberSyntax;
        }

        fn consumeLeadingSign(raw: []const u8, index: *usize, policy: SignPolicy) !void {
            if (index.* == raw.len) return;
            switch (raw[index.*]) {
                '-' => switch (policy) {
                    .none => return error.InvalidNumberSyntax,
                    .negative, .positive_and_negative => index.* += 1,
                },
                '+' => switch (policy) {
                    .positive_and_negative => index.* += 1,
                    .none, .negative => return error.InvalidNumberSyntax,
                },
                else => {},
            }
        }

        fn consumeDigitRun(raw: []const u8, index: *usize, base: u8) bool {
            const start = index.*;
            while (index.* < raw.len) {
                const byte = raw[index.*];
                if (syntax.digit_separator != null and byte == syntax.digit_separator.?) {
                    index.* += 1;
                    continue;
                }
                if (digitValue(byte, base) == null) break;
                index.* += 1;
            }
            return validDigitRun(raw[start..index.*], base);
        }

        fn validDigitRun(bytes: []const u8, base: u8) bool {
            if (bytes.len == 0) return false;
            var prev_was_digit = false;
            var saw_digit = false;
            for (bytes) |byte| {
                if (syntax.digit_separator != null and byte == syntax.digit_separator.?) {
                    if (!prev_was_digit) return false;
                    prev_was_digit = false;
                    continue;
                }
                if (digitValue(byte, base) == null) return false;
                prev_was_digit = true;
                saw_digit = true;
            }
            return saw_digit and prev_was_digit;
        }

        fn hasInvalidLeadingZero(digits: []const u8) bool {
            if (digits[0] != '0') return false;
            var count: usize = 0;
            for (digits) |byte| {
                if (syntax.digit_separator == null or byte != syntax.digit_separator.?) count += 1;
            }
            return count > 1;
        }

        fn normalizeDecimalNumber(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
            var out = std.Io.Writer.Allocating.init(allocator);
            errdefer out.deinit();
            for (bytes, 0..) |byte, i| {
                if (syntax.digit_separator != null and byte == syntax.digit_separator.?) continue;
                if (syntax.strip_leading_positive_sign and byte == '+' and i == 0) continue;
                try out.writer.writeByte(byte);
            }
            return try out.toOwnedSlice();
        }

        fn removeSeparators(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
            if (syntax.digit_separator == null) return try allocator.dupe(u8, bytes);
            var out = std.Io.Writer.Allocating.init(allocator);
            errdefer out.deinit();
            for (bytes) |byte| if (byte != syntax.digit_separator.?) try out.writer.writeByte(byte);
            return try out.toOwnedSlice();
        }

        fn validateIntegerBounds(bytes: []const u8, base: u8) !void {
            if (syntax.integer_bounds.min == null and syntax.integer_bounds.max == null) return;

            if (bytes.len != 0 and bytes[0] == '-') {
                const value = std.fmt.parseInt(i128, bytes, base) catch |err| switch (err) {
                    error.Overflow => return error.IntegerOverflow,
                    error.InvalidCharacter => return error.InvalidValue,
                };
                if (syntax.integer_bounds.min) |min| if (value < min) return error.IntegerOverflow;
                return;
            }

            const value = std.fmt.parseInt(u128, bytes, base) catch |err| switch (err) {
                error.Overflow => return error.IntegerOverflow,
                error.InvalidCharacter => return error.InvalidValue,
            };
            if (syntax.integer_bounds.max) |max| if (value > max) return error.IntegerOverflow;
        }

        fn needsNormalization() bool {
            return syntax.digit_separator != null or syntax.strip_leading_positive_sign or syntax.special_floats or
                syntax.prefixed_integers.binary or syntax.prefixed_integers.octal or syntax.prefixed_integers.hex;
        }
    };
}

pub fn readInteger(comptime T: type, integer: Integer) !T {
    if (@typeInfo(T).int.signedness == .unsigned and integer.bytes.len != 0 and integer.bytes[0] == '-') return error.InvalidValue;
    return std.fmt.parseInt(T, integer.bytes, integer.base) catch |err| switch (err) {
        error.Overflow => error.IntegerOverflow,
        error.InvalidCharacter => error.InvalidValue,
    };
}

pub fn readFloatBytes(comptime T: type, bytes: []const u8) !T {
    return std.fmt.parseFloat(T, bytes) catch error.InvalidValue;
}

pub fn readFloatFromInteger(comptime T: type, integer: Integer) !T {
    if (integer.bytes.len != 0 and integer.bytes[0] == '-') {
        const value = std.fmt.parseInt(i128, integer.bytes, integer.base) catch return error.InvalidValue;
        return @floatFromInt(value);
    }
    const value = std.fmt.parseInt(u128, integer.bytes, integer.base) catch return error.InvalidValue;
    return @floatFromInt(value);
}

pub fn ensureFiniteFloat(value: anytype) !void {
    const Float = switch (@typeInfo(@TypeOf(value))) {
        .comptime_float => f64,
        else => @TypeOf(value),
    };
    const finite_value: Float = value;
    if (!std.math.isFinite(finite_value)) return error.InvalidJsonFloat;
}

fn validateFloatBytes(bytes: []const u8) !void {
    _ = std.fmt.parseFloat(f64, bytes) catch return error.InvalidValue;
}

fn isSpecialFloat(raw: []const u8) bool {
    const body = if (raw.len != 0 and (raw[0] == '+' or raw[0] == '-')) raw[1..] else raw;
    return std.mem.eql(u8, body, "inf") or std.mem.eql(u8, body, "nan");
}

fn normalizeSpecialFloat(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    if (raw.len != 0 and raw[0] == '+') return try allocator.dupe(u8, raw[1..]);
    return try allocator.dupe(u8, raw);
}

fn digitValue(byte: u8, base: u8) ?u8 {
    const value: u8 = switch (byte) {
        '0'...'9' => byte - '0',
        'a'...'f' => byte - 'a' + 10,
        'A'...'F' => byte - 'A' + 10,
        else => return null,
    };
    if (value >= base) return null;
    return value;
}

test "number parser supports JSON-style numbers" {
    const JsonNumber = Parser(.{ .decimal_float = true, .exponent = true });
    const allocator = std.testing.allocator;

    var int = try JsonNumber.parseAlloc(allocator, "-42");
    defer int.deinit(allocator);
    try std.testing.expectEqual(@as(i32, -42), try JsonNumber.readInt(i32, int.int));

    var float = try JsonNumber.parseAlloc(allocator, "1e+10");
    defer float.deinit(allocator);
    try std.testing.expectEqual(@as(f64, 1e10), try JsonNumber.readFloat(f64, float));

    try std.testing.expectError(error.InvalidNumberSyntax, JsonNumber.parseAlloc(allocator, "+1"));
    try std.testing.expectError(error.InvalidNumberSyntax, JsonNumber.parseAlloc(allocator, "01"));
}

test "number parser enforces sign policies" {
    const allocator = std.testing.allocator;
    const NoSign = Parser(.{ .sign = .none, .strip_leading_positive_sign = false });
    const Signed = Parser(.{ .sign = .positive_and_negative });

    var unsigned = try NoSign.parseAlloc(allocator, "42");
    defer unsigned.deinit(allocator);
    try std.testing.expectEqual(@as(u8, 42), try NoSign.readInt(u8, unsigned.int));

    try std.testing.expectError(error.InvalidNumberSyntax, NoSign.parseAlloc(allocator, "-1"));
    try std.testing.expectError(error.InvalidNumberSyntax, NoSign.parseAlloc(allocator, "+1"));

    var positive = try Signed.parseAlloc(allocator, "+42");
    defer positive.deinit(allocator);
    try std.testing.expectEqualStrings("42", positive.int.bytes);
    try std.testing.expectEqual(@as(i16, 42), try Signed.readInt(i16, positive.int));
}

test "number parser gates decimal floats and exponents" {
    const allocator = std.testing.allocator;
    const IntegersOnly = Parser(.{});
    const DecimalFloat = Parser(.{ .decimal_float = true, .exponent = false });

    try std.testing.expectError(error.InvalidType, IntegersOnly.parseAlloc(allocator, "1.5"));

    var fractional = try DecimalFloat.parseAlloc(allocator, "1.5");
    defer fractional.deinit(allocator);
    try std.testing.expectEqual(@as(f32, 1.5), try DecimalFloat.readFloat(f32, fractional));

    try std.testing.expectError(error.InvalidNumberSyntax, DecimalFloat.parseAlloc(allocator, "1e2"));
    try std.testing.expectError(error.InvalidNumberSyntax, DecimalFloat.parseAlloc(allocator, "1."));
    try std.testing.expectError(error.InvalidNumberSyntax, DecimalFloat.parseAlloc(allocator, ".5"));
}

test "number parser validates digit separators" {
    const allocator = std.testing.allocator;
    const Separated = Parser(.{ .digit_separator = '_' });

    var grouped = try Separated.parseAlloc(allocator, "1_000_000");
    defer grouped.deinit(allocator);
    try std.testing.expectEqualStrings("1000000", grouped.int.bytes);
    try std.testing.expectEqual(@as(u64, 1_000_000), try Separated.readInt(u64, grouped.int));

    try std.testing.expectError(error.InvalidNumberSyntax, Separated.parseAlloc(allocator, "_1"));
    try std.testing.expectError(error.InvalidNumberSyntax, Separated.parseAlloc(allocator, "1_"));
    try std.testing.expectError(error.InvalidNumberSyntax, Separated.parseAlloc(allocator, "1__0"));
}

test "number parser supports configured prefixed integer bases" {
    const allocator = std.testing.allocator;
    const DecimalOnly = Parser(.{});
    const Prefixed = Parser(.{ .prefixed_integers = .{ .binary = true, .octal = true, .hex = true }, .digit_separator = '_' });

    try std.testing.expectError(error.InvalidNumberSyntax, DecimalOnly.parseAlloc(allocator, "0x10"));

    var hex = try Prefixed.parseAlloc(allocator, "0xdead_beef");
    defer hex.deinit(allocator);
    try std.testing.expectEqual(@as(u64, 0xdead_beef), try Prefixed.readInt(u64, hex.int));

    var octal = try Prefixed.parseAlloc(allocator, "0o755");
    defer octal.deinit(allocator);
    try std.testing.expectEqual(@as(u16, 0o755), try Prefixed.readInt(u16, octal.int));

    var binary = try Prefixed.parseAlloc(allocator, "0b1010_0101");
    defer binary.deinit(allocator);
    try std.testing.expectEqual(@as(u8, 0b1010_0101), try Prefixed.readInt(u8, binary.int));

    try std.testing.expectError(error.InvalidNumberSyntax, Prefixed.parseAlloc(allocator, "+0x1"));
    try std.testing.expectError(error.InvalidNumberSyntax, Prefixed.parseAlloc(allocator, "0b102"));
}

test "number parser enforces configured integer bounds" {
    const allocator = std.testing.allocator;
    const I64Bounded = Parser(.{
        .sign = .positive_and_negative,
        .integer_bounds = .{ .min = std.math.minInt(i64), .max = @intCast(std.math.maxInt(i64)) },
    });

    var min = try I64Bounded.parseAlloc(allocator, "-9223372036854775808");
    defer min.deinit(allocator);
    try std.testing.expectEqual(@as(i64, std.math.minInt(i64)), try I64Bounded.readInt(i64, min.int));

    var max = try I64Bounded.parseAlloc(allocator, "9223372036854775807");
    defer max.deinit(allocator);
    try std.testing.expectEqual(@as(i64, std.math.maxInt(i64)), try I64Bounded.readInt(i64, max.int));

    try std.testing.expectError(error.IntegerOverflow, I64Bounded.parseAlloc(allocator, "-9223372036854775809"));
    try std.testing.expectError(error.IntegerOverflow, I64Bounded.parseAlloc(allocator, "9223372036854775808"));
}

test "number parser controls integer to float conversion" {
    const allocator = std.testing.allocator;
    const StrictFloat = Parser(.{ .decimal_float = true });
    const CoercingFloat = Parser(.{ .decimal_float = true, .integer_to_float = true });

    var integer = try StrictFloat.parseAlloc(allocator, "42");
    defer integer.deinit(allocator);
    try std.testing.expectError(error.InvalidType, StrictFloat.readFloat(f64, integer));
    try std.testing.expectEqual(@as(f64, 42.0), try CoercingFloat.readFloat(f64, integer));
}

test "number parser maps typed conversion errors" {
    const allocator = std.testing.allocator;
    const Signed = Parser(.{});

    var negative = try Signed.parseAlloc(allocator, "-1");
    defer negative.deinit(allocator);
    try std.testing.expectError(error.InvalidValue, Signed.readInt(u8, negative.int));

    var large = try Signed.parseAlloc(allocator, "300");
    defer large.deinit(allocator);
    try std.testing.expectError(error.IntegerOverflow, Signed.readInt(u8, large.int));
}

test "number parser normalizes and signs special floats" {
    const allocator = std.testing.allocator;
    const TomlSpecial = Parser(.{ .decimal_float = true, .sign = .positive_and_negative, .special_floats = true });
    const NoPositiveSign = Parser(.{ .decimal_float = true, .sign = .negative, .special_floats = true });

    var positive_inf = try TomlSpecial.parseAlloc(allocator, "+inf");
    defer positive_inf.deinit(allocator);
    try std.testing.expectEqualStrings("inf", positive_inf.float);
    try std.testing.expect(std.math.isPositiveInf(try TomlSpecial.readFloat(f64, positive_inf)));

    var negative_nan = try TomlSpecial.parseAlloc(allocator, "-nan");
    defer negative_nan.deinit(allocator);
    try std.testing.expect(std.math.isNan(try TomlSpecial.readFloat(f64, negative_nan)));

    try std.testing.expectError(error.InvalidNumberSyntax, NoPositiveSign.parseAlloc(allocator, "+nan"));
}

test "number parser validates finite float emission when configured" {
    const JsonNumber = Parser(.{ .finite_float_emission = true });
    const PermissiveNumber = Parser(.{});

    try JsonNumber.emitFloat(@as(f64, 1.25));
    try std.testing.expectError(error.InvalidJsonFloat, JsonNumber.emitFloat(std.math.inf(f64)));
    try PermissiveNumber.emitFloat(std.math.inf(f64));
}

test "number parser supports TOML-style numbers" {
    const TomlNumber = Parser(.{
        .decimal_float = true,
        .exponent = true,
        .sign = .positive_and_negative,
        .digit_separator = '_',
        .prefixed_integers = .{ .binary = true, .octal = true, .hex = true },
        .special_floats = true,
        .integer_bounds = .{ .min = std.math.minInt(i64), .max = @intCast(std.math.maxInt(i64)) },
        .integer_to_float = true,
    });
    const allocator = std.testing.allocator;

    var hex = try TomlNumber.parseAlloc(allocator, "0xdead_beef");
    defer hex.deinit(allocator);
    try std.testing.expectEqual(@as(u64, 0xdead_beef), try TomlNumber.readInt(u64, hex.int));

    var grouped = try TomlNumber.parseAlloc(allocator, "+224_617.445_991_228");
    defer grouped.deinit(allocator);
    try std.testing.expectEqual(@as(f64, 224617.445991228), try TomlNumber.readFloat(f64, grouped));

    var nan = try TomlNumber.parseAlloc(allocator, "+nan");
    defer nan.deinit(allocator);
    try std.testing.expect(std.math.isNan(try TomlNumber.readFloat(f64, nan)));

    try std.testing.expectError(error.InvalidNumberSyntax, TomlNumber.parseAlloc(allocator, "1__0"));
    try std.testing.expectError(error.IntegerOverflow, TomlNumber.parseAlloc(allocator, "9223372036854775808"));
}
