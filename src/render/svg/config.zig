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
const colors = @import("../colors.zig");
const types = @import("../types.zig");

pub const MarkerShape = types.MarkerShape;
pub const EdgeStyleContext = types.EdgeStyleContext;

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

/// SVG rendering configuration
pub const SvgConfig = struct {
    /// Pixels per character cell (horizontal)
    char_width: usize = 10,
    /// Pixels per line (vertical)
    line_height: usize = 20,
    /// Padding around the entire SVG
    padding: usize = 20,
    /// Node corner radius
    node_radius: usize = 4,
    /// Node fill color
    node_fill: []const u8 = "#f0f0f0",
    /// Node stroke color
    node_stroke: []const u8 = "#333333",
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

    /// Font family
    font_family: []const u8 = "monospace",
    /// Font size in pixels
    font_size: usize = 12,
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
    /// Subgraph box fill color (with transparency)
    subgraph_fill: []const u8 = "#e8f4fd",
    /// Subgraph box fill opacity
    subgraph_fill_opacity: []const u8 = "0.4",
    /// Subgraph box stroke color
    subgraph_stroke: []const u8 = "#4a90d9",
    /// Subgraph box corner radius
    subgraph_radius: usize = 6,
    /// Subgraph label font size in pixels
    subgraph_font_size: usize = 11,
    /// Subgraph label color
    subgraph_label_color: []const u8 = "#4a90d9",

    /// Global `<style>` block — placed inside `<defs>` at the top of the SVG.
    /// For shared CSS: hover effects, theming, CSS variables, class-based styling.
    /// Set to raw SVG content including the `<style>` tags.
    global_style: ?[]const u8 = null,

    /// Global `<script>` block — placed at end of SVG (DOM is ready).
    /// For shared functions, pan/zoom, event delegation, library initialization.
    /// Set to raw SVG content including the `<script>` tags.
    global_script: ?[]const u8 = null,
};
