const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("zerde", .{
        .root_source_file = b.path("src/zerde.zig"),
        .target = target,
        .optimize = optimize,
    });

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);

    addCompileErrorTest(b, test_step, mod, target, optimize, "test/compile_errors/bad_metadata_field.zig", "error: zerde metadata references unknown field 'name' on bad_metadata_field.User");
    addCompileErrorTest(b, test_step, mod, target, optimize, "test/compile_errors/bad_type_option.zig", "error: unknown zerde type metadata option");
    addCompileErrorTest(b, test_step, mod, target, optimize, "test/compile_errors/bad_field_option.zig", "error: unknown zerde metadata for field 'id' option");
    addCompileErrorTest(b, test_step, mod, target, optimize, "test/compile_errors/bad_custom_hook.zig", "error: zerde metadata for field 'id' custom hook bad_custom_hook.BadHook is missing 'deserialize'");
    addCompileErrorTest(b, test_step, mod, target, optimize, "test/compile_errors/human_codec_read.zig", "error: human format is write-only");
}

fn addCompileErrorTest(
    b: *std.Build,
    test_step: *std.Build.Step,
    zerde_mod: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    path: []const u8,
    expected_error: []const u8,
) void {
    const test_mod = b.createModule(.{
        .root_source_file = b.path(path),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{
            .name = "zerde",
            .module = zerde_mod,
        }},
    });
    const compile_test = b.addTest(.{
        .root_module = test_mod,
    });
    compile_test.expect_errors = .{ .contains = expected_error };
    test_step.dependOn(&compile_test.step);
}
