//! Terminal renderer for zigraph
//!
//! Renders LayoutIR to text using Unicode box-drawing glyphs.
//!
//! ## Box Drawing Characters
//!
//! - `│` vertical line
//! - `─` horizontal line
//! - `└` corner down-right
//! - `┘` corner down-left
//! - `┌` corner up-right
//! - `┐` corner up-left
//!
//! Arrow markers are configurable via `MarkerShape` (default: `↓↑→←`).
//!
//! ## Module structure
//!
//! ```text
//! terminal/
//!   mod.zig          ← this file: render() entry point + re-exports
//!   config.zig       ← Config, style types, presets, defaults
//!   buffer.zig       ← Buffer2D (flat 2D character + color buffer)
//!   junctions.zig    ← CP_* codepoints, mergeJunction, isSubgraphBorderChar
//!   nodes.zig        ← paintNode
//!   edges.zig        ← paintEdge, drawDirectVertical/Horizontal/Manhattan
//!   labels.zig       ← LegendEntry, canPlaceLabel, paintLabel
//!   subgraphs.zig    ← paintSubgraphs, paintSubgraphLabels, paintSubgraphBox
//!   render_tests.zig ← integration tests
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;
const ir_mod = @import("../../core/ir.zig");
const LayoutIR = ir_mod.LayoutIR(usize);
const colors = @import("../color/mod.zig");
const types = @import("../types.zig");

// ── Submodule imports ───────────────────────────────────────────────────────

const config_mod = @import("config.zig");
const buffer_mod = @import("buffer.zig");
const junction_mod = @import("junctions.zig");
const node_render = @import("nodes.zig");
const edge_render = @import("edges.zig");
const label_render = @import("labels.zig");
const subgraph_render = @import("subgraphs.zig");

// ── Public re-exports ───────────────────────────────────────────────────────

pub const Config = config_mod.Config;
pub const MarkerShape = config_mod.MarkerShape;
pub const EdgeStyleContext = config_mod.EdgeStyleContext;
pub const NodeStyleContext = config_mod.NodeStyleContext;
pub const SubgraphStyleContext = config_mod.SubgraphStyleContext;
pub const TextAttrs = config_mod.TextAttrs;
pub const LineWeight = config_mod.LineWeight;
pub const NodeBorder = config_mod.NodeBorder;
pub const LabelPlacement = config_mod.LabelPlacement;
pub const SubgraphBorder = config_mod.SubgraphBorder;
pub const LabelPosition = config_mod.LabelPosition;
pub const TerminalEdgeStyle = config_mod.TerminalEdgeStyle;
pub const TerminalNodeStyle = config_mod.TerminalNodeStyle;
pub const TerminalEdgeLabelStyle = config_mod.TerminalEdgeLabelStyle;
pub const TerminalSubgraphStyle = config_mod.TerminalSubgraphStyle;
pub const defaultEdgeStyle = config_mod.defaultEdgeStyle;
pub const defaultNodeStyle = config_mod.defaultNodeStyle;
pub const defaultEdgeLabelStyle = config_mod.defaultEdgeLabelStyle;
pub const defaultSubgraphStyle = config_mod.defaultSubgraphStyle;
pub const subgraph_presets = config_mod.subgraph_presets;

pub const Buffer2D = buffer_mod.Buffer2D;
pub const LegendEntry = label_render.LegendEntry;

// Junction constants + functions (used by tests and advanced consumers)
pub const mergeJunction = junction_mod.mergeJunction;
pub const mergeWithDoubleLine = junction_mod.mergeWithDoubleLine;
pub const isSubgraphBorderChar = junction_mod.isSubgraphBorderChar;
pub const isMarkerChar = junction_mod.isMarkerChar;
// Codepoint constants
pub const CP_V_LINE = junction_mod.CP_V_LINE;
pub const CP_H_LINE = junction_mod.CP_H_LINE;
pub const CP_ARROW_DOWN = junction_mod.CP_ARROW_DOWN;
pub const CP_ARROW_UP = junction_mod.CP_ARROW_UP;
pub const CP_ARROW_RIGHT = junction_mod.CP_ARROW_RIGHT;
pub const CP_ARROW_LEFT = junction_mod.CP_ARROW_LEFT;
pub const CP_ARROW_DOWN_DASH = junction_mod.CP_ARROW_DOWN_DASH;
pub const CP_ARROW_UP_DASH = junction_mod.CP_ARROW_UP_DASH;
pub const CP_ARROW_RIGHT_DASH = junction_mod.CP_ARROW_RIGHT_DASH;
pub const CP_ARROW_LEFT_DASH = junction_mod.CP_ARROW_LEFT_DASH;
pub const CP_V_LINE_DASH = junction_mod.CP_V_LINE_DASH;
pub const CP_H_LINE_DASH = junction_mod.CP_H_LINE_DASH;
pub const CP_CORNER_DR = junction_mod.CP_CORNER_DR;
pub const CP_CORNER_DL = junction_mod.CP_CORNER_DL;
pub const CP_CORNER_UR = junction_mod.CP_CORNER_UR;
pub const CP_CORNER_UL = junction_mod.CP_CORNER_UL;
pub const CP_T_DOWN = junction_mod.CP_T_DOWN;
pub const CP_T_UP = junction_mod.CP_T_UP;
pub const CP_T_RIGHT = junction_mod.CP_T_RIGHT;
pub const CP_T_LEFT = junction_mod.CP_T_LEFT;
pub const CP_CROSS = junction_mod.CP_CROSS;
pub const CP_SG_UR = junction_mod.CP_SG_UR;
pub const CP_SG_UL = junction_mod.CP_SG_UL;
pub const CP_SG_DR = junction_mod.CP_SG_DR;
pub const CP_SG_DL = junction_mod.CP_SG_DL;
pub const CP_SG_H = junction_mod.CP_SG_H;
pub const CP_SG_V = junction_mod.CP_SG_V;
pub const CP_MIX_CROSS_DH = junction_mod.CP_MIX_CROSS_DH;
pub const CP_MIX_CROSS_DV = junction_mod.CP_MIX_CROSS_DV;
pub const CP_MIX_T_DOWN_DH = junction_mod.CP_MIX_T_DOWN_DH;
pub const CP_MIX_T_UP_DH = junction_mod.CP_MIX_T_UP_DH;
pub const CP_MIX_T_RIGHT_DV = junction_mod.CP_MIX_T_RIGHT_DV;
pub const CP_MIX_T_LEFT_DV = junction_mod.CP_MIX_T_LEFT_DV;

// Paint functions (public for advanced usage / tests)
pub const paintEdge = edge_render.paintEdge;
pub const paintNode = node_render.paintNode;
pub const paintSubgraphs = subgraph_render.paintSubgraphs;
pub const paintSubgraphLabels = subgraph_render.paintSubgraphLabels;
pub const paintSubgraphBox = subgraph_render.paintSubgraphBox;
pub const canPlaceLabel = label_render.canPlaceLabel;
pub const paintLabel = label_render.paintLabel;
pub const drawDirectVertical = edge_render.drawDirectVertical;
pub const drawDirectHorizontal = edge_render.drawDirectHorizontal;
pub const drawDirectManhattan = edge_render.drawDirectManhattan;

// ── Force test inclusion for submodules ─────────────────────────────────────

comptime {
    _ = config_mod;
    _ = buffer_mod;
    _ = junction_mod;
    _ = node_render;
    _ = edge_render;
    _ = label_render;
    _ = subgraph_render;
    _ = @import("render_tests.zig");
}

// ── Public API ──────────────────────────────────────────────────────────────

/// Render any GenericLayoutIR to a Unicode string.
/// Converts coordinates to usize if needed, then renders.
pub fn renderGeneric(comptime Coord: type, layout_ir: *const ir_mod.LayoutIR(Coord), allocator: Allocator) ![]u8 {
    return renderGenericWithConfig(Coord, layout_ir, allocator, .{});
}

/// Render any GenericLayoutIR to a Unicode string with configuration.
pub fn renderGenericWithConfig(comptime Coord: type, layout_ir: *const ir_mod.LayoutIR(Coord), allocator: Allocator, config: Config) ![]u8 {
    if (Coord == usize) {
        return renderWithConfig(layout_ir, allocator, config);
    }
    var converted = try layout_ir.convertCoord(usize, allocator);
    defer converted.deinit();
    return renderWithConfig(&converted, allocator, config);
}

/// Render a LayoutIR to a Unicode string.
pub fn render(layout_ir: *const LayoutIR, allocator: Allocator) ![]u8 {
    return renderWithConfig(layout_ir, allocator, .{});
}

/// Render a LayoutIR to a Unicode string with configuration.
pub fn renderWithConfig(layout_ir: *const LayoutIR, allocator: Allocator, config: Config) ![]u8 {
    const base_width = layout_ir.getWidth();
    const height = layout_ir.getHeight();

    if (base_width == 0 or height == 0) {
        const result = try allocator.alloc(u8, 0);
        return result;
    }

    // Check if extra width is needed for self-loop indicators (↺ + label)
    var extra_width: usize = 0;
    for (layout_ir.getEdges()) |edge| {
        if (edge.reversed and edge.from_id == edge.to_id) {
            if (layout_ir.nodeById(edge.from_id)) |node| {
                var needed = node.x + node.width + 1; // +1 for ↺
                if (edge.label) |label| {
                    needed += label.len + 2; // +2 for quotes
                }
                if (needed > base_width + extra_width) {
                    extra_width = needed - base_width;
                }
            }
        }
    }

    const width = base_width + extra_width;

    // Single flat allocation for cache efficiency
    var buffer = try Buffer2D.init(allocator, width, height);
    defer buffer.deinit(allocator);

    // Arena for style function contexts (bulk-freed at end of render)
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const total_edges = layout_ir.getEdges().len;
    const total_nodes = layout_ir.getNodes().len;

    // Paint subgraph boxes first (background layer)
    if (config.show_subgraphs) {
        subgraph_render.paintSubgraphs(&buffer, layout_ir);
    }

    // Paint all edges (so nodes overwrite them)
    for (layout_ir.getEdges()) |edge| {
        // Build edge style context
        const from_label = if (layout_ir.nodeById(edge.from_id)) |n| n.label else "";
        const to_label = if (layout_ir.nodeById(edge.to_id)) |n| n.label else "";
        const ctx = EdgeStyleContext{
            .edge_index = edge.edge_index,
            .total_edges = total_edges,
            .from_id = edge.from_id,
            .to_id = edge.to_id,
            .from_label = from_label,
            .to_label = to_label,
            .label = edge.label,
            .directed = edge.directed,
            .reversed = edge.reversed,
            .arena = arena,
        };

        // Call style function, resolve color (style > palette > none)
        const style = config.edge_style_fn(ctx);
        const edge_color: u8 = if (style.color != 0)
            style.color
        else if (config.edge_palette) |palette|
            colors.getAnsi(palette, edge.edge_index)
        else
            0;

        edge_render.paintEdge(&buffer, &edge, edge_color, style.weight, style.marker_end, style.marker_start);
    }

    // For invisible dummy nodes, paint a vertical line at their position
    // and clean up any marker characters to make a continuous line.
    if (!config.show_dummy_nodes) {
        for (layout_ir.getNodes()) |node| {
            if (node.kind == .dummy) {
                const x = node.center_x;
                const y = node.y;

                const current = buffer.get(x, y);
                const merged = junction_mod.mergeJunction(current, true, true, false, false);
                buffer.set(x, y, merged);

                if (y > 0) {
                    const above = buffer.get(x, y - 1);
                    if (junction_mod.isMarkerChar(above)) {
                        buffer.set(x, y - 1, CP_V_LINE);
                    }
                }
                const below = buffer.get(x, y + 1);
                if (junction_mod.isMarkerChar(below)) {
                    buffer.set(x, y + 1, CP_V_LINE);
                }
            }
        }
    }

    // Paint edge labels (between edges and nodes)
    var legend_edges: std.ArrayListUnmanaged(LegendEntry) = .{};
    defer legend_edges.deinit(allocator);

    for (layout_ir.getEdges()) |edge| {
        if (edge.label) |label| {
            // Skip self-loop labels — handled after node painting with ↺ indicator
            if (edge.reversed and edge.from_id == edge.to_id) continue;

            // Resolve edge color via style function (same logic as paint loop)
            const from_label = if (layout_ir.nodeById(edge.from_id)) |n| n.label else "";
            const to_label = if (layout_ir.nodeById(edge.to_id)) |n| n.label else "";
            const ctx = EdgeStyleContext{
                .edge_index = edge.edge_index,
                .total_edges = total_edges,
                .from_id = edge.from_id,
                .to_id = edge.to_id,
                .from_label = from_label,
                .to_label = to_label,
                .label = edge.label,
                .directed = edge.directed,
                .reversed = edge.reversed,
                .arena = arena,
            };
            const style = config.edge_style_fn(ctx);
            const edge_color: u8 = if (style.color != 0)
                style.color
            else if (config.edge_palette) |palette|
                colors.getAnsi(palette, edge.edge_index)
            else
                0;

            if (label_render.canPlaceLabel(&buffer, label, edge.label_x, edge.label_y)) {
                label_render.paintLabel(&buffer, label, edge.label_x, edge.label_y, edge_color);
            } else {
                // Couldn't place — try sliding Y within the edge's vertical span
                var placed = false;
                const min_y = edge.from_y + 1;
                const max_y = if (edge.to_y > 1) edge.to_y - 1 else edge.to_y;
                var try_y = min_y;
                while (try_y <= max_y) : (try_y += 1) {
                    if (try_y == edge.label_y) continue; // Already tried
                    if (label_render.canPlaceLabel(&buffer, label, edge.label_x, try_y)) {
                        label_render.paintLabel(&buffer, label, edge.label_x, try_y, edge_color);
                        placed = true;
                        break;
                    }
                }
                if (!placed) {
                    // Fallback: add to legend
                    try legend_edges.append(allocator, .{
                        .from_id = edge.from_id,
                        .to_id = edge.to_id,
                        .label = label,
                        .color = edge_color,
                    });
                }
            }
        }
    }

    // Paint nodes (overwrite edges)
    for (layout_ir.getNodes()) |node| {
        if (node.kind == .dummy) {
            node_render.paintNode(&buffer, &node, config.show_dummy_nodes, .{});
        } else {
            const node_ctx = NodeStyleContext{
                .node_id = node.id,
                .label = node.label,
                .total_nodes = total_nodes,
                .width = node.width,
                .height = 1,
                .is_implicit = node.kind == .implicit,
                .arena = arena,
            };
            const node_style = config.node_style_fn(node_ctx);
            node_render.paintNode(&buffer, &node, config.show_dummy_nodes, node_style);
        }
    }

    // Paint subgraph labels last so they're not overwritten by edges/nodes
    if (config.show_subgraphs) {
        subgraph_render.paintSubgraphLabels(&buffer, layout_ir);
    }

    // Paint self-loop indicators (↺) after nodes
    for (layout_ir.getEdges()) |edge| {
        if (edge.reversed and edge.from_id == edge.to_id) {
            const from_label = if (layout_ir.nodeById(edge.from_id)) |n| n.label else "";
            const sl_ctx = EdgeStyleContext{
                .edge_index = edge.edge_index,
                .total_edges = total_edges,
                .from_id = edge.from_id,
                .to_id = edge.to_id,
                .from_label = from_label,
                .to_label = from_label,
                .label = edge.label,
                .directed = edge.directed,
                .reversed = edge.reversed,
                .arena = arena,
            };
            const sl_style = config.edge_style_fn(sl_ctx);
            const edge_color: u8 = if (sl_style.color != 0)
                sl_style.color
            else if (config.edge_palette) |palette|
                colors.getAnsi(palette, edge.edge_index)
            else
                0;

            if (layout_ir.nodeById(edge.from_id)) |node| {
                const loop_x = node.x + node.width; // right after ']'
                const loop_y = node.y;
                buffer.setWithColor(loop_x, loop_y, 0x21BA, edge_color); // ↺
                if (edge.label) |label| {
                    label_render.paintLabel(&buffer, label, loop_x + 1, loop_y, edge_color);
                }
            }
        }
    }

    // Convert to UTF-8 string with optional ANSI color escapes
    var output: std.ArrayListUnmanaged(u8) = .{};
    errdefer output.deinit(allocator);
    try output.ensureTotalCapacity(allocator, height * (width * 4 + 1));

    var last_color: u8 = 0;

    for (0..height) |y| {
        const row = buffer.getRow(y);
        const color_row = buffer.getColorRow(y);

        // Trim trailing spaces
        var end: usize = row.len;
        while (end > 0 and row[end - 1] == ' ') {
            end -= 1;
        }

        // Encode each character with optional color
        for (row[0..end], color_row[0..end]) |codepoint, cell_color| {
            if (cell_color != 0 and cell_color != last_color) {
                const seq = colors.escape.fg256(cell_color);
                try output.appendSlice(allocator, &seq);
                last_color = cell_color;
            } else if (cell_color == 0 and last_color != 0) {
                try output.appendSlice(allocator, colors.escape.reset);
                last_color = 0;
            }

            var buf: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(codepoint, &buf) catch 1;
            try output.appendSlice(allocator, buf[0..len]);
        }

        if (last_color != 0) {
            try output.appendSlice(allocator, colors.escape.reset);
            last_color = 0;
        }

        try output.append(allocator, '\n');
    }

    // Append legend for labels that couldn't be placed inline
    if (legend_edges.items.len > 0) {
        try output.appendSlice(allocator, "\nEdge labels:\n");
        for (legend_edges.items) |entry| {
            try output.appendSlice(allocator, "  ");

            const from_label = if (layout_ir.nodeById(entry.from_id)) |n| n.label else "?";
            const to_label = if (layout_ir.nodeById(entry.to_id)) |n| n.label else "?";

            if (entry.color != 0) {
                const seq = colors.escape.fg256(entry.color);
                try output.appendSlice(allocator, &seq);
            }

            try output.appendSlice(allocator, from_label);
            try output.appendSlice(allocator, " → ");
            try output.appendSlice(allocator, to_label);
            try output.appendSlice(allocator, ": \"");
            try output.appendSlice(allocator, entry.label);
            try output.appendSlice(allocator, "\"");

            if (entry.color != 0) {
                try output.appendSlice(allocator, colors.escape.reset);
            }
            try output.append(allocator, '\n');
        }
    }

    return output.toOwnedSlice(allocator);
}
