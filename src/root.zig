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
pub const ErrorDetail = errors.ErrorDetail;
pub const ZigraphError = errors.ZigraphError;

/// Intermediate Representation for layout
pub const ir = @import("core/ir.zig");
pub const LayoutIR = ir.LayoutIR;
pub const LayoutNode = ir.LayoutNode;
pub const LayoutEdge = ir.LayoutEdge;
pub const EdgePath = ir.EdgePath;

// ============================================================================
// Algorithms
// ============================================================================

/// Layering algorithms - assign nodes to horizontal levels
pub const layering = struct {
    pub const longest_path = @import("algorithms/layering/longest_path.zig");
    pub const virtual = @import("algorithms/layering/virtual.zig");
};

/// Crossing reduction algorithms - minimize edge crossings
pub const crossing = struct {
    pub const median = @import("algorithms/crossing/median.zig");
    pub const adjacent_exchange = @import("algorithms/crossing/adjacent_exchange.zig");
    
    // Re-export reducers for easy access
    pub const reducers = @import("algorithms/crossing/reducers.zig");
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
    pub const simple = @import("algorithms/positioning/simple.zig");
    pub const brandes_kopf = @import("algorithms/positioning/brandes_kopf.zig");
};

/// Edge routing algorithms - determine edge paths
pub const routing = struct {
    pub const direct = @import("algorithms/routing/direct.zig");
    pub const spline = @import("algorithms/routing/spline.zig");
};

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
// Comptime Support
// ============================================================================

/// Comptime graph builder for zero-runtime-cost diagrams
pub const comptime_graph = @import("comptime_graph.zig");
pub const ComptimeGraph = comptime_graph.ComptimeGraph;

// ============================================================================
// Layout configuration
// ============================================================================

/// Available layering algorithms
pub const Layering = enum {
    /// Longest path layering - simple, fast, may produce more layers
    longest_path,
    // Future: coffman_graham, network_simplex
};

/// Available positioning algorithms
pub const Positioning = enum {
    /// Simple left-to-right positioning
    simple,
    /// Brandes-Köpf - centers parents over children, better tree layouts
    brandes_kopf,
};

/// Available edge routing algorithms
pub const Routing = enum {
    /// Direct Manhattan routing (straight lines with corners)
    direct,
    /// Spline routing (smooth bezier curves)
    spline,
};

/// Configuration for the layout algorithm.
pub const LayoutConfig = struct {
    // Algorithm selection
    /// Layering algorithm (default: longest_path)
    layering: Layering = .longest_path,
    /// Crossing reduction pipeline (default: median + adjacent exchange)
    /// Use presets: crossing.fast, crossing.balanced, crossing.quality, crossing.none
    /// Or build custom: &[_]crossing.Reducer{ crossing.medianReducer(4), ... }
    crossing_reducers: []const crossing.Reducer = &crossing.balanced,
    /// Positioning algorithm (default: brandes_kopf)
    positioning: Positioning = .brandes_kopf,
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

/// Compute layout for a graph using the Sugiyama algorithm.
///
/// This is the main entry point for layout computation.
/// Algorithm selection via config: layering, crossing, positioning, routing.
///
/// Returns error.EmptyGraph if the graph has no nodes.
/// Returns error.CycleDetected if the graph contains a cycle.
/// Custom crossing reducers may return additional errors.
/// Use `graph.validate()` before calling for detailed cycle info.
pub fn layout(g: *const Graph, allocator: std.mem.Allocator, config: LayoutConfig) anyerror!LayoutIR {
    // Step 0: Validate graph (unless skipped)
    if (!config.skip_validation) {
        var validation = try g.validate(allocator);
        defer validation.deinit();

        switch (validation) {
            .empty => return error.EmptyGraph,
            .cycle => return error.CycleDetected,
            .ok => {},
        }
    }

    // Step 1: Layer assignment
    var layer_assignment = switch (config.layering) {
        .longest_path => try layering.longest_path.compute(g, allocator),
    };
    defer layer_assignment.deinit();

    // Step 2: Build virtual levels (includes dummy nodes for skip-level edges)
    var virtual_levels = try layering.virtual.buildVirtualLevels(
        g,
        layer_assignment.levels,
        layer_assignment.max_level,
        allocator,
    );
    defer virtual_levels.deinit();

    // Step 3: Crossing reduction pipeline on virtual levels (includes dummies)
    try crossing.runPipeline(config.crossing_reducers, &virtual_levels, g, allocator);

    // Step 4: Position all nodes (real + dummy) respecting crossing-reduced order
    var virtual_positions = try layering.virtual.computeVirtualPositions(
        g,
        &virtual_levels,
        config.node_spacing,
        config.level_spacing,
        allocator,
    );
    defer virtual_positions.deinit();

    // Step 4b: Extract real node positions from virtual positions
    var real_positions = try layering.virtual.extractRealNodePositions(
        g,
        &virtual_levels,
        &virtual_positions,
        config.level_spacing,
        allocator,
    );
    defer real_positions.deinit();

    // Step 4c: Extract dummy positions from virtual positions (respects crossing order)
    var dummy_positions = try layering.virtual.extractDummyPositions(
        &virtual_levels,
        &virtual_positions,
        g.edges.items.len,
        config.level_spacing,
        allocator,
    );
    defer dummy_positions.deinit();

    // Step 5: Build LayoutIR
    var result = LayoutIR.init(allocator);
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
    // Map: (edge_idx * 10000 + level) → dummy_node_id
    // Always add dummy nodes - renderer decides whether to display them
    var dummy_id_map = std.AutoHashMap(usize, usize).init(allocator);
    defer dummy_id_map.deinit();

    // Iterate through virtual levels to find dummy nodes
    for (virtual_levels.levels.items, 0..) |level, level_idx| {
        for (level.items, 0..) |vnode, pos_in_level| {
            if (vnode.dummyEdge()) |edge_idx| {
                // Get position from virtual positions
                const x = virtual_positions.x.items[level_idx].items[pos_in_level];
                const y = level_idx * (1 + config.level_spacing);

                // Create a synthetic ID for this dummy
                const dummy_id = 0x80000000 + edge_idx * 1000 + level_idx;

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
                const key = edge_idx * 10000 + level_idx;
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
        ),
        .spline => try routing.spline.routeWithDummies(
            g,
            result.nodes.items,
            &result.id_to_index,
            &dummy_positions,
            allocator,
            .{},
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

            const level_span = to_node.level - from_node.level;

            if (level_span > 1) {
                // This is a long edge - split it through dummies
                // Free the original path since we're replacing it with direct segments
                edge.path.deinit();

                var prev_id = edge.from_id;
                var prev_x = edge.from_x;
                var prev_y = edge.from_y;

                // Add segments through each intermediate level
                for ((from_node.level + 1)..(to_node.level)) |intermediate_level| {
                    const key = edge_idx * 10000 + intermediate_level;
                    if (dummy_id_map.get(key)) |dummy_id| {
                        const dummy_node = result.nodes.items[result.id_to_index.get(dummy_id).?];

                        // Determine path type based on x alignment
                        const edge_path: ir.EdgePath = if (prev_x == dummy_node.center_x)
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
                        });

                        prev_id = dummy_id;
                        prev_x = dummy_node.center_x;
                        prev_y = dummy_node.y + 1; // Bottom of dummy
                    }
                }

                // Final segment from last dummy to target
                const final_path: ir.EdgePath = if (prev_x == edge.to_x)
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

    // Set dimensions
    result.setDimensions(real_positions.total_width, real_positions.total_height);

    return result;
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

// ============================================================================
// Version info
// ============================================================================

pub const version = "0.1.0";
pub const version_major = 0;
pub const version_minor = 1;
pub const version_patch = 0;

// ============================================================================
// Tests
// ============================================================================

test "version is defined" {
    try std.testing.expectEqualStrings("0.1.0", version);
}

test "core modules are accessible" {
    const allocator = std.testing.allocator;

    // Test Graph
    var g = Graph.init(allocator);
    defer g.deinit();
    try g.addNode(1, "Test");
    try std.testing.expectEqual(@as(usize, 1), g.nodeCount());

    // Test LayoutIR
    var layout_ir = LayoutIR.init(allocator);
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

// Run tests from submodules
test {
    _ = graph;
    _ = ir;
    _ = errors;
    _ = layering.longest_path;
    _ = crossing.median;
    _ = positioning.simple;
    _ = routing.direct;
    _ = unicode;
    _ = @import("fuzz_tests.zig");
}
