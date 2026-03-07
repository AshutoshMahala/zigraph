//! SVG Renderer for zigraph
//!
//! Renders LayoutIR to Scalable Vector Graphics (SVG) format.
//! Essential for:
//! - Visualizing bezier curves and spline control points
//! - High-quality output for documentation
//! - Browser-based visualization
//! - Debugging edge routing algorithms
//!
//! ## Module structure
//!
//! ```text
//! svg/
//!   mod.zig          ← this file: render() entry point + re-exports
//!   config.zig       ← SvgConfig, style types, presets
//!   defs.zig         ← marker definitions (<defs> helpers)
//!   helpers.zig      ← findNodeLabel, computeSubgraphDepths, xmlEscape, writeXmlEscaped
//!   nodes.zig        ← renderNode, renderDummyNode
//!   edges.zig        ← renderEdge, renderSelfLoop, renderBezierEdge
//!   splines.zig      ← renderStitchedEdges, renderSplinePath
//!   subgraphs.zig    ← renderSubgraphs
//!   render_tests.zig ← integration tests
//! ```
//!
//! ## Usage
//!
//! ```zig
//! var ir = try zigraph.layout(&graph, allocator, .{});
//! defer ir.deinit();
//!
//! const svg = try zigraph.svg.render(&ir, allocator, .{});
//! defer allocator.free(svg);
//!
//! // Write to file
//! try std.fs.cwd().writeFile("graph.svg", svg);
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;
const ir_mod = @import("../../core/ir.zig");
const LayoutIR = ir_mod.LayoutIR(usize);

// ── Submodule imports ───────────────────────────────────────────────────────

const config_mod = @import("config.zig");
const node_render = @import("nodes.zig");
const edge_render = @import("edges.zig");
const spline_render = @import("splines.zig");
const subgraph_render = @import("subgraphs.zig");
const defs_mod = @import("defs.zig");
const helpers_mod = @import("helpers.zig");
const types = @import("../types.zig");

// ── Public re-exports ───────────────────────────────────────────────────────

pub const SvgConfig = config_mod.SvgConfig;
pub const EdgeStyle = config_mod.EdgeStyle;
pub const EdgeStyleContext = config_mod.EdgeStyleContext;
pub const NodeStyle = config_mod.NodeStyle;
pub const NodeStyleContext = config_mod.NodeStyleContext;
pub const SubgraphStyle = config_mod.SubgraphStyle;
pub const SubgraphStyleContext = config_mod.SubgraphStyleContext;
pub const EdgeLabelStyle = config_mod.EdgeLabelStyle;
pub const shapes = config_mod.shapes;
pub const subgraph_presets = config_mod.subgraph_presets;
pub const defaultEdgeLabelStyle = config_mod.defaultEdgeLabelStyle;
pub const MarkerShape = types.MarkerShape;
pub const ResolvedEdgeStyle = config_mod.ResolvedEdgeStyle;
pub const defaultEdgeStyle = config_mod.defaultEdgeStyle;
pub const monoEdgeStyle = config_mod.monoEdgeStyle;
pub const renderBezierEdge = edge_render.renderBezierEdge;

const MarkerDef = defs_mod.MarkerDef;
const findOrAddMarker = defs_mod.findOrAddMarker;
const writeMarkerDef = defs_mod.writeMarkerDef;
const findNodeLabel = helpers_mod.findNodeLabel;
const computeSubgraphDepths = helpers_mod.computeSubgraphDepths;
const xmlEscape = helpers_mod.xmlEscape;

// ── Force test inclusion for submodules ─────────────────────────────────────

comptime {
    _ = config_mod;
    _ = node_render;
    _ = edge_render;
    _ = spline_render;
    _ = subgraph_render;
    _ = defs_mod;
    _ = helpers_mod;
    _ = @import("render_tests.zig");
}

// ── Public API ──────────────────────────────────────────────────────────────

/// Render any GenericLayoutIR to SVG string.
/// Converts coordinates to usize if needed, then renders.
pub fn renderGeneric(comptime Coord: type, layout: *const ir_mod.LayoutIR(Coord), allocator: Allocator, config_arg: SvgConfig) ![]u8 {
    if (Coord == usize) {
        return render(layout, allocator, config_arg);
    }
    var converted = try layout.convertCoord(usize, allocator);
    defer converted.deinit();
    return render(&converted, allocator, config_arg);
}

/// Render LayoutIR to SVG string.
pub fn render(layout: *const LayoutIR, allocator: Allocator, config: SvgConfig) ![]u8 {
    var buffer: std.ArrayListUnmanaged(u8) = .{};
    errdefer buffer.deinit(allocator);

    // Arena for style function results — one bulk free when render is done.
    // Static strings (palette lookups) are zero-cost; dynamic strings
    // (allocPrint into arena) persist until the arena is freed here.
    var style_arena = std.heap.ArenaAllocator.init(allocator);
    defer style_arena.deinit();
    const arena_alloc = style_arena.allocator();

    const writer = buffer.writer(allocator);

    // ── Pre-compute edge styles ─────────────────────────────────────────

    var max_edge_idx: usize = 0;
    for (layout.edges.items) |edge| {
        if (edge.edge_index > max_edge_idx) max_edge_idx = edge.edge_index;
    }
    const num_edge_indices = if (layout.edges.items.len > 0) max_edge_idx + 1 else 0;

    // Call edge_style_fn once per unique edge_index
    const edge_styles = try arena_alloc.alloc(EdgeStyle, num_edge_indices);
    const computed = try arena_alloc.alloc(bool, num_edge_indices);
    @memset(computed, false);

    for (layout.edges.items) |edge| {
        if (computed[edge.edge_index]) continue;
        computed[edge.edge_index] = true;

        edge_styles[edge.edge_index] = config.edge_style_fn(.{
            .edge_index = edge.edge_index,
            .total_edges = num_edge_indices,
            .from_id = edge.from_id,
            .to_id = edge.to_id,
            .from_label = findNodeLabel(layout.nodes.items, edge.from_id, layout.id_to_index),
            .to_label = findNodeLabel(layout.nodes.items, edge.to_id, layout.id_to_index),
            .label = edge.label,
            .directed = edge.directed,
            .reversed = edge.reversed,
            .arena = arena_alloc,
        });
    }

    // ── Pre-compute edge label styles ───────────────────────────────────

    const label_styles = try arena_alloc.alloc(EdgeLabelStyle, num_edge_indices);
    @memset(label_styles, EdgeLabelStyle{}); // defaults for edges without labels
    {
        var label_computed = try arena_alloc.alloc(bool, num_edge_indices);
        @memset(label_computed, false);

        for (layout.edges.items) |edge| {
            if (edge.label == null) continue;
            if (label_computed[edge.edge_index]) continue;
            label_computed[edge.edge_index] = true;

            label_styles[edge.edge_index] = config.edge_label_style_fn(.{
                .edge_index = edge.edge_index,
                .total_edges = num_edge_indices,
                .from_id = edge.from_id,
                .to_id = edge.to_id,
                .from_label = findNodeLabel(layout.nodes.items, edge.from_id, layout.id_to_index),
                .to_label = findNodeLabel(layout.nodes.items, edge.to_id, layout.id_to_index),
                .label = edge.label,
                .directed = edge.directed,
                .reversed = edge.reversed,
                .arena = arena_alloc,
            });
        }
    }

    // ── Collect unique markers ──────────────────────────────────────────

    var unique_markers: [128]MarkerDef = undefined;
    var num_unique_markers: usize = 0;

    // Resolve each edge style to marker IDs
    const resolved = try arena_alloc.alloc(ResolvedEdgeStyle, num_edge_indices);

    for (0..num_edge_indices) |i| {
        if (!computed[i]) {
            resolved[i] = .{ .stroke = "#666666", .marker_end_id = null, .marker_start_id = null, .extra_attrs = null };
            continue;
        }
        const style = edge_styles[i];
        resolved[i] = .{
            .stroke = style.stroke,
            .marker_end_id = if (style.marker_end != .none)
                findOrAddMarker(&unique_markers, &num_unique_markers, style.stroke, style.marker_end)
            else
                null,
            .marker_start_id = if (style.marker_start != .none)
                findOrAddMarker(&unique_markers, &num_unique_markers, style.stroke, style.marker_start)
            else
                null,
            .extra_attrs = style.extra_attrs,
        };
    }

    // ── SVG header ──────────────────────────────────────────────────────

    // Calculate dimensions with overflow checking
    const width = std.math.mul(usize, layout.width, config.char_width) catch return error.OutOfMemory;
    const width_padded = std.math.add(usize, width, config.padding * 2) catch return error.OutOfMemory;
    const height = std.math.mul(usize, layout.height, config.line_height) catch return error.OutOfMemory;
    const height_padded = std.math.add(usize, height, config.padding * 2) catch return error.OutOfMemory;

    try writer.print(
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<svg xmlns="http://www.w3.org/2000/svg" 
        \\     width="{d}" height="{d}" 
        \\     viewBox="0 0 {d} {d}">
        \\
        \\  <!-- Marker definitions -->
        \\  <defs>
        \\
    , .{ width_padded, height_padded, width_padded, height_padded });

    // ── Write unique marker defs ────────────────────────────────────────

    for (unique_markers[0..num_unique_markers], 0..) |m, i| {
        try writeMarkerDef(writer, i, m.shape, m.color, config.arrow_size);
    }

    // ── Pre-compute node styles ──────────────────────────────────────────

    var total_real_nodes: usize = 0;
    for (layout.nodes.items) |node| {
        if (node.kind != .dummy) total_real_nodes += 1;
    }

    const node_styles = try arena_alloc.alloc(NodeStyle, layout.nodes.items.len);
    for (layout.nodes.items, 0..) |node, idx| {
        if (node.kind == .dummy) continue;
        node_styles[idx] = config.node_style_fn(.{
            .node_id = node.id,
            .label = node.label,
            .total_nodes = total_real_nodes,
            .width = node.width * config.char_width,
            .height = node.height * config.line_height,
            .is_implicit = node.kind == .implicit,
            .arena = arena_alloc,
        });
    }

    // ── Pre-compute subgraph styles ─────────────────────────────────────

    const sg_items = layout.subgraphs.items;
    const sg_depths = computeSubgraphDepths(sg_items, arena_alloc);
    const subgraph_styles = try arena_alloc.alloc(SubgraphStyle, sg_items.len);
    for (sg_items, 0..) |sg, idx| {
        subgraph_styles[idx] = config.subgraph_style_fn(.{
            .subgraph_id = sg.id,
            .parent_id = sg.parent_id,
            .label = sg.label,
            .depth = if (idx < sg_depths.len) sg_depths[idx] else 0,
            .total_subgraphs = sg_items.len,
            .width = sg.width * config.char_width,
            .height = sg.height * config.line_height,
            .arena = arena_alloc,
        });
    }

    // ── Write user-provided defs from EdgeStyle.defs ────────────────────

    for (0..num_edge_indices) |i| {
        if (!computed[i]) continue;
        if (edge_styles[i].defs) |d| {
            try writer.writeAll("    ");
            try writer.writeAll(d);
            try writer.writeAll("\n");
        }
    }

    // ── Write user-provided defs from NodeStyle.defs ────────────────────

    for (layout.nodes.items, 0..) |node, idx| {
        if (node.kind == .dummy) continue;
        if (node_styles[idx].defs) |d| {
            try writer.writeAll("    ");
            try writer.writeAll(d);
            try writer.writeAll("\n");
        }
    }

    // ── Write user-provided defs from SubgraphStyle.defs ────────────────

    for (subgraph_styles) |sg_style| {
        if (sg_style.defs) |d| {
            try writer.writeAll("    ");
            try writer.writeAll(d);
            try writer.writeAll("\n");
        }
    }

    // ── Write global <style> inside <defs> ──────────────────────────────

    if (config.global_style) |style| {
        try writer.writeAll("    ");
        try writer.writeAll(style);
        try writer.writeAll("\n");
    }

    try writer.writeAll(
        \\  </defs>
        \\
        \\  <!-- Background -->
        \\  <rect width="100%" height="100%" fill="white"/>
        \\
    );

    // Render subgraph boxes (behind everything else)
    if (config.show_subgraphs and layout.subgraphs.items.len > 0) {
        try writer.writeAll(
            \\  <!-- Subgraphs -->
            \\  <g id="subgraphs">
            \\
        );
        try subgraph_render.renderSubgraphs(writer, layout, config, subgraph_styles);
        try writer.writeAll(
            \\  </g>
            \\
        );
    }

    try writer.writeAll(
        \\  <!-- Edges (rendered first, under nodes) -->
        \\  <g id="edges">
        \\
    );

    // Render edges
    if (config.stitch_splines) {
        // Group edges by edge_index and render as stitched splines
        try spline_render.renderStitchedEdges(writer, layout, allocator, config, resolved, label_styles);
    } else {
        // Render each edge segment individually
        for (layout.edges.items) |edge| {
            const style = if (edge.edge_index < resolved.len) resolved[edge.edge_index] else ResolvedEdgeStyle{
                .stroke = "#666666",
                .marker_end_id = null,
                .marker_start_id = null,
                .extra_attrs = null,
            };
            const ls = if (edge.edge_index < label_styles.len) label_styles[edge.edge_index] else EdgeLabelStyle{};

            // Self-loops: render a loop arc
            if (edge.reversed and edge.from_id == edge.to_id) {
                try edge_render.renderSelfLoop(writer, &edge, config, style, ls, layout.nodes.items);
                continue;
            }
            try edge_render.renderEdge(writer, edge, config, style, ls);
        }
    }

    try writer.writeAll(
        \\  </g>
        \\
        \\  <!-- Nodes -->
        \\  <g id="nodes">
        \\
    );

    // Render nodes
    for (layout.nodes.items, 0..) |node, idx| {
        if (node.kind == .dummy) {
            if (config.show_dummy_nodes) {
                try node_render.renderDummyNode(writer, node, config);
            }
            continue;
        }
        try node_render.renderNode(writer, node, node_styles[idx], config);
    }

    // SVG footer
    try writer.writeAll(
        \\  </g>
        \\
    );

    // ── Write global <script> at end (DOM is ready) ─────────────────────

    if (config.global_script) |script| {
        try writer.writeAll("  ");
        try writer.writeAll(script);
        try writer.writeAll("\n");
    }

    try writer.writeAll(
        \\</svg>
        \\
    );

    return buffer.toOwnedSlice(allocator);
}
