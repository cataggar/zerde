# root

## Navigation

- [API Index](README.md)
- Next: [json](json.md)

Public root module for Zerde serialization APIs.

## Aliases

- [Bytes](#alias-bytes)
- [Timestamp](#alias-timestamp)
- [LocalDate](#alias-localdate)
- [LocalTime](#alias-localtime)
- [LocalDateTime](#alias-localdatetime)
- [OffsetDateTime](#alias-offsetdatetime)

## Imports

- [json](#import-json) `@import("json.zig")`
- [toml](#import-toml) `@import("toml.zig")`
- [msgpack](#import-msgpack) `@import("msgpack.zig")`
- [zon](#import-zon) `@import("zon.zig")`
- [binary](#import-binary) `@import("binary.zig")`
- [csv](#import-csv) `@import("csv.zig")`
- [human](#import-human) `@import("human.zig")`
- [base64](#import-base64) `@import("base64.zig")`
- [number](#import-number) `@import("number.zig")`
- [traits](#import-traits) `@import("traits.zig")`
- [Codec](#import-codec) `@import("codec.zig")`
- [Format](#import-format) `@import("codec.zig")`
- [serialize](#import-serialize) `@import("serialize.zig")`
- [deserialize](#import-deserialize) `@import("deserialize.zig")`
- [deinit](#import-deinit) `@import("deinit.zig")`

<a id="import-json"></a>

## json

```zig
pub const json = @import("json.zig");
```

JSON format API.

<a id="import-toml"></a>

## toml

```zig
pub const toml = @import("toml.zig");
```

TOML format API.

<a id="import-msgpack"></a>

## msgpack

```zig
pub const msgpack = @import("msgpack.zig");
```

MessagePack format API.

<a id="import-zon"></a>

## zon

```zig
pub const zon = @import("zon.zig");
```

Zig Object Notation format API.

<a id="import-binary"></a>

## binary

```zig
pub const binary = @import("binary.zig");
```

Binary format API.

<a id="import-csv"></a>

## csv

```zig
pub const csv = @import("csv.zig");
```

CSV and tab-delimited format API.

<a id="import-human"></a>

## human

```zig
pub const human = @import("human.zig");
```

Human-readable format API.

<a id="import-base64"></a>

## base64

```zig
pub const base64 = @import("base64.zig");
```

Base64 helpers and byte wrapper type.

<a id="import-number"></a>

## number

```zig
pub const number = @import("number.zig");
```

Shared numeric parsing and conversion helpers.

<a id="import-traits"></a>

## traits

```zig
pub const traits = @import("traits.zig");
```

Trait helpers for types supported by Zerde.

<a id="alias-bytes"></a>

## Bytes

```zig
pub const Bytes = base64.Bytes;
```

References: [`base64.Bytes`](base64.md#type-bytes)

Wrapper type for serializing raw bytes as bytes rather than UTF-8 strings.

<a id="alias-timestamp"></a>

## Timestamp

```zig
pub const Timestamp = datetime.Timestamp;
```

References: [`datetime.Timestamp`](datetime.md#type-timestamp)

[Timestamp](#alias-timestamp) with seconds elapsed since the Unix epoch and nanosecond precision.

<a id="alias-localdate"></a>

## LocalDate

```zig
pub const LocalDate = datetime.LocalDate;
```

References: [`datetime.LocalDate`](datetime.md#type-localdate)

Local date: `YYYY-MM-DD`.

<a id="alias-localtime"></a>

## LocalTime

```zig
pub const LocalTime = datetime.LocalTime;
```

References: [`datetime.LocalTime`](datetime.md#type-localtime)

Local time: `HH:MM:SS[.fraction]`.

<a id="alias-localdatetime"></a>

## LocalDateTime

```zig
pub const LocalDateTime = datetime.LocalDateTime;
```

References: [`datetime.LocalDateTime`](datetime.md#type-localdatetime)

Local date-time: `YYYY-MM-DDTHH:MM:SS[.fraction]`.

<a id="alias-offsetdatetime"></a>

## OffsetDateTime

```zig
pub const OffsetDateTime = datetime.OffsetDateTime;
```

References: [`datetime.OffsetDateTime`](datetime.md#type-offsetdatetime)

Offset date-time: `YYYY-MM-DDTHH:MM:SS[.fraction]Z` or with `+/-HH:MM`.

<a id="import-codec"></a>

## Codec

```zig
pub const Codec = @import("codec.zig").Codec;
```

Type-specialized codec namespace factory.

<a id="import-format"></a>

## Format

```zig
pub const Format = @import("codec.zig").Format;
```

Formats supported by the simple codec dispatch API.

<a id="import-serialize"></a>

## serialize

```zig
pub const serialize = @import("serialize.zig").serialize;
```

Generic type-directed serialization traversal.

<a id="import-deserialize"></a>

## deserialize

```zig
pub const deserialize = @import("deserialize.zig").deserialize;
```

Generic type-directed deserialization traversal.

<a id="import-deinit"></a>

## deinit

```zig
pub const deinit = @import("deinit.zig").deinit;
```

Type-directed cleanup for values produced by Zerde deserialization.

