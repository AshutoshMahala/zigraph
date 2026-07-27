//! Subgraph compaction pass.
//!
//! Ported from ascii-dag's `refine_x_positions()` + `compact_subgraphs()`.
//! These two functions run in alternation (3 rounds) after initial x-positioning
//! but BEFORE `fixSubgraphOverlaps()`.
//!
//! - **refineXPositions**: Shifts nodes toward the median x of their connected
//!   neighbors on adjacent levels, reducing zigzag edges (coordinate assignment).
//! - **compactSubgraphs**: Pulls outlier subgraph members toward the subgraph
//!   centroid, cascading neighbor pushes when blocked.

const std = @import("std");
const Allocator = std.mem.Allocator;
const graph_mod = @import("../../../core/graph.zig");
const Graph = graph_mod.Graph;

/// Minimum gap between same-subgraph neighbors on a level.
const MIN_GAP: usize = 3;
/// Gap between nodes of different subgraphs (H_PAD + SIBLING + H_PAD).
const SG_GAP: usize = 5;
/// Number of down/up sweep iterations for refineXPositions.
const REFINE_ITERATIONS: usize = 8;
/// Subgraph horizontal padding (for left margin).
const SUBGRAPH_H_PAD: usize = 2;

/// Run 3 rounds of refine + compact (matching ascii-dag pipeline).
pub fn refineAndCompact(
    g: *const Graph,
    node_x: []usize,
    node_level: []const usize,
    node_widths: []const usize,
    node_count: usize,
    allocator: Allocator,
) !void {
    if (node_count == 0) return;

    const node_sg = try buildNodeSg(g, node_count, allocator);
    defer allocator.free(node_sg);

    const ml = maxLevel(node_level, node_count);

    // Build level lists once (re-sort in place when needed)
    const level_lists = try buildLevelLists(node_level, node_count, ml, allocator);
    defer freeLevelLists(level_lists, allocator);

    // Build node-to-level-position lookup (updated via re-sort)
    const node_to_pos = try allocator.alloc(usize, node_count);
    defer allocator.free(node_to_pos);

    // Scratch buffer for median computation — pre-allocate for max degree
    var max_degree: usize = 0;
    for (0..node_count) |ni| {
        const deg = g.frozenChildren(ni).len + g.frozenParents(ni).len;
        max_degree = @max(max_degree, deg);
    }
    var median_buf = std.ArrayListUnmanaged(usize).empty;
    defer median_buf.deinit(allocator);
    try median_buf.ensureTotalCapacity(allocator, max_degree);

    // Group sibling subgraphs together on each level before refine/compact.
    // Without this, crossing minimization may interleave nodes from different
    // parent subgraphs on the same level, creating huge gaps between siblings.
    try groupSiblingSubgraphs(g, node_x, node_widths, node_count, node_sg, level_lists, allocator);

    const compact_rounds = 3;
    for (0..compact_rounds) |_| {
        try refineXPositions(g, node_x, node_level, node_widths, node_count, node_sg, ml, level_lists, node_to_pos, &median_buf, allocator);
        try compactSubgraphs(g, node_x, node_level, node_widths, node_count, node_sg, ml, level_lists, node_to_pos, allocator);
    }
}

// ═══════════════════════════════════════════════════════════════════════
// Per-level sorted node lists
// ═══════════════════════════════════════════════════════════════════════

fn buildLevelLists(
    node_level: []const usize,
    node_count: usize,
    ml: usize,
    allocator: Allocator,
) ![]std.ArrayListUnmanaged(usize) {
    const lists = try allocator.alloc(std.ArrayListUnmanaged(usize), ml + 1);
    for (lists) |*ln| ln.* = .empty;

    for (0..node_count) |ni| {
        const lvl = node_level[ni];
        if (lvl <= ml) {
            try lists[lvl].append(allocator, ni);
        }
    }
    return lists;
}

fn freeLevelLists(lists: []std.ArrayListUnmanaged(usize), allocator: Allocator) void {
    for (lists) |*ln| ln.deinit(allocator);
    allocator.free(lists);
}

/// Re-sort all level lists by current x positions and rebuild node_to_pos.
fn resortLevels(
    level_lists: []std.ArrayListUnmanaged(usize),
    node_x: []const usize,
    node_to_pos: []usize,
) void {
    for (level_lists) |*ln| {
        std.mem.sort(usize, ln.items, node_x, struct {
            fn cmp(x: []const usize, a: usize, b: usize) bool {
                return x[a] < x[b];
            }
        }.cmp);
        for (ln.items, 0..) |ni, pos| {
            node_to_pos[ni] = pos;
        }
    }
}

fn maxLevel(node_level: []const usize, node_count: usize) usize {
    var ml: usize = 0;
    for (node_level[0..node_count]) |l| ml = @max(ml, l);
    return ml;
}

// ═══════════════════════════════════════════════════════════════════════
// Node → subgraph mapping
// ═══════════════════════════════════════════════════════════════════════

fn buildNodeSg(g: *const Graph, node_count: usize, allocator: Allocator) ![]?usize {
    const node_sg = try allocator.alloc(?usize, node_count);
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
    return node_sg;
}

// ═══════════════════════════════════════════════════════════════════════
// Gap helpers
// ═══════════════════════════════════════════════════════════════════════

fn gapBetween(node_sg: []const ?usize, a: usize, b: usize) usize {
    const a_sg = node_sg[a];
    const b_sg = node_sg[b];
    if (a_sg != null and b_sg != null) {
        if (a_sg.? != b_sg.?) return SG_GAP;
    }
    return MIN_GAP;
}

fn leftMargin(node_sg: []const ?usize, node_idx: usize) usize {
    return if (node_sg[node_idx] != null) SUBGRAPH_H_PAD else 0;
}

// ═══════════════════════════════════════════════════════════════════════
// Sibling subgraph grouping
// ═══════════════════════════════════════════════════════════════════════

/// Reorder nodes within each level so that nodes belonging to the same
/// top-level subgraph ancestor are contiguous AND ordered consistently
/// across all levels (by global centroid).  Without this, crossing
/// minimization may interleave nodes from different parent subgraphs
/// (e.g. eu-west-1 nodes between two us-east-1 children).
fn groupSiblingSubgraphs(
    g: *const Graph,
    node_x: []usize,
    node_widths: []const usize,
    node_count: usize,
    node_sg: []const ?usize,
    level_lists: []std.ArrayListUnmanaged(usize),
    allocator: Allocator,
) !void {
    const sg_count = g.subgraphCount();
    if (sg_count < 2) return;

    // 1. Topmost ancestor SG index for each SG.
    const top_anc = try allocator.alloc(usize, sg_count);
    defer allocator.free(top_anc);
    for (0..sg_count) |si| {
        var cur: usize = si;
        while (true) {
            const sg = g.subgraphs.items[cur];
            if (sg.parent_id) |pid| {
                if (g.subgraph_id_to_index.get(pid)) |pi| {
                    cur = pi;
                    continue;
                }
            }
            break;
        }
        top_anc[si] = cur;
    }

    // 2. Group ID per node:
    //    SG node  → topmost ancestor sg_idx
    //    non-SG   → sg_count + node_idx  (unique, won't collide)
    const node_group = try allocator.alloc(usize, node_count);
    defer allocator.free(node_group);
    for (0..node_count) |ni| {
        node_group[ni] = if (node_sg[ni]) |si| top_anc[si] else sg_count + ni;
    }

    // 3. Compute group centroid for ordering.
    //    Small bridge groups (few members, many external connections) use
    //    NEIGHBOR centroid — placing them where their edges want them.
    //    Large self-contained groups keep their OWN centroid.

    // 3a. Own centroid.
    var own_sum = std.AutoHashMapUnmanaged(usize, u64).empty;
    defer own_sum.deinit(allocator);
    var own_cnt = std.AutoHashMapUnmanaged(usize, u64).empty;
    defer own_cnt.deinit(allocator);
    for (0..node_count) |ni| {
        const grp = node_group[ni];
        const cx: u64 = @intCast(node_x[ni] + node_widths[ni] / 2);
        const s = try own_sum.getOrPut(allocator, grp);
        if (!s.found_existing) s.value_ptr.* = 0;
        s.value_ptr.* += cx;
        const c = try own_cnt.getOrPut(allocator, grp);
        if (!c.found_existing) c.value_ptr.* = 0;
        c.value_ptr.* += 1;
    }

    // 3b. Neighbor centroid: sum center-x of external neighbors per group.
    var nbr_sum = std.AutoHashMapUnmanaged(usize, u64).empty;
    defer nbr_sum.deinit(allocator);
    var nbr_cnt = std.AutoHashMapUnmanaged(usize, u64).empty;
    defer nbr_cnt.deinit(allocator);
    for (0..node_count) |ni| {
        const grp = node_group[ni];
        // Children in different groups
        for (g.frozenChildren(ni)) |child| {
            if (child >= node_count) continue;
            if (node_group[child] != grp) {
                const cx: u64 = @intCast(node_x[child] + node_widths[child] / 2);
                const s = try nbr_sum.getOrPut(allocator, grp);
                if (!s.found_existing) s.value_ptr.* = 0;
                s.value_ptr.* += cx;
                const c = try nbr_cnt.getOrPut(allocator, grp);
                if (!c.found_existing) c.value_ptr.* = 0;
                c.value_ptr.* += 1;
            }
        }
        // Parents in different groups
        for (g.frozenParents(ni)) |parent| {
            if (parent >= node_count) continue;
            if (node_group[parent] != grp) {
                const cx: u64 = @intCast(node_x[parent] + node_widths[parent] / 2);
                const s = try nbr_sum.getOrPut(allocator, grp);
                if (!s.found_existing) s.value_ptr.* = 0;
                s.value_ptr.* += cx;
                const c = try nbr_cnt.getOrPut(allocator, grp);
                if (!c.found_existing) c.value_ptr.* = 0;
                c.value_ptr.* += 1;
            }
        }
    }

    // 3c. Final centroid: use neighbor centroid for small bridge groups
    //     (few members with external connections), own for large groups.
    var grp_centroid = std.AutoHashMapUnmanaged(usize, u64).empty;
    defer grp_centroid.deinit(allocator);
    {
        var it = own_sum.iterator();
        while (it.next()) |kv| {
            const grp = kv.key_ptr.*;
            const oc = own_cnt.get(grp) orelse 1;
            const own_cx = kv.value_ptr.* / oc;
            const nc = nbr_cnt.get(grp) orelse 0;
            if (nc > 0 and (oc <= 3 or nc > oc)) {
                // Small bridge group (≤3 members) or group with more
                // external than internal connections: place where
                // cross-subgraph edges want it, reducing zig-zag.
                const ns = nbr_sum.get(grp) orelse 0;
                try grp_centroid.put(allocator, grp, ns / nc);
            } else {
                // Large or self-contained group: use own centroid.
                try grp_centroid.put(allocator, grp, own_cx);
            }
        }
    }

    // 4. Per-level reorder by (global_centroid, original_position).
    const SortEntry = struct {
        node_idx: usize,
        centroid: u64,
        orig_pos: usize,
    };
    var sort_buf = std.ArrayListUnmanaged(SortEntry).empty;
    defer sort_buf.deinit(allocator);

    for (level_lists) |*ln| {
        if (ln.items.len < 2) continue;

        // Sort by current x to establish left-to-right order.
        std.mem.sort(usize, ln.items, node_x, struct {
            fn cmp(x: []const usize, a: usize, b: usize) bool {
                return x[a] < x[b];
            }
        }.cmp);

        // Build sort entries with global centroid.
        sort_buf.clearRetainingCapacity();
        try sort_buf.ensureTotalCapacity(allocator, ln.items.len);
        for (ln.items, 0..) |ni, pos| {
            sort_buf.appendAssumeCapacity(.{
                .node_idx = ni,
                .centroid = grp_centroid.get(node_group[ni]) orelse 0,
                .orig_pos = pos,
            });
        }

        // Check if re-ordering would change anything.
        var needs = false;
        for (1..sort_buf.items.len) |i| {
            const a = sort_buf.items[i - 1];
            const b = sort_buf.items[i];
            if (a.centroid > b.centroid) {
                needs = true;
                break;
            }
        }
        if (!needs) continue;

        // Sort: primary = global centroid, secondary = original position.
        std.mem.sort(SortEntry, sort_buf.items, {}, struct {
            fn cmp(_: void, a: SortEntry, b: SortEntry) bool {
                if (a.centroid != b.centroid) return a.centroid < b.centroid;
                return a.orig_pos < b.orig_pos;
            }
        }.cmp);

        // Write back + position inheritance.
        // Save original sorted x values (one per slot).
        const n = ln.items.len;
        const orig_xs = try allocator.alloc(usize, n);
        defer allocator.free(orig_xs);
        for (0..n) |i| {
            orig_xs[i] = node_x[ln.items[i]]; // ln is still original sorted order
        }
        // Write new order.
        for (sort_buf.items, 0..) |entry, i| ln.items[i] = entry.node_idx;
        // Assign inherited positions.
        for (ln.items, 0..) |ni, i| {
            node_x[ni] = orig_xs[i];
        }

        // Forward pass: enforce minimum gaps (left → right).
        for (ln.items, 0..) |ni, pos| {
            const min_x: usize = if (pos == 0)
                leftMargin(node_sg, ni)
            else blk: {
                const prev = ln.items[pos - 1];
                const gap = gapBetween(node_sg, prev, ni);
                break :blk node_x[prev] + node_widths[prev] + gap;
            };
            node_x[ni] = @max(node_x[ni], min_x);
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════
// refineXPositions — median placement
// ═══════════════════════════════════════════════════════════════════════

fn refineXPositions(
    g: *const Graph,
    node_x: []usize,
    node_level: []const usize,
    node_widths: []const usize,
    node_count: usize,
    node_sg: []const ?usize,
    ml: usize,
    level_lists: []std.ArrayListUnmanaged(usize),
    node_to_pos: []usize,
    median_buf: *std.ArrayListUnmanaged(usize),
    allocator: Allocator,
) !void {
    _ = allocator;
    if (node_count == 0 or ml == 0) return;

    for (0..REFINE_ITERATIONS) |_| {
        // Re-sort levels by current x positions
        resortLevels(level_lists, node_x, node_to_pos);

        // Down sweep: align with parents (level - 1)
        for (1..ml + 1) |level| {
            const ln = level_lists[level].items;
            const adj_level = level - 1;

            // Pass 1: right-to-left
            {
                var pos_i = ln.len;
                while (pos_i > 0) {
                    pos_i -= 1;
                    if (connectedMedianX(g, ln[pos_i], adj_level, node_level, node_x, node_widths, median_buf)) |target_cx| {
                        shiftNodeToTarget(node_x, node_widths, node_sg, ln, pos_i, target_cx);
                    }
                }
            }
            // Pass 2: left-to-right
            for (0..ln.len) |pos_i| {
                if (connectedMedianX(g, ln[pos_i], adj_level, node_level, node_x, node_widths, median_buf)) |target_cx| {
                    shiftNodeToTarget(node_x, node_widths, node_sg, ln, pos_i, target_cx);
                }
            }
        }

        // Up sweep: align with children (level + 1)
        {
            var level = ml;
            while (level > 0) {
                level -= 1;
                const ln = level_lists[level].items;
                const adj_level = level + 1;

                // Pass 1: right-to-left
                {
                    var pos_i = ln.len;
                    while (pos_i > 0) {
                        pos_i -= 1;
                        if (connectedMedianX(g, ln[pos_i], adj_level, node_level, node_x, node_widths, median_buf)) |target_cx| {
                            shiftNodeToTarget(node_x, node_widths, node_sg, ln, pos_i, target_cx);
                        }
                    }
                }
                // Pass 2: left-to-right
                for (0..ln.len) |pos_i| {
                    if (connectedMedianX(g, ln[pos_i], adj_level, node_level, node_x, node_widths, median_buf)) |target_cx| {
                        shiftNodeToTarget(node_x, node_widths, node_sg, ln, pos_i, target_cx);
                    }
                }
            }
        }
    }
}

/// Compute median center-x of connected neighbors on a specific adjacent level.
/// O(degree) per call — no linear scan of level nodes.
fn connectedMedianX(
    g: *const Graph,
    node_idx: usize,
    adj_level: usize,
    node_level: []const usize,
    node_x: []const usize,
    node_widths: []const usize,
    buf: *std.ArrayListUnmanaged(usize),
) ?usize {
    buf.clearRetainingCapacity();

    // Children
    for (g.frozenChildren(node_idx)) |child_idx| {
        if (child_idx < node_level.len and node_level[child_idx] == adj_level) {
            buf.appendAssumeCapacity(node_x[child_idx] + node_widths[child_idx] / 2);
        }
    }
    // Parents
    for (g.frozenParents(node_idx)) |parent_idx| {
        if (parent_idx < node_level.len and node_level[parent_idx] == adj_level) {
            buf.appendAssumeCapacity(node_x[parent_idx] + node_widths[parent_idx] / 2);
        }
    }

    if (buf.items.len == 0) return null;

    std.mem.sort(usize, buf.items, {}, std.sort.asc(usize));

    const n = buf.items.len;
    if (n % 2 == 1) {
        return buf.items[n / 2];
    } else {
        return (buf.items[n / 2 - 1] + buf.items[n / 2]) / 2;
    }
}

fn shiftNodeToTarget(
    node_x: []usize,
    node_widths: []const usize,
    node_sg: []const ?usize,
    level_sorted: []const usize,
    pos: usize,
    target_center: usize,
) void {
    const ni = level_sorted[pos];
    const my_w = node_widths[ni];
    const target_x = if (target_center >= my_w / 2) target_center - my_w / 2 else 0;

    const min_x: usize = if (pos == 0)
        leftMargin(node_sg, ni)
    else blk: {
        const prev = level_sorted[pos - 1];
        const gap = gapBetween(node_sg, prev, ni);
        break :blk node_x[prev] + node_widths[prev] + gap;
    };

    const max_x: usize = if (pos + 1 < level_sorted.len) blk: {
        const next = level_sorted[pos + 1];
        const gap = gapBetween(node_sg, ni, next);
        break :blk if (node_x[next] >= my_w + gap) node_x[next] - my_w - gap else 0;
    } else std.math.maxInt(usize);

    node_x[ni] = @min(max_x, @max(min_x, target_x));
}

// ═══════════════════════════════════════════════════════════════════════
// compactSubgraphs — centroid pulling
// ═══════════════════════════════════════════════════════════════════════

fn compactSubgraphs(
    g: *const Graph,
    node_x: []usize,
    node_level: []const usize,
    node_widths: []const usize,
    node_count: usize,
    node_sg: []const ?usize,
    ml: usize,
    level_lists: []std.ArrayListUnmanaged(usize),
    node_to_pos: []usize,
    allocator: Allocator,
) !void {
    const sg_count = g.subgraphCount();
    if (sg_count == 0) return;

    // Re-sort levels once before compaction
    resortLevels(level_lists, node_x, node_to_pos);

    // Scratch for members and distances
    var members = std.ArrayListUnmanaged(usize).empty;
    defer members.deinit(allocator);

    const DistEntry = struct { node_idx: usize, dist: usize };
    var by_distance = std.ArrayListUnmanaged(DistEntry).empty;
    defer by_distance.deinit(allocator);

    _ = ml;

    for (0..sg_count) |sg_idx| {
        members.clearRetainingCapacity();

        for (0..node_count) |ni| {
            if (node_sg[ni]) |s| {
                if (s == sg_idx) try members.append(allocator, ni);
            }
        }

        if (members.items.len <= 1) continue;

        // Compute centroid
        var sum: usize = 0;
        for (members.items) |ni| {
            sum += node_x[ni] + node_widths[ni] / 2;
        }
        const centroid = sum / members.items.len;

        // Sort by distance from centroid (farthest first)
        by_distance.clearRetainingCapacity();
        for (members.items) |ni| {
            const cx = node_x[ni] + node_widths[ni] / 2;
            const dist = if (cx >= centroid) cx - centroid else centroid - cx;
            try by_distance.append(allocator, .{ .node_idx = ni, .dist = dist });
        }

        std.mem.sort(DistEntry, by_distance.items, {}, struct {
            fn cmp(_: void, a: DistEntry, b: DistEntry) bool {
                return a.dist > b.dist;
            }
        }.cmp);

        for (by_distance.items) |entry| {
            if (entry.dist < SG_GAP) continue;

            const ni = entry.node_idx;
            const my_w = node_widths[ni];
            const my_cx = node_x[ni] + my_w / 2;
            const target_x = if (centroid >= my_w / 2) centroid - my_w / 2 else 0;

            const level = node_level[ni];
            const ln = level_lists[level].items;
            const pos = node_to_pos[ni];

            // Validate pos
            if (pos >= ln.len or ln[pos] != ni) continue;

            // Compute simple constraints
            const min_x: usize = if (pos == 0)
                leftMargin(node_sg, ni)
            else blk: {
                const prev = ln[pos - 1];
                const gap = gapBetween(node_sg, prev, ni);
                break :blk node_x[prev] + node_widths[prev] + gap;
            };

            const max_x: usize = if (pos + 1 < ln.len) blk: {
                const next = ln[pos + 1];
                const gap = gapBetween(node_sg, ni, next);
                break :blk if (node_x[next] >= my_w + gap) node_x[next] - my_w - gap else 0;
            } else std.math.maxInt(usize);

            const simple_x = @min(max_x, @max(min_x, target_x));

            const simple_ok = (my_cx > centroid and simple_x < node_x[ni]) or
                (my_cx < centroid and simple_x > node_x[ni]);

            if (simple_ok) {
                node_x[ni] = simple_x;
            } else if (my_cx > centroid and target_x < min_x) {
                const push_target = (node_x[ni] + target_x) / 2;
                cascadePush(node_x, node_widths, node_sg, ln, pos, push_target, .left);
            } else if (my_cx < centroid and target_x > max_x) {
                const push_target = (node_x[ni] + target_x) / 2;
                cascadePush(node_x, node_widths, node_sg, ln, pos, push_target, .right);
            }
        }
    }
}

const Direction = enum { left, right };

fn cascadePush(
    node_x: []usize,
    node_widths: []const usize,
    node_sg: []const ?usize,
    level_sorted: []const usize,
    pos: usize,
    target_x: usize,
    direction: Direction,
) void {
    const ni = level_sorted[pos];
    node_x[ni] = target_x;

    switch (direction) {
        .left => {
            var i = pos;
            while (i > 0) {
                const curr = level_sorted[i];
                const prev = level_sorted[i - 1];
                const gap = gapBetween(node_sg, prev, curr);
                const needed = if (node_x[curr] >= node_widths[prev] + gap)
                    node_x[curr] - node_widths[prev] - gap
                else
                    0;
                if (node_x[prev] <= needed) break;
                const margin = if (i - 1 == 0) leftMargin(node_sg, prev) else 0;
                node_x[prev] = @max(needed, margin);
                i -= 1;
            }
        },
        .right => {
            var i = pos;
            while (i + 1 < level_sorted.len) {
                const curr = level_sorted[i];
                const next = level_sorted[i + 1];
                const gap = gapBetween(node_sg, curr, next);
                const needed = node_x[curr] + node_widths[curr] + gap;
                if (node_x[next] >= needed) break;
                node_x[next] = needed;
                i += 1;
            }
        },
    }
}

test "compact: basic refine and compact" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(0, "A");
    try g.addNode(1, "B");
    try g.addDiEdge(0, 1);

    const sg1 = try g.addSubgraph("SG1");
    try g.putNodes(&.{0}).inside(sg1);
    const sg2 = try g.addSubgraph("SG2");
    try g.putNodes(&.{1}).inside(sg2);

    var node_x = [_]usize{ 0, 20 };
    const node_level = [_]usize{ 0, 1 };
    const node_widths = [_]usize{ 3, 3 };

    _ = try g.ensureFrozen();
    try refineAndCompact(&g, &node_x, &node_level, &node_widths, 2, allocator);
}
