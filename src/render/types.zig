//! Shared rendering types used across SVG, Unicode, and JSON renderers.
//!
//! Types here are renderer-agnostic — they describe *what* to render, not *how*.
//! Each renderer maps these to its own output format (SVG polygons, Unicode
//! codepoints, etc.).

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Marker shapes for edge endpoints (arrowheads / tails).
///
/// Semantic — describes *what* the marker means, not *how* it's drawn.
/// Shared across renderers; each maps to its own output format:
///
/// | MarkerShape   | SVG                      | Unicode (directional)        |
/// |---------------|--------------------------|------------------------------|
/// | `.arrow`      | filled `<polygon>`       | `▼ ▲ ▶ ◀`                   |
/// | `.open_arrow` | outline `<polygon>`      | `▽ △ ▷ ◁`                   |
/// | `.diamond`    | 45° rotated filled rect  | `◆`                          |
/// | `.open_diamond`| 45° rotated outline rect| `◇`                          |
/// | `.circle`     | filled `<circle>`        | `●`                          |
/// | `.open_circle`| outline `<circle>`       | `○`                          |
/// | `.none`       | (nothing)                | (nothing)                    |
pub const MarkerShape = enum {
    /// No marker rendered
    none,
    /// Filled arrowhead (default for directed edges)
    arrow,
    /// Outline arrowhead (UML inheritance)
    open_arrow,
    /// Filled diamond (UML composition)
    diamond,
    /// Outline diamond (UML aggregation)
    open_diamond,
    /// Filled circle
    circle,
    /// Outline circle
    open_circle,
};

/// Per-edge context passed to style functions.
///
/// Contains enough information for any style decision — coloring by index,
/// by node identity, by edge direction, etc. Shared across all renderers
/// (SVG, Unicode, JSON). Each renderer's style *return* type differs, but
/// the context is the same.
///
/// ## Examples
///
/// ```zig
/// fn styleByTarget(ctx: EdgeStyleContext) svg.EdgeStyle {
///     if (std.mem.eql(u8, ctx.to_label, "Error"))
///         return .{ .stroke = "#e5484d" };
///     return .{ .stroke = colors.get(&colors.radix, ctx.edge_index) };
/// }
/// ```
pub const EdgeStyleContext = struct {
    /// Zero-based index of this edge (unique per original edge, shared across segments)
    edge_index: usize,
    /// Total number of unique edges in the graph
    total_edges: usize,
    /// Source node ID (IR direction — check `reversed` for semantic direction)
    from_id: usize,
    /// Target node ID (IR direction — check `reversed` for semantic direction)
    to_id: usize,
    /// Source node label (empty string for dummy nodes)
    from_label: []const u8,
    /// Target node label (empty string for dummy nodes)
    to_label: []const u8,
    /// Edge label text (e.g., "depends on"), if any
    label: ?[]const u8,
    /// Whether this edge is directed (has an arrowhead in the default style)
    directed: bool,
    /// Whether this edge was reversed for cycle breaking (back-edge)
    reversed: bool,
    /// Arena allocator — use for dynamic string formatting (e.g., `allocPrint`).
    /// Memory persists until the render pass completes, then bulk-freed.
    arena: Allocator,
};
