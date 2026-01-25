//! Adjacent Exchange crossing reduction refinement
//!
//! This algorithm improves upon an existing node ordering by swapping
//! adjacent nodes when it reduces the number of edge crossings.
//!
//! It's typically run after median/barycenter as a refinement step.
//! Time complexity: O(n²) per layer per pass.

const std = @import("std");
const Allocator = std.mem.Allocator;
const graph_mod = @import("../../core/graph.zig");
const Graph = graph_mod.Graph;
const virtual_mod = @import("../layering/virtual.zig");
const VirtualLevels = virtual_mod.VirtualLevels;
const VNode = virtual_mod.VNode;

/// Count crossings between two adjacent layers.
/// Assumes fixed_layer is fixed and we're counting crossings with free_layer.
fn countCrossings(
    g: *const Graph,
    fixed_layer: []const VNode,
    free_layer: []const VNode,
    comptime is_downward: bool,
) usize {
    var crossings: usize = 0;

    // For each pair of nodes in free_layer
    for (0..free_layer.len) |i| {
        for ((i + 1)..free_layer.len) |j| {
            // Get positions of connected nodes in fixed layer
            const node_i = free_layer[i];
            const node_j = free_layer[j];

            // Find connections to fixed layer (use fixed-size arrays)
            // 256 connections per node is generous - typical DAGs have 2-10
            var i_connections: [256]usize = undefined;
            var i_count: usize = 0;
            var j_connections: [256]usize = undefined;
            var j_count: usize = 0;

            for (fixed_layer, 0..) |fixed_node, pos| {
                if (hasEdge(g, fixed_node, node_i, is_downward)) {
                    if (i_count < 256) {
                        i_connections[i_count] = pos;
                        i_count += 1;
                    }
                }
                if (hasEdge(g, fixed_node, node_j, is_downward)) {
                    if (j_count < 256) {
                        j_connections[j_count] = pos;
                        j_count += 1;
                    }
                }
            }

            // Count crossings between these two nodes
            for (i_connections[0..i_count]) |pi| {
                for (j_connections[0..j_count]) |pj| {
                    // Crossing occurs when edges cross
                    // Node i is at position i, node j at position j (i < j)
                    // If pi > pj, the edges cross
                    if (pi > pj) {
                        crossings += 1;
                    }
                }
            }
        }
    }

    return crossings;
}

/// Check if there's an edge between two vnodes
fn hasEdge(g: *const Graph, a: VNode, b: VNode, comptime a_is_parent: bool) bool {
    const a_real = a.realIndex();
    const b_real = b.realIndex();
    const a_edge = a.dummyEdge();
    const b_edge = b.dummyEdge();

    if (a_real != null and b_real != null) {
        // Both real nodes - check graph edges
        const from_idx = if (a_is_parent) a_real.? else b_real.?;
        const to_idx = if (a_is_parent) b_real.? else a_real.?;
        
        const from_node = g.nodeAt(from_idx) orelse return false;
        const to_node = g.nodeAt(to_idx) orelse return false;
        
        for (g.edges.items) |edge| {
            if (edge.from == from_node.id and edge.to == to_node.id) {
                return true;
            }
        }
    } else if (a_edge != null and b_real != null) {
        // a is dummy, b is real - check if edge connects
        const edge = g.edges.items[a_edge.?];
        const b_node = g.nodeAt(b_real.?) orelse return false;
        if (a_is_parent) {
            return edge.to == b_node.id;
        } else {
            return edge.from == b_node.id;
        }
    } else if (a_real != null and b_edge != null) {
        // a is real, b is dummy
        const edge = g.edges.items[b_edge.?];
        const a_node = g.nodeAt(a_real.?) orelse return false;
        if (a_is_parent) {
            return edge.from == a_node.id;
        } else {
            return edge.to == a_node.id;
        }
    } else if (a_edge != null and b_edge != null) {
        // Both dummies - connected if same edge
        return a_edge.? == b_edge.?;
    }

    return false;
}

/// Count crossings if we swap nodes at positions i and j in free_layer
fn countCrossingsWithSwap(
    g: *const Graph,
    fixed_layer: []const VNode,
    free_layer: []VNode,
    i: usize,
    j: usize,
    comptime is_downward: bool,
) usize {
    // Swap
    const tmp = free_layer[i];
    free_layer[i] = free_layer[j];
    free_layer[j] = tmp;

    const crossings = countCrossings(g, fixed_layer, free_layer, is_downward);

    // Swap back
    free_layer[j] = free_layer[i];
    free_layer[i] = tmp;

    return crossings;
}

/// Count crossings between just two specific nodes in the free layer.
/// This is O(m) where m is edges, much cheaper than full layer count.
fn countPairCrossings(
    g: *const Graph,
    fixed_layer: []const VNode,
    node_i: VNode,
    node_j: VNode,
    comptime is_downward: bool,
) usize {
    // Find positions of connections in fixed layer
    var i_connections: [64]usize = undefined;
    var i_count: usize = 0;
    var j_connections: [64]usize = undefined;
    var j_count: usize = 0;

    for (fixed_layer, 0..) |fixed_node, pos| {
        if (hasEdge(g, fixed_node, node_i, is_downward)) {
            if (i_count < 64) {
                i_connections[i_count] = pos;
                i_count += 1;
            }
        }
        if (hasEdge(g, fixed_node, node_j, is_downward)) {
            if (j_count < 64) {
                j_connections[j_count] = pos;
                j_count += 1;
            }
        }
    }

    // Count crossings: if i is left of j, crossing occurs when pi > pj
    var crossings: usize = 0;
    for (i_connections[0..i_count]) |pi| {
        for (j_connections[0..j_count]) |pj| {
            if (pi > pj) {
                crossings += 1;
            }
        }
    }
    return crossings;
}

/// Refine a single layer by adjacent exchanges.
/// Returns number of swaps made.
fn refineLayer(
    g: *const Graph,
    fixed_layer: []const VNode,
    free_layer: []VNode,
    comptime is_downward: bool,
) usize {
    // Skip large layers - adjacent exchange is O(n²) per layer
    // For layers with many nodes, the cost outweighs the benefit
    if (free_layer.len < 2 or free_layer.len > 20) return 0;

    var swaps: usize = 0;
    var improved = true;

    // Limit iterations to avoid worst-case O(n³)
    var iterations: usize = 0;
    const max_iterations = free_layer.len * 2;

    while (improved and iterations < max_iterations) {
        improved = false;
        iterations += 1;

        // Try swapping each adjacent pair
        for (0..(free_layer.len - 1)) |i| {
            const node_i = free_layer[i];
            const node_j = free_layer[i + 1];

            // Only count crossings between these two nodes - much faster!
            // Before swap: node_i is at position i (left), node_j at i+1 (right)
            const before = countPairCrossings(g, fixed_layer, node_i, node_j, is_downward);
            // After swap: positions reversed, so swap node order in count
            const after = countPairCrossings(g, fixed_layer, node_j, node_i, is_downward);

            if (after < before) {
                // Swap improves things - keep it
                free_layer[i] = node_j;
                free_layer[i + 1] = node_i;
                swaps += 1;
                improved = true;
            }
        }
    }

    return swaps;
}

/// Apply adjacent exchange refinement to virtual levels.
/// This should be called after median/barycenter reduction.
pub fn refine(
    g: *const Graph,
    virtual_levels: *VirtualLevels,
    passes: usize,
) void {
    if (virtual_levels.levels.items.len < 2) return;

    for (0..passes) |_| {
        var total_swaps: usize = 0;

        // Down sweep
        for (1..virtual_levels.levels.items.len) |level_idx| {
            const fixed = virtual_levels.levels.items[level_idx - 1].items;
            const free = virtual_levels.levels.items[level_idx].items;
            total_swaps += refineLayer(g, fixed, free, true);
        }

        // Up sweep
        var level_idx = virtual_levels.levels.items.len - 1;
        while (level_idx > 0) : (level_idx -= 1) {
            const fixed = virtual_levels.levels.items[level_idx].items;
            const free = virtual_levels.levels.items[level_idx - 1].items;
            total_swaps += refineLayer(g, fixed, free, false);
        }

        // Early exit if no improvement
        if (total_swaps == 0) break;
    }
}

test "adjacent exchange - simple swap" {
    // Basic test that the algorithm runs without errors
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(0, "A");
    try g.addNode(1, "B");
    try g.addNode(2, "C");
    try g.addEdge(0, 1);
    try g.addEdge(0, 2);

    // Would need VirtualLevels to fully test
    // This is a placeholder for integration testing
}
