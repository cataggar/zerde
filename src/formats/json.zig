const std = @import("std");

pub fn write(writer: *std.Io.Writer, value: anytype) !void {
    _ = writer;
    _ = value;
    return error.Unsupported;
}

pub fn read(comptime T: type, allocator: std.mem.Allocator, reader: *std.Io.Reader) !T {
    _ = allocator;
    _ = reader;
    return error.Unsupported;
}

pub fn writeAlloc(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    _ = allocator;
    _ = value;
    return error.Unsupported;
}

pub fn readSlice(comptime T: type, allocator: std.mem.Allocator, input: []const u8) !T {
    _ = allocator;
    _ = input;
    return error.Unsupported;
}
