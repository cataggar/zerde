//! Shared format selector for dispatch APIs.

/// Formats recognized by Zerde's comptime dispatch APIs.
pub const Format = enum {
    json,
    toml,
    msgpack,
    zon,
    binary,
    csv,
    human,
};
