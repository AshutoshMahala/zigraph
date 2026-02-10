//! Longest-path layering algorithm
//!
//! Assigns each node to a level based on the longest path from roots.
//! This is the standard Sugiyama layering approach.
//!
//! Complexity: O(V + E) per iteration, typically O(V + E) total
//!
//! ## Algorithm
//!
//! Uses a fixed-point iteration:
//! 1. Initialize all nodes to level 0
//! 2. For each edge (u, v): level[v] = max(level[v], level[u] + 1)
//! 3. Repeat until no changes

const std = @import("std");
const Allocator = std.mem.Allocator;
const graph_mod = @import("../../../core/graph.zig");
const Graph = graph_mod.Graph;

/// Result of layering computation
pub const LayerAssignment = struct {
    /// Level assignment for each node (indexed by node index)
    levels: []usize,
    /// Maximum level (0-indexed)
    max_level: usize,
    /// Allocator used (needed for deinit)
    allocator: Allocator,

    pub fn deinit(self: *LayerAssignment) void {
        self.allocator.free(self.levels);
    }

    /// Get the level of a node by index
    pub fn getLevel(self: *const LayerAssignment, node_idx: usize) usize {
        return self.levels[node_idx];
    }
};

/// Compute layer assignment using longest-path algorithm.
///
/// Each node is assigned to a level such that:
/// - Root nodes (no parents) are at level 0
/// - Each node is at level = max(parent levels) + 1
///
/// This produces a proper layering where all edges point downward.
pub fn compute(g: *const Graph, allocator: Allocator) !LayerAssignment {
    const node_count = g.nodeCount();

    if (node_count == 0) {
        return .{
            .levels = &.{},
            .max_level = 0,
            .allocator = allocator,
        };
    }

    // Allocate level array
    const levels = try allocator.alloc(usize, node_count);
    @memset(levels, 0);

    // Fixed-point iteration
    var changed = true;
    while (changed) {
        changed = false;

        for (g.edges.items) |edge| {
            const from_idx = g.nodeIndex(edge.from) orelse continue;
            const to_idx = g.nodeIndex(edge.to) orelse continue;

            const new_level = levels[from_idx] + 1;
            if (new_level > levels[to_idx]) {
                levels[to_idx] = new_level;
                changed = true;
            }
        }
    }

    // Find max level
    var max_level: usize = 0;
    for (levels) |level| {
        max_level = @max(max_level, level);
    }

    return .{
        .levels = levels,
        .max_level = max_level,
        .allocator = allocator,
    };
}

/// Organize nodes into level buckets.
///
/// Returns an array of arrays where result[level] contains
/// the indices of nodes at that level.
pub fn organizeLevels(
    layer_assignment: *const LayerAssignment,
    allocator: Allocator,
) !std.ArrayListUnmanaged(std.ArrayListUnmanaged(usize)) {
    var levels: std.ArrayListUnmanaged(std.ArrayListUnmanaged(usize)) = .{};

    // Create level buckets
    const level_count = layer_assignment.max_level + 1;
    try levels.ensureTotalCapacity(allocator, level_count);
    for (0..level_count) |_| {
        try levels.append(allocator, .{});
    }

    // Assign nodes to levels
    for (layer_assignment.levels, 0..) |level, node_idx| {
        try levels.items[level].append(allocator, node_idx);
    }

    return levels;
}

// ============================================================================
// Tests
// ============================================================================

test "longest_path: simple chain" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addEdge(1, 2);
    try g.addEdge(2, 3);

    var assignment = try compute(&g, allocator);
    defer assignment.deinit();

    try std.testing.expectEqual(@as(usize, 0), assignment.getLevel(0)); // A
    try std.testing.expectEqual(@as(usize, 1), assignment.getLevel(1)); // B
    try std.testing.expectEqual(@as(usize, 2), assignment.getLevel(2)); // C
    try std.testing.expectEqual(@as(usize, 2), assignment.max_level);
}

test "longest_path: diamond graph" {
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

    var assignment = try compute(&g, allocator);
    defer assignment.deinit();

    try std.testing.expectEqual(@as(usize, 0), assignment.getLevel(0)); // A
    try std.testing.expectEqual(@as(usize, 1), assignment.getLevel(1)); // B
    try std.testing.expectEqual(@as(usize, 1), assignment.getLevel(2)); // C
    try std.testing.expectEqual(@as(usize, 2), assignment.getLevel(3)); // D
}

test "longest_path: skip-level edge" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    //   A
    //   |  \
    //   B   |
    //   |   |
    //   C <-+
    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addEdge(1, 2);
    try g.addEdge(2, 3);
    try g.addEdge(1, 3); // Skip-level edge

    var assignment = try compute(&g, allocator);
    defer assignment.deinit();

    try std.testing.expectEqual(@as(usize, 0), assignment.getLevel(0)); // A
    try std.testing.expectEqual(@as(usize, 1), assignment.getLevel(1)); // B
    try std.testing.expectEqual(@as(usize, 2), assignment.getLevel(2)); // C (longest path)
}

test "longest_path: multiple roots" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    //   A   B
    //    \ /
    //     C
    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addEdge(1, 3);
    try g.addEdge(2, 3);

    var assignment = try compute(&g, allocator);
    defer assignment.deinit();

    try std.testing.expectEqual(@as(usize, 0), assignment.getLevel(0)); // A
    try std.testing.expectEqual(@as(usize, 0), assignment.getLevel(1)); // B
    try std.testing.expectEqual(@as(usize, 1), assignment.getLevel(2)); // C
}

test "longest_path: organize into level buckets" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addEdge(1, 2);
    try g.addEdge(1, 3);

    var assignment = try compute(&g, allocator);
    defer assignment.deinit();

    var levels = try organizeLevels(&assignment, allocator);
    defer {
        for (levels.items) |*level| {
            level.deinit(allocator);
        }
        levels.deinit(allocator);
    }

    try std.testing.expectEqual(@as(usize, 2), levels.items.len);
    try std.testing.expectEqual(@as(usize, 1), levels.items[0].items.len); // Level 0: A
    try std.testing.expectEqual(@as(usize, 2), levels.items[1].items.len); // Level 1: B, C
}
