//! Terminal renderer configuration and style types.
//!
//! Defines all style structs, enums, default style functions, presets,
//! and the `Config` struct that controls terminal rendering behaviour.

const types = @import("../types.zig");

// ── Re-exports from shared types ────────────────────────────────────────────

pub const MarkerShape = types.MarkerShape;
pub const EdgeStyleContext = types.EdgeStyleContext;
pub const NodeStyleContext = types.NodeStyleContext;
pub const SubgraphStyleContext = types.SubgraphStyleContext;

// ── Terminal style types ────────────────────────────────────────────────────

/// Text attributes for terminal cells.
pub const TextAttrs = packed struct {
    bold: bool = false,
    dim: bool = false,
    italic: bool = false,
    underline: bool = false,
    _pad: u4 = 0,
};

/// Line weight for edge rendering (which box-drawing character set to use).
/// Note: `.heavy` and `.double` are defined but not yet implemented in the
/// renderer — they currently render identically to `.light`.
pub const LineWeight = enum {
    light, // ─ │ (default)
    heavy, // ━ ┃ (planned)
    double, // ═ ║ (planned)
    dashed, // ┈ ┊ (reversed edges)
};

/// Node border style.
pub const NodeBorder = enum {
    // 1-row variants
    bracket, // [label]  (explicit default)
    angle, // <label>  (implicit default)
    none, //  label

    // 3-row variants
    single_box, // ┌─┐ │ │ └─┘
    heavy_box, // ┏━┓ ┃ ┃ ┗━┛
    double_box, // ╔═╗ ║ ║ ╚═╝
    rounded_box, // ╭─╮ │ │ ╰─╯
    open_box, // ┌── │   ──┘

    pub fn height(self: NodeBorder) u8 {
        return switch (self) {
            .bracket, .angle, .none => 1,
            .single_box, .heavy_box, .double_box, .rounded_box, .open_box => 3,
        };
    }
};

/// Edge label placement strategy.
pub const LabelPlacement = enum {
    auto, // layout-computed position (default)
    near_source, // close to source node
    near_target, // close to target node
    center, // center of horizontal segment
};

/// Subgraph border style.
pub const SubgraphBorder = enum {
    single, // ┌─┐ │ │ └─┘
    double, // ╔═╗ ║ ║ ╚═╝ (default)
    heavy, // ┏━┓ ┃ ┃ ┗━┛
    dashed, // ┄ ┆ corners: ┌┐└┘
    none, // no border
};

/// Subgraph label position.
pub const LabelPosition = enum {
    top_left, // label on top border, left-aligned
    top_center, // label on top border, centered
    inside, // one row below top border (legacy behavior)
};

/// Style returned by `edge_style_fn` for each edge.
pub const TerminalEdgeStyle = struct {
    color: u8 = 0, // ANSI 256 color (0 = use palette or default)
    weight: LineWeight = .light,
    marker_end: MarkerShape = .arrow,
    marker_start: MarkerShape = .none,
};

/// Style returned by `node_style_fn` for each node.
pub const TerminalNodeStyle = struct {
    border: NodeBorder = .bracket,
    fg_color: u8 = 0,
    bg_color: u8 = 0,
    attrs: TextAttrs = .{},
};

/// Style returned by `edge_label_style_fn` for each edge label.
pub const TerminalEdgeLabelStyle = struct {
    color: u8 = 0, // 0 = follow edge color
    placement: LabelPlacement = .auto,
    attrs: TextAttrs = .{},
};

/// Style returned by `subgraph_style_fn` for each subgraph.
pub const TerminalSubgraphStyle = struct {
    border: SubgraphBorder = .double,
    color: u8 = 0,
    label_pos: LabelPosition = .top_left,
    label_attrs: TextAttrs = .{},
};

// ── Default style functions ─────────────────────────────────────────────────

pub fn defaultEdgeStyle(ctx: EdgeStyleContext) TerminalEdgeStyle {
    return .{ .weight = if (ctx.reversed) .dashed else .light };
}

pub fn defaultNodeStyle(ctx: NodeStyleContext) TerminalNodeStyle {
    return .{ .border = if (ctx.is_implicit) .angle else .bracket };
}

pub fn defaultEdgeLabelStyle(_: EdgeStyleContext) TerminalEdgeLabelStyle {
    return .{};
}

pub fn defaultSubgraphStyle(_: SubgraphStyleContext) TerminalSubgraphStyle {
    return .{};
}

// ── Subgraph style presets ──────────────────────────────────────────────────

pub const subgraph_presets = struct {
    /// Cycle border style and color by nesting depth.
    pub fn depthCycled(ctx: SubgraphStyleContext) TerminalSubgraphStyle {
        const borders = [_]SubgraphBorder{ .double, .single, .heavy, .dashed };
        const palette = [_]u8{ 33, 34, 35, 36 };
        return .{
            .border = borders[ctx.depth % borders.len],
            .color = palette[ctx.depth % palette.len],
        };
    }
};

// ── Configuration ───────────────────────────────────────────────────────────

/// Configuration for terminal rendering.
pub const Config = struct {
    /// Show dummy nodes (for debugging layout)
    show_dummy_nodes: bool = false,

    /// Show subgraph bounding boxes
    show_subgraphs: bool = true,

    /// Edge color palette (ANSI 256-color codes) — backward-compatible convenience.
    /// When set, provides default colors for edges. Overridden by edge_style_fn
    /// returning a non-zero color.
    edge_palette: ?[]const u8 = null,

    /// Per-edge style function — returns line weight, color, markers.
    edge_style_fn: *const fn (EdgeStyleContext) TerminalEdgeStyle = &defaultEdgeStyle,

    /// Per-node style function — returns border, colors, text attributes.
    node_style_fn: *const fn (NodeStyleContext) TerminalNodeStyle = &defaultNodeStyle,

    /// Per-edge-label style function — returns color, placement, text attributes.
    edge_label_style_fn: *const fn (EdgeStyleContext) TerminalEdgeLabelStyle = &defaultEdgeLabelStyle,

    /// Per-subgraph style function — returns border, color, label position.
    subgraph_style_fn: *const fn (SubgraphStyleContext) TerminalSubgraphStyle = &defaultSubgraphStyle,
};
