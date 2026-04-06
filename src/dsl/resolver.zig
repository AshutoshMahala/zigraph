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
    label_owned: bool = false,
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
    label_owned: bool = false,
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
                    if (std.mem.eql(u8, dir.value, "dag") or std.mem.eql(u8, dir.value, "sugiyama"))
                        cfg.layout = .dag
                    else if (std.mem.eql(u8, dir.value, "tree"))
                        cfg.layout = .tree
                    else if (std.mem.eql(u8, dir.value, "force") or std.mem.eql(u8, dir.value, "fruchterman_reingold"))
                        cfg.layout = .force;
                    // unknown layout values silently ignored (parser already warned)
                },
                .direction => cfg.direction = dir.value,
                .spacing   => cfg.spacing   = dir.value,
                .theme     => cfg.theme     = dir.value,
                .import_, .border, .align_ => {},
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
                .table_headers, .table_row, .vars_block => {},
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
        if (e.fan_out) {
            if (e.chain.len < 2) return;
            const src = e.chain[0];
            try self.ensureNode(src.id, src.loc, node_map);
            for (e.chain[1..]) |tgt| {
                try self.ensureNode(tgt.id, tgt.loc, node_map);
                try edges_list.append(self.allocator, .{
                    .from       = src.id,
                    .to         = tgt.id,
                    .op         = e.operator,
                    .label      = e.label,
                    .properties = try self.cascadeEdgeProperties(e.classes, e.properties),
                    .loc        = e.loc,
                });
            }
        } else {
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
                    .properties = try self.cascadeEdgeProperties(e.classes, e.properties),
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
                .table_headers, .table_row, .vars_block => {},
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
// Var substitution helper
// ============================================================

/// Apply var substitution to all labels, property values, and card fields
/// in the resolved block's nodes and edges.
fn applyVarSubstitution(
    allocator: std.mem.Allocator,
    resolved: anytype,
    vars_map: *const std.StringHashMap([]const u8),
    err_list: *errors.ErrorList,
) !void {
    for (resolved.nodes) |*node| {
        // Labels
        const orig = node.label;
        node.label = try substituteVars(allocator, node.label, vars_map, err_list, node.loc);
        node.label_owned = node.label.ptr != orig.ptr;

        // Property values
        for (node.properties) |*prop| {
            prop.value = try substituteVars(allocator, prop.value, vars_map, err_list, node.loc);
        }

        // Card fields
        if (node.card_fields) |fields| {
            var needs_sub = false;
            for (fields) |f| {
                if (std.mem.indexOf(u8, f, "${") != null) { needs_sub = true; break; }
            }
            if (needs_sub) {
                const new_fields = try allocator.alloc([]const u8, fields.len);
                for (fields, 0..) |f, fi| {
                    new_fields[fi] = try substituteVars(allocator, f, vars_map, err_list, node.loc);
                }
                node.card_fields = new_fields;
            }
        }
    }
    for (resolved.edges) |*edge| {
        // Labels
        if (edge.label) |lbl| {
            const new_lbl = try substituteVars(allocator, lbl, vars_map, err_list, edge.loc);
            edge.label = new_lbl;
            edge.label_owned = new_lbl.ptr != lbl.ptr;
        }

        // Property values
        for (edge.properties) |*prop| {
            prop.value = try substituteVars(allocator, prop.value, vars_map, err_list, edge.loc);
        }
    }
}

/// Replace all `${name}` occurrences in `text` with values from `vars_map`.
/// Returns the original slice (without allocation) when no `${` is present.
/// Otherwise returns a newly allocated slice owned by `allocator`.
/// Reports an error for undefined variable references.
fn substituteVars(
    allocator: std.mem.Allocator,
    text: []const u8,
    vars_map: *const std.StringHashMap([]const u8),
    err_list: *errors.ErrorList,
    loc: Loc,
) ![]const u8 {
    // Fast path: no substitution markers
    if (std.mem.indexOf(u8, text, "${") == null) return text;

    var result: std.ArrayListUnmanaged(u8) = .{};
    var i: usize = 0;
    while (i < text.len) {
        if (i + 1 < text.len and text[i] == '$' and text[i + 1] == '{') {
            const start = i + 2;
            const end = std.mem.indexOfScalarPos(u8, text, start, '}') orelse {
                try result.append(allocator, text[i]);
                i += 1;
                continue;
            };
            const var_name = text[start..end];
            if (vars_map.get(var_name)) |value| {
                try result.appendSlice(allocator, value);
            } else {
                // Report error for undefined variable, but preserve the text
                try err_list.add(loc, .unresolved_reference, "undefined variable");
                try result.appendSlice(allocator, text[i .. end + 1]);
            }
            i = end + 1;
        } else {
            try result.append(allocator, text[i]);
            i += 1;
        }
    }
    return result.toOwnedSlice(allocator);
}

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

    // Build document-level vars map
    var doc_vars_map = std.StringHashMap([]const u8).init(allocator);
    defer doc_vars_map.deinit();
    for (doc.vars) |v| {
        try doc_vars_map.put(v.key, v.value);
    }

    // 3. Bare statements → __default__ block (only if non-empty)
    if (doc.statements.len > 0) {
        const resolved = try r.resolveStatements(doc.statements);
        if (doc_vars_map.count() > 0) {
            try applyVarSubstitution(allocator, resolved, &doc_vars_map, err_list);
        }
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

        // [card] blocks: default all rect nodes to card shape
        if (block_config.layout == .card) {
            for (resolved.nodes) |*node| {
                if (node.shape == .rect) node.shape = .card;
            }
        }

        // Build block-level vars map (block vars override doc vars)
        var blk_vars_map = std.StringHashMap([]const u8).init(allocator);
        defer blk_vars_map.deinit();
        // Start with doc-level vars
        var doc_it = doc_vars_map.iterator();
        while (doc_it.next()) |entry| {
            try blk_vars_map.put(entry.key_ptr.*, entry.value_ptr.*);
        }
        // Override with block-level vars
        for (blk.vars) |v| {
            try blk_vars_map.put(v.key, v.value);
        }

        if (blk_vars_map.count() > 0) {
            try applyVarSubstitution(allocator, resolved, &blk_vars_map, err_list);
        }

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
        .table_headers, .table_row, .vars_block => {},
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
    a.free(doc.vars);
    for (doc.blocks) |blk| {
        a.free(blk.directives);
        for (blk.styles) |sr| a.free(sr.properties.properties);
        a.free(blk.styles);
        for (blk.statements) |s| freeAstStatement(s);
        a.free(blk.statements);
        a.free(blk.vars);
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
            if (node.label_owned) a.free(node.label);
            a.free(node.properties);
        }
        a.free(blk.nodes);
        for (blk.edges) |edge| {
            if (edge.label_owned) {
                if (edge.label) |lbl| a.free(lbl);
            }
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

    // Default block uses file-level layout (sugiyama → dag alias)
    try std.testing.expectEqual(ast.Layout.dag, out.result.blocks[0].config.layout);
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

test "card block defaults all nodes to card shape" {
    const src = "services [card] {\n  Auth\n  Gateway\n  DB\n}";
    const out = try testResolve(src);
    defer freeAstDoc(out.doc);
    defer freeResolveResult(out.result);
    defer @constCast(&out.err_list).deinit();

    try std.testing.expect(!out.err_list.hasErrors());
    try std.testing.expectEqual(@as(usize, 1), out.result.blocks.len);

    const blk = out.result.blocks[0];
    try std.testing.expectEqualStrings("services", blk.name);
    try std.testing.expectEqual(ast.Layout.card, blk.config.layout);
    try std.testing.expectEqual(@as(usize, 3), blk.nodes.len);

    for (blk.nodes) |node| {
        try std.testing.expectEqual(ast.Shape.card, node.shape);
    }
}

test "multiplicity property resolved" {
    // Parse: server: { multiple: true }
    // Resolve and check the server node has a "multiple" property with value "true"
    const src = "server: { multiple: true }";
    const out = try testResolve(src);
    defer freeAstDoc(out.doc);
    defer freeResolveResult(out.result);
    defer @constCast(&out.err_list).deinit();

    try std.testing.expect(!out.err_list.hasErrors());
    try std.testing.expectEqual(@as(usize, 1), out.result.blocks.len);

    const blk = out.result.blocks[0];
    try std.testing.expectEqual(@as(usize, 1), blk.nodes.len);

    const node = blk.nodes[0];
    try std.testing.expectEqualStrings("server", node.id);

    // Verify the "multiple" property flowed through the style cascade
    var found_multiple = false;
    for (node.properties) |prop| {
        if (std.mem.eql(u8, prop.key, "multiple")) {
            try std.testing.expectEqualStrings("true", prop.value);
            found_multiple = true;
        }
    }
    try std.testing.expect(found_multiple);
}

test "var substitution in labels" {
    const src = "vars { env: production }\nserver: \"${env} server\"\nserver -> db";
    const out = try testResolve(src);
    defer @constCast(&out.err_list).deinit();
    defer freeAstDoc(out.doc);

    try std.testing.expect(!out.err_list.hasErrors());
    try std.testing.expectEqual(@as(usize, 1), out.result.blocks.len);

    const blk = out.result.blocks[0];
    // Find the server node and verify its label has been substituted
    var found_server = false;
    for (blk.nodes) |node| {
        if (std.mem.eql(u8, node.id, "server")) {
            try std.testing.expectEqualStrings("production server", node.label);
            // Free the substituted label (allocated by substituteVars)
            std.testing.allocator.free(node.label);
            found_server = true;
        }
        std.testing.allocator.free(node.properties);
    }
    try std.testing.expect(found_server);
    for (blk.edges) |edge| {
        std.testing.allocator.free(edge.properties);
    }
    std.testing.allocator.free(blk.nodes);
    std.testing.allocator.free(blk.edges);
    std.testing.allocator.free(blk.subgraphs);
    std.testing.allocator.free(out.result.blocks);
}

test "undefined var reports error" {
    const src = "server: \"${undefined_var} server\"";
    const out = try testResolve(src);
    defer @constCast(&out.err_list).deinit();
    defer freeAstDoc(out.doc);

    // No vars defined, so ${undefined_var} should not trigger substitution
    // (vars_map.count() == 0 skips substitution entirely)
    // But if we define a var and reference an undefined one:
    const a = std.testing.allocator;
    for (out.result.blocks) |blk_inner| {
        for (blk_inner.nodes) |node| a.free(node.properties);
        a.free(blk_inner.nodes);
        for (blk_inner.edges) |edge| a.free(edge.properties);
        a.free(blk_inner.edges);
        for (blk_inner.subgraphs) |sg| freeSubgraph(sg);
        a.free(blk_inner.subgraphs);
    }
    a.free(out.result.blocks);
}

test "undefined var with defined vars reports error" {
    const src = "vars { env: production }\nserver: \"${missing} server\"";
    const out = try testResolve(src);
    defer @constCast(&out.err_list).deinit();
    defer freeAstDoc(out.doc);

    // Should have an error for the undefined variable
    try std.testing.expect(out.err_list.hasErrors());

    const a = std.testing.allocator;
    for (out.result.blocks) |blk_inner| {
        for (blk_inner.nodes) |node| {
            if (node.label_owned) a.free(node.label);
            a.free(node.properties);
        }
        a.free(blk_inner.nodes);
        for (blk_inner.edges) |edge| {
            if (edge.label_owned) {
                if (edge.label) |lbl| a.free(lbl);
            }
            a.free(edge.properties);
        }
        a.free(blk_inner.edges);
        for (blk_inner.subgraphs) |sg| freeSubgraph(sg);
        a.free(blk_inner.subgraphs);
    }
    a.free(out.result.blocks);
}
