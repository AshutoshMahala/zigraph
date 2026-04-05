const std = @import("std");
const ast = @import("ast.zig");
const errors = @import("errors.zig");
const tokenizer_mod = @import("tokenizer.zig");
const parser_mod = @import("parser.zig");

const Loc = errors.Loc;

// ============================================================
// Resolved types
// ============================================================

pub const ResolvedProperty = struct {
    key: []const u8,
    value: []const u8,
};

pub const ResolvedNode = struct {
    id: []const u8,
    label: []const u8,
    shape: ast.Shape,
    card_fields: ?[]const []const u8,
    properties: []ResolvedProperty,
    loc: Loc,
};

pub const ResolvedEdge = struct {
    from: []const u8,
    to: []const u8,
    op: ast.EdgeOp,
    label: ?[]const u8,
    properties: []ResolvedProperty,
    loc: Loc,
};

pub const ResolvedSubgraph = struct {
    name: []const u8,
    label: ?[]const u8,
    node_ids: []const []const u8,
    properties: []ResolvedProperty,
    children: []ResolvedSubgraph,
};

pub const ResolvedConfig = struct {
    layout: ast.Layout,
    direction: []const u8,
    spacing: []const u8,
    theme: []const u8,
};

pub const ResolvedBlock = struct {
    name: []const u8,
    config: ResolvedConfig,
    nodes: []ResolvedNode,
    edges: []ResolvedEdge,
    subgraphs: []ResolvedSubgraph,
};

pub const ResolveResult = struct {
    blocks: []ResolvedBlock,
};

// ============================================================
// Resolver state
// ============================================================

const Resolver = struct {
    allocator: std.mem.Allocator,
    err_list: *errors.ErrorList,

    /// Global @style node { ... } defaults: key -> value
    node_defaults: std.StringHashMapUnmanaged([]const u8),
    /// Global @style edge { ... } defaults: key -> value
    edge_defaults: std.StringHashMapUnmanaged([]const u8),
    /// Global @style .class { ... } rules: class_name -> (key -> value)
    class_styles: std.StringHashMapUnmanaged(std.StringHashMapUnmanaged([]const u8)),

    fn init(allocator: std.mem.Allocator, err_list: *errors.ErrorList) Resolver {
        return .{
            .allocator = allocator,
            .err_list = err_list,
            .node_defaults = .{},
            .edge_defaults = .{},
            .class_styles = .{},
        };
    }

    fn deinit(self: *Resolver) void {
        self.node_defaults.deinit(self.allocator);
        self.edge_defaults.deinit(self.allocator);
        var it = self.class_styles.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.class_styles.deinit(self.allocator);
    }

    /// Load global style rules into maps.
    fn loadStyles(self: *Resolver, styles: []const ast.StyleRule) !void {
        for (styles) |rule| {
            switch (rule.selector) {
                .element => |elem| {
                    const map = if (elem == .node) &self.node_defaults else &self.edge_defaults;
                    for (rule.properties.properties) |prop| {
                        try map.put(self.allocator, prop.key, prop.value);
                    }
                },
                .class => |cls| {
                    const result = try self.class_styles.getOrPut(self.allocator, cls);
                    if (!result.found_existing) {
                        result.value_ptr.* = .{};
                    }
                    for (rule.properties.properties) |prop| {
                        try result.value_ptr.put(self.allocator, prop.key, prop.value);
                    }
                },
            }
        }
    }

    /// Resolve config from directives, falling back to base defaults.
    fn resolveConfig(base: ResolvedConfig, directives: []const ast.Directive) ResolvedConfig {
        var cfg = base;
        for (directives) |dir| {
            switch (dir.kind) {
                .layout => {
                    if (std.mem.eql(u8, dir.value, "dag"))   cfg.layout = .dag
                    else if (std.mem.eql(u8, dir.value, "tree"))  cfg.layout = .tree
                    else if (std.mem.eql(u8, dir.value, "force")) cfg.layout = .force;
                    // unknown layout values silently ignored (parser already warned)
                },
                .direction => cfg.direction = dir.value,
                .spacing   => cfg.spacing   = dir.value,
                .theme     => cfg.theme     = dir.value,
            }
        }
        return cfg;
    }

    /// Build resolved properties by cascading: node/edge defaults → class styles → inline props.
    fn cascadeNodeProperties(
        self: *Resolver,
        classes: []const []const u8,
        inline_props: ?ast.PropertyBlock,
    ) ![]ResolvedProperty {
        // Start with node defaults
        var merged: std.StringHashMapUnmanaged([]const u8) = .{};
        defer merged.deinit(self.allocator);

        var it = self.node_defaults.iterator();
        while (it.next()) |entry| {
            try merged.put(self.allocator, entry.key_ptr.*, entry.value_ptr.*);
        }

        // Apply class styles
        for (classes) |cls| {
            if (self.class_styles.get(cls)) |cls_map| {
                var cit = cls_map.iterator();
                while (cit.next()) |entry| {
                    try merged.put(self.allocator, entry.key_ptr.*, entry.value_ptr.*);
                }
            }
        }

        // Apply inline properties
        if (inline_props) |pb| {
            for (pb.properties) |prop| {
                try merged.put(self.allocator, prop.key, prop.value);
            }
        }

        var result: std.ArrayListUnmanaged(ResolvedProperty) = .{};
        var mit = merged.iterator();
        while (mit.next()) |entry| {
            try result.append(self.allocator, .{
                .key   = entry.key_ptr.*,
                .value = entry.value_ptr.*,
            });
        }
        return result.toOwnedSlice(self.allocator);
    }

    fn cascadeEdgeProperties(
        self: *Resolver,
        classes: []const []const u8,
        inline_props: ?ast.PropertyBlock,
    ) ![]ResolvedProperty {
        var merged: std.StringHashMapUnmanaged([]const u8) = .{};
        defer merged.deinit(self.allocator);

        var it = self.edge_defaults.iterator();
        while (it.next()) |entry| {
            try merged.put(self.allocator, entry.key_ptr.*, entry.value_ptr.*);
        }

        for (classes) |cls| {
            if (self.class_styles.get(cls)) |cls_map| {
                var cit = cls_map.iterator();
                while (cit.next()) |entry| {
                    try merged.put(self.allocator, entry.key_ptr.*, entry.value_ptr.*);
                }
            }
        }

        if (inline_props) |pb| {
            for (pb.properties) |prop| {
                try merged.put(self.allocator, prop.key, prop.value);
            }
        }

        var result: std.ArrayListUnmanaged(ResolvedProperty) = .{};
        var mit = merged.iterator();
        while (mit.next()) |entry| {
            try result.append(self.allocator, .{
                .key   = entry.key_ptr.*,
                .value = entry.value_ptr.*,
            });
        }
        return result.toOwnedSlice(self.allocator);
    }

    /// Derive shape from properties or card_fields; default is rect.
    fn resolveShape(
        props: []const ResolvedProperty,
        card_fields: ?[]const []const u8,
    ) ast.Shape {
        if (card_fields != null) return .card;
        for (props) |p| {
            if (std.mem.eql(u8, p.key, "shape")) {
                if (std.mem.eql(u8, p.value, "rect"))          return .rect;
                if (std.mem.eql(u8, p.value, "circle"))        return .circle;
                if (std.mem.eql(u8, p.value, "diamond"))       return .diamond;
                if (std.mem.eql(u8, p.value, "cylinder"))      return .cylinder;
                if (std.mem.eql(u8, p.value, "person"))        return .person;
                if (std.mem.eql(u8, p.value, "pill"))          return .pill;
                if (std.mem.eql(u8, p.value, "hexagon"))       return .hexagon;
                if (std.mem.eql(u8, p.value, "parallelogram")) return .parallelogram;
                if (std.mem.eql(u8, p.value, "queue"))         return .queue;
                if (std.mem.eql(u8, p.value, "cloud"))         return .cloud;
                if (std.mem.eql(u8, p.value, "card"))          return .card;
            }
        }
        return .rect;
    }

    /// Ensure a node with `id` exists in the map; if not, create an implicit one.
    fn ensureNode(
        self: *Resolver,
        id: []const u8,
        loc: Loc,
        node_map: *std.StringHashMapUnmanaged(ResolvedNode),
    ) !void {
        if (node_map.contains(id)) return;
        const props = try self.cascadeNodeProperties(&.{}, null);
        const shape = resolveShape(props, null);
        try node_map.put(self.allocator, id, .{
            .id          = id,
            .label       = id,
            .shape       = shape,
            .card_fields = null,
            .properties  = props,
            .loc         = loc,
        });
    }

    /// Resolve a NodeRef into a node, creating or updating the map entry.
    fn resolveNodeRef(
        self: *Resolver,
        ref: ast.NodeRef,
        node_map: *std.StringHashMapUnmanaged(ResolvedNode),
    ) !void {
        const props = try self.cascadeNodeProperties(ref.classes, ref.properties);
        const shape = resolveShape(props, ref.card_fields);
        const label = ref.label orelse ref.id;
        try node_map.put(self.allocator, ref.id, .{
            .id          = ref.id,
            .label       = label,
            .shape       = shape,
            .card_fields = ref.card_fields,
            .properties  = props,
            .loc         = ref.loc,
        });
    }

    /// Collect node IDs that appear in a subgraph's statements (does not recurse into named blocks).
    fn collectSubgraphNodeIds(
        self: *Resolver,
        stmts: []const ast.Statement,
        node_map: *std.StringHashMapUnmanaged(ResolvedNode),
        edges_list: *std.ArrayListUnmanaged(ResolvedEdge),
    ) ![]const []const u8 {
        var ids: std.StringHashMapUnmanaged(void) = .{};
        defer ids.deinit(self.allocator);

        for (stmts) |stmt| {
            switch (stmt) {
                .edge => |e| {
                    for (e.chain) |ref| {
                        try self.ensureNode(ref.id, ref.loc, node_map);
                        try ids.put(self.allocator, ref.id, {});
                    }
                    // create edges
                    try self.resolveEdgeStatement(e, node_map, edges_list);
                },
                .node_decl => |nd| {
                    try self.resolveNodeRef(nd.ref, node_map);
                    try ids.put(self.allocator, nd.ref.id, {});
                },
                .subgraph => |sg| {
                    _ = sg;
                    // nested subgraph node collection omitted for simplicity
                },
            }
        }

        var result: std.ArrayListUnmanaged([]const u8) = .{};
        var it = ids.keyIterator();
        while (it.next()) |k| {
            try result.append(self.allocator, k.*);
        }
        return result.toOwnedSlice(self.allocator);
    }

    fn resolveEdgeStatement(
        self: *Resolver,
        e: ast.EdgeStatement,
        node_map: *std.StringHashMapUnmanaged(ResolvedNode),
        edges_list: *std.ArrayListUnmanaged(ResolvedEdge),
    ) !void {
        const props = try self.cascadeEdgeProperties(e.classes, e.properties);

        if (e.fan_out) {
            // chain[0] → chain[1..] all as individual edges
            if (e.chain.len < 2) return;
            const src = e.chain[0];
            try self.ensureNode(src.id, src.loc, node_map);
            for (e.chain[1..]) |tgt| {
                try self.ensureNode(tgt.id, tgt.loc, node_map);
                // Duplicate props slice for each edge — share the same slice since it's read-only
                try edges_list.append(self.allocator, .{
                    .from       = src.id,
                    .to         = tgt.id,
                    .op         = e.operator,
                    .label      = e.label,
                    .properties = props,
                    .loc        = e.loc,
                });
            }
        } else {
            // linear chain: adjacent pairs
            var i: usize = 0;
            while (i + 1 < e.chain.len) : (i += 1) {
                const src = e.chain[i];
                const tgt = e.chain[i + 1];
                try self.ensureNode(src.id, src.loc, node_map);
                try self.ensureNode(tgt.id, tgt.loc, node_map);
                try edges_list.append(self.allocator, .{
                    .from       = src.id,
                    .to         = tgt.id,
                    .op         = e.operator,
                    .label      = e.label,
                    .properties = props,
                    .loc        = e.loc,
                });
            }
        }
    }

    fn resolveSubgraph(
        self: *Resolver,
        sg: ast.SubgraphDecl,
        node_map: *std.StringHashMapUnmanaged(ResolvedNode),
        edges_list: *std.ArrayListUnmanaged(ResolvedEdge),
    ) !ResolvedSubgraph {
        // Resolve children subgraphs first (nested)
        var children: std.ArrayListUnmanaged(ResolvedSubgraph) = .{};
        for (sg.statements) |stmt| {
            if (stmt == .subgraph) {
                const child = try self.resolveSubgraph(stmt.subgraph, node_map, edges_list);
                try children.append(self.allocator, child);
            }
        }

        const node_ids = try self.collectSubgraphNodeIds(sg.statements, node_map, edges_list);

        var props: std.ArrayListUnmanaged(ResolvedProperty) = .{};
        if (sg.properties) |pb| {
            for (pb.properties) |p| {
                try props.append(self.allocator, .{ .key = p.key, .value = p.value });
            }
        }

        return ResolvedSubgraph{
            .name       = sg.name,
            .label      = sg.label,
            .node_ids   = node_ids,
            .properties = try props.toOwnedSlice(self.allocator),
            .children   = try children.toOwnedSlice(self.allocator),
        };
    }

    /// Resolve a list of statements into nodes, edges, subgraphs.
    fn resolveStatements(
        self: *Resolver,
        stmts: []const ast.Statement,
    ) !struct {
        nodes: []ResolvedNode,
        edges: []ResolvedEdge,
        subgraphs: []ResolvedSubgraph,
    } {
        var node_map: std.StringHashMapUnmanaged(ResolvedNode) = .{};
        defer node_map.deinit(self.allocator);

        var edges_list: std.ArrayListUnmanaged(ResolvedEdge) = .{};
        var subgraphs_list: std.ArrayListUnmanaged(ResolvedSubgraph) = .{};

        for (stmts) |stmt| {
            switch (stmt) {
                .edge => |e| {
                    try self.resolveEdgeStatement(e, &node_map, &edges_list);
                },
                .node_decl => |nd| {
                    try self.resolveNodeRef(nd.ref, &node_map);
                },
                .subgraph => |sg| {
                    const resolved_sg = try self.resolveSubgraph(sg, &node_map, &edges_list);
                    try subgraphs_list.append(self.allocator, resolved_sg);
                },
            }
        }

        // Convert node_map to slice (preserve insertion-ish order by iterating map)
        var nodes_list: std.ArrayListUnmanaged(ResolvedNode) = .{};
        var nit = node_map.iterator();
        while (nit.next()) |entry| {
            try nodes_list.append(self.allocator, entry.value_ptr.*);
        }

        return .{
            .nodes     = try nodes_list.toOwnedSlice(self.allocator),
            .edges     = try edges_list.toOwnedSlice(self.allocator),
            .subgraphs = try subgraphs_list.toOwnedSlice(self.allocator),
        };
    }
};

// ============================================================
// Public entry point
// ============================================================

pub fn resolve(
    allocator: std.mem.Allocator,
    doc: ast.Document,
    err_list: *errors.ErrorList,
) !ResolveResult {
    var r = Resolver.init(allocator, err_list);
    defer r.deinit();

    // 1. Load global styles
    try r.loadStyles(doc.styles);

    // 2. Global config defaults
    const global_config = ResolvedConfig{
        .layout    = .dag,
        .direction = "top-down",
        .spacing   = "normal",
        .theme     = "default",
    };
    const file_config = Resolver.resolveConfig(global_config, doc.directives);

    var blocks_list: std.ArrayListUnmanaged(ResolvedBlock) = .{};

    // 3. Bare statements → __default__ block (only if non-empty)
    if (doc.statements.len > 0) {
        const resolved = try r.resolveStatements(doc.statements);
        try blocks_list.append(allocator, .{
            .name      = "__default__",
            .config    = file_config,
            .nodes     = resolved.nodes,
            .edges     = resolved.edges,
            .subgraphs = resolved.subgraphs,
        });
    }

    // 4. Named blocks
    for (doc.blocks) |blk| {
        // Build per-block style maps (merged on top of global)
        var block_resolver = Resolver.init(allocator, err_list);
        defer block_resolver.deinit();

        // Inherit global styles first
        try block_resolver.loadStyles(doc.styles);
        // Then override with block-local styles
        try block_resolver.loadStyles(blk.styles);

        // Config: file-level → block-level directives
        var block_config = file_config;
        if (blk.layout) |lt| block_config.layout = lt;
        block_config = Resolver.resolveConfig(block_config, blk.directives);

        const resolved = try block_resolver.resolveStatements(blk.statements);
        try blocks_list.append(allocator, .{
            .name      = blk.name,
            .config    = block_config,
            .nodes     = resolved.nodes,
            .edges     = resolved.edges,
            .subgraphs = resolved.subgraphs,
        });
    }

    return ResolveResult{
        .blocks = try blocks_list.toOwnedSlice(allocator),
    };
}

// ============================================================
// Free helpers (for tests)
// ============================================================

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

fn freeAstDoc(doc: ast.Document) void {
    const a = std.testing.allocator;
    a.free(doc.directives);
    for (doc.styles) |sr| a.free(sr.properties.properties);
    a.free(doc.styles);
    for (doc.statements) |s| freeAstStatement(s);
    a.free(doc.statements);
    for (doc.blocks) |blk| {
        a.free(blk.directives);
        for (blk.styles) |sr| a.free(sr.properties.properties);
        a.free(blk.styles);
        for (blk.statements) |s| freeAstStatement(s);
        a.free(blk.statements);
    }
    a.free(doc.blocks);
}

fn freeSubgraph(sg: ResolvedSubgraph) void {
    const a = std.testing.allocator;
    a.free(sg.node_ids);
    a.free(sg.properties);
    for (sg.children) |ch| freeSubgraph(ch);
    a.free(sg.children);
}

fn freeResolveResult(result: ResolveResult) void {
    const a = std.testing.allocator;
    for (result.blocks) |blk| {
        for (blk.nodes) |node| {
            a.free(node.properties);
        }
        a.free(blk.nodes);
        for (blk.edges) |edge| {
            // properties slice may be shared across fan-out edges; free once per unique pointer
            // For simplicity, free each — they are distinct slices from cascadeEdgeProperties
            a.free(edge.properties);
        }
        a.free(blk.edges);
        for (blk.subgraphs) |sg| freeSubgraph(sg);
        a.free(blk.subgraphs);
    }
    a.free(result.blocks);
}

// ============================================================
// Tests
// ============================================================

fn testResolve(source: []const u8) !struct { result: ResolveResult, doc: ast.Document, err_list: errors.ErrorList } {
    var err_list = errors.ErrorList.init(std.testing.allocator);
    const tokens = try tokenizer_mod.tokenize(std.testing.allocator, source, &err_list);
    defer std.testing.allocator.free(tokens);
    var parser = parser_mod.Parser.init(std.testing.allocator, tokens, &err_list);
    const doc = try parser.parse();
    const result = try resolve(std.testing.allocator, doc, &err_list);
    return .{ .result = result, .doc = doc, .err_list = err_list };
}

test "resolve chain A -> B -> C produces 1 block, 3 nodes, 2 edges" {
    const out = try testResolve("A -> B -> C");
    defer freeAstDoc(out.doc);
    defer freeResolveResult(out.result);
    defer @constCast(&out.err_list).deinit();

    try std.testing.expect(!out.err_list.hasErrors());
    try std.testing.expectEqual(@as(usize, 1), out.result.blocks.len);

    const blk = out.result.blocks[0];
    try std.testing.expectEqualStrings("__default__", blk.name);
    try std.testing.expectEqual(@as(usize, 3), blk.nodes.len);
    try std.testing.expectEqual(@as(usize, 2), blk.edges.len);

    // Each node's label should equal its ID (implicit nodes)
    for (blk.nodes) |node| {
        try std.testing.expectEqualStrings(node.id, node.label);
    }
}

test "resolve node with explicit label" {
    const out = try testResolve("db: \"PostgreSQL\"");
    defer freeAstDoc(out.doc);
    defer freeResolveResult(out.result);
    defer @constCast(&out.err_list).deinit();

    try std.testing.expect(!out.err_list.hasErrors());
    try std.testing.expectEqual(@as(usize, 1), out.result.blocks.len);

    const blk = out.result.blocks[0];
    try std.testing.expectEqual(@as(usize, 1), blk.nodes.len);
    try std.testing.expectEqualStrings("db", blk.nodes[0].id);
    try std.testing.expectEqualStrings("PostgreSQL", blk.nodes[0].label);
}

test "resolve class style cascades shape" {
    const src = "@style .db { shape: cylinder }\ndb: \"PostgreSQL\" .db";
    const out = try testResolve(src);
    defer freeAstDoc(out.doc);
    defer freeResolveResult(out.result);
    defer @constCast(&out.err_list).deinit();

    try std.testing.expect(!out.err_list.hasErrors());
    const blk = out.result.blocks[0];
    try std.testing.expectEqual(@as(usize, 1), blk.nodes.len);

    const node = blk.nodes[0];
    try std.testing.expectEqual(ast.Shape.cylinder, node.shape);
}

test "resolve multiple blocks with layout inheritance" {
    const src = "@layout sugiyama\nA -> B\nmodules [force] {\n  X -- Y\n}";
    const out = try testResolve(src);
    defer freeAstDoc(out.doc);
    defer freeResolveResult(out.result);
    defer @constCast(&out.err_list).deinit();

    try std.testing.expect(!out.err_list.hasErrors());
    // 1 default block + 1 named block
    try std.testing.expectEqual(@as(usize, 2), out.result.blocks.len);

    // Default block uses file-level layout (sugiyama → treated as dag since unknown value, stays dag)
    // Named block uses force
    const named = out.result.blocks[1];
    try std.testing.expectEqualStrings("modules", named.name);
    try std.testing.expectEqual(ast.Layout.force, named.config.layout);
}

test "resolve subgraph collects node_ids" {
    const src = "backend: {\n  API -> DB\n}";
    const out = try testResolve(src);
    defer freeAstDoc(out.doc);
    defer freeResolveResult(out.result);
    defer @constCast(&out.err_list).deinit();

    try std.testing.expect(!out.err_list.hasErrors());
    try std.testing.expectEqual(@as(usize, 1), out.result.blocks.len);

    const blk = out.result.blocks[0];
    try std.testing.expectEqual(@as(usize, 1), blk.subgraphs.len);

    const sg = blk.subgraphs[0];
    try std.testing.expectEqualStrings("backend", sg.name);
    try std.testing.expectEqual(@as(usize, 2), sg.node_ids.len);
}

test "resolve card fields produce card shape" {
    const src = "svc: [Auth | Port: 8080]";
    const out = try testResolve(src);
    defer freeAstDoc(out.doc);
    defer freeResolveResult(out.result);
    defer @constCast(&out.err_list).deinit();

    try std.testing.expect(!out.err_list.hasErrors());
    const blk = out.result.blocks[0];
    try std.testing.expectEqual(@as(usize, 1), blk.nodes.len);

    const node = blk.nodes[0];
    try std.testing.expectEqual(ast.Shape.card, node.shape);
    try std.testing.expect(node.card_fields != null);
}
