const std = @import("std");
const Allocator = std.mem.Allocator;
const ast = @import("ast.zig");
const tokenizer = @import("tokenizer.zig");
const parser = @import("parser.zig");
const errors = @import("errors.zig");

pub const ImportResult = struct {
    styles: []ast.StyleRule,
    vars: []ast.Property,
};

/// Resolve all @import directives in `directives`, reading and parsing each
/// imported file relative to `base_dir`. Collected style rules and vars from
/// all imports (including transitively imported files) are returned.
///
/// `visited` tracks absolute paths already processed so cycles can be detected.
/// Keys in `visited` must be allocator-owned strings.
pub fn resolveImports(
    allocator: Allocator,
    directives: []const ast.Directive,
    base_dir: []const u8,
    visited: *std.StringHashMap(void),
    err_list: *errors.ErrorList,
) !ImportResult {
    var styles = std.ArrayListUnmanaged(ast.StyleRule){};
    errdefer styles.deinit(allocator);

    var vars = std.ArrayListUnmanaged(ast.Property){};
    errdefer vars.deinit(allocator);

    for (directives) |directive| {
        if (directive.kind != .import_) continue;

        // Resolve the import path relative to base_dir.
        const abs_path = try std.fs.path.join(allocator, &.{ base_dir, directive.value });
        errdefer allocator.free(abs_path);

        // Cycle detection: check if we have already visited this path.
        if (visited.contains(abs_path)) {
            try err_list.add(directive.loc, .unresolved_reference, "import cycle detected");
            allocator.free(abs_path);
            continue;
        }

        // Mark as visited (transfer ownership of abs_path to the map key).
        try visited.put(abs_path, {});
        // abs_path is now owned by visited — do not free it here.

        // Read the imported file.
        const source = std.fs.cwd().readFileAlloc(allocator, abs_path, 1024 * 1024) catch {
            try err_list.add(directive.loc, .unresolved_reference, "could not read imported file");
            continue;
        };
        defer allocator.free(source);

        // Tokenize the imported file.
        const tokens = try tokenizer.tokenize(allocator, source, err_list);
        defer allocator.free(tokens);

        // Parse the imported file.
        var p = parser.Parser.init(allocator, tokens, err_list);
        const doc = try p.parse();
        defer freeDoc(allocator, doc);

        // Determine the base directory of the imported file for recursive imports.
        const import_dir = std.fs.path.dirname(abs_path) orelse ".";

        // Recursively resolve imports in the imported file first.
        const sub_result = try resolveImports(allocator, doc.directives, import_dir, visited, err_list);
        defer {
            allocator.free(sub_result.styles);
            allocator.free(sub_result.vars);
        }

        // Merge: sub-imports first, then the file's own styles/vars.
        try styles.appendSlice(allocator, sub_result.styles);
        try vars.appendSlice(allocator, sub_result.vars);

        try styles.appendSlice(allocator, doc.styles);
        try vars.appendSlice(allocator, doc.vars);
    }

    return ImportResult{
        .styles = try styles.toOwnedSlice(allocator),
        .vars = try vars.toOwnedSlice(allocator),
    };
}

// ── Minimal document cleanup for parsed imports ──────────────────────────────
// We only free the allocator-owned slices produced by Parser.parse(); we do
// NOT deep-free node/property text because those point into the source slice
// which is freed by the caller.

fn freeDoc(allocator: Allocator, doc: ast.Document) void {
    allocator.free(doc.directives);
    for (doc.styles) |sr| allocator.free(sr.properties.properties);
    allocator.free(doc.styles);
    for (doc.statements) |s| freeStatement(allocator, s);
    allocator.free(doc.statements);
    for (doc.blocks) |blk| {
        allocator.free(blk.directives);
        for (blk.styles) |sr| allocator.free(sr.properties.properties);
        allocator.free(blk.styles);
        for (blk.statements) |s| freeStatement(allocator, s);
        allocator.free(blk.statements);
        allocator.free(blk.vars);
    }
    allocator.free(doc.blocks);
    allocator.free(doc.vars);
}

fn freeStatement(allocator: Allocator, stmt: ast.Statement) void {
    switch (stmt) {
        .edge => |e| {
            for (e.chain) |ref| freeNodeRef(allocator, ref);
            allocator.free(e.chain);
            allocator.free(e.classes);
            if (e.properties) |pb| allocator.free(pb.properties);
        },
        .node_decl => |nd| freeNodeRef(allocator, nd.ref),
        .subgraph => |sg| {
            for (sg.statements) |s| freeStatement(allocator, s);
            allocator.free(sg.statements);
            if (sg.properties) |pb| allocator.free(pb.properties);
        },
        .table_headers, .table_row, .vars_block => {},
    }
}

fn freeNodeRef(allocator: Allocator, ref: ast.NodeRef) void {
    allocator.free(ref.classes);
    if (ref.properties) |pb| allocator.free(pb.properties);
    if (ref.card_fields) |cf| {
        for (cf) |f| allocator.free(f);
        allocator.free(cf);
    }
}

// ── Tests ────────────────────────────────────────────────────────────────────

test "import: cycle detection" {
    const allocator = std.testing.allocator;
    var err_list = errors.ErrorList.init(allocator);
    defer err_list.deinit();

    var visited = std.StringHashMap(void).init(allocator);
    defer {
        var it = visited.keyIterator();
        while (it.next()) |key| allocator.free(key.*);
        visited.deinit();
    }

    // Pre-mark a path as visited to simulate a cycle.
    const fake_path = try std.fs.path.join(allocator, &.{ "/fake/path", "styles.zgraph" });
    try visited.put(fake_path, {});

    const directives: []const ast.Directive = &.{.{
        .kind = .import_,
        .value = "styles.zgraph",
        .loc = errors.Loc.zero,
    }};

    const result = try resolveImports(allocator, directives, "/fake/path", &visited, &err_list);
    defer {
        allocator.free(result.styles);
        allocator.free(result.vars);
    }
    try std.testing.expect(err_list.hasErrors());
}
