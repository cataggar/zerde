//! docs-md - source-based Markdown API docs for Zig 0.16 projects.
//!
//! Usage:
//!
//!     zig run tools/docs-md.zig -- \
//!       --root src/root.zig \
//!       --out docs/api \
//!       --project-root . \
//!       --name my_package \
//!       --emit-index \
//!       --follow-imports
//!
//! Build integration example:
//!
//!     const docgen = b.addExecutable(.{
//!         .name = "docs-md",
//!         .root_source_file = b.path("tools/docs-md.zig"),
//!         .target = b.graph.host,
//!     });
//!
//!     const run_docgen = b.addRunArtifact(docgen);
//!     run_docgen.addArgs(&.{
//!         "--root", "src/root.zig",
//!         "--out", "docs/api",
//!         "--project-root", ".",
//!         "--emit-index",
//!         "--follow-imports",
//!     });
//!
//!     const docs_step = b.step("docs-md", "Generate Markdown API docs");
//!     docs_step.dependOn(&run_docgen.step);
//!
//! Limitations:
//! - This is intentionally source/AST based and does not do semantic analysis.
//! - It does not evaluate comptime code or fully resolve aliases.
//! - Import strings with escapes are not decoded beyond simple quoted paths.
//! - Complex signatures are rendered as useful approximations instead of failing.
//!
//! MIT License
//!
//! Copyright (c) 2026 Grant Wade <grant@wade.software>
//!
//! Permission is hereby granted, free of charge, to any person obtaining a copy
//! of this software and associated documentation files (the "Software"), to deal
//! in the Software without restriction, including without limitation the rights
//! to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//! copies of the Software, and to permit persons to whom the Software is
//! furnished to do so, subject to the following conditions:
//!
//! The above copyright notice and this permission notice shall be included in all
//! copies or substantial portions of the Software.
//!
//! THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//! IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//! FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//! AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//! LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//! OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//! SOFTWARE.

const std = @import("std");

const Ast = std.zig.Ast;
const Allocator = std.mem.Allocator;
const Dir = std.Io.Dir;

const max_file_size: usize = 64 * 1024 * 1024;

const Config = struct {
    root: []const u8 = "",
    out: []const u8 = "",
    project_root: []const u8 = ".",
    name: []const u8 = "package",
    include_private: bool = false,
    follow_imports: bool = false,
    emit_index: bool = false,
    check: bool = false,
    single_file: bool = false,
    verbose: bool = false,
};

const Visibility = enum {
    public,
    private,
};

const DeclKind = enum {
    function,
    type,
    constant,
    variable,
    alias,
    import,
    other,

    fn pluralTitle(kind: DeclKind) []const u8 {
        return switch (kind) {
            .function => "Functions",
            .type => "Types",
            .constant => "Constants",
            .variable => "Variables",
            .alias => "Aliases",
            .import => "Imports",
            .other => "Other Declarations",
        };
    }

    fn detailPrefix(kind: DeclKind) []const u8 {
        return switch (kind) {
            .function => "fn",
            .type => "type",
            .constant => "const",
            .variable => "var",
            .alias => "alias",
            .import => "import",
            .other => "decl",
        };
    }
};

const FieldDocs = struct {
    name: []const u8,
    doc: []const u8,
    signature: []const u8,
    line: usize,
};

const DeclDocs = struct {
    name: []const u8,
    kind: DeclKind,
    visibility: Visibility,
    doc: []const u8,
    signature: []const u8,
    line: usize,
    fields: std.ArrayList(FieldDocs) = .empty,
    children: std.ArrayList(DeclDocs) = .empty,
    import_path: ?[]const u8 = null,
    resolved_import_path: ?[]const u8 = null,
};

const ImportDocs = struct {
    name: []const u8,
    import_path: []const u8,
    resolved_path: ?[]const u8,
    public: bool,
};

const ModuleDocs = struct {
    name: []const u8,
    path: []const u8,
    doc: []const u8,
    decls: std.ArrayList(DeclDocs) = .empty,
    imports: std.ArrayList(ImportDocs) = .empty,
};

const PackageDocs = struct {
    name: []const u8,
    modules: std.ArrayList(ModuleDocs) = .empty,
    visited_paths: std.ArrayList([]const u8) = .empty,
};

const SymbolEntry = struct {
    name: []const u8,
    key: []const u8,
    module_name: []const u8,
    anchor: []const u8,
    kind: DeclKind,
};

const SymbolIndex = struct {
    entries: std.ArrayList(SymbolEntry) = .empty,
};

const SymbolRef = struct {
    text: []const u8,
    href: []const u8,
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.arena.allocator();

    const raw_args = try init.minimal.args.toSlice(allocator);
    const args = try allocator.alloc([]const u8, raw_args.len);
    for (raw_args, 0..) |arg, i| args[i] = arg;

    const exit_code = run(allocator, io, args) catch |err| {
        std.debug.print("docs-md: {s}\n", .{@errorName(err)});
        return err;
    };
    std.process.exit(exit_code);
}

fn run(allocator: Allocator, io: std.Io, args: []const []const u8) !u8 {
    var config = parseArgs(args) catch |err| {
        printUsage();
        std.debug.print("docs-md: {s}\n", .{@errorName(err)});
        return 2;
    };
    if (config.name.len == 0) config.name = "package";

    if (config.verbose) {
        std.debug.print("docs-md: parsing {s}\n", .{config.root});
    }

    const project_root_abs = try std.fs.path.resolve(allocator, &.{config.project_root});
    const root_abs = try std.fs.path.resolve(allocator, &.{config.root});

    var docs = PackageDocs{ .name = config.name };
    try addModule(allocator, io, &config, &docs, project_root_abs, root_abs, "root");

    var symbols = SymbolIndex{};
    try buildSymbolIndex(allocator, &docs, &symbols);

    if (config.single_file) {
        var content = std.ArrayList(u8).empty;
        defer content.deinit(allocator);
        try renderSingleFile(allocator, &content, &docs, &symbols);
        const path = try singleOutputPath(allocator, config.out, config.name);
        const changed = try writeOrCheck(allocator, io, path, content.items, config.check);
        if (changed and config.check) return 1;
    } else {
        var changed_any = false;
        if (config.emit_index) {
            var content = std.ArrayList(u8).empty;
            defer content.deinit(allocator);
            try renderIndex(allocator, &content, &docs);
            const path = try std.fs.path.join(allocator, &.{ config.out, "README.md" });
            changed_any = try writeOrCheck(allocator, io, path, content.items, config.check) or changed_any;
        }
        for (docs.modules.items) |*module| {
            var content = std.ArrayList(u8).empty;
            defer content.deinit(allocator);
            try renderModule(allocator, &content, &docs, module, &symbols);
            const rel = try moduleOutputRelativePath(allocator, module.name);
            const path = try std.fs.path.join(allocator, &.{ config.out, rel });
            changed_any = try writeOrCheck(allocator, io, path, content.items, config.check) or changed_any;
        }
        if (changed_any and config.check) return 1;
    }

    return 0;
}

fn parseArgs(args: []const []const u8) !Config {
    var config = Config{};
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printUsage();
            std.process.exit(0);
        } else if (std.mem.eql(u8, arg, "--root")) {
            i += 1;
            if (i >= args.len) return error.MissingRootValue;
            config.root = args[i];
        } else if (std.mem.eql(u8, arg, "--out")) {
            i += 1;
            if (i >= args.len) return error.MissingOutValue;
            config.out = args[i];
        } else if (std.mem.eql(u8, arg, "--project-root")) {
            i += 1;
            if (i >= args.len) return error.MissingProjectRootValue;
            config.project_root = args[i];
        } else if (std.mem.eql(u8, arg, "--name")) {
            i += 1;
            if (i >= args.len) return error.MissingNameValue;
            config.name = args[i];
        } else if (std.mem.eql(u8, arg, "--include-private")) {
            config.include_private = true;
        } else if (std.mem.eql(u8, arg, "--follow-imports")) {
            config.follow_imports = true;
        } else if (std.mem.eql(u8, arg, "--emit-index")) {
            config.emit_index = true;
        } else if (std.mem.eql(u8, arg, "--check")) {
            config.check = true;
        } else if (std.mem.eql(u8, arg, "--single-file")) {
            config.single_file = true;
        } else if (std.mem.eql(u8, arg, "--verbose")) {
            config.verbose = true;
        } else {
            return error.UnknownArgument;
        }
    }
    if (config.root.len == 0) return error.MissingRoot;
    if (config.out.len == 0) return error.MissingOut;
    return config;
}

fn printUsage() void {
    std.debug.print(
        \\Usage: docs-md --root src/root.zig --out docs/api [options]
        \\
        \\Options:
        \\  --project-root DIR   Project root used to constrain followed imports (default: .)
        \\  --name NAME          Package name for index/single-file output
        \\  --include-private   Include private declarations
        \\  --follow-imports    Recursively follow project-local @import("*.zig") declarations
        \\  --emit-index        Generate README.md in multi-file mode
        \\  --check             Exit nonzero if generated files differ
        \\  --single-file       Emit one Markdown file at OUT/NAME.md
        \\  --verbose           Print progress and followed imports
        \\
    , .{});
}

fn addModule(
    allocator: Allocator,
    io: std.Io,
    config: *const Config,
    docs: *PackageDocs,
    project_root_abs: []const u8,
    path_abs: []const u8,
    requested_name: []const u8,
) !void {
    if (!isInsidePath(project_root_abs, path_abs)) {
        if (config.verbose) std.debug.print("docs-md: skipping outside project: {s}\n", .{path_abs});
        return;
    }

    for (docs.visited_paths.items) |visited| {
        if (std.mem.eql(u8, visited, path_abs)) return;
    }
    try docs.visited_paths.append(allocator, try allocator.dupe(u8, path_abs));

    const module_name = if (std.mem.eql(u8, requested_name, "root"))
        requested_name
    else
        try moduleNameFromPath(allocator, project_root_abs, path_abs, requested_name);

    if (config.verbose) std.debug.print("docs-md: module {s}\n", .{module_name});

    const module = try parseModule(allocator, io, config, project_root_abs, path_abs, module_name);
    try docs.modules.append(allocator, module);
    if (config.follow_imports) {
        for (module.imports.items) |import_doc| {
            if (import_doc.resolved_path) |resolved| {
                const import_name = try moduleNameFromPath(allocator, project_root_abs, resolved, "");
                try addModule(allocator, io, config, docs, project_root_abs, resolved, import_name);
            }
        }
    }
}

fn parseModule(
    allocator: Allocator,
    io: std.Io,
    config: *const Config,
    project_root_abs: []const u8,
    path_abs: []const u8,
    module_name: []const u8,
) !ModuleDocs {
    const source = try Dir.cwd().readFileAllocOptions(
        io,
        path_abs,
        allocator,
        .limited(max_file_size),
        .of(u8),
        0,
    );

    var tree = try Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);

    if (tree.errors.len != 0) {
        std.debug.print("docs-md: warning: {s}: parsed with {d} syntax error(s)\n", .{ path_abs, tree.errors.len });
    }

    var module = ModuleDocs{
        .name = try allocator.dupe(u8, module_name),
        .path = try allocator.dupe(u8, path_abs),
        .doc = try collectModuleDoc(allocator, tree),
    };

    try collectDecls(allocator, config, project_root_abs, path_abs, tree, tree.rootDecls(), &module.decls, &module.imports);
    return module;
}

fn collectDecls(
    allocator: Allocator,
    config: *const Config,
    project_root_abs: []const u8,
    source_path_abs: []const u8,
    tree: Ast,
    members: []const Ast.Node.Index,
    decls: *std.ArrayList(DeclDocs),
    imports: *std.ArrayList(ImportDocs),
) anyerror!void {
    for (members) |node| {
        const tag = tree.nodeTag(node);
        if (tag == .test_decl) continue;

        var fn_buffer: [1]Ast.Node.Index = undefined;
        if (tree.fullFnProto(&fn_buffer, node)) |fn_proto| {
            const is_public = fn_proto.visib_token != null;
            if (!is_public and !config.include_private) continue;
            const name_token = fn_proto.name_token orelse continue;
            const decl = DeclDocs{
                .name = try allocator.dupe(u8, tree.tokenSlice(name_token)),
                .kind = .function,
                .visibility = if (is_public) .public else .private,
                .doc = try collectDocComment(allocator, tree, fn_proto.firstToken()),
                .signature = try functionSignature(allocator, tree, node, fn_proto),
                .line = lineNumber(tree, fn_proto.firstToken()),
            };
            try decls.append(allocator, decl);
            continue;
        }

        if (tree.fullVarDecl(node)) |var_decl| {
            const is_public = var_decl.visib_token != null;
            const name_token = var_decl.ast.mut_token + 1;
            if (tree.tokenTag(name_token) != .identifier) continue;
            const name = tree.tokenSlice(name_token);
            const mut = tree.tokenTag(var_decl.ast.mut_token);
            const init_node = var_decl.ast.init_node.unwrap();
            const import_path = if (init_node) |init| importPathFromNode(tree, init) else null;
            const resolved_import = if (import_path) |import_text|
                try resolveLocalImport(allocator, project_root_abs, source_path_abs, import_text)
            else
                null;

            if (import_path) |import_text| {
                try imports.append(allocator, .{
                    .name = try allocator.dupe(u8, name),
                    .import_path = try allocator.dupe(u8, import_text),
                    .resolved_path = resolved_import,
                    .public = is_public,
                });
            }

            if (!is_public and !config.include_private) continue;

            var kind: DeclKind = if (mut == .keyword_var) .variable else .constant;
            if (init_node) |init| {
                if (containerKind(tree, init) != null) {
                    kind = .type;
                } else if (import_path != null) {
                    kind = .import;
                } else if (mut == .keyword_const and isAliasExpr(tree, init)) {
                    kind = .alias;
                }
            }

            var decl = DeclDocs{
                .name = try allocator.dupe(u8, name),
                .kind = kind,
                .visibility = if (is_public) .public else .private,
                .doc = try collectDocComment(allocator, tree, var_decl.firstToken()),
                .signature = try varSignature(allocator, tree, node, var_decl, kind),
                .line = lineNumber(tree, var_decl.firstToken()),
                .import_path = import_path,
                .resolved_import_path = resolved_import,
            };

            if (init_node) |init| {
                var container_buffer: [2]Ast.Node.Index = undefined;
                if (tree.fullContainerDecl(&container_buffer, init)) |container| {
                    try collectContainerMembers(allocator, config, project_root_abs, source_path_abs, tree, container.ast.members, &decl);
                }
            }

            try decls.append(allocator, decl);
            continue;
        }
    }
}

fn collectContainerMembers(
    allocator: Allocator,
    config: *const Config,
    project_root_abs: []const u8,
    source_path_abs: []const u8,
    tree: Ast,
    members: []const Ast.Node.Index,
    owner: *DeclDocs,
) anyerror!void {
    var nested_imports = std.ArrayList(ImportDocs).empty;
    for (members) |member| {
        if (tree.fullContainerField(member)) |field| {
            if (field.ast.tuple_like) continue;
            const first = field.firstToken();
            const name = tree.tokenSlice(field.ast.main_token);
            try owner.fields.append(allocator, .{
                .name = try allocator.dupe(u8, name),
                .doc = try collectDocComment(allocator, tree, first),
                .signature = try simpleNodeSignature(allocator, tree, member),
                .line = lineNumber(tree, first),
            });
        }
    }
    try collectDecls(allocator, config, project_root_abs, source_path_abs, tree, members, &owner.children, &nested_imports);
}

fn collectModuleDoc(allocator: Allocator, tree: Ast) ![]const u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    var tok: Ast.TokenIndex = 0;
    while (tok < tree.tokens.len and tree.tokenTag(tok) == .container_doc_comment) : (tok += 1) {
        if (out.items.len != 0) try out.append(allocator, '\n');
        try appendDocTokenText(allocator, &out, tree.tokenSlice(tok));
    }
    return out.toOwnedSlice(allocator);
}

fn collectDocComment(allocator: Allocator, tree: Ast, first_token: Ast.TokenIndex) ![]const u8 {
    if (first_token == 0) return "";

    var first_doc = first_token;
    var cursor = first_token;
    while (cursor > 0) {
        const prev = cursor - 1;
        if (tree.tokenTag(prev) != .doc_comment) break;
        if (!tokensAreAttached(tree, prev, cursor)) break;
        first_doc = prev;
        cursor = prev;
    }

    if (first_doc == first_token) return "";

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    var tok = first_doc;
    while (tok < first_token) : (tok += 1) {
        if (out.items.len != 0) try out.append(allocator, '\n');
        try appendDocTokenText(allocator, &out, tree.tokenSlice(tok));
    }
    return out.toOwnedSlice(allocator);
}

fn tokensAreAttached(tree: Ast, doc_token: Ast.TokenIndex, next_token: Ast.TokenIndex) bool {
    const doc_end = tree.tokenStart(doc_token) + @as(u32, @intCast(tree.tokenSlice(doc_token).len));
    const next_start = tree.tokenStart(next_token);
    if (doc_end > next_start) return false;
    const gap = tree.source[doc_end..next_start];
    var newline_count: usize = 0;
    for (gap) |byte| {
        switch (byte) {
            '\n' => newline_count += 1,
            ' ', '\t', '\r' => {},
            else => return false,
        }
    }
    return newline_count <= 1;
}

fn appendDocTokenText(allocator: Allocator, out: *std.ArrayList(u8), token: []const u8) !void {
    var text = token;
    if (std.mem.startsWith(u8, text, "///") or std.mem.startsWith(u8, text, "//!")) {
        text = text[3..];
    }
    if (text.len > 0 and text[0] == ' ') text = text[1..];
    try out.appendSlice(allocator, text);
}

fn lineNumber(tree: Ast, token: Ast.TokenIndex) usize {
    return tree.tokenLocation(0, token).line + 1;
}

fn containerKind(tree: Ast, node: Ast.Node.Index) ?[]const u8 {
    var buffer: [2]Ast.Node.Index = undefined;
    const container = tree.fullContainerDecl(&buffer, node) orelse return null;
    return switch (tree.tokenTag(container.ast.main_token)) {
        .keyword_struct => "struct",
        .keyword_enum => "enum",
        .keyword_union => "union",
        .keyword_opaque => "opaque",
        else => null,
    };
}

fn isAliasExpr(tree: Ast, node: Ast.Node.Index) bool {
    return switch (tree.nodeTag(node)) {
        .identifier, .field_access, .deref, .unwrap_optional => true,
        else => false,
    };
}

fn importPathFromNode(tree: Ast, node: Ast.Node.Index) ?[]const u8 {
    var buffer: [2]Ast.Node.Index = undefined;
    const params = tree.builtinCallParams(&buffer, node) orelse return switch (tree.nodeTag(node)) {
        .field_access, .unwrap_optional => importPathFromNode(tree, tree.nodeData(node).node_and_token[0]),
        else => null,
    };
    if (params.len == 0) return null;
    if (!std.mem.eql(u8, tree.tokenSlice(tree.nodeMainToken(node)), "@import")) return null;

    const first_param_token = tree.firstToken(params[0]);
    if (tree.tokenTag(first_param_token) != .string_literal) return null;
    const literal = tree.tokenSlice(first_param_token);
    if (literal.len < 2 or literal[0] != '"' or literal[literal.len - 1] != '"') return null;
    return literal[1 .. literal.len - 1];
}

fn resolveLocalImport(
    allocator: Allocator,
    project_root_abs: []const u8,
    source_path_abs: []const u8,
    import_path: []const u8,
) !?[]const u8 {
    if (!std.mem.endsWith(u8, import_path, ".zig")) return null;
    if (std.fs.path.isAbsolute(import_path)) return null;
    const source_dir = std.fs.path.dirname(source_path_abs) orelse ".";
    const resolved = try std.fs.path.resolve(allocator, &.{ source_dir, import_path });
    if (!isInsidePath(project_root_abs, resolved)) return null;
    return resolved;
}

fn functionSignature(allocator: Allocator, tree: Ast, node: Ast.Node.Index, fn_proto: Ast.full.FnProto) ![]const u8 {
    const start = fn_proto.firstToken();
    const end = if (tree.nodeTag(node) == .fn_decl)
        tree.lastToken(fn_proto.ast.proto_node)
    else
        tree.lastToken(node);
    return trimAndCopy(allocator, sourceSliceTokens(tree, start, end));
}

fn varSignature(
    allocator: Allocator,
    tree: Ast,
    node: Ast.Node.Index,
    var_decl: Ast.full.VarDecl,
    kind: DeclKind,
) ![]const u8 {
    if (kind == .type) {
        if (var_decl.ast.init_node.unwrap()) |init| {
            const has_semicolon = tree.tokenTag(tree.lastToken(node) + 1) == .semicolon;
            if (containerHeaderSignature(allocator, tree, var_decl.firstToken(), init, has_semicolon)) |sig| return sig;
        }
    }

    const last = tree.lastToken(node);
    const end_token = if (tree.tokenTag(last + 1) == .semicolon) last + 1 else last;
    const full = std.mem.trim(u8, sourceSliceTokens(tree, var_decl.firstToken(), end_token), &std.ascii.whitespace);
    if (full.len <= 240 and std.mem.indexOfScalar(u8, full, '\n') == null) return allocator.dupe(u8, full);

    if (var_decl.ast.init_node.unwrap()) |init| {
        const init_start = tree.tokenStart(tree.firstToken(init));
        const decl_start = tree.tokenStart(var_decl.firstToken());
        if (init_start > decl_start) {
            var out = std.ArrayList(u8).empty;
            defer out.deinit(allocator);
            try out.appendSlice(allocator, std.mem.trimEnd(u8, tree.source[decl_start..init_start], &std.ascii.whitespace));
            try out.appendSlice(allocator, "...");
            if (tree.tokenTag(tree.lastToken(node) + 1) == .semicolon) try out.append(allocator, ';');
            return out.toOwnedSlice(allocator);
        }
    }
    return trimAndCopy(allocator, full[0..@min(full.len, 240)]);
}

fn containerHeaderSignature(allocator: Allocator, tree: Ast, start_token: Ast.TokenIndex, init: Ast.Node.Index, has_semicolon: bool) ?[]const u8 {
    const first = tree.firstToken(init);
    const last = tree.lastToken(init);
    var tok = first;
    while (tok <= last) : (tok += 1) {
        if (tree.tokenTag(tok) == .l_brace) {
            const start = tree.tokenStart(start_token);
            const end = tree.tokenStart(tok) + 1;
            var out = std.ArrayList(u8).empty;
            defer out.deinit(allocator);
            out.appendSlice(allocator, std.mem.trimEnd(u8, tree.source[start..end], &std.ascii.whitespace)) catch return null;
            out.appendSlice(allocator, " ... }") catch return null;
            if (has_semicolon) out.append(allocator, ';') catch return null;
            return out.toOwnedSlice(allocator) catch null;
        }
    }
    return null;
}

fn simpleNodeSignature(allocator: Allocator, tree: Ast, node: Ast.Node.Index) ![]const u8 {
    return trimAndCopy(allocator, sourceSliceTokens(tree, tree.firstToken(node), tree.lastToken(node)));
}

fn sourceSliceTokens(tree: Ast, start_token: Ast.TokenIndex, end_token: Ast.TokenIndex) []const u8 {
    const start = tree.tokenStart(start_token);
    const end = tree.tokenStart(end_token) + @as(u32, @intCast(tree.tokenSlice(end_token).len));
    return tree.source[start..end];
}

fn trimAndCopy(allocator: Allocator, text: []const u8) ![]const u8 {
    return allocator.dupe(u8, std.mem.trim(u8, text, &std.ascii.whitespace));
}

fn buildSymbolIndex(allocator: Allocator, docs: *const PackageDocs, index: *SymbolIndex) !void {
    for (docs.modules.items) |module| {
        try addDeclSymbols(allocator, index, module.name, module.decls.items, null, null);
    }
}

fn addDeclSymbols(
    allocator: Allocator,
    index: *SymbolIndex,
    module_name: []const u8,
    decls: []const DeclDocs,
    parent_key: ?[]const u8,
    parent_anchor: ?[]const u8,
) !void {
    for (decls) |decl| {
        const key = if (parent_key) |parent|
            try std.fmt.allocPrint(allocator, "{s}.{s}", .{ parent, decl.name })
        else
            try std.fmt.allocPrint(allocator, "{s}.{s}", .{ module_name, decl.name });
        const anchor = if (parent_anchor != null)
            try declAnchor(allocator, decl, parent_anchor)
        else
            try declAnchor(allocator, decl, null);

        try index.entries.append(allocator, .{
            .name = decl.name,
            .key = key,
            .module_name = module_name,
            .anchor = anchor,
            .kind = decl.kind,
        });

        try addDeclSymbols(allocator, index, module_name, decl.children.items, key, decl.name);
    }
}

fn renderSingleFile(allocator: Allocator, out: *std.ArrayList(u8), docs: *const PackageDocs, symbols: *const SymbolIndex) !void {
    try out.print(allocator, "# {s}\n\n", .{docs.name});
    try out.appendSlice(allocator, "Generated API documentation.\n\n");
    try out.appendSlice(allocator, "## Modules\n\n");
    for (docs.modules.items) |module| {
        try out.print(allocator, "- [{s}](#{s})\n", .{ module.name, try anchorAlloc(allocator, "module", module.name) });
    }
    try out.append(allocator, '\n');
    for (docs.modules.items) |module| {
        try out.print(allocator, "<a id=\"{s}\"></a>\n\n", .{try anchorAlloc(allocator, "module", module.name)});
        try renderModuleBody(allocator, out, docs, &module, symbols, 2, true);
    }
}

fn renderIndex(allocator: Allocator, out: *std.ArrayList(u8), docs: *const PackageDocs) !void {
    try out.print(allocator, "# {s} API\n\n", .{docs.name});
    try out.appendSlice(allocator, "Generated Markdown API documentation.\n\n");
    try out.appendSlice(allocator, "## Modules\n\n");
    for (docs.modules.items) |module| {
        const rel = try moduleOutputRelativePath(allocator, module.name);
        try out.print(allocator, "- [{s}]({s})\n", .{ module.name, rel });
    }
}

fn renderModule(allocator: Allocator, out: *std.ArrayList(u8), docs: *const PackageDocs, module: *const ModuleDocs, symbols: *const SymbolIndex) !void {
    try renderModuleBody(allocator, out, docs, module, symbols, 1, false);
}

fn renderModuleBody(
    allocator: Allocator,
    out: *std.ArrayList(u8),
    docs: *const PackageDocs,
    module: *const ModuleDocs,
    symbols: *const SymbolIndex,
    heading_level: usize,
    single_file: bool,
) !void {
    try appendHeading(allocator, out, heading_level, module.name);
    try out.append(allocator, '\n');
    try renderModuleNavigation(allocator, out, docs, module, heading_level + 1, single_file);
    if (module.doc.len != 0) {
        try appendHeading(allocator, out, heading_level + 1, "Overview");
        try out.append(allocator, '\n');
        try appendLinkedMarkdownText(allocator, out, symbols, module.name, module.doc, single_file);
        try out.appendSlice(allocator, "\n\n");
    }

    try renderSummaryGroup(allocator, out, module.decls.items, .function);
    try renderSummaryGroup(allocator, out, module.decls.items, .type);
    try renderSummaryGroup(allocator, out, module.decls.items, .constant);
    try renderSummaryGroup(allocator, out, module.decls.items, .variable);
    try renderSummaryGroup(allocator, out, module.decls.items, .alias);
    try renderSummaryGroup(allocator, out, module.decls.items, .import);

    for (module.decls.items) |decl| {
        try renderDecl(allocator, out, symbols, module.name, decl, heading_level + 1, null, single_file);
    }
}

fn renderModuleNavigation(
    allocator: Allocator,
    out: *std.ArrayList(u8),
    docs: *const PackageDocs,
    module: *const ModuleDocs,
    heading_level: usize,
    single_file: bool,
) !void {
    if (single_file) return;

    try appendHeading(allocator, out, heading_level, "Navigation");
    try out.append(allocator, '\n');
    try out.print(allocator, "- [API Index]({s})\n", .{try indexHref(allocator, module.name)});

    const current_index = findModuleIndex(docs, module.name) orelse 0;
    if (current_index > 0) {
        const previous = docs.modules.items[current_index - 1];
        try out.print(allocator, "- Previous: [{s}]({s})\n", .{ previous.name, try moduleHref(allocator, module.name, previous.name) });
    }
    if (current_index + 1 < docs.modules.items.len) {
        const next = docs.modules.items[current_index + 1];
        try out.print(allocator, "- Next: [{s}]({s})\n", .{ next.name, try moduleHref(allocator, module.name, next.name) });
    }
    if (parentModuleName(module.name)) |parent_name| {
        if (findModuleIndex(docs, parent_name) != null) {
            try out.print(allocator, "- Parent: [{s}]({s})\n", .{ parent_name, try moduleHref(allocator, module.name, parent_name) });
        }
    }

    var wrote_submodules = false;
    for (docs.modules.items) |candidate| {
        if (!isImmediateSubmodule(module.name, candidate.name)) continue;
        if (!wrote_submodules) {
            try out.appendSlice(allocator, "- Submodules: ");
            wrote_submodules = true;
        } else {
            try out.appendSlice(allocator, ", ");
        }
        try out.print(allocator, "[{s}]({s})", .{ candidate.name, try moduleHref(allocator, module.name, candidate.name) });
    }
    if (wrote_submodules) try out.append(allocator, '\n');
    try out.append(allocator, '\n');
}

fn findModuleIndex(docs: *const PackageDocs, module_name: []const u8) ?usize {
    for (docs.modules.items, 0..) |module, index| {
        if (std.mem.eql(u8, module.name, module_name)) return index;
    }
    return null;
}

fn parentModuleName(module_name: []const u8) ?[]const u8 {
    if (std.mem.lastIndexOfScalar(u8, module_name, '.')) |dot| return module_name[0..dot];
    return null;
}

fn isImmediateSubmodule(parent: []const u8, candidate: []const u8) bool {
    if (candidate.len <= parent.len + 1) return false;
    if (!std.mem.startsWith(u8, candidate, parent)) return false;
    if (candidate[parent.len] != '.') return false;
    return std.mem.indexOfScalar(u8, candidate[parent.len + 1 ..], '.') == null;
}

fn indexHref(allocator: Allocator, current_module: []const u8) ![]const u8 {
    const current_rel = try moduleOutputRelativePath(allocator, current_module);
    const depth = modulePathDepth(current_rel);
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    var i: usize = 0;
    while (i < depth) : (i += 1) try out.appendSlice(allocator, "../");
    try out.appendSlice(allocator, "README.md");
    return out.toOwnedSlice(allocator);
}

fn moduleHref(allocator: Allocator, current_module: []const u8, target_module: []const u8) ![]const u8 {
    const target_rel = try moduleOutputRelativePath(allocator, target_module);
    const current_rel = try moduleOutputRelativePath(allocator, current_module);
    const depth = modulePathDepth(current_rel);
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    var i: usize = 0;
    while (i < depth) : (i += 1) try out.appendSlice(allocator, "../");
    try out.appendSlice(allocator, target_rel);
    return out.toOwnedSlice(allocator);
}

fn renderSummaryGroup(allocator: Allocator, out: *std.ArrayList(u8), decls: []const DeclDocs, kind: DeclKind) !void {
    var count: usize = 0;
    for (decls) |decl| {
        if (decl.kind == kind) count += 1;
    }
    if (count == 0) return;

    try out.print(allocator, "## {s}\n\n", .{kind.pluralTitle()});
    for (decls) |decl| {
        if (decl.kind != kind) continue;
        const anchor = try declAnchor(allocator, decl, null);
        try out.appendSlice(allocator, "- [");
        try appendMarkdownEscaped(allocator, out, decl.name);
        try out.print(allocator, "](#{s})", .{anchor});
        if (decl.visibility == .private) try out.appendSlice(allocator, " _(private)_");
        if (decl.import_path) |path| try out.print(allocator, " `@import(\"{s}\")`", .{path});
        try out.append(allocator, '\n');
    }
    try out.append(allocator, '\n');
}

fn renderDecl(
    allocator: Allocator,
    out: *std.ArrayList(u8),
    symbols: *const SymbolIndex,
    current_module: []const u8,
    decl: DeclDocs,
    heading_level: usize,
    parent: ?[]const u8,
    single_file: bool,
) !void {
    const display_name = if (parent) |p| try std.fmt.allocPrint(allocator, "{s}.{s}", .{ p, decl.name }) else decl.name;
    const anchor = try declAnchor(allocator, decl, parent);

    try out.print(allocator, "<a id=\"{s}\"></a>\n\n", .{anchor});
    try appendHeading(allocator, out, heading_level, display_name);
    try out.append(allocator, '\n');
    if (decl.doc.len != 0) {
        try appendLinkedMarkdownText(allocator, out, symbols, current_module, decl.doc, single_file);
        try out.appendSlice(allocator, "\n\n");
    }
    try out.appendSlice(allocator, "```zig\n");
    try out.appendSlice(allocator, decl.signature);
    try out.appendSlice(allocator, "\n```\n\n");
    try appendSignatureReferences(allocator, out, symbols, current_module, decl.signature, anchor, single_file);
    if (decl.fields.items.len != 0) {
        try appendHeading(allocator, out, heading_level + 1, "Fields");
        try out.append(allocator, '\n');
        try out.appendSlice(allocator, "```zig\n");
        for (decl.fields.items) |field| {
            try out.print(allocator, "    {s}\n", .{field.signature});
        }
        try out.appendSlice(allocator, "```\n\n");
        for (decl.fields.items) |field| {
            if (field.doc.len == 0) continue;
            try out.print(allocator, "`{s}`: ", .{field.name});
            try appendLinkedMarkdownText(allocator, out, symbols, current_module, field.doc, single_file);
            try out.append(allocator, '\n');
        }
        try out.append(allocator, '\n');
    }
    if (decl.children.items.len != 0) {
        try appendHeading(allocator, out, heading_level + 1, "Nested Declarations");
        try out.append(allocator, '\n');
        for (decl.children.items) |child| {
            const child_anchor = try declAnchor(allocator, child, decl.name);
            try out.print(allocator, "- [{s}](#{s})\n", .{ child.name, child_anchor });
        }
        try out.append(allocator, '\n');
        for (decl.children.items) |child| {
            try renderDecl(allocator, out, symbols, current_module, child, heading_level + 1, decl.name, single_file);
        }
    }
}

fn appendSignatureReferences(
    allocator: Allocator,
    out: *std.ArrayList(u8),
    symbols: *const SymbolIndex,
    current_module: []const u8,
    signature: []const u8,
    current_anchor: []const u8,
    single_file: bool,
) !void {
    var refs = std.ArrayList(SymbolRef).empty;
    defer refs.deinit(allocator);

    var i: usize = 0;
    while (i < signature.len) {
        if (signature[i] == '"') {
            i = skipQuoted(signature, i, '"');
            continue;
        }
        if (signature[i] == '\'') {
            i = skipQuoted(signature, i, '\'');
            continue;
        }
        if (!isIdentStart(signature[i])) {
            i += 1;
            continue;
        }

        const start = i;
        i = scanReference(signature, i);
        const token = signature[start..i];
        if (try resolveReference(allocator, symbols, current_module, token, single_file)) |href| {
            if (isSelfHref(allocator, href, current_anchor)) continue;
            if (!hasSymbolRef(refs.items, token, href)) {
                try refs.append(allocator, .{ .text = token, .href = href });
            }
        }
    }

    if (refs.items.len == 0) return;
    try out.appendSlice(allocator, "References: ");
    for (refs.items, 0..) |ref, index| {
        if (index != 0) try out.appendSlice(allocator, ", ");
        try out.print(allocator, "[`{s}`]({s})", .{ ref.text, ref.href });
    }
    try out.appendSlice(allocator, "\n\n");
}

fn appendLinkedMarkdownText(
    allocator: Allocator,
    out: *std.ArrayList(u8),
    symbols: *const SymbolIndex,
    current_module: []const u8,
    text: []const u8,
    single_file: bool,
) !void {
    var i: usize = 0;
    var in_backticks = false;
    while (i < text.len) {
        if (text[i] == '`') {
            in_backticks = !in_backticks;
            try out.append(allocator, text[i]);
            i += 1;
            continue;
        }
        if (in_backticks or !isIdentStart(text[i])) {
            try out.append(allocator, text[i]);
            i += 1;
            continue;
        }

        const start = i;
        i = scanReference(text, i);
        const token = text[start..i];
        if (start > 0 and (text[start - 1] == '[' or text[start - 1] == '(')) {
            try out.appendSlice(allocator, token);
            continue;
        }
        if (try resolveReference(allocator, symbols, current_module, token, single_file)) |href| {
            try out.print(allocator, "[{s}]({s})", .{ token, href });
        } else {
            try out.appendSlice(allocator, token);
        }
    }
}

fn hasSymbolRef(refs: []const SymbolRef, text: []const u8, href: []const u8) bool {
    for (refs) |ref| {
        if (std.mem.eql(u8, ref.text, text) and std.mem.eql(u8, ref.href, href)) return true;
    }
    return false;
}

fn isSelfHref(allocator: Allocator, href: []const u8, current_anchor: []const u8) bool {
    const self_href = std.fmt.allocPrint(allocator, "#{s}", .{current_anchor}) catch return false;
    return std.mem.eql(u8, href, self_href);
}

fn resolveReference(
    allocator: Allocator,
    symbols: *const SymbolIndex,
    current_module: []const u8,
    reference: []const u8,
    single_file: bool,
) !?[]const u8 {
    if (isIgnoredReference(reference)) return null;
    const qualified = std.mem.indexOfScalar(u8, reference, '.') != null;
    if (!qualified and !std.ascii.isUpper(reference[0])) return null;

    const symbol = if (qualified)
        findExactSymbol(symbols, reference) orelse findExactSymbol(symbols, try std.fmt.allocPrint(allocator, "{s}.{s}", .{ current_module, reference }))
    else
        findExactSymbol(symbols, try std.fmt.allocPrint(allocator, "{s}.{s}", .{ current_module, reference })) orelse findUniqueUnqualifiedSymbol(symbols, reference);

    if (symbol) |entry| {
        if (!qualified and !isTypeLikeKind(entry.kind)) return null;
        return try symbolHref(allocator, current_module, entry, single_file);
    }
    return null;
}

fn isTypeLikeKind(kind: DeclKind) bool {
    return switch (kind) {
        .type, .alias, .constant => true,
        .function, .variable, .import, .other => false,
    };
}

fn findExactSymbol(symbols: *const SymbolIndex, key: []const u8) ?SymbolEntry {
    for (symbols.entries.items) |entry| {
        if (std.mem.eql(u8, entry.key, key)) return entry;
    }
    return null;
}

fn findUniqueUnqualifiedSymbol(symbols: *const SymbolIndex, name: []const u8) ?SymbolEntry {
    var result: ?SymbolEntry = null;
    for (symbols.entries.items) |entry| {
        if (!std.mem.eql(u8, entry.name, name)) continue;
        if (result != null) return null;
        result = entry;
    }
    return result;
}

fn symbolHref(allocator: Allocator, current_module: []const u8, symbol: SymbolEntry, single_file: bool) ![]const u8 {
    if (single_file or std.mem.eql(u8, current_module, symbol.module_name)) {
        return std.fmt.allocPrint(allocator, "#{s}", .{symbol.anchor});
    }

    const target_rel = try moduleOutputRelativePath(allocator, symbol.module_name);
    const current_rel = try moduleOutputRelativePath(allocator, current_module);
    const depth = modulePathDepth(current_rel);

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    var i: usize = 0;
    while (i < depth) : (i += 1) try out.appendSlice(allocator, "../");
    try out.appendSlice(allocator, target_rel);
    try out.append(allocator, '#');
    try out.appendSlice(allocator, symbol.anchor);
    return out.toOwnedSlice(allocator);
}

fn modulePathDepth(module_path: []const u8) usize {
    const dirname = std.fs.path.dirname(module_path) orelse return 0;
    if (dirname.len == 0 or std.mem.eql(u8, dirname, ".")) return 0;
    var depth: usize = 1;
    for (dirname) |byte| {
        if (byte == std.fs.path.sep) depth += 1;
    }
    return depth;
}

fn scanReference(text: []const u8, start: usize) usize {
    var i = start;
    while (i < text.len) {
        if (!isIdentContinue(text[i])) break;
        i += 1;
    }
    while (i + 1 < text.len and text[i] == '.' and isIdentStart(text[i + 1])) {
        i += 2;
        while (i < text.len and isIdentContinue(text[i])) i += 1;
    }
    return i;
}

fn skipQuoted(text: []const u8, start: usize, quote: u8) usize {
    var i = start + 1;
    while (i < text.len) : (i += 1) {
        if (text[i] == '\\') {
            i += 1;
            continue;
        }
        if (text[i] == quote) return i + 1;
    }
    return i;
}

fn isIdentStart(byte: u8) bool {
    return (byte >= 'A' and byte <= 'Z') or (byte >= 'a' and byte <= 'z') or byte == '_';
}

fn isIdentContinue(byte: u8) bool {
    return isIdentStart(byte) or (byte >= '0' and byte <= '9');
}

fn isIgnoredReference(reference: []const u8) bool {
    if (reference.len == 0) return true;
    if (std.mem.eql(u8, reference, "Self")) return true;
    inline for (.{
        "addrspace",  "align",       "allowzero",    "and",      "anyerror",    "anyframe",    "anyopaque",   "anytype",
        "asm",        "bool",        "break",        "callconv", "catch",       "comptime",    "const",       "continue",
        "defer",      "else",        "enum",         "errdefer", "error",       "export",      "extern",      "false",
        "fn",         "for",         "if",           "inline",   "isize",       "linksection", "noalias",     "noinline",
        "noreturn",   "nosuspend",   "null",         "opaque",   "or",          "orelse",      "packed",      "pub",
        "resume",     "return",      "struct",       "suspend",  "switch",      "test",        "threadlocal", "true",
        "try",        "type",        "undefined",    "union",    "unreachable", "usize",       "var",         "void",
        "volatile",   "while",       "u1",           "u2",       "u3",          "u4",          "u5",          "u6",
        "u7",         "u8",          "u16",          "u24",      "u32",         "u64",         "u128",        "i1",
        "i2",         "i3",          "i4",           "i5",       "i6",          "i7",          "i8",          "i16",
        "i24",        "i32",         "i64",          "i128",     "f16",         "f32",         "f64",         "f80",
        "f128",       "c_char",      "c_short",      "c_ushort", "c_int",       "c_uint",      "c_long",      "c_ulong",
        "c_longlong", "c_ulonglong", "c_longdouble",
    }) |word| {
        if (std.mem.eql(u8, reference, word)) return true;
    }
    return false;
}

fn appendHeading(allocator: Allocator, out: *std.ArrayList(u8), level: usize, title: []const u8) !void {
    var i: usize = 0;
    while (i < level) : (i += 1) try out.append(allocator, '#');
    try out.append(allocator, ' ');
    try out.appendSlice(allocator, title);
    try out.append(allocator, '\n');
}

fn appendMarkdownEscaped(allocator: Allocator, out: *std.ArrayList(u8), text: []const u8) !void {
    for (text) |byte| {
        switch (byte) {
            '[', ']', '(', ')', '\\' => {
                try out.append(allocator, '\\');
                try out.append(allocator, byte);
            },
            else => try out.append(allocator, byte),
        }
    }
}

fn declAnchor(allocator: Allocator, decl: DeclDocs, parent: ?[]const u8) ![]const u8 {
    const base = if (parent) |p| try std.fmt.allocPrint(allocator, "{s}-{s}", .{ p, decl.name }) else decl.name;
    return anchorAlloc(allocator, decl.kind.detailPrefix(), base);
}

fn anchorAlloc(allocator: Allocator, prefix: []const u8, text: []const u8) ![]const u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    try out.appendSlice(allocator, prefix);
    try out.append(allocator, '-');
    var last_dash = false;
    for (text) |byte| {
        const lower = std.ascii.toLower(byte);
        if (isAnchorByte(lower)) {
            try out.append(allocator, lower);
            last_dash = false;
        } else if (!last_dash) {
            try out.append(allocator, '-');
            last_dash = true;
        }
    }
    while (out.items.len != 0 and out.items[out.items.len - 1] == '-') _ = out.pop();
    return out.toOwnedSlice(allocator);
}

fn isAnchorByte(byte: u8) bool {
    return (byte >= 'a' and byte <= 'z') or (byte >= '0' and byte <= '9') or byte == '_';
}

fn moduleOutputRelativePath(allocator: Allocator, module_name: []const u8) ![]const u8 {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    for (module_name) |byte| {
        try out.append(allocator, if (byte == '.') std.fs.path.sep else byte);
    }
    try out.appendSlice(allocator, ".md");
    return out.toOwnedSlice(allocator);
}

fn singleOutputPath(allocator: Allocator, out_dir: []const u8, package_name: []const u8) ![]const u8 {
    const file_name = try std.fmt.allocPrint(allocator, "{s}.md", .{package_name});
    return std.fs.path.join(allocator, &.{ out_dir, file_name });
}

fn moduleNameFromPath(allocator: Allocator, project_root_abs: []const u8, path_abs: []const u8, fallback: []const u8) ![]const u8 {
    if (fallback.len != 0) return allocator.dupe(u8, fallback);
    var rel = try std.fs.path.relative(allocator, "/", null, project_root_abs, path_abs);
    if (std.mem.startsWith(u8, rel, "src" ++ std.fs.path.sep_str)) rel = rel[4..];
    if (std.mem.endsWith(u8, rel, ".zig")) rel = rel[0 .. rel.len - 4];
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    for (rel) |byte| {
        try out.append(allocator, if (byte == std.fs.path.sep) '.' else byte);
    }
    return out.toOwnedSlice(allocator);
}

fn isInsidePath(root_abs: []const u8, path_abs: []const u8) bool {
    if (std.mem.eql(u8, root_abs, ".") or root_abs.len == 0) {
        return !std.fs.path.isAbsolute(path_abs) and !std.mem.startsWith(u8, path_abs, "..");
    }
    if (std.mem.eql(u8, root_abs, path_abs)) return true;
    if (!std.mem.startsWith(u8, path_abs, root_abs)) return false;
    if (root_abs.len == 0 or root_abs[root_abs.len - 1] == std.fs.path.sep) return true;
    return path_abs.len > root_abs.len and path_abs[root_abs.len] == std.fs.path.sep;
}

fn writeOrCheck(allocator: Allocator, io: std.Io, path: []const u8, content: []const u8, check: bool) !bool {
    if (check) {
        const existing = Dir.cwd().readFileAlloc(io, path, allocator, .limited(max_file_size)) catch |err| switch (err) {
            error.FileNotFound => {
                std.debug.print("docs-md: would create {s}\n", .{path});
                return true;
            },
            else => |e| return e,
        };
        if (!std.mem.eql(u8, existing, content)) {
            std.debug.print("docs-md: differs {s}\n", .{path});
            return true;
        }
        return false;
    }

    if (std.fs.path.dirname(path)) |parent| {
        if (parent.len != 0) try Dir.cwd().createDirPath(io, parent);
    }
    const tmp = try std.fmt.allocPrint(allocator, "{s}.tmp", .{path});
    try Dir.cwd().writeFile(io, .{ .sub_path = tmp, .data = content });
    try Dir.cwd().rename(tmp, Dir.cwd(), path, io);
    return true;
}

test "anchor generation is deterministic" {
    const allocator = std.testing.allocator;
    const anchor = try anchorAlloc(allocator, "fn", "Foo.bar!");
    defer allocator.free(anchor);
    try std.testing.expectEqualStrings("fn-foo-bar", anchor);
}
