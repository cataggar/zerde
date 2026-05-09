const std = @import("std");

const default_host = "127.0.0.1";
const default_port = 8000;
const default_root = "zig-out/docs";
const max_file_size = 64 * 1024 * 1024;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;
    const arena = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);
    const host = if (args.len > 1) args[1] else default_host;
    const root = default_root;
    const port = if (args.len > 2) try std.fmt.parseUnsigned(u16, args[2], 10) else default_port;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_file.interface;

    var address = try std.Io.net.IpAddress.parse(host, port);
    var tcp_server = try address.listen(io, .{ .reuse_address = true });
    defer tcp_server.deinit(io);

    try stdout.print("serving {s}/ on http://{s}:{d}/\n", .{ root, host, port });
    try stdout.flush();

    while (true) {
        {
            var stream = try tcp_server.accept(io);
            defer stream.close(io);

            try serveConnection(io, allocator, root, stream);
        }
    }
}

fn serveConnection(io: std.Io, allocator: std.mem.Allocator, root: []const u8, stream: std.Io.net.Stream) !void {
    var send_buffer: [4096]u8 = undefined;
    var recv_buffer: [4096]u8 = undefined;
    var connection_reader = stream.reader(io, &recv_buffer);
    var connection_writer = stream.writer(io, &send_buffer);
    var server: std.http.Server = .init(&connection_reader.interface, &connection_writer.interface);

    var request = server.receiveHead() catch |err| switch (err) {
        error.HttpConnectionClosing => return,
        else => |e| return e,
    };

    try serveRequest(io, allocator, root, &request);
}

fn serveRequest(io: std.Io, allocator: std.mem.Allocator, root: []const u8, request: *std.http.Server.Request) !void {
    if (request.head.method != .GET and request.head.method != .HEAD) {
        return request.respond("method not allowed\n", .{
            .status = .method_not_allowed,
            .keep_alive = false,
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = "text/plain; charset=utf-8" },
                .{ .name = "Allow", .value = "GET, HEAD" },
            },
        });
    }

    var arena_state: std.heap.ArenaAllocator = .init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const file_path = targetPath(arena, root, request.head.target) catch |err| switch (err) {
        error.BadPath => return request.respond("bad request\n", .{
            .status = .bad_request,
            .keep_alive = false,
            .extra_headers = &.{.{ .name = "Content-Type", .value = "text/plain; charset=utf-8" }},
        }),
        else => |e| return e,
    };

    const content = std.Io.Dir.cwd().readFileAlloc(io, file_path, allocator, .limited(max_file_size)) catch |err| switch (err) {
        error.FileNotFound, error.IsDir => return request.respond("not found\n", .{
            .status = .not_found,
            .keep_alive = false,
            .extra_headers = &.{.{ .name = "Content-Type", .value = "text/plain; charset=utf-8" }},
        }),
        else => |e| return e,
    };
    defer allocator.free(content);

    try request.respond(content, .{
        .keep_alive = false,
        .extra_headers = &.{.{ .name = "Content-Type", .value = contentType(file_path) }},
    });
}

fn targetPath(allocator: std.mem.Allocator, root: []const u8, target: []const u8) ![]const u8 {
    const path_end = std.mem.indexOfAny(u8, target, "?#") orelse target.len;
    const raw_path = target[0..path_end];
    if (raw_path.len == 0 or raw_path[0] != '/') return error.BadPath;

    const relative = raw_path[1..];
    if (relative.len == 0) return try std.fs.path.join(allocator, &.{ root, "index.html" });

    const decoded_buffer = try allocator.dupe(u8, relative);
    const decoded = std.Uri.percentDecodeInPlace(decoded_buffer);
    if (!isSafeRelativePath(decoded)) return error.BadPath;

    const file_relative = if (std.mem.endsWith(u8, decoded, "/"))
        try std.fmt.allocPrint(allocator, "{s}index.html", .{decoded})
    else
        decoded;

    return try std.fs.path.join(allocator, &.{ root, file_relative });
}

fn isSafeRelativePath(path: []const u8) bool {
    if (path.len == 0 or path[0] == '/' or path[0] == '\\') return false;

    var parts = std.mem.splitScalar(u8, path, '/');
    while (parts.next()) |part| {
        if (part.len == 0) return false;
        if (std.mem.eql(u8, part, ".") or std.mem.eql(u8, part, "..")) return false;
        if (std.mem.indexOfAny(u8, part, "\\\x00") != null) return false;
    }
    return true;
}

fn contentType(path: []const u8) []const u8 {
    if (std.mem.endsWith(u8, path, ".html")) return "text/html; charset=utf-8";
    if (std.mem.endsWith(u8, path, ".css")) return "text/css; charset=utf-8";
    if (std.mem.endsWith(u8, path, ".js")) return "application/javascript; charset=utf-8";
    if (std.mem.endsWith(u8, path, ".wasm")) return "application/wasm";
    if (std.mem.endsWith(u8, path, ".json")) return "application/json; charset=utf-8";
    if (std.mem.endsWith(u8, path, ".svg")) return "image/svg+xml";
    if (std.mem.endsWith(u8, path, ".png")) return "image/png";
    return "application/octet-stream";
}
