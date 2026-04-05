const std = @import("std");

pub const ast = @import("ast.zig");
pub const tokenizer = @import("tokenizer.zig");
pub const parser = @import("parser.zig");
pub const resolver = @import("resolver.zig");
pub const bridge = @import("bridge.zig");
pub const markdown = @import("markdown.zig");
pub const errors = @import("errors.zig");
pub const BuiltGraph = bridge.BuiltGraph;

pub const ParseResult = struct {
    graphs: []BuiltGraph,
    err_list: errors.ErrorList,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ParseResult) void {
        for (self.graphs) |*g| g.deinit();
        self.allocator.free(self.graphs);
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
    defer freeResolveResult(allocator, resolve_result);

    var graphs_list = std.ArrayListUnmanaged(BuiltGraph){};
    errdefer {
        for (graphs_list.items) |*g| g.deinit();
        graphs_list.deinit(allocator);
    }

    for (resolve_result.blocks) |blk| {
        const built = try bridge.buildGraph(allocator, blk);
        try graphs_list.append(allocator, built);
    }

    return ParseResult{
        .graphs = try graphs_list.toOwnedSlice(allocator),
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

    for (blocks) |blk| {
        const tokens = try tokenizer.tokenize(allocator, blk.content, &err_list);
        defer allocator.free(tokens);

        var p = parser.Parser.init(allocator, tokens, &err_list);
        const doc = try p.parse();
        defer freeDoc(allocator, doc);

        const resolve_result = try resolver.resolve(allocator, doc, &err_list);
        defer freeResolveResult(allocator, resolve_result);

        for (resolve_result.blocks) |rb| {
            const built = try bridge.buildGraph(allocator, rb);
            try graphs_list.append(allocator, built);
        }
    }

    return ParseResult{
        .graphs = try graphs_list.toOwnedSlice(allocator),
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
    for (doc.blocks) |blk| {
        allocator.free(blk.directives);
        for (blk.styles) |sr| allocator.free(sr.properties.properties);
        allocator.free(blk.styles);
        for (blk.statements) |s| freeStatement(allocator, s);
        allocator.free(blk.statements);
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
        for (blk.nodes) |node| allocator.free(node.properties);
        allocator.free(blk.nodes);
        for (blk.edges) |edge| allocator.free(edge.properties);
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
}
