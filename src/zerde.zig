//! Public root module for Zerde serialization APIs.

/// JSON format API.
pub const json = @import("formats/json.zig");
/// Debug format API for human-readable serialization output.
pub const debug = @import("formats/debug.zig");

/// Type-specialized codec namespace factory.
pub const Codec = @import("codec.zig").Codec;

/// Generic type-directed serialization traversal.
pub const serialize = @import("serialize.zig").serialize;
/// Generic type-directed deserialization traversal.
pub const deserialize = @import("deserialize.zig").deserialize;
/// Type-directed cleanup for values produced by Zerde deserialization.
pub const deinit = @import("deinit.zig").deinit;

test {
    _ = json;
    _ = debug;
    _ = Codec;
    _ = serialize;
    _ = deserialize;
    _ = deinit;
    _ = @import("meta.zig");
    _ = @import("schema.zig");
    _ = @import("internal/rename.zig");
    _ = @import("internal/testing.zig");
    _ = @import("internal/traits.zig");
}
