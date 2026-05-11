//! Public root module for Zerde serialization APIs.

/// JSON format API.
pub const json = @import("json.zig");
/// TOML format API.
pub const toml = @import("toml.zig");
/// MessagePack format API.
pub const msgpack = @import("msgpack.zig");
/// CBOR format API.
pub const cbor = @import("cbor.zig");
/// Zig Object Notation format API.
pub const zon = @import("zon.zig");
/// Binary format API.
pub const binary = @import("binary.zig");
/// CSV and tab-delimited format API.
pub const csv = @import("csv.zig");
/// Human-readable format API.
pub const human = @import("human.zig");
/// Base64 helpers and byte wrapper type.
pub const base64 = @import("base64.zig");
/// Shared numeric parsing and conversion helpers.
pub const number = @import("number.zig");
/// Trait helpers for types supported by Zerde.
pub const traits = @import("traits.zig");
/// Structural event APIs for custom representations and transcoding.
pub const events = @import("events.zig");
/// Schema inspection and debug output APIs.
pub const schema = @import("schema.zig");

const datetime = @import("datetime.zig");

/// Wrapper type for serializing raw bytes as bytes rather than UTF-8 strings.
pub const Bytes = base64.Bytes;

/// Timestamp with seconds elapsed since the Unix epoch and nanosecond precision.
pub const Timestamp = datetime.Timestamp;

/// Local date: `YYYY-MM-DD`.
pub const LocalDate = datetime.LocalDate;
/// Local time: `HH:MM:SS[.fraction]`.
pub const LocalTime = datetime.LocalTime;
/// Local date-time: `YYYY-MM-DDTHH:MM:SS[.fraction]`.
pub const LocalDateTime = datetime.LocalDateTime;
/// Offset date-time: `YYYY-MM-DDTHH:MM:SS[.fraction]Z` or with `+/-HH:MM`.
pub const OffsetDateTime = datetime.OffsetDateTime;

/// Type-specialized codec namespace factory.
pub const Codec = @import("codec.zig").Codec;
/// Shared format selector for comptime dispatch APIs.
pub const Format = @import("format.zig").Format;

/// Generic type-directed serialization traversal.
pub const serialize = @import("serialize.zig").serialize;
/// Generic type-directed deserialization traversal.
pub const deserialize = @import("deserialize.zig").deserialize;
/// Generic structural event traversal from a decoder into a sink.
pub const consume = events.consume;
/// Generic structural event traversal from a decoder into an encoder sink.
pub const pipe = events.pipe;
/// Type-directed cleanup for values produced by Zerde deserialization.
pub const deinit = @import("deinit.zig").deinit;

test {
    _ = json;
    _ = toml;
    _ = msgpack;
    _ = cbor;
    _ = zon;
    _ = binary;
    _ = csv;
    _ = human;
    _ = base64;
    _ = number;
    _ = Bytes;
    _ = Timestamp;
    _ = LocalDate;
    _ = LocalTime;
    _ = LocalDateTime;
    _ = OffsetDateTime;
    _ = Codec;
    _ = Format;
    _ = serialize;
    _ = deserialize;
    _ = consume;
    _ = pipe;
    _ = deinit;
    _ = @import("meta.zig");
    _ = @import("format.zig");
    _ = schema;
    _ = @import("rename.zig");
    _ = @import("testing.zig");
    _ = traits;
    _ = events;
    _ = @import("containers.zig");
}
