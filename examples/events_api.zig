const std = @import("std");
const zerde = @import("zerde");

const TraceSink = struct {
    allocator: std.mem.Allocator,
    out: std.ArrayList(u8) = .empty,
    depth: usize = 0,

    fn deinit(self: *TraceSink) void {
        self.out.deinit(self.allocator);
    }

    fn appendLine(self: *TraceSink, comptime fmt: []const u8, args: anytype) !void {
        for (0..self.depth) |_| try self.out.appendSlice(self.allocator, "  ");
        const line = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(line);
        try self.out.appendSlice(self.allocator, line);
        try self.out.append(self.allocator, '\n');
    }

    pub fn emitNull(self: *TraceSink) !void {
        try self.appendLine("null", .{});
    }

    pub fn emitBool(self: *TraceSink, value: bool) !void {
        try self.appendLine("bool {any}", .{value});
    }

    pub fn emitInt(self: *TraceSink, value: i128) !void {
        try self.appendLine("int {d}", .{value});
    }

    pub fn emitFloat(self: *TraceSink, value: f64) !void {
        try self.appendLine("float {d}", .{value});
    }

    pub fn emitString(self: *TraceSink, value: []const u8) !void {
        try self.appendLine("string \"{s}\"", .{value});
    }

    pub fn emitBytes(self: *TraceSink, value: []const u8) !void {
        try self.appendLine("bytes len={d}", .{value.len});
    }

    pub fn beginSeq(self: *TraceSink, len: ?usize) !void {
        try self.appendLine("begin seq len={?d}", .{len});
        self.depth += 1;
    }

    pub fn endSeq(self: *TraceSink) !void {
        self.depth -= 1;
        try self.appendLine("end seq", .{});
    }

    pub fn beginStruct(self: *TraceSink, len: ?usize) !void {
        try self.appendLine("begin struct len={?d}", .{len});
        self.depth += 1;
    }

    pub fn emitFieldName(self: *TraceSink, name: []const u8) !void {
        try self.appendLine("field {s}", .{name});
    }

    pub fn endStruct(self: *TraceSink) !void {
        self.depth -= 1;
        try self.appendLine("end struct", .{});
    }
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const input =
        \\{
        \\  "id": 42,
        \\  "name": "Ada",
        \\  "active": true,
        \\  "scores": [10, 20, 30],
        \\  "meta": { "lang": "zig", "year": 2026 }
        \\}
    ;

    var trace_reader: std.Io.Reader = .fixed(input);
    var trace_decoder = zerde.json.decoder(&trace_reader, allocator);
    var trace = TraceSink{ .allocator = allocator };
    defer trace.deinit();

    try zerde.events.consume(allocator, &trace_decoder, &trace);
    try trace_decoder.finish();
    std.debug.print("event trace:\n{s}\n", .{trace.out.items});

    var tree_reader: std.Io.Reader = .fixed(input);
    var tree_decoder = zerde.json.decoder(&tree_reader, allocator);
    var value = try zerde.events.readAlloc(allocator, &tree_decoder);
    defer value.deinit(allocator);
    try tree_decoder.finish();
    std.debug.print("top-level fields: {d}\n", .{value.struct_.len});

    var pipe_reader: std.Io.Reader = .fixed(input);
    var json_decoder = zerde.json.decoder(&pipe_reader, allocator);
    var msgpack_out = std.Io.Writer.Allocating.init(allocator);
    defer msgpack_out.deinit();
    var msgpack_encoder = zerde.msgpack.encoder(&msgpack_out.writer);

    try zerde.events.pipe(allocator, &json_decoder, &msgpack_encoder);
    try json_decoder.finish();
    try msgpack_encoder.finish();

    const msgpack_base64 = try zerde.base64.encodeAlloc(allocator, msgpack_out.writer.buffered());
    defer allocator.free(msgpack_base64);
    std.debug.print("messagepack base64: {s}\n", .{msgpack_base64});
}
