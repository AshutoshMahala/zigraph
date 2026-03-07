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

/// Per-node context passed to style functions.
///
/// Contains enough information for any style decision — by label identity,
/// by node count, by implicit/explicit kind, etc. Shared across all renderers
/// (SVG, Unicode, JSON). Each renderer's style *return* type differs, but
/// the context is the same.
///
/// ## Examples
///
/// ```zig
/// fn styleByLabel(ctx: NodeStyleContext) svg.NodeStyle {
///     if (std.mem.eql(u8, ctx.label, "Error"))
///         return .{ .shape_svg = "...", .fill = "#fee2e2", .stroke = "#e5484d" };
///     return shapes.rounded_rectangle(ctx);
/// }
/// ```
pub const NodeStyleContext = struct {
    /// Original node ID from the graph
    node_id: usize,
    /// Node label text
    label: []const u8,
    /// Total number of real (non-dummy) nodes in the graph
    total_nodes: usize,
    /// Bounding box width in pixels (layout-computed)
    width: usize,
    /// Bounding box height in pixels (layout-computed)
    height: usize,
    /// Whether this node was implicitly created (mentioned as edge target
    /// but never explicitly added). Presets render dashed borders for these.
    is_implicit: bool,
    /// Arena allocator — use for dynamic string formatting (e.g., `allocPrint`).
    /// Memory persists until the render pass completes, then bulk-freed.
    arena: Allocator,
};

/// Per-subgraph context passed to style functions.
///
/// Contains enough information for any style decision — by label, by nesting
/// depth, by parent identity, etc. Shared across all renderers (SVG, Unicode,
/// JSON). Each renderer's style *return* type differs, but the context is the same.
///
/// ## Examples
///
/// ```zig
/// fn styleByDepth(ctx: SubgraphStyleContext) svg.SubgraphStyle {
///     const fills = [_][]const u8{ "#e8f4fd", "#e6f4ea", "#fff4e6" };
///     return .{ .box_svg = "...", .fill = fills[ctx.depth % fills.len] };
/// }
/// ```
pub const SubgraphStyleContext = struct {
    /// Subgraph ID (matches Graph.Subgraph.id)
    subgraph_id: usize,
    /// Parent subgraph ID (null = root-level subgraph)
    parent_id: ?usize,
    /// Display label
    label: []const u8,
    /// Nesting depth: 0 = root-level, 1 = nested once, etc.
    /// Computed from `parent_id` chains at render time.
    depth: usize,
    /// Total number of subgraphs in the graph
    total_subgraphs: usize,
    /// Bounding box width in pixels (layout-computed)
    width: usize,
    /// Bounding box height in pixels (layout-computed)
    height: usize,
    /// Arena allocator — use for dynamic string formatting (e.g., `allocPrint`).
    /// Memory persists until the render pass completes, then bulk-freed.
    arena: Allocator,
};
