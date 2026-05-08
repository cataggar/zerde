//! Metadata parsing and validation helpers.

/// Normalized type-level metadata options.
pub const Options = struct {};

/// Returns normalized metadata options for `T`.
pub fn optionsFor(comptime T: type) Options {
    _ = T;
    return .{};
}

/// Validates metadata options for `T` at comptime.
pub fn validate(comptime T: type, comptime options: Options) void {
    _ = T;
    _ = options;
}
