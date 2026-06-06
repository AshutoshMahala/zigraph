//! Subgraph position padding for horizontal and vertical spacing.
//!
//! Provides functions to insert extra space into the layout for subgraph
//! boundary lines. Horizontal padding shifts x-coordinates based on the
//! number of subgraph boundaries crossed between adjacent nodes. Vertical
//! padding computes per-level y-offsets for top/bottom borders.

const std = @import("std");
const Allocator = std.mem.Allocator;
const graph_mod = @import("../../../core/graph.zig");
const Graph = graph_mod.Graph;
const virtual_mod = @import("../layering/virtual.zig");
const VirtualLevels = virtual_mod.VirtualLevels;
const VNode = virtual_mod.VNode;
const VirtualPositions = virtual_mod.VirtualPositions;
const common = @import("common.zig");
const vnodeSubgraph = common.vnodeSubgraph;
const ancestorChain = common.ancestorChain;
const countBoundaryTransitions = common.countBoundaryTransitions;
const default_padding = common.default_padding;

/// Apply horizontal padding to virtual positions for subgraph borders.
///
/// After crossing reduction and initial positioning, this function shifts
/// x-coordinates to create space for subgraph boundary lines. The padding
/// ensures that subgraph boxes drawn by renderers don't overlap with nodes
/// from other subgraphs.
///
/// For each adjacent pair of VNodes on a level, if they belong to different
/// subgraphs (or different nesting levels), extra horizontal space is inserted
/// proportional to the number of subgraph boundaries crossed.
///
/// At the left and right edges of each level, space is added for the outermost
/// subgraph borders of the first and last nodes.
///
/// Only call when `g.hasSubgraphs()` is true.
pub fn applySubgraphPadding(
    g: *const Graph,
    vlevels: *const VirtualLevels,
    positions: *VirtualPositions,
    allocator: Allocator,
) !void {
    const pad = default_padding;
    const sg_count = g.subgraphCount();
    if (sg_count == 0) return;

    // Scratch buffers for ancestor chain computation
    const max_depth: usize = 16; // support up to 16 nesting levels
    var chain_a: [max_depth]usize = undefined;
    var chain_b: [max_depth]usize = undefined;

    // Per-level x offset accumulator (allocated once)
    var max_width: usize = 0;
    for (vlevels.levels.items) |level| {
        max_width = @max(max_width, level.items.len);
    }
    if (max_width == 0) return;

    const offsets = try allocator.alloc(usize, max_width);
    defer allocator.free(offsets);

    var new_total_width: usize = 0;

    for (vlevels.levels.items, 0..) |level, level_idx| {
        const n = level.items.len;
        if (n == 0) continue;

        // Compute cumulative x-offset for each VNode position.
        // Offset[i] = total extra padding to add to node i's x.

        // First node: offset for left-side subgraph borders
        const first_sg = vnodeSubgraph(g, level.items[0]);
        const first_depth = if (first_sg) |sg| ancestorChain(g, sg, &chain_a) else 0;
        offsets[0] = first_depth * pad;

        // Subsequent nodes: add transitions between adjacent pairs
        for (1..n) |i| {
            const prev_sg = vnodeSubgraph(g, level.items[i - 1]);
            const curr_sg = vnodeSubgraph(g, level.items[i]);
            const transitions = countBoundaryTransitions(
                g,
                prev_sg,
                curr_sg,
                &chain_a,
                &chain_b,
            );
            // Each transition needs 'pad' space on each side of the border
            offsets[i] = offsets[i - 1] + transitions * pad;
        }

        // Last node: additional right-side borders
        const last_sg = vnodeSubgraph(g, level.items[n - 1]);
        const last_depth = if (last_sg) |sg| ancestorChain(g, sg, &chain_a) else 0;
        const right_extra = last_depth * pad;

        // Apply offsets to x positions
        for (0..n) |i| {
            positions.x.items[level_idx].items[i] += offsets[i];
        }

        // Update total width estimate
        if (n > 0) {
            const last_x = positions.x.items[level_idx].items[n - 1];
            const last_w = level.items[n - 1].width(g);
            new_total_width = @max(new_total_width, last_x + last_w + right_extra);
        }
    }

    positions.total_width = @max(positions.total_width, new_total_width);
}

/// Compute per-level y-offsets to create vertical space for subgraph borders.
///
/// Returns an array of y-offsets indexed by level. Each entry is the extra
/// vertical space (in rows) to add before that level due to subgraph borders
/// that start or end between the previous level and this one.
///
/// The caller must `allocator.free()` the returned slice.
pub fn computeLevelYOffsets(
    g: *const Graph,
    vlevels: *const VirtualLevels,
    allocator: Allocator,
) ![]usize {
    const num_levels = vlevels.levels.items.len;
    if (num_levels == 0) return allocator.alloc(usize, 0);

    const sg_count = g.subgraphCount();
    // Padding per nesting level must match computeBoundingBoxes.
    const pad: usize = default_padding;
    const label_row: usize = 1; // extra row for subgraph label

    const y_offsets = try allocator.alloc(usize, num_levels);
    @memset(y_offsets, 0);

    if (sg_count == 0) return y_offsets;

    // Per-subgraph level presence matrix.
    const sg_on_level = try allocator.alloc(bool, sg_count * num_levels);
    defer allocator.free(sg_on_level);
    @memset(sg_on_level, false);

    // Fill level presence — check which levels each subgraph has members on
    for (vlevels.levels.items, 0..) |level, level_idx| {
        for (level.items) |vnode| {
            var sg_id = vnodeSubgraph(g, vnode);
            // Mark all ancestors as present too
            while (sg_id) |sid| {
                if (g.subgraph_id_to_index.get(sid)) |sg_idx| {
                    sg_on_level[sg_idx * num_levels + level_idx] = true;
                }
                const sg = g.subgraphById(sid) orelse break;
                sg_id = sg.parent_id;
            }
        }
    }

    // For each level boundary, compute the maximum *stacking depth* of
    // opening and closing subgraph borders.
    //
    // Sibling subgraphs at the same depth sit side-by-side, not stacked,
    // so we use the deepest ancestor chain rather than counting every border.
    // For each transitioning subgraph, its stacking depth = 1 + number of
    // ancestors that also transition at this same boundary.
    for (1..num_levels) |level_idx| {
        var max_open_depth: usize = 0;
        var max_close_depth: usize = 0;

        for (0..sg_count) |sg_idx| {
            const on_prev = sg_on_level[sg_idx * num_levels + level_idx - 1];
            const on_curr = sg_on_level[sg_idx * num_levels + level_idx];

            if (on_curr and !on_prev) {
                // Subgraph opens — walk parent chain to count stacked ancestors
                var depth: usize = 1;
                var parent_id = g.subgraphs.items[sg_idx].parent_id;
                while (parent_id) |pid| {
                    if (g.subgraph_id_to_index.get(pid)) |parent_idx| {
                        const p_prev = sg_on_level[parent_idx * num_levels + level_idx - 1];
                        const p_curr = sg_on_level[parent_idx * num_levels + level_idx];
                        if (p_curr and !p_prev) depth += 1;
                    }
                    const parent_sg = g.subgraphById(pid) orelse break;
                    parent_id = parent_sg.parent_id;
                }
                max_open_depth = @max(max_open_depth, depth);
            }

            if (on_prev and !on_curr) {
                // Subgraph closes — walk parent chain to count stacked ancestors
                var depth: usize = 1;
                var parent_id = g.subgraphs.items[sg_idx].parent_id;
                while (parent_id) |pid| {
                    if (g.subgraph_id_to_index.get(pid)) |parent_idx| {
                        const p_prev = sg_on_level[parent_idx * num_levels + level_idx - 1];
                        const p_curr = sg_on_level[parent_idx * num_levels + level_idx];
                        if (p_prev and !p_curr) depth += 1;
                    }
                    const parent_sg = g.subgraphById(pid) orelse break;
                    parent_id = parent_sg.parent_id;
                }
                max_close_depth = @max(max_close_depth, depth);
            }
        }

        y_offsets[level_idx] = max_close_depth * pad + max_open_depth * (pad + label_row);
    }

    // First level: max stacking depth of subgraphs that start here
    {
        var max_open_depth: usize = 0;
        for (0..sg_count) |sg_idx| {
            if (sg_on_level[sg_idx * num_levels + 0]) {
                var depth: usize = 1;
                var parent_id = g.subgraphs.items[sg_idx].parent_id;
                while (parent_id) |pid| {
                    if (g.subgraph_id_to_index.get(pid)) |parent_idx| {
                        if (sg_on_level[parent_idx * num_levels + 0]) depth += 1;
                    }
                    const parent_sg = g.subgraphById(pid) orelse break;
                    parent_id = parent_sg.parent_id;
                }
                max_open_depth = @max(max_open_depth, depth);
            }
        }
        y_offsets[0] = max_open_depth * (pad + label_row);
    }

    return y_offsets;
}

// ============================================================================
// Tests
// ============================================================================

test "applySubgraphPadding: adds horizontal space" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    // Two nodes: A(root), B(sg) on same level
    try g.addNode(1, "A"); // width 3
    try g.addNode(2, "B"); // width 3
    const sg = try g.addSubgraph("SG");
    try g.putNodes(&.{2}).inside(sg);

    var vlevels = VirtualLevels{
        .levels = .empty,
        .allocator = allocator,
    };
    defer vlevels.deinit();

    try vlevels.levels.append(allocator, .empty);
    try vlevels.levels.items[0].append(allocator, .{ .real = 0 }); // A root
    try vlevels.levels.items[0].append(allocator, .{ .real = 1 }); // B sg

    // Create initial positions: A at x=0, B at x=6
    var positions = VirtualPositions{
        .x = .{},
        .total_width = 9,
        .total_height = 1,
        .allocator = allocator,
    };
    defer positions.deinit();
    try positions.x.append(allocator, .empty);
    try positions.x.items[0].append(allocator, 0); // A
    try positions.x.items[0].append(allocator, 6); // B

    try applySubgraphPadding(&g, &vlevels, &positions, allocator);

    // A (root) should be at x=0 (no subgraph borders on left)
    try std.testing.expectEqual(@as(usize, 0), positions.x.items[0].items[0]);

    // B (sg, depth 1) has 1 boundary transition from root→sg
    // Transition padding = 1 * default_padding = 2
    // So B's offset = 0 + 2 = 2, B's x = 6 + 2 = 8
    try std.testing.expectEqual(@as(usize, 8), positions.x.items[0].items[1]);
}

test "applySubgraphPadding: nested subgraph adds more padding" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A"); // root node
    try g.addNode(2, "B"); // in inner subgraph
    const outer = try g.addSubgraph("outer");
    const inner = try g.addSubgraph("inner");
    try g.putSubgraphs(&.{inner}).inside(outer);
    try g.putNodes(&.{2}).inside(inner);

    var vlevels = VirtualLevels{
        .levels = .empty,
        .allocator = allocator,
    };
    defer vlevels.deinit();

    try vlevels.levels.append(allocator, .empty);
    try vlevels.levels.items[0].append(allocator, .{ .real = 0 }); // A root
    try vlevels.levels.items[0].append(allocator, .{ .real = 1 }); // B inner

    var positions = VirtualPositions{
        .x = .{},
        .total_width = 9,
        .total_height = 1,
        .allocator = allocator,
    };
    defer positions.deinit();
    try positions.x.append(allocator, .empty);
    try positions.x.items[0].append(allocator, 0); // A
    try positions.x.items[0].append(allocator, 6); // B

    try applySubgraphPadding(&g, &vlevels, &positions, allocator);

    // A at x=0 (no borders)
    try std.testing.expectEqual(@as(usize, 0), positions.x.items[0].items[0]);

    // B is in inner (depth 2), root→inner boundary means 2 transitions
    // offset = 0 + 2 * 2 = 4, B's x = 6 + 4 = 10
    try std.testing.expectEqual(@as(usize, 10), positions.x.items[0].items[1]);
}

test "computeLevelYOffsets: subgraph spanning all levels" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    const sg = try g.addSubgraph("SG");
    try g.putNodes(&.{ 1, 2 }).inside(sg);

    // Two levels: A on level 0, B on level 1
    var vlevels = VirtualLevels{
        .levels = .empty,
        .allocator = allocator,
    };
    defer vlevels.deinit();

    try vlevels.levels.append(allocator, .empty);
    try vlevels.levels.items[0].append(allocator, .{ .real = 0 });
    try vlevels.levels.append(allocator, .empty);
    try vlevels.levels.items[1].append(allocator, .{ .real = 1 });

    const offsets = try computeLevelYOffsets(&g, &vlevels, allocator);
    defer allocator.free(offsets);

    try std.testing.expectEqual(@as(usize, 2), offsets.len);
    // Level 0: subgraph starts here → top border (y_pad=2 + label=1 = 3)
    try std.testing.expectEqual(@as(usize, 3), offsets[0]);
    // Level 1: subgraph continues (no new borders) → 0
    try std.testing.expectEqual(@as(usize, 0), offsets[1]);
}

test "computeLevelYOffsets: subgraph starts mid-graph" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "X"); // root, level 0
    try g.addNode(2, "A"); // sg, level 1
    try g.addNode(3, "B"); // sg, level 2
    const sg = try g.addSubgraph("SG");
    try g.putNodes(&.{ 2, 3 }).inside(sg);

    var vlevels = VirtualLevels{
        .levels = .empty,
        .allocator = allocator,
    };
    defer vlevels.deinit();

    try vlevels.levels.append(allocator, .empty);
    try vlevels.levels.items[0].append(allocator, .{ .real = 0 }); // X
    try vlevels.levels.append(allocator, .empty);
    try vlevels.levels.items[1].append(allocator, .{ .real = 1 }); // A
    try vlevels.levels.append(allocator, .empty);
    try vlevels.levels.items[2].append(allocator, .{ .real = 2 }); // B

    const offsets = try computeLevelYOffsets(&g, &vlevels, allocator);
    defer allocator.free(offsets);

    try std.testing.expectEqual(@as(usize, 3), offsets.len);
    // Level 0: no subgraphs → 0
    try std.testing.expectEqual(@as(usize, 0), offsets[0]);
    // Level 1: subgraph starts → top border (y_pad=2 + label=1 = 3)
    try std.testing.expectEqual(@as(usize, 3), offsets[1]);
    // Level 2: subgraph continues → 0
    try std.testing.expectEqual(@as(usize, 0), offsets[2]);
}

test "computeLevelYOffsets: no subgraphs returns zeros" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");

    var vlevels = VirtualLevels{
        .levels = .empty,
        .allocator = allocator,
    };
    defer vlevels.deinit();

    try vlevels.levels.append(allocator, .empty);
    try vlevels.levels.items[0].append(allocator, .{ .real = 0 });

    const offsets = try computeLevelYOffsets(&g, &vlevels, allocator);
    defer allocator.free(offsets);

    try std.testing.expectEqual(@as(usize, 1), offsets.len);
    try std.testing.expectEqual(@as(usize, 0), offsets[0]);
}
