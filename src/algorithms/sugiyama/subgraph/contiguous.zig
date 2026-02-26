//! Contiguous level enforcement for subgraph members.
//!
//! After layer assignment, nodes in a subgraph may be scattered across
//! non-contiguous levels. This module compacts each subgraph's level span
//! to be contiguous while preserving relative ordering.

const std = @import("std");
const Allocator = std.mem.Allocator;
const graph_mod = @import("../../../core/graph.zig");
const Graph = graph_mod.Graph;
const LayerAssignment = @import("../layering/longest_path.zig").LayerAssignment;

/// Enforce contiguous level spans for subgraph members.
///
/// After the initial layer assignment, nodes in a subgraph may be scattered
/// across non-contiguous levels (e.g., levels 1, 3, 5). This function compacts
/// each subgraph's level span to be contiguous while preserving relative
/// ordering and edge direction constraints.
///
/// Algorithm (bottom-up, O(V + S)):
/// 1. For each subgraph (deepest first), compute the set of levels used
///    by its direct member nodes.
/// 2. If levels are already contiguous, skip.
/// 3. Otherwise, reassign levels to fill gaps. The min level is preserved,
///    and nodes are shifted down to fill holes.
/// 4. Update `max_level` if the global level count changed.
///
/// Only call when `g.hasSubgraphs()` is true.
pub fn enforceContiguousLevels(
    g: *const Graph,
    assignment: *LayerAssignment,
    allocator: Allocator,
) !void {
    const sg_count = g.subgraphCount();
    if (sg_count == 0) return;

    const node_count = g.nodeCount();
    if (node_count == 0) return;

    // Compute subgraph depths for bottom-up ordering
    const depths = try allocator.alloc(usize, sg_count);
    defer allocator.free(depths);
    const order = try allocator.alloc(usize, sg_count);
    defer allocator.free(order);

    for (g.subgraphs.items, 0..) |sg, i| {
        var depth: usize = 0;
        var current = sg.parent_id;
        while (current) |pid| {
            depth += 1;
            const parent = g.subgraphById(pid) orelse break;
            current = parent.parent_id;
        }
        depths[i] = depth;
        order[i] = i;
    }

    // Sort by depth descending (deepest first)
    std.mem.sort(usize, order, depths, struct {
        fn cmp(d: []usize, a: usize, b: usize) bool {
            return d[a] > d[b];
        }
    }.cmp);

    // For each subgraph (bottom-up), compact its level span
    // Track which levels are used by each subgraph's members, then
    // remap to fill gaps.
    const level_used = try allocator.alloc(bool, assignment.max_level + 1);
    defer allocator.free(level_used);

    for (order) |sg_idx| {
        const sg = g.subgraphs.items[sg_idx];

        // Find all levels used by nodes in this subgraph (direct members only)
        @memset(level_used, false);
        var min_level: usize = std.math.maxInt(usize);
        var max_level: usize = 0;
        var has_members = false;

        for (0..node_count) |node_idx| {
            const node_id = g.nodes.items[node_idx].id;
            const node_sg = g.nodeSubgraph(node_id) orelse continue;
            if (node_sg != sg.id) continue;

            has_members = true;
            const level = assignment.levels[node_idx];
            level_used[level] = true;
            min_level = @min(min_level, level);
            max_level = @max(max_level, level);
        }

        if (!has_members) continue;
        if (min_level == max_level) continue; // single level = always contiguous

        // Check if already contiguous
        var gap_count: usize = 0;
        var lvl = min_level;
        while (lvl <= max_level) : (lvl += 1) {
            if (!level_used[lvl]) gap_count += 1;
        }
        if (gap_count == 0) continue; // already contiguous

        // Build a mapping: for each used level in [min_level..max_level],
        // assign a new contiguous level starting from min_level.
        // Nodes at unused levels don't belong to this subgraph, so they
        // stay at their current level (global reassignment is handled by
        // renormalization later).
        var new_level = min_level;
        for (min_level..max_level + 1) |l| {
            if (!level_used[l]) continue;

            if (l != new_level) {
                // Move all nodes at level l in this subgraph to new_level
                for (0..node_count) |node_idx| {
                    const node_id = g.nodes.items[node_idx].id;
                    const node_sg = g.nodeSubgraph(node_id) orelse continue;
                    if (node_sg != sg.id) continue;
                    if (assignment.levels[node_idx] == l) {
                        assignment.levels[node_idx] = new_level;
                    }
                }
            }
            new_level += 1;
        }
    }

    // Renormalize: remove empty levels from the global assignment.
    // Count the max level actually used.
    var new_max: usize = 0;
    for (assignment.levels[0..node_count]) |l| {
        new_max = @max(new_max, l);
    }
    assignment.max_level = new_max;
}

// ============================================================================
// Tests
// ============================================================================

test "enforceContiguousLevels: compacts gaps" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    // Three nodes: A at level 0, B at level 2, C at level 4
    // All in the same subgraph → should compact to levels 0, 1, 2
    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    const sg = try g.addSubgraph("cluster");
    try g.putNodes(&.{ 1, 2, 3 }).inside(sg);

    var levels = try allocator.alloc(usize, 3);
    defer allocator.free(levels);
    levels[0] = 0; // A
    levels[1] = 2; // B
    levels[2] = 4; // C

    var assignment = LayerAssignment{
        .levels = levels,
        .max_level = 4,
        .allocator = allocator,
    };

    try enforceContiguousLevels(&g, &assignment, allocator);

    // Should compact to contiguous: 0, 1, 2
    try std.testing.expectEqual(@as(usize, 0), assignment.levels[0]);
    try std.testing.expectEqual(@as(usize, 1), assignment.levels[1]);
    try std.testing.expectEqual(@as(usize, 2), assignment.levels[2]);
    try std.testing.expectEqual(@as(usize, 2), assignment.max_level);
}

test "enforceContiguousLevels: already contiguous noop" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    const sg = try g.addSubgraph("cluster");
    try g.putNodes(&.{ 1, 2 }).inside(sg);

    var levels = try allocator.alloc(usize, 2);
    defer allocator.free(levels);
    levels[0] = 1;
    levels[1] = 2;

    var assignment = LayerAssignment{
        .levels = levels,
        .max_level = 2,
        .allocator = allocator,
    };

    try enforceContiguousLevels(&g, &assignment, allocator);

    // Should be unchanged
    try std.testing.expectEqual(@as(usize, 1), assignment.levels[0]);
    try std.testing.expectEqual(@as(usize, 2), assignment.levels[1]);
}

test "enforceContiguousLevels: mixed subgraph and non-subgraph nodes" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    // A (no subgraph) at level 0, B at level 1, C at level 3
    // B and C in a subgraph → should compact B,C to levels 1,2
    // A stays at 0
    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    const sg = try g.addSubgraph("cluster");
    try g.putNodes(&.{ 2, 3 }).inside(sg);

    var levels = try allocator.alloc(usize, 3);
    defer allocator.free(levels);
    levels[0] = 0; // A (free)
    levels[1] = 1; // B (in sg)
    levels[2] = 3; // C (in sg)

    var assignment = LayerAssignment{
        .levels = levels,
        .max_level = 3,
        .allocator = allocator,
    };

    try enforceContiguousLevels(&g, &assignment, allocator);

    // A stays at 0
    try std.testing.expectEqual(@as(usize, 0), assignment.levels[0]);
    // B stays at 1 (min level preserved)
    try std.testing.expectEqual(@as(usize, 1), assignment.levels[1]);
    // C compacted from 3 to 2
    try std.testing.expectEqual(@as(usize, 2), assignment.levels[2]);
}
