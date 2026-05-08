const std = @import("std");

const meta = @import("meta.zig");
const schema_mod = @import("schema.zig");

pub const Format = enum {
    json,
    debug,
};

pub fn Codec(comptime T: type) type {
    comptime {
        meta.validate(T, meta.optionsFor(T));
    }

    return struct {
        pub const Type = T;
        pub const options = meta.optionsFor(T);

        pub fn write(writer: *std.Io.Writer, value: T, comptime format: Format) !void {
            _ = writer;
            _ = value;
            return switch (format) {
                .json, .debug => error.Unsupported,
            };
        }

        pub fn read(allocator: std.mem.Allocator, reader: *std.Io.Reader, comptime format: Format) !T {
            _ = allocator;
            _ = reader;
            return switch (format) {
                .json, .debug => error.Unsupported,
            };
        }

        pub fn validate(value: T) !void {
            _ = value;
        }

        pub fn schema() schema_mod.Schema {
            return schema_mod.forType(T);
        }

        pub fn deinit(allocator: std.mem.Allocator, value: T) void {
            _ = allocator;
            _ = value;
        }
    };
}
