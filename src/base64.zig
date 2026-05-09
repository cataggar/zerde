//! Base64 helpers used by byte-oriented serialization.

const std = @import("std");

/// Wrapper type for serializing raw bytes distinctly from UTF-8 strings.
pub const Bytes = struct {
    value: []const u8,

    /// Returns the wrapped byte slice.
    pub fn slice(self: Bytes) []const u8 {
        return self.value;
    }

    /// Returns the number of wrapped bytes.
    pub fn len(self: Bytes) usize {
        return self.value.len;
    }

    /// Returns true when no bytes are wrapped.
    pub fn isEmpty(self: Bytes) bool {
        return self.value.len == 0;
    }
};

/// Writes standard padded RFC 4648 base64 for `bytes`.
pub fn writeEncoded(writer: *std.Io.Writer, bytes: []const u8) !void {
    try std.base64.standard.Encoder.encodeWriter(writer, bytes);
}

/// Returns allocator-owned standard padded RFC 4648 base64 for `bytes`.
pub fn encodeAlloc(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    const len = std.base64.standard.Encoder.calcSize(bytes.len);
    const out = try allocator.alloc(u8, len);
    errdefer allocator.free(out);
    _ = std.base64.standard.Encoder.encode(out, bytes);
    return out;
}

/// Decodes standard padded RFC 4648 base64 into allocator-owned bytes.
pub fn decodeAlloc(allocator: std.mem.Allocator, encoded: []const u8) ![]u8 {
    const len = std.base64.standard.Decoder.calcSizeForSlice(encoded) catch return error.InvalidBase64;
    const out = try allocator.alloc(u8, len);
    errdefer allocator.free(out);
    std.base64.standard.Decoder.decode(out, encoded) catch return error.InvalidBase64;
    return out;
}

/// Decodes standard padded RFC 4648 base64 into an exact fixed byte array type.
pub fn decodeArray(comptime T: type, encoded: []const u8) !T {
    const array_info = @typeInfo(T).array;
    if (array_info.child != u8) @compileError("base64.decodeArray requires a [N]u8 type");

    const len = std.base64.standard.Decoder.calcSizeForSlice(encoded) catch return error.InvalidBase64;
    if (len != array_info.len) return error.InvalidArrayLength;

    var out: T = undefined;
    std.base64.standard.Decoder.decode(out[0..], encoded) catch return error.InvalidBase64;
    return out;
}

/// Returns true when `T` is a supported byte value for wrapper or metadata use.
pub fn isByteType(comptime T: type) bool {
    if (T == Bytes) return true;
    return switch (@typeInfo(T)) {
        .array => |array_info| array_info.child == u8,
        .pointer => |pointer_info| pointer_info.size == .slice and pointer_info.child == u8,
        else => false,
    };
}

test "base64 encodes and decodes bytes" {
    const encoded = try encodeAlloc(std.testing.allocator, "Hello");
    defer std.testing.allocator.free(encoded);
    try std.testing.expectEqualStrings("SGVsbG8=", encoded);

    const decoded = try decodeAlloc(std.testing.allocator, encoded);
    defer std.testing.allocator.free(decoded);
    try std.testing.expectEqualSlices(u8, "Hello", decoded);
}

test "base64 rejects invalid input" {
    try std.testing.expectError(error.InvalidBase64, decodeAlloc(std.testing.allocator, "not base64!"));
}

test "Bytes exposes non-owning slice helpers" {
    const bytes = Bytes{ .value = "Hello" };
    try std.testing.expectEqualStrings("Hello", bytes.slice());
    try std.testing.expectEqual(@as(usize, 5), bytes.len());
    try std.testing.expect(!bytes.isEmpty());

    const empty = Bytes{ .value = "" };
    try std.testing.expectEqualStrings("", empty.slice());
    try std.testing.expectEqual(@as(usize, 0), empty.len());
    try std.testing.expect(empty.isEmpty());
}
