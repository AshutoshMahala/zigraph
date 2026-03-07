//! SVG renderer configuration.
//!
//! All rendering parameters — dimensions, colors, fonts, flags — live here.
//! Shared by all SVG submodules.
//!
//! ## Edge styling
//!
//! Edge appearance is controlled by `edge_style_fn` — a function that receives
//! per-edge context and returns visual style (color, markers, optional raw SVG).
//! The default does palette-cycling with Radix UI colors.
//!
//! ```zig
//! // Custom: red for back-edges, palette for everything else
//! fn myStyle(ctx: EdgeStyleContext) EdgeStyle {
//!     if (ctx.reversed) return .{ .stroke = "#e5484d" };
//!     return .{ .stroke = colors.get(&colors.radix, ctx.edge_index) };
//! }
//! const svg = try zigraph.svg.render(&ir, alloc, .{ .edge_style_fn = &myStyle });
//! ```

const std = @import("std");
const colors = @import("../color/mod.zig");
const types = @import("../types.zig");
const helpers = @import("helpers.zig");

pub const MarkerShape = types.MarkerShape;
pub const EdgeStyleContext = types.EdgeStyleContext;
pub const NodeStyleContext = types.NodeStyleContext;
pub const SubgraphStyleContext = types.SubgraphStyleContext;

/// What the edge style function returns — color + markers + SVG escape hatches.
///
/// Three levels of customization:
///   - `stroke`               → the color (solid hex or `url(#gradient-ref)`)
///   - `marker_end/start`     → endpoint shapes (arrow, diamond, circle, etc.)
///   - `defs` + `extra_attrs` → raw SVG injection (gradients, filters, dasharray)
///
/// Most users only need `stroke`. The defaults handle everything else.
pub const EdgeStyle = struct {
    /// Edge stroke color — hex like `"#e54d2e"` or SVG ref like `"url(#grad-3)"`.
    stroke: []const u8 = "#666666",
    /// Marker at the end of the edge path (arrowhead). `.arrow` for directed edges.
    marker_end: MarkerShape = .arrow,
    /// Marker at the start of the edge path (tail). `.none` by default.
    marker_start: MarkerShape = .none,
    /// Raw SVG injected into `<defs>` — for gradients, filters, clip paths, animations.
    defs: ?[]const u8 = null,
    /// Raw attributes added to the `<path>` element — dasharray, opacity, CSS classes.
    extra_attrs: ?[]const u8 = null,
};

/// Pre-computed rendering info for a single edge.
///
/// Created by the renderer after calling `edge_style_fn` for all edges and
/// collecting unique marker definitions. Internal to the SVG pipeline — not
/// part of the public API.
pub const ResolvedEdgeStyle = struct {
    /// Stroke color from EdgeStyle
    stroke: []const u8,
    /// Index into the unique-markers array for marker-end, or null if `.none`
    marker_end_id: ?usize,
    /// Index into the unique-markers array for marker-start, or null if `.none`
    marker_start_id: ?usize,
    /// Extra attributes for the <path> element
    extra_attrs: ?[]const u8,
};

/// Default edge style function — palette-cycling with Radix UI colors.
///
/// Equivalent to the old `color_edges = true` + `edge_palette = &colors.radix`.
/// Directed edges get filled arrowheads; undirected edges get no markers.
pub fn defaultEdgeStyle(ctx: EdgeStyleContext) EdgeStyle {
    return .{
        .stroke = colors.get(&colors.radix, ctx.edge_index),
        .marker_end = if (ctx.directed) .arrow else .none,
    };
}

/// Monochrome edge style — all edges use the same gray color.
///
/// Equivalent to the old `color_edges = false, edge_stroke = "#666666"`.
/// Use as: `.edge_style_fn = &monoEdgeStyle`
pub fn monoEdgeStyle(ctx: EdgeStyleContext) EdgeStyle {
    return .{
        .stroke = "#666666",
        .marker_end = if (ctx.directed) .arrow else .none,
    };
}

/// What the edge label style function returns — appearance and placement of edge labels.
///
/// Reuses the same `EdgeStyleContext` — labels are per-edge. All fields use
/// null/defaults to inherit from the edge style or global config:
///   - `color = null` → follows edge stroke color
///   - `font_family = null` → `"monospace"`
///   - `font_size = null` → `12`
///   - `position = 50` → centered on edge path (0 = source, 100 = target)
///   - `on_path = null` → follows global `labels_on_path` config
pub const EdgeLabelStyle = struct {
    /// Label text color. When null, inherits the edge stroke color.
    color: ?[]const u8 = null,
    /// Font family. When null, uses the renderer default ("monospace").
    font_family: ?[]const u8 = null,
    /// Font size in pixels. When null, uses the renderer default (12).
    font_size: ?usize = null,
    /// Label position along the edge path as a percentage (0–100).
    /// 0 = at source, 50 = center (default), 100 = at target.
    /// Values above 100 are clamped to 100.
    position: u8 = 50,
    /// Whether this label follows the edge path curve (`<textPath>`).
    /// When null, uses the global `labels_on_path` config.
    on_path: ?bool = null,
    /// Raw attributes added to the `<text>` (or `<textPath>`) element —
    /// CSS classes, data attrs, font-weight, opacity, onclick, etc.
    extra_attrs: ?[]const u8 = null,
};

/// Default edge label style — inherit everything from edge style + global config.
///
/// All fields are null/defaults → label color follows edge stroke, font is
/// monospace 12px, centered at 50%, placement follows global `labels_on_path`.
pub fn defaultEdgeLabelStyle(_: EdgeStyleContext) EdgeLabelStyle {
    return .{};
}

/// What the node style function returns — shape geometry + colors + SVG escape hatches.
///
/// The `shape_svg` field contains SVG geometry relative to (0,0) — including the
/// label text. The renderer wraps it in a positioned `<g>` with inherited fill/stroke.
///
/// Built-in preset functions (in the `shapes` namespace) produce standard shapes.
/// Custom functions return arbitrary SVG — the renderer can't tell the difference.
pub const NodeStyle = struct {
    /// SVG geometry relative to (0,0) — shape element(s) + label `<text>`.
    /// The renderer wraps this in `<g transform="translate(x,y)" fill=... stroke=...>`.
    /// Shape elements inherit fill/stroke from the `<g>`.
    /// Text elements should set explicit `fill` and `stroke="none"` to avoid
    /// inheriting the shape's fill color.
    shape_svg: []const u8,
    /// Shape fill color — applied on the wrapping `<g>`, inherited by shape elements.
    fill: []const u8 = "#f0f0f0",
    /// Shape stroke color — applied on the wrapping `<g>`, inherited by shape elements.
    stroke: []const u8 = "#333333",
    /// Raw SVG injected into `<defs>` — for gradients, filters, clip paths.
    defs: ?[]const u8 = null,
    /// Raw attributes added to the wrapping `<g>` element — CSS classes, data attrs.
    extra_attrs: ?[]const u8 = null,
};

/// Built-in node shape presets.
///
/// Each function takes a `NodeStyleContext` and returns a `NodeStyle` with
/// appropriate SVG geometry. Use as: `.node_style_fn = &shapes.diamond`
///
/// All presets:
/// - Render dashed borders for implicit nodes (`ctx.is_implicit`)
/// - Use monospace 12px font for labels
/// - Center text vertically and horizontally within the bounding box
/// - Set explicit `fill`/`stroke="none"` on `<text>` to prevent SVG inheritance issues
pub const shapes = struct {
    /// Rounded rectangle (default) — `<rect>` with `rx="4"`.
    pub fn rounded_rectangle(ctx: NodeStyleContext) NodeStyle {
        const dash: []const u8 = if (ctx.is_implicit) " stroke-dasharray=\"4,2\"" else "";
        const label = helpers.xmlEscape(ctx.arena, ctx.label);
        return .{ .shape_svg = std.fmt.allocPrint(ctx.arena,
            \\<rect x="0" y="0" width="{d}" height="{d}" rx="4" ry="4"{s}/>
            \\<text x="{d}" y="{d}" text-anchor="middle" font-family="monospace" font-size="12" fill="#333333" stroke="none">{s}</text>
        , .{ ctx.width, ctx.height, dash, ctx.width / 2, ctx.height / 2 + 4, label }) catch "" };
    }

    /// Sharp rectangle — `<rect>` with no corner rounding.
    pub fn rectangle(ctx: NodeStyleContext) NodeStyle {
        const dash: []const u8 = if (ctx.is_implicit) " stroke-dasharray=\"4,2\"" else "";
        const label = helpers.xmlEscape(ctx.arena, ctx.label);
        return .{ .shape_svg = std.fmt.allocPrint(ctx.arena,
            \\<rect x="0" y="0" width="{d}" height="{d}"{s}/>
            \\<text x="{d}" y="{d}" text-anchor="middle" font-family="monospace" font-size="12" fill="#333333" stroke="none">{s}</text>
        , .{ ctx.width, ctx.height, dash, ctx.width / 2, ctx.height / 2 + 4, label }) catch "" };
    }

    /// Ellipse — `<ellipse>` filling the bounding box.
    pub fn ellipse(ctx: NodeStyleContext) NodeStyle {
        const dash: []const u8 = if (ctx.is_implicit) " stroke-dasharray=\"4,2\"" else "";
        const label = helpers.xmlEscape(ctx.arena, ctx.label);
        return .{ .shape_svg = std.fmt.allocPrint(ctx.arena,
            \\<ellipse cx="{d}" cy="{d}" rx="{d}" ry="{d}"{s}/>
            \\<text x="{d}" y="{d}" text-anchor="middle" font-family="monospace" font-size="12" fill="#333333" stroke="none">{s}</text>
        , .{ ctx.width / 2, ctx.height / 2, ctx.width / 2, ctx.height / 2, dash, ctx.width / 2, ctx.height / 2 + 4, label }) catch "" };
    }

    /// Diamond — `<polygon>` rotated 45°. Good for decision nodes in flowcharts.
    pub fn diamond(ctx: NodeStyleContext) NodeStyle {
        const dash: []const u8 = if (ctx.is_implicit) " stroke-dasharray=\"4,2\"" else "";
        const label = helpers.xmlEscape(ctx.arena, ctx.label);
        return .{ .shape_svg = std.fmt.allocPrint(ctx.arena,
            \\<polygon points="{d},0 {d},{d} {d},{d} 0,{d}"{s}/>
            \\<text x="{d}" y="{d}" text-anchor="middle" font-family="monospace" font-size="12" fill="#333333" stroke="none">{s}</text>
        , .{ ctx.width / 2, ctx.width, ctx.height / 2, ctx.width / 2, ctx.height, ctx.height / 2, dash, ctx.width / 2, ctx.height / 2 + 4, label }) catch "" };
    }

    /// Parallelogram — skewed rectangle. Good for I/O nodes in flowcharts.
    pub fn parallelogram(ctx: NodeStyleContext) NodeStyle {
        const dash: []const u8 = if (ctx.is_implicit) " stroke-dasharray=\"4,2\"" else "";
        const skew = ctx.width / 5;
        const label = helpers.xmlEscape(ctx.arena, ctx.label);
        return .{ .shape_svg = std.fmt.allocPrint(ctx.arena,
            \\<polygon points="{d},0 {d},0 {d},{d} 0,{d}"{s}/>
            \\<text x="{d}" y="{d}" text-anchor="middle" font-family="monospace" font-size="12" fill="#333333" stroke="none">{s}</text>
        , .{ skew, ctx.width, ctx.width - skew, ctx.height, ctx.height, dash, ctx.width / 2, ctx.height / 2 + 4, label }) catch "" };
    }

    /// Hexagon — six-sided polygon. Good for preparation/state nodes.
    pub fn hexagon(ctx: NodeStyleContext) NodeStyle {
        const dash: []const u8 = if (ctx.is_implicit) " stroke-dasharray=\"4,2\"" else "";
        const inset = ctx.width / 4;
        const label = helpers.xmlEscape(ctx.arena, ctx.label);
        return .{ .shape_svg = std.fmt.allocPrint(ctx.arena,
            \\<polygon points="{d},0 {d},0 {d},{d} {d},{d} {d},{d} 0,{d}"{s}/>
            \\<text x="{d}" y="{d}" text-anchor="middle" font-family="monospace" font-size="12" fill="#333333" stroke="none">{s}</text>
        , .{ inset, ctx.width - inset, ctx.width, ctx.height / 2, ctx.width - inset, ctx.height, inset, ctx.height, ctx.height / 2, dash, ctx.width / 2, ctx.height / 2 + 4, label }) catch "" };
    }

    /// Circle — equal width/height circle. Centers within the bounding box.
    pub fn circle(ctx: NodeStyleContext) NodeStyle {
        const dash: []const u8 = if (ctx.is_implicit) " stroke-dasharray=\"4,2\"" else "";
        const label = helpers.xmlEscape(ctx.arena, ctx.label);
        const r = @min(ctx.width, ctx.height) / 2;
        return .{ .shape_svg = std.fmt.allocPrint(ctx.arena,
            \\<circle cx="{d}" cy="{d}" r="{d}"{s}/>
            \\<text x="{d}" y="{d}" text-anchor="middle" font-family="monospace" font-size="12" fill="#333333" stroke="none">{s}</text>
        , .{ ctx.width / 2, ctx.height / 2, r, dash, ctx.width / 2, ctx.height / 2 + 4, label }) catch "" };
    }
};

/// What the subgraph style function returns — box geometry + colors + SVG escape hatches.
///
/// The `box_svg` field contains SVG geometry relative to (0,0) — including the
/// label text. The renderer wraps it in a positioned `<g>` with inherited fill/stroke.
///
/// Built-in preset functions (in the `subgraph_presets` namespace) produce standard shapes.
/// Custom functions return arbitrary SVG — the renderer can't tell the difference.
pub const SubgraphStyle = struct {
    /// SVG geometry relative to (0,0) — box element(s) + label `<text>`.
    /// The renderer wraps this in `<g transform="translate(x,y)" fill=... fill-opacity=... stroke=...>`.
    /// Shape elements inherit fill/stroke from the `<g>`.
    /// Text elements should set explicit `fill` to avoid inheriting the box's fill color.
    box_svg: []const u8,
    /// Box fill color — applied on the wrapping `<g>`, inherited by shape elements.
    fill: []const u8 = "#e8f4fd",
    /// Box fill opacity — applied on the wrapping `<g>`.
    fill_opacity: []const u8 = "0.4",
    /// Box stroke color — applied on the wrapping `<g>`, inherited by shape elements.
    stroke: []const u8 = "#4a90d9",
    /// Raw SVG injected into `<defs>` — for gradients, filters, clip paths.
    defs: ?[]const u8 = null,
    /// Raw attributes added to the wrapping `<g>` element — CSS classes, data attrs.
    extra_attrs: ?[]const u8 = null,
};

/// Built-in subgraph shape presets.
///
/// Each function takes a `SubgraphStyleContext` and returns a `SubgraphStyle` with
/// appropriate SVG geometry. Use as: `.subgraph_style_fn = &subgraph_presets.default`
///
/// The default preset reproduces the current hardcoded output: a dashed rounded
/// rectangle with a bold label at top-left.
pub const subgraph_presets = struct {
    /// Dashed rounded rectangle with bold label top-left (default).
    /// Reproduces the original hardcoded subgraph style.
    pub fn default(ctx: SubgraphStyleContext) SubgraphStyle {
        const label = helpers.xmlEscape(ctx.arena, ctx.label);
        return .{ .box_svg = std.fmt.allocPrint(ctx.arena,
            \\<rect x="0" y="0" width="{d}" height="{d}" rx="6" ry="6" stroke-width="1" stroke-dasharray="4,2"/>
            \\<text x="6" y="13" font-family="monospace" font-size="11" font-weight="bold" fill="#4a90d9" stroke="none">{s}</text>
        , .{ ctx.width, ctx.height, label }) catch "" };
    }
};

/// SVG rendering configuration
pub const SvgConfig = struct {
    /// Pixels per character cell (horizontal)
    char_width: usize = 10,
    /// Pixels per line (vertical)
    line_height: usize = 20,
    /// Padding around the entire SVG
    padding: usize = 20,
    /// Edge stroke width
    edge_width: usize = 2,
    /// Arrow / marker size (px)
    arrow_size: usize = 8,
    /// Stitch edge segments through dummies into smooth splines
    stitch_splines: bool = true,
    /// Show dummy nodes (when false, they're hidden)
    show_dummy_nodes: bool = false,

    /// Edge style function. Receives per-edge context, returns visual style.
    ///
    /// Default: palette-cycling with Radix UI colors (directed → arrow, undirected → none).
    /// Replace with your own function for custom coloring, markers, gradients, etc.
    edge_style_fn: *const fn (EdgeStyleContext) EdgeStyle = &defaultEdgeStyle,

    /// Node style function. Receives per-node context, returns visual style.
    ///
    /// Default: rounded rectangle with monospace label.
    /// Replace with a built-in preset (`shapes.diamond`, `shapes.ellipse`, etc.)
    /// or your own function for custom shapes, colors, compound nodes, etc.
    node_style_fn: *const fn (NodeStyleContext) NodeStyle = &shapes.rounded_rectangle,

    /// Edge label style function. Receives per-edge context, returns label appearance.
    ///
    /// Default: inherit everything from edge style + global config.
    /// Replace with your own function for custom label colors, font sizes,
    /// positioning, path-following overrides, etc.
    edge_label_style_fn: *const fn (EdgeStyleContext) EdgeLabelStyle = &defaultEdgeLabelStyle,

    /// Subgraph style function. Receives per-subgraph context, returns visual style.
    ///
    /// Default: dashed rounded rectangle with bold label top-left.
    /// Replace with your own function for custom boxes, depth-based coloring,
    /// cylinder shapes, etc.
    subgraph_style_fn: *const fn (SubgraphStyleContext) SubgraphStyle = &subgraph_presets.default,

    /// Show control points for debugging bezier curves
    show_control_points: bool = false,
    /// Control point color (when show_control_points is true)
    control_point_color: []const u8 = "#ff0000",
    /// Render edge labels along the path using SVG <textPath>
    /// When false (default), labels are placed at fixed positions near the edge.
    /// When true, labels follow the edge curve using SVG text-on-a-path.
    labels_on_path: bool = false,
    /// Show subgraph bounding boxes (when subgraphs exist in the IR)
    show_subgraphs: bool = true,

    /// Global `<style>` block — placed inside `<defs>` at the top of the SVG.
    /// For shared CSS: hover effects, theming, CSS variables, class-based styling.
    /// Set to raw SVG content including the `<style>` tags.
    global_style: ?[]const u8 = null,

    /// Global `<script>` block — placed at end of SVG (DOM is ready).
    /// For shared functions, pan/zoom, event delegation, library initialization.
    /// Set to raw SVG content including the `<script>` tags.
    global_script: ?[]const u8 = null,
};
