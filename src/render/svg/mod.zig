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
//!   mod.zig         ← this file: render() entry point + re-exports
//!   config.zig      ← SvgConfig struct
//!   nodes.zig       ← renderNode
//!   edges.zig       ← renderEdge, renderSingleEdge, renderSelfLoop, renderBezierEdge
//!   splines.zig     ← renderStitchedEdges, renderSplinePath
//!   subgraphs.zig   ← renderSubgraphs
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
const LayoutNode = ir_mod.LayoutNode(usize);

// ── Submodule re-exports ────────────────────────────────────────────────────

const config_mod = @import("config.zig");
const node_render = @import("nodes.zig");
const edge_render = @import("edges.zig");
const spline_render = @import("splines.zig");
const subgraph_render = @import("subgraphs.zig");
const types = @import("../types.zig");

pub const SvgConfig = config_mod.SvgConfig;
pub const EdgeStyle = config_mod.EdgeStyle;
pub const EdgeStyleContext = config_mod.EdgeStyleContext;
pub const NodeStyle = config_mod.NodeStyle;
pub const NodeStyleContext = config_mod.NodeStyleContext;
pub const SubgraphStyle = config_mod.SubgraphStyle;
pub const SubgraphStyleContext = config_mod.SubgraphStyleContext;
pub const shapes = config_mod.shapes;
pub const subgraph_presets = config_mod.subgraph_presets;
pub const MarkerShape = types.MarkerShape;
pub const ResolvedEdgeStyle = config_mod.ResolvedEdgeStyle;
pub const defaultEdgeStyle = config_mod.defaultEdgeStyle;
pub const monoEdgeStyle = config_mod.monoEdgeStyle;
pub const renderBezierEdge = edge_render.renderBezierEdge;

/// A unique (color, shape) pair for a `<marker>` definition.
const MarkerDef = struct { color: []const u8, shape: MarkerShape };

// ── Force test inclusion for submodules ─────────────────────────────────────

comptime {
    _ = config_mod;
    _ = node_render;
    _ = edge_render;
    _ = spline_render;
    _ = subgraph_render;
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
            .from_label = findNodeLabel(layout.nodes.items, edge.from_id),
            .to_label = findNodeLabel(layout.nodes.items, edge.to_id),
            .label = edge.label,
            .directed = edge.directed,
            .reversed = edge.reversed,
            .arena = arena_alloc,
        });
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
            .height = config.line_height,
            .is_implicit = node.kind == .implicit,
            .arena = arena_alloc,
        });
    }

    // ── Pre-compute subgraph styles ─────────────────────────────────────

    const sg_items = layout.subgraphs.items;
    const subgraph_styles = try arena_alloc.alloc(SubgraphStyle, sg_items.len);
    for (sg_items, 0..) |sg, idx| {
        subgraph_styles[idx] = config.subgraph_style_fn(.{
            .subgraph_id = sg.id,
            .parent_id = sg.parent_id,
            .label = sg.label,
            .depth = computeSubgraphDepth(sg_items, sg.parent_id),
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
        try spline_render.renderStitchedEdges(writer, layout, allocator, config, resolved);
    } else {
        // Render each edge segment individually
        for (layout.edges.items) |edge| {
            const style = if (edge.edge_index < resolved.len) resolved[edge.edge_index] else ResolvedEdgeStyle{
                .stroke = "#666666",
                .marker_end_id = null,
                .marker_start_id = null,
                .extra_attrs = null,
            };

            // Self-loops: render a loop arc
            if (edge.reversed and edge.from_id == edge.to_id) {
                try edge_render.renderSelfLoop(writer, &edge, config, style, layout.nodes.items);
                continue;
            }
            try edge_render.renderEdge(writer, edge, config, style);
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

// ── Helpers ─────────────────────────────────────────────────────────────────

/// Find a node label by ID. Returns empty string for unknown/dummy nodes.
fn findNodeLabel(nodes: []const LayoutNode, node_id: usize) []const u8 {
    for (nodes) |node| {
        if (node.id == node_id) return node.label;
    }
    return "";
}

/// Find an existing (color, shape) marker or add a new one. Returns the index.
fn findOrAddMarker(
    markers: *[128]MarkerDef,
    count: *usize,
    color: []const u8,
    shape: MarkerShape,
) usize {
    for (markers[0..count.*], 0..) |m, i| {
        if (m.shape == shape and std.mem.eql(u8, m.color, color)) return i;
    }
    if (count.* >= 128) return 0; // safety cap
    markers[count.*] = .{ .color = color, .shape = shape };
    count.* += 1;
    return count.* - 1;
}

/// Write a single `<marker>` definition for the given shape and color.
fn writeMarkerDef(writer: anytype, id: usize, shape: MarkerShape, color: []const u8, size: usize) !void {
    const half = size / 2;
    switch (shape) {
        .none => {},
        .arrow => {
            try writer.print(
                \\    <marker id="zg-m-{d}" markerWidth="{d}" markerHeight="{d}" 
                \\            refX="{d}" refY="{d}" orient="auto" markerUnits="userSpaceOnUse">
                \\      <polygon points="0 0, {d} {d}, 0 {d}" fill="{s}"/>
                \\    </marker>
                \\
            , .{ id, size, size, size, half, size, half, size, color });
        },
        .open_arrow => {
            try writer.print(
                \\    <marker id="zg-m-{d}" markerWidth="{d}" markerHeight="{d}" 
                \\            refX="{d}" refY="{d}" orient="auto" markerUnits="userSpaceOnUse">
                \\      <polygon points="0 0, {d} {d}, 0 {d}" fill="white" stroke="{s}" stroke-width="1"/>
                \\    </marker>
                \\
            , .{ id, size, size, size, half, size, half, size, color });
        },
        .diamond => {
            try writer.print(
                \\    <marker id="zg-m-{d}" markerWidth="{d}" markerHeight="{d}" 
                \\            refX="{d}" refY="{d}" orient="auto" markerUnits="userSpaceOnUse">
                \\      <polygon points="{d} 0, {d} {d}, {d} {d}, 0 {d}" fill="{s}"/>
                \\    </marker>
                \\
            , .{ id, size, size, size, half, half, size, half, half, size, half, color });
        },
        .open_diamond => {
            try writer.print(
                \\    <marker id="zg-m-{d}" markerWidth="{d}" markerHeight="{d}" 
                \\            refX="{d}" refY="{d}" orient="auto" markerUnits="userSpaceOnUse">
                \\      <polygon points="{d} 0, {d} {d}, {d} {d}, 0 {d}" fill="white" stroke="{s}" stroke-width="1"/>
                \\    </marker>
                \\
            , .{ id, size, size, size, half, half, size, half, half, size, half, color });
        },
        .circle => {
            try writer.print(
                \\    <marker id="zg-m-{d}" markerWidth="{d}" markerHeight="{d}" 
                \\            refX="{d}" refY="{d}" orient="auto" markerUnits="userSpaceOnUse">
                \\      <circle cx="{d}" cy="{d}" r="{d}" fill="{s}"/>
                \\    </marker>
                \\
            , .{ id, size, size, size, half, half, half, half, color });
        },
        .open_circle => {
            try writer.print(
                \\    <marker id="zg-m-{d}" markerWidth="{d}" markerHeight="{d}" 
                \\            refX="{d}" refY="{d}" orient="auto" markerUnits="userSpaceOnUse">
                \\      <circle cx="{d}" cy="{d}" r="{d}" fill="white" stroke="{s}" stroke-width="1"/>
                \\    </marker>
                \\
            , .{ id, size, size, size, half, half, half, half, color });
        },
    }
}

/// Compute nesting depth for a subgraph by walking up parent_id chains.
/// Returns 0 for root-level subgraphs, 1 for one level nested, etc.
fn computeSubgraphDepth(subgraphs: []const ir_mod.SubgraphInfo(usize), parent_id: ?usize) usize {
    var depth: usize = 0;
    var current = parent_id;
    while (current) |pid| {
        depth += 1;
        // Find the parent subgraph and continue up
        var found = false;
        for (subgraphs) |sg| {
            if (sg.id == pid) {
                current = sg.parent_id;
                found = true;
                break;
            }
        }
        if (!found) break; // orphan parent_id — shouldn't happen, but be safe
    }
    return depth;
}

// ============================================================================
// Tests
// ============================================================================

test "svg: basic render" {
    const allocator = std.testing.allocator;

    var layout = LayoutIR.init(allocator);
    defer layout.deinit();

    try layout.addNode(.{
        .id = 1,
        .label = "Test",
        .x = 0,
        .y = 0,
        .width = 6,
        .center_x = 3,
        .level = 0,
        .level_position = 0,
    });

    layout.setDimensions(10, 5);

    const svg = try render(&layout, allocator, .{});
    defer allocator.free(svg);

    // Should contain SVG structure
    try std.testing.expect(std.mem.indexOf(u8, svg, "<svg") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "</svg>") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "Test") != null);
}

test "svg: edge rendering" {
    const allocator = std.testing.allocator;

    var layout = LayoutIR.init(allocator);
    defer layout.deinit();

    try layout.addNode(.{
        .id = 1,
        .label = "A",
        .x = 0,
        .y = 0,
        .width = 3,
        .center_x = 1,
        .level = 0,
        .level_position = 0,
    });
    try layout.addNode(.{
        .id = 2,
        .label = "B",
        .x = 0,
        .y = 2,
        .width = 3,
        .center_x = 1,
        .level = 1,
        .level_position = 0,
    });

    try layout.addEdge(.{
        .from_id = 1,
        .to_id = 2,
        .from_x = 1,
        .from_y = 1,
        .to_x = 1,
        .to_y = 2,
        .path = .direct,
        .edge_index = 0,
    });

    layout.setDimensions(5, 5);

    const svg = try render(&layout, allocator, .{});
    defer allocator.free(svg);

    // Should contain line element for direct edge
    try std.testing.expect(std.mem.indexOf(u8, svg, "<line") != null);
}

test "svg: corner edge rendering" {
    const allocator = std.testing.allocator;

    var layout = LayoutIR.init(allocator);
    defer layout.deinit();

    try layout.addNode(.{
        .id = 1,
        .label = "A",
        .x = 0,
        .y = 0,
        .width = 3,
        .center_x = 1,
        .level = 0,
        .level_position = 0,
    });
    try layout.addNode(.{
        .id = 2,
        .label = "B",
        .x = 5,
        .y = 4,
        .width = 3,
        .center_x = 6,
        .level = 1,
        .level_position = 0,
    });

    try layout.addEdge(.{
        .from_id = 1,
        .to_id = 2,
        .from_x = 1,
        .from_y = 1,
        .to_x = 6,
        .to_y = 4,
        .path = .{ .corner = .{ .horizontal_y = 2 } },
        .edge_index = 0,
    });

    layout.setDimensions(10, 6);

    // Disable stitch_splines so the per-edge renderEdge path (which handles
    // .corner routing) is exercised instead of the stitched spline path.
    const svg = try render(&layout, allocator, .{ .stitch_splines = false });
    defer allocator.free(svg);

    // Corner edges use path elements with L-shaped segments
    try std.testing.expect(std.mem.indexOf(u8, svg, "<path") != null);
}

test "svg: multiple nodes and edges" {
    const allocator = std.testing.allocator;

    var layout = LayoutIR.init(allocator);
    defer layout.deinit();

    // Build a small diamond: A -> B, A -> C, B -> D, C -> D
    try layout.addNode(.{
        .id = 1,
        .label = "A",
        .x = 5,
        .y = 0,
        .width = 3,
        .center_x = 6,
        .level = 0,
        .level_position = 0,
    });
    try layout.addNode(.{
        .id = 2,
        .label = "B",
        .x = 0,
        .y = 4,
        .width = 3,
        .center_x = 1,
        .level = 1,
        .level_position = 0,
    });
    try layout.addNode(.{
        .id = 3,
        .label = "C",
        .x = 10,
        .y = 4,
        .width = 3,
        .center_x = 11,
        .level = 1,
        .level_position = 1,
    });
    try layout.addNode(.{
        .id = 4,
        .label = "D",
        .x = 5,
        .y = 8,
        .width = 3,
        .center_x = 6,
        .level = 2,
        .level_position = 0,
    });

    for ([_]struct { from: usize, to: usize, idx: usize }{
        .{ .from = 1, .to = 2, .idx = 0 },
        .{ .from = 1, .to = 3, .idx = 1 },
        .{ .from = 2, .to = 4, .idx = 2 },
        .{ .from = 3, .to = 4, .idx = 3 },
    }) |e| {
        try layout.addEdge(.{
            .from_id = e.from,
            .to_id = e.to,
            .from_x = 6,
            .from_y = 1,
            .to_x = 6,
            .to_y = 4,
            .path = .direct,
            .edge_index = e.idx,
        });
    }

    layout.setDimensions(15, 10);

    const svg = try render(&layout, allocator, .{});
    defer allocator.free(svg);

    // Should contain all 4 node labels
    try std.testing.expect(std.mem.indexOf(u8, svg, ">A<") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, ">B<") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, ">C<") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, ">D<") != null);
    // Should have valid SVG structure
    try std.testing.expect(std.mem.indexOf(u8, svg, "<svg") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "</svg>") != null);
}

test "svg: empty layout" {
    const allocator = std.testing.allocator;

    var layout = LayoutIR.init(allocator);
    defer layout.deinit();

    layout.setDimensions(0, 0);

    const svg = try render(&layout, allocator, .{});
    defer allocator.free(svg);

    // Should still produce valid SVG
    try std.testing.expect(std.mem.indexOf(u8, svg, "<svg") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "</svg>") != null);
}

test "svg: colored edges" {
    const allocator = std.testing.allocator;

    var layout = LayoutIR.init(allocator);
    defer layout.deinit();

    try layout.addNode(.{
        .id = 1,
        .label = "A",
        .x = 0,
        .y = 0,
        .width = 3,
        .center_x = 1,
        .level = 0,
        .level_position = 0,
    });
    try layout.addNode(.{
        .id = 2,
        .label = "B",
        .x = 0,
        .y = 4,
        .width = 3,
        .center_x = 1,
        .level = 1,
        .level_position = 0,
    });

    try layout.addEdge(.{
        .from_id = 1,
        .to_id = 2,
        .from_x = 1,
        .from_y = 1,
        .to_x = 1,
        .to_y = 4,
        .path = .direct,
        .edge_index = 0,
    });

    layout.setDimensions(5, 5);

    // Default edge_style_fn does palette cycling (equivalent to old color_edges=true)
    const svg_out = try render(&layout, allocator, .{});
    defer allocator.free(svg_out);

    // Should contain colored stroke from palette
    try std.testing.expect(std.mem.indexOf(u8, svg_out, "stroke=") != null);
    // Should contain marker definitions with zg-m- prefix
    try std.testing.expect(std.mem.indexOf(u8, svg_out, "zg-m-") != null);
}

test "svg: subgraph rendering" {
    const allocator = std.testing.allocator;

    var layout = LayoutIR.init(allocator);
    defer layout.deinit();

    try layout.addNode(.{
        .id = 1,
        .label = "A",
        .x = 5,
        .y = 3,
        .width = 3,
        .center_x = 6,
        .level = 0,
        .level_position = 0,
    });
    try layout.addNode(.{
        .id = 2,
        .label = "B",
        .x = 5,
        .y = 7,
        .width = 3,
        .center_x = 6,
        .level = 1,
        .level_position = 0,
    });

    // Add a subgraph bounding box
    try layout.subgraphs.append(allocator, .{
        .id = 0,
        .parent_id = null,
        .label = "cluster",
        .x = 3,
        .y = 1,
        .width = 10,
        .height = 10,
    });

    layout.setDimensions(20, 15);

    const svg = try render(&layout, allocator, .{});
    defer allocator.free(svg);

    // Should contain subgraph group and rect
    try std.testing.expect(std.mem.indexOf(u8, svg, "id=\"subgraphs\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "stroke-dasharray") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "cluster") != null);
}

test "svg: subgraph rendering disabled" {
    const allocator = std.testing.allocator;

    var layout = LayoutIR.init(allocator);
    defer layout.deinit();

    try layout.subgraphs.append(allocator, .{
        .id = 0,
        .parent_id = null,
        .label = "hidden",
        .x = 0,
        .y = 0,
        .width = 5,
        .height = 5,
    });

    layout.setDimensions(10, 10);

    const svg = try render(&layout, allocator, .{ .show_subgraphs = false });
    defer allocator.free(svg);

    // Should NOT contain subgraph elements
    try std.testing.expect(std.mem.indexOf(u8, svg, "id=\"subgraphs\"") == null);
}

test "svg: global_style and global_script injection" {
    const allocator = std.testing.allocator;

    var layout = LayoutIR.init(allocator);
    defer layout.deinit();

    layout.setDimensions(5, 5);

    const style_content = "<style>.node:hover { opacity: 0.8; }</style>";
    const script_content = "<script>console.log('hello');</script>";

    const svg = try render(&layout, allocator, .{
        .global_style = style_content,
        .global_script = script_content,
    });
    defer allocator.free(svg);

    // Style should be inside <defs>
    const defs_end = std.mem.indexOf(u8, svg, "</defs>").?;
    const style_pos = std.mem.indexOf(u8, svg, ".node:hover").?;
    try std.testing.expect(style_pos < defs_end);

    // Script should be after </g> (nodes group) and before </svg>
    const svg_end = std.mem.indexOf(u8, svg, "</svg>").?;
    const script_pos = std.mem.indexOf(u8, svg, "console.log").?;
    try std.testing.expect(script_pos < svg_end);
    try std.testing.expect(script_pos > defs_end);
}

test "svg: global_style and global_script null by default" {
    const allocator = std.testing.allocator;

    var layout = LayoutIR.init(allocator);
    defer layout.deinit();

    layout.setDimensions(5, 5);

    const svg = try render(&layout, allocator, .{});
    defer allocator.free(svg);

    // Should NOT contain <style> or <script> tags
    try std.testing.expect(std.mem.indexOf(u8, svg, "<style>") == null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "<script>") == null);
}

test "svg: node_style_fn shapes" {
    const allocator = std.testing.allocator;

    var layout = LayoutIR.init(allocator);
    defer layout.deinit();

    try layout.addNode(.{
        .id = 1,
        .label = "Hello",
        .x = 0,
        .y = 0,
        .width = 7,
        .center_x = 3,
        .level = 0,
        .level_position = 0,
    });

    layout.setDimensions(10, 5);

    // Test default (rounded_rectangle)
    const svg_default = try render(&layout, allocator, .{});
    defer allocator.free(svg_default);
    // Should have <g transform=...> wrapper and <rect with rx
    try std.testing.expect(std.mem.indexOf(u8, svg_default, "<g transform=") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg_default, "rx=\"4\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg_default, ">Hello<") != null);

    // Test diamond shape
    const svg_diamond = try render(&layout, allocator, .{
        .node_style_fn = &config_mod.shapes.diamond,
    });
    defer allocator.free(svg_diamond);
    try std.testing.expect(std.mem.indexOf(u8, svg_diamond, "<polygon") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg_diamond, ">Hello<") != null);

    // Test ellipse shape
    const svg_ellipse = try render(&layout, allocator, .{
        .node_style_fn = &config_mod.shapes.ellipse,
    });
    defer allocator.free(svg_ellipse);
    try std.testing.expect(std.mem.indexOf(u8, svg_ellipse, "<ellipse") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg_ellipse, ">Hello<") != null);
}

test "svg: custom node_style_fn" {
    const allocator = std.testing.allocator;

    var layout = LayoutIR.init(allocator);
    defer layout.deinit();

    try layout.addNode(.{
        .id = 1,
        .label = "Custom",
        .x = 0,
        .y = 0,
        .width = 8,
        .center_x = 4,
        .level = 0,
        .level_position = 0,
    });

    layout.setDimensions(10, 5);

    const svg = try render(&layout, allocator, .{
        .node_style_fn = &struct {
            fn style(_: NodeStyleContext) NodeStyle {
                return .{
                    .shape_svg = "<circle cx=\"40\" cy=\"10\" r=\"10\"/><text x=\"40\" y=\"14\" text-anchor=\"middle\" fill=\"#333\" stroke=\"none\">Custom</text>",
                    .fill = "#ff0000",
                    .stroke = "#00ff00",
                };
            }
        }.style,
    });
    defer allocator.free(svg);

    try std.testing.expect(std.mem.indexOf(u8, svg, "fill=\"#ff0000\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "stroke=\"#00ff00\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, ">Custom<") != null);
}

test "svg: custom subgraph_style_fn" {
    const allocator = std.testing.allocator;

    var layout = LayoutIR.init(allocator);
    defer layout.deinit();

    try layout.addNode(.{
        .id = 1,
        .label = "A",
        .x = 2,
        .y = 2,
        .width = 3,
        .center_x = 3,
        .level = 0,
        .level_position = 0,
    });

    // Root-level subgraph
    try layout.subgraphs.append(allocator, .{
        .id = 0,
        .parent_id = null,
        .label = "Root",
        .x = 1,
        .y = 1,
        .width = 8,
        .height = 6,
    });

    // Nested subgraph (depth 1)
    try layout.subgraphs.append(allocator, .{
        .id = 1,
        .parent_id = 0,
        .label = "Nested",
        .x = 2,
        .y = 2,
        .width = 5,
        .height = 3,
    });

    layout.setDimensions(15, 10);

    const svg = try render(&layout, allocator, .{
        .subgraph_style_fn = &struct {
            fn style(ctx: SubgraphStyleContext) SubgraphStyle {
                if (ctx.depth == 0) {
                    return .{
                        .box_svg = std.fmt.allocPrint(ctx.arena,
                            \\<rect x="0" y="0" width="{d}" height="{d}" rx="8" ry="8"/>
                            \\<text x="8" y="16" font-family="monospace" font-size="12" fill="#e5484d" stroke="none">{s}</text>
                        , .{ ctx.width, ctx.height, ctx.label }) catch "",
                        .fill = "#fce8e8",
                        .stroke = "#e5484d",
                    };
                }
                return .{
                    .box_svg = std.fmt.allocPrint(ctx.arena,
                        \\<rect x="0" y="0" width="{d}" height="{d}" rx="4" ry="4"/>
                        \\<text x="4" y="13" font-family="monospace" font-size="11" fill="#30a46c" stroke="none">{s}</text>
                    , .{ ctx.width, ctx.height, ctx.label }) catch "",
                    .fill = "#e6f4ea",
                    .stroke = "#30a46c",
                };
            }
        }.style,
    });
    defer allocator.free(svg);

    // Root subgraph should use red style
    try std.testing.expect(std.mem.indexOf(u8, svg, "fill=\"#fce8e8\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "stroke=\"#e5484d\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, ">Root<") != null);

    // Nested subgraph should use green style
    try std.testing.expect(std.mem.indexOf(u8, svg, "fill=\"#e6f4ea\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "stroke=\"#30a46c\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, ">Nested<") != null);

    // Both should be inside the subgraphs group
    try std.testing.expect(std.mem.indexOf(u8, svg, "id=\"subgraphs\"") != null);
}

test "svg: subgraph depth computation" {
    const allocator = std.testing.allocator;

    var layout = LayoutIR.init(allocator);
    defer layout.deinit();

    // Three-level nesting: root → mid → deep
    try layout.subgraphs.append(allocator, .{
        .id = 10,
        .parent_id = null,
        .label = "root",
        .x = 0,
        .y = 0,
        .width = 20,
        .height = 15,
    });
    try layout.subgraphs.append(allocator, .{
        .id = 20,
        .parent_id = 10,
        .label = "mid",
        .x = 1,
        .y = 1,
        .width = 15,
        .height = 10,
    });
    try layout.subgraphs.append(allocator, .{
        .id = 30,
        .parent_id = 20,
        .label = "deep",
        .x = 2,
        .y = 2,
        .width = 10,
        .height = 5,
    });

    layout.setDimensions(25, 20);

    // Use a style fn that encodes depth into the fill color for testing
    const svg = try render(&layout, allocator, .{
        .subgraph_style_fn = &struct {
            fn style(ctx: SubgraphStyleContext) SubgraphStyle {
                const fills = [_][]const u8{ "#depth0", "#depth1", "#depth2" };
                return .{
                    .box_svg = std.fmt.allocPrint(ctx.arena,
                        \\<rect x="0" y="0" width="{d}" height="{d}"/>
                    , .{ ctx.width, ctx.height }) catch "",
                    .fill = fills[ctx.depth % fills.len],
                };
            }
        }.style,
    });
    defer allocator.free(svg);

    try std.testing.expect(std.mem.indexOf(u8, svg, "fill=\"#depth0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "fill=\"#depth1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "fill=\"#depth2\"") != null);
}
