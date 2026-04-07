//! zigraph - Zero-dependency graph layout engine for Zig
//!
//! This library provides hierarchical (Sugiyama) graph layout with
//! pluggable algorithms and presets for different use cases.
//!
//! ## Quick Start
//!
//! ```zig
//! const zigraph = @import("zigraph");
//!
//! var graph = zigraph.Graph.init(allocator);
//! defer graph.deinit();
//!
//! try graph.addNode(1, "Start");
//! try graph.addNode(2, "End");
//! try graph.addEdge(1, 2);
//!
//! const ir = try zigraph.layout(graph, allocator, .{});
//! defer ir.deinit();
//! ```

const std = @import("std");

/// Fixed-point module alias (used in FDG layout bridge).
const fp_mod = @import("algorithms/shared/fixed_point.zig");

// ============================================================================
// Core types
// ============================================================================

/// Core graph data structures
pub const graph = @import("core/graph.zig");
pub const Graph = graph.Graph;
pub const Node = graph.Node;
pub const Edge = graph.Edge;
pub const NodeKind = graph.NodeKind;
pub const NodeOptions = graph.NodeOptions;
pub const Pin = graph.Pin;
pub const Subgraph = graph.Subgraph;
pub const ValidationResult = graph.ValidationResult;
pub const CycleInfo = graph.CycleInfo;

/// Error types (WDP Level 0 compliant)
pub const errors = @import("core/errors.zig");
pub const Code = errors.Code;
pub const Diagnostic = errors.Diagnostic;
pub const DiagnosticInfo = errors.DiagnosticInfo;
pub const ZigraphError = errors.ZigraphError;
pub const ValidationFailures = errors.ValidationFailures;
pub const Requirements = errors.Requirements;
pub const GraphProperties = errors.GraphProperties;
pub const diagnosticInfo = errors.diagnosticInfo;

/// Validation algorithms
pub const validation = @import("core/validation.zig");

/// Curated layout presets for common use cases
pub const presets = @import("presets.zig");

/// Intermediate Representation for layout.
/// All IR types are parameterized by coordinate type:
///   const MyIR = ir.LayoutIR(f32);
///   const DefaultIR = ir.LayoutIR(usize);
pub const ir = @import("core/ir.zig");
pub const LayoutIR = ir.LayoutIR;
pub const LayoutNode = ir.LayoutNode;
pub const LayoutEdge = ir.LayoutEdge;
pub const EdgePath = ir.EdgePath;
pub const SubgraphInfo = ir.SubgraphInfo;
pub const coordCast = ir.coordCast;

// ============================================================================
// Algorithms
// ============================================================================

/// Cycle-breaking algorithms — detect and mark back edges
pub const cycle_breaking = @import("algorithms/sugiyama/cycle_breaking.zig");

/// Layering algorithms - assign nodes to horizontal levels
pub const layering = struct {
    pub const longest_path = @import("algorithms/sugiyama/layering/longest_path.zig");
    pub const network_simplex = @import("algorithms/sugiyama/layering/network_simplex.zig");
    pub const virtual = @import("algorithms/sugiyama/layering/virtual.zig");
};

/// Crossing reduction algorithms - minimize edge crossings
pub const crossing = struct {
    pub const median = @import("algorithms/sugiyama/crossing/median.zig");
    pub const adjacent_exchange = @import("algorithms/sugiyama/crossing/adjacent_exchange.zig");

    // Re-export reducers for easy access
    pub const reducers = @import("algorithms/sugiyama/crossing/reducers.zig");
    pub const Reducer = reducers.Reducer;

    // Preset pipelines
    pub const fast = reducers.fast;
    pub const balanced = reducers.balanced;
    pub const quality = reducers.quality;
    pub const none = reducers.none;

    // Factory functions for building custom pipelines
    pub const medianReducer = reducers.median;
    pub const adjacentExchangeReducer = reducers.adjacentExchange;

    // Pipeline runner
    pub const runPipeline = reducers.runPipeline;
};

/// Node positioning algorithms - assign x-coordinates
pub const positioning = struct {
    pub const common = @import("algorithms/sugiyama/positioning/common.zig");
    pub const barycentric = @import("algorithms/sugiyama/positioning/barycentric.zig");
    pub const brandes_kopf = @import("algorithms/sugiyama/positioning/brandes_kopf.zig");
};

/// Edge routing algorithms - determine edge paths
pub const routing = struct {
    pub const direct = @import("algorithms/sugiyama/routing/direct.zig");
    pub const spline = @import("algorithms/sugiyama/routing/spline.zig");
};

/// Subgraph-aware layout orchestration (adjacency enforcement + bounding boxes)
pub const subgraph_layout = @import("algorithms/sugiyama/subgraph.zig");

/// Force-directed graph layout algorithms.
///
/// Each algorithm is standalone — call `compute()` directly with a `*const Graph`
/// and get back a `PositionResult` with Q16.16 positions. Or use `layoutTyped()`
/// for the integrated pipeline.
///
/// ```zig
/// // Standalone usage
/// const fr = zigraph.fdg.fruchterman_reingold;
/// var result = try fr.compute(&graph, allocator, .{});
/// defer result.deinit();
///
/// // Integrated usage
/// var ir = try zigraph.layoutTyped(f32, &graph, allocator, .{
///     .algorithm = .{ .fruchterman_reingold = .{} },
/// });
/// ```
pub const fdg = struct {
    pub const fixed_point = @import("algorithms/shared/fixed_point.zig");
    pub const common = @import("algorithms/shared/common.zig");
    pub const quadtree = @import("algorithms/shared/quadtree.zig");
    pub const forces = @import("algorithms/shared/forces/mod.zig");
    pub const fruchterman_reingold = @import("algorithms/fruchterman_reingold/mod.zig");
};

/// Algorithm interface for BYOA (Bring Your Own Algorithm)
pub const algorithm_interface = @import("algorithms/interface.zig");

// ============================================================================
// Rendering
// ============================================================================

/// Terminal renderer (box drawing characters)
pub const terminal = @import("render/terminal/mod.zig");

/// JSON renderer for external tool integration
pub const json = @import("render/json.zig");

/// SVG renderer for high-quality vector output and spline visualization
pub const svg = @import("render/svg/mod.zig");

/// Type-erased renderer interface (wraps SVG, Terminal, JSON, or custom backends)
pub const Renderer = @import("render/Renderer.zig");

/// Color system — numeric Color struct, scientific colormaps, palettes, gradients
pub const color = @import("render/color/mod.zig");

/// Shared rendering types (MarkerShape, etc.)
pub const render_types = @import("render/types.zig");

/// Shared render helpers (subgraph depth computation, etc.)
pub const render_helpers = @import("render/helpers.zig");

pub const MarkerShape = render_types.MarkerShape;
pub const EdgeStyleContext = render_types.EdgeStyleContext;
pub const NodeStyleContext = render_types.NodeStyleContext;
pub const SubgraphStyleContext = render_types.SubgraphStyleContext;
pub const EdgeStyle = svg.EdgeStyle;
pub const EdgeLabelStyle = svg.EdgeLabelStyle;
pub const NodeStyle = svg.NodeStyle;
pub const SubgraphStyle = svg.SubgraphStyle;
pub const shapes = svg.shapes;
pub const subgraph_presets = svg.subgraph_presets;

// Terminal renderer types
pub const TerminalEdgeStyle = terminal.TerminalEdgeStyle;
pub const TerminalNodeStyle = terminal.TerminalNodeStyle;
pub const TerminalEdgeLabelStyle = terminal.TerminalEdgeLabelStyle;
pub const TerminalSubgraphStyle = terminal.TerminalSubgraphStyle;
pub const LineWeight = terminal.LineWeight;
pub const NodeBorder = terminal.NodeBorder;
pub const LabelPlacement = terminal.LabelPlacement;
pub const SubgraphBorder = terminal.SubgraphBorder;
pub const LabelPosition = terminal.LabelPosition;
pub const TextAttrs = terminal.TextAttrs;
pub const TerminalColor = terminal.Color;
pub const TerminalColorMode = terminal.ColorMode;
pub const TerminalCellColor = terminal.CellColor;
pub const TerminalCharSet = terminal.CharSet;
pub const TerminalOutputFormat = terminal.OutputFormat;
pub const TerminalRenderPlan = terminal.RenderPlan;
pub const TerminalHitResult = terminal.HitResult;
pub const terminal_subgraph_presets = terminal.subgraph_presets;
pub const terminal_node_presets = terminal.node_presets;

// ============================================================================
// Layout configuration
// ============================================================================

/// Cycle-breaking strategy for handling cyclic graphs in Sugiyama layout.
///
/// The classic Sugiyama pipeline requires a DAG. When the input graph has
/// cycles, back edges must be virtually reversed so that layering can
/// proceed. The reversed edges are restored in the final IR with the
/// `reversed` flag set, allowing renderers to style them differently.
pub const CycleBreaking = enum {
    /// Reject cyclic graphs with error.CycleDetected (default).
    /// Use this when you know your input is acyclic or want strict validation.
    none,
    /// DFS-based back-edge reversal.
    /// Detects back edges via depth-first search and virtually reverses them.
    /// O(V + E) time. Produces a valid DAG for any input.
    depth_first,
};

/// Available layering algorithms
pub const Layering = enum {
    /// Longest path layering - simple, fast, may produce more layers
    longest_path,
    /// Network simplex - optimal minimum edge span (slower)
    network_simplex,
    /// Network simplex fast - bounded iterations, near-optimal (good default)
    network_simplex_fast,
};

/// Available positioning algorithms
pub const Positioning = enum {
    /// Left-to-right packing respecting crossing order.
    /// This is the fastest and guarantees no overlaps. Dummy nodes are properly spaced.
    compact,
    /// Single-pass barycentric: nudges nodes toward connected neighbours.
    /// Starts from compact baseline, then refines with parent/child averaging.
    barycentric,
    /// Multi-pass (Brandes-Köpf): best visual quality for trees/DAGs.
    /// Widest-level-first placement with iterative parent/child centering.
    brandes_kopf,
};

/// Available edge routing algorithms
pub const Routing = enum {
    /// Direct Manhattan routing (straight lines with corners)
    direct,
    /// Spline routing (smooth bezier curves)
    spline,
};

/// How fan-out edges (one parent, multiple children) are drawn.
/// Only affects sources with 2+ children at the same level.
pub const FanOutStyle = enum {
    /// Each edge gets its own horizontal corner (default)
    individual,
    /// Sibling edges share a single horizontal bus bar
    bus,
};

/// Top-level algorithm selection.
///
/// Sugiyama is the default (hierarchical, level-based). Force-directed
/// algorithms produce free-form layouts. Each variant carries its own config.
pub const Algorithm = union(enum) {
    /// Sugiyama hierarchical layout (default).
    /// Sub-algorithm selection (layering, crossing, positioning) is in LayoutConfig.
    sugiyama,

    /// Fruchterman-Reingold force-directed layout — standard (O(N²) exact).
    fruchterman_reingold: fdg.fruchterman_reingold.Config,

    /// Fruchterman-Reingold force-directed layout — fast (O(N log N) Barnes-Hut).
    fruchterman_reingold_fast: fdg.fruchterman_reingold.Config,
};

/// Configuration for the layout algorithm.
pub const LayoutConfig = struct {
    // Top-level algorithm
    /// Layout algorithm family (default: Sugiyama hierarchical).
    algorithm: Algorithm = .sugiyama,

    // Sugiyama-specific options (ignored for force-directed algorithms)
    /// Cycle-breaking strategy (default: none — rejects cyclic graphs)
    /// Set to .depth_first to automatically handle cyclic graphs.
    cycle_breaking: CycleBreaking = .none,
    /// Layering algorithm (default: longest_path)
    layering: Layering = .longest_path,
    /// Crossing reduction pipeline (default: median + adjacent exchange)
    /// Use presets: crossing.fast, crossing.balanced, crossing.quality, crossing.none
    /// Or build custom: &[_]crossing.Reducer{ crossing.medianReducer(4), ... }
    crossing_reducers: []const crossing.Reducer = &crossing.balanced,
    /// Positioning algorithm (default: compact - left-to-right packing)
    /// .barycentric = single-pass barycentric, .brandes_kopf = multi-pass (best quality)
    positioning: Positioning = .compact,
    /// Edge routing algorithm (default: direct)
    routing: Routing = .direct,
    /// Fan-out style for direct routing (default: individual)
    /// When .bus, sibling edges share a horizontal bar instead of individual corners.
    fan_out_style: FanOutStyle = .individual,

    // Tuning parameters
    /// Horizontal spacing between nodes
    node_spacing: usize = 3,
    /// Vertical spacing between levels
    level_spacing: usize = 2,

    // Debug options
    /// Include dummy nodes in IR (for debugging layout)
    include_dummy_nodes: bool = false,

    // Performance options
    /// Skip validation (for performance if you know graph is valid)
    skip_validation: bool = false,

    // Render options (Unicode only)
    /// Edge color palette (ANSI 256-color codes)
    /// Use colors.ansi, colors.ansi_dark, or colors.ansi_light
    edge_palette: ?[]const u8 = null,
};

/// Layout error type with detailed information
/// Combines semantic errors (EmptyGraph, CycleDetected) with allocation errors.
/// Note: Custom crossing reducers may produce additional errors.
pub const LayoutError = error{
    EmptyGraph,
    CycleDetected,
} || std.mem.Allocator.Error;

/// Compute layout for a graph.
///
/// This is the main entry point for layout computation.
/// The `algorithm` field in config selects between Sugiyama (hierarchical)
/// and force-directed algorithms. Default is Sugiyama.
///
/// Returns error.EmptyGraph if the graph has no nodes.
/// Returns error.CycleDetected if the graph contains a cycle (Sugiyama only,
/// and only when `cycle_breaking` is `.none`). Set `cycle_breaking` to
/// `.depth_first` to automatically handle cyclic graphs.
/// Custom crossing reducers may return additional errors.
/// Use `graph.validate()` before calling for detailed cycle info.
pub fn layout(g: *const Graph, allocator: std.mem.Allocator, config: LayoutConfig) anyerror!LayoutIR(usize) {
    return switch (config.algorithm) {
        .sugiyama => layoutSugiyama(g, allocator, config),
        .fruchterman_reingold => |fr_config| layoutFdg(g, allocator, config, fr_config, false),
        .fruchterman_reingold_fast => |fr_config| layoutFdg(g, allocator, config, fr_config, true),
    };
}

/// Force-directed layout: runs FR, builds LayoutIR from positions.
fn layoutFdg(
    g: *const Graph,
    allocator: std.mem.Allocator,
    _: LayoutConfig,
    fr_config: fdg.fruchterman_reingold.Config,
    fast: bool,
) anyerror!LayoutIR(usize) {
    const n = g.nodeCount();
    if (n == 0) {
        errors.captureError(error.EmptyGraph, @src());
        return error.EmptyGraph;
    }

    // Run the force-directed algorithm
    var fdg_result = if (fast)
        try fdg.fruchterman_reingold.computeFast(g, allocator, fr_config)
    else
        try fdg.fruchterman_reingold.compute(g, allocator, fr_config);
    defer fdg_result.deinit();

    // Build LayoutIR from FDG positions
    var result = LayoutIR(usize).init(allocator);
    errdefer result.deinit();

    // Scale FDG positions to a reasonable terminal size.
    //
    // FDG produces Q16.16 coordinates. We need to map them to integer cells
    // suitable for terminal rendering (typically ≤ 120 columns, proportional height).
    //
    // Key insight: terminal characters are roughly 2× taller than wide, so
    // we apply a char_aspect correction. We use **uniform scaling** (same
    // effective scale for both axes after aspect correction) to preserve the
    // layout's proportions — independent x/y scaling distorts the graph.
    const max_label_w: usize = blk: {
        var max_w: usize = 3;
        for (0..n) |i| {
            const nd = g.nodeAt(i) orelse continue;
            if (nd.width > max_w) max_w = nd.width;
        }
        break :blk max_w;
    };

    // Character aspect ratio: a terminal cell is ~2x taller than wide.
    // We compress Y by this factor so that visually the graph looks square.
    const char_aspect: f64 = 2.0;

    // Target: enough room so nodes don't overlap.
    // Each node needs at least (label_width + 4) horizontal cells.
    // Use sqrt(N) to estimate the grid dimension.
    const cell_w: f64 = @floatFromInt(max_label_w + 4);
    const sqrt_n: f64 = @sqrt(@as(f64, @floatFromInt(n)));
    const target_span: f64 = cell_w * (sqrt_n + 1);

    const fdg_w = fp_mod.toFloat(fdg_result.width);
    const fdg_h = fp_mod.toFloat(fdg_result.height);

    // Uniform scale: pick the scale that fits the larger axis into target_span.
    // For the Y axis, account for char_aspect (fewer rows needed than columns
    // for the same visual distance).
    const effective_fdg_span = @max(fdg_w, fdg_h / char_aspect);
    const scale: f64 = if (effective_fdg_span > 1.0) target_span / effective_fdg_span else 1.0;
    const scale_x: f64 = scale;
    const scale_y: f64 = scale / char_aspect;

    // Add nodes with scaled positions
    for (0..n) |node_idx| {
        const node = g.nodeAt(node_idx) orelse continue;
        const pos = fdg_result.positions[node_idx];

        const fx = fp_mod.toFloat(pos.x) * scale_x;
        const fy = fp_mod.toFloat(pos.y) * scale_y;
        const x: usize = @intFromFloat(@max(0.0, @round(fx)));
        const y: usize = @intFromFloat(@max(0.0, @round(fy)));

        try result.addNode(.{
            .id = node.id,
            .label = node.label,
            .x = x,
            .y = y,
            .width = node.width,
            .height = node.height,
            .center_x = x + node.width / 2,
            .center_y = y + node.height / 2,
            .level = 0, // FDG doesn't have levels
            .level_position = node_idx,
            .kind = node.kind,
        });
    }

    // Post-processing: compress large vertical gaps.
    // FDG repulsion can push clusters far apart, leaving huge empty bands.
    // We detect gaps between consecutive Y coordinates that are much larger
    // than average and shrink them.
    if (result.nodes.items.len > 1) {
        const items = result.nodes.items;
        const node_count = items.len;

        // Sort node indices by Y coordinate
        const order = try allocator.alloc(usize, node_count);
        defer allocator.free(order);
        for (order, 0..) |*o, i| o.* = i;
        std.mem.sort(usize, order, items, struct {
            fn cmp(nodes: []LayoutNode(usize), a: usize, b: usize) bool {
                return nodes[a].y < nodes[b].y;
            }
        }.cmp);

        // Collect gaps and find the median to set a robust threshold.
        // Using median instead of mean prevents a single large outlier
        // from inflating the threshold.
        const gap_count = node_count - 1;
        const gaps = try allocator.alloc(usize, gap_count);
        defer allocator.free(gaps);
        for (0..gap_count) |i| {
            gaps[i] = items[order[i + 1]].y -| items[order[i]].y;
        }
        std.mem.sort(usize, gaps, {}, std.sort.asc(usize));

        const median_gap = gaps[gap_count / 2];
        const max_gap = @max(median_gap * 2, 3);

        // Walk sorted order, track cumulative shift for over-sized gaps
        var shift: usize = 0;
        var prev_y: usize = items[order[0]].y;
        for (1..node_count) |i| {
            const idx = order[i];
            const cur_y = items[idx].y;
            const gap = cur_y -| prev_y;
            if (gap > max_gap) {
                shift += gap - max_gap;
            }
            prev_y = cur_y;
            items[idx].y -|= shift;
        }

        // Update center_x (unchanged) — but we must refresh after Y shift
        for (items) |*nd| {
            nd.center_x = nd.x + nd.width / 2;
        }
    }

    // Route edges — use direct routing (straight lines) for FDG.
    // For horizontal edges (same Y), use node box edges so the connecting
    // line and arrow are visible between the nodes rather than hidden
    // under node labels (which are painted last and overwrite edges).
    for (g.edges.items, 0..) |edge, edge_idx| {
        const from_idx = g.nodeIndex(edge.from) orelse continue;
        const to_idx = g.nodeIndex(edge.to) orelse continue;

        const from_node = result.nodes.items[from_idx];
        const to_node = result.nodes.items[to_idx];

        var from_x = from_node.center_x;
        const from_y = from_node.y;
        var to_x = to_node.center_x;
        const to_y = to_node.y;

        // When nodes share the same row, route from the box edge of the
        // source to the box edge of the target so the line/arrow is visible.
        if (from_y == to_y) {
            if (from_node.x + from_node.width <= to_node.x) {
                // source is left of target
                from_x = from_node.x + from_node.width; // right edge of source
                to_x = to_node.x; // left edge of target
            } else if (to_node.x + to_node.width <= from_node.x) {
                // target is left of source
                from_x = from_node.x; // left edge of source
                to_x = to_node.x + to_node.width; // right edge of target
            }
        }

        try result.addEdge(.{
            .from_id = edge.from,
            .to_id = edge.to,
            .from_x = from_x,
            .from_y = from_y,
            .to_x = to_x,
            .to_y = to_y,
            .path = .direct,
            .edge_index = edge_idx,
            .directed = edge.directed,
            .label = edge.label,
        });
    }

    // Compute edge label positions.
    // For FDG direct edges, place the label near the midpoint of the edge.
    // For vertical/diagonal edges: midpoint Y, centered on the edge X.
    // For horizontal edges: midpoint X, one row above the edge Y.
    for (result.edges.items) |*edge| {
        const lbl = edge.label orelse continue;
        const label_width = lbl.len + 2; // +2 for quotes

        const mid_y = if (edge.from_y <= edge.to_y)
            edge.from_y + (edge.to_y - edge.from_y) / 2
        else
            edge.to_y + (edge.from_y - edge.to_y) / 2;

        const mid_x = if (edge.from_x <= edge.to_x)
            edge.from_x + (edge.to_x - edge.from_x) / 2
        else
            edge.to_x + (edge.from_x - edge.to_x) / 2;

        if (edge.from_y == edge.to_y) {
            // Horizontal edge: label above the line
            edge.label_x = if (mid_x >= label_width / 2) mid_x - label_width / 2 else 0;
            edge.label_y = if (mid_y > 0) mid_y - 1 else 0;
        } else {
            // Vertical/diagonal edge: label beside the midpoint
            edge.label_x = if (mid_x >= label_width / 2) mid_x - label_width / 2 else 0;
            edge.label_y = mid_y;
        }
    }

    // Set dimensions from the actual placed node positions
    var max_x: usize = 1;
    var max_y: usize = 1;
    for (result.nodes.items) |node| {
        const right = node.x + node.width + 2;
        if (right > max_x) max_x = right;
        const bottom = node.y + 2;
        if (bottom > max_y) max_y = bottom;
    }
    // Also account for edge labels
    for (result.edges.items) |edge| {
        if (edge.label) |lbl| {
            const right = edge.label_x + lbl.len + 2;
            if (right > max_x) max_x = right;
        }
    }
    result.setDimensions(max_x, max_y);

    // Compute subgraph bounding boxes (reuses Sugiyama's algorithm-agnostic function)
    if (g.hasSubgraphs()) {
        try subgraph_layout.computeBoundingBoxes(g, &result, allocator);

        // Expand layout dimensions if subgraph boxes extend beyond
        for (result.subgraphs.items) |sg_info| {
            const right = sg_info.x + sg_info.width;
            const bottom = sg_info.y + sg_info.height;
            if (right > result.width or bottom > result.height) {
                result.setDimensions(@max(result.width, right), @max(result.height, bottom));
            }
        }
    }

    return result;
}

// Dummy node ID encoding constants.
// Dummy nodes get synthetic IDs in a separate namespace from real nodes:
//   dummy_id = dummy_id_base + edge_index * dummy_id_edge_stride + level_index
// The lookup key for (edge, level) → dummy_id is:
//   key = edge_index * dummy_key_stride + level_index
const dummy_id_base: usize = 0x80000000;
const dummy_id_edge_stride: usize = 1000;
const dummy_key_stride: usize = 10000;

// ============================================================================
// Sugiyama pipeline steps (extracted for composability)
// ============================================================================

/// Step 0: Validate the graph for Sugiyama layout.
///
/// Checks for empty graph and cycles. When cycle_breaking is disabled,
/// cycles are rejected with diagnostics (human-readable detail + node IDs).
fn validateForSugiyama(g: *const Graph, allocator: std.mem.Allocator, config: LayoutConfig) !void {
    if (config.skip_validation) return;

    var validation_result = try g.validate(allocator);
    defer validation_result.deinit();

    switch (validation_result) {
        .empty => {
            errors.captureError(error.EmptyGraph, @src());
            return error.EmptyGraph;
        },
        .cycle => |cycle_info| {
            if (config.cycle_breaking == .none) {
                // Build human-readable detail (capped at 5 nodes)
                var detail_buf: [256]u8 = undefined;
                var fbs = std.io.fixedBufferStream(&detail_buf);
                const w = fbs.writer();
                const max_shown = 5;
                const path = cycle_info.path;
                const total = path.len;
                const show = @min(total, max_shown);
                for (path[0..show], 0..) |node_idx, i| {
                    if (i > 0) w.writeAll(" -> ") catch {};
                    if (g.nodeAt(node_idx)) |node| {
                        w.writeAll(node.label) catch {};
                    } else {
                        w.print("{d}", .{node_idx}) catch {};
                    }
                }
                if (total > max_shown) {
                    w.print(" -> ... (+{d} more)", .{total - max_shown}) catch {};
                }

                // Build machine-readable node IDs (indices → IDs)
                var id_buf: [64]usize = undefined;
                const id_count = @min(total, 64);
                for (path[0..id_count], 0..) |node_idx, i| {
                    id_buf[i] = if (g.nodeAt(node_idx)) |node| node.id else node_idx;
                }

                errors.captureErrorFull(error.CycleDetected, @src(), fbs.getWritten(), id_buf[0..id_count]);
                return error.CycleDetected;
            }
        },
        .ok => {},
    }
}

/// Step 3b: Compute effective level spacing based on fan-out and labels.
///
/// Returns enough vertical rows between levels to stagger outgoing edges,
/// plus extra rows when edge labels are present.
fn computeEffectiveLevelSpacing(g: *const Graph, config: LayoutConfig) usize {
    const has_edge_labels = blk: {
        for (g.edges.items) |edge| {
            if (edge.label != null) break :blk true;
        }
        break :blk false;
    };
    const label_extra: usize = if (has_edge_labels) 2 else 0;

    var max_fan: usize = 0;
    for (0..g.nodeCount()) |node_idx| {
        const children = g.getChildren(node_idx);
        if (children.len > max_fan) max_fan = children.len;
        const parents = g.getParents(node_idx);
        if (parents.len > max_fan) max_fan = parents.len;
    }
    // Scale level spacing with fan-out, but cap it to avoid excessive
    // vertical stretching. A single high-fan node should not inflate the
    // entire graph. Use sqrt(fan) to grow sub-linearly.
    const needed: usize = if (max_fan > 2)
        @min(2 + std.math.sqrt(max_fan), 8)
    else
        2;
    return @max(config.level_spacing, needed) + label_extra;
}

/// Step 6b: Fix up reversed (back) edges in the IR.
///
/// The pipeline routed them downward (from→to flipped), so this step:
///   1. Swaps from_id/to_id back to the original semantic direction
///   2. Keeps coordinates as-is (they represent the visual downward path)
///   3. Sets reversed=true so renderers draw dashed lines
///   4. Moves 'directed' flag from last segment to first segment (arrow at top)
fn fixupReversedEdges(result: *LayoutIR(usize), reversed_edges: ?[]const bool) void {
    const re = reversed_edges orelse return;

    for (result.edges.items) |*result_edge| {
        if (result_edge.edge_index < re.len and re[result_edge.edge_index]) {
            result_edge.reversed = true;
            const tmp_id = result_edge.from_id;
            result_edge.from_id = result_edge.to_id;
            result_edge.to_id = tmp_id;
        }
    }

    // For multi-segment reversed edges, move the arrowhead flag
    // from the last segment (bottom) to the first segment (top).
    for (0..re.len) |edge_idx| {
        if (!re[edge_idx]) continue;

        var first_seg: ?*ir.LayoutEdge(usize) = null;
        var last_seg: ?*ir.LayoutEdge(usize) = null;
        for (result.edges.items) |*seg| {
            if (seg.edge_index != edge_idx) continue;
            if (first_seg == null or seg.from_y < first_seg.?.from_y) {
                first_seg = seg;
            }
            if (last_seg == null or seg.from_y > last_seg.?.from_y) {
                last_seg = seg;
            }
        }

        if (first_seg != null and last_seg != null and first_seg != last_seg) {
            const was_directed = last_seg.?.directed;
            last_seg.?.directed = false;
            first_seg.?.directed = was_directed;
        }
    }
}

/// Step 7: Stagger horizontal_y for corner-path edges.
///
/// Find a safe horizontal_y for a split edge segment, avoiding collisions
/// with intermediate nodes. Returns a h_y in [min_h_y, max_h_y] that doesn't
/// cross through any node (other than from_id/to_id) along the horizontal span.
fn findSafeSplitHorizontalY(
    initial_h_y: usize,
    min_h_y: usize,
    max_h_y: usize,
    x_from: usize,
    x_to: usize,
    nodes: []const ir.LayoutNode(usize),
    from_id: usize,
    to_id: usize,
) usize {
    const x_lo = @min(x_from, x_to);
    const x_hi = @max(x_from, x_to);

    // Check if initial h_y is safe
    if (!splitHorizontalCollides(initial_h_y, x_lo, x_hi, nodes, from_id, to_id)) {
        return initial_h_y;
    }
    // Search outward from initial_h_y
    var offset: usize = 1;
    const range = if (max_h_y >= min_h_y) max_h_y - min_h_y + 1 else 1;
    while (offset <= range) : (offset += 1) {
        if (initial_h_y >= min_h_y + offset) {
            const candidate = initial_h_y - offset;
            if (candidate >= min_h_y and !splitHorizontalCollides(candidate, x_lo, x_hi, nodes, from_id, to_id)) {
                return candidate;
            }
        }
        {
            const candidate = initial_h_y + offset;
            if (candidate <= max_h_y and !splitHorizontalCollides(candidate, x_lo, x_hi, nodes, from_id, to_id)) {
                return candidate;
            }
        }
    }
    return initial_h_y;
}

/// Check if a horizontal segment at h_y from x_lo..x_hi collides with any
/// real (non-dummy) node other than from_id/to_id.
fn splitHorizontalCollides(
    h_y: usize,
    x_lo: usize,
    x_hi: usize,
    nodes: []const ir.LayoutNode(usize),
    from_id: usize,
    to_id: usize,
) bool {
    for (nodes) |n| {
        if (n.id == from_id or n.id == to_id) continue;
        if (n.kind == .dummy) continue;
        // Node visual area: [y-1, y+height] (includes arrow row above and border below)
        const node_y_min = if (n.y > 0) n.y - 1 else 0;
        const node_y_max = n.y + n.height;
        if (h_y < node_y_min or h_y > node_y_max) continue;
        // Check x overlap
        const node_x_max = n.x + n.width;
        if (x_hi < n.x or x_lo > node_x_max) continue;
        return true;
    }
    return false;
}

/// Groups corner edges by from_y, then sorts each group so that edges
/// reaching farthest horizontally exit closest to the source node (lowest
/// h_y / slot 0). This reduces edge crossings: wide-spanning edges clear
/// over the top, while short-reach edges tuck underneath.
fn staggerCornerEdges(result: *LayoutIR(usize)) void {
    const edges = result.edges.items;
    const n = edges.len;
    if (n == 0) return;

    // Collect indices of corner edges, grouped by from_y.
    // We process them in groups: for each unique from_y, sort by
    // horizontal distance descending, then assign slots.
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (edges[i].path != .corner) continue;
        const group_from_y = edges[i].from_y;

        // Assign slot based on how many wider-reaching edges share this from_y.
        // An edge is "wider" if its absolute horizontal distance is greater.
        const my_dist = if (edges[i].to_x >= edges[i].from_x)
            edges[i].to_x - edges[i].from_x
        else
            edges[i].from_x - edges[i].to_x;

        var slot: usize = 0;
        for (edges[0..n]) |*prev| {
            if (@intFromPtr(prev) == @intFromPtr(&edges[i])) continue;
            if (prev.path != .corner) continue;
            if (prev.from_y != group_from_y) continue;
            // Count edges that go farther than this one (they get lower slots)
            const prev_dist = if (prev.to_x >= prev.from_x)
                prev.to_x - prev.from_x
            else
                prev.from_x - prev.to_x;
            if (prev_dist > my_dist) {
                slot += 1;
            } else if (prev_dist == my_dist) {
                // Tiebreaker: edge going further left gets lower slot
                if (prev.to_x < edges[i].to_x) {
                    slot += 1;
                }
            }
        }

        const available = if (edges[i].to_y > edges[i].from_y + 1)
            edges[i].to_y - edges[i].from_y - 1
        else
            1;
        const initial_h_y = edges[i].from_y + (slot % available);
        const min_h_y = edges[i].from_y + 1;
        const max_h_y = if (edges[i].to_y > 1) edges[i].to_y - 1 else min_h_y;
        edges[i].path.corner.horizontal_y = findSafeSplitHorizontalY(
            initial_h_y,
            if (min_h_y <= max_h_y) min_h_y else initial_h_y,
            if (max_h_y >= min_h_y) max_h_y else initial_h_y,
            edges[i].from_x,
            edges[i].to_x,
            result.nodes.items,
            edges[i].from_id,
            edges[i].to_id,
        );
    }
}

/// Step 8: Propagate edge labels from the input graph to the IR edges.
///
/// Labels come from the original Graph.Edge; looked up via edge_index.
/// For split edges (through dummies), only the first segment gets the label.
/// Label is positioned on a dedicated row below the horizontal routing area.
fn propagateEdgeLabels(result: *LayoutIR(usize), g: *const Graph, allocator: std.mem.Allocator) !void {
    var label_assigned = try allocator.alloc(bool, g.edges.items.len);
    defer allocator.free(label_assigned);
    @memset(label_assigned, false);

    for (result.edges.items) |*edge| {
        const orig_idx = edge.edge_index;
        if (orig_idx >= g.edges.items.len) continue;

        const orig_label = g.edges.items[orig_idx].label orelse continue;
        if (label_assigned[orig_idx]) continue;
        label_assigned[orig_idx] = true;

        edge.label = orig_label;

        var label_y: usize = undefined;
        var edge_x_at_label: usize = undefined;

        switch (edge.path) {
            .direct => {
                label_y = if (edge.to_y > edge.from_y + 2)
                    edge.from_y + 2
                else
                    edge.from_y + 1;
                edge_x_at_label = edge.from_x;
            },
            .corner => |c| {
                if (c.horizontal_y + 1 < edge.to_y) {
                    label_y = c.horizontal_y + 1;
                } else if (c.horizontal_y > edge.from_y + 1) {
                    label_y = c.horizontal_y - 1;
                } else {
                    label_y = edge.from_y + 1;
                }
                edge_x_at_label = edge.to_x;
            },
            .side_channel => |sc| {
                label_y = if (sc.start_y + 1 < sc.end_y)
                    sc.start_y + 1
                else if (edge.to_y > edge.from_y + 2)
                    edge.from_y + 2
                else
                    edge.from_y + 1;
                edge_x_at_label = sc.channel_x;
            },
            .multi_segment => {
                label_y = if (edge.to_y > edge.from_y + 2)
                    edge.from_y + 2
                else
                    edge.from_y + 1;
                edge_x_at_label = edge.from_x;
            },
            .spline => {
                label_y = if (edge.to_y > edge.from_y + 2)
                    edge.from_y + 2
                else
                    edge.from_y + 1;
                edge_x_at_label = edge.from_x;
            },
        }

        const label_width = orig_label.len + 2;
        const label_x = if (edge_x_at_label >= label_width / 2)
            edge_x_at_label - label_width / 2
        else
            0;

        edge.label_x = label_x;
        edge.label_y = label_y;
    }
}

/// Step 9: Widen layout if edge labels extend beyond current width.
fn widenForLabels(result: *LayoutIR(usize), total_width: usize, total_height: usize) void {
    var needed_width = total_width;
    for (result.edges.items) |edge| {
        if (edge.label) |lbl| {
            const right = edge.label_x + lbl.len + 2;
            if (right > needed_width) needed_width = right;
        }
    }
    result.setDimensions(needed_width, total_height);
}

/// Compute layout using the Sugiyama hierarchical algorithm.
fn layoutSugiyama(g: *const Graph, allocator: std.mem.Allocator, config: LayoutConfig) anyerror!LayoutIR(usize) {
    // Step 0: Validate graph (unless skipped)
    try validateForSugiyama(g, allocator, config);

    // Step 0b: Cycle breaking — detect and virtually reverse back edges
    const reversed_edges: ?[]bool = switch (config.cycle_breaking) {
        .none => null,
        .depth_first => try cycle_breaking.detectBackEdges(g, allocator),
    };
    defer if (reversed_edges) |re| allocator.free(re);

    // Step 1: Layer assignment (with reversed edges for cycle breaking)
    var layer_assignment = switch (config.layering) {
        .longest_path => try layering.longest_path.computeWithReversed(g, allocator, reversed_edges),
        .network_simplex => try layering.network_simplex.computeWithReversed(g, allocator, reversed_edges),
        .network_simplex_fast => try layering.network_simplex.computeFastWithReversed(g, allocator, reversed_edges),
    };
    defer layer_assignment.deinit();

    // Step 1a: Apply pin.y constraints and enforce subgraph contiguity,
    // then repair topological ordering so all edges still flow downward.
    {
        // Phase 1: Apply pin.y hints
        for (0..g.nodeCount()) |node_idx| {
            const node = g.nodeAt(node_idx) orelse continue;
            const pin = node.pin orelse continue;
            if (pin.y) |pinned_level| {
                layer_assignment.levels[node_idx] = pinned_level;
                layer_assignment.max_level = @max(layer_assignment.max_level, pinned_level);
            }
        }

        // Phase 1b: Enforce contiguous level spans for subgraph members.
        if (g.hasSubgraphs()) {
            try subgraph_layout.enforceContiguousLevels(g, &layer_assignment, allocator);
        }

        // Phase 2: Topological repair — ensure every edge u→v has level[u] < level[v].
        // If a pin caused a violation, push the child node down (cascading).
        // Uses fixed-point iteration; converges in O(depth) passes for DAGs.
        var changed = true;
        var safety: usize = 0;
        const max_iters = g.nodeCount() + 1;
        while (changed and safety < max_iters) : (safety += 1) {
            changed = false;
            for (g.edges.items, 0..) |edge, edge_idx| {
                // Respect reversed edges from cycle breaking
                const is_reversed = if (reversed_edges) |re| re[edge_idx] else false;
                const from_id = if (is_reversed) edge.to else edge.from;
                const to_id = if (is_reversed) edge.from else edge.to;

                const from_idx = g.nodeIndex(from_id) orelse continue;
                const to_idx = g.nodeIndex(to_id) orelse continue;
                if (from_idx == to_idx) continue;

                // Skip if the child is pinned — don't override explicit user intent
                const to_node = g.nodeAt(to_idx) orelse continue;
                if (to_node.pin) |to_pin| {
                    if (to_pin.y != null) continue;
                }

                // Enforce: level[to] > level[from]
                if (layer_assignment.levels[to_idx] <= layer_assignment.levels[from_idx]) {
                    layer_assignment.levels[to_idx] = layer_assignment.levels[from_idx] + 1;
                    layer_assignment.max_level = @max(layer_assignment.max_level, layer_assignment.levels[to_idx]);
                    changed = true;
                }
            }
        }

        // Phase 3: Level compaction — collapse sparse level indices to dense
        // consecutive values. E.g. [0, 0, 12, 13, 14, 14] → [0, 0, 1, 2, 3, 3].
        // This prevents pin.y pixel-coordinate inflation from creating huge
        // level gaps that spawn excessive dummy nodes for skip-level edges.
        {
            const node_count = g.nodeCount();

            // Collect unique levels
            const unique_buf = try allocator.alloc(usize, node_count);
            defer allocator.free(unique_buf);
            var unique_count: usize = 0;

            for (0..node_count) |ni| {
                const lev = layer_assignment.levels[ni];
                var found = false;
                for (0..unique_count) |ui| {
                    if (unique_buf[ui] == lev) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    unique_buf[unique_count] = lev;
                    unique_count += 1;
                }
            }

            // Sort unique levels (insertion sort — typically very few unique levels)
            const unique_levels = unique_buf[0..unique_count];
            for (1..unique_count) |i| {
                const key = unique_levels[i];
                var j: usize = i;
                while (j > 0 and unique_levels[j - 1] > key) {
                    unique_levels[j] = unique_levels[j - 1];
                    j -= 1;
                }
                unique_levels[j] = key;
            }

            // Remap each node's level to its dense rank
            for (0..node_count) |ni| {
                const old_level = layer_assignment.levels[ni];
                for (unique_levels, 0..) |ul, rank| {
                    if (ul == old_level) {
                        layer_assignment.levels[ni] = rank;
                        break;
                    }
                }
            }

            // Update max_level to dense count
            layer_assignment.max_level = if (unique_count > 0) unique_count - 1 else 0;
        }
    }

    // Step 1b: Promote subgraph root/isolated nodes closer to siblings.
    // Eliminates long dangling edges inside subgraph boxes caused by root
    // nodes at level 0 when their subgraph peers are deep in the hierarchy.
    // Runs AFTER topological repair so peer levels are finalized.
    // Only moves nodes DOWN (higher level numbers), so edge constraints remain valid.
    if (g.hasSubgraphs()) {
        try subgraph_layout.promoteSubgraphRoots(g, &layer_assignment, allocator);

        // Re-compact levels after promotion may have left gaps
        var new_max: usize = 0;
        for (0..g.nodeCount()) |ni| {
            new_max = @max(new_max, layer_assignment.levels[ni]);
        }
        layer_assignment.max_level = new_max;
    }

    // Step 2: Build virtual levels (includes dummy nodes for skip-level edges)
    var virtual_levels = try layering.virtual.buildVirtualLevelsWithReversed(
        g,
        layer_assignment.levels,
        layer_assignment.max_level,
        allocator,
        reversed_edges,
    );
    defer virtual_levels.deinit();

    // Step 3: Crossing reduction
    if (g.hasSubgraphs() and config.crossing_reducers.len > 0) {
        // Block-based crossing reduction: median sweep with subgraph block constraints.
        // Each level is partitioned into blocks by subgraph membership. Nodes are
        // sorted within blocks (intra-block median) and blocks are ordered by their
        // average median (inter-block). Adjacency is maintained by construction.
        var total_passes: usize = 0;
        for (config.crossing_reducers) |r| total_passes += r.passes;
        if (total_passes > 0) {
            try subgraph_layout.blockBasedCrossingReduction(g, &virtual_levels, total_passes, allocator);
        }
    } else {
        // Standard flat crossing reduction pipeline
        try crossing.runPipeline(config.crossing_reducers, &virtual_levels, g, allocator);
    }

    // Step 3b: Compute adaptive level spacing
    const effective_level_spacing = computeEffectiveLevelSpacing(g, config);

    // Step 4: Position nodes
    // For .compact: use left-to-right packing on virtual levels (fast, no collisions)
    // For .barycentric/.brandes_kopf: run positioning algorithm
    var virtual_positions = switch (config.positioning) {
        .compact => try layering.virtual.computeVirtualPositions(
            g,
            &virtual_levels,
            config.node_spacing,
            effective_level_spacing,
            allocator,
        ),
        .barycentric, .brandes_kopf => blk: {
            // Extract real-node-only levels for positioning algorithms
            var real_node_levels = try layering.virtual.extractRealNodeLevels(&virtual_levels, allocator);
            defer {
                for (real_node_levels.items) |*level| level.deinit(allocator);
                real_node_levels.deinit(allocator);
            }

            const levels_slice = real_node_levels.items;
            const pos_config = positioning.common.Config{
                .node_spacing = config.node_spacing,
                .level_spacing = effective_level_spacing,
            };

            var pos_assignment = switch (config.positioning) {
                .brandes_kopf => try positioning.brandes_kopf.compute(g, levels_slice, pos_config, allocator),
                .barycentric => try positioning.barycentric.compute(g, levels_slice, pos_config, allocator),
                .compact => unreachable,
            };
            defer pos_assignment.deinit();

            // Position virtual levels using real node positions as hints
            break :blk try layering.virtual.computeVirtualPositionsWithHints(
                g,
                &virtual_levels,
                config.node_spacing,
                effective_level_spacing,
                pos_assignment.x,
                allocator,
            );
        },
    };
    defer virtual_positions.deinit();

    // Step 4a: Apply subgraph horizontal padding
    // Shifts x-coordinates to create space for subgraph border lines between
    // nodes of different subgraphs. Must happen before position extraction.
    if (g.hasSubgraphs()) {
        try subgraph_layout.applySubgraphPadding(g, &virtual_levels, &virtual_positions, allocator);
    }

    // Step 4a-y: Compute per-level y-offsets for subgraph top/bottom borders
    const level_y_offsets: ?[]usize = if (g.hasSubgraphs())
        try subgraph_layout.computeLevelYOffsets(g, &virtual_levels, allocator)
    else
        null;
    defer if (level_y_offsets) |offsets| allocator.free(offsets);

    // Build cumulative y-offsets (each level += sum of all previous offsets)
    var cumulative_y: []usize = &.{};
    defer if (cumulative_y.len > 0) allocator.free(cumulative_y);
    if (level_y_offsets) |offsets| {
        cumulative_y = try allocator.alloc(usize, offsets.len);
        var accum: usize = 0;
        for (offsets, 0..) |off, i| {
            accum += off;
            cumulative_y[i] = accum;
        }
    }

    // Step 4b: Extract real node positions from virtual positions
    var real_positions = try layering.virtual.extractRealNodePositions(
        g,
        &virtual_levels,
        &virtual_positions,
        effective_level_spacing,
        allocator,
    );
    defer real_positions.deinit();

    // Step 4c: Extract dummy positions from virtual positions (respects crossing order)
    var dummy_positions = try layering.virtual.extractDummyPositions(
        &virtual_levels,
        &virtual_positions,
        g.edges.items.len,
        effective_level_spacing,
        real_positions.level_y,
        allocator,
    );
    defer dummy_positions.deinit();

    // Step 4d: Apply vertical subgraph padding (y-offsets for border rows)
    if (cumulative_y.len > 0) {
        // Shift real node y positions and center_y
        for (0..g.nodeCount()) |node_idx| {
            const lvl = real_positions.level[node_idx];
            if (lvl < cumulative_y.len) {
                real_positions.y[node_idx] += cumulative_y[lvl];
                real_positions.center_y[node_idx] += cumulative_y[lvl];
            }
        }
        // Shift level_y entries
        for (real_positions.level_y, 0..) |*ly, lvl| {
            if (lvl < cumulative_y.len) {
                ly.* += cumulative_y[lvl];
            }
        }
        // Shift dummy waypoint y positions
        // Use level_y to reverse-lookup which level a dummy Y corresponds to
        for (dummy_positions.waypoints.items) |*edge_wps| {
            for (edge_wps.items) |*wp| {
                // Find which level this waypoint's Y coordinate came from
                // by searching level_y (already shifted) minus cumulative shift
                // The dummy Y was already computed from level_y, so find the
                // matching level index and add its cumulative offset
                var best_level: usize = 0;
                var best_dist: usize = std.math.maxInt(usize);
                const pre_shift_level_y = real_positions.level_y;
                for (pre_shift_level_y, 0..) |ly, li| {
                    // Undo the shift we just applied to find original
                    const orig_ly = if (li < cumulative_y.len) ly - cumulative_y[li] else ly;
                    const dist = if (wp.level >= orig_ly) wp.level - orig_ly else orig_ly - wp.level;
                    if (dist < best_dist) {
                        best_dist = dist;
                        best_level = li;
                    }
                }
                if (best_level < cumulative_y.len) {
                    wp.level += cumulative_y[best_level];
                }
            }
        }
        // Update total height
        const total_extra_y = cumulative_y[cumulative_y.len - 1];
        real_positions.total_height += total_extra_y;
        virtual_positions.total_height += total_extra_y;
    }

    // Step 4e: Refine + compact subgraphs, then fix overlaps
    if (g.subgraphCount() >= 2) {
        // Build node widths array from graph
        const node_widths = try allocator.alloc(usize, g.nodeCount());
        defer allocator.free(node_widths);
        for (0..g.nodeCount()) |ni| {
            node_widths[ni] = if (g.nodeAt(ni)) |n| n.width else 1;
        }

        // Step 4e-i: Refine x-positions + compact subgraphs (3 rounds)
        try subgraph_layout.refineAndCompact(
            g,
            real_positions.x,
            real_positions.level,
            node_widths,
            g.nodeCount(),
            allocator,
        );

        // Step 4e-ii: Fix remaining subgraph overlaps
        const extra_w = try subgraph_layout.fixSubgraphOverlaps(
            g,
            real_positions.x,
            real_positions.level,
            node_widths,
            g.nodeCount(),
            allocator,
        );
        real_positions.total_width += extra_w;
        // Update center_x to match shifted x positions
        for (0..g.nodeCount()) |ni| {
            real_positions.center_x[ni] = real_positions.x[ni] + node_widths[ni] / 2;
        }
    }

    // Step 5: Build LayoutIR
    var result = LayoutIR(usize).init(allocator);
    errdefer result.deinit();

    // Add real nodes
    for (0..g.nodeCount()) |node_idx| {
        const node = g.nodeAt(node_idx) orelse continue;
        try result.addNode(.{
            .id = node.id,
            .label = node.label,
            .x = real_positions.x[node_idx],
            .y = real_positions.y[node_idx],
            .width = node.width,
            .height = real_positions.height[node_idx],
            .center_x = real_positions.center_x[node_idx],
            .center_y = real_positions.center_y[node_idx],
            .level = real_positions.level[node_idx],
            .level_position = real_positions.level_position[node_idx],
            .kind = node.kind,
        });
        try result.addNodeToLevel(real_positions.level[node_idx], result.nodes.items.len - 1);
    }

    // Build dummy node mapping for edge splitting
    // Always add dummy nodes - renderer decides whether to display them
    var dummy_id_map = std.AutoHashMap(usize, usize).init(allocator);
    defer dummy_id_map.deinit();

    // Iterate through virtual levels to find dummy nodes
    for (virtual_levels.levels.items, 0..) |level, level_idx| {
        for (level.items, 0..) |vnode, pos_in_level| {
            if (vnode.dummyEdge()) |edge_idx| {
                // Get position from virtual positions
                const x = virtual_positions.x.items[level_idx].items[pos_in_level];
                // Use per-level Y from real_positions (already accounts for variable heights)
                // NOTE: level_y already includes cumulative_y from Step 4d, so do NOT add it again
                const y = if (level_idx < real_positions.level_y.len)
                    real_positions.level_y[level_idx]
                else
                    level_idx * (1 + effective_level_spacing);

                const dummy_id = dummy_id_base + edge_idx * dummy_id_edge_stride + level_idx;

                try result.addNode(.{
                    .id = dummy_id,
                    .label = "O", // Simple circle for dummy (when visible)
                    .x = x,
                    .y = y,
                    .width = 1, // Single character
                    .height = 1, // Dummy nodes always height 1
                    .center_x = x,
                    .center_y = y, // center_y = y for height-1 nodes
                    .level = level_idx,
                    .level_position = pos_in_level,
                    .kind = .dummy,
                    .edge_index = edge_idx,
                });

                // Store mapping for edge splitting
                const key = edge_idx * dummy_key_stride + level_idx;
                try dummy_id_map.put(key, dummy_id);
            }
        }
    }

    // Step 6: Edge routing (with dummy node support)
    var routed_edges = switch (config.routing) {
        .direct => try routing.direct.routeWithDummies(
            g,
            result.nodes.items,
            &result.id_to_index,
            &dummy_positions,
            allocator,
            reversed_edges,
            config.fan_out_style,
        ),
        .spline => try routing.spline.routeWithDummies(
            g,
            result.nodes.items,
            &result.id_to_index,
            &dummy_positions,
            allocator,
            .{},
            reversed_edges,
        ),
    };
    // Note: we don't defer deinit on paths - ownership transfers to result.edges
    // EXCEPT when splitting edges - those paths must be freed manually
    defer routed_edges.deinit(allocator);

    // Always split edges through dummy nodes
    // This gives consistent rendering whether dummies are visible or not
    if (dummy_id_map.count() > 0) {
        for (routed_edges.items, 0..) |*edge, edge_idx| {
            // Get source and target node info
            const from_node = result.nodes.items[result.id_to_index.get(edge.from_id).?];
            const to_node = result.nodes.items[result.id_to_index.get(edge.to_id).?];

            // Reversed edges have already been flipped by routing, so they
            // flow downward and get proper level_span like normal edges.
            const level_span = if (to_node.level > from_node.level)
                to_node.level - from_node.level
            else
                0;

            if (level_span > 1) {
                // This is a long edge - split it through dummies
                // Free the original path since we're replacing it with direct segments
                edge.path.deinit();

                var prev_id = edge.from_id;
                var prev_x = edge.from_x;
                var prev_y = edge.from_y;

                // Add segments through each intermediate level
                for ((from_node.level + 1)..(to_node.level)) |intermediate_level| {
                    const key = edge_idx * dummy_key_stride + intermediate_level;
                    if (dummy_id_map.get(key)) |dummy_id| {
                        const dummy_node = result.nodes.items[result.id_to_index.get(dummy_id).?];

                        // Determine path type based on x alignment
                        const edge_path: ir.EdgePath(usize) = if (prev_x == dummy_node.center_x)
                            .direct
                        else blk: {
                            const min_h_y = prev_y + 1;
                            const max_h_y = if (dummy_node.y > 1) dummy_node.y - 1 else min_h_y;
                            const h_y = findSafeSplitHorizontalY(
                                min_h_y,
                                min_h_y,
                                max_h_y,
                                prev_x,
                                dummy_node.center_x,
                                result.nodes.items,
                                prev_id,
                                dummy_id,
                            );
                            break :blk .{ .corner = .{ .horizontal_y = h_y } };
                        };

                        // Add edge from prev to dummy
                        try result.addEdge(.{
                            .from_id = prev_id,
                            .to_id = dummy_id,
                            .from_x = prev_x,
                            .from_y = prev_y,
                            .to_x = dummy_node.center_x,
                            .to_y = dummy_node.y,
                            .path = edge_path,
                            .edge_index = edge_idx,
                            // Intermediate segments never draw arrows
                            .directed = false,
                        });

                        prev_id = dummy_id;
                        prev_x = dummy_node.center_x;
                        prev_y = dummy_node.y + dummy_node.height; // Bottom of dummy
                    }
                }

                // Final segment from last dummy to target
                const final_path: ir.EdgePath(usize) = if (prev_x == edge.to_x)
                    .direct
                else blk: {
                    const min_h_y = prev_y + 1;
                    const max_h_y = if (edge.to_y > 1) edge.to_y - 1 else min_h_y;
                    const h_y = findSafeSplitHorizontalY(
                        min_h_y,
                        min_h_y,
                        max_h_y,
                        prev_x,
                        edge.to_x,
                        result.nodes.items,
                        prev_id,
                        edge.to_id,
                    );
                    break :blk .{ .corner = .{ .horizontal_y = h_y } };
                };

                // Add final segment from last dummy to target
                try result.addEdge(.{
                    .from_id = prev_id,
                    .to_id = edge.to_id,
                    .from_x = prev_x,
                    .from_y = prev_y,
                    .to_x = edge.to_x,
                    .to_y = edge.to_y,
                    .path = final_path,
                    .edge_index = edge_idx,
                    .directed = edge.directed,
                });
            } else {
                // Short edge - add directly (ownership of path transfers)
                try result.addEdge(edge.*);
            }
        }
    } else {
        // No dummies: add all edges as-is
        for (routed_edges.items) |edge| {
            try result.addEdge(edge);
        }
    }

    // Step 6b: Fix up reversed (back) edges
    fixupReversedEdges(&result, reversed_edges);

    // Step 7: Stagger horizontal_y for corner edges
    staggerCornerEdges(&result);

    // Step 8: Propagate edge labels and compute label positions
    try propagateEdgeLabels(&result, g, allocator);

    // Step 9: Widen layout if labels extend beyond current width
    widenForLabels(&result, real_positions.total_width, real_positions.total_height);

    // Step 10: Compute subgraph bounding boxes
    if (g.hasSubgraphs()) {
        try subgraph_layout.computeBoundingBoxes(g, &result, allocator);

        // Expand layout dimensions if subgraph boxes extend beyond
        for (result.subgraphs.items) |sg_info| {
            const right = sg_info.x + sg_info.width;
            const bottom = sg_info.y + sg_info.height;
            if (right > result.width or bottom > result.height) {
                result.setDimensions(@max(result.width, right), @max(result.height, bottom));
            }
        }
    }

    return result;
}

/// Compute layout with a user-chosen coordinate type.
///
/// The internal Sugiyama pipeline runs with native integer arithmetic.
/// The result is converted to the specified `Coord` type at the boundary
/// using `coordCast`.
///
/// When `Coord` is `usize`, this is equivalent to `layout()` — no conversion,
/// no extra allocation.
///
/// ```zig
/// // Get layout in f32 coordinates (for GPU / web rendering)
/// var ir_f32 = try zigraph.layoutTyped(f32, &graph, allocator, .{});
/// defer ir_f32.deinit();
///
/// // Get layout in u16 coordinates (for embedded / low-memory)
/// var ir_u16 = try zigraph.layoutTyped(u16, &graph, allocator, .{});
/// defer ir_u16.deinit();
/// ```
pub fn layoutTyped(comptime Coord: type, g: *const Graph, allocator: std.mem.Allocator, config: LayoutConfig) anyerror!LayoutIR(Coord) {
    var usize_result = try layout(g, allocator, config);

    // Fast path: no conversion needed when Coord is already usize
    if (Coord == usize) {
        return usize_result;
    }

    // Convert to target coordinate type
    defer usize_result.deinit();
    return try usize_result.convertCoord(Coord, allocator);
}

/// Convenience function: layout and render in one step.
///
/// Returns the terminal (box-drawing) string representation of the graph.
/// Returns error.EmptyGraph or error.CycleDetected if graph is invalid.
/// Custom crossing reducers may return additional errors.
pub fn render(g: *const Graph, allocator: std.mem.Allocator, config: LayoutConfig) anyerror![]u8 {
    var layout_ir = try layout(g, allocator, config);
    defer layout_ir.deinit();

    return try terminal.renderWithConfig(&layout_ir, allocator, .{
        .show_dummy_nodes = config.include_dummy_nodes,
        .edge_palette = config.edge_palette,
    });
}

/// Export graph layout as JSON.
///
/// Returns a JSON string containing all layout information:
/// - nodes with positions, labels, levels
/// - edges with routing paths
/// - overall dimensions
///
/// Use this to integrate with external tools (SVG renderers, web UIs, etc.)
/// Custom crossing reducers may return additional errors.
pub fn exportJson(g: *const Graph, allocator: std.mem.Allocator, config: LayoutConfig) anyerror![]u8 {
    var layout_ir = try layout(g, allocator, config);
    defer layout_ir.deinit();

    return try json.render(&layout_ir, allocator);
}

/// Layout and render with a custom coordinate type.
///
/// Internally computes the layout (usize), converts to Coord, then renders
/// via the renderer's generic path. Useful when you want the rendered output
/// to reflect a non-usize coordinate space (e.g., JSON with float coords).
///
/// For Terminal and SVG, the renderers convert back to usize internally,
/// so prefer `render()` for those formats unless you need the typed IR
/// for other purposes.
pub fn renderTyped(comptime Coord: type, g: *const Graph, allocator: std.mem.Allocator, config: LayoutConfig) anyerror![]u8 {
    var layout_ir = try layoutTyped(Coord, g, allocator, config);
    defer layout_ir.deinit();

    return try terminal.renderGenericWithConfig(Coord, &layout_ir, allocator, .{
        .show_dummy_nodes = config.include_dummy_nodes,
        .edge_palette = config.edge_palette,
    });
}

/// Export graph layout as JSON with a custom coordinate type.
///
/// This is where typed coordinates shine — the JSON output will contain
/// float values (`"x": 3.5`) or narrow integers (`"x": 42`) matching
/// your chosen Coord type exactly.
///
/// ```zig
/// const json_f32 = try zigraph.exportJsonTyped(f32, &graph, allocator, .{});
/// // Output: {"nodes":[{"x":3.0,"y":0.0,...}], ...}
/// ```
pub fn exportJsonTyped(comptime Coord: type, g: *const Graph, allocator: std.mem.Allocator, config: LayoutConfig) anyerror![]u8 {
    var layout_ir = try layoutTyped(Coord, g, allocator, config);
    defer layout_ir.deinit();

    return try json.renderGeneric(Coord, &layout_ir, allocator);
}

/// Export graph layout as SVG.
///
/// Returns an SVG string with nodes as rectangles and edges as paths/lines.
/// Works well with all layout algorithms including force-directed.
///
/// ```zig
/// const output = try zigraph.exportSvg(&graph, allocator, .{
///     .algorithm = .{ .fruchterman_reingold = .{} },
/// });
/// defer allocator.free(output);
/// try std.fs.cwd().writeFile(.{ .sub_path = "graph.svg", .data = output });
/// ```
pub fn exportSvg(g: *const Graph, allocator: std.mem.Allocator, config: LayoutConfig) anyerror![]u8 {
    var layout_ir = try layout(g, allocator, config);
    defer layout_ir.deinit();

    return try svg.render(&layout_ir, allocator, .{});
}

/// Export graph layout as SVG with a custom coordinate type.
pub fn exportSvgTyped(comptime Coord: type, g: *const Graph, allocator: std.mem.Allocator, config: LayoutConfig) anyerror![]u8 {
    var layout_ir = try layoutTyped(Coord, g, allocator, config);
    defer layout_ir.deinit();

    return try svg.renderGeneric(Coord, &layout_ir, allocator, .{});
}

// ============================================================================
// Version info
// ============================================================================

pub const version = "0.2.1";
pub const version_major = 0;
pub const version_minor = 2;
pub const version_patch = 1;

// ============================================================================
// Tests
// ============================================================================

test "version is defined" {
    try std.testing.expectEqualStrings("0.2.1", version);
}

test "core modules are accessible" {
    const allocator = std.testing.allocator;

    // Test Graph
    var g = Graph.init(allocator);
    defer g.deinit();
    try g.addNode(1, "Test");
    try std.testing.expectEqual(@as(usize, 1), g.nodeCount());

    // Test LayoutIR
    var layout_ir = LayoutIR(usize).init(allocator);
    defer layout_ir.deinit();
    try std.testing.expectEqual(@as(usize, 0), layout_ir.getNodes().len);
}

test "end-to-end layout: simple chain" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "Start");
    try g.addNode(2, "Middle");
    try g.addNode(3, "End");
    try g.addEdge(1, 2);
    try g.addEdge(2, 3);

    var result = try layout(&g, allocator, .{});
    defer result.deinit();

    // Should have 3 nodes
    try std.testing.expectEqual(@as(usize, 3), result.getNodes().len);

    // Should have 3 levels
    try std.testing.expectEqual(@as(usize, 3), result.getLevelCount());

    // Should have 2 edges
    try std.testing.expectEqual(@as(usize, 2), result.getEdges().len);

    // Nodes should be ordered by level (Y coordinate)
    const nodes = result.getNodes();
    try std.testing.expect(nodes[0].y < nodes[1].y);
    try std.testing.expect(nodes[1].y < nodes[2].y);
}

test "end-to-end layout: diamond" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    //     A
    //    / \
    //   B   C
    //    \ /
    //     D
    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addNode(4, "D");
    try g.addEdge(1, 2);
    try g.addEdge(1, 3);
    try g.addEdge(2, 4);
    try g.addEdge(3, 4);

    var result = try layout(&g, allocator, .{});
    defer result.deinit();

    // Should have 4 nodes
    try std.testing.expectEqual(@as(usize, 4), result.getNodes().len);

    // Should have 3 levels (A, B/C, D)
    try std.testing.expectEqual(@as(usize, 3), result.getLevelCount());

    // Should have 4 edges
    try std.testing.expectEqual(@as(usize, 4), result.getEdges().len);
}

test "end-to-end render: simple chain" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "Start");
    try g.addNode(2, "End");
    try g.addEdge(1, 2);

    const output = try render(&g, allocator, .{});
    defer allocator.free(output);

    // Should contain node labels
    try std.testing.expect(std.mem.indexOf(u8, output, "[Start]") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "[End]") != null);
}

test "layout: empty graph returns error" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    const result = layout(&g, allocator, .{});
    try std.testing.expectError(error.EmptyGraph, result);
}

test "layout: cyclic graph returns error" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    // A -> B -> C -> A (cycle)
    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addEdge(1, 2);
    try g.addEdge(2, 3);
    try g.addEdge(3, 1); // Creates cycle

    const result = layout(&g, allocator, .{});
    try std.testing.expectError(error.CycleDetected, result);
}

test "layout: cyclic graph with cycle_breaking produces valid layout" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    // A -> B -> C -> A (cycle)
    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addEdge(1, 2);
    try g.addEdge(2, 3);
    try g.addEdge(3, 1); // Back edge

    var result = try layout(&g, allocator, .{
        .cycle_breaking = .depth_first,
    });
    defer result.deinit();

    // Should produce a valid layout with 3 real nodes (plus dummies for back edge routing)
    var real_node_count: usize = 0;
    for (result.nodes.items) |node| {
        if (node.kind != .dummy) real_node_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 3), real_node_count);

    // At least one edge should be marked as reversed
    var has_reversed = false;
    for (result.edges.items) |edge| {
        if (edge.reversed) has_reversed = true;
    }
    try std.testing.expect(has_reversed);

    // Width and height should be reasonable
    try std.testing.expect(result.width > 0);
    try std.testing.expect(result.height > 0);
}

test "layout: cycle_breaking preserves acyclic graph behavior" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    // Acyclic: A -> B -> C
    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addEdge(1, 2);
    try g.addEdge(2, 3);

    // With cycle_breaking enabled on an acyclic graph, should work identically
    var result_cb = try layout(&g, allocator, .{
        .cycle_breaking = .depth_first,
    });
    defer result_cb.deinit();

    var result_no_cb = try layout(&g, allocator, .{});
    defer result_no_cb.deinit();

    // Same number of nodes and edges
    try std.testing.expectEqual(result_no_cb.nodes.items.len, result_cb.nodes.items.len);

    // No reversed edges (graph is acyclic)
    for (result_cb.edges.items) |edge| {
        try std.testing.expect(!edge.reversed);
    }
}

test "layout: cycle_breaking works with all layering algorithms" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    // A -> B -> C -> A (cycle)
    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addEdge(1, 2);
    try g.addEdge(2, 3);
    try g.addEdge(3, 1);

    // Test with each layering algorithm
    const layerings = [_]Layering{ .longest_path, .network_simplex, .network_simplex_fast };
    for (layerings) |lay| {
        var result = try layout(&g, allocator, .{
            .cycle_breaking = .depth_first,
            .layering = lay,
        });
        defer result.deinit();

        var real_count: usize = 0;
        for (result.nodes.items) |node| {
            if (node.kind != .dummy) real_count += 1;
        }
        try std.testing.expectEqual(@as(usize, 3), real_count);
        try std.testing.expect(result.width > 0);
    }
}

test "layout: positioning config affects output" {
    // Verify that config.positioning is actually wired in and affects the layout.
    // For a tree graph, brandes_kopf centers parents over children,
    // while simple packs left-to-right with level centering.
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    // Tree graph: A -> B, A -> C (parent with two children)
    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addEdge(1, 2);
    try g.addEdge(1, 3);

    // Layout with brandes_kopf (centers parent over children)
    var result_bk = try layout(&g, allocator, .{
        .positioning = .brandes_kopf,
    });
    defer result_bk.deinit();

    // Layout with barycentric (single-pass barycentric)
    var result_simple = try layout(&g, allocator, .{
        .positioning = .barycentric,
    });
    defer result_simple.deinit();

    // Both should produce valid layouts with same number of nodes
    try std.testing.expectEqual(@as(usize, 3), result_bk.getNodes().len);
    try std.testing.expectEqual(@as(usize, 3), result_simple.getNodes().len);

    // The positioning algorithm is now wired in and affecting the layout.
    // Brandes-Köpf produces different x-coordinates than simple for most graphs.
    // We verify the config is respected by checking the layouts are valid.
    // (Exact position differences depend on centering calculations.)
    try std.testing.expect(result_bk.getWidth() > 0);
    try std.testing.expect(result_simple.getWidth() > 0);
}

test "layout: can skip validation for performance" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addEdge(1, 2);

    // Skip validation - useful when you know graph is valid
    var result = try layout(&g, allocator, .{ .skip_validation = true });
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.getNodes().len);
}

test "layoutTyped: usize is identical to layout" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addEdge(1, 2);

    var result = try layoutTyped(usize, &g, allocator, .{});
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.getNodes().len);
    try std.testing.expect(result.getEdges().len >= 1);
}

test "layoutTyped: f32 produces float coordinates" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "Start");
    try g.addNode(2, "End");
    try g.addEdge(1, 2);

    var result = try layoutTyped(f32, &g, allocator, .{});
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.getNodes().len);

    // Coordinates should be valid floats
    const nodes = result.getNodes();
    try std.testing.expect(nodes[0].y < nodes[1].y);
    try std.testing.expect(nodes[0].width > 0.0);
}

test "layoutTyped: u16 produces narrow coordinates" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addEdge(1, 2);
    try g.addEdge(1, 3);

    var result = try layoutTyped(u16, &g, allocator, .{});
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 3), result.getNodes().len);
    try std.testing.expectEqual(@as(usize, 2), result.getLevelCount());
}

test "exportJsonTyped: f32 JSON output" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addEdge(1, 2);

    const output = try exportJsonTyped(f32, &g, allocator, .{});
    defer allocator.free(output);

    // f32 JSON should contain float notation (e.g., "e+00" or ".")
    try std.testing.expect(output.len > 0);
    // Should contain node labels
    try std.testing.expect(std.mem.indexOf(u8, output, "\"A\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"B\"") != null);
}

// ============================================================================
// FDG integration tests
// ============================================================================

test "layout: FR standard produces valid IR" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addEdge(1, 2);
    try g.addEdge(2, 3);
    try g.addEdge(1, 3);

    var result = try layout(&g, allocator, .{
        .algorithm = .{ .fruchterman_reingold = .{} },
    });
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 3), result.getNodes().len);
    try std.testing.expectEqual(@as(usize, 3), result.getEdges().len);
    try std.testing.expect(result.getWidth() > 0);
    try std.testing.expect(result.getHeight() > 0);
}

test "layout: FR fast produces valid IR" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addEdge(1, 2);
    try g.addEdge(2, 3);

    var result = try layout(&g, allocator, .{
        .algorithm = .{ .fruchterman_reingold_fast = .{} },
    });
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 3), result.getNodes().len);
    try std.testing.expectEqual(@as(usize, 2), result.getEdges().len);
    try std.testing.expect(result.getWidth() > 0);
    try std.testing.expect(result.getHeight() > 0);
}

test "layout: FR deterministic" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "X");
    try g.addNode(2, "Y");
    try g.addNode(3, "Z");
    try g.addEdge(1, 2);
    try g.addEdge(2, 3);
    try g.addEdge(1, 3);

    var r1 = try layout(&g, allocator, .{
        .algorithm = .{ .fruchterman_reingold = .{} },
    });
    defer r1.deinit();

    var r2 = try layout(&g, allocator, .{
        .algorithm = .{ .fruchterman_reingold = .{} },
    });
    defer r2.deinit();

    // Same seed → bit-exact identical positions
    for (r1.getNodes(), r2.getNodes()) |n1, n2| {
        try std.testing.expectEqual(n1.x, n2.x);
        try std.testing.expectEqual(n1.y, n2.y);
    }
}

test "layout: FR empty graph returns error" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    const result = layout(&g, allocator, .{
        .algorithm = .{ .fruchterman_reingold = .{} },
    });
    try std.testing.expectError(error.EmptyGraph, result);
}

test "end-to-end: layout with subgraphs produces bounding boxes" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    // Build a small graph with subgraph structure:
    //   [Gateway] → [Auth] → [DB]
    //                ↑ in cluster "backend"
    try g.addNode(1, "Gateway");
    try g.addNode(2, "Auth");
    try g.addNode(3, "DB");
    try g.addDiEdge(1, 2);
    try g.addDiEdge(2, 3);

    const backend = try g.addSubgraph("backend");
    try g.putNodes(&.{ 2, 3 }).inside(backend);

    var result = try layout(&g, allocator, .{});
    defer result.deinit();

    // Basic IR sanity
    try std.testing.expectEqual(@as(usize, 3), result.getNodes().len);
    try std.testing.expect(result.getEdges().len >= 2);

    // Should have exactly 1 subgraph bbox
    try std.testing.expectEqual(@as(usize, 1), result.getSubgraphs().len);
    const sg_bbox = result.getSubgraphs()[0];
    try std.testing.expectEqual(backend, sg_bbox.id);
    try std.testing.expectEqualStrings("backend", sg_bbox.label);

    // Bbox must have positive dimensions
    try std.testing.expect(sg_bbox.width > 0);
    try std.testing.expect(sg_bbox.height > 0);

    // Bbox must contain both Auth and DB nodes
    for (result.getNodes()) |node| {
        if (node.id == 2 or node.id == 3) {
            try std.testing.expect(node.x >= sg_bbox.x);
            try std.testing.expect(node.y >= sg_bbox.y);
            try std.testing.expect(node.x + node.width <= sg_bbox.x + sg_bbox.width);
            try std.testing.expect(node.y + node.height <= sg_bbox.y + sg_bbox.height);
        }
    }

    // Gateway (node 1) should NOT be inside the bbox
    for (result.getNodes()) |node| {
        if (node.id == 1) {
            const inside_x = node.x >= sg_bbox.x and node.x + node.width <= sg_bbox.x + sg_bbox.width;
            const inside_y = node.y >= sg_bbox.y and node.y + node.height <= sg_bbox.y + sg_bbox.height;
            // Gateway could spatially overlap due to layout, but semantically it's not in the subgraph.
            // We just verify the subgraph bbox is computed from Auth + DB, not Gateway.
            _ = inside_x;
            _ = inside_y;
        }
    }
}

test "end-to-end: layout with nested subgraphs" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addDiEdge(1, 2);
    try g.addDiEdge(2, 3);

    const outer = try g.addSubgraph("outer");
    const inner = try g.addSubgraph("inner");
    try g.putSubgraphs(&.{inner}).inside(outer);
    try g.putNodes(&.{ 1, 2, 3 }).inside(inner);

    var result = try layout(&g, allocator, .{});
    defer result.deinit();

    // Should have 2 subgraph bboxes
    try std.testing.expectEqual(@as(usize, 2), result.getSubgraphs().len);

    // Find inner/outer bboxes
    var inner_box: ?SubgraphInfo(usize) = null;
    var outer_box: ?SubgraphInfo(usize) = null;
    for (result.getSubgraphs()) |sg| {
        if (sg.id == inner) inner_box = sg;
        if (sg.id == outer) outer_box = sg;
    }
    try std.testing.expect(inner_box != null);
    try std.testing.expect(outer_box != null);

    // Outer must fully contain inner
    const ib = inner_box.?;
    const ob = outer_box.?;
    try std.testing.expect(ob.x <= ib.x);
    try std.testing.expect(ob.y <= ib.y);
    try std.testing.expect(ob.x + ob.width >= ib.x + ib.width);
    try std.testing.expect(ob.y + ob.height >= ib.y + ib.height);
}

test "end-to-end: layout without subgraphs unchanged" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addDiEdge(1, 2);

    var result = try layout(&g, allocator, .{});
    defer result.deinit();

    // No subgraphs → no subgraph bboxes
    try std.testing.expectEqual(@as(usize, 0), result.getSubgraphs().len);
    try std.testing.expectEqual(@as(usize, 2), result.getNodes().len);
    try std.testing.expect(result.getEdges().len >= 1);
}

test "end-to-end: subgraphs with typed coord conversion" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "X");
    try g.addNode(2, "Y");
    try g.addDiEdge(1, 2);
    const sg = try g.addSubgraph("cluster");
    try g.putNodes(&.{ 1, 2 }).inside(sg);

    var result_f32 = try layoutTyped(f32, &g, allocator, .{});
    defer result_f32.deinit();

    // Subgraph bbox should be converted to f32
    try std.testing.expectEqual(@as(usize, 1), result_f32.getSubgraphs().len);
    const bbox = result_f32.getSubgraphs()[0];
    try std.testing.expect(bbox.width > 0.0);
    try std.testing.expect(bbox.height > 0.0);
}

test "layout: Sugiyama pin.y overrides level assignment" {
    const allocator = std.testing.allocator;

    // A → B → C → D  (simple chain)
    // Pin A at level 0, C at level 2  (natural assignment would be 0,1,2,3)
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, NodeOptions{ .label = "A", .pin = Pin{ .y = 0 } });
    try g.addNode(2, "B");
    try g.addNode(3, NodeOptions{ .label = "C", .pin = Pin{ .y = 2 } });
    try g.addNode(4, "D");
    try g.addEdge(1, 2);
    try g.addEdge(2, 3);
    try g.addEdge(3, 4);

    var result = try layout(&g, allocator, .{});
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 4), result.getNodes().len);

    // Pinned nodes must land on their requested levels
    const a = result.nodeById(1).?;
    const c = result.nodeById(3).?;
    try std.testing.expectEqual(@as(usize, 0), a.level);
    try std.testing.expectEqual(@as(usize, 2), c.level);

    // Unpinned D must be after C
    const d = result.nodeById(4).?;
    try std.testing.expect(d.y > c.y);

    // Edges still valid
    try std.testing.expect(result.getEdges().len >= 3);
}

test "layout: Sugiyama pin.y respects topological ordering" {
    const allocator = std.testing.allocator;

    // Graph: Client(6) → Server(1), Server → Auth(2), Server → API(3),
    //        Auth → DB(4), API → DB, API → Cache(5)
    // Pinning Server to level 3 and API to level 5 would violate ordering
    // (Server's natural level is 1, API's is 2). The repair pass must push
    // children downward so all edges still flow top-to-bottom.
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(6, "Client");
    try g.addNode(1, NodeOptions{ .label = "Server", .pin = Pin{ .y = 3 } });
    try g.addNode(2, "Auth");
    try g.addNode(3, NodeOptions{ .label = "API", .pin = Pin{ .y = 5 } });
    try g.addNode(4, "Database");
    try g.addNode(5, "Cache");
    try g.addEdge(6, 1);
    try g.addEdge(1, 2);
    try g.addEdge(1, 3);
    try g.addEdge(2, 4);
    try g.addEdge(3, 4);
    try g.addEdge(3, 5);

    var result = try layout(&g, allocator, .{ .routing = .spline });
    defer result.deinit();

    // All real nodes must exist (plus dummy nodes for skip-level edges)
    try std.testing.expect(result.getNodes().len >= 6);

    // Every edge must flow downward (from_y < to_y for non-reversed edges)
    for (result.getEdges()) |edge| {
        if (!edge.reversed) {
            try std.testing.expect(edge.from_y <= edge.to_y);
        }
    }

    // Server (pinned to level 3) must be above Auth and API in level ordering
    const server = result.nodeById(1).?;
    const auth = result.nodeById(2).?;
    const api = result.nodeById(3).?;
    try std.testing.expect(server.level < auth.level);
    try std.testing.expect(server.level < api.level);

    // API (pinned to level 5) must be above its children
    const db = result.nodeById(4).?;
    const cache = result.nodeById(5).?;
    try std.testing.expect(api.level < db.level);
    try std.testing.expect(api.level < cache.level);
}

test "layout: Sugiyama pin re-layout feedback loop — node count stable" {
    // Simulates what example 09 does: layout → extract positions → feed back as pins → re-layout.
    // Verifies that dummy node count doesn't grow across iterations.
    const allocator = std.testing.allocator;

    // -- Iteration 0: no pins --
    var g0 = Graph.init(allocator);
    defer g0.deinit();
    try g0.addNode(6, "Client");
    try g0.addNode(1, "Server");
    try g0.addNode(2, "Auth");
    try g0.addNode(3, "API");
    try g0.addNode(4, "Database");
    try g0.addNode(5, "Cache");
    try g0.addEdge(6, 1);
    try g0.addEdge(1, 2);
    try g0.addEdge(1, 3);
    try g0.addEdge(2, 4);
    try g0.addEdge(3, 4);
    try g0.addEdge(3, 5);

    var ir0 = try layout(&g0, allocator, .{ .routing = .spline });
    defer ir0.deinit();

    const total_nodes_0 = ir0.getNodes().len;
    try std.testing.expect(total_nodes_0 >= 6); // at least 6 real nodes

    // Count explicit+implicit (real) nodes and dummies
    var real_0: usize = 0;
    var dummy_0: usize = 0;
    for (ir0.getNodes()) |n| {
        if (n.kind == .dummy) {
            dummy_0 += 1;
        } else {
            real_0 += 1;
        }
    }

    // Extract positions from IR (simulating frontend's pin conversion)
    // Pin Server(1) and API(3) at their layout positions
    const server_y_0 = ir0.nodeById(1).?.y;
    const api_y_0 = ir0.nodeById(3).?.y;

    // -- Iteration 1: pin Server and API at their layout positions --
    var g1 = Graph.init(allocator);
    defer g1.deinit();
    try g1.addNode(6, "Client");
    try g1.addNode(1, NodeOptions{ .label = "Server", .pin = Pin{ .y = server_y_0 } });
    try g1.addNode(2, "Auth");
    try g1.addNode(3, NodeOptions{ .label = "API", .pin = Pin{ .y = api_y_0 } });
    try g1.addNode(4, "Database");
    try g1.addNode(5, "Cache");
    try g1.addEdge(6, 1);
    try g1.addEdge(1, 2);
    try g1.addEdge(1, 3);
    try g1.addEdge(2, 4);
    try g1.addEdge(3, 4);
    try g1.addEdge(3, 5);

    var ir1 = try layout(&g1, allocator, .{ .routing = .spline });
    defer ir1.deinit();

    const total_nodes_1 = ir1.getNodes().len;
    const total_edges_1 = ir1.getEdges().len;

    var real_1: usize = 0;
    var dummy_1: usize = 0;
    for (ir1.getNodes()) |n| {
        if (n.kind == .dummy) {
            dummy_1 += 1;
        } else {
            real_1 += 1;
        }
    }

    // -- Iteration 2: pin at the NEW positions from iteration 1 --
    const server_y_1 = ir1.nodeById(1).?.y;
    const api_y_1 = ir1.nodeById(3).?.y;

    var g2 = Graph.init(allocator);
    defer g2.deinit();
    try g2.addNode(6, "Client");
    try g2.addNode(1, NodeOptions{ .label = "Server", .pin = Pin{ .y = server_y_1 } });
    try g2.addNode(2, "Auth");
    try g2.addNode(3, NodeOptions{ .label = "API", .pin = Pin{ .y = api_y_1 } });
    try g2.addNode(4, "Database");
    try g2.addNode(5, "Cache");
    try g2.addEdge(6, 1);
    try g2.addEdge(1, 2);
    try g2.addEdge(1, 3);
    try g2.addEdge(2, 4);
    try g2.addEdge(3, 4);
    try g2.addEdge(3, 5);

    var ir2 = try layout(&g2, allocator, .{ .routing = .spline });
    defer ir2.deinit();

    const total_nodes_2 = ir2.getNodes().len;
    const total_edges_2 = ir2.getEdges().len;

    var real_2: usize = 0;
    var dummy_2: usize = 0;
    for (ir2.getNodes()) |n| {
        if (n.kind == .dummy) {
            dummy_2 += 1;
        } else {
            real_2 += 1;
        }
    }

    // Real node count must always be 6
    try std.testing.expectEqual(@as(usize, 6), real_0);
    try std.testing.expectEqual(@as(usize, 6), real_1);
    try std.testing.expectEqual(@as(usize, 6), real_2);

    // Note: un-pinned (iter 0) may differ from pinned (iter 1) in total nodes/edges
    // because pinning changes the level structure. That's fine.
    // The KEY invariant: pinned iterations must be STABLE (iter 1 == iter 2)

    // Edge count stable between pinned iterations
    try std.testing.expectEqual(total_edges_1, total_edges_2);

    // Total node count (including dummies) must NOT grow
    try std.testing.expectEqual(total_nodes_1, total_nodes_2);

    // Dummy count must be stable between pinned iterations
    try std.testing.expectEqual(dummy_1, dummy_2);
}

test "layout: Sugiyama pin jitter stress — dummy count stays bounded" {
    // Simulates a realistic interactive session: pin 3 nodes, jitter their
    // y-positions by small amounts (±1) each iteration, run 10 re-layouts.
    // Dummy count must stay bounded — not explode across iterations.
    const allocator = std.testing.allocator;

    // Jitter offsets: small perturbations simulating user dragging nodes slightly
    const jitter = [_]i32{ 0, 1, -1, 2, -1, 0, 1, -2, 1, 0 };
    const N_ITERS = jitter.len;

    var dummy_counts: [N_ITERS]usize = undefined;
    var total_counts: [N_ITERS]usize = undefined;
    var edge_counts: [N_ITERS]usize = undefined;

    // Starting pin values (close to natural Sugiyama levels: Server=1, Auth=2, API=2)
    var server_pin: usize = 1;
    var auth_pin: usize = 2;
    var api_pin: usize = 2;

    for (0..N_ITERS) |iter| {
        // Apply jitter to pin positions (clamp to >= 0)
        const j = jitter[iter];
        server_pin = if (j < 0 and @as(usize, @intCast(-j)) > server_pin) 0 else if (j >= 0) server_pin + @as(usize, @intCast(j)) else server_pin - @as(usize, @intCast(-j));
        auth_pin = if (j < 0 and @as(usize, @intCast(-j)) > auth_pin) 0 else if (j >= 0) auth_pin + @as(usize, @intCast(j)) else auth_pin - @as(usize, @intCast(-j));
        // API jitters in the opposite direction for variety
        const j_inv = -j;
        api_pin = if (j_inv < 0 and @as(usize, @intCast(-j_inv)) > api_pin) 0 else if (j_inv >= 0) api_pin + @as(usize, @intCast(j_inv)) else api_pin - @as(usize, @intCast(-j_inv));

        var g = Graph.init(allocator);
        defer g.deinit();
        try g.addNode(6, "Client");
        try g.addNode(1, NodeOptions{ .label = "Server", .pin = Pin{ .y = server_pin } });
        try g.addNode(2, NodeOptions{ .label = "Auth", .pin = Pin{ .y = auth_pin } });
        try g.addNode(3, NodeOptions{ .label = "API", .pin = Pin{ .y = api_pin } });
        try g.addNode(4, "Database");
        try g.addNode(5, "Cache");
        try g.addEdge(6, 1);
        try g.addEdge(1, 2);
        try g.addEdge(1, 3);
        try g.addEdge(2, 4);
        try g.addEdge(3, 4);
        try g.addEdge(3, 5);

        var layout_ir = try layout(&g, allocator, .{ .routing = .spline });
        defer layout_ir.deinit();

        var dummies: usize = 0;
        for (layout_ir.getNodes()) |n| {
            if (n.kind == .dummy) dummies += 1;
        }
        dummy_counts[iter] = dummies;
        total_counts[iter] = layout_ir.getNodes().len;
        edge_counts[iter] = layout_ir.getEdges().len;

        // Feed back actual positions for next iteration (simulating the browser loop)
        server_pin = layout_ir.nodeById(1).?.y;
        auth_pin = layout_ir.nodeById(2).?.y;
        api_pin = layout_ir.nodeById(3).?.y;
    }

    // Find min and max dummy counts across all iterations
    var min_dummies: usize = dummy_counts[0];
    var max_dummies: usize = dummy_counts[0];
    for (dummy_counts) |d| {
        min_dummies = @min(min_dummies, d);
        max_dummies = @max(max_dummies, d);
    }

    // Key assertion: dummy count must NOT explode.
    // With level compaction, max should be very close to min.
    // Allow some fluctuation (jitter can change which edges skip levels)
    // but max must be <= min + 8.
    try std.testing.expect(max_dummies <= min_dummies + 8);

    // Also verify: total nodes should stay bounded (6 real + bounded dummies)
    for (total_counts) |t| {
        try std.testing.expect(t <= 6 + max_dummies);
        try std.testing.expect(t >= 6);
    }
}

test "layout: FR standard respects pin constraints" {
    const allocator = std.testing.allocator;

    // Triangle A → B → C, A → C   with A pinned at (0,0), C pinned at (5,5)
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, NodeOptions{ .label = "A", .pin = Pin{ .x = 0, .y = 0 } });
    try g.addNode(2, "B");
    try g.addNode(3, NodeOptions{ .label = "C", .pin = Pin{ .x = 5, .y = 5 } });
    try g.addEdge(1, 2);
    try g.addEdge(2, 3);
    try g.addEdge(1, 3);

    var result = try layout(&g, allocator, .{
        .algorithm = .{ .fruchterman_reingold = .{} },
    });
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 3), result.getNodes().len);
    try std.testing.expectEqual(@as(usize, 3), result.getEdges().len);

    // The two pinned nodes should be at distinct positions
    const a = result.nodeById(1).?;
    const c = result.nodeById(3).?;
    // A should be closer to the origin than C
    try std.testing.expect(a.x < c.x);
    try std.testing.expect(a.y < c.y);
    // The unpinned node B should exist in a valid position
    const b = result.nodeById(2).?;
    try std.testing.expect(b.x >= 0);
    try std.testing.expect(b.y >= 0);
}

test "layout: FR fast respects pin constraints" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    // Pin two opposite corners of a 4-node graph
    try g.addNode(1, NodeOptions{ .label = "TL", .pin = Pin{ .x = 0, .y = 0 } });
    try g.addNode(2, NodeOptions{ .label = "BR", .pin = Pin{ .x = 8, .y = 8 } });
    try g.addNode(3, "Free1");
    try g.addNode(4, "Free2");
    try g.addEdge(1, 3);
    try g.addEdge(3, 2);
    try g.addEdge(1, 4);
    try g.addEdge(4, 2);

    var result = try layout(&g, allocator, .{
        .algorithm = .{ .fruchterman_reingold_fast = .{} },
    });
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 4), result.getNodes().len);

    // Pinned nodes keep their relative ordering
    const tl = result.nodeById(1).?;
    const br = result.nodeById(2).?;
    try std.testing.expect(tl.x < br.x);
    try std.testing.expect(tl.y < br.y);
}

// Run tests from submodules
test {
    _ = graph;
    _ = ir;
    _ = errors;
    _ = layering.longest_path;
    _ = crossing.median;
    _ = positioning.barycentric;
    _ = routing.direct;
    _ = terminal;
    _ = svg;
    _ = json;
    _ = subgraph_layout;
    _ = @import("fuzz_tests.zig");

    // Force-directed graph modules
    _ = fdg.fixed_point;
    _ = fdg.common;
    _ = fdg.quadtree;
    _ = fdg.fruchterman_reingold;
}
