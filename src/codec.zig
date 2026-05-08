//! Type-specialized codec API.

const std = @import("std");

const meta = @import("meta.zig");
const schema_mod = @import("schema.zig");

/// Formats supported by the simple codec dispatch API.
pub const Format = enum {
    json,
    debug,
};

/// Returns a type-specific namespace for serialization, deserialization,
/// validation, schema generation, and cleanup.
pub fn Codec(comptime T: type) type {
    comptime {
        meta.validate(T, meta.optionsFor(T));
    }

    return struct {
        /// The Zig type handled by this codec namespace.
        pub const Type = T;
        /// Normalized metadata options for `Type`.
        pub const options = meta.optionsFor(T);

        /// Serializes `value` in the selected comptime-known `format`.
        pub fn write(writer: *std.Io.Writer, value: T, comptime format: Format) !void {
            _ = writer;
            _ = value;
            return switch (format) {
                .json, .debug => error.Unsupported,
            };
        }

        /// Deserializes a `Type` value from `reader` in the selected format.
        pub fn read(allocator: std.mem.Allocator, reader: *std.Io.Reader, comptime format: Format) !T {
            _ = allocator;
            _ = reader;
            return switch (format) {
                .json, .debug => error.Unsupported,
            };
        }

        /// Validates a value against codec-level rules.
        pub fn validate(value: T) !void {
            _ = value;
        }

        /// Returns the internal schema descriptor for `Type`.
        pub fn schema() schema_mod.Schema {
            return schema_mod.forType(T);
        }

        /// Cleans up allocations owned by a value produced by Zerde deserialization.
        pub fn deinit(allocator: std.mem.Allocator, value: T) void {
            _ = allocator;
            _ = value;
        }
    };
}
