//! Terminal renderer configuration and style types.
//!
//! Defines all style structs, enums, default style functions, presets,
//! and the `Config` struct that controls terminal rendering behaviour.
//!
//! ## Color architecture
//!
//! Three layers separate user intent from buffer storage from output encoding:
//!
//! - `Color` (user API) — tagged union returned by style functions
//! - `CellColor` (buffer storage) — packed u32 per cell, holds tag + ANSI/RGB payload
//! - `ColorMode` (output encoding) — determines ANSI escape format at serialization
//!
//! Style functions return `Color`. The renderer resolves it to `CellColor` via
//! `resolveColor()` and stores it in the buffer. At serialization time, `ColorMode`
//! determines whether to emit ANSI 256 or truecolor escape sequences.

const types = @import("../types.zig");
const colormaps = @import("../color/colormaps.zig");

// ── Re-exports from shared types ────────────────────────────────────────────

pub const MarkerShape = types.MarkerShape;
pub const EdgeStyleContext = types.EdgeStyleContext;
pub const NodeStyleContext = types.NodeStyleContext;
pub const SubgraphStyleContext = types.SubgraphStyleContext;

// ── Color system ────────────────────────────────────────────────────────────

/// Output color encoding mode. Determines which ANSI escape sequences the
/// serializer emits. Does not affect buffer storage (always `CellColor`).
pub const ColorMode = enum {
    none, // no color output (piping, CI logs, plain text)
    ansi256, // \e[38;5;{n}m — broad terminal compatibility
    truecolor, // \e[38;2;R;G;Bm — modern terminals
};

/// User-facing color specification returned by style functions.
/// Converted to `CellColor` at buffer-write time via `resolveColor()`.
pub const Color = union(enum) {
    default, // terminal default (no escape emitted)
    ansi256: u8, // ANSI 256 index (0-255)
    rgb: Rgb, // 24-bit true color
    gradient: GradientSpec, // per-cell color from a colormap (resolved in Topic 9)

    pub const Rgb = struct { r: u8, g: u8, b: u8 };
};

/// Gradient specification — references a colormap and a range within it.
/// Actual per-cell sampling is deferred to the plan+single-pass pipeline (Topic 9).
/// Currently resolves to `.default` (no color).
pub const GradientSpec = struct {
    map: *const colormaps.ColorMap,
    from: f32 = 0.0,
    to: f32 = 1.0,
};

/// Compact per-cell color storage. Packed into 4 bytes.
///
/// The tag distinguishes default (no color), ANSI 256 index, or 24-bit RGB.
/// Painters pass this value opaquely to `Buffer2D.setWithColor()`.
pub const CellColor = packed struct(u32) {
    payload: u24 = 0,
    tag: Tag = .default,
    _pad: u6 = 0,

    pub const Tag = enum(u2) { default = 0, ansi = 1, rgb = 2, _reserved = 3 };

    /// No color (terminal default foreground).
    pub const none: CellColor = .{};

    /// Construct from an ANSI 256 palette index.
    pub fn ansi256(index: u8) CellColor {
        return .{ .payload = @as(u24, index), .tag = .ansi };
    }

    /// Construct from 24-bit RGB.
    pub fn rgb(r_val: u8, g_val: u8, b_val: u8) CellColor {
        return .{ .payload = @as(u24, r_val) | (@as(u24, g_val) << 8) | (@as(u24, b_val) << 16), .tag = .rgb };
    }

    pub fn isSet(self: CellColor) bool {
        return self.tag != .default;
    }

    /// Extract ANSI 256 index (valid when tag == .ansi).
    pub fn ansiIndex(self: CellColor) u8 {
        return @truncate(self.payload);
    }

    /// Extract red channel (valid when tag == .rgb).
    pub fn r(self: CellColor) u8 {
        return @truncate(self.payload);
    }

    /// Extract green channel (valid when tag == .rgb).
    pub fn g(self: CellColor) u8 {
        return @truncate(self.payload >> 8);
    }

    /// Extract blue channel (valid when tag == .rgb).
    pub fn b(self: CellColor) u8 {
        return @truncate(self.payload >> 16);
    }
};

/// Convert a user-facing `Color` to compact `CellColor` for buffer storage.
pub fn resolveColor(color: Color) CellColor {
    return switch (color) {
        .default => CellColor.none,
        .ansi256 => |v| CellColor.ansi256(v),
        .rgb => |v| CellColor.rgb(v.r, v.g, v.b),
        .gradient => CellColor.none, // per-cell gradient deferred to plan+single-pass (Topic 9)
    };
}

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
/// Edge line weight. Controls the box-drawing characters used for edges
/// and how junctions merge when edges of different weights cross.
pub const LineWeight = enum {
    light, // ─ │ (default)
    heavy, // ━ ┃
    double, // ═ ║
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
    color: Color = .default,
    weight: LineWeight = .light,
    marker_end: MarkerShape = .arrow,
    marker_start: MarkerShape = .none,
};

/// Style returned by `node_style_fn` for each node.
pub const TerminalNodeStyle = struct {
    border: NodeBorder = .bracket,
    fg_color: Color = .default,
    bg_color: Color = .default,
    attrs: TextAttrs = .{},
};

/// Style returned by `edge_label_style_fn` for each edge label.
pub const TerminalEdgeLabelStyle = struct {
    color: Color = .default, // .default = follow edge color
    placement: LabelPlacement = .auto,
    attrs: TextAttrs = .{},
};

/// Style returned by `subgraph_style_fn` for each subgraph.
pub const TerminalSubgraphStyle = struct {
    border: SubgraphBorder = .double,
    color: Color = .default,
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
            .color = .{ .ansi256 = palette[ctx.depth % palette.len] },
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
    /// returning a non-default color.
    edge_palette: ?[]const u8 = null,

    /// Output color encoding mode.
    color_mode: ColorMode = .ansi256,

    /// Per-edge style function — returns line weight, color, markers.
    edge_style_fn: *const fn (EdgeStyleContext) TerminalEdgeStyle = &defaultEdgeStyle,

    /// Per-node style function — returns border, colors, text attributes.
    node_style_fn: *const fn (NodeStyleContext) TerminalNodeStyle = &defaultNodeStyle,

    /// Per-edge-label style function — returns color, placement, text attributes.
    edge_label_style_fn: *const fn (EdgeStyleContext) TerminalEdgeLabelStyle = &defaultEdgeLabelStyle,

    /// Per-subgraph style function — returns border, color, label position.
    subgraph_style_fn: *const fn (SubgraphStyleContext) TerminalSubgraphStyle = &defaultSubgraphStyle,
};
