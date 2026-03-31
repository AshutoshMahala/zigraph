//! Render plan for the terminal renderer.
//!
//! Separates "what to paint" from "how to paint" (compositor in mod.zig).
//! Builds a lightweight plan from LayoutIR that pre-computes:
//! - Y-expansion tables
//! - Transformed element coordinates
//! - Resolved styles and colors
//! - Spatial index for band queries
//! - Label placement via geometric occupancy (no buffer needed)

const std = @import("std");
const Allocator = std.mem.Allocator;
const ir_mod = @import("../../core/ir.zig");
const LayoutIR = ir_mod.LayoutIR(usize);
const LayoutEdge = ir_mod.LayoutEdge(usize);
const LayoutNode = ir_mod.LayoutNode(usize);
const EdgePath = ir_mod.EdgePath(usize);
const config_mod = @import("config.zig");
const Config = config_mod.Config;
const CellColor = config_mod.CellColor;
const TerminalNodeStyle = config_mod.TerminalNodeStyle;
const TerminalSubgraphStyle = config_mod.TerminalSubgraphStyle;
const LineWeight = config_mod.LineWeight;
const MarkerShape = config_mod.MarkerShape;
const NodeStyleContext = config_mod.NodeStyleContext;
const EdgeStyleContext = config_mod.EdgeStyleContext;
const LabelPlacement = config_mod.LabelPlacement;
const TextAttrs = config_mod.TextAttrs;
const resolveColor = config_mod.resolveColor;
const Color = config_mod.Color;
const label_render = @import("labels.zig");
const LegendEntry = label_render.LegendEntry;
const colors = @import("../color/mod.zig");
const shared_helpers = @import("../helpers.zig");

// ── Plan element types ──────────────────────────────────────────────────────

pub const ElementKind = enum(u4) {
    subgraph_box,
    edge,
    dummy_fix,
    label,
    node,
    subgraph_label,
    self_loop,
};

/// Entry in the spatial index. Sorted by y_min for range queries.
pub const PlanElement = struct {
    kind: ElementKind,
    /// Index into the kind-specific array in RenderPlan.
    index: u32,
    y_min: u32,
    y_max: u32,
};

/// Pre-computed edge with transformed coordinates and resolved style.
pub const EdgePlan = struct {
    edge: LayoutEdge,
    color: CellColor,
    style_color: Color,
    weight: LineWeight,
    marker_end: MarkerShape,
    marker_start: MarkerShape,
};

/// Pre-computed node with resolved position and style.
pub const NodePlan = struct {
    node_index: u32,
    node_id: usize,
    x: usize,
    width: usize,
    rendered_y: usize,
    level_height: usize,
    style: TerminalNodeStyle,
};

/// Result of a hit-test query: which element (if any) occupies a cell.
pub const HitResult = union(enum) {
    node: usize, // node id
    edge: usize, // edge index
    subgraph: usize, // subgraph index in subgraph_plans
    none,
};

/// Pre-computed subgraph with transformed position and resolved style.
pub const SubgraphPlan = struct {
    x: usize,
    y: usize,
    w: usize,
    h: usize,
    label: []const u8,
    style: TerminalSubgraphStyle,
};

/// Dummy node fix — fills vertical lines through the level band.
pub const DummyFix = struct {
    center_x: usize,
    rendered_y: usize,
    level_height: usize,
};

/// Pre-computed self-loop indicator.
pub const SelfLoop = struct {
    loop_x: usize,
    label_row: usize,
    color: CellColor,
    label: ?[]const u8,
};

/// Resolved label placement — either placed at a specific position or sent to legend.
pub const LabelPlan = struct {
    placement: union(enum) {
        placed: struct { x: usize, y: usize },
        legend,
    },
    label: []const u8,
    color: CellColor,
    attrs: TextAttrs,
    from_id: usize,
    to_id: usize,
};

// ── RenderPlan ──────────────────────────────────────────────────────────────

pub const RenderPlan = struct {
    /// Rendered width (with self-loop extra width).
    width: usize,
    /// Rendered height (with Y-expansion).
    height: usize,

    // Y-expansion tables (compositor needs these for label Y-transform)
    num_levels: usize,
    level_ir_ys: []usize,
    level_max_height: []usize,
    cumulative_extra: []usize,

    // Per-kind arrays — painted in Z-order by compositor
    edge_plans: []EdgePlan,
    node_plans: []NodePlan,
    subgraph_plans: []SubgraphPlan,
    dummy_fixes: []DummyFix,
    self_loops: []SelfLoop,

    // Label placement results (resolved during plan building)
    label_plans: []LabelPlan,
    legend_entries: []LegendEntry,

    // Spatial index (sorted by y_min)
    elements: []PlanElement,

    arena: std.heap.ArenaAllocator,

    /// Build a render plan from LayoutIR and config.
    /// Pre-computes Y-expansion, element transforms, styles, and spatial index.
    pub fn build(backing_allocator: Allocator, layout_ir: *const LayoutIR, config: Config) !RenderPlan {
        var arena = std.heap.ArenaAllocator.init(backing_allocator);
        errdefer arena.deinit();
        const alloc = arena.allocator();

        const base_width = layout_ir.getWidth();
        const ir_height = layout_ir.getHeight();
        const total_edges = layout_ir.getEdges().len;
        const total_nodes = layout_ir.getNodes().len;

        // ── Y-expansion ─────────────────────────────────────────────────
        var max_level: usize = 0;
        for (layout_ir.getNodes()) |node| {
            if (node.level > max_level) max_level = node.level;
        }
        const num_levels = max_level + 1;

        const level_ir_ys = try alloc.alloc(usize, num_levels);
        const level_max_height = try alloc.alloc(usize, num_levels);
        @memset(level_ir_ys, 0);
        @memset(level_max_height, 1);

        for (layout_ir.getNodes()) |node| {
            level_ir_ys[node.level] = node.y;
            if (node.kind == .dummy) continue;
            const ns = config.node_style_fn(.{
                .node_id = node.id,
                .label = node.label,
                .total_nodes = total_nodes,
                .width = node.width,
                .height = 1,
                .is_implicit = node.kind == .implicit,
                .arena = alloc,
            });
            const h: usize = ns.border.height();
            if (h > level_max_height[node.level]) level_max_height[node.level] = h;
        }

        const cumulative_extra = try alloc.alloc(usize, num_levels + 1);
        cumulative_extra[0] = 0;
        for (0..num_levels) |l| {
            cumulative_extra[l + 1] = cumulative_extra[l] + (level_max_height[l] -| 1);
        }
        const total_extra = cumulative_extra[num_levels];
        const height = ir_height + total_extra;

        // ── Self-loop extra width ───────────────────────────────────────
        var extra_width: usize = 0;
        for (layout_ir.getEdges()) |edge| {
            if (edge.reversed and edge.from_id == edge.to_id) {
                if (layout_ir.nodeById(edge.from_id)) |node| {
                    var needed = node.x + node.width + 1;
                    if (edge.label) |lbl| {
                        needed += lbl.len + 2;
                    }
                    if (needed > base_width + extra_width) {
                        extra_width = needed - base_width;
                    }
                }
            }
        }
        const width = base_width + extra_width;

        // ── Build subgraph plans ────────────────────────────────────────
        const sgs = layout_ir.subgraphs.items;
        var sg_plans = std.ArrayListUnmanaged(SubgraphPlan){};
        if (config.show_subgraphs and sgs.len > 0) {
            const sg_depths = shared_helpers.computeSubgraphDepths(sgs, alloc);
            try sg_plans.ensureTotalCapacity(alloc, sgs.len);
            // Reverse order: parents first (they appear last in the array)
            var idx: usize = sgs.len;
            while (idx > 0) {
                idx -= 1;
                const sg = sgs[idx];
                const sg_style = config.subgraph_style_fn(.{
                    .subgraph_id = sg.id,
                    .parent_id = sg.parent_id,
                    .label = sg.label,
                    .depth = if (idx < sg_depths.len) sg_depths[idx] else 0,
                    .total_subgraphs = sgs.len,
                    .width = sg.width,
                    .height = sg.height,
                    .arena = alloc,
                });
                const new_y = if (total_extra == 0) sg.y else yTransform(sg.y, num_levels, level_ir_ys, cumulative_extra);
                const new_h = if (total_extra == 0) sg.height else blk: {
                    const new_bottom = yTransform(sg.y + sg.height -| 1, num_levels, level_ir_ys, cumulative_extra);
                    break :blk new_bottom - new_y + 1;
                };
                sg_plans.appendAssumeCapacity(.{
                    .x = sg.x,
                    .y = new_y,
                    .w = sg.width,
                    .h = new_h,
                    .label = sg.label,
                    .style = sg_style,
                });
            }
        }

        // ── Build edge plans ────────────────────────────────────────────
        var edge_plans_list = std.ArrayListUnmanaged(EdgePlan){};
        try edge_plans_list.ensureTotalCapacity(alloc, total_edges);

        for (layout_ir.getEdges()) |edge| {
            const from_label = if (layout_ir.nodeById(edge.from_id)) |n| n.label else "";
            const to_label = if (layout_ir.nodeById(edge.to_id)) |n| n.label else "";
            const style = config.edge_style_fn(.{
                .edge_index = edge.edge_index,
                .total_edges = total_edges,
                .from_id = edge.from_id,
                .to_id = edge.to_id,
                .from_label = from_label,
                .to_label = to_label,
                .label = edge.label,
                .directed = edge.directed,
                .reversed = edge.reversed,
                .arena = alloc,
            });
            const edge_color: CellColor = if (style.color != .default)
                resolveColor(style.color)
            else if (config.edge_palette) |palette|
                CellColor.ansi256(colors.getAnsi(palette, edge.edge_index))
            else
                CellColor.none;

            // Preserve the original Color for gradient-aware painting.
            const style_color: Color = if (style.color != .default)
                style.color
            else if (config.edge_palette) |palette|
                Color{ .ansi256 = colors.getAnsi(palette, edge.edge_index) }
            else
                .default;

            const te = if (total_extra == 0)
                edge
            else
                try transformEdge(edge, num_levels, level_ir_ys, cumulative_extra, alloc);

            edge_plans_list.appendAssumeCapacity(.{
                .edge = te,
                .color = edge_color,
                .style_color = style_color,
                .weight = style.weight,
                .marker_end = style.marker_end,
                .marker_start = style.marker_start,
            });
        }

        // ── Optimize h_y for congested rows ─────────────────────────────
        optimizeHorizontalRows(edge_plans_list.items, alloc);

        // ── Build dummy fix list ────────────────────────────────────────
        var dummy_fixes_list = std.ArrayListUnmanaged(DummyFix){};
        if (!config.show_dummy_nodes) {
            for (layout_ir.getNodes()) |node| {
                if (node.kind == .dummy) {
                    try dummy_fixes_list.append(alloc, .{
                        .center_x = node.center_x,
                        .rendered_y = yTransform(node.y, num_levels, level_ir_ys, cumulative_extra),
                        .level_height = level_max_height[node.level],
                    });
                }
            }
        }

        // ── Build node plans ────────────────────────────────────────────
        var node_plans_list = std.ArrayListUnmanaged(NodePlan){};
        try node_plans_list.ensureTotalCapacity(alloc, total_nodes);

        for (layout_ir.getNodes(), 0..) |node, ni| {
            const rendered_y = yTransform(node.y, num_levels, level_ir_ys, cumulative_extra);
            const lh = level_max_height[node.level];
            const node_style = if (node.kind == .dummy)
                TerminalNodeStyle{}
            else
                config.node_style_fn(.{
                    .node_id = node.id,
                    .label = node.label,
                    .total_nodes = total_nodes,
                    .width = node.width,
                    .height = 1,
                    .is_implicit = node.kind == .implicit,
                    .arena = alloc,
                });
            node_plans_list.appendAssumeCapacity(.{
                .node_index = @intCast(ni),
                .node_id = node.id,
                .x = node.x,
                .width = node.width,
                .rendered_y = rendered_y,
                .level_height = lh,
                .style = node_style,
            });
        }

        // ── Build self-loop plans ───────────────────────────────────────
        var self_loops_list = std.ArrayListUnmanaged(SelfLoop){};
        for (layout_ir.getEdges(), 0..) |edge, ei| {
            if (edge.reversed and edge.from_id == edge.to_id) {
                const ep = edge_plans_list.items[ei];
                if (layout_ir.nodeById(edge.from_id)) |node| {
                    const loop_x = node.x + node.width;
                    const loop_y = yTransform(node.y, num_levels, level_ir_ys, cumulative_extra);
                    // Find this node's plan to get its style
                    var ns = TerminalNodeStyle{};
                    for (node_plans_list.items) |np| {
                        if (layout_ir.getNodes()[np.node_index].id == node.id) {
                            ns = np.style;
                            break;
                        }
                    }
                    const label_row = if (ns.border.height() == 3) loop_y + 1 else loop_y;
                    try self_loops_list.append(alloc, .{
                        .loop_x = loop_x,
                        .label_row = label_row,
                        .color = ep.color,
                        .label = edge.label,
                    });
                }
            }
        }

        // ── Resolve label placements (geometric occupancy) ──────────────
        var label_plans_list = std.ArrayListUnmanaged(LabelPlan){};
        var legend_list = std.ArrayListUnmanaged(LegendEntry){};
        {
            // Build occupancy model: per-row sorted interval list.
            // We pre-seed it with known element bounding areas that labels
            // cannot overlap: node rectangles, subgraph border perimeters.
            var occupancy = RowOccupancy.init(alloc, height);

            // Seed from nodes (their rendered rectangles block labels)
            const ir_nodes = layout_ir.getNodes();
            for (node_plans_list.items) |np| {
                const node = ir_nodes[np.node_index];
                if (node.kind == .dummy) continue;
                const nh = np.style.border.height();
                const actual_y = if (nh == 1 and np.level_height > 1)
                    np.rendered_y + np.level_height / 2
                else
                    np.rendered_y;
                var row: usize = actual_y;
                while (row < actual_y + nh) : (row += 1) {
                    try occupancy.addInterval(row, node.x, node.x + node.width);
                }
            }

            // Seed from subgraph border perimeters
            for (sg_plans.items) |sp| {
                if (sp.style.border == .none) continue;
                if (sp.w < 2 or sp.h < 2) continue;
                // Top and bottom horizontal lines
                try occupancy.addInterval(sp.y, sp.x, sp.x + sp.w);
                try occupancy.addInterval(sp.y + sp.h -| 1, sp.x, sp.x + sp.w);
                // Left and right vertical lines (interior rows)
                var row: usize = sp.y + 1;
                const bottom = sp.y + sp.h -| 1;
                while (row < bottom) : (row += 1) {
                    try occupancy.addInterval(row, sp.x, sp.x + 1);
                    try occupancy.addInterval(row, sp.x + sp.w - 1, sp.x + sp.w);
                }
            }

            // Sort labels: longer labels first (harder to fit, need first pick)
            const LabelCandidate = struct {
                edge_index: usize,
                label: []const u8,
                label_color: CellColor,
                label_attrs: TextAttrs,
                placement: LabelPlacement,
                from_id: usize,
                to_id: usize,
            };
            var candidates = std.ArrayListUnmanaged(LabelCandidate){};

            for (layout_ir.getEdges(), 0..) |edge, ei| {
                if (edge.label) |label| {
                    // Skip self-loop labels
                    if (edge.reversed and edge.from_id == edge.to_id) continue;

                    const ep = edge_plans_list.items[ei];

                    // Call edge_label_style_fn
                    const from_label = if (layout_ir.nodeById(edge.from_id)) |n| n.label else "";
                    const to_label = if (layout_ir.nodeById(edge.to_id)) |n| n.label else "";
                    const label_style = config.edge_label_style_fn(.{
                        .edge_index = edge.edge_index,
                        .total_edges = total_edges,
                        .from_id = edge.from_id,
                        .to_id = edge.to_id,
                        .from_label = from_label,
                        .to_label = to_label,
                        .label = edge.label,
                        .directed = edge.directed,
                        .reversed = edge.reversed,
                        .arena = alloc,
                    });

                    // Resolve label color: label style override > edge color
                    const label_color = if (label_style.color != .default)
                        resolveColor(label_style.color)
                    else
                        ep.color;

                    try candidates.append(alloc, .{
                        .edge_index = ei,
                        .label = label,
                        .label_color = label_color,
                        .label_attrs = label_style.attrs,
                        .placement = label_style.placement,
                        .from_id = edge.from_id,
                        .to_id = edge.to_id,
                    });
                }
            }

            // Sort: longer labels first for priority placement
            std.mem.sort(LabelCandidate, candidates.items, {}, struct {
                fn lessThan(_: void, a: LabelCandidate, b: LabelCandidate) bool {
                    return a.label.len > b.label.len;
                }
            }.lessThan);

            // Place each label
            for (candidates.items) |cand| {
                const ep = edge_plans_list.items[cand.edge_index];
                const te = ep.edge;
                const label_w = cand.label.len + 2; // +2 for quotes

                // Compute candidate Y positions based on placement hint
                const primary_y = te.label_y;
                const from_y = te.from_y;
                const to_y = te.to_y;

                const placed = switch (cand.placement) {
                    .auto => tryPlaceLabel(&occupancy, cand.label, te.label_x, primary_y, from_y, to_y, width, label_w),
                    .near_source => blk: {
                        const target_y = if (from_y + 1 < to_y) from_y + 1 else from_y;
                        break :blk tryPlaceLabel(&occupancy, cand.label, te.label_x, target_y, from_y, to_y, width, label_w);
                    },
                    .near_target => blk: {
                        const target_y = if (to_y > 1 and to_y - 1 > from_y) to_y - 1 else to_y;
                        break :blk tryPlaceLabel(&occupancy, cand.label, te.label_x, target_y, from_y, to_y, width, label_w);
                    },
                    .center => blk: {
                        const mid_y = from_y + (to_y -| from_y) / 2;
                        break :blk tryPlaceLabel(&occupancy, cand.label, te.label_x, mid_y, from_y, to_y, width, label_w);
                    },
                };

                if (placed) |pos| {
                    try label_plans_list.append(alloc, .{
                        .placement = .{ .placed = .{ .x = pos.x, .y = pos.y } },
                        .label = cand.label,
                        .color = cand.label_color,
                        .attrs = cand.label_attrs,
                        .from_id = cand.from_id,
                        .to_id = cand.to_id,
                    });
                    try occupancy.addInterval(pos.y, pos.x, pos.x + label_w);
                } else {
                    try label_plans_list.append(alloc, .{
                        .placement = .legend,
                        .label = cand.label,
                        .color = cand.label_color,
                        .attrs = cand.label_attrs,
                        .from_id = cand.from_id,
                        .to_id = cand.to_id,
                    });
                    try legend_list.append(alloc, .{
                        .from_id = cand.from_id,
                        .to_id = cand.to_id,
                        .label = cand.label,
                        .color = cand.label_color,
                    });
                }
            }
        }

        // ── Build spatial index ─────────────────────────────────────────
        const total_elements = sg_plans.items.len * 2 + // box + label
            edge_plans_list.items.len +
            dummy_fixes_list.items.len +
            node_plans_list.items.len +
            self_loops_list.items.len;
        var elements = std.ArrayListUnmanaged(PlanElement){};
        try elements.ensureTotalCapacity(alloc, total_elements);

        for (sg_plans.items, 0..) |sp, i| {
            elements.appendAssumeCapacity(.{
                .kind = .subgraph_box,
                .index = @intCast(i),
                .y_min = @intCast(sp.y),
                .y_max = @intCast(sp.y + sp.h -| 1),
            });
        }
        for (edge_plans_list.items, 0..) |ep, i| {
            const y_min = @min(ep.edge.from_y, ep.edge.to_y);
            const y_max = @max(ep.edge.from_y, ep.edge.to_y);
            elements.appendAssumeCapacity(.{
                .kind = .edge,
                .index = @intCast(i),
                .y_min = @intCast(y_min),
                .y_max = @intCast(y_max),
            });
        }
        for (dummy_fixes_list.items, 0..) |df, i| {
            elements.appendAssumeCapacity(.{
                .kind = .dummy_fix,
                .index = @intCast(i),
                .y_min = @intCast(if (df.rendered_y > 0) df.rendered_y - 1 else 0),
                .y_max = @intCast(df.rendered_y + df.level_height),
            });
        }
        for (node_plans_list.items, 0..) |np, i| {
            const node_h = @max(np.style.border.height(), np.level_height);
            elements.appendAssumeCapacity(.{
                .kind = .node,
                .index = @intCast(i),
                .y_min = @intCast(np.rendered_y),
                .y_max = @intCast(np.rendered_y + node_h -| 1),
            });
        }
        for (sg_plans.items, 0..) |sp, i| {
            elements.appendAssumeCapacity(.{
                .kind = .subgraph_label,
                .index = @intCast(i),
                .y_min = @intCast(sp.y),
                .y_max = @intCast(sp.y + sp.h -| 1),
            });
        }
        for (self_loops_list.items, 0..) |sl, i| {
            elements.appendAssumeCapacity(.{
                .kind = .self_loop,
                .index = @intCast(i),
                .y_min = @intCast(sl.label_row),
                .y_max = @intCast(sl.label_row),
            });
        }

        std.mem.sort(PlanElement, elements.items, {}, struct {
            fn lessThan(_: void, a: PlanElement, b: PlanElement) bool {
                return a.y_min < b.y_min;
            }
        }.lessThan);

        return .{
            .width = width,
            .height = height,
            .num_levels = num_levels,
            .level_ir_ys = level_ir_ys,
            .level_max_height = level_max_height,
            .cumulative_extra = cumulative_extra,
            .edge_plans = edge_plans_list.items,
            .node_plans = node_plans_list.items,
            .subgraph_plans = sg_plans.items,
            .dummy_fixes = dummy_fixes_list.items,
            .self_loops = self_loops_list.items,
            .label_plans = label_plans_list.items,
            .legend_entries = legend_list.items,
            .elements = elements.items,
            .arena = arena,
        };
    }

    pub fn deinit(self: *RenderPlan) void {
        self.arena.deinit();
    }

    /// Number of bands (for future multi-band support; currently 1).
    pub fn bandCount(self: *const RenderPlan) usize {
        _ = self;
        return 1;
    }

    /// Map terminal cell (x, y) to the element at that position.
    /// Checks nodes first (higher Z-order), then edges, then subgraphs.
    pub fn elementAt(self: *const RenderPlan, x: usize, y: usize) HitResult {
        const elems = self.elementsInRange(y, y + 1);

        // First pass: check nodes (highest Z-order for interaction)
        for (elems) |elem| {
            if (elem.kind == .node) {
                const np = self.node_plans[elem.index];
                const node_h = @max(np.style.border.height(), np.level_height);
                const actual_y = if (np.style.border.height() == 1 and np.level_height > 1)
                    np.rendered_y + np.level_height / 2
                else
                    np.rendered_y;
                if (y >= actual_y and y < actual_y + node_h and x >= np.x and x < np.x + np.width) {
                    return .{ .node = np.node_id };
                }
            }
        }

        // Second pass: check edges
        for (elems) |elem| {
            if (elem.kind == .edge) {
                const ep = self.edge_plans[elem.index];
                if (edgeContains(ep.edge, x, y)) {
                    return .{ .edge = ep.edge.edge_index };
                }
            }
        }

        // Third pass: check subgraph boxes
        for (elems) |elem| {
            if (elem.kind == .subgraph_box or elem.kind == .subgraph_label) {
                const sp = self.subgraph_plans[elem.index];
                if (x >= sp.x and x < sp.x + sp.w and y >= sp.y and y < sp.y + sp.h) {
                    return .{ .subgraph = elem.index };
                }
            }
        }

        return .none;
    }

    /// Query elements intersecting Y range [y_start, y_end).
    pub fn elementsInRange(self: *const RenderPlan, y_start: usize, y_end: usize) []const PlanElement {
        if (self.elements.len == 0) return &.{};

        const ys = @as(u32, @intCast(y_start));
        const ye = @as(u32, @intCast(y_end));

        // Binary search: find first element where y_min < y_end
        // Since sorted by y_min, skip elements that start at or after y_end.
        var first: usize = self.elements.len;
        var last: usize = 0;

        for (self.elements, 0..) |elem, i| {
            if (elem.y_min >= ye) break; // all remaining start after range
            if (elem.y_max >= ys) {
                if (first == self.elements.len) first = i;
                last = i + 1;
            }
        }

        if (first >= self.elements.len) return &.{};
        return self.elements[first..last];
    }
};

// ── Edge hit-testing ────────────────────────────────────────────────────────

/// Check if a point lies on an axis-aligned segment (horizontal or vertical).
fn segmentContains(x1: usize, y1: usize, x2: usize, y2: usize, px: usize, py: usize) bool {
    if (x1 == x2) {
        // Vertical segment
        if (px != x1) return false;
        const lo = @min(y1, y2);
        const hi = @max(y1, y2);
        return py >= lo and py <= hi;
    } else if (y1 == y2) {
        // Horizontal segment
        if (py != y1) return false;
        const lo = @min(x1, x2);
        const hi = @max(x1, x2);
        return px >= lo and px <= hi;
    }
    return false;
}

/// Check if a terminal cell (px, py) lies on any segment of an edge's path.
fn edgeContains(edge: LayoutEdge, px: usize, py: usize) bool {
    const from_x = edge.from_x;
    const from_y = edge.from_y;
    const to_x = edge.to_x;
    const to_y = edge.to_y;

    switch (edge.path) {
        .direct => {
            // Vertical line at from_x (== to_x for direct edges)
            if (px != from_x) return false;
            const y_lo = @min(from_y, to_y);
            const y_hi = @max(from_y, to_y);
            return py >= y_lo and py <= y_hi;
        },
        .corner => |c| {
            const h_y = c.horizontal_y;
            // Vertical segment from source to h_y
            if (px == from_x) {
                const y_lo = @min(from_y, h_y);
                const y_hi = @max(from_y, h_y);
                if (py >= y_lo and py <= y_hi) return true;
            }
            // Horizontal segment at h_y
            if (py == h_y) {
                const x_lo = @min(from_x, to_x);
                const x_hi = @max(from_x, to_x);
                if (px >= x_lo and px <= x_hi) return true;
            }
            // Vertical segment from h_y to target
            if (px == to_x) {
                const y_lo = @min(h_y, to_y);
                const y_hi = @max(h_y, to_y);
                if (py >= y_lo and py <= y_hi) return true;
            }
            return false;
        },
        .side_channel => |sc| {
            // Horizontal from source to channel
            if (py == from_y) {
                const x_lo = @min(from_x, sc.channel_x);
                const x_hi = @max(from_x, sc.channel_x);
                if (px >= x_lo and px <= x_hi) return true;
            }
            // Vertical channel
            if (px == sc.channel_x) {
                const y_lo = @min(sc.start_y, sc.end_y);
                const y_hi = @max(sc.start_y, sc.end_y);
                if (py >= y_lo and py <= y_hi) return true;
            }
            // Horizontal from channel to target
            if (py == to_y) {
                const x_lo = @min(sc.channel_x, to_x);
                const x_hi = @max(sc.channel_x, to_x);
                if (px >= x_lo and px <= x_hi) return true;
            }
            return false;
        },
        .multi_segment => |ms| {
            // Check each segment between waypoints
            var prev_x = from_x;
            var prev_y = from_y;
            for (ms.waypoints.items) |wp| {
                if (segmentContains(prev_x, prev_y, wp.x, wp.y, px, py)) return true;
                prev_x = wp.x;
                prev_y = wp.y;
            }
            return segmentContains(prev_x, prev_y, to_x, to_y, px, py);
        },
        .spline => {
            // Approximate: check if point is near the straight line from source to target
            // (splines are rare in terminal rendering; this is a reasonable approximation)
            return segmentContains(from_x, from_y, to_x, to_y, px, py);
        },
    }
}

// ── h_y congestion optimization ─────────────────────────────────────────────

/// Congestion threshold: if more than this many corner edges share the same h_y,
/// the row is considered congested and edges are redistributed.
const CONGESTION_THRESHOLD: usize = 3;

/// Detect congested horizontal rows and redistribute h_y values.
/// Groups corner edges by their h_y. For any h_y with more edges than the
/// threshold, sorts those edges by target_x and redistributes them across the
/// available vertical gap (from_y+1 .. to_y-1) to minimize visual overlap.
///
/// Modifies EdgePlan.edge.path.corner.horizontal_y in-place (plan copies, not IR).
fn optimizeHorizontalRows(edge_plans: []EdgePlan, alloc: Allocator) void {
    if (edge_plans.len < CONGESTION_THRESHOLD) return;

    // Group edge indices by h_y
    const HyGroup = struct {
        indices: std.ArrayListUnmanaged(usize),
    };
    var groups = std.AutoHashMapUnmanaged(usize, HyGroup){};
    defer {
        var git = groups.iterator();
        while (git.next()) |entry| {
            entry.value_ptr.indices.deinit(alloc);
        }
        groups.deinit(alloc);
    }

    for (edge_plans, 0..) |ep, i| {
        switch (ep.edge.path) {
            .corner => |c| {
                const entry = groups.getOrPut(alloc, c.horizontal_y) catch continue;
                if (!entry.found_existing) {
                    entry.value_ptr.* = .{ .indices = .{} };
                }
                entry.value_ptr.indices.append(alloc, i) catch continue;
            },
            else => {},
        }
    }

    // Process congested groups
    var it = groups.iterator();
    while (it.next()) |entry| {
        const group = entry.value_ptr;
        if (group.indices.items.len <= CONGESTION_THRESHOLD) continue;

        const indices = group.indices.items;

        // Sort edges by target_x so spatially-nearby targets cluster together
        std.mem.sort(usize, indices, edge_plans, struct {
            fn lessThan(eps: []EdgePlan, a: usize, b: usize) bool {
                return eps[a].edge.to_x < eps[b].edge.to_x;
            }
        }.lessThan);

        // Determine available gap rows for this group.
        // Use the union of all edges' from_y..to_y ranges.
        var min_from: usize = std.math.maxInt(usize);
        var max_to: usize = 0;
        for (indices) |idx| {
            const e = &edge_plans[idx].edge;
            if (e.from_y < min_from) min_from = e.from_y;
            if (e.to_y > max_to) max_to = e.to_y;
        }

        // Available rows: from_y+1 .. to_y-1
        const gap_start = min_from + 1;
        const gap_end = if (max_to > 0) max_to else gap_start;
        if (gap_end <= gap_start) continue;

        const available = gap_end - gap_start;
        const count = indices.len;

        // Distribute edges evenly across available rows
        for (indices, 0..) |idx, slot| {
            const new_h_y = gap_start + (slot * available) / count;
            // Clamp to valid range
            const clamped = @min(new_h_y, gap_end - 1);
            // Must still be within this edge's own from_y..to_y span
            const e = &edge_plans[idx].edge;
            const edge_min = e.from_y + 1;
            const edge_max = if (e.to_y > 0) e.to_y - 1 else e.from_y + 1;
            const final_h_y = @max(edge_min, @min(clamped, edge_max));
            e.path.corner.horizontal_y = final_h_y;
        }
    }
}

// ── Geometric occupancy model ───────────────────────────────────────────────

const Interval = struct { x_min: usize, x_max: usize };

/// Per-row interval occupancy tracker for label collision detection.
/// Tracks occupied X-ranges per Y-row. Uses a flat list per row (small N
/// per row in practice — typically <10 elements per row).
const RowOccupancy = struct {
    /// rows[y] is a list of occupied X-intervals on row y.
    rows: []std.ArrayListUnmanaged(Interval),
    alloc: Allocator,
    height: usize,

    fn init(allocator: Allocator, h: usize) RowOccupancy {
        const rows = allocator.alloc(std.ArrayListUnmanaged(Interval), h) catch
            return .{ .rows = &.{}, .alloc = allocator, .height = 0 };
        @memset(rows, std.ArrayListUnmanaged(Interval){});
        return .{ .rows = rows, .alloc = allocator, .height = h };
    }

    fn addInterval(self: *RowOccupancy, y: usize, x_min: usize, x_max: usize) !void {
        if (y >= self.height) return;
        try self.rows[y].append(self.alloc, .{ .x_min = x_min, .x_max = x_max });
    }

    fn isFree(self: *const RowOccupancy, y: usize, x_min: usize, x_max: usize) bool {
        if (y >= self.height) return false;
        for (self.rows[y].items) |iv| {
            // Overlap if intervals are not disjoint
            if (x_min < iv.x_max and x_max > iv.x_min) return false;
        }
        return true;
    }
};

/// Try to place a label, returning the resolved (x, y) or null if legend.
/// Attempts: primary position → vertical sliding → horizontal sliding → null.
fn tryPlaceLabel(
    occupancy: *RowOccupancy,
    label: []const u8,
    base_x: usize,
    primary_y: usize,
    from_y: usize,
    to_y: usize,
    buf_width: usize,
    label_w: usize,
) ?struct { x: usize, y: usize } {
    _ = label;

    // Bounds check
    if (base_x + label_w > buf_width) {
        // Try clamped X
        if (label_w > buf_width) return null;
        const clamped_x = buf_width - label_w;
        if (occupancy.isFree(primary_y, clamped_x, clamped_x + label_w))
            return .{ .x = clamped_x, .y = primary_y };
    } else {
        // Try primary position
        if (occupancy.isFree(primary_y, base_x, base_x + label_w))
            return .{ .x = base_x, .y = primary_y };
    }

    // Vertical sliding within edge span
    const min_y = if (from_y + 1 < to_y) from_y + 1 else from_y;
    const max_y = if (to_y > 1) to_y - 1 else to_y;
    const x_end = @min(base_x + label_w, buf_width);
    if (x_end < base_x + label_w) {
        // Label doesn't fit at base_x — skip vertical sliding at this X
    } else {
        var try_y = min_y;
        while (try_y <= max_y) : (try_y += 1) {
            if (try_y == primary_y) continue;
            if (occupancy.isFree(try_y, base_x, base_x + label_w))
                return .{ .x = base_x, .y = try_y };
        }
    }

    // Horizontal sliding: try shifting X ± 1..3 at primary_y and slide rows
    const max_shift: usize = 3;
    var shift: usize = 1;
    while (shift <= max_shift) : (shift += 1) {
        // Try right shift
        const rx = base_x + shift;
        if (rx + label_w <= buf_width) {
            if (occupancy.isFree(primary_y, rx, rx + label_w))
                return .{ .x = rx, .y = primary_y };
            // Also try vertical slide at shifted X
            var sy = min_y;
            while (sy <= max_y) : (sy += 1) {
                if (sy == primary_y) continue;
                if (occupancy.isFree(sy, rx, rx + label_w))
                    return .{ .x = rx, .y = sy };
            }
        }
        // Try left shift
        if (base_x >= shift) {
            const lx = base_x - shift;
            if (lx + label_w <= buf_width) {
                if (occupancy.isFree(primary_y, lx, lx + label_w))
                    return .{ .x = lx, .y = primary_y };
                var sy = min_y;
                while (sy <= max_y) : (sy += 1) {
                    if (sy == primary_y) continue;
                    if (occupancy.isFree(sy, lx, lx + label_w))
                        return .{ .x = lx, .y = sy };
                }
            }
        }
    }

    return null;
}

// ── Y-expansion helpers ─────────────────────────────────────────────────────

fn yTransform(ir_y: usize, num_levels: usize, level_ir_ys: []const usize, cumulative_extra: []const usize) usize {
    var l: usize = 0;
    while (l < num_levels and level_ir_ys[l] <= ir_y) : (l += 1) {}
    if (l == 0) return ir_y;
    l -= 1;
    if (ir_y == level_ir_ys[l]) {
        return ir_y + cumulative_extra[l];
    } else {
        return ir_y + cumulative_extra[l + 1];
    }
}

fn transformEdge(edge: LayoutEdge, num_levels: usize, level_ir_ys: []const usize, cumulative_extra: []const usize, arena_alloc: Allocator) !LayoutEdge {
    var e = edge;
    e.from_y = yTransform(edge.from_y, num_levels, level_ir_ys, cumulative_extra);
    e.to_y = yTransform(edge.to_y, num_levels, level_ir_ys, cumulative_extra);
    e.label_y = yTransform(edge.label_y, num_levels, level_ir_ys, cumulative_extra);
    switch (e.path) {
        .direct => {},
        .corner => |*c| {
            c.horizontal_y = yTransform(c.horizontal_y, num_levels, level_ir_ys, cumulative_extra);
        },
        .side_channel => |*sc| {
            sc.start_y = yTransform(sc.start_y, num_levels, level_ir_ys, cumulative_extra);
            sc.end_y = yTransform(sc.end_y, num_levels, level_ir_ys, cumulative_extra);
        },
        .multi_segment => |ms| {
            const wp = try arena_alloc.alloc(EdgePath.Waypoint, ms.waypoints.items.len);
            for (ms.waypoints.items, 0..) |pt, i| {
                wp[i] = .{ .x = pt.x, .y = yTransform(pt.y, num_levels, level_ir_ys, cumulative_extra) };
            }
            e.path = .{ .multi_segment = .{
                .waypoints = .{ .items = wp, .capacity = wp.len },
                .allocator = ms.allocator,
            } };
        },
        .spline => |*sp| {
            sp.cp1_y = yTransform(sp.cp1_y, num_levels, level_ir_ys, cumulative_extra);
            sp.cp2_y = yTransform(sp.cp2_y, num_levels, level_ir_ys, cumulative_extra);
        },
    }
    return e;
}

// ── Tests ───────────────────────────────────────────────────────────────────

test "optimizeHorizontalRows: no-op below threshold" {
    // 2 edges sharing h_y = 3 — below threshold (3), no changes
    var plans = [_]EdgePlan{
        makeTestEdgePlan(0, 10, 0, 10, 3),
        makeTestEdgePlan(0, 20, 0, 10, 3),
    };
    optimizeHorizontalRows(&plans, std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 3), plans[0].edge.path.corner.horizontal_y);
    try std.testing.expectEqual(@as(usize, 3), plans[1].edge.path.corner.horizontal_y);
}

test "optimizeHorizontalRows: redistributes congested rows" {
    // 5 edges all with h_y = 2, from_y = 0, to_y = 10. Gap = rows 1..9.
    // After optimization they should be spread across the gap.
    var plans = [_]EdgePlan{
        makeTestEdgePlan(0, 5, 0, 10, 2),
        makeTestEdgePlan(0, 15, 0, 10, 2),
        makeTestEdgePlan(0, 25, 0, 10, 2),
        makeTestEdgePlan(0, 35, 0, 10, 2),
        makeTestEdgePlan(0, 45, 0, 10, 2),
    };
    optimizeHorizontalRows(&plans, std.testing.allocator);

    // All h_y values should be in range [1, 9]
    for (plans) |p| {
        const h_y = p.edge.path.corner.horizontal_y;
        try std.testing.expect(h_y >= 1 and h_y <= 9);
    }

    // Should be sorted by target_x (ascending), so h_y should be non-decreasing
    // since they're distributed evenly
    var prev_hy: usize = 0;
    for (plans) |p| {
        const h_y = p.edge.path.corner.horizontal_y;
        try std.testing.expect(h_y >= prev_hy);
        prev_hy = h_y;
    }
}

test "optimizeHorizontalRows: direct edges unaffected" {
    // Mix of corner and direct edges — direct should be untouched
    var plans = [_]EdgePlan{
        makeTestEdgePlan(0, 10, 0, 10, 2),
        makeTestDirectEdgePlan(0, 10, 0, 10),
        makeTestEdgePlan(0, 20, 0, 10, 2),
        makeTestEdgePlan(0, 30, 0, 10, 2),
        makeTestEdgePlan(0, 40, 0, 10, 2),
    };
    optimizeHorizontalRows(&plans, std.testing.allocator);
    try std.testing.expect(plans[1].edge.path == .direct);
}

/// Helper: create a test EdgePlan with a corner path.
fn makeTestEdgePlan(from_x: usize, to_x: usize, from_y: usize, to_y: usize, h_y: usize) EdgePlan {
    return .{
        .edge = .{
            .from_id = 0,
            .to_id = 1,
            .from_x = from_x,
            .from_y = from_y,
            .to_x = to_x,
            .to_y = to_y,
            .path = .{ .corner = .{ .horizontal_y = h_y } },
            .edge_index = 0,
        },
        .color = CellColor.none,
        .style_color = .default,
        .weight = .light,
        .marker_end = .arrow,
        .marker_start = .none,
    };
}

/// Helper: create a test EdgePlan with a direct path.
fn makeTestDirectEdgePlan(from_x: usize, to_x: usize, from_y: usize, to_y: usize) EdgePlan {
    _ = to_x;
    return .{
        .edge = .{
            .from_id = 0,
            .to_id = 1,
            .from_x = from_x,
            .from_y = from_y,
            .to_x = from_x,
            .to_y = to_y,
            .path = .{ .direct = {} },
            .edge_index = 0,
        },
        .color = CellColor.none,
        .style_color = .default,
        .weight = .light,
        .marker_end = .arrow,
        .marker_start = .none,
    };
}

// ── edgeContains tests ──────────────────────────────────────────────────────

test "edgeContains: direct edge vertical" {
    const edge: LayoutEdge = .{
        .from_id = 0,
        .to_id = 1,
        .from_x = 5,
        .from_y = 2,
        .to_x = 5,
        .to_y = 8,
        .path = .{ .direct = {} },
        .edge_index = 0,
    };
    // On the vertical line
    try std.testing.expect(edgeContains(edge, 5, 2));
    try std.testing.expect(edgeContains(edge, 5, 5));
    try std.testing.expect(edgeContains(edge, 5, 8));
    // Off the line
    try std.testing.expect(!edgeContains(edge, 4, 5));
    try std.testing.expect(!edgeContains(edge, 6, 5));
    try std.testing.expect(!edgeContains(edge, 5, 1));
    try std.testing.expect(!edgeContains(edge, 5, 9));
}

test "edgeContains: corner edge L-shape" {
    const edge: LayoutEdge = .{
        .from_id = 0,
        .to_id = 1,
        .from_x = 3,
        .from_y = 0,
        .to_x = 10,
        .to_y = 6,
        .path = .{ .corner = .{ .horizontal_y = 3 } },
        .edge_index = 0,
    };
    // Vertical from source down to h_y
    try std.testing.expect(edgeContains(edge, 3, 0));
    try std.testing.expect(edgeContains(edge, 3, 2));
    try std.testing.expect(edgeContains(edge, 3, 3));
    // Horizontal at h_y
    try std.testing.expect(edgeContains(edge, 5, 3));
    try std.testing.expect(edgeContains(edge, 10, 3));
    // Vertical from h_y to target
    try std.testing.expect(edgeContains(edge, 10, 4));
    try std.testing.expect(edgeContains(edge, 10, 6));
    // Off path
    try std.testing.expect(!edgeContains(edge, 7, 5));
    try std.testing.expect(!edgeContains(edge, 3, 5));
    try std.testing.expect(!edgeContains(edge, 10, 0));
}

test "edgeContains: side channel" {
    const edge: LayoutEdge = .{
        .from_id = 0,
        .to_id = 1,
        .from_x = 4,
        .from_y = 2,
        .to_x = 8,
        .to_y = 10,
        .path = .{ .side_channel = .{ .channel_x = 0, .start_y = 2, .end_y = 10 } },
        .edge_index = 0,
    };
    // Horizontal from source to channel
    try std.testing.expect(edgeContains(edge, 2, 2));
    try std.testing.expect(edgeContains(edge, 0, 2));
    // Vertical channel
    try std.testing.expect(edgeContains(edge, 0, 5));
    try std.testing.expect(edgeContains(edge, 0, 10));
    // Horizontal from channel to target
    try std.testing.expect(edgeContains(edge, 4, 10));
    try std.testing.expect(edgeContains(edge, 8, 10));
    // Off path
    try std.testing.expect(!edgeContains(edge, 5, 5));
}

// ── elementAt tests ─────────────────────────────────────────────────────────

test "elementAt: node hit" {
    // Build a minimal RenderPlan with one node
    var elements = [_]PlanElement{
        .{ .kind = .node, .index = 0, .y_min = 2, .y_max = 2 },
    };
    var node_plans = [_]NodePlan{
        .{
            .node_index = 0,
            .node_id = 42,
            .x = 5,
            .width = 7,
            .rendered_y = 2,
            .level_height = 1,
            .style = .{},
        },
    };
    const plan = RenderPlan{
        .width = 20,
        .height = 10,
        .num_levels = 1,
        .level_ir_ys = &.{},
        .level_max_height = &.{},
        .cumulative_extra = &.{},
        .edge_plans = &.{},
        .node_plans = &node_plans,
        .subgraph_plans = &.{},
        .dummy_fixes = &.{},
        .self_loops = &.{},
        .label_plans = &.{},
        .legend_entries = &.{},
        .elements = &elements,
        .arena = undefined,
    };
    // Inside node
    try std.testing.expectEqual(HitResult{ .node = 42 }, plan.elementAt(5, 2));
    try std.testing.expectEqual(HitResult{ .node = 42 }, plan.elementAt(11, 2));
    // Outside node (left)
    try std.testing.expectEqual(HitResult.none, plan.elementAt(4, 2));
    // Outside node (right)
    try std.testing.expectEqual(HitResult.none, plan.elementAt(12, 2));
    // Wrong row
    try std.testing.expectEqual(HitResult.none, plan.elementAt(5, 3));
}

test "elementAt: edge hit" {
    var elements = [_]PlanElement{
        .{ .kind = .edge, .index = 0, .y_min = 0, .y_max = 6 },
    };
    var edge_plans = [_]EdgePlan{
        .{
            .edge = .{
                .from_id = 0,
                .to_id = 1,
                .from_x = 5,
                .from_y = 0,
                .to_x = 5,
                .to_y = 6,
                .path = .{ .direct = {} },
                .edge_index = 3,
            },
            .color = CellColor.none,
            .style_color = .default,
            .weight = .light,
            .marker_end = .arrow,
            .marker_start = .none,
        },
    };
    const plan = RenderPlan{
        .width = 20,
        .height = 10,
        .num_levels = 1,
        .level_ir_ys = &.{},
        .level_max_height = &.{},
        .cumulative_extra = &.{},
        .edge_plans = &edge_plans,
        .node_plans = &.{},
        .subgraph_plans = &.{},
        .dummy_fixes = &.{},
        .self_loops = &.{},
        .label_plans = &.{},
        .legend_entries = &.{},
        .elements = &elements,
        .arena = undefined,
    };
    try std.testing.expectEqual(HitResult{ .edge = 3 }, plan.elementAt(5, 3));
    try std.testing.expectEqual(HitResult.none, plan.elementAt(4, 3));
}

test "elementAt: node takes priority over edge" {
    var elements = [_]PlanElement{
        .{ .kind = .edge, .index = 0, .y_min = 0, .y_max = 6 },
        .{ .kind = .node, .index = 0, .y_min = 3, .y_max = 3 },
    };
    var edge_plans = [_]EdgePlan{
        .{
            .edge = .{
                .from_id = 0,
                .to_id = 1,
                .from_x = 5,
                .from_y = 0,
                .to_x = 5,
                .to_y = 6,
                .path = .{ .direct = {} },
                .edge_index = 0,
            },
            .color = CellColor.none,
            .style_color = .default,
            .weight = .light,
            .marker_end = .arrow,
            .marker_start = .none,
        },
    };
    var node_plans = [_]NodePlan{
        .{
            .node_index = 0,
            .node_id = 10,
            .x = 3,
            .width = 5,
            .rendered_y = 3,
            .level_height = 1,
            .style = .{},
        },
    };
    const plan = RenderPlan{
        .width = 20,
        .height = 10,
        .num_levels = 1,
        .level_ir_ys = &.{},
        .level_max_height = &.{},
        .cumulative_extra = &.{},
        .edge_plans = &edge_plans,
        .node_plans = &node_plans,
        .subgraph_plans = &.{},
        .dummy_fixes = &.{},
        .self_loops = &.{},
        .label_plans = &.{},
        .legend_entries = &.{},
        .elements = &elements,
        .arena = undefined,
    };
    // At (5,3), both node and edge overlap. Node should win.
    try std.testing.expectEqual(HitResult{ .node = 10 }, plan.elementAt(5, 3));
    // At (5,1), only edge
    try std.testing.expectEqual(HitResult{ .edge = 0 }, plan.elementAt(5, 1));
}
