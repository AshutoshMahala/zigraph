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

const std = @import("std");
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

/// Character set used for buffer serialization.
pub const CharSet = enum {
    unicode, // Box-drawing characters (default): ┌ ─ ┐ │ └ ┘ ├ ┤ ┬ ┴ ┼
    ascii, // ASCII fallback:                     + - + | + + + + + + +
};

/// Output serialization format.
pub const OutputFormat = enum {
    raw, // Plain text with optional ANSI escapes (terminal output)
    html_pre, // <pre> block with <span style="..."> for colors
};

/// User-facing color specification returned by style functions.
/// Converted to `CellColor` at buffer-write time via `resolveColor()`.
pub const Color = union(enum) {
    default, // terminal default (no escape emitted)
    ansi256: u8, // ANSI 256 index (0-255)
    rgb: Rgb, // 24-bit true color
    gradient: GradientSpec, // per-cell color from a colormap

    pub const Rgb = struct { r: u8, g: u8, b: u8 };
};

/// Gradient specification — references a colormap and a [from, to] range.
/// Resolved per-cell via `resolveColorAt()` during node/edge painting.
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
/// For gradients this returns `.none` — use `resolveColorAt` with a position instead.
pub fn resolveColor(color: Color) CellColor {
    return switch (color) {
        .default => CellColor.none,
        .ansi256 => |v| CellColor.ansi256(v),
        .rgb => |v| CellColor.rgb(v.r, v.g, v.b),
        .gradient => CellColor.none,
    };
}

/// Resolve a `Color` at a normalized position `t` (0.0–1.0) within a span.
/// Flat colors ignore `t`. Gradients sample the colormap at the mapped position.
pub fn resolveColorAt(color: Color, t: f32) CellColor {
    return switch (color) {
        .default => CellColor.none,
        .ansi256 => |v| CellColor.ansi256(v),
        .rgb => |v| CellColor.rgb(v.r, v.g, v.b),
        .gradient => |g| blk: {
            const mapped = g.from + (g.to - g.from) * std.math.clamp(t, 0.0, 1.0);
            const c = g.map.sample(mapped);
            const rb: u8 = @intFromFloat(@round(std.math.clamp(c.r, 0.0, 1.0) * 255.0));
            const gb: u8 = @intFromFloat(@round(std.math.clamp(c.g, 0.0, 1.0) * 255.0));
            const bb: u8 = @intFromFloat(@round(std.math.clamp(c.b, 0.0, 1.0) * 255.0));
            break :blk CellColor.rgb(rb, gb, bb);
        },
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

    // 3-row closed variants (all four corners)
    single_box, // ┌─┐ │ │ └─┘
    heavy_box, // ┏━┓ ┃ ┃ ┗━┛
    double_box, // ╔═╗ ║ ║ ╚═╝
    rounded_box, // ╭─╮ │ │ ╰─╯

    // 3-row open variants (TL + BR corners only — implicit feel)
    open_single, // ┌── │ │  ──┘
    open_heavy, // ┏━━ ┃ ┃  ━━┛
    open_double, // ╔══ ║ ║  ══╝
    open_rounded, // ╭── │ │  ──╯

    pub fn height(self: NodeBorder) u8 {
        return switch (self) {
            .bracket, .angle, .none => 1,
            .single_box,
            .heavy_box,
            .double_box,
            .rounded_box,
            .open_single,
            .open_heavy,
            .open_double,
            .open_rounded,
            => 3,
        };
    }

    /// Return the open (implicit) counterpart of a closed box style.
    /// 1-row styles return `.angle`; open styles return themselves.
    pub fn openVariant(self: NodeBorder) NodeBorder {
        return switch (self) {
            .bracket, .angle, .none => .angle,
            .single_box, .open_single => .open_single,
            .heavy_box, .open_heavy => .open_heavy,
            .double_box, .open_double => .open_double,
            .rounded_box, .open_rounded => .open_rounded,
        };
    }

    /// Return the closed (explicit) counterpart of an open box style.
    /// 1-row styles return `.bracket`; closed styles return themselves.
    pub fn closedVariant(self: NodeBorder) NodeBorder {
        return switch (self) {
            .bracket, .angle, .none => .bracket,
            .single_box, .open_single => .single_box,
            .heavy_box, .open_heavy => .heavy_box,
            .double_box, .open_double => .double_box,
            .rounded_box, .open_rounded => .rounded_box,
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
/// When `border = .none`, `.top_left` and `.top_center` paint at the top row
/// of the subgraph bounding box (the border row that is otherwise invisible).
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
///
/// Colors: `border_color` applies to box-drawing chars, `text_color` to the
/// label text, `bg_color` to the cell background behind the node. Any of
/// these can be a gradient — per-cell sampling happens automatically.
/// When `.default`, no escape is emitted (terminal default colors).
pub const TerminalNodeStyle = struct {
    border: NodeBorder = .bracket,
    border_color: Color = .default,
    text_color: Color = .default,
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
    /// Subgraph border and label color. Supports `.default`, ANSI-256, and
    /// truecolor values. `.gradient` is not yet supported in the terminal
    /// renderer and silently falls back to no color.
    color: Color = .default,
    label_pos: LabelPosition = .top_left,
    // TODO: label text attributes (bold, dim, italic, underline) — requires
    // ANSI text-attribute escape sequence support, which is not yet implemented
    // for any terminal text output (nodes, edges, or subgraphs).
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

// ── Node style presets ──────────────────────────────────────────────────────

pub const node_presets = struct {
    /// 3-row single box: explicit = ┌─┐│ │└─┘, implicit = ┌── │ │  ──┘
    pub fn singleBox(ctx: NodeStyleContext) TerminalNodeStyle {
        return .{ .border = if (ctx.is_implicit) .open_single else .single_box };
    }
    /// 3-row heavy box: explicit = ┏━┓┃ ┃┗━┛, implicit = ┏━━ ┃ ┃  ━━┛
    pub fn heavyBox(ctx: NodeStyleContext) TerminalNodeStyle {
        return .{ .border = if (ctx.is_implicit) .open_heavy else .heavy_box };
    }
    /// 3-row double box: explicit = ╔═╗║ ║╚═╝, implicit = ╔══ ║ ║  ══╝
    pub fn doubleBox(ctx: NodeStyleContext) TerminalNodeStyle {
        return .{ .border = if (ctx.is_implicit) .open_double else .double_box };
    }
    /// 3-row rounded box: explicit = ╭─╮│ │╰─╯, implicit = ╭── │ │  ──╯
    pub fn roundedBox(ctx: NodeStyleContext) TerminalNodeStyle {
        return .{ .border = if (ctx.is_implicit) .open_rounded else .rounded_box };
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

    /// Character set for output. `.ascii` maps box-drawing to ASCII equivalents.
    char_set: CharSet = .unicode,

    /// Serialization format. `.html_pre` emits styled HTML instead of ANSI escapes.
    output_format: OutputFormat = .raw,

    /// CSS style string for the `<pre>` wrapper when `output_format = .html_pre`.
    html_pre_style: []const u8 = "font-family:monospace;line-height:1.2",

    /// Per-edge style function — returns line weight, color, markers.
    edge_style_fn: *const fn (EdgeStyleContext) TerminalEdgeStyle = &defaultEdgeStyle,

    /// Per-node style function — returns border, colors, text attributes.
    node_style_fn: *const fn (NodeStyleContext) TerminalNodeStyle = &defaultNodeStyle,

    /// Per-edge-label style function — returns color, placement, text attributes.
    edge_label_style_fn: *const fn (EdgeStyleContext) TerminalEdgeLabelStyle = &defaultEdgeLabelStyle,

    /// Per-subgraph style function — returns border, color, label position.
    subgraph_style_fn: *const fn (SubgraphStyleContext) TerminalSubgraphStyle = &defaultSubgraphStyle,
};
