# datetime

## Navigation

- [API Index](README.md)
- Previous: [toml](toml.md)
- Next: [msgpack](msgpack.md)

## Overview

First-class date and time value types.

## Types

- [Timestamp](#type-timestamp)
- [LocalDate](#type-localdate)
- [LocalTime](#type-localtime)
- [LocalDateTime](#type-localdatetime)
- [OffsetDateTime](#type-offsetdatetime)

<a id="type-timestamp"></a>

## Timestamp

[Timestamp](#type-timestamp) with seconds elapsed since the Unix epoch and nanosecond precision.

```zig
pub const Timestamp = struct {
    /// Seconds elapsed since 1970-01-01 00:00:00 UTC.
    seconds: i64,
    /// Nanoseconds within the current second.
    nanoseconds: u32 = 0,
};
```

### Nested Declarations

| Name | Signature | Return Type | Description |
| --- | --- | --- | --- |
| [zerdeWrite](#fn-timestamp-zerdewrite) | `pub fn zerdeWrite(self: Timestamp, enc: anytype) !void` | `!void` | Serializes as a MessagePack timestamp extension when supported, otherwise as a struct. |
| [zerdeRead](#fn-timestamp-zerderead) | `pub fn zerdeRead(allocator: std.mem.Allocator, dec: anytype) !Timestamp` | `!Timestamp` | Deserializes from a MessagePack timestamp extension when supported, otherwise from a struct. |

<a id="fn-timestamp-zerdewrite"></a>

### Timestamp.zerdeWrite

Serializes as a MessagePack timestamp extension when supported, otherwise as a struct.

```zig
pub fn zerdeWrite(self: Timestamp, enc: anytype) !void
```

References: [`Timestamp`](#type-timestamp)

<a id="fn-timestamp-zerderead"></a>

### Timestamp.zerdeRead

Deserializes from a MessagePack timestamp extension when supported, otherwise from a struct.

```zig
pub fn zerdeRead(allocator: std.mem.Allocator, dec: anytype) !Timestamp
```

References: [`Timestamp`](#type-timestamp)

<a id="type-localdate"></a>

## LocalDate

Local date: `YYYY-MM-DD`.

```zig
pub const LocalDate = struct {
    year: u16,
    month: u8,
    day: u8,
};
```

### Nested Declarations

| Name | Signature | Return Type | Description |
| --- | --- | --- | --- |
| [parse](#fn-localdate-parse) | `pub fn parse(input: []const u8) !LocalDate` | `!LocalDate` | Parses a &#96;YYYY-MM-DD&#96; local date. |
| [format](#fn-localdate-format) | `pub fn format(self: LocalDate, writer: *std.Io.Writer) !void` | `!void` | Writes this date as &#96;YYYY-MM-DD&#96;. |
| [zerdeWrite](#fn-localdate-zerdewrite) | `pub fn zerdeWrite(self: LocalDate, enc: anytype) !void` | `!void` | Serializes this date as a native datetime token when supported, otherwise as a string. |
| [zerdeRead](#fn-localdate-zerderead) | `pub fn zerdeRead(allocator: std.mem.Allocator, dec: anytype) !LocalDate` | `!LocalDate` | Deserializes a local date from a native datetime token or string. |

<a id="fn-localdate-parse"></a>

### LocalDate.parse

Parses a `YYYY-MM-DD` local date.

```zig
pub fn parse(input: []const u8) !LocalDate
```

References: [`LocalDate`](#type-localdate)

<a id="fn-localdate-format"></a>

### LocalDate.format

Writes this date as `YYYY-MM-DD`.

```zig
pub fn format(self: LocalDate, writer: *std.Io.Writer) !void
```

References: [`LocalDate`](#type-localdate)

<a id="fn-localdate-zerdewrite"></a>

### LocalDate.zerdeWrite

Serializes this date as a native datetime token when supported, otherwise as a string.

```zig
pub fn zerdeWrite(self: LocalDate, enc: anytype) !void
```

References: [`LocalDate`](#type-localdate)

<a id="fn-localdate-zerderead"></a>

### LocalDate.zerdeRead

Deserializes a local date from a native datetime token or string.

```zig
pub fn zerdeRead(allocator: std.mem.Allocator, dec: anytype) !LocalDate
```

References: [`LocalDate`](#type-localdate)

<a id="type-localtime"></a>

## LocalTime

Local time: `HH:MM:SS[.fraction]`.

```zig
pub const LocalTime = struct {
    hour: u8,
    minute: u8,
    second: u8,
    nanosecond: u32 = 0,
};
```

### Nested Declarations

| Name | Signature | Return Type | Description |
| --- | --- | --- | --- |
| [parse](#fn-localtime-parse) | `pub fn parse(input: []const u8) !LocalTime` | `!LocalTime` | Parses a &#96;HH:MM:SS[.fraction]&#96; local time. |
| [format](#fn-localtime-format) | `pub fn format(self: LocalTime, writer: *std.Io.Writer) !void` | `!void` | Writes this time as &#96;HH:MM:SS[.fraction]&#96;. |
| [zerdeWrite](#fn-localtime-zerdewrite) | `pub fn zerdeWrite(self: LocalTime, enc: anytype) !void` | `!void` | Serializes this time as a native datetime token when supported, otherwise as a string. |
| [zerdeRead](#fn-localtime-zerderead) | `pub fn zerdeRead(allocator: std.mem.Allocator, dec: anytype) !LocalTime` | `!LocalTime` | Deserializes a local time from a native datetime token or string. |

<a id="fn-localtime-parse"></a>

### LocalTime.parse

Parses a `HH:MM:SS[.fraction]` local time.

```zig
pub fn parse(input: []const u8) !LocalTime
```

References: [`LocalTime`](#type-localtime)

<a id="fn-localtime-format"></a>

### LocalTime.format

Writes this time as `HH:MM:SS[.fraction]`.

```zig
pub fn format(self: LocalTime, writer: *std.Io.Writer) !void
```

References: [`LocalTime`](#type-localtime)

<a id="fn-localtime-zerdewrite"></a>

### LocalTime.zerdeWrite

Serializes this time as a native datetime token when supported, otherwise as a string.

```zig
pub fn zerdeWrite(self: LocalTime, enc: anytype) !void
```

References: [`LocalTime`](#type-localtime)

<a id="fn-localtime-zerderead"></a>

### LocalTime.zerdeRead

Deserializes a local time from a native datetime token or string.

```zig
pub fn zerdeRead(allocator: std.mem.Allocator, dec: anytype) !LocalTime
```

References: [`LocalTime`](#type-localtime)

<a id="type-localdatetime"></a>

## LocalDateTime

Local date-time: `YYYY-MM-DDTHH:MM:SS[.fraction]`.

```zig
pub const LocalDateTime = struct {
    date: LocalDate,
    time: LocalTime,
};
```

### Nested Declarations

| Name | Signature | Return Type | Description |
| --- | --- | --- | --- |
| [parse](#fn-localdatetime-parse) | `pub fn parse(input: []const u8) !LocalDateTime` | `!LocalDateTime` | Parses a &#96;YYYY-MM-DDTHH:MM:SS[.fraction]&#96; local date-time. |
| [format](#fn-localdatetime-format) | `pub fn format(self: LocalDateTime, writer: *std.Io.Writer) !void` | `!void` | Writes this date-time as &#96;YYYY-MM-DDTHH:MM:SS[.fraction]&#96;. |
| [zerdeWrite](#fn-localdatetime-zerdewrite) | `pub fn zerdeWrite(self: LocalDateTime, enc: anytype) !void` | `!void` | Serializes this date-time as a native datetime token when supported, otherwise as a string. |
| [zerdeRead](#fn-localdatetime-zerderead) | `pub fn zerdeRead(allocator: std.mem.Allocator, dec: anytype) !LocalDateTime` | `!LocalDateTime` | Deserializes a local date-time from a native datetime token or string. |

<a id="fn-localdatetime-parse"></a>

### LocalDateTime.parse

Parses a `YYYY-MM-DDTHH:MM:SS[.fraction]` local date-time.

```zig
pub fn parse(input: []const u8) !LocalDateTime
```

References: [`LocalDateTime`](#type-localdatetime)

<a id="fn-localdatetime-format"></a>

### LocalDateTime.format

Writes this date-time as `YYYY-MM-DDTHH:MM:SS[.fraction]`.

```zig
pub fn format(self: LocalDateTime, writer: *std.Io.Writer) !void
```

References: [`LocalDateTime`](#type-localdatetime)

<a id="fn-localdatetime-zerdewrite"></a>

### LocalDateTime.zerdeWrite

Serializes this date-time as a native datetime token when supported, otherwise as a string.

```zig
pub fn zerdeWrite(self: LocalDateTime, enc: anytype) !void
```

References: [`LocalDateTime`](#type-localdatetime)

<a id="fn-localdatetime-zerderead"></a>

### LocalDateTime.zerdeRead

Deserializes a local date-time from a native datetime token or string.

```zig
pub fn zerdeRead(allocator: std.mem.Allocator, dec: anytype) !LocalDateTime
```

References: [`LocalDateTime`](#type-localdatetime)

<a id="type-offsetdatetime"></a>

## OffsetDateTime

Offset date-time: `YYYY-MM-DDTHH:MM:SS[.fraction]Z` or with `+/-HH:MM`.

```zig
pub const OffsetDateTime = struct {
    date: LocalDate,
    time: LocalTime,
    offset_minutes: i16,
};
```

### Nested Declarations

| Name | Signature | Return Type | Description |
| --- | --- | --- | --- |
| [parse](#fn-offsetdatetime-parse) | `pub fn parse(input: []const u8) !OffsetDateTime` | `!OffsetDateTime` | Parses an offset date-time ending in &#96;Z&#96; or a &#96;+/-HH:MM&#96; offset. |
| [format](#fn-offsetdatetime-format) | `pub fn format(self: OffsetDateTime, writer: *std.Io.Writer) !void` | `!void` | Writes this date-time with a &#96;Z&#96; or &#96;+/-HH:MM&#96; offset. |
| [zerdeWrite](#fn-offsetdatetime-zerdewrite) | `pub fn zerdeWrite(self: OffsetDateTime, enc: anytype) !void` | `!void` | Serializes this date-time as a native datetime token when supported, otherwise as a string. |
| [zerdeRead](#fn-offsetdatetime-zerderead) | `pub fn zerdeRead(allocator: std.mem.Allocator, dec: anytype) !OffsetDateTime` | `!OffsetDateTime` | Deserializes an offset date-time from a native datetime token or string. |

<a id="fn-offsetdatetime-parse"></a>

### OffsetDateTime.parse

Parses an offset date-time ending in `Z` or a `+/-HH:MM` offset.

```zig
pub fn parse(input: []const u8) !OffsetDateTime
```

References: [`OffsetDateTime`](#type-offsetdatetime)

<a id="fn-offsetdatetime-format"></a>

### OffsetDateTime.format

Writes this date-time with a `Z` or `+/-HH:MM` offset.

```zig
pub fn format(self: OffsetDateTime, writer: *std.Io.Writer) !void
```

References: [`OffsetDateTime`](#type-offsetdatetime)

<a id="fn-offsetdatetime-zerdewrite"></a>

### OffsetDateTime.zerdeWrite

Serializes this date-time as a native datetime token when supported, otherwise as a string.

```zig
pub fn zerdeWrite(self: OffsetDateTime, enc: anytype) !void
```

References: [`OffsetDateTime`](#type-offsetdatetime)

<a id="fn-offsetdatetime-zerderead"></a>

### OffsetDateTime.zerdeRead

Deserializes an offset date-time from a native datetime token or string.

```zig
pub fn zerdeRead(allocator: std.mem.Allocator, dec: anytype) !OffsetDateTime
```

References: [`OffsetDateTime`](#type-offsetdatetime)

