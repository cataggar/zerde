# datetime

## Navigation

- [API Index](README.md)
- Previous: [toml](toml.md)
- Next: [msgpack](msgpack.md)

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
pub const Timestamp = struct { ... };
```

### Fields

```zig
    seconds: i64
    nanoseconds: u32 = 0
```

`seconds`: Seconds elapsed since 1970-01-01 00:00:00 UTC.
`nanoseconds`: Nanoseconds within the current second.

### Nested Declarations

- [zerdeWrite](#fn-timestamp-zerdewrite)
- [zerdeRead](#fn-timestamp-zerderead)

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
pub const LocalDate = struct { ... };
```

### Fields

```zig
    year: u16
    month: u8
    day: u8
```


### Nested Declarations

- [parse](#fn-localdate-parse)
- [format](#fn-localdate-format)
- [zerdeWrite](#fn-localdate-zerdewrite)
- [zerdeRead](#fn-localdate-zerderead)

<a id="fn-localdate-parse"></a>

### LocalDate.parse

```zig
pub fn parse(input: []const u8) !LocalDate
```

References: [`LocalDate`](#type-localdate)

<a id="fn-localdate-format"></a>

### LocalDate.format

```zig
pub fn format(self: LocalDate, writer: *std.Io.Writer) !void
```

References: [`LocalDate`](#type-localdate)

<a id="fn-localdate-zerdewrite"></a>

### LocalDate.zerdeWrite

```zig
pub fn zerdeWrite(self: LocalDate, enc: anytype) !void
```

References: [`LocalDate`](#type-localdate)

<a id="fn-localdate-zerderead"></a>

### LocalDate.zerdeRead

```zig
pub fn zerdeRead(allocator: std.mem.Allocator, dec: anytype) !LocalDate
```

References: [`LocalDate`](#type-localdate)

<a id="type-localtime"></a>

## LocalTime

Local time: `HH:MM:SS[.fraction]`.

```zig
pub const LocalTime = struct { ... };
```

### Fields

```zig
    hour: u8
    minute: u8
    second: u8
    nanosecond: u32 = 0
```


### Nested Declarations

- [parse](#fn-localtime-parse)
- [format](#fn-localtime-format)
- [zerdeWrite](#fn-localtime-zerdewrite)
- [zerdeRead](#fn-localtime-zerderead)

<a id="fn-localtime-parse"></a>

### LocalTime.parse

```zig
pub fn parse(input: []const u8) !LocalTime
```

References: [`LocalTime`](#type-localtime)

<a id="fn-localtime-format"></a>

### LocalTime.format

```zig
pub fn format(self: LocalTime, writer: *std.Io.Writer) !void
```

References: [`LocalTime`](#type-localtime)

<a id="fn-localtime-zerdewrite"></a>

### LocalTime.zerdeWrite

```zig
pub fn zerdeWrite(self: LocalTime, enc: anytype) !void
```

References: [`LocalTime`](#type-localtime)

<a id="fn-localtime-zerderead"></a>

### LocalTime.zerdeRead

```zig
pub fn zerdeRead(allocator: std.mem.Allocator, dec: anytype) !LocalTime
```

References: [`LocalTime`](#type-localtime)

<a id="type-localdatetime"></a>

## LocalDateTime

Local date-time: `YYYY-MM-DDTHH:MM:SS[.fraction]`.

```zig
pub const LocalDateTime = struct { ... };
```

### Fields

```zig
    date: LocalDate
    time: LocalTime
```


### Nested Declarations

- [parse](#fn-localdatetime-parse)
- [format](#fn-localdatetime-format)
- [zerdeWrite](#fn-localdatetime-zerdewrite)
- [zerdeRead](#fn-localdatetime-zerderead)

<a id="fn-localdatetime-parse"></a>

### LocalDateTime.parse

```zig
pub fn parse(input: []const u8) !LocalDateTime
```

References: [`LocalDateTime`](#type-localdatetime)

<a id="fn-localdatetime-format"></a>

### LocalDateTime.format

```zig
pub fn format(self: LocalDateTime, writer: *std.Io.Writer) !void
```

References: [`LocalDateTime`](#type-localdatetime)

<a id="fn-localdatetime-zerdewrite"></a>

### LocalDateTime.zerdeWrite

```zig
pub fn zerdeWrite(self: LocalDateTime, enc: anytype) !void
```

References: [`LocalDateTime`](#type-localdatetime)

<a id="fn-localdatetime-zerderead"></a>

### LocalDateTime.zerdeRead

```zig
pub fn zerdeRead(allocator: std.mem.Allocator, dec: anytype) !LocalDateTime
```

References: [`LocalDateTime`](#type-localdatetime)

<a id="type-offsetdatetime"></a>

## OffsetDateTime

Offset date-time: `YYYY-MM-DDTHH:MM:SS[.fraction]Z` or with `+/-HH:MM`.

```zig
pub const OffsetDateTime = struct { ... };
```

### Fields

```zig
    date: LocalDate
    time: LocalTime
    offset_minutes: i16
```


### Nested Declarations

- [parse](#fn-offsetdatetime-parse)
- [format](#fn-offsetdatetime-format)
- [zerdeWrite](#fn-offsetdatetime-zerdewrite)
- [zerdeRead](#fn-offsetdatetime-zerderead)

<a id="fn-offsetdatetime-parse"></a>

### OffsetDateTime.parse

```zig
pub fn parse(input: []const u8) !OffsetDateTime
```

References: [`OffsetDateTime`](#type-offsetdatetime)

<a id="fn-offsetdatetime-format"></a>

### OffsetDateTime.format

```zig
pub fn format(self: OffsetDateTime, writer: *std.Io.Writer) !void
```

References: [`OffsetDateTime`](#type-offsetdatetime)

<a id="fn-offsetdatetime-zerdewrite"></a>

### OffsetDateTime.zerdeWrite

```zig
pub fn zerdeWrite(self: OffsetDateTime, enc: anytype) !void
```

References: [`OffsetDateTime`](#type-offsetdatetime)

<a id="fn-offsetdatetime-zerderead"></a>

### OffsetDateTime.zerdeRead

```zig
pub fn zerdeRead(allocator: std.mem.Allocator, dec: anytype) !OffsetDateTime
```

References: [`OffsetDateTime`](#type-offsetdatetime)

