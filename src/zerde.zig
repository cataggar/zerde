//! Public root module for Zerde serialization APIs.

/// JSON format API.
pub const json = @import("json.zig");
/// TOML format API.
pub const toml = @import("toml.zig");
/// Human-readable format API.
pub const human = @import("human.zig");
/// Base64 helpers and byte wrapper type.
pub const base64 = @import("base64.zig");
/// Shared numeric parsing and conversion helpers.
pub const number = @import("number.zig");

/// Wrapper type for serializing raw bytes as bytes rather than UTF-8 strings.
pub const Bytes = base64.Bytes;

/// Type-specialized codec namespace factory.
pub const Codec = @import("codec.zig").Codec;
/// Formats supported by the simple codec dispatch API.
pub const Format = @import("codec.zig").Format;

/// Generic type-directed serialization traversal.
pub const serialize = @import("serialize.zig").serialize;
/// Generic type-directed deserialization traversal.
pub const deserialize = @import("deserialize.zig").deserialize;
/// Type-directed cleanup for values produced by Zerde deserialization.
pub const deinit = @import("deinit.zig").deinit;

test {
    _ = json;
    _ = toml;
    _ = human;
    _ = base64;
    _ = number;
    _ = Bytes;
    _ = @import("datetime.zig");
    _ = Codec;
    _ = Format;
    _ = serialize;
    _ = deserialize;
    _ = deinit;
    _ = @import("meta.zig");
    _ = @import("schema.zig");
    _ = @import("rename.zig");
    _ = @import("testing.zig");
    _ = @import("traits.zig");
}
