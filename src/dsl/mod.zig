const std = @import("std");

pub const ast = @import("ast.zig");
pub const tokenizer = @import("tokenizer.zig");
pub const parser = @import("parser.zig");
pub const resolver = @import("resolver.zig");
pub const bridge = @import("bridge.zig");
pub const markdown = @import("markdown.zig");
pub const errors = @import("errors.zig");
pub const direction = @import("direction.zig");
pub const tree_bridge = @import("tree_bridge.zig");
pub const imports = @import("imports.zig");
pub const formatter = @import("formatter.zig");
pub const BuiltGraph = bridge.BuiltGraph;
pub const BuiltTable = bridge.BuiltTable;
pub const TreeResult = tree_bridge.TreeResult;

pub const ParseResult = struct {
    graphs: []BuiltGraph,
    tables: []BuiltTable,
    trees: []TreeResult,
    owned_labels: []const []const u8,
    err_list: errors.ErrorList,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ParseResult) void {
        for (self.graphs) |*g| g.deinit();
        self.allocator.free(self.graphs);
        for (self.tables) |*t| t.deinit();
        self.allocator.free(self.tables);
        for (self.trees) |*t| t.deinit();
        self.allocator.free(self.trees);
        for (self.owned_labels) |lbl| self.allocator.free(lbl);
        self.allocator.free(self.owned_labels);
        self.err_list.deinit();
    }

    pub fn hasErrors(self: *const ParseResult) bool {
        return self.err_list.hasErrors();
    }
};

/// Full pipeline: tokenize → parse → resolve → build graphs from a DSL source string.
pub fn parseAndBuild(allocator: std.mem.Allocator, source: []const u8) !ParseResult {
    var err_list = errors.ErrorList.init(allocator);
    errdefer err_list.deinit();

    const tokens = try tokenizer.tokenize(allocator, source, &err_list);
    defer allocator.free(tokens);

    var p = parser.Parser.init(allocator, tokens, &err_list);
    const doc = try p.parse();
    defer freeDoc(allocator, doc);

    const resolve_result = try resolver.resolve(allocator, doc, &err_list);

    // Collect owned labels (from var substitution) before freeing resolve result.
    // These labels are borrowed by BuiltGraph and must outlive it.
    var owned_labels_list = std.ArrayListUnmanaged([]const u8){};
    errdefer {
        for (owned_labels_list.items) |lbl| allocator.free(lbl);
        owned_labels_list.deinit(allocator);
    }
    for (resolve_result.blocks) |blk| {
        for (blk.nodes) |node| {
            if (node.label_owned) try owned_labels_list.append(allocator, node.label);
        }
        for (blk.edges) |edge| {
            if (edge.label_owned) {
                if (edge.label) |lbl| try owned_labels_list.append(allocator, lbl);
            }
        }
    }

    defer freeResolveResult(allocator, resolve_result);

    var graphs_list = std.ArrayListUnmanaged(BuiltGraph){};
    errdefer {
        for (graphs_list.items) |*g| g.deinit();
        graphs_list.deinit(allocator);
    }

    var tables_list = std.ArrayListUnmanaged(BuiltTable){};
    errdefer {
        for (tables_list.items) |*t| t.deinit();
        tables_list.deinit(allocator);
    }

    var trees_list = std.ArrayListUnmanaged(TreeResult){};
    errdefer {
        for (trees_list.items) |*t| t.deinit();
        trees_list.deinit(allocator);
    }

    // resolved blocks: optional __default__ block first, then named blocks
    // matching doc.blocks order. Track named-block offset.
    var doc_block_idx: usize = 0;
    for (resolve_result.blocks) |blk| {
        switch (blk.config.layout) {
            .table => {
                // table_headers/table_row are not preserved by the resolver;
                // use the original AST block's statements and directives.
                const ast_stmts: []const ast.Statement = if (std.mem.eql(u8, blk.name, "__default__"))
                    doc.statements
                else if (doc_block_idx >= doc.blocks.len)
                    &.{}
                else blk_stmts: {
                    const s = doc.blocks[doc_block_idx].statements;
                    break :blk_stmts s;
                };
                const ast_dirs: []const ast.Directive = if (std.mem.eql(u8, blk.name, "__default__"))
                    doc.directives
                else if (doc_block_idx >= doc.blocks.len)
                    &.{}
                else dir_blk: {
                    const d = doc.blocks[doc_block_idx].directives;
                    break :dir_blk d;
                };
                const built = try bridge.buildTable(allocator, blk.name, ast_stmts, ast_dirs, &err_list);
                try tables_list.append(allocator, built);
            },
            .tree => {
                // Build both a BuiltGraph and a TreeResult for tree blocks.
                const built_graph = try bridge.buildGraph(allocator, blk);
                try graphs_list.append(allocator, built_graph);

                // Collect node ids/labels and edges for tree_bridge.buildTree
                var node_ids = std.ArrayListUnmanaged([]const u8){};
                defer node_ids.deinit(allocator);
                var node_labels = std.ArrayListUnmanaged([]const u8){};
                defer node_labels.deinit(allocator);
                for (blk.nodes) |n| {
                    try node_ids.append(allocator, n.id);
                    try node_labels.append(allocator, n.label);
                }
                var tree_edges = std.ArrayListUnmanaged(tree_bridge.Edge){};
                defer tree_edges.deinit(allocator);
                for (blk.edges) |e| {
                    try tree_edges.append(allocator, .{ .from = e.from, .to = e.to });
                }
                const built_tree = try tree_bridge.buildTree(
                    allocator,
                    node_ids.items,
                    node_labels.items,
                    tree_edges.items,
                    &err_list,
                );
                try trees_list.append(allocator, built_tree);
            },
            else => {
                // .dag, .force, .card, .flow → buildGraph
                const built = try bridge.buildGraph(allocator, blk);
                try graphs_list.append(allocator, built);
            },
        }
        if (!std.mem.eql(u8, blk.name, "__default__")) {
            doc_block_idx += 1;
        }
    }

    return ParseResult{
        .graphs = try graphs_list.toOwnedSlice(allocator),
        .tables = try tables_list.toOwnedSlice(allocator),
        .trees = try trees_list.toOwnedSlice(allocator),
        .owned_labels = try owned_labels_list.toOwnedSlice(allocator),
        .err_list = err_list,
        .allocator = allocator,
    };
}

/// Extract zgraph code blocks from Markdown then run parseAndBuild on each.
pub fn parseMarkdown(allocator: std.mem.Allocator, md_source: []const u8) !ParseResult {
    const blocks = try markdown.extractBlocks(allocator, md_source);
    defer allocator.free(blocks);

    var err_list = errors.ErrorList.init(allocator);
    errdefer err_list.deinit();

    var graphs_list = std.ArrayListUnmanaged(BuiltGraph){};
    errdefer {
        for (graphs_list.items) |*g| g.deinit();
        graphs_list.deinit(allocator);
    }

    var tables_list = std.ArrayListUnmanaged(BuiltTable){};
    errdefer {
        for (tables_list.items) |*t| t.deinit();
        tables_list.deinit(allocator);
    }

    var trees_list = std.ArrayListUnmanaged(TreeResult){};
    errdefer {
        for (trees_list.items) |*t| t.deinit();
        trees_list.deinit(allocator);
    }

    var owned_labels_list = std.ArrayListUnmanaged([]const u8){};
    errdefer {
        for (owned_labels_list.items) |lbl| allocator.free(lbl);
        owned_labels_list.deinit(allocator);
    }

    for (blocks) |blk| {
        const tokens = try tokenizer.tokenize(allocator, blk.content, &err_list);
        defer allocator.free(tokens);

        var p = parser.Parser.init(allocator, tokens, &err_list);
        const doc = try p.parse();
        defer freeDoc(allocator, doc);

        const resolve_result = try resolver.resolve(allocator, doc, &err_list);

        // Collect owned labels before freeing resolve result
        for (resolve_result.blocks) |rb_inner| {
            for (rb_inner.nodes) |node| {
                if (node.label_owned) try owned_labels_list.append(allocator, node.label);
            }
            for (rb_inner.edges) |edge| {
                if (edge.label_owned) {
                    if (edge.label) |lbl| try owned_labels_list.append(allocator, lbl);
                }
            }
        }

        defer freeResolveResult(allocator, resolve_result);

        var doc_block_idx: usize = 0;
        for (resolve_result.blocks) |rb| {
            switch (rb.config.layout) {
                .table => {
                    const ast_stmts: []const ast.Statement = if (std.mem.eql(u8, rb.name, "__default__"))
                        doc.statements
                    else if (doc_block_idx >= doc.blocks.len)
                        &.{}
                    else s: {
                        break :s doc.blocks[doc_block_idx].statements;
                    };
                    const ast_dirs: []const ast.Directive = if (std.mem.eql(u8, rb.name, "__default__"))
                        doc.directives
                    else if (doc_block_idx >= doc.blocks.len)
                        &.{}
                    else d: {
                        break :d doc.blocks[doc_block_idx].directives;
                    };
                    const built = try bridge.buildTable(allocator, rb.name, ast_stmts, ast_dirs, &err_list);
                    try tables_list.append(allocator, built);
                },
                .tree => {
                    const built_graph = try bridge.buildGraph(allocator, rb);
                    try graphs_list.append(allocator, built_graph);

                    var node_ids = std.ArrayListUnmanaged([]const u8){};
                    defer node_ids.deinit(allocator);
                    var node_labels = std.ArrayListUnmanaged([]const u8){};
                    defer node_labels.deinit(allocator);
                    for (rb.nodes) |n| {
                        try node_ids.append(allocator, n.id);
                        try node_labels.append(allocator, n.label);
                    }
                    var tree_edges = std.ArrayListUnmanaged(tree_bridge.Edge){};
                    defer tree_edges.deinit(allocator);
                    for (rb.edges) |e| {
                        try tree_edges.append(allocator, .{ .from = e.from, .to = e.to });
                    }
                    const built_tree = try tree_bridge.buildTree(
                        allocator,
                        node_ids.items,
                        node_labels.items,
                        tree_edges.items,
                        &err_list,
                    );
                    try trees_list.append(allocator, built_tree);
                },
                else => {
                    const built = try bridge.buildGraph(allocator, rb);
                    try graphs_list.append(allocator, built);
                },
            }
            if (!std.mem.eql(u8, rb.name, "__default__")) {
                doc_block_idx += 1;
            }
        }
    }

    return ParseResult{
        .graphs = try graphs_list.toOwnedSlice(allocator),
        .tables = try tables_list.toOwnedSlice(allocator),
        .trees = try trees_list.toOwnedSlice(allocator),
        .owned_labels = try owned_labels_list.toOwnedSlice(allocator),
        .err_list = err_list,
        .allocator = allocator,
    };
}

// ── Internal helpers ────────────────────────────────────────────────────────

fn freeDoc(allocator: std.mem.Allocator, doc: ast.Document) void {
    allocator.free(doc.directives);
    for (doc.styles) |sr| allocator.free(sr.properties.properties);
    allocator.free(doc.styles);
    for (doc.statements) |s| freeStatement(allocator, s);
    allocator.free(doc.statements);
    allocator.free(doc.vars);
    for (doc.blocks) |blk| {
        allocator.free(blk.directives);
        for (blk.styles) |sr| allocator.free(sr.properties.properties);
        allocator.free(blk.styles);
        for (blk.statements) |s| freeStatement(allocator, s);
        allocator.free(blk.statements);
        allocator.free(blk.vars);
    }
    allocator.free(doc.blocks);
}

fn freeStatement(allocator: std.mem.Allocator, stmt: ast.Statement) void {
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
        .table_headers => |th| allocator.free(th.fields),
        .table_row => |tr| allocator.free(tr.fields),
        .vars_block => {},
    }
}

fn freeNodeRef(allocator: std.mem.Allocator, ref: ast.NodeRef) void {
    allocator.free(ref.classes);
    if (ref.properties) |pb| allocator.free(pb.properties);
    if (ref.card_fields) |cf| {
        for (cf) |f| allocator.free(f);
        allocator.free(cf);
    }
}

fn freeSubgraph(allocator: std.mem.Allocator, sg: resolver.ResolvedSubgraph) void {
    allocator.free(sg.node_ids);
    allocator.free(sg.properties);
    for (sg.children) |ch| freeSubgraph(allocator, ch);
    allocator.free(sg.children);
}

fn freeResolveResult(allocator: std.mem.Allocator, result: resolver.ResolveResult) void {
    for (result.blocks) |blk| {
        for (blk.nodes) |node| {
            // label_owned labels are tracked in ParseResult.owned_labels — don't free here
            allocator.free(node.properties);
        }
        allocator.free(blk.nodes);
        for (blk.edges) |edge| {
            // label_owned labels are tracked in ParseResult.owned_labels — don't free here
            allocator.free(edge.properties);
        }
        allocator.free(blk.edges);
        for (blk.subgraphs) |sg| freeSubgraph(allocator, sg);
        allocator.free(blk.subgraphs);
    }
    allocator.free(result.blocks);
}

// ── Pull in all submodule tests ─────────────────────────────────────────────

test {
    _ = ast;
    _ = tokenizer;
    _ = parser;
    _ = resolver;
    _ = bridge;
    _ = markdown;
    _ = errors;
    _ = direction;
    _ = tree_bridge;
    _ = imports;
    _ = formatter;
}

// ── End-to-end integration tests ────────────────────────────────────────────

test "end-to-end: [flow] block renders left-right" {
    const allocator = std.testing.allocator;
    const source =
        \\pipeline [flow] {
        \\  A -> B -> C
        \\}
    ;
    var result = try parseAndBuild(allocator, source);
    defer result.deinit();
    try std.testing.expect(!result.hasErrors());
    try std.testing.expect(result.graphs.len >= 1);
    // Check direction is left_right
    try std.testing.expectEqual(ast.Direction.left_right, result.graphs[0].direction);
}

test "end-to-end: vars substitution" {
    const allocator = std.testing.allocator;
    const source =
        \\vars {
        \\  svc: MyService
        \\}
        \\server: "${svc}"
        \\server -> db
    ;
    var result = try parseAndBuild(allocator, source);
    defer result.deinit();
    try std.testing.expect(!result.hasErrors());
    try std.testing.expect(result.graphs.len >= 1);
}

test "end-to-end: [table] block" {
    const allocator = std.testing.allocator;
    const source =
        \\metrics [table] {
        \\  headers: ID, Name, Status
        \\  row: 1, Parser, done
        \\  row: 2, Resolver, planned
        \\}
    ;
    var result = try parseAndBuild(allocator, source);
    defer result.deinit();
    try std.testing.expect(!result.hasErrors());
    try std.testing.expectEqual(@as(usize, 1), result.tables.len);
    try std.testing.expect(result.tables[0].headers != null);
    try std.testing.expectEqual(@as(usize, 3), result.tables[0].headers.?.len);
    try std.testing.expectEqual(@as(usize, 2), result.tables[0].rows.len);
}

test "end-to-end: [table] block with @border directive" {
    const allocator = std.testing.allocator;
    const source =
        \\metrics [table] {
        \\  @border double
        \\  @align center
        \\  headers: ID, Name
        \\  row: 1, Parser
        \\}
    ;
    var result = try parseAndBuild(allocator, source);
    defer result.deinit();
    try std.testing.expect(!result.hasErrors());
    try std.testing.expectEqual(@as(usize, 1), result.tables.len);
    try std.testing.expectEqualStrings("double", result.tables[0].border);
    try std.testing.expectEqualStrings("center", result.tables[0].alignment);
}

test "end-to-end: [table] column count mismatch reports error" {
    const allocator = std.testing.allocator;
    const source =
        \\metrics [table] {
        \\  headers: ID, Name, Status
        \\  row: 1, Parser
        \\}
    ;
    var result = try parseAndBuild(allocator, source);
    defer result.deinit();
    try std.testing.expect(result.hasErrors());
}

test "end-to-end: [tree] block" {
    const allocator = std.testing.allocator;
    const source =
        \\hierarchy [tree] {
        \\  root -> a
        \\  root -> b
        \\  b -> c
        \\}
    ;
    var result = try parseAndBuild(allocator, source);
    defer result.deinit();
    try std.testing.expect(!result.hasErrors());
    try std.testing.expect(result.trees.len >= 1);
    try std.testing.expect(result.trees[0].roots.len >= 1);
}
