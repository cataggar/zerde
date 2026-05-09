const builtin = @import("builtin");
const std = @import("std");

pub const std_options: std.Options = .{
    .logFn = log,
};
pub const std_options_debug_io: std.Io = .{
    .userdata = runner_io.userdata,
    .vtable = &debug_io_vtable,
};

const runner_io = std.Io.Threaded.global_single_threaded.io();
const capture_dir = ".zig-cache/tmp";
const max_capture_size = 64 * 1024 * 1024;

const debug_io_vtable: std.Io.VTable = vtable: {
    var vtable = std.Io.Threaded.global_single_threaded.io().vtable.*;
    vtable.lockStderr = lockDebugStderr;
    vtable.tryLockStderr = tryLockDebugStderr;
    vtable.unlockStderr = unlockDebugStderr;
    break :vtable vtable;
};

var debug_stderr_mutex: std.Io.Mutex = .init;
var debug_stderr_buffer: [0]u8 = .{};
var debug_stderr_writer: std.Io.File.Writer = undefined;

const Capture = struct {
    saved_stdout: std.Io.File,
    saved_stderr: std.Io.File,
    output_file: std.Io.File,
    path_buffer: [128]u8,
    path_len: usize,

    fn start(test_index: usize) !Capture {
        var capture: Capture = .{
            .saved_stdout = try saveStdFile(.stdout),
            .saved_stderr = undefined,
            .output_file = undefined,
            .path_buffer = undefined,
            .path_len = 0,
        };
        errdefer closeSavedStdFile(capture.saved_stdout);

        capture.saved_stderr = try saveStdFile(.stderr);
        errdefer closeSavedStdFile(capture.saved_stderr);

        var random_bytes: [8]u8 = undefined;
        runner_io.random(&random_bytes);
        const random = std.mem.readInt(u64, &random_bytes, .little);

        const capture_path = try std.fmt.bufPrint(&capture.path_buffer, capture_dir ++ "/test-runner-{d}-{x}.log", .{
            test_index,
            random,
        });
        capture.path_len = capture_path.len;

        const cwd = std.Io.Dir.cwd();
        try cwd.createDirPath(runner_io, capture_dir);

        capture.output_file = try cwd.createFile(runner_io, capture_path, .{ .read = true, .exclusive = true });
        errdefer capture.output_file.close(runner_io);

        try redirectStdFile(capture.output_file, .stdout);
        try redirectStdFile(capture.output_file, .stderr);

        return capture;
    }

    fn finish(self: Capture, allocator: std.mem.Allocator) ![]u8 {
        try redirectStdFile(self.saved_stdout, .stdout);
        try redirectStdFile(self.saved_stderr, .stderr);
        closeSavedStdFile(self.saved_stdout);
        closeSavedStdFile(self.saved_stderr);
        self.output_file.close(runner_io);

        const cwd = std.Io.Dir.cwd();
        const capture_path = self.path();
        defer cwd.deleteFile(runner_io, capture_path) catch {};
        return cwd.readFileAlloc(runner_io, capture_path, allocator, .limited(max_capture_size));
    }

    fn path(self: *const Capture) []const u8 {
        return self.path_buffer[0..self.path_len];
    }
};

const StdFile = enum {
    stdout,
    stderr,

    fn file(std_file: StdFile) std.Io.File {
        return switch (std_file) {
            .stdout => .stdout(),
            .stderr => .stderr(),
        };
    }

    fn posixFd(std_file: StdFile) std.posix.fd_t {
        return switch (std_file) {
            .stdout => std.posix.STDOUT_FILENO,
            .stderr => std.posix.STDERR_FILENO,
        };
    }
};

const Status = enum {
    pass,
    skip,
    fail,
    leak,
    log_error,

    fn label(status: Status) []const u8 {
        return switch (status) {
            .pass => "PASS",
            .skip => "SKIP",
            .fail => "FAIL",
            .leak => "LEAK",
            .log_error => "LOGERR",
        };
    }

    fn isFailure(status: Status) bool {
        return switch (status) {
            .pass, .skip => false,
            .fail, .leak, .log_error => true,
        };
    }
};

var log_err_count: usize = 0;

pub fn main(init: std.process.Init.Minimal) void {
    run(init) catch |err| {
        std.debug.print("test runner failed: {t}\n", .{err});
        std.process.exit(1);
    };
}

fn run(init: std.process.Init.Minimal) !void {
    var fba_buffer: [8192]u8 = undefined;
    var fba: std.heap.FixedBufferAllocator = .init(&fba_buffer);
    const args = try init.args.toSlice(fba.allocator());
    for (args[1..]) |arg| {
        if (std.mem.startsWith(u8, arg, "--seed=")) {
            std.testing.random_seed = try std.fmt.parseUnsigned(u32, arg["--seed=".len..], 0);
        }
    }

    const test_fns = builtin.test_functions;
    const name_width = longestTestName(test_fns);
    const allocator = std.heap.smp_allocator;

    var pass_count: usize = 0;
    var skip_count: usize = 0;
    var fail_count: usize = 0;

    for (test_fns, 0..) |test_fn, test_index| {
        const capture = try Capture.start(test_index);

        std.testing.allocator_instance = .{};
        std.testing.io_instance = .init(std.testing.allocator, .{
            .argv0 = .init(init.args),
            .environ = init.environ,
        });
        std.testing.environ = init.environ;
        std.testing.log_level = .warn;
        log_err_count = 0;

        var status: Status = .pass;
        if (test_fn.func()) |_| {
            status = .pass;
        } else |err| switch (err) {
            error.SkipZigTest => status = .skip,
            else => {
                status = .fail;
                if (@errorReturnTrace()) |trace| std.debug.dumpErrorReturnTrace(trace);
            },
        }

        std.testing.io_instance.deinit();
        const leak_count = std.testing.allocator_instance.detectLeaks();
        std.testing.allocator_instance.deinitWithoutLeakChecks();
        if (status == .pass and leak_count != 0) status = .leak;
        if (status == .pass and log_err_count != 0) status = .log_error;

        const output = try capture.finish(allocator);
        defer allocator.free(output);

        printResultLine(test_fn.name, name_width, status);
        if (status.isFailure() and output.len != 0) {
            std.debug.print("  stdout/stderr:\n", .{});
            printIndented(output);
        }

        switch (status) {
            .pass => pass_count += 1,
            .skip => skip_count += 1,
            .fail, .leak, .log_error => fail_count += 1,
        }
    }

    std.debug.print("\n{d} passed; {d} skipped; {d} failed.\n", .{ pass_count, skip_count, fail_count });
    if (fail_count != 0) std.process.exit(1);
}

fn longestTestName(test_fns: []const std.builtin.TestFn) usize {
    var width: usize = 0;
    for (test_fns) |test_fn| width = @max(width, test_fn.name.len);
    return width;
}

fn printResultLine(name: []const u8, name_width: usize, status: Status) void {
    std.debug.print("{s}", .{name});
    for (name.len..name_width) |_| std.debug.print(" ", .{});
    std.debug.print("  {s}\n", .{status.label()});
}

fn printIndented(output: []const u8) void {
    std.debug.print("    ", .{});
    for (output) |byte| {
        std.debug.print("{c}", .{byte});
        if (byte == '\n') std.debug.print("    ", .{});
    }
    if (output[output.len - 1] != '\n') std.debug.print("\n", .{});
}

fn saveStdFile(std_file: StdFile) !std.Io.File {
    const file = std_file.file();
    if (builtin.os.tag == .windows) return file;

    return .{
        .handle = try duplicatePosixHandle(file.handle),
        .flags = file.flags,
    };
}

fn closeSavedStdFile(file: std.Io.File) void {
    if (builtin.os.tag != .windows) file.close(runner_io);
}

fn redirectStdFile(source: std.Io.File, std_file: StdFile) !void {
    if (builtin.os.tag == .windows) {
        try windowsSetStdHandle(source.handle, std_file);
    } else {
        try std.Io.Threaded.dup2(source.handle, std_file.posixFd());
    }
}

fn duplicatePosixHandle(handle: std.Io.File.Handle) !std.Io.File.Handle {
    while (true) {
        const result = std.posix.system.dup(handle);
        switch (std.posix.errno(result)) {
            .SUCCESS => return @intCast(result),
            .INTR => continue,
            .BADF => return error.BadFileDescriptor,
            .MFILE => return error.ProcessFdQuotaExceeded,
            .NFILE => return error.SystemFdQuotaExceeded,
            else => |err| return std.posix.unexpectedErrno(err),
        }
    }
}

fn lockDebugStderr(_: ?*anyopaque, terminal_mode: ?std.Io.Terminal.Mode) std.Io.Cancelable!std.Io.LockedStderr {
    debug_stderr_mutex.lockUncancelable(runner_io);
    debug_stderr_writer = std.Io.File.stderr().writerStreaming(runner_io, &debug_stderr_buffer);
    return .{
        .file_writer = &debug_stderr_writer,
        .terminal_mode = terminal_mode orelse .no_color,
    };
}

fn tryLockDebugStderr(_: ?*anyopaque, terminal_mode: ?std.Io.Terminal.Mode) std.Io.Cancelable!?std.Io.LockedStderr {
    if (!debug_stderr_mutex.tryLock()) return null;
    debug_stderr_writer = std.Io.File.stderr().writerStreaming(runner_io, &debug_stderr_buffer);
    return .{
        .file_writer = &debug_stderr_writer,
        .terminal_mode = terminal_mode orelse .no_color,
    };
}

fn unlockDebugStderr(_: ?*anyopaque) void {
    if (debug_stderr_writer.err == null) debug_stderr_writer.interface.flush() catch {};
    debug_stderr_writer.err = null;
    debug_stderr_writer.interface.end = 0;
    debug_stderr_writer.interface.buffer = &.{};
    debug_stderr_mutex.unlock(runner_io);
}

const windows_stdio = if (builtin.os.tag == .windows) struct {
    const windows = std.os.windows;
    const STD_OUTPUT_HANDLE: windows.DWORD = @bitCast(@as(i32, -11));
    const STD_ERROR_HANDLE: windows.DWORD = @bitCast(@as(i32, -12));

    extern "kernel32" fn SetStdHandle(
        nStdHandle: windows.DWORD,
        hHandle: windows.HANDLE,
    ) callconv(.winapi) windows.BOOL;
} else struct {};

fn windowsSetStdHandle(handle: std.Io.File.Handle, std_file: StdFile) !void {
    const windows = std.os.windows;
    const std_handle = switch (std_file) {
        .stdout => windows_stdio.STD_OUTPUT_HANDLE,
        .stderr => windows_stdio.STD_ERROR_HANDLE,
    };

    if (windows_stdio.SetStdHandle(std_handle, handle) == .FALSE) {
        return windows.unexpectedError(windows.GetLastError());
    }

    switch (std_file) {
        .stdout => windows.peb().ProcessParameters.hStdOutput = handle,
        .stderr => windows.peb().ProcessParameters.hStdError = handle,
    }
}

pub fn log(
    comptime message_level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    if (@intFromEnum(message_level) <= @intFromEnum(std.log.Level.err)) log_err_count +|= 1;
    if (@intFromEnum(message_level) <= @intFromEnum(std.testing.log_level)) {
        std.debug.print("[" ++ @tagName(scope) ++ "] (" ++ @tagName(message_level) ++ "): " ++ format ++ "\n", args);
    }
}
