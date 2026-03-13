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
//!   junctions.zig    ← CP_* codepoints, mergeJunction, isDoubleBorderChar
//!   nodes.zig        ← paintNode
//!   edges.zig        ← paintEdge, drawDirectVertical/Horizontal/Manhattan
//!   labels.zig       ← LegendEntry, canPlaceLabel, paintLabel
//!   subgraphs.zig    ← paintSubgraphBox, paintSubgraphLabel
//!   render_tests.zig ← integration tests
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;
const ir_mod = @import("../../core/ir.zig");
const LayoutIR = ir_mod.LayoutIR(usize);
const colors = @import("../color/mod.zig");
const types = @import("../types.zig");
const shared_helpers = @import("../helpers.zig");

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
pub const Color = config_mod.Color;
pub const ColorMode = config_mod.ColorMode;
pub const CellColor = config_mod.CellColor;
pub const resolveColor = config_mod.resolveColor;
pub const resolveColorAt = config_mod.resolveColorAt;
pub const TerminalEdgeStyle = config_mod.TerminalEdgeStyle;
pub const TerminalNodeStyle = config_mod.TerminalNodeStyle;
pub const TerminalEdgeLabelStyle = config_mod.TerminalEdgeLabelStyle;
pub const TerminalSubgraphStyle = config_mod.TerminalSubgraphStyle;
pub const defaultEdgeStyle = config_mod.defaultEdgeStyle;
pub const defaultNodeStyle = config_mod.defaultNodeStyle;
pub const defaultEdgeLabelStyle = config_mod.defaultEdgeLabelStyle;
pub const defaultSubgraphStyle = config_mod.defaultSubgraphStyle;
pub const subgraph_presets = config_mod.subgraph_presets;
pub const node_presets = config_mod.node_presets;

pub const Buffer2D = buffer_mod.Buffer2D;
pub const LegendEntry = label_render.LegendEntry;

// Junction constants + functions (used by tests and advanced consumers)
pub const mergeJunction = junction_mod.mergeJunction;
pub const mergeJunctionWeighted = junction_mod.mergeJunctionWeighted;
pub const mergeWithDoubleLine = junction_mod.mergeWithDoubleLine;
pub const isDoubleBorderChar = junction_mod.isDoubleBorderChar;
pub const isMarkerChar = junction_mod.isMarkerChar;
pub const ArmWeight = junction_mod.ArmWeight;
pub const DirWeights = junction_mod.DirWeights;
pub const decomposeChar = junction_mod.decomposeChar;
pub const lookupChar = junction_mod.lookupChar;
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
// Heavy codepoints
pub const CP_HV_V_LINE = junction_mod.CP_HV_V_LINE;
pub const CP_HV_H_LINE = junction_mod.CP_HV_H_LINE;
pub const CP_HV_CORNER_UR = junction_mod.CP_HV_CORNER_UR;
pub const CP_HV_CORNER_UL = junction_mod.CP_HV_CORNER_UL;
pub const CP_HV_CORNER_DR = junction_mod.CP_HV_CORNER_DR;
pub const CP_HV_CORNER_DL = junction_mod.CP_HV_CORNER_DL;
pub const CP_HV_CROSS = junction_mod.CP_HV_CROSS;
// Double codepoints
pub const CP_DB_V_LINE = junction_mod.CP_DB_V_LINE;
pub const CP_DB_H_LINE = junction_mod.CP_DB_H_LINE;

// Paint functions (public for advanced usage / tests)
pub const paintEdge = edge_render.paintEdge;
pub const paintNode = node_render.paintNode;
pub const paintSubgraphBox = subgraph_render.paintSubgraphBox;
pub const paintSubgraphLabel = subgraph_render.paintSubgraphLabel;
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
    const ir_height = layout_ir.getHeight();

    if (base_width == 0 or ir_height == 0) {
        const result = try allocator.alloc(u8, 0);
        return result;
    }

    // Arena for style function contexts and coordinate tables (bulk-freed at end)
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const total_edges = layout_ir.getEdges().len;
    const total_nodes = layout_ir.getNodes().len;

    // ── Y-expansion: compute per-level max rendered height ──────────────

    // Find max level index and collect per-level info
    var max_level: usize = 0;
    for (layout_ir.getNodes()) |node| {
        if (node.level > max_level) max_level = node.level;
    }
    const num_levels = max_level + 1;

    const level_ir_ys = try arena.alloc(usize, num_levels);
    const level_max_height = try arena.alloc(usize, num_levels);
    @memset(level_ir_ys, 0);
    @memset(level_max_height, 1);

    // Pass 1: collect level Y positions and max rendered heights
    for (layout_ir.getNodes()) |node| {
        level_ir_ys[node.level] = node.y;
        if (node.kind == .dummy) continue;
        const node_ctx = NodeStyleContext{
            .node_id = node.id,
            .label = node.label,
            .total_nodes = total_nodes,
            .width = node.width,
            .height = 1,
            .is_implicit = node.kind == .implicit,
            .arena = arena,
        };
        const ns = config.node_style_fn(node_ctx);
        const h: usize = ns.border.height();
        if (h > level_max_height[node.level]) level_max_height[node.level] = h;
    }

    // Build cumulative extra rows: cumulative_extra[L] = total extra rows from levels 0..L-1
    const cumulative_extra = try arena.alloc(usize, num_levels + 1);
    cumulative_extra[0] = 0;
    for (0..num_levels) |l| {
        cumulative_extra[l + 1] = cumulative_extra[l] + (level_max_height[l] -| 1);
    }
    const total_extra = cumulative_extra[num_levels];
    const height = ir_height + total_extra;

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

    // ── Paint subgraph boxes first (background layer) ───────────────────
    const sg_depths: []const usize = if (config.show_subgraphs and layout_ir.subgraphs.items.len > 0)
        shared_helpers.computeSubgraphDepths(layout_ir.subgraphs.items, arena)
    else
        &.{};

    // Pre-compute styles once per subgraph (avoids calling style_fn twice per SG).
    const sg_styles: []const config_mod.TerminalSubgraphStyle = if (config.show_subgraphs and layout_ir.subgraphs.items.len > 0) blk: {
        const sgs = layout_ir.subgraphs.items;
        const styles = arena.alloc(config_mod.TerminalSubgraphStyle, sgs.len) catch break :blk &.{};
        for (sgs, 0..) |sg, idx| {
            styles[idx] = config.subgraph_style_fn(.{
                .subgraph_id = sg.id,
                .parent_id = sg.parent_id,
                .label = sg.label,
                .depth = if (idx < sg_depths.len) sg_depths[idx] else 0,
                .total_subgraphs = sgs.len,
                .width = sg.width,
                .height = sg.height,
                .arena = arena,
            });
        }
        break :blk styles;
    } else &.{};

    if (config.show_subgraphs) {
        const sgs = layout_ir.subgraphs.items;
        if (sgs.len > 0) {
            // Render in reverse order: parents first (they appear last in the array)
            var idx: usize = sgs.len;
            while (idx > 0) {
                idx -= 1;
                const sg = sgs[idx];
                const sg_style = if (idx < sg_styles.len) sg_styles[idx] else config_mod.TerminalSubgraphStyle{};
                const new_y = if (total_extra == 0) sg.y else yTransform(sg.y, num_levels, level_ir_ys, cumulative_extra);
                const new_h = if (total_extra == 0) sg.height else blk: {
                    const new_bottom = yTransform(sg.y + sg.height -| 1, num_levels, level_ir_ys, cumulative_extra);
                    break :blk new_bottom - new_y + 1;
                };
                subgraph_render.paintSubgraphBox(&buffer, sg.x, new_y, sg.width, new_h, sg_style);
            }
        }
    }

    // ── Paint all edges (so nodes overwrite them) ───────────────────────
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
        const edge_color: CellColor = if (style.color != .default)
            resolveColor(style.color)
        else if (config.edge_palette) |palette|
            CellColor.ansi256(colors.getAnsi(palette, edge.edge_index))
        else
            CellColor.none;

        if (total_extra == 0) {
            edge_render.paintEdge(&buffer, &edge, edge_color, style.weight, style.marker_end, style.marker_start);
        } else {
            var te = try transformEdge(edge, num_levels, level_ir_ys, cumulative_extra, arena);
            edge_render.paintEdge(&buffer, &te, edge_color, style.weight, style.marker_end, style.marker_start);
        }
    }

    // For invisible dummy nodes, paint a vertical line at their position
    // and clean up any marker characters to make a continuous line.
    // When Y-expansion is active, fill the entire level band with verticals.
    if (!config.show_dummy_nodes) {
        for (layout_ir.getNodes()) |node| {
            if (node.kind == .dummy) {
                const x = node.center_x;
                const y = yTransform(node.y, num_levels, level_ir_ys, cumulative_extra);
                const lh = level_max_height[node.level];

                // Fill the entire level band with vertical lines
                var dy: usize = 0;
                while (dy < lh) : (dy += 1) {
                    const row = y + dy;
                    if (row < height) {
                        const current = buffer.get(x, row);
                        const merged = junction_mod.mergeJunction(current, true, true, false, false);
                        buffer.set(x, row, merged);
                    }
                }

                if (y > 0) {
                    const above = buffer.get(x, y - 1);
                    if (junction_mod.isMarkerChar(above)) {
                        buffer.set(x, y - 1, CP_V_LINE);
                    }
                }
                const band_bottom = y + lh;
                if (band_bottom < height) {
                    const below = buffer.get(x, band_bottom);
                    if (junction_mod.isMarkerChar(below)) {
                        buffer.set(x, band_bottom, CP_V_LINE);
                    }
                }
            }
        }
    }

    // ── Paint edge labels (between edges and nodes) ─────────────────────
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
            const edge_color: CellColor = if (style.color != .default)
                resolveColor(style.color)
            else if (config.edge_palette) |palette|
                CellColor.ansi256(colors.getAnsi(palette, edge.edge_index))
            else
                CellColor.none;

            const lbl_y = yTransform(edge.label_y, num_levels, level_ir_ys, cumulative_extra);
            if (label_render.canPlaceLabel(&buffer, label, edge.label_x, lbl_y)) {
                label_render.paintLabel(&buffer, label, edge.label_x, lbl_y, edge_color);
            } else {
                // Couldn't place — try sliding Y within the edge's vertical span
                var placed = false;
                const t_from_y = yTransform(edge.from_y, num_levels, level_ir_ys, cumulative_extra);
                const t_to_y = yTransform(edge.to_y, num_levels, level_ir_ys, cumulative_extra);
                const min_y = t_from_y + 1;
                const max_y = if (t_to_y > 1) t_to_y - 1 else t_to_y;
                var try_y = min_y;
                while (try_y <= max_y) : (try_y += 1) {
                    if (try_y == lbl_y) continue; // Already tried
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

    // ── Paint nodes (overwrite edges) ───────────────────────────────────
    for (layout_ir.getNodes()) |node| {
        const rendered_y = yTransform(node.y, num_levels, level_ir_ys, cumulative_extra);
        const lh = level_max_height[node.level];
        if (node.kind == .dummy) {
            node_render.paintNode(&buffer, &node, config.show_dummy_nodes, .{}, rendered_y, lh);
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
            node_render.paintNode(&buffer, &node, config.show_dummy_nodes, node_style, rendered_y, lh);
        }
    }

    // Paint subgraph labels last so they're not overwritten by edges/nodes
    if (config.show_subgraphs) {
        const sgs = layout_ir.subgraphs.items;
        for (sgs, 0..) |sg, idx| {
            const sg_style = if (idx < sg_styles.len) sg_styles[idx] else config_mod.TerminalSubgraphStyle{};
            const new_y = if (total_extra == 0) sg.y else yTransform(sg.y, num_levels, level_ir_ys, cumulative_extra);
            const new_h = if (total_extra == 0) sg.height else blk: {
                const new_bottom = yTransform(sg.y + sg.height -| 1, num_levels, level_ir_ys, cumulative_extra);
                break :blk new_bottom - new_y + 1;
            };
            subgraph_render.paintSubgraphLabel(&buffer, sg.x, new_y, sg.width, new_h, sg.label, sg_style);
        }
    }

    // ── Paint self-loop indicators (↺) after nodes ──────────────────────
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
            const edge_color: CellColor = if (sl_style.color != .default)
                resolveColor(sl_style.color)
            else if (config.edge_palette) |palette|
                CellColor.ansi256(colors.getAnsi(palette, edge.edge_index))
            else
                CellColor.none;

            if (layout_ir.nodeById(edge.from_id)) |node| {
                const loop_x = node.x + node.width; // right after ']'
                const loop_y = yTransform(node.y, num_levels, level_ir_ys, cumulative_extra);
                // For 3-row nodes, place ↺ on the label row (middle)
                const node_ctx = NodeStyleContext{
                    .node_id = node.id,
                    .label = node.label,
                    .total_nodes = total_nodes,
                    .width = node.width,
                    .height = 1,
                    .is_implicit = node.kind == .implicit,
                    .arena = arena,
                };
                const ns = config.node_style_fn(node_ctx);
                const label_row = if (ns.border.height() == 3) loop_y + 1 else loop_y;
                buffer.setWithColor(loop_x, label_row, 0x21BA, edge_color); // ↺
                if (edge.label) |elabel| {
                    label_render.paintLabel(&buffer, elabel, loop_x + 1, label_row, edge_color);
                }
            }
        }
    }

    // Convert to UTF-8 string with optional ANSI color escapes
    var output: std.ArrayListUnmanaged(u8) = .{};
    errdefer output.deinit(allocator);
    try output.ensureTotalCapacity(allocator, height * (width * 4 + 1));

    var last_fg: CellColor = CellColor.none;
    var last_bg: CellColor = CellColor.none;
    const has_bg = buffer.hasBgPlane();

    for (0..height) |y| {
        const row = buffer.getRow(y);
        const color_row = buffer.getColorRow(y);
        const bg_row: ?[]const CellColor = if (has_bg) buffer.getBgColorRow(y) else null;

        // Trim trailing spaces
        var end: usize = row.len;
        while (end > 0 and row[end - 1] == ' ') {
            end -= 1;
        }

        // Encode each character with optional fg + bg color
        for (0..end) |xi| {
            const codepoint = row[xi];

            if (config.color_mode != .none) {
                const cell_fg = color_row[xi];
                const cell_bg: CellColor = if (bg_row) |bgr| bgr[xi] else CellColor.none;

                // Foreground escape
                if (cell_fg.isSet() and !cellColorEql(cell_fg, last_fg)) {
                    try emitFgEscape(&output, allocator, cell_fg, config.color_mode);
                    last_fg = cell_fg;
                } else if (!cell_fg.isSet() and last_fg.isSet()) {
                    try output.appendSlice(allocator, colors.escape.reset);
                    last_fg = CellColor.none;
                    last_bg = CellColor.none; // reset clears both
                }

                // Background escape
                if (cell_bg.isSet() and !cellColorEql(cell_bg, last_bg)) {
                    try emitBgEscape(&output, allocator, cell_bg, config.color_mode);
                    last_bg = cell_bg;
                } else if (!cell_bg.isSet() and last_bg.isSet()) {
                    // Need to clear bg without resetting fg — use bg default
                    try output.appendSlice(allocator, "\x1b[49m");
                    last_bg = CellColor.none;
                }
            }

            var buf: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(codepoint, &buf) catch 1;
            try output.appendSlice(allocator, buf[0..len]);
        }

        if (config.color_mode != .none and (last_fg.isSet() or last_bg.isSet())) {
            try output.appendSlice(allocator, colors.escape.reset);
            last_fg = CellColor.none;
            last_bg = CellColor.none;
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

            if (config.color_mode != .none and entry.color.isSet()) {
                try emitFgEscape(&output, allocator, entry.color, config.color_mode);
            }

            try output.appendSlice(allocator, from_label);
            try output.appendSlice(allocator, " → ");
            try output.appendSlice(allocator, to_label);
            try output.appendSlice(allocator, ": \"");
            try output.appendSlice(allocator, entry.label);
            try output.appendSlice(allocator, "\"");

            if (config.color_mode != .none and entry.color.isSet()) {
                try output.appendSlice(allocator, colors.escape.reset);
            }
            try output.append(allocator, '\n');
        }
    }

    return output.toOwnedSlice(allocator);
}

// ── Color serialization helpers ─────────────────────────────────────────────

fn cellColorEql(a: CellColor, b: CellColor) bool {
    // Compare packed u32 representation directly for identity check
    return @as(u32, @bitCast(a)) == @as(u32, @bitCast(b));
}

/// Emit a foreground color escape sequence, adapting between ANSI 256 and
/// truecolor as needed. In `.none` mode this is a no-op.
fn emitFgEscape(output: *std.ArrayListUnmanaged(u8), allocator: Allocator, cc: CellColor, mode: ColorMode) !void {
    switch (mode) {
        .none => {},
        .ansi256 => switch (cc.tag) {
            .ansi => {
                const seq = colors.escape.fg256(cc.ansiIndex());
                try output.appendSlice(allocator, &seq);
            },
            .rgb => {
                // Quantize RGB → nearest ANSI 256 index
                const idx = colors.rgbToAnsi256(cc.r(), cc.g(), cc.b());
                const seq = colors.escape.fg256(idx);
                try output.appendSlice(allocator, &seq);
            },
            else => {},
        },
        .truecolor => switch (cc.tag) {
            .rgb => {
                const seq = colors.escape.fgRgb(cc.r(), cc.g(), cc.b());
                try output.appendSlice(allocator, &seq);
            },
            .ansi => {
                // Expand ANSI 256 → RGB for truecolor output
                const rgb_val = colors.ansi256ToRgb(cc.ansiIndex());
                const seq = colors.escape.fgRgb(rgb_val.r, rgb_val.g, rgb_val.b);
                try output.appendSlice(allocator, &seq);
            },
            else => {},
        },
    }
}

/// Emit a background color escape sequence, mirroring `emitFgEscape`.
fn emitBgEscape(output: *std.ArrayListUnmanaged(u8), allocator: Allocator, cc: CellColor, mode: ColorMode) !void {
    switch (mode) {
        .none => {},
        .ansi256 => switch (cc.tag) {
            .ansi => {
                const seq = colors.escape.bg256(cc.ansiIndex());
                try output.appendSlice(allocator, &seq);
            },
            .rgb => {
                const idx = colors.rgbToAnsi256(cc.r(), cc.g(), cc.b());
                const seq = colors.escape.bg256(idx);
                try output.appendSlice(allocator, &seq);
            },
            else => {},
        },
        .truecolor => switch (cc.tag) {
            .rgb => {
                const seq = colors.escape.bgRgb(cc.r(), cc.g(), cc.b());
                try output.appendSlice(allocator, &seq);
            },
            .ansi => {
                const rgb_val = colors.ansi256ToRgb(cc.ansiIndex());
                const seq = colors.escape.bgRgb(rgb_val.r, rgb_val.g, rgb_val.b);
                try output.appendSlice(allocator, &seq);
            },
            else => {},
        },
    }
}

// ── Y-expansion helpers ─────────────────────────────────────────────────────

const EdgePath = ir_mod.EdgePath(usize);
const LayoutEdge = ir_mod.LayoutEdge(usize);

/// Map an IR Y coordinate to the rendered Y coordinate, accounting for
/// level expansion from 3-row node borders.
///
/// For a Y that sits exactly at a level's IR position, the offset is the
/// cumulative expansion from all *previous* levels. For a Y in a gap between
/// levels, the offset includes the expansion from the level above the gap.
fn yTransform(ir_y: usize, num_levels: usize, level_ir_ys: []const usize, cumulative_extra: []const usize) usize {
    // Find the last level whose Y <= ir_y
    var l: usize = 0;
    while (l < num_levels and level_ir_ys[l] <= ir_y) : (l += 1) {}
    // l = first level with Y > ir_y (or num_levels)
    if (l == 0) return ir_y; // Before the first level — no expansion
    l -= 1;
    if (ir_y == level_ir_ys[l]) {
        // Exactly at this level
        return ir_y + cumulative_extra[l];
    } else {
        // In the gap after level l — include l's expansion
        return ir_y + cumulative_extra[l + 1];
    }
}

/// Create a stack copy of an edge with all Y coordinates transformed.
/// The path union is copied by value (slices point at original data).
/// For multi_segment paths, waypoints are cloned with transformed Y values.
fn transformEdge(edge: LayoutEdge, num_levels: usize, level_ir_ys: []const usize, cumulative_extra: []const usize, arena: Allocator) !LayoutEdge {
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
            const wp = try arena.alloc(EdgePath.Waypoint, ms.waypoints.items.len);
            for (ms.waypoints.items, 0..) |pt, i| {
                wp[i] = .{ .x = pt.x, .y = yTransform(pt.y, num_levels, level_ir_ys, cumulative_extra) };
            }
            // Replace the waypoints slice in the copy with the transformed version.
            // We can't directly reassign the ArrayListUnmanaged, so we overwrite
            // items pointer and len via the underlying structure.
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
