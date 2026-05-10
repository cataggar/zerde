# number

## Navigation

- [API Index](README.md)
- Previous: [deinit](deinit.md)
- Next: [toml](toml.md)

## Overview

Shared numeric token parsing, normalization, and typed conversion helpers.

## Functions

- [Parser](#fn-parser)
- [readInteger](#fn-readinteger)
- [readFloatBytes](#fn-readfloatbytes)
- [readFloatFromInteger](#fn-readfloatfrominteger)
- [ensureFiniteFloat](#fn-ensurefinitefloat)

## Types

- [SignPolicy](#type-signpolicy)
- [IntegerPrefixes](#type-integerprefixes)
- [IntegerBounds](#type-integerbounds)
- [Syntax](#type-syntax)
- [Integer](#type-integer)
- [Token](#type-token)

<a id="type-signpolicy"></a>

## SignPolicy

Allowed leading sign forms for a numeric token.

```zig
pub const SignPolicy = enum {
    /// Reject both `+` and `-`.
    none,
    /// Accept `-` only.
    negative,
    /// Accept both `+` and `-`.
    positive_and_negative,
};
```

<a id="type-integerprefixes"></a>

## IntegerPrefixes

[Integer](#type-integer) radix prefixes accepted by a syntax.

```zig
pub const IntegerPrefixes = struct {
    /// Accept `0b` binary integers.
    binary: bool = false,
    /// Accept `0o` octal integers.
    octal: bool = false,
    /// Accept `0x` hexadecimal integers.
    hex: bool = false,
};
```

<a id="type-integerbounds"></a>

## IntegerBounds

Optional normalized integer bounds checked during token parsing.

```zig
pub const IntegerBounds = struct {
    /// Minimum signed integer value accepted by the syntax.
    min: ?i128 = null,
    /// Maximum non-negative integer value accepted by the syntax.
    max: ?u128 = null,
};
```

<a id="type-syntax"></a>

## Syntax

Numeric grammar and conversion capabilities for a format.

```zig
pub const Syntax = struct {
    /// Accept integer tokens.
    integer: bool = true,
    /// Accept decimal float tokens with a fractional part or exponent.
    decimal_float: bool = false,
    /// Accept exponent notation on decimal floats.
    exponent: bool = false,
    /// Leading sign policy for integers, decimal floats, and special floats.
    sign: SignPolicy = .negative,
    /// Sign policy for exponent signs.
    exponent_sign: SignPolicy = .positive_and_negative,
    /// Optional digit separator that is allowed between digits and stripped.
    digit_separator: ?u8 = null,
    /// Accepted non-decimal integer prefixes.
    prefixed_integers: IntegerPrefixes = .{},
    /// Accept `inf` and `nan` special float tokens.
    special_floats: bool = false,
    /// Reject multi-digit decimal numbers whose integer part starts with zero.
    reject_leading_zero_decimal: bool = true,
    /// Remove a leading `+` from normalized decimal and special-float tokens.
    strip_leading_positive_sign: bool = true,
    /// Optional bounds for parsed integer tokens before type-directed reads.
    integer_bounds: IntegerBounds = .{},
    /// Permit reading integer tokens through `readFloat`.
    integer_to_float: bool = false,
    /// Reject non-finite values from `emitFloat`.
    finite_float_emission: bool = false,
};
```

<a id="type-integer"></a>

## Integer

Normalized integer token bytes and their radix.

```zig
pub const Integer = struct {
    /// Allocator-owned normalized digits, including `-` when negative.
    bytes: []u8,
    /// Integer radix used to parse `bytes`.
    base: u8,
};
```

<a id="type-token"></a>

## Token

Allocator-owned normalized numeric token.

```zig
pub const Token = union(enum) {
    /// Integer token with normalized digits and radix.
    int: Integer,
    /// Float token with normalized decimal or special-float bytes.
    float: []u8,
};
```

### Nested Declarations

- [deinit](#fn-token-deinit)
- [isFloat](#fn-token-isfloat)

<a id="fn-token-deinit"></a>

### Token.deinit

Frees the token bytes owned by `self`.

```zig
pub fn deinit(self: Token, allocator: std.mem.Allocator) void
```

References: [`Token`](#type-token)

<a id="fn-token-isfloat"></a>

### Token.isFloat

Returns whether this token is a float token.

```zig
pub fn isFloat(self: Token) bool
```

References: [`Token`](#type-token)

<a id="fn-parser"></a>

## Parser

Returns a numeric parser specialized for `syntax`.

```zig
pub fn Parser(comptime syntax: Syntax) type
```

References: [`Syntax`](#type-syntax)

<a id="fn-readinteger"></a>

## readInteger

Converts a normalized integer token to `T`.

```zig
pub fn readInteger(comptime T: type, integer: Integer) !T
```

References: [`Integer`](#type-integer)

<a id="fn-readfloatbytes"></a>

## readFloatBytes

Parses normalized float bytes into `T`.

```zig
pub fn readFloatBytes(comptime T: type, bytes: []const u8) !T
```

<a id="fn-readfloatfrominteger"></a>

## readFloatFromInteger

Converts a normalized integer token to a float `T`.

```zig
pub fn readFloatFromInteger(comptime T: type, integer: Integer) !T
```

References: [`Integer`](#type-integer)

<a id="fn-ensurefinitefloat"></a>

## ensureFiniteFloat

Returns `error.InvalidJsonFloat` if `value` is not finite.

```zig
pub fn ensureFiniteFloat(value: anytype) !void
```

