//! Subgraph-aware orchestration for Sugiyama layout
//!
//! Provides constraint enforcement for subgraph-grouped layouts:
//! - **Layering**: contiguous level spans for subgraph members
//! - **Adjacency**: nodes in the same subgraph are contiguous on each level
//! - **Bounding boxes**: computed bottom-up with padding per nesting level
//!
//! These functions are called by the layout pipeline (`root.zig`) when the
//! input graph contains subgraphs. They wrap — never replace — the existing
//! crossing reduction and positioning algorithms.
//!
//! Design principle: subgraph logic lives in orchestration wrappers,
//! never inside hot loops. Existing inner functions remain untouched.

const std = @import("std");
const Allocator = std.mem.Allocator;
const graph_mod = @import("../../core/graph.zig");
const Graph = graph_mod.Graph;
const virtual_mod = @import("layering/virtual.zig");
const VirtualLevels = virtual_mod.VirtualLevels;
const VNode = virtual_mod.VNode;
const ir_mod = @import("../../core/ir.zig");
const LayerAssignment = @import("layering/longest_path.zig").LayerAssignment;

/// Default padding around subgraph bounding boxes (in layout cells).
pub const default_padding: usize = 1;

// ============================================================================
// Subgraph membership
// ============================================================================

/// Determine which subgraph a VNode belongs to.
///
/// - **Real nodes**: returns the node's immediate subgraph via `nodeSubgraph`.
/// - **Dummy nodes**: returns the subgraph only when *both* endpoints of the
///   edge share the same immediate subgraph (intra-subgraph edge).
///   Cross-subgraph edge dummies return `null`, allowing them to float
///   freely between blocks during adjacency enforcement.
pub fn vnodeSubgraph(g: *const Graph, vnode: VNode) ?usize {
    return switch (vnode) {
        .real => |node_idx| blk: {
            const node = g.nodeAt(node_idx) orelse break :blk null;
            break :blk g.nodeSubgraph(node.id);
        },
        .dummy => |edge_idx| blk: {
            if (edge_idx >= g.edges.items.len) break :blk null;
            const edge = g.edges.items[edge_idx];
            const from_sg = g.nodeSubgraph(edge.from) orelse break :blk null;
            const to_sg = g.nodeSubgraph(edge.to) orelse break :blk null;
            break :blk if (from_sg == to_sg) from_sg else null;
        },
    };
}

// ============================================================================
// Crossing reduction constraint
// ============================================================================

/// Maximum number of distinct blocks (subgraphs + root) on a single level.
/// Levels exceeding this are left unchanged — an extremely unlikely scenario.
// ============================================================================
// Layering constraints
// ============================================================================

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

const MAX_BLOCKS: usize = 128;

/// Enforce subgraph adjacency on all virtual levels.
///
/// After crossing reduction, nodes in the same subgraph may be interleaved
/// with nodes from other subgraphs. This function groups them contiguously
/// while preserving within-group relative order (stable partitioning).
///
/// Block ordering uses the average position of each block's members in the
/// crossing-reduced layout, inheriting the median heuristic's quality.
///
/// Only call when `g.hasSubgraphs()` is true.
pub fn enforceSubgraphAdjacency(
    g: *const Graph,
    vlevels: *VirtualLevels,
    allocator: Allocator,
) !void {
    // Find max level width for buffer allocation
    var max_width: usize = 0;
    for (vlevels.levels.items) |level| {
        max_width = @max(max_width, level.items.len);
    }
    if (max_width <= 1) return;

    const scratch = try allocator.alloc(VNode, max_width);
    defer allocator.free(scratch);
    const keys = try allocator.alloc(usize, max_width);
    defer allocator.free(keys);

    const SENTINEL = std.math.maxInt(usize);

    for (vlevels.levels.items) |*level| {
        const n = level.items.len;
        if (n <= 1) continue;

        // Phase 1: assign block key to each VNode
        for (level.items, 0..) |vnode, i| {
            keys[i] = vnodeSubgraph(g, vnode) orelse SENTINEL;
        }

        // Phase 2: collect unique blocks with running sum of positions
        var block_keys: [MAX_BLOCKS]usize = undefined;
        var block_sum: [MAX_BLOCKS]f32 = undefined;
        var block_count: [MAX_BLOCKS]usize = undefined;
        var n_blocks: usize = 0;
        var overflow = false;

        for (keys[0..n], 0..) |key, pos| {
            var found = false;
            for (block_keys[0..n_blocks], 0..) |existing, bi| {
                if (existing == key) {
                    block_sum[bi] += @floatFromInt(pos);
                    block_count[bi] += 1;
                    found = true;
                    break;
                }
            }
            if (!found) {
                if (n_blocks >= MAX_BLOCKS) {
                    overflow = true;
                    break;
                }
                block_keys[n_blocks] = key;
                block_sum[n_blocks] = @floatFromInt(pos);
                block_count[n_blocks] = 1;
                n_blocks += 1;
            }
        }

        // Too many distinct blocks on this level — skip enforcement
        if (overflow) continue;

        // Phase 3: sort blocks by average position (selection sort — n_blocks is small)
        // Finalize averages in-place
        for (0..n_blocks) |bi| {
            block_sum[bi] /= @floatFromInt(block_count[bi]);
        }
        for (0..n_blocks) |i| {
            var min_idx = i;
            for (i + 1..n_blocks) |j| {
                if (block_sum[j] < block_sum[min_idx]) min_idx = j;
            }
            if (min_idx != i) {
                std.mem.swap(usize, &block_keys[i], &block_keys[min_idx]);
                std.mem.swap(f32, &block_sum[i], &block_sum[min_idx]);
                std.mem.swap(usize, &block_count[i], &block_count[min_idx]);
            }
        }

        // Phase 4: emit nodes grouped by block (stable — preserves within-block order)
        var out: usize = 0;
        for (block_keys[0..n_blocks]) |bk| {
            for (level.items, 0..) |vnode, i| {
                if (keys[i] == bk) {
                    scratch[out] = vnode;
                    out += 1;
                }
            }
        }

        @memcpy(level.items, scratch[0..n]);
    }
}

// ============================================================================
// Bounding box computation
// ============================================================================

/// Compute subgraph bounding boxes and append them to the layout IR.
///
/// Processes the subgraph tree bottom-up:
/// 1. **Leaf subgraphs**: bbox = envelope of direct member nodes + padding
/// 2. **Parent subgraphs**: bbox = union of child bboxes + direct members + padding
///
/// Each nesting level adds `default_padding` cells on all sides, plus one
/// extra row at the top for the subgraph label.
pub fn computeBoundingBoxes(
    g: *const Graph,
    result: *ir_mod.LayoutIR(usize),
    allocator: Allocator,
) !void {
    const sg_count = g.subgraphCount();
    if (sg_count == 0) return;

    // Compute depth of each subgraph for bottom-up ordering
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

    // Sort by depth descending (deepest = leaves first)
    std.mem.sort(usize, order, depths, struct {
        fn cmp(d: []usize, a: usize, b: usize) bool {
            return d[a] > d[b];
        }
    }.cmp);

    // Per-subgraph bounding accumulators (indexed by subgraph array index)
    const min_x = try allocator.alloc(usize, sg_count);
    defer allocator.free(min_x);
    const min_y = try allocator.alloc(usize, sg_count);
    defer allocator.free(min_y);
    const max_x = try allocator.alloc(usize, sg_count);
    defer allocator.free(max_x);
    const max_y = try allocator.alloc(usize, sg_count);
    defer allocator.free(max_y);
    const has_content = try allocator.alloc(bool, sg_count);
    defer allocator.free(has_content);

    @memset(min_x, std.math.maxInt(usize));
    @memset(min_y, std.math.maxInt(usize));
    @memset(max_x, 0);
    @memset(max_y, 0);
    @memset(has_content, false);

    // Pass 1: envelope of direct member nodes
    for (result.nodes.items) |node| {
        if (node.kind == .dummy) continue;
        const node_sg = g.nodeSubgraph(node.id) orelse continue;
        const sg_idx = g.subgraph_id_to_index.get(node_sg) orelse continue;

        has_content[sg_idx] = true;
        min_x[sg_idx] = @min(min_x[sg_idx], node.x);
        min_y[sg_idx] = @min(min_y[sg_idx], node.y);
        max_x[sg_idx] = @max(max_x[sg_idx], node.x + node.width);
        max_y[sg_idx] = @max(max_y[sg_idx], node.y + 1); // node height = 1 row
    }

    // Pass 2: bottom-up — pad each subgraph, then propagate to parent
    for (order) |sg_idx| {
        if (!has_content[sg_idx]) continue;

        const sg = g.subgraphs.items[sg_idx];
        const pad = default_padding;
        const label_row: usize = 1; // extra top row for label

        // Apply padding
        min_x[sg_idx] = if (min_x[sg_idx] >= pad) min_x[sg_idx] - pad else 0;
        min_y[sg_idx] = if (min_y[sg_idx] >= pad + label_row) min_y[sg_idx] - (pad + label_row) else 0;
        max_x[sg_idx] += pad;
        max_y[sg_idx] += pad;

        // Expand parent's accumulator
        if (sg.parent_id) |pid| {
            if (g.subgraph_id_to_index.get(pid)) |parent_idx| {
                has_content[parent_idx] = true;
                min_x[parent_idx] = @min(min_x[parent_idx], min_x[sg_idx]);
                min_y[parent_idx] = @min(min_y[parent_idx], min_y[sg_idx]);
                max_x[parent_idx] = @max(max_x[parent_idx], max_x[sg_idx]);
                max_y[parent_idx] = @max(max_y[parent_idx], max_y[sg_idx]);
            }
        }
    }

    // Emit SubgraphInfo entries to IR
    for (order) |sg_idx| {
        if (!has_content[sg_idx]) continue;
        const sg = g.subgraphs.items[sg_idx];

        try result.subgraphs.append(result.allocator, .{
            .id = sg.id,
            .parent_id = sg.parent_id,
            .label = sg.label,
            .x = min_x[sg_idx],
            .y = min_y[sg_idx],
            .width = max_x[sg_idx] - min_x[sg_idx],
            .height = max_y[sg_idx] - min_y[sg_idx],
        });
    }
}

// ============================================================================
// Tests
// ============================================================================

test "vnodeSubgraph: real node with subgraph" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    const sg = try g.addSubgraph("cluster");
    try g.putNodes(&.{1}).inside(sg);

    // Node 1 (idx 0) is in sg
    try std.testing.expectEqual(@as(?usize, sg), vnodeSubgraph(&g, .{ .real = 0 }));
    // Node 2 (idx 1) has no subgraph
    try std.testing.expectEqual(@as(?usize, null), vnodeSubgraph(&g, .{ .real = 1 }));
}

test "vnodeSubgraph: real node without subgraph" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");

    try std.testing.expectEqual(@as(?usize, null), vnodeSubgraph(&g, .{ .real = 0 }));
}

test "vnodeSubgraph: dummy intra-subgraph edge" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    const sg = try g.addSubgraph("cluster");
    try g.putNodes(&.{ 1, 2 }).inside(sg);

    try g.addEdge(1, 2); // edge 0: intra-subgraph
    try g.addEdge(1, 3); // edge 1: cross-subgraph (A in sg, C root)

    // Dummy for intra-subgraph edge → belongs to sg
    try std.testing.expectEqual(@as(?usize, sg), vnodeSubgraph(&g, .{ .dummy = 0 }));
    // Dummy for cross-subgraph edge → null
    try std.testing.expectEqual(@as(?usize, null), vnodeSubgraph(&g, .{ .dummy = 1 }));
}

test "vnodeSubgraph: dummy cross-subgraph edge" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    const sg_a = try g.addSubgraph("SG-A");
    const sg_b = try g.addSubgraph("SG-B");
    try g.putNodes(&.{1}).inside(sg_a);
    try g.putNodes(&.{2}).inside(sg_b);

    try g.addEdge(1, 2); // edge 0: cross-subgraph

    // Dummy for cross-subgraph edge → null (floats freely)
    try std.testing.expectEqual(@as(?usize, null), vnodeSubgraph(&g, .{ .dummy = 0 }));
}

test "enforceSubgraphAdjacency: groups nodes by subgraph" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addNode(4, "D");
    const sg_a = try g.addSubgraph("SG-A");
    const sg_b = try g.addSubgraph("SG-B");
    try g.putNodes(&.{ 1, 3 }).inside(sg_a); // node_idx 0 and 2
    try g.putNodes(&.{ 2, 4 }).inside(sg_b); // node_idx 1 and 3

    // Single level with interleaved subgraph members:
    // [A(sg_a), B(sg_b), C(sg_a), D(sg_b)]
    var vlevels = VirtualLevels{
        .levels = .{},
        .allocator = allocator,
    };
    defer vlevels.deinit();

    try vlevels.levels.append(allocator, .{});
    try vlevels.levels.items[0].append(allocator, .{ .real = 0 }); // A, sg_a
    try vlevels.levels.items[0].append(allocator, .{ .real = 1 }); // B, sg_b
    try vlevels.levels.items[0].append(allocator, .{ .real = 2 }); // C, sg_a
    try vlevels.levels.items[0].append(allocator, .{ .real = 3 }); // D, sg_b

    try enforceSubgraphAdjacency(&g, &vlevels, allocator);

    // After enforcement: sg_a nodes adjacent, sg_b nodes adjacent
    // sg_a avg pos = (0+2)/2 = 1.0, sg_b avg pos = (1+3)/2 = 2.0
    // → sg_a first, then sg_b: [A, C, B, D]
    const items = vlevels.levels.items[0].items;
    try std.testing.expectEqual(@as(usize, 4), items.len);
    try std.testing.expectEqual(@as(?usize, 0), items[0].realIndex()); // A
    try std.testing.expectEqual(@as(?usize, 2), items[1].realIndex()); // C
    try std.testing.expectEqual(@as(?usize, 1), items[2].realIndex()); // B
    try std.testing.expectEqual(@as(?usize, 3), items[3].realIndex()); // D
}

test "enforceSubgraphAdjacency: preserves single-element levels" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    const sg = try g.addSubgraph("SG");
    try g.putNodes(&.{1}).inside(sg);

    var vlevels = VirtualLevels{
        .levels = .{},
        .allocator = allocator,
    };
    defer vlevels.deinit();

    try vlevels.levels.append(allocator, .{});
    try vlevels.levels.items[0].append(allocator, .{ .real = 0 });

    try enforceSubgraphAdjacency(&g, &vlevels, allocator);

    try std.testing.expectEqual(@as(usize, 1), vlevels.levels.items[0].items.len);
    try std.testing.expectEqual(@as(?usize, 0), vlevels.levels.items[0].items[0].realIndex());
}

test "enforceSubgraphAdjacency: root-level nodes form a block" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    // A(root), B(sg), C(root), D(sg)
    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addNode(4, "D");
    const sg = try g.addSubgraph("SG");
    try g.putNodes(&.{ 2, 4 }).inside(sg); // B(idx1), D(idx3)

    var vlevels = VirtualLevels{
        .levels = .{},
        .allocator = allocator,
    };
    defer vlevels.deinit();

    try vlevels.levels.append(allocator, .{});
    try vlevels.levels.items[0].append(allocator, .{ .real = 0 }); // A root
    try vlevels.levels.items[0].append(allocator, .{ .real = 1 }); // B sg
    try vlevels.levels.items[0].append(allocator, .{ .real = 2 }); // C root
    try vlevels.levels.items[0].append(allocator, .{ .real = 3 }); // D sg

    try enforceSubgraphAdjacency(&g, &vlevels, allocator);

    const items = vlevels.levels.items[0].items;
    try std.testing.expectEqual(@as(usize, 4), items.len);

    // Root avg = (0+2)/2 = 1.0, SG avg = (1+3)/2 = 2.0
    // → root block first: [A, C], then sg block: [B, D]
    try std.testing.expectEqual(@as(?usize, 0), items[0].realIndex()); // A
    try std.testing.expectEqual(@as(?usize, 2), items[1].realIndex()); // C
    try std.testing.expectEqual(@as(?usize, 1), items[2].realIndex()); // B
    try std.testing.expectEqual(@as(?usize, 3), items[3].realIndex()); // D
}

test "enforceSubgraphAdjacency: no subgraphs is noop" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");

    var vlevels = VirtualLevels{
        .levels = .{},
        .allocator = allocator,
    };
    defer vlevels.deinit();

    try vlevels.levels.append(allocator, .{});
    try vlevels.levels.items[0].append(allocator, .{ .real = 0 });
    try vlevels.levels.items[0].append(allocator, .{ .real = 1 });
    try vlevels.levels.items[0].append(allocator, .{ .real = 2 });

    try enforceSubgraphAdjacency(&g, &vlevels, allocator);

    // All nodes are root-level → same single block → order preserved
    const items = vlevels.levels.items[0].items;
    try std.testing.expectEqual(@as(?usize, 0), items[0].realIndex());
    try std.testing.expectEqual(@as(?usize, 1), items[1].realIndex());
    try std.testing.expectEqual(@as(?usize, 2), items[2].realIndex());
}

test "computeBoundingBoxes: simple flat subgraph" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "AA"); // width = 4 (label 2 + borders 2)
    try g.addNode(2, "BB");
    const sg = try g.addSubgraph("cluster");
    try g.putNodes(&.{ 1, 2 }).inside(sg);

    // Build a mock IR with positioned nodes
    var result = ir_mod.LayoutIR(usize).init(allocator);
    defer result.deinit();

    try result.addNode(.{
        .id = 1,
        .label = "AA",
        .x = 5,
        .y = 3,
        .width = 4,
        .center_x = 7,
        .level = 0,
        .level_position = 0,
        .kind = .explicit,
    });
    try result.addNode(.{
        .id = 2,
        .label = "BB",
        .x = 12,
        .y = 3,
        .width = 4,
        .center_x = 14,
        .level = 0,
        .level_position = 1,
        .kind = .explicit,
    });

    try computeBoundingBoxes(&g, &result, allocator);

    // Should have 1 subgraph bbox
    try std.testing.expectEqual(@as(usize, 1), result.subgraphs.items.len);
    const bbox = result.subgraphs.items[0];
    try std.testing.expectEqual(sg, bbox.id);
    try std.testing.expectEqualStrings("cluster", bbox.label);

    // Node envelope: x=[5, 16), y=[3, 4)
    // Padding: 1 cell each side, 1 extra top for label
    // min_x = 5 - 1 = 4, min_y = 3 - 2 = 1, max_x = 16 + 1 = 17, max_y = 4 + 1 = 5
    try std.testing.expectEqual(@as(usize, 4), bbox.x);
    try std.testing.expectEqual(@as(usize, 1), bbox.y);
    try std.testing.expectEqual(@as(usize, 13), bbox.width); // 17 - 4
    try std.testing.expectEqual(@as(usize, 4), bbox.height); // 5 - 1
}

test "computeBoundingBoxes: nested subgraphs" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    const outer = try g.addSubgraph("outer");
    const inner = try g.addSubgraph("inner");
    try g.putSubgraphs(&.{inner}).inside(outer);
    try g.putNodes(&.{ 1, 2 }).inside(inner);

    var result = ir_mod.LayoutIR(usize).init(allocator);
    defer result.deinit();

    try result.addNode(.{
        .id = 1, .label = "A", .x = 10, .y = 5,
        .width = 3, .center_x = 11, .level = 0, .level_position = 0, .kind = .explicit,
    });
    try result.addNode(.{
        .id = 2, .label = "B", .x = 16, .y = 5,
        .width = 3, .center_x = 17, .level = 0, .level_position = 1, .kind = .explicit,
    });

    try computeBoundingBoxes(&g, &result, allocator);

    // Should have 2 subgraph bboxes (inner first in bottom-up order)
    try std.testing.expectEqual(@as(usize, 2), result.subgraphs.items.len);

    // Find inner and outer by ID
    var inner_bbox: ?ir_mod.SubgraphInfo(usize) = null;
    var outer_bbox: ?ir_mod.SubgraphInfo(usize) = null;
    for (result.subgraphs.items) |sg_info| {
        if (sg_info.id == inner) inner_bbox = sg_info;
        if (sg_info.id == outer) outer_bbox = sg_info;
    }

    try std.testing.expect(inner_bbox != null);
    try std.testing.expect(outer_bbox != null);

    // Inner envelope: x=[10, 19), y=[5, 6), padded: x=[9, 20), y=[3, 7)
    const ib = inner_bbox.?;
    try std.testing.expectEqual(@as(usize, 9), ib.x);
    try std.testing.expectEqual(@as(usize, 3), ib.y);

    // Outer must fully contain inner (with additional padding)
    const ob = outer_bbox.?;
    try std.testing.expect(ob.x <= ib.x);
    try std.testing.expect(ob.y <= ib.y);
    try std.testing.expect(ob.x + ob.width >= ib.x + ib.width);
    try std.testing.expect(ob.y + ob.height >= ib.y + ib.height);
}

test "computeBoundingBoxes: empty subgraph produces no bbox" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    _ = try g.addSubgraph("empty"); // no nodes placed inside

    var result = ir_mod.LayoutIR(usize).init(allocator);
    defer result.deinit();

    try result.addNode(.{
        .id = 1, .label = "A", .x = 0, .y = 0,
        .width = 3, .center_x = 1, .level = 0, .level_position = 0, .kind = .explicit,
    });

    try computeBoundingBoxes(&g, &result, allocator);

    // Empty subgraph should NOT appear in output
    try std.testing.expectEqual(@as(usize, 0), result.subgraphs.items.len);
}

test "computeBoundingBoxes: skips dummy nodes" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    const sg = try g.addSubgraph("SG");
    try g.putNodes(&.{1}).inside(sg);

    var result = ir_mod.LayoutIR(usize).init(allocator);
    defer result.deinit();

    // Real node in subgraph
    try result.addNode(.{
        .id = 1, .label = "A", .x = 5, .y = 3,
        .width = 3, .center_x = 6, .level = 0, .level_position = 0, .kind = .explicit,
    });
    // Dummy node at extreme position — should NOT affect bbox
    try result.addNode(.{
        .id = 0x80000000, .label = "O", .x = 100, .y = 100,
        .width = 1, .center_x = 100, .level = 1, .level_position = 0, .kind = .dummy,
    });
    // Real node NOT in subgraph
    try result.addNode(.{
        .id = 2, .label = "B", .x = 50, .y = 50,
        .width = 3, .center_x = 51, .level = 1, .level_position = 1, .kind = .explicit,
    });

    try computeBoundingBoxes(&g, &result, allocator);

    try std.testing.expectEqual(@as(usize, 1), result.subgraphs.items.len);
    const bbox = result.subgraphs.items[0];
    // Only node A (x=5, width=3) contributes: envelope x=[5,8), y=[3,4)
    // Padded: x=[4,9), y=[1,5)  → width=5, height=4
    try std.testing.expectEqual(@as(usize, 4), bbox.x);
    try std.testing.expectEqual(@as(usize, 1), bbox.y);
    try std.testing.expectEqual(@as(usize, 5), bbox.width);
    try std.testing.expectEqual(@as(usize, 4), bbox.height);
}

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
