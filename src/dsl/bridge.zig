const std = @import("std");
const zigraph = @import("zigraph");

const ast = @import("ast.zig");
const resolver = @import("resolver.zig");

const ResolvedBlock = resolver.ResolvedBlock;
const ResolvedNode = resolver.ResolvedNode;
const ResolvedEdge = resolver.ResolvedEdge;
const ResolvedSubgraph = resolver.ResolvedSubgraph;

// ============================================================
// Public types
// ============================================================

pub const BuiltGraph = struct {
    graph: zigraph.Graph,
    config: zigraph.LayoutConfig,
    id_map: std.StringHashMapUnmanaged(usize),
    direction: ast.Direction,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *BuiltGraph) void {
        self.graph.deinit();
        self.id_map.deinit(self.allocator);
    }
};

// ============================================================
// Bridge: ResolvedBlock → BuiltGraph
// ============================================================

pub fn buildGraph(allocator: std.mem.Allocator, block: ResolvedBlock) !BuiltGraph {
    var g = zigraph.Graph.init(allocator);
    errdefer g.deinit();

    var id_map = std.StringHashMapUnmanaged(usize){};
    errdefer id_map.deinit(allocator);

    var next_id: usize = 1;

    // Assign numeric IDs to all nodes
    for (block.nodes) |node| {
        if (!id_map.contains(node.id)) {
            try id_map.put(allocator, node.id, next_id);
            next_id += 1;
        }
    }

    // Also ensure any node referenced in edges has an ID
    for (block.edges) |edge| {
        if (!id_map.contains(edge.from)) {
            try id_map.put(allocator, edge.from, next_id);
            next_id += 1;
        }
        if (!id_map.contains(edge.to)) {
            try id_map.put(allocator, edge.to, next_id);
            next_id += 1;
        }
    }

    // Add nodes to graph (addNode is a no-op if the id already exists)
    for (block.nodes) |node| {
        const numeric_id = id_map.get(node.id).?;
        if (node.card_fields) |fields| {
            try g.addNode(numeric_id, zigraph.NodeOptions{
                .label = node.label,
                .lines = fields,
            });
        } else {
            try g.addNode(numeric_id, zigraph.NodeOptions{
                .label = node.label,
            });
        }
    }

    // Ensure edge endpoints exist as nodes in graph (implicit nodes from edge-only declarations)
    for (block.edges) |edge| {
        const from_id = id_map.get(edge.from).?;
        const to_id = id_map.get(edge.to).?;
        // addNode is a no-op if node already exists
        try g.addNode(from_id, zigraph.NodeOptions{ .label = edge.from });
        try g.addNode(to_id, zigraph.NodeOptions{ .label = edge.to });
    }

    // Add edges
    for (block.edges) |edge| {
        const from_id = id_map.get(edge.from).?;
        const to_id = id_map.get(edge.to).?;

        switch (edge.op) {
            .directed, .bold, .bold_double, .dashed_directed, .dotted_directed => {
                if (edge.label) |lbl| {
                    try g.addDiEdgeLabeled(from_id, to_id, lbl);
                } else {
                    try g.addDiEdge(from_id, to_id);
                }
            },
            .reverse => {
                // Swap direction
                if (edge.label) |lbl| {
                    try g.addDiEdgeLabeled(to_id, from_id, lbl);
                } else {
                    try g.addDiEdge(to_id, from_id);
                }
            },
            .undirected, .dotted_undirected => {
                if (edge.label) |lbl| {
                    try g.addUnDiEdgeLabeled(from_id, to_id, lbl);
                } else {
                    try g.addUnDiEdge(from_id, to_id);
                }
            },
            .bidirectional => {
                // Two directed edges
                if (edge.label) |lbl| {
                    try g.addDiEdgeLabeled(from_id, to_id, lbl);
                    try g.addDiEdgeLabeled(to_id, from_id, lbl);
                } else {
                    try g.addDiEdge(from_id, to_id);
                    try g.addDiEdge(to_id, from_id);
                }
            },
        }
    }

    // Add subgraphs
    try addSubgraphs(allocator, &g, &id_map, block.subgraphs);

    // Determine layout config
    const config = switch (block.config.layout) {
        .force => zigraph.presets.fdg_presets.standard(),
        .dag, .tree => zigraph.presets.sugiyama.standard(),
    };

    // Map direction string to enum
    const direction: ast.Direction = blk: {
        if (std.mem.eql(u8, block.config.direction, "left-right")) break :blk .left_right
        else if (std.mem.eql(u8, block.config.direction, "bottom-up")) break :blk .bottom_up
        else if (std.mem.eql(u8, block.config.direction, "right-left")) break :blk .right_left
        else break :blk .top_down;
    };

    return BuiltGraph{
        .graph = g,
        .config = config,
        .id_map = id_map,
        .direction = direction,
        .allocator = allocator,
    };
}

fn addSubgraphs(
    allocator: std.mem.Allocator,
    g: *zigraph.Graph,
    id_map: *std.StringHashMapUnmanaged(usize),
    subgraphs: []const ResolvedSubgraph,
) !void {
    for (subgraphs) |sg| {
        const sg_label = sg.label orelse sg.name;
        const sg_id = try g.addSubgraph(sg_label);

        // Collect the numeric IDs for nodes in this subgraph
        var node_ids = std.ArrayListUnmanaged(usize){};
        defer node_ids.deinit(allocator);

        for (sg.node_ids) |str_id| {
            if (id_map.get(str_id)) |num_id| {
                // Ensure node exists in graph (addNode is no-op if already present)
                try g.addNode(num_id, zigraph.NodeOptions{ .label = str_id });
                try node_ids.append(allocator, num_id);
            }
        }

        if (node_ids.items.len > 0) {
            try g.putNodes(node_ids.items).inside(sg_id);
        }

        // Recurse into children subgraphs
        try addSubgraphs(allocator, g, id_map, sg.children);
    }
}

// ============================================================
// Tests
// ============================================================

const tokenizer_mod = @import("tokenizer.zig");
const parser_mod = @import("parser.zig");
const errors_mod = @import("errors.zig");

fn testBuild(source: []const u8) !BuiltGraph {
    const allocator = std.testing.allocator;
    var err_list = errors_mod.ErrorList.init(allocator);
    defer err_list.deinit();

    const tokens = try tokenizer_mod.tokenize(allocator, source, &err_list);
    defer allocator.free(tokens);

    var parser = parser_mod.Parser.init(allocator, tokens, &err_list);
    const doc = try parser.parse();
    defer {
        allocator.free(doc.directives);
        for (doc.styles) |sr| allocator.free(sr.properties.properties);
        allocator.free(doc.styles);
        for (doc.statements) |s| freeAstStatement(s);
        allocator.free(doc.statements);
        for (doc.blocks) |blk| {
            allocator.free(blk.directives);
            for (blk.styles) |sr| allocator.free(sr.properties.properties);
            allocator.free(blk.styles);
            for (blk.statements) |s| freeAstStatement(s);
            allocator.free(blk.statements);
        }
        allocator.free(doc.blocks);
    }

    const resolve_result = try resolver.resolve(allocator, doc, &err_list);
    defer {
        for (resolve_result.blocks) |blk| {
            for (blk.nodes) |node| allocator.free(node.properties);
            allocator.free(blk.nodes);
            for (blk.edges) |edge| allocator.free(edge.properties);
            allocator.free(blk.edges);
            for (blk.subgraphs) |sg| freeSubgraph(sg);
            allocator.free(blk.subgraphs);
        }
        allocator.free(resolve_result.blocks);
    }

    if (resolve_result.blocks.len == 0) return error.NoBlocks;
    return buildGraph(allocator, resolve_result.blocks[0]);
}

fn freeAstStatement(stmt: ast.Statement) void {
    const a = std.testing.allocator;
    switch (stmt) {
        .edge => |e| {
            for (e.chain) |ref| freeAstNodeRef(ref);
            a.free(e.chain);
            a.free(e.classes);
            if (e.properties) |pb| a.free(pb.properties);
        },
        .node_decl => |nd| freeAstNodeRef(nd.ref),
        .subgraph => |sg| {
            for (sg.statements) |s| freeAstStatement(s);
            a.free(sg.statements);
            if (sg.properties) |pb| a.free(pb.properties);
        },
    }
}

fn freeAstNodeRef(ref: ast.NodeRef) void {
    const a = std.testing.allocator;
    a.free(ref.classes);
    if (ref.properties) |pb| a.free(pb.properties);
    if (ref.card_fields) |cf| {
        for (cf) |f| a.free(f);
        a.free(cf);
    }
}

fn freeSubgraph(sg: resolver.ResolvedSubgraph) void {
    const a = std.testing.allocator;
    a.free(sg.node_ids);
    a.free(sg.properties);
    for (sg.children) |ch| freeSubgraph(ch);
    a.free(sg.children);
}

test "simple chain A -> B -> C produces 3 nodes and 2 edges" {
    var built = try testBuild("A -> B -> C");
    defer built.deinit();

    try std.testing.expectEqual(@as(usize, 3), built.graph.nodes.items.len);
    try std.testing.expectEqual(@as(usize, 2), built.graph.edges.items.len);
}

test "labeled edge produces 2 nodes and 1 edge" {
    var built = try testBuild("A -> B: \"connects\"");
    defer built.deinit();

    try std.testing.expectEqual(@as(usize, 2), built.graph.nodes.items.len);
    try std.testing.expectEqual(@as(usize, 1), built.graph.edges.items.len);
}

test "undirected edge produces 2 nodes and at least 1 edge" {
    var built = try testBuild("A -- B");
    defer built.deinit();

    try std.testing.expectEqual(@as(usize, 2), built.graph.nodes.items.len);
    try std.testing.expect(built.graph.edges.items.len >= 1);
}

test "subgraph produces hasSubgraphs true" {
    var built = try testBuild("cluster: {\n  A -> B\n}");
    defer built.deinit();

    try std.testing.expect(built.graph.hasSubgraphs());
}

test "card node with fields produces non-empty lines" {
    var built = try testBuild("svc: [Auth | Port: 8080]");
    defer built.deinit();

    try std.testing.expectEqual(@as(usize, 1), built.graph.nodes.items.len);
    const node = built.graph.nodes.items[0];
    try std.testing.expect(node.lines.len > 0);
}

test "force layout config produces fruchterman_reingold algorithm" {
    const allocator = std.testing.allocator;
    var err_list = errors_mod.ErrorList.init(allocator);
    defer err_list.deinit();

    const source = "modules [force] {\n  A -> B\n}";
    const tokens = try tokenizer_mod.tokenize(allocator, source, &err_list);
    defer allocator.free(tokens);

    var parser = parser_mod.Parser.init(allocator, tokens, &err_list);
    const doc = try parser.parse();
    defer {
        allocator.free(doc.directives);
        for (doc.styles) |sr| allocator.free(sr.properties.properties);
        allocator.free(doc.styles);
        for (doc.statements) |s| freeAstStatement(s);
        allocator.free(doc.statements);
        for (doc.blocks) |blk| {
            allocator.free(blk.directives);
            for (blk.styles) |sr| allocator.free(sr.properties.properties);
            allocator.free(blk.styles);
            for (blk.statements) |s| freeAstStatement(s);
            allocator.free(blk.statements);
        }
        allocator.free(doc.blocks);
    }

    const resolve_result = try resolver.resolve(allocator, doc, &err_list);
    defer {
        for (resolve_result.blocks) |blk| {
            for (blk.nodes) |node| allocator.free(node.properties);
            allocator.free(blk.nodes);
            for (blk.edges) |edge| allocator.free(edge.properties);
            allocator.free(blk.edges);
            for (blk.subgraphs) |sg| freeSubgraph(sg);
            allocator.free(blk.subgraphs);
        }
        allocator.free(resolve_result.blocks);
    }

    // First block is __default__ (empty), second is "modules [force]"
    try std.testing.expect(resolve_result.blocks.len >= 1);

    // Find the force block
    var force_block_idx: ?usize = null;
    for (resolve_result.blocks, 0..) |blk, i| {
        if (blk.config.layout == .force) {
            force_block_idx = i;
            break;
        }
    }
    try std.testing.expect(force_block_idx != null);

    var built = try buildGraph(allocator, resolve_result.blocks[force_block_idx.?]);
    defer built.deinit();

    try std.testing.expect(built.config.algorithm == .fruchterman_reingold);
}
