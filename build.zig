const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("zerde", .{
        .root_source_file = b.path("src/zerde.zig"),
        .target = target,
        .optimize = optimize,
    });

    const docs_lib = b.addLibrary(.{
        .name = "zerde",
        .root_module = mod,
    });
    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs_lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Generate project documentation");
    docs_step.dependOn(&install_docs.step);

    const examples_step = b.step("examples", "Build runnable examples");
    addExample(b, examples_step, mod, target, optimize, "basic-json", "examples/basic_json.zig");
    addExample(b, examples_step, mod, target, optimize, "bytes", "examples/bytes.zig");
    addExample(b, examples_step, mod, target, optimize, "codec-formats", "examples/codec_formats.zig");
    addExample(b, examples_step, mod, target, optimize, "custom-field-hook", "examples/custom_field_hook.zig");
    addExample(b, examples_step, mod, target, optimize, "events-api", "examples/events_api.zig");
    addExample(b, examples_step, mod, target, optimize, "events-csv-to-json", "examples/events_csv_to_json.zig");
    addExample(b, examples_step, mod, target, optimize, "metadata", "examples/metadata.zig");
    addExample(b, examples_step, mod, target, optimize, "tagged-unions", "examples/tagged_unions.zig");
    addExample(b, examples_step, mod, target, optimize, "toml-config", "examples/toml_config.zig");

    const docs_md_exe = b.addExecutable(.{
        .name = "docs-md",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/docs-md.zig"),
            .target = b.graph.host,
            .optimize = optimize,
        }),
    });
    const run_docs_md = b.addRunArtifact(docs_md_exe);
    run_docs_md.addArgs(&.{
        "--root",         "src/zerde.zig",
        "--out",          "docs",
        "--project-root", ".",
        "--name",         "zerde",
        "--emit-index",   "--follow-imports",
    });

    const docs_md_step = b.step("docs-md", "Generate Markdown API docs");
    docs_md_step.dependOn(&run_docs_md.step);

    const doc_server = b.addExecutable(.{
        .name = "doc-server",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/doc_server.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_doc_server = b.addRunArtifact(doc_server);
    run_doc_server.step.dependOn(&install_docs.step);
    if (b.args) |args| run_doc_server.addArgs(args);

    const doc_serve_step = b.step("docs-serve", "Generate docs and serve zig-out/docs over HTTP");
    doc_serve_step.dependOn(&run_doc_server.step);

    const mod_tests = b.addTest(.{
        .root_module = mod,
        .test_runner = .{
            .path = b.path("tools/test_runner.zig"),
            .mode = .simple,
        },
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);

    addCompileErrorTest(b, test_step, mod, target, optimize, "test/compile_errors/bad_metadata_field.zig", "error: zerde metadata references unknown field 'name' on bad_metadata_field.User");
    addCompileErrorTest(b, test_step, mod, target, optimize, "test/compile_errors/bad_type_option.zig", "error: unknown zerde type metadata option");
    addCompileErrorTest(b, test_step, mod, target, optimize, "test/compile_errors/bad_field_option.zig", "error: unknown zerde metadata for field 'id' option");
    addCompileErrorTest(b, test_step, mod, target, optimize, "test/compile_errors/bad_custom_hook.zig", "error: zerde metadata for field 'id' custom hook bad_custom_hook.BadHook is missing 'read'");
    addCompileErrorTest(b, test_step, mod, target, optimize, "test/compile_errors/human_codec_read.zig", "error: human format is write-only");
    addCompileErrorTest(b, test_step, mod, target, optimize, "test/compile_errors/internal_union_tag_collision.zig", "error: zerde internal union_repr payload field 'kind' conflicts with tag field on internal_union_tag_collision.Event");
}

fn addExample(
    b: *std.Build,
    examples_step: *std.Build.Step,
    zerde_mod: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    name: []const u8,
    path: []const u8,
) void {
    const exe = b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = b.path(path),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{
                .name = "zerde",
                .module = zerde_mod,
            }},
        }),
    });
    const install = b.addInstallArtifact(exe, .{});
    examples_step.dependOn(&install.step);
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
