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

// ── Submodule imports ───────────────────────────────────────────────────────

const config_mod = @import("config.zig");
const buffer_mod = @import("buffer.zig");
const junction_mod = @import("junctions.zig");
const node_render = @import("nodes.zig");
const edge_render = @import("edges.zig");
const label_render = @import("labels.zig");
const subgraph_render = @import("subgraphs.zig");
const plan_mod = @import("plan.zig");

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
pub const CharSet = config_mod.CharSet;
pub const OutputFormat = config_mod.OutputFormat;
pub const CellColor = config_mod.CellColor;
pub const resolveColor = config_mod.resolveColor;
pub const resolveColorAt = config_mod.resolveColorAt;
pub const TerminalEdgeStyle = config_mod.TerminalEdgeStyle;
pub const TerminalNodeStyle = config_mod.TerminalNodeStyle;
pub const NodePaintContext = config_mod.NodePaintContext;
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
pub const toAscii = junction_mod.toAscii;
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
pub const EdgeColor = edge_render.EdgeColor;
pub const paintNode = node_render.paintNode;
pub const paintSubgraphBox = subgraph_render.paintSubgraphBox;
pub const paintSubgraphLabel = subgraph_render.paintSubgraphLabel;
pub const canPlaceLabel = label_render.canPlaceLabel;
pub const paintLabel = label_render.paintLabel;
pub const drawDirectVertical = edge_render.drawDirectVertical;
pub const drawDirectHorizontal = edge_render.drawDirectHorizontal;
pub const drawDirectManhattan = edge_render.drawDirectManhattan;

pub const RenderPlan = plan_mod.RenderPlan;
pub const NodePlan = plan_mod.NodePlan;
pub const HitResult = plan_mod.HitResult;

// ── Force test inclusion for submodules ─────────────────────────────────────

comptime {
    _ = config_mod;
    _ = buffer_mod;
    _ = junction_mod;
    _ = node_render;
    _ = edge_render;
    _ = label_render;
    _ = subgraph_render;
    _ = plan_mod;
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
    var list = std.Io.Writer.Allocating.init(allocator);
    errdefer list.deinit();
    try renderGenericStreamingWithConfig(Coord, layout_ir, &list.writer, allocator, config);
    return list.toOwnedSlice();
}

/// Stream-render any GenericLayoutIR to a writer.
pub fn renderGenericStreamingWithConfig(comptime Coord: type, layout_ir: *const ir_mod.LayoutIR(Coord), writer: anytype, allocator: Allocator, config: Config) !void {
    if (Coord == usize) {
        return renderStreamingWithConfig(layout_ir, writer, allocator, config);
    }
    var converted = try layout_ir.convertCoord(usize, allocator);
    defer converted.deinit();
    return renderStreamingWithConfig(&converted, writer, allocator, config);
}

/// Stream-render a LayoutIR to a writer with default config.
pub fn renderStreaming(layout_ir: *const LayoutIR, writer: anytype, allocator: Allocator) !void {
    return renderStreamingWithConfig(layout_ir, writer, allocator, .{});
}

/// Render a LayoutIR to a Unicode string.
pub fn render(layout_ir: *const LayoutIR, allocator: Allocator) ![]u8 {
    return renderWithConfig(layout_ir, allocator, .{});
}

/// Render a LayoutIR to a Unicode string with configuration.
pub fn renderWithConfig(layout_ir: *const LayoutIR, allocator: Allocator, config: Config) ![]u8 {
    var list = std.Io.Writer.Allocating.init(allocator);
    errdefer list.deinit();
    try renderStreamingWithConfig(layout_ir, &list.writer, allocator, config);
    return list.toOwnedSlice();
}

/// Serialize a Buffer2D to a writer using the `.raw` terminal format.
///
/// Useful for custom rendering pipelines: build your RenderPlan, allocate and
/// paint a Buffer2D (possibly larger than the plan height), then call this to
/// produce ANSI-colored terminal output.
///
/// `render_height` is the number of rows to emit. Pass `buffer.height` for
/// the full buffer. Values exceeding `buffer.height` are capped automatically.
pub fn serializeBuffer(buffer: *const Buffer2D, writer: anytype, config: Config, render_height: usize) !void {
    const use_ascii = config.char_set == .ascii;
    var last_fg: CellColor = CellColor.none;
    var last_bg: CellColor = CellColor.none;
    var last_attrs: TextAttrs = .{};
    const has_bg = buffer.hasBgPlane();
    const has_attrs = buffer.hasAttrsPlane();

    const safe_height = @min(render_height, buffer.height);

    for (0..safe_height) |y| {
        const row = buffer.getRow(y);
        const color_row = buffer.getColorRow(y);
        const bg_row: ?[]const CellColor = if (has_bg) buffer.getBgColorRow(y) else null;
        const attrs_row: ?[]const TextAttrs = if (has_attrs) buffer.getAttrsRow(y) else null;

        var end: usize = row.len;
        while (end > 0 and row[end - 1] == ' ') end -= 1;

        for (0..end) |xi| {
            const codepoint = if (use_ascii) junction_mod.toAscii(row[xi]) else row[xi];

            if (config.color_mode != .none) {
                const cell_fg = color_row[xi];
                const cell_bg: CellColor = if (bg_row) |bgr| bgr[xi] else CellColor.none;
                const cell_attrs: TextAttrs = if (attrs_row) |ar| ar[xi] else .{};

                // Check if attrs changed — if so, full reset + re-apply everything
                if (@as(u8, @bitCast(cell_attrs)) != @as(u8, @bitCast(last_attrs))) {
                    try writer.writeAll(colors.escape.reset);
                    last_fg = CellColor.none;
                    last_bg = CellColor.none;
                    last_attrs = cell_attrs;
                    if (@as(u8, @bitCast(cell_attrs)) != 0) {
                        try emitAttrsEscape(writer, cell_attrs);
                    }
                    // Re-emit colors after reset
                    if (cell_fg.isSet()) {
                        try emitFgEscape(writer, cell_fg, config.color_mode);
                        last_fg = cell_fg;
                    }
                    if (cell_bg.isSet()) {
                        try emitBgEscape(writer, cell_bg, config.color_mode);
                        last_bg = cell_bg;
                    }
                } else {
                    // Attrs unchanged — handle fg/bg transitions normally
                    if (cell_fg.isSet() and !cellColorEql(cell_fg, last_fg)) {
                        try emitFgEscape(writer, cell_fg, config.color_mode);
                        last_fg = cell_fg;
                    } else if (!cell_fg.isSet() and last_fg.isSet()) {
                        try writer.writeAll(colors.escape.reset);
                        last_fg = CellColor.none;
                        last_bg = CellColor.none;
                        last_attrs = .{};
                    }

                    if (cell_bg.isSet() and !cellColorEql(cell_bg, last_bg)) {
                        try emitBgEscape(writer, cell_bg, config.color_mode);
                        last_bg = cell_bg;
                    } else if (!cell_bg.isSet() and last_bg.isSet()) {
                        try writer.writeAll("\x1b[49m");
                        last_bg = CellColor.none;
                    }
                }
            }

            var enc_buf: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(codepoint, &enc_buf) catch 1;
            try writer.writeAll(enc_buf[0..len]);
        }

        if (config.color_mode != .none and (last_fg.isSet() or last_bg.isSet() or @as(u8, @bitCast(last_attrs)) != 0)) {
            try writer.writeAll(colors.escape.reset);
            last_fg = CellColor.none;
            last_bg = CellColor.none;
            last_attrs = .{};
        }

        try writer.writeByte('\n');
    }
}

/// Streaming render entry point — writes directly to any writer (zero accumulation).
pub fn renderStreamingWithConfig(layout_ir: *const LayoutIR, writer: anytype, allocator: Allocator, config: Config) !void {
    const base_width = layout_ir.getWidth();
    const ir_height = layout_ir.getHeight();

    if (base_width == 0 or ir_height == 0) return;

    // ── Step 1: Build render plan ───────────────────────────────────────
    var plan = try plan_mod.RenderPlan.build(allocator, layout_ir, config);
    defer plan.deinit();

    const width = plan.width;
    const height = plan.height;

    // ── Step 2: Allocate band buffer (full height for 9a) ───────────────
    var buffer = try Buffer2D.init(allocator, width, height);
    defer buffer.deinit(allocator);

    // ── Step 3: Composite from plan in Z-order ─────────────────────────

    // Z0: Paint subgraph boxes (background layer)
    for (plan.subgraph_plans) |sp| {
        subgraph_render.paintSubgraphBox(&buffer, sp.x, sp.y, sp.w, sp.h, sp.style);
    }

    // Z1: Paint edges
    for (plan.edge_plans) |ep| {
        edge_render.paintEdge(&buffer, &ep.edge, ep.style_color, ep.weight, ep.marker_end, ep.marker_start);
    }

    // Z2: Dummy node cleanup
    for (plan.dummy_fixes) |df| {
        const x = df.center_x;
        const y = df.rendered_y;
        const lh = df.level_height;

        // Propagate edge color from adjacent cells (above or below the band).
        // Edge painting (Z1) doesn't cover the dummy's level band, so cells
        // within the band would otherwise remain colorless.
        const edge_color = blk: {
            if (y > 0) {
                const c = buffer.getColor(x, y - 1);
                if (c.isSet()) break :blk c;
            }
            if (y + lh < height) {
                const c = buffer.getColor(x, y + lh);
                if (c.isSet()) break :blk c;
            }
            break :blk CellColor.none;
        };

        var dy: usize = 0;
        while (dy < lh) : (dy += 1) {
            const row = y + dy;
            if (row < height) {
                const current = buffer.get(x, row);
                const merged = junction_mod.mergeJunction(current, true, true, false, false);
                if (edge_color.isSet()) {
                    buffer.setWithColor(x, row, merged, edge_color);
                } else {
                    buffer.set(x, row, merged);
                }
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

    // Z3: Paint edge labels (plan-driven placement from geometric occupancy)
    for (plan.label_plans) |lp| {
        switch (lp.placement) {
            .placed => |pos| {
                label_render.paintLabel(&buffer, lp.label, pos.x, pos.y, lp.color, lp.attrs);
            },
            .legend => {}, // legend entries handled below
        }
    }

    // Z4: Paint nodes
    const nodes = layout_ir.getNodes();
    for (plan.node_plans) |np| {
        const node = &nodes[np.node_index];
        node_render.paintNode(&buffer, node, config.show_dummy_nodes, np.style, np.rendered_y, np.level_height);
    }

    // Z5: Paint subgraph labels
    for (plan.subgraph_plans) |sp| {
        subgraph_render.paintSubgraphLabel(&buffer, sp.x, sp.y, sp.w, sp.h, sp.label, sp.style);
    }

    // Z6: Paint self-loop indicators
    for (plan.self_loops) |sl| {
        buffer.setWithColor(sl.loop_x, sl.label_row, 0x21BA, sl.color); // ↺
        if (sl.label) |elabel| {
            label_render.paintLabel(&buffer, elabel, sl.loop_x + 1, sl.label_row, sl.color, .{});
        }
    }

    // ── Step 4: Serialize buffer → writer ──────────────────────────────
    const use_ascii = config.char_set == .ascii;

    switch (config.output_format) {
        .raw => {
            var last_fg: CellColor = CellColor.none;
            var last_bg: CellColor = CellColor.none;
            var last_attrs: TextAttrs = .{};
            const has_bg = buffer.hasBgPlane();
            const has_attrs_plane = buffer.hasAttrsPlane();

            for (0..height) |y| {
                const row = buffer.getRow(y);
                const color_row = buffer.getColorRow(y);
                const bg_row: ?[]const CellColor = if (has_bg) buffer.getBgColorRow(y) else null;
                const attrs_row: ?[]const TextAttrs = if (has_attrs_plane) buffer.getAttrsRow(y) else null;

                var end: usize = row.len;
                while (end > 0 and row[end - 1] == ' ') {
                    end -= 1;
                }

                for (0..end) |xi| {
                    const codepoint = if (use_ascii) junction_mod.toAscii(row[xi]) else row[xi];

                    if (config.color_mode != .none) {
                        const cell_fg = color_row[xi];
                        const cell_bg: CellColor = if (bg_row) |bgr| bgr[xi] else CellColor.none;
                        const cell_attrs: TextAttrs = if (attrs_row) |ar| ar[xi] else .{};

                        if (@as(u8, @bitCast(cell_attrs)) != @as(u8, @bitCast(last_attrs))) {
                            try writer.writeAll(colors.escape.reset);
                            last_fg = CellColor.none;
                            last_bg = CellColor.none;
                            last_attrs = cell_attrs;
                            if (@as(u8, @bitCast(cell_attrs)) != 0) {
                                try emitAttrsEscape(writer, cell_attrs);
                            }
                            if (cell_fg.isSet()) {
                                try emitFgEscape(writer, cell_fg, config.color_mode);
                                last_fg = cell_fg;
                            }
                            if (cell_bg.isSet()) {
                                try emitBgEscape(writer, cell_bg, config.color_mode);
                                last_bg = cell_bg;
                            }
                        } else {
                            if (cell_fg.isSet() and !cellColorEql(cell_fg, last_fg)) {
                                try emitFgEscape(writer, cell_fg, config.color_mode);
                                last_fg = cell_fg;
                            } else if (!cell_fg.isSet() and last_fg.isSet()) {
                                try writer.writeAll(colors.escape.reset);
                                last_fg = CellColor.none;
                                last_bg = CellColor.none;
                                last_attrs = .{};
                            }

                            if (cell_bg.isSet() and !cellColorEql(cell_bg, last_bg)) {
                                try emitBgEscape(writer, cell_bg, config.color_mode);
                                last_bg = cell_bg;
                            } else if (!cell_bg.isSet() and last_bg.isSet()) {
                                try writer.writeAll("\x1b[49m");
                                last_bg = CellColor.none;
                            }
                        }
                    }

                    var buf: [4]u8 = undefined;
                    const len = std.unicode.utf8Encode(codepoint, &buf) catch 1;
                    try writer.writeAll(buf[0..len]);
                }

                if (config.color_mode != .none and (last_fg.isSet() or last_bg.isSet() or @as(u8, @bitCast(last_attrs)) != 0)) {
                    try writer.writeAll(colors.escape.reset);
                    last_fg = CellColor.none;
                    last_bg = CellColor.none;
                    last_attrs = .{};
                }

                try writer.writeByte('\n');
            }

            // Legend
            try emitLegend(writer, plan.legend_entries, layout_ir, config, use_ascii);
        },
        .html_pre => {
            // Validate html_pre_style: reject characters that could break
            // out of the style attribute or inject HTML.
            for (config.html_pre_style) |c| {
                if (c == '"' or c == '<' or c == '>') return error.InvalidHtmlPreStyle;
            }
            try writer.writeAll("<pre style=\"");
            try writer.writeAll(config.html_pre_style);
            try writer.writeAll("\">\n");
            var span_open = false;
            const has_bg = buffer.hasBgPlane();
            const has_attrs_plane = buffer.hasAttrsPlane();

            for (0..height) |y| {
                const row = buffer.getRow(y);
                const color_row = buffer.getColorRow(y);
                const bg_row: ?[]const CellColor = if (has_bg) buffer.getBgColorRow(y) else null;
                const attrs_row: ?[]const TextAttrs = if (has_attrs_plane) buffer.getAttrsRow(y) else null;

                var end: usize = row.len;
                while (end > 0 and row[end - 1] == ' ') {
                    end -= 1;
                }

                for (0..end) |xi| {
                    const codepoint = if (use_ascii) junction_mod.toAscii(row[xi]) else row[xi];
                    const cell_fg = color_row[xi];
                    const cell_bg: CellColor = if (bg_row) |bgr| bgr[xi] else CellColor.none;
                    const cell_attrs: TextAttrs = if (attrs_row) |ar| ar[xi] else .{};
                    const has_style = cell_fg.isSet() or cell_bg.isSet() or @as(u8, @bitCast(cell_attrs)) != 0;

                    if (has_style) {
                        if (span_open) try writer.writeAll("</span>");
                        try writer.writeAll("<span style=\"");
                        var need_sep = false;
                        if (cell_fg.isSet()) {
                            try emitHtmlFgColor(writer, cell_fg);
                            need_sep = true;
                        }
                        if (cell_bg.isSet()) {
                            if (need_sep) try writer.writeByte(';');
                            try emitHtmlBgColor(writer, cell_bg);
                            need_sep = true;
                        }
                        if (cell_attrs.bold) {
                            if (need_sep) try writer.writeByte(';');
                            try writer.writeAll("font-weight:bold");
                            need_sep = true;
                        }
                        if (cell_attrs.italic) {
                            if (need_sep) try writer.writeByte(';');
                            try writer.writeAll("font-style:italic");
                            need_sep = true;
                        }
                        if (cell_attrs.underline) {
                            if (need_sep) try writer.writeByte(';');
                            try writer.writeAll("text-decoration:underline");
                            need_sep = true;
                        }
                        if (cell_attrs.dim) {
                            if (need_sep) try writer.writeByte(';');
                            try writer.writeAll("opacity:0.7");
                        }
                        try writer.writeAll("\">");
                        span_open = true;
                    } else if (span_open) {
                        try writer.writeAll("</span>");
                        span_open = false;
                    }

                    try emitHtmlChar(writer, codepoint);
                }

                if (span_open) {
                    try writer.writeAll("</span>");
                    span_open = false;
                }
                try writer.writeByte('\n');
            }

            // Legend
            try emitLegend(writer, plan.legend_entries, layout_ir, config, use_ascii);

            try writer.writeAll("</pre>\n");
        },
    }
}

// ── Color serialization helpers ─────────────────────────────────────────────

fn cellColorEql(a: CellColor, b: CellColor) bool {
    // Compare packed u32 representation directly for identity check
    return @as(u32, @bitCast(a)) == @as(u32, @bitCast(b));
}

/// Emit a foreground color escape sequence, adapting between ANSI 256 and
/// truecolor as needed. In `.none` mode this is a no-op.
fn emitFgEscape(writer: anytype, cc: CellColor, mode: ColorMode) !void {
    switch (mode) {
        .none => {},
        .ansi256 => switch (cc.tag) {
            .ansi => {
                const seq = colors.escape.fg256(cc.ansiIndex());
                try writer.writeAll(&seq);
            },
            .rgb => {
                // Quantize RGB → nearest ANSI 256 index
                const idx = colors.rgbToAnsi256(cc.r(), cc.g(), cc.b());
                const seq = colors.escape.fg256(idx);
                try writer.writeAll(&seq);
            },
            else => {},
        },
        .truecolor => switch (cc.tag) {
            .rgb => {
                const seq = colors.escape.fgRgb(cc.r(), cc.g(), cc.b());
                try writer.writeAll(&seq);
            },
            .ansi => {
                // Expand ANSI 256 → RGB for truecolor output
                const rgb_val = colors.ansi256ToRgb(cc.ansiIndex());
                const seq = colors.escape.fgRgb(rgb_val.r, rgb_val.g, rgb_val.b);
                try writer.writeAll(&seq);
            },
            else => {},
        },
    }
}

/// Emit a background color escape sequence, mirroring `emitFgEscape`.
fn emitBgEscape(writer: anytype, cc: CellColor, mode: ColorMode) !void {
    switch (mode) {
        .none => {},
        .ansi256 => switch (cc.tag) {
            .ansi => {
                const seq = colors.escape.bg256(cc.ansiIndex());
                try writer.writeAll(&seq);
            },
            .rgb => {
                const idx = colors.rgbToAnsi256(cc.r(), cc.g(), cc.b());
                const seq = colors.escape.bg256(idx);
                try writer.writeAll(&seq);
            },
            else => {},
        },
        .truecolor => switch (cc.tag) {
            .rgb => {
                const seq = colors.escape.bgRgb(cc.r(), cc.g(), cc.b());
                try writer.writeAll(&seq);
            },
            .ansi => {
                const rgb_val = colors.ansi256ToRgb(cc.ansiIndex());
                const seq = colors.escape.bgRgb(rgb_val.r, rgb_val.g, rgb_val.b);
                try writer.writeAll(&seq);
            },
            else => {},
        },
    }
}

/// Emit ANSI escape sequences for text attributes (bold, dim, italic, underline).
/// Each attribute is a separate SGR parameter. Called after a reset when attrs change.
fn emitAttrsEscape(writer: anytype, text_attrs: TextAttrs) !void {
    if (text_attrs.bold) try writer.writeAll("\x1b[1m");
    if (text_attrs.dim) try writer.writeAll("\x1b[2m");
    if (text_attrs.italic) try writer.writeAll("\x1b[3m");
    if (text_attrs.underline) try writer.writeAll("\x1b[4m");
}

// ── HTML serialization helpers ──────────────────────────────────────────────

/// Resolve a CellColor to (r, g, b) for CSS, converting ANSI 256 if needed.
fn cellColorToRgb(cc: CellColor) struct { r: u8, g: u8, b: u8 } {
    return switch (cc.tag) {
        .rgb => .{ .r = cc.r(), .g = cc.g(), .b = cc.b() },
        .ansi => blk: {
            const c = colors.ansi256ToRgb(cc.ansiIndex());
            break :blk .{ .r = c.r, .g = c.g, .b = c.b };
        },
        else => .{ .r = 0, .g = 0, .b = 0 }, // unreachable if caller checks isSet()
    };
}

/// Emit `color:#rrggbb` (no trailing semicolon).
fn emitHtmlFgColor(writer: anytype, cc: CellColor) !void {
    const rgb = cellColorToRgb(cc);
    var buf: [13]u8 = undefined; // "color:#rrggbb"
    const s = std.fmt.bufPrint(&buf, "color:#{x:0>2}{x:0>2}{x:0>2}", .{ rgb.r, rgb.g, rgb.b }) catch unreachable;
    try writer.writeAll(s);
}

/// Emit `background-color:#rrggbb` (no trailing semicolon).
fn emitHtmlBgColor(writer: anytype, cc: CellColor) !void {
    const rgb = cellColorToRgb(cc);
    var buf: [24]u8 = undefined; // "background-color:#rrggbb"
    const s = std.fmt.bufPrint(&buf, "background-color:#{x:0>2}{x:0>2}{x:0>2}", .{ rgb.r, rgb.g, rgb.b }) catch unreachable;
    try writer.writeAll(s);
}

/// Emit a single Unicode codepoint as HTML-safe UTF-8.
fn emitHtmlChar(writer: anytype, cp: u21) !void {
    switch (cp) {
        '<' => try writer.writeAll("&lt;"),
        '>' => try writer.writeAll("&gt;"),
        '&' => try writer.writeAll("&amp;"),
        '"' => try writer.writeAll("&quot;"),
        '\'' => try writer.writeAll("&#39;"),
        else => {
            var buf: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(cp, &buf) catch 1;
            try writer.writeAll(buf[0..len]);
        },
    }
}

/// Emit a UTF-8 string slice as HTML-safe text.
fn emitHtmlStr(writer: anytype, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '<' => try writer.writeAll("&lt;"),
            '>' => try writer.writeAll("&gt;"),
            '&' => try writer.writeAll("&amp;"),
            '"' => try writer.writeAll("&quot;"),
            '\'' => try writer.writeAll("&#39;"),
            else => try writer.writeByte(c),
        }
    }
}

/// Emit the edge-label legend section, adapting output encoding to the format.
fn emitLegend(
    writer: anytype,
    legend_items: []const LegendEntry,
    layout_ir: *const LayoutIR,
    config: Config,
    use_ascii: bool,
) !void {
    if (legend_items.len == 0) return;

    const is_html = config.output_format == .html_pre;
    try writer.writeAll("\nEdge labels:\n");

    for (legend_items) |entry| {
        try writer.writeAll("  ");
        const from_label = if (layout_ir.nodeById(entry.from_id)) |n| n.label else "?";
        const to_label = if (layout_ir.nodeById(entry.to_id)) |n| n.label else "?";

        // Color open
        if (entry.color.isSet()) {
            if (is_html) {
                try writer.writeAll("<span style=\"");
                try emitHtmlFgColor(writer, entry.color);
                try writer.writeAll("\">");
            } else if (config.color_mode != .none) {
                try emitFgEscape(writer, entry.color, config.color_mode);
            }
        }

        // Labels + arrow
        if (is_html) {
            try emitHtmlStr(writer, from_label);
            try writer.writeAll(if (use_ascii) " -&gt; " else " \xe2\x86\x92 ");
            try emitHtmlStr(writer, to_label);
            try writer.writeAll(": &quot;");
            try emitHtmlStr(writer, entry.label);
            try writer.writeAll("&quot;");
        } else {
            try writer.writeAll(from_label);
            try writer.writeAll(if (use_ascii) " -> " else " \xe2\x86\x92 ");
            try writer.writeAll(to_label);
            try writer.writeAll(": \"");
            try writer.writeAll(entry.label);
            try writer.writeAll("\"");
        }

        // Color close
        if (entry.color.isSet()) {
            if (is_html) {
                try writer.writeAll("</span>");
            } else if (config.color_mode != .none) {
                try writer.writeAll(colors.escape.reset);
            }
        }
        try writer.writeByte('\n');
    }
}
