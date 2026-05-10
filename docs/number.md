# number

## Navigation

- [API Index](README.md)
- Previous: [deinit](deinit.md)
- Next: [toml](toml.md)

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

```zig
pub const SignPolicy = enum { ... };
```

Allowed leading sign forms for a numeric token.

<a id="type-integerprefixes"></a>

## IntegerPrefixes

```zig
pub const IntegerPrefixes = struct { ... };
```

[Integer](#type-integer) radix prefixes accepted by a syntax.

### Fields

```zig
    binary: bool = false
    octal: bool = false
    hex: bool = false
```

`binary`: Accept `0b` binary integers.
`octal`: Accept `0o` octal integers.
`hex`: Accept `0x` hexadecimal integers.

<a id="type-integerbounds"></a>

## IntegerBounds

```zig
pub const IntegerBounds = struct { ... };
```

Optional normalized integer bounds checked during token parsing.

### Fields

```zig
    min: ?i128 = null
    max: ?u128 = null
```

`min`: Minimum signed integer value accepted by the syntax.
`max`: Maximum non-negative integer value accepted by the syntax.

<a id="type-syntax"></a>

## Syntax

```zig
pub const Syntax = struct { ... };
```

Numeric grammar and conversion capabilities for a format.

### Fields

```zig
    integer: bool = true
    decimal_float: bool = false
    exponent: bool = false
    sign: SignPolicy = .negative
    exponent_sign: SignPolicy = .positive_and_negative
    digit_separator: ?u8 = null
    prefixed_integers: IntegerPrefixes = .{}
    special_floats: bool = false
    reject_leading_zero_decimal: bool = true
    strip_leading_positive_sign: bool = true
    integer_bounds: IntegerBounds = .{}
    integer_to_float: bool = false
    finite_float_emission: bool = false
```

`integer`: Accept integer tokens.
`decimal_float`: Accept decimal float tokens with a fractional part or exponent.
`exponent`: Accept exponent notation on decimal floats.
`sign`: Leading sign policy for integers, decimal floats, and special floats.
`exponent_sign`: Sign policy for exponent signs.
`digit_separator`: Optional digit separator that is allowed between digits and stripped.
`prefixed_integers`: Accepted non-decimal integer prefixes.
`special_floats`: Accept `inf` and `nan` special float tokens.
`reject_leading_zero_decimal`: Reject multi-digit decimal numbers whose integer part starts with zero.
`strip_leading_positive_sign`: Remove a leading `+` from normalized decimal and special-float tokens.
`integer_bounds`: Optional bounds for parsed integer tokens before type-directed reads.
`integer_to_float`: Permit reading integer tokens through `readFloat`.
`finite_float_emission`: Reject non-finite values from `emitFloat`.

<a id="type-integer"></a>

## Integer

```zig
pub const Integer = struct { ... };
```

Normalized integer token bytes and their radix.

### Fields

```zig
    bytes: []u8
    base: u8
```

`bytes`: Allocator-owned normalized digits, including `-` when negative.
`base`: [Integer](#type-integer) radix used to parse `bytes`.

<a id="type-token"></a>

## Token

```zig
pub const Token = union(enum) { ... };
```

Allocator-owned normalized numeric token.

### Fields

```zig
    int: Integer
    float: []u8
```

`int`: [Integer](#type-integer) token with normalized digits and radix.
`float`: Float token with normalized decimal or special-float bytes.

### Nested Declarations

- [deinit](#fn-token-deinit)
- [isFloat](#fn-token-isfloat)

<a id="fn-token-deinit"></a>

### Token.deinit

```zig
pub fn deinit(self: Token, allocator: std.mem.Allocator) void
```

References: [`Token`](#type-token)

Frees the token bytes owned by `self`.

<a id="fn-token-isfloat"></a>

### Token.isFloat

```zig
pub fn isFloat(self: Token) bool
```

References: [`Token`](#type-token)

Returns whether this token is a float token.

<a id="fn-parser"></a>

## Parser

```zig
pub fn Parser(comptime syntax: Syntax) type
```

References: [`Syntax`](#type-syntax)

Returns a numeric parser specialized for `syntax`.

<a id="fn-readinteger"></a>

## readInteger

```zig
pub fn readInteger(comptime T: type, integer: Integer) !T
```

References: [`Integer`](#type-integer)

Converts a normalized integer token to `T`.

<a id="fn-readfloatbytes"></a>

## readFloatBytes

```zig
pub fn readFloatBytes(comptime T: type, bytes: []const u8) !T
```

Parses normalized float bytes into `T`.

<a id="fn-readfloatfrominteger"></a>

## readFloatFromInteger

```zig
pub fn readFloatFromInteger(comptime T: type, integer: Integer) !T
```

References: [`Integer`](#type-integer)

Converts a normalized integer token to a float `T`.

<a id="fn-ensurefinitefloat"></a>

## ensureFiniteFloat

```zig
pub fn ensureFiniteFloat(value: anytype) !void
```

Returns `error.InvalidJsonFloat` if `value` is not finite.

