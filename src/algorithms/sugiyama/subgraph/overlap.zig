//! Subgraph overlap repair.
//!
//! After horizontal padding and position extraction, sibling subgraphs may still
//! overlap if their bounding boxes (computed from member nodes) collide.
//!
//! This module implements an iterative overlap detection and shifting algorithm
//! inspired by ascii-dag's `fix_subgraph_overlaps()`:
//!
//! 1. Compute per-subgraph bounding box envelope from node positions
//! 2. Group sibling subgraphs by parent
//! 3. For each sibling pair whose level ranges overlap, enforce a minimum gap
//! 4. Shift conflicting subgraphs (and all their descendants) right
//! 5. Repair per-level node collisions caused by the shifts
//! 6. Repeat up to MAX_ROUNDS until convergence

const std = @import("std");
const Allocator = std.mem.Allocator;
const graph_mod = @import("../../../core/graph.zig");
const Graph = graph_mod.Graph;
const common = @import("common.zig");
const default_padding = common.default_padding;

/// Horizontal padding for subgraph borders (same as default_padding).
const SUBGRAPH_H_PAD: usize = default_padding;
/// Minimum gap (in cells) between sibling subgraph bounding boxes.
const SIBLING_GAP: usize = 1;
/// Maximum repair iterations.
const MAX_ROUNDS: usize = 8;
/// Minimum gap between nodes of different subgraphs on the same level.
const CROSS_SG_GAP: usize = SUBGRAPH_H_PAD + SIBLING_GAP + SUBGRAPH_H_PAD; // 5

/// Fix overlapping sibling subgraphs by shifting node x-coordinates.
///
/// Operates on the extracted real node positions. Returns the total extra
/// width added (so the caller can update total_width).
///
/// Parameters:
///   - g: the graph (for subgraph hierarchy info)
///   - node_x: mutable x-coordinates indexed by node_idx
///   - node_level: level assignment per node_idx
///   - node_widths: width per node_idx
///   - node_count: number of real nodes
///   - allocator: scratch memory
pub fn fixSubgraphOverlaps(
    g: *const Graph,
    node_x: []usize,
    node_level: []const usize,
    node_widths: []const usize,
    node_count: usize,
    allocator: Allocator,
) !usize {
    const sg_count = g.subgraphCount();
    if (sg_count < 2) return 0;

    // ── Build node → subgraph index mapping ──────────────────────────
    const node_sg = try allocator.alloc(?usize, node_count);
    defer allocator.free(node_sg);

    for (0..node_count) |ni| {
        const node = g.nodeAt(ni) orelse {
            node_sg[ni] = null;
            continue;
        };
        if (g.nodeSubgraph(node.id)) |sg_id| {
            node_sg[ni] = g.subgraph_id_to_index.get(sg_id);
        } else {
            node_sg[ni] = null;
        }
    }

    // ── Per-subgraph level ranges ────────────────────────────────────
    const sg_min_level = try allocator.alloc(usize, sg_count);
    defer allocator.free(sg_min_level);
    const sg_max_level = try allocator.alloc(usize, sg_count);
    defer allocator.free(sg_max_level);
    @memset(sg_min_level, std.math.maxInt(usize));
    @memset(sg_max_level, 0);

    for (0..node_count) |ni| {
        if (node_sg[ni]) |sg_idx| {
            const lvl = node_level[ni];
            sg_min_level[sg_idx] = @min(sg_min_level[sg_idx], lvl);
            sg_max_level[sg_idx] = @max(sg_max_level[sg_idx], lvl);
        }
    }

    // Propagate child ranges UP to parents (bottom-up by depth)
    const depths = try allocator.alloc(usize, sg_count);
    defer allocator.free(depths);
    var max_depth: usize = 0;
    for (g.subgraphs.items, 0..) |sg, i| {
        var d: usize = 0;
        var cur = sg.parent_id;
        while (cur) |pid| {
            d += 1;
            const parent = g.subgraphById(pid) orelse break;
            cur = parent.parent_id;
        }
        depths[i] = d;
        max_depth = @max(max_depth, d);
    }

    // Bottom-up propagation
    {
        var depth = max_depth;
        while (true) {
            for (0..sg_count) |sg_idx| {
                if (depths[sg_idx] != depth) continue;
                if (sg_min_level[sg_idx] == std.math.maxInt(usize)) continue;
                const parent_id = g.subgraphs.items[sg_idx].parent_id orelse continue;
                const parent_idx = g.subgraph_id_to_index.get(parent_id) orelse continue;
                sg_min_level[parent_idx] = @min(sg_min_level[parent_idx], sg_min_level[sg_idx]);
                sg_max_level[parent_idx] = @max(sg_max_level[parent_idx], sg_max_level[sg_idx]);
            }
            if (depth == 0) break;
            depth -= 1;
        }
    }

    // ── Collect descendants mapping (sg_idx → list of all descendant node indices) ──
    // We flatten this: for each node, compute all ancestor subgraph indices
    // Then when shifting a subgraph, we shift all nodes whose ancestor chain includes it.

    // ── Iterative overlap repair ─────────────────────────────────────
    var total_extra: usize = 0;

    for (0..MAX_ROUNDS) |_| {
        // Compute fresh bboxes matching bbox.zig's rendering logic exactly:
        // 1. Node envelope per leaf subgraph
        // 2. Bottom-up: pad each subgraph, then propagate to parent with gap
        const bbox_min_x = try allocator.alloc(usize, sg_count);
        defer allocator.free(bbox_min_x);
        const bbox_max_x = try allocator.alloc(usize, sg_count);
        defer allocator.free(bbox_max_x);
        const bbox_valid = try allocator.alloc(bool, sg_count);
        defer allocator.free(bbox_valid);
        @memset(bbox_min_x, std.math.maxInt(usize));
        @memset(bbox_max_x, 0);
        @memset(bbox_valid, false);

        // Pass 1: direct member node envelope
        for (0..node_count) |ni| {
            if (node_sg[ni]) |sg_idx| {
                bbox_valid[sg_idx] = true;
                bbox_min_x[sg_idx] = @min(bbox_min_x[sg_idx], node_x[ni]);
                bbox_max_x[sg_idx] = @max(bbox_max_x[sg_idx], node_x[ni] + node_widths[ni]);
            }
        }

        // Sort subgraphs by depth descending for bottom-up processing
        const order = try allocator.alloc(usize, sg_count);
        defer allocator.free(order);
        for (0..sg_count) |i| order[i] = i;
        std.mem.sort(usize, order, depths, struct {
            fn cmp(d: []const usize, a: usize, b: usize) bool {
                return d[a] > d[b];
            }
        }.cmp);

        // Pass 2: bottom-up — pad each subgraph, then propagate to parent
        // This matches bbox.zig exactly: pad → expand parent → pad parent → ...
        const PARENT_CHILD_H_GAP: usize = 1;
        for (order) |sg_idx| {
            if (!bbox_valid[sg_idx]) continue;

            // Apply padding to this subgraph's bbox
            if (bbox_min_x[sg_idx] >= SUBGRAPH_H_PAD) {
                bbox_min_x[sg_idx] -= SUBGRAPH_H_PAD;
            } else {
                bbox_min_x[sg_idx] = 0;
            }
            bbox_max_x[sg_idx] += SUBGRAPH_H_PAD;

            // Ensure label fits
            const sg = g.subgraphs.items[sg_idx];
            if (sg.label.len > 0) {
                const min_label_width = sg.label.len + 4;
                const current_width = bbox_max_x[sg_idx] - bbox_min_x[sg_idx];
                if (current_width < min_label_width) {
                    bbox_max_x[sg_idx] += min_label_width - current_width;
                }
            }

            // Expand parent's accumulator (with PARENT_CHILD_H_GAP)
            if (sg.parent_id) |pid| {
                if (g.subgraph_id_to_index.get(pid)) |parent_idx| {
                    bbox_valid[parent_idx] = true;
                    const child_left = if (bbox_min_x[sg_idx] >= PARENT_CHILD_H_GAP)
                        bbox_min_x[sg_idx] - PARENT_CHILD_H_GAP
                    else
                        0;
                    const child_right = bbox_max_x[sg_idx] + PARENT_CHILD_H_GAP;
                    bbox_min_x[parent_idx] = @min(bbox_min_x[parent_idx], child_left);
                    bbox_max_x[parent_idx] = @max(bbox_max_x[parent_idx], child_right);
                }
            }
        }

        // ── Group siblings by parent ─────────────────────────────────
        // Find all unique parent IDs, then process each group
        var any_shifted = false;

        // Collect all parent→children groups
        // Use a temporary array of (parent_id_or_sentinel, sg_idx) pairs
        const Parent = struct { parent: usize, sg_idx: usize };
        var parents_list = std.ArrayListUnmanaged(Parent).empty;
        defer parents_list.deinit(allocator);

        const SENTINEL: usize = std.math.maxInt(usize);
        for (0..sg_count) |sg_idx| {
            if (!bbox_valid[sg_idx]) continue;
            const parent_key = if (g.subgraphs.items[sg_idx].parent_id) |pid|
                g.subgraph_id_to_index.get(pid) orelse SENTINEL
            else
                SENTINEL;
            try parents_list.append(allocator, .{ .parent = parent_key, .sg_idx = sg_idx });
        }

        // Sort by parent key to group siblings together
        std.mem.sort(Parent, parents_list.items, {}, struct {
            fn cmp(_: void, a: Parent, b: Parent) bool {
                return a.parent < b.parent;
            }
        }.cmp);

        // Process each sibling group
        var group_start: usize = 0;
        while (group_start < parents_list.items.len) {
            const group_parent = parents_list.items[group_start].parent;
            var group_end = group_start + 1;
            while (group_end < parents_list.items.len and
                parents_list.items[group_end].parent == group_parent) : (group_end += 1)
            {}

            const group = parents_list.items[group_start..group_end];
            if (group.len >= 2) {
                // Sort siblings by left edge of bbox
                std.mem.sort(Parent, group, bbox_min_x, struct {
                    fn cmp(min_x: []const usize, a: Parent, b: Parent) bool {
                        return min_x[a.sg_idx] < min_x[b.sg_idx];
                    }
                }.cmp);

                // Level-aware frontier sweep
                const Frontier = struct { sg_idx: usize, right: usize, min_l: usize, max_l: usize };
                var processed = std.ArrayListUnmanaged(Frontier).empty;
                defer processed.deinit(allocator);

                for (group) |entry| {
                    const sg_idx = entry.sg_idx;
                    const left = bbox_min_x[sg_idx];
                    const right = bbox_max_x[sg_idx];
                    const cur_min_l = sg_min_level[sg_idx];
                    const cur_max_l = sg_max_level[sg_idx];

                    // Find effective frontier among level-overlapping siblings
                    var eff_frontier: usize = 0;
                    var has_level_overlap = false;
                    for (processed.items) |prev| {
                        const overlaps = prev.min_l <= cur_max_l and cur_min_l <= prev.max_l;
                        if (overlaps and prev.right > eff_frontier) {
                            eff_frontier = prev.right;
                            has_level_overlap = true;
                        }
                    }

                    if (has_level_overlap and eff_frontier + SIBLING_GAP > left) {
                        const shift = eff_frontier + SIBLING_GAP - left;

                        // Shift all nodes in this subgraph and its descendants
                        shiftSubgraphNodes(g, sg_idx, node_sg, node_x, node_count, shift);

                        total_extra += shift;
                        any_shifted = true;

                        try processed.append(allocator, .{
                            .sg_idx = sg_idx,
                            .right = right + shift,
                            .min_l = cur_min_l,
                            .max_l = cur_max_l,
                        });
                    } else {
                        try processed.append(allocator, .{
                            .sg_idx = sg_idx,
                            .right = right,
                            .min_l = cur_min_l,
                            .max_l = cur_max_l,
                        });
                    }
                }
            }

            group_start = group_end;
        }

        // ── Per-level collision repair ───────────────────────────────
        if (any_shifted) {
            const max_level = blk: {
                var ml: usize = 0;
                for (node_level[0..node_count]) |l| ml = @max(ml, l);
                break :blk ml;
            };

            for (0..max_level + 1) |level| {
                // Collect node indices at this level, sorted by x
                var level_nodes = std.ArrayListUnmanaged(usize).empty;
                defer level_nodes.deinit(allocator);

                for (0..node_count) |ni| {
                    if (node_level[ni] == level) {
                        try level_nodes.append(allocator, ni);
                    }
                }

                std.mem.sort(usize, level_nodes.items, node_x, struct {
                    fn cmp(x: []const usize, a: usize, b: usize) bool {
                        return x[a] < x[b];
                    }
                }.cmp);

                // Enforce minimum gap between adjacent nodes
                for (1..level_nodes.items.len) |j| {
                    const prev = level_nodes.items[j - 1];
                    const curr = level_nodes.items[j];

                    const need_sg_gap = blk: {
                        const prev_sg = node_sg[prev];
                        const curr_sg = node_sg[curr];
                        if (prev_sg != null and curr_sg != null) {
                            break :blk prev_sg.? != curr_sg.?;
                        }
                        // If either node is unaffiliated, use standard gap
                        break :blk false;
                    };

                    const gap: usize = if (need_sg_gap) CROSS_SG_GAP else 3;
                    const prev_right = node_x[prev] + node_widths[prev] + gap;
                    if (node_x[curr] < prev_right) {
                        node_x[curr] = prev_right;
                    }
                }
            }
        }

        if (!any_shifted) break; // Converged
    }

    return total_extra;
}

/// Shift all nodes belonging to a subgraph or any of its descendants.
fn shiftSubgraphNodes(
    g: *const Graph,
    sg_idx: usize,
    node_sg: []const ?usize,
    node_x: []usize,
    node_count: usize,
    shift: usize,
) void {
    for (0..node_count) |ni| {
        const nsg = node_sg[ni] orelse continue;
        if (isDescendantOrSelf(g, nsg, sg_idx)) {
            node_x[ni] += shift;
        }
    }
}

/// Check if child_sg_idx is the same as or a descendant of ancestor_sg_idx.
fn isDescendantOrSelf(g: *const Graph, child_sg_idx: usize, ancestor_sg_idx: usize) bool {
    if (child_sg_idx == ancestor_sg_idx) return true;
    var cur_idx = child_sg_idx;
    while (true) {
        const parent_id = g.subgraphs.items[cur_idx].parent_id orelse return false;
        const parent_idx = g.subgraph_id_to_index.get(parent_id) orelse return false;
        if (parent_idx == ancestor_sg_idx) return true;
        cur_idx = parent_idx;
    }
}

// ============================================================================
// Tests
// ============================================================================

test "fixSubgraphOverlaps: two sibling subgraphs get separated" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    const sg1 = try g.addSubgraph("SG1");
    const sg2 = try g.addSubgraph("SG2");
    try g.putNodes(&.{1}).inside(sg1);
    try g.putNodes(&.{2}).inside(sg2);

    // Both nodes at x=0, level=0, width=3 — they overlap
    var node_x = [_]usize{ 0, 0 };
    const node_level = [_]usize{ 0, 0 };
    const node_widths = [_]usize{ 3, 3 };

    const extra = try fixSubgraphOverlaps(
        &g,
        &node_x,
        &node_level,
        &node_widths,
        2,
        allocator,
    );

    // Node B should have been shifted right
    try std.testing.expect(node_x[1] > node_x[0]);
    try std.testing.expect(extra > 0);
}

test "fixSubgraphOverlaps: no overlap when already separated" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    const sg1 = try g.addSubgraph("SG1");
    const sg2 = try g.addSubgraph("SG2");
    try g.putNodes(&.{1}).inside(sg1);
    try g.putNodes(&.{2}).inside(sg2);

    // Already well-separated
    var node_x = [_]usize{ 0, 20 };
    const node_level = [_]usize{ 0, 0 };
    const node_widths = [_]usize{ 3, 3 };

    const extra = try fixSubgraphOverlaps(
        &g,
        &node_x,
        &node_level,
        &node_widths,
        2,
        allocator,
    );

    try std.testing.expectEqual(@as(usize, 0), extra);
    try std.testing.expectEqual(@as(usize, 0), node_x[0]);
    try std.testing.expectEqual(@as(usize, 20), node_x[1]);
}

test "fixSubgraphOverlaps: disjoint levels can overlap in x" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    const sg1 = try g.addSubgraph("SG1");
    const sg2 = try g.addSubgraph("SG2");
    try g.putNodes(&.{1}).inside(sg1);
    try g.putNodes(&.{2}).inside(sg2);

    // Same x but different levels — no overlap needed
    var node_x = [_]usize{ 0, 0 };
    const node_level = [_]usize{ 0, 5 };
    const node_widths = [_]usize{ 3, 3 };

    const extra = try fixSubgraphOverlaps(
        &g,
        &node_x,
        &node_level,
        &node_widths,
        2,
        allocator,
    );

    try std.testing.expectEqual(@as(usize, 0), extra);
}
