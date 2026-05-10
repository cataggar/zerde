# root

## Navigation

- [API Index](README.md)

<details>
<summary>All documents</summary>

- [root](root.md)
- [json](json.md)
- [serialize](serialize.md)
- [base64](base64.md)
- [containers](containers.md)
- [meta](meta.md)
- [rename](rename.md)
- [deserialize](deserialize.md)
- [deinit](deinit.md)
- [number](number.md)
- [toml](toml.md)
- [datetime](datetime.md)
- [msgpack](msgpack.md)
- [zon](zon.md)
- [binary](binary.md)
- [csv](csv.md)
- [events](events.md)
- [human](human.md)
- [traits](traits.md)
- [codec](codec.md)
- [schema](schema.md)

</details>

## Overview

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
- [events](#import-events) `@import("events.zig")`
- [Codec](#import-codec) `@import("codec.zig")`
- [Format](#import-format) `@import("codec.zig")`
- [serialize](#import-serialize) `@import("serialize.zig")`
- [deserialize](#import-deserialize) `@import("deserialize.zig")`
- [deinit](#import-deinit) `@import("deinit.zig")`

<a id="import-json"></a>

## json

JSON format API.

```zig
pub const json = @import("json.zig");
```

<a id="import-toml"></a>

## toml

TOML format API.

```zig
pub const toml = @import("toml.zig");
```

<a id="import-msgpack"></a>

## msgpack

MessagePack format API.

```zig
pub const msgpack = @import("msgpack.zig");
```

<a id="import-zon"></a>

## zon

Zig Object Notation format API.

```zig
pub const zon = @import("zon.zig");
```

<a id="import-binary"></a>

## binary

Binary format API.

```zig
pub const binary = @import("binary.zig");
```

<a id="import-csv"></a>

## csv

CSV and tab-delimited format API.

```zig
pub const csv = @import("csv.zig");
```

<a id="import-human"></a>

## human

Human-readable format API.

```zig
pub const human = @import("human.zig");
```

<a id="import-base64"></a>

## base64

Base64 helpers and byte wrapper type.

```zig
pub const base64 = @import("base64.zig");
```

<a id="import-number"></a>

## number

Shared numeric parsing and conversion helpers.

```zig
pub const number = @import("number.zig");
```

<a id="import-traits"></a>

## traits

Trait helpers for types supported by Zerde.

```zig
pub const traits = @import("traits.zig");
```

<a id="import-events"></a>

## events

Structural event APIs for custom representations and transcoding.

```zig
pub const events = @import("events.zig");
```

<a id="alias-bytes"></a>

## Bytes

Wrapper type for serializing raw bytes as bytes rather than UTF-8 strings.

```zig
pub const Bytes = base64.Bytes;
```

References: [`base64.Bytes`](base64.md#type-bytes)

<a id="alias-timestamp"></a>

## Timestamp

[Timestamp](#alias-timestamp) with seconds elapsed since the Unix epoch and nanosecond precision.

```zig
pub const Timestamp = datetime.Timestamp;
```

References: [`datetime.Timestamp`](datetime.md#type-timestamp)

<a id="alias-localdate"></a>

## LocalDate

Local date: `YYYY-MM-DD`.

```zig
pub const LocalDate = datetime.LocalDate;
```

References: [`datetime.LocalDate`](datetime.md#type-localdate)

<a id="alias-localtime"></a>

## LocalTime

Local time: `HH:MM:SS[.fraction]`.

```zig
pub const LocalTime = datetime.LocalTime;
```

References: [`datetime.LocalTime`](datetime.md#type-localtime)

<a id="alias-localdatetime"></a>

## LocalDateTime

Local date-time: `YYYY-MM-DDTHH:MM:SS[.fraction]`.

```zig
pub const LocalDateTime = datetime.LocalDateTime;
```

References: [`datetime.LocalDateTime`](datetime.md#type-localdatetime)

<a id="alias-offsetdatetime"></a>

## OffsetDateTime

Offset date-time: `YYYY-MM-DDTHH:MM:SS[.fraction]Z` or with `+/-HH:MM`.

```zig
pub const OffsetDateTime = datetime.OffsetDateTime;
```

References: [`datetime.OffsetDateTime`](datetime.md#type-offsetdatetime)

<a id="import-codec"></a>

## Codec

Type-specialized codec namespace factory.

```zig
pub const Codec = @import("codec.zig").Codec;
```

<a id="import-format"></a>

## Format

Formats supported by the simple codec dispatch API.

```zig
pub const Format = @import("codec.zig").Format;
```

<a id="import-serialize"></a>

## serialize

Generic type-directed serialization traversal.

```zig
pub const serialize = @import("serialize.zig").serialize;
```

<a id="import-deserialize"></a>

## deserialize

Generic type-directed deserialization traversal.

```zig
pub const deserialize = @import("deserialize.zig").deserialize;
```

<a id="import-deinit"></a>

## deinit

Type-directed cleanup for values produced by Zerde deserialization.

```zig
pub const deinit = @import("deinit.zig").deinit;
```

