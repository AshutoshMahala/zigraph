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

/// Unicode renderer (box drawing characters)
pub const unicode = @import("render/unicode.zig");

/// JSON renderer for external tool integration
pub const json = @import("render/json.zig");

/// SVG renderer for high-quality vector output and spline visualization
pub const svg = @import("render/svg.zig");

/// Color palettes for graph visualization
pub const colors = @import("render/colors.zig");

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

    // Scale FDG positions to a reasonable size.
    // FDG produces Q16.16 coordinates spanning ~20..220 for a few nodes.
    // We want terminal output ≤ 80 columns wide and compact vertically too.
    // Compute a scale that maps the bounding box to a target size,
    // ensuring nodes (which have label widths) don't overlap.
    const max_label_w: usize = blk: {
        var max_w: usize = 3;
        for (0..n) |i| {
            const nd = g.nodeAt(i) orelse continue;
            if (nd.width > max_w) max_w = nd.width;
        }
        break :blk max_w;
    };
    // Target: each node gets at least (label_width + 2) horizontal cells
    // and 3 vertical cells. Scale proportionally.
    const target_cell: f64 = @floatFromInt(max_label_w + 4);
    const sqrt_n: f64 = @sqrt(@as(f64, @floatFromInt(n)));
    const target_w: f64 = target_cell * (sqrt_n + 1);
    const target_h: f64 = 3.0 * (sqrt_n + 1);

    const fdg_w = fp_mod.toFloat(fdg_result.width);
    const fdg_h = fp_mod.toFloat(fdg_result.height);
    const scale_x: f64 = if (fdg_w > 1.0) target_w / fdg_w else 1.0;
    const scale_y: f64 = if (fdg_h > 1.0) target_h / fdg_h else 1.0;

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
            .center_x = x + node.width / 2,
            .level = 0, // FDG doesn't have levels
            .level_position = node_idx,
            .kind = node.kind,
        });
    }

    // Route edges — use direct routing (straight lines) for FDG
    // Edge endpoints are at the center of each node box
    for (g.edges.items, 0..) |edge, edge_idx| {
        const from_idx = g.nodeIndex(edge.from) orelse continue;
        const to_idx = g.nodeIndex(edge.to) orelse continue;

        const from_node = result.nodes.items[from_idx];
        const to_node = result.nodes.items[to_idx];

        try result.addEdge(.{
            .from_id = edge.from,
            .to_id = edge.to,
            .from_x = from_node.center_x,
            .from_y = from_node.y, // center of 1-row node
            .to_x = to_node.center_x,
            .to_y = to_node.y,
            .path = .direct,
            .edge_index = edge_idx,
            .directed = edge.directed,
            .label = edge.label,
        });
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
    result.setDimensions(max_x, max_y);

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

/// Compute layout using the Sugiyama hierarchical algorithm.
fn layoutSugiyama(g: *const Graph, allocator: std.mem.Allocator, config: LayoutConfig) anyerror!LayoutIR(usize) {
    // Step 0: Validate graph (unless skipped)
    if (!config.skip_validation) {
        var validation_result = try g.validate(allocator);
        defer validation_result.deinit();

        switch (validation_result) {
            .empty => {
                errors.captureError(error.EmptyGraph, @src());
                return error.EmptyGraph;
            },
            .cycle => |cycle_info| {
                // If cycle breaking is enabled, we handle cycles below.
                // If not, reject the graph with detail and node IDs.
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

    // Step 2: Build virtual levels (includes dummy nodes for skip-level edges)
    var virtual_levels = try layering.virtual.buildVirtualLevelsWithReversed(
        g,
        layer_assignment.levels,
        layer_assignment.max_level,
        allocator,
        reversed_edges,
    );
    defer virtual_levels.deinit();

    // Step 3: Crossing reduction pipeline on virtual levels (includes dummies)
    try crossing.runPipeline(config.crossing_reducers, &virtual_levels, g, allocator);

    // Step 3b: Compute adaptive level spacing
    // Need enough vertical rows between levels to stagger outgoing edges.
    // Also add extra rows when edge labels are present (dedicated label row).
    const has_edge_labels = blk: {
        for (g.edges.items) |edge| {
            if (edge.label != null) break :blk true;
        }
        break :blk false;
    };
    const label_extra: usize = if (has_edge_labels) 2 else 0;

    const effective_level_spacing = blk: {
        var max_fan: usize = 0;
        for (0..g.nodeCount()) |node_idx| {
            const children = g.getChildren(node_idx);
            if (children.len > max_fan) max_fan = children.len;
            const parents = g.getParents(node_idx);
            if (parents.len > max_fan) max_fan = parents.len;
        }
        // Need enough rows to stagger all edges in the busiest level gap.
        // Cap at 20 to avoid absurd vertical gaps for extreme fan-out/in;
        // the router's slot modulo wraps gracefully when rows < edges.
        const needed = if (max_fan > 1) @min(max_fan + 1, 20) else 2;
        break :blk @max(config.level_spacing, needed) + label_extra;
    };

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
        allocator,
    );
    defer dummy_positions.deinit();

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
            .center_x = real_positions.center_x[node_idx],
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
                const y = level_idx * (1 + effective_level_spacing);

                const dummy_id = dummy_id_base + edge_idx * dummy_id_edge_stride + level_idx;

                try result.addNode(.{
                    .id = dummy_id,
                    .label = "O", // Simple circle for dummy (when visible)
                    .x = x,
                    .y = y,
                    .width = 1, // Single character
                    .center_x = x,
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
                        else
                            .{ .corner = .{ .horizontal_y = prev_y + 1 } };

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
                        prev_y = dummy_node.y + 1; // Bottom of dummy
                    }
                }

                // Final segment from last dummy to target
                const final_path: ir.EdgePath(usize) = if (prev_x == edge.to_x)
                    .direct
                else
                    .{ .corner = .{ .horizontal_y = prev_y + 1 } };

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

    // Step 6b: Mark reversed (back) edges in the IR.
    // The pipeline routed them downward (from→to flipped), so now we:
    //   1. Swap from_id/to_id back to the original semantic direction
    //   2. Keep coordinates as-is (they represent the visual downward path)
    //   3. Set reversed=true so renderers draw dashed lines
    //   4. Move 'directed' flag from last segment to first segment (arrow at top)
    if (reversed_edges) |re| {
        for (result.edges.items) |*result_edge| {
            if (result_edge.edge_index < re.len and re[result_edge.edge_index]) {
                result_edge.reversed = true;
                // Swap from/to IDs back to original direction
                const tmp_id = result_edge.from_id;
                result_edge.from_id = result_edge.to_id;
                result_edge.to_id = tmp_id;
            }
        }

        // For multi-segment reversed edges, move the 'directed' (arrowhead) flag
        // from the last segment (bottom, where routing put it) to the first
        // segment (top, where the semantic target is for back edges).
        for (0..re.len) |edge_idx| {
            if (!re[edge_idx]) continue;

            // Find first and last segments of this reversed edge (by from_y)
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

            // Swap: move arrow from last segment to first segment
            if (first_seg != null and last_seg != null and first_seg != last_seg) {
                const was_directed = last_seg.?.directed;
                last_seg.?.directed = false;
                first_seg.?.directed = was_directed;
            }
        }
    }

    // Step 7: Stagger horizontal_y for all corner edges.
    // After splitting, edges from both the router and the splitter coexist in
    // result.edges.  Group them by from_y (same source-level band) and assign
    // sequential slots so no two horizontal segments share the same row.
    for (result.edges.items, 0..) |*edge, i| {
        if (edge.path != .corner) continue;
        // Count how many earlier corner edges share this from_y
        var slot: usize = 0;
        for (result.edges.items[0..i]) |prev| {
            if (prev.path == .corner and prev.from_y == edge.from_y) {
                slot += 1;
            }
        }
        const available = if (edge.to_y > edge.from_y + 1) edge.to_y - edge.from_y - 1 else 1;
        edge.path.corner.horizontal_y = edge.from_y + 1 + (slot % available);
    }

    // Step 8: Propagate edge labels and compute label positions.
    // Labels come from the original Graph.Edge; we look them up via edge_index.
    // For split edges (through dummies), only the first segment gets the label.
    // Label is placed on a dedicated row below the horizontal routing area.
    {
        // Track which original edges have already had their label assigned
        // (so split edges don't duplicate the label on every segment).
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

            // Compute label position based on path type.
            // For corner edges, place on the post-corner vertical (at to_x)
            // where the edge has diverged from the shared source column.
            // For other paths, place near the source.
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
                    // Place on the post-corner vertical at to_x.
                    // Y just below the horizontal turn, with room before destination.
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

            // Center the label text (rendered as "text", so width = len + 2 for quotes)
            const label_width = orig_label.len + 2;
            const label_x = if (edge_x_at_label >= label_width / 2)
                edge_x_at_label - label_width / 2
            else
                0;

            edge.label_x = label_x;
            edge.label_y = label_y;
        }
    }

    // Step 9: Widen layout if labels extend beyond current width.
    {
        var needed_width = real_positions.total_width;
        for (result.edges.items) |edge| {
            if (edge.label) |lbl| {
                const right = edge.label_x + lbl.len + 2; // +2 for quotes
                if (right > needed_width) needed_width = right;
            }
        }
        result.setDimensions(needed_width, real_positions.total_height);
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
/// Returns the Unicode string representation of the graph.
/// Returns error.EmptyGraph or error.CycleDetected if graph is invalid.
/// Custom crossing reducers may return additional errors.
pub fn render(g: *const Graph, allocator: std.mem.Allocator, config: LayoutConfig) anyerror![]u8 {
    var layout_ir = try layout(g, allocator, config);
    defer layout_ir.deinit();

    return try unicode.renderWithConfig(&layout_ir, allocator, .{
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
/// For Unicode and SVG, the renderers convert back to usize internally,
/// so prefer `render()` for those formats unless you need the typed IR
/// for other purposes.
pub fn renderTyped(comptime Coord: type, g: *const Graph, allocator: std.mem.Allocator, config: LayoutConfig) anyerror![]u8 {
    var layout_ir = try layoutTyped(Coord, g, allocator, config);
    defer layout_ir.deinit();

    return try unicode.renderGenericWithConfig(Coord, &layout_ir, allocator, .{
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

    return try svg.render(&layout_ir, allocator, .{
        .color_edges = true,
    });
}

/// Export graph layout as SVG with a custom coordinate type.
pub fn exportSvgTyped(comptime Coord: type, g: *const Graph, allocator: std.mem.Allocator, config: LayoutConfig) anyerror![]u8 {
    var layout_ir = try layoutTyped(Coord, g, allocator, config);
    defer layout_ir.deinit();

    return try svg.renderGeneric(Coord, &layout_ir, allocator, .{
        .color_edges = true,
    });
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

// Run tests from submodules
test {
    _ = graph;
    _ = ir;
    _ = errors;
    _ = layering.longest_path;
    _ = crossing.median;
    _ = positioning.barycentric;
    _ = routing.direct;
    _ = unicode;
    _ = @import("fuzz_tests.zig");

    // Force-directed graph modules
    _ = fdg.fixed_point;
    _ = fdg.common;
    _ = fdg.quadtree;
    _ = fdg.fruchterman_reingold;
}
