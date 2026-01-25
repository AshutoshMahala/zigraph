//! Median crossing reduction algorithm
//!
//! Reorders nodes within each level to minimize edge crossings
//! using the median heuristic from the Sugiyama framework.
//!
//! ## Algorithm
//!
//! Performs alternating sweeps:
//! 1. Top-down: order each level by median position of parents
//! 2. Bottom-up: order each level by median position of children
//!
//! Repeat for `passes` iterations (typically 2-6).
//!
//! ## Complexity
//!
//! O(passes * (V + E)) with position map optimization.
//! Without the map, it would be O(passes * V * level_width).

const std = @import("std");
const Allocator = std.mem.Allocator;
const graph_mod = @import("../../core/graph.zig");
const Graph = graph_mod.Graph;

/// Reduce edge crossings using median heuristic.
///
/// Modifies `levels` in place to minimize crossings.
/// Each level is a list of node indices.
pub fn reduce(
    g: *const Graph,
    levels: []std.ArrayListUnmanaged(usize),
    passes: usize,
    allocator: Allocator,
) !void {
    if (levels.len <= 1) return;

    const node_count = g.nodeCount();
    if (node_count == 0) return;

    // Find max level width for buffer sizing
    var max_level_width: usize = 0;
    for (levels) |level| {
        if (level.items.len > max_level_width) {
            max_level_width = level.items.len;
        }
    }

    // Pre-allocate ALL working buffers ONCE - reused across all passes
    // This avoids O(levels * passes) allocations
    const position_map = try allocator.alloc(usize, node_count);
    defer allocator.free(position_map);

    const positions_buf = try allocator.alloc(usize, node_count);
    defer allocator.free(positions_buf);

    const node_medians = try allocator.alloc(NodeMedian, max_level_width);
    defer allocator.free(node_medians);

    const max_level = levels.len - 1;

    for (0..passes) |_| {
        // Top-down pass: order by median of parents
        for (1..levels.len) |level_idx| {
            // Build position map for parent level
            buildPositionMap(position_map, levels[level_idx - 1].items);
            orderByMedianWithBuffers(g, &levels[level_idx], position_map, true, positions_buf, node_medians);
        }

        // Bottom-up pass: order by median of children
        var level_idx = max_level;
        while (level_idx > 0) : (level_idx -= 1) {
            // Build position map for child level
            buildPositionMap(position_map, levels[level_idx].items);
            orderByMedianWithBuffers(g, &levels[level_idx - 1], position_map, false, positions_buf, node_medians);
        }
    }
}

/// Build a position map: position_map[node_idx] = position in level
fn buildPositionMap(position_map: []usize, level_nodes: []const usize) void {
    // Reset to "not in level"
    @memset(position_map, std.math.maxInt(usize));

    // Set positions for nodes in this level
    for (level_nodes, 0..) |node_idx, pos| {
        if (node_idx < position_map.len) {
            position_map[node_idx] = pos;
        }
    }
}

/// Order nodes by median position of neighbors - uses pre-allocated buffers
fn orderByMedianWithBuffers(
    g: *const Graph,
    level_nodes: *std.ArrayListUnmanaged(usize),
    position_map: []const usize,
    use_parents: bool,
    positions_buf: []usize,
    node_medians: []NodeMedian,
) void {
    if (level_nodes.items.len == 0) return;

    for (level_nodes.items, 0..) |node_idx, pos| {
        const neighbor_indices = if (use_parents)
            g.getParents(node_idx)
        else
            g.getChildren(node_idx);

        if (neighbor_indices.len == 0) {
            // No neighbors: keep original position
            node_medians[pos] = .{ .node_idx = node_idx, .median = @as(f32, @floatFromInt(pos)) };
        } else {
            // Collect positions using O(1) map lookup
            var pos_count: usize = 0;
            for (neighbor_indices) |n_idx| {
                if (n_idx < position_map.len) {
                    const mapped_pos = position_map[n_idx];
                    if (mapped_pos != std.math.maxInt(usize)) {
                        positions_buf[pos_count] = mapped_pos;
                        pos_count += 1;
                    }
                }
            }

            const median = computeMedian(positions_buf[0..pos_count], pos);
            node_medians[pos] = .{ .node_idx = node_idx, .median = median };
        }
    }

    // Sort by median
    std.mem.sort(NodeMedian, node_medians[0..level_nodes.items.len], {}, lessThanMedian);

    // Update level with sorted order
    for (node_medians[0..level_nodes.items.len], 0..) |nm, i| {
        level_nodes.items[i] = nm.node_idx;
    }
}

/// Order nodes by median position of neighbors (parents or children)
/// Legacy function - allocates per call. Use orderByMedianWithBuffers for performance.
fn orderByMedian(
    g: *const Graph,
    level_nodes: *std.ArrayListUnmanaged(usize),
    position_map: []const usize,
    use_parents: bool,
    allocator: Allocator,
) !void {
    if (level_nodes.items.len == 0) return;

    // Compute median for each node
    var node_medians = try allocator.alloc(NodeMedian, level_nodes.items.len);
    defer allocator.free(node_medians);

    // Temp buffer for positions (reused per node to avoid repeated allocs)
    var positions_buf = try allocator.alloc(usize, g.nodeCount());
    defer allocator.free(positions_buf);

    for (level_nodes.items, 0..) |node_idx, pos| {
        const neighbor_indices = if (use_parents)
            g.getParents(node_idx)
        else
            g.getChildren(node_idx);

        if (neighbor_indices.len == 0) {
            // No neighbors: keep original position
            node_medians[pos] = .{ .node_idx = node_idx, .median = @as(f32, @floatFromInt(pos)) };
        } else {
            // Collect positions using O(1) map lookup instead of O(n) scan
            var pos_count: usize = 0;
            for (neighbor_indices) |n_idx| {
                if (n_idx < position_map.len) {
                    const mapped_pos = position_map[n_idx];
                    if (mapped_pos != std.math.maxInt(usize)) {
                        positions_buf[pos_count] = mapped_pos;
                        pos_count += 1;
                    }
                }
            }

            const median = computeMedian(positions_buf[0..pos_count], pos);
            node_medians[pos] = .{ .node_idx = node_idx, .median = median };
        }
    }

    // Sort by median
    std.mem.sort(NodeMedian, node_medians, {}, lessThanMedian);

    // Update level with sorted order
    for (node_medians, 0..) |nm, i| {
        level_nodes.items[i] = nm.node_idx;
    }
}

const NodeMedian = struct {
    node_idx: usize,
    median: f32,
};

fn lessThanMedian(_: void, a: NodeMedian, b: NodeMedian) bool {
    return a.median < b.median;
}

/// Compute median of positions. If empty, returns default_pos.
fn computeMedian(positions: []usize, default_pos: usize) f32 {
    if (positions.len == 0) {
        return @as(f32, @floatFromInt(default_pos));
    }

    // Sort positions
    std.mem.sort(usize, positions, {}, std.sort.asc(usize));

    if (positions.len % 2 == 1) {
        // Odd: return middle element
        return @as(f32, @floatFromInt(positions[positions.len / 2]));
    } else {
        // Even: return average of two middle elements
        const mid = positions.len / 2;
        const a: f32 = @floatFromInt(positions[mid - 1]);
        const b: f32 = @floatFromInt(positions[mid]);
        return (a + b) / 2.0;
    }
}

// ============================================================================
// Virtual Level Crossing Reduction (with dummy nodes)
// ============================================================================

const virtual_mod = @import("../layering/virtual.zig");
const VNode = virtual_mod.VNode;
const VirtualLevels = virtual_mod.VirtualLevels;

/// Reduce edge crossings on virtual levels (includes dummy nodes).
///
/// This is the proper Sugiyama crossing reduction that handles long edges.
/// Dummy nodes participate in the median heuristic, ensuring long edges
/// are positioned to minimize crossings with other edges and nodes.
pub fn reduceVirtual(
    g: *const Graph,
    vlevels: *VirtualLevels,
    passes: usize,
    allocator: Allocator,
) !void {
    if (vlevels.levels.items.len <= 1) return;

    // Find max level width for buffer sizing
    var max_level_width: usize = 0;
    for (vlevels.levels.items) |level| {
        max_level_width = @max(max_level_width, level.items.len);
    }

    if (max_level_width == 0) return;

    // Pre-allocate working buffers
    const real_pos_map = try allocator.alloc(usize, g.nodeCount());
    defer allocator.free(real_pos_map);

    const edge_count = g.edges.items.len;
    const dummy_pos_map = try allocator.alloc(usize, if (edge_count > 0) edge_count else 1);
    defer allocator.free(dummy_pos_map);

    const vnode_medians = try allocator.alloc(VNodeMedian, max_level_width);
    defer allocator.free(vnode_medians);

    const positions_buf = try allocator.alloc(usize, max_level_width);
    defer allocator.free(positions_buf);

    const max_level = vlevels.levels.items.len - 1;

    for (0..passes) |_| {
        // Top-down pass
        for (1..vlevels.levels.items.len) |level_idx| {
            buildVirtualPositionMaps(
                vlevels.levels.items[level_idx - 1].items,
                real_pos_map,
                dummy_pos_map,
            );
            orderVirtualByMedian(
                g,
                &vlevels.levels.items[level_idx],
                real_pos_map,
                dummy_pos_map,
                true,
                vnode_medians,
                positions_buf,
            );
        }

        // Bottom-up pass
        var level_idx = max_level;
        while (level_idx > 0) : (level_idx -= 1) {
            buildVirtualPositionMaps(
                vlevels.levels.items[level_idx].items,
                real_pos_map,
                dummy_pos_map,
            );
            orderVirtualByMedian(
                g,
                &vlevels.levels.items[level_idx - 1],
                real_pos_map,
                dummy_pos_map,
                false,
                vnode_medians,
                positions_buf,
            );
        }
    }
}

/// Build position maps for adjacent level lookup
fn buildVirtualPositionMaps(
    level_vnodes: []const VNode,
    real_pos_map: []usize,
    dummy_pos_map: []usize,
) void {
    // Reset maps
    @memset(real_pos_map, std.math.maxInt(usize));
    @memset(dummy_pos_map, std.math.maxInt(usize));

    // Set positions
    for (level_vnodes, 0..) |vnode, pos| {
        switch (vnode) {
            .real => |idx| {
                if (idx < real_pos_map.len) {
                    real_pos_map[idx] = pos;
                }
            },
            .dummy => |edge_idx| {
                if (edge_idx < dummy_pos_map.len) {
                    dummy_pos_map[edge_idx] = pos;
                }
            },
        }
    }
}

const VNodeMedian = struct {
    vnode: VNode,
    median: f32,
};

fn lessThanVNodeMedian(_: void, a: VNodeMedian, b: VNodeMedian) bool {
    return a.median < b.median;
}

/// Order virtual nodes by median position of connected nodes in adjacent level
fn orderVirtualByMedian(
    g: *const Graph,
    level_vnodes: *std.ArrayListUnmanaged(VNode),
    real_pos_map: []const usize,
    dummy_pos_map: []const usize,
    use_parents: bool,
    vnode_medians: []VNodeMedian,
    positions_buf: []usize,
) void {
    if (level_vnodes.items.len == 0) return;

    for (level_vnodes.items, 0..) |vnode, pos| {
        var pos_count: usize = 0;

        switch (vnode) {
            .real => |node_idx| {
                // Real node: find connected real nodes in adjacent level
                const neighbors = if (use_parents)
                    g.getParents(node_idx)
                else
                    g.getChildren(node_idx);

                for (neighbors) |n_idx| {
                    if (n_idx < real_pos_map.len) {
                        const mapped = real_pos_map[n_idx];
                        if (mapped != std.math.maxInt(usize)) {
                            positions_buf[pos_count] = mapped;
                            pos_count += 1;
                        }
                    }
                }
            },
            .dummy => |edge_idx| {
                // Dummy node: connected to same edge's dummy OR endpoint in adjacent level
                const edge = g.edges.items[edge_idx];
                const from_idx = g.nodeIndex(edge.from);
                const to_idx = g.nodeIndex(edge.to);

                // Check for same edge's dummy in adjacent level
                if (edge_idx < dummy_pos_map.len) {
                    const dummy_mapped = dummy_pos_map[edge_idx];
                    if (dummy_mapped != std.math.maxInt(usize)) {
                        positions_buf[pos_count] = dummy_mapped;
                        pos_count += 1;
                    }
                }

                // Check for endpoint in adjacent level
                if (use_parents) {
                    // Looking at parent level - source of edge might be there
                    if (from_idx) |idx| {
                        if (idx < real_pos_map.len) {
                            const mapped = real_pos_map[idx];
                            if (mapped != std.math.maxInt(usize)) {
                                positions_buf[pos_count] = mapped;
                                pos_count += 1;
                            }
                        }
                    }
                } else {
                    // Looking at child level - target of edge might be there
                    if (to_idx) |idx| {
                        if (idx < real_pos_map.len) {
                            const mapped = real_pos_map[idx];
                            if (mapped != std.math.maxInt(usize)) {
                                positions_buf[pos_count] = mapped;
                                pos_count += 1;
                            }
                        }
                    }
                }
            },
        }

        const median = computeMedian(positions_buf[0..pos_count], pos);
        vnode_medians[pos] = .{ .vnode = vnode, .median = median };
    }

    // Sort by median
    std.mem.sort(VNodeMedian, vnode_medians[0..level_vnodes.items.len], {}, lessThanVNodeMedian);

    // Update level with sorted order
    for (vnode_medians[0..level_vnodes.items.len], 0..) |vm, i| {
        level_vnodes.items[i] = vm.vnode;
    }
}

// ============================================================================
// Tests
// ============================================================================

test "median: simple crossing reduction" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    //   A   B
    //    \ /
    //     X (crossing)
    //    / \
    //   C   D
    //
    // Edges: A->D, B->C (causes crossing if A,B and C,D are in insertion order)
    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addNode(4, "D");
    try g.addEdge(1, 4); // A -> D
    try g.addEdge(2, 3); // B -> C

    // Initial level order (causes crossing)
    var level0: std.ArrayListUnmanaged(usize) = .{};
    try level0.append(allocator, 0); // A
    try level0.append(allocator, 1); // B
    defer level0.deinit(allocator);

    var level1: std.ArrayListUnmanaged(usize) = .{};
    try level1.append(allocator, 2); // C
    try level1.append(allocator, 3); // D
    defer level1.deinit(allocator);

    var levels = [_]std.ArrayListUnmanaged(usize){ level0, level1 };

    // Run crossing reduction
    try reduce(&g, &levels, 2, allocator);

    // After reduction, should reorder to eliminate crossing
    // Either: A,B with D,C or B,A with C,D
    // Check that adjacent edges don't cross
    const a_pos = for (levels[0].items, 0..) |idx, pos| {
        if (idx == 0) break pos;
    } else 0;
    const d_pos = for (levels[1].items, 0..) |idx, pos| {
        if (idx == 3) break pos;
    } else 0;
    const b_pos = for (levels[0].items, 0..) |idx, pos| {
        if (idx == 1) break pos;
    } else 0;
    const c_pos = for (levels[1].items, 0..) |idx, pos| {
        if (idx == 2) break pos;
    } else 0;

    // Check crossing is reduced (A->D and B->C shouldn't cross)
    // Crossing happens if (a_pos < b_pos) != (d_pos < c_pos)
    const no_crossing = (a_pos < b_pos) == (d_pos < c_pos);
    try std.testing.expect(no_crossing);
}

test "median: compute median" {
    var positions = [_]usize{ 3, 1, 2 };
    const med = computeMedian(&positions, 0);
    try std.testing.expectEqual(@as(f32, 2.0), med);

    var even = [_]usize{ 1, 2, 3, 4 };
    const med_even = computeMedian(&even, 0);
    try std.testing.expectEqual(@as(f32, 2.5), med_even);

    const empty: []usize = &.{};
    const med_empty = computeMedian(empty, 5);
    try std.testing.expectEqual(@as(f32, 5.0), med_empty);
}
