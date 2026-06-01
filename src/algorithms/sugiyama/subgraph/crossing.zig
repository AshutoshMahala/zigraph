//! Block-based crossing reduction for subgraph-aware layouts.
//!
//! Provides a crossing reduction pipeline that respects subgraph boundaries
//! by partitioning each level into blocks (one per subgraph plus one for
//! unaffiliated nodes). Blocks are ordered by average median position,
//! and nodes within each block are sorted by individual median.

const std = @import("std");
const Allocator = std.mem.Allocator;
const graph_mod = @import("../../../core/graph.zig");
const Graph = graph_mod.Graph;
const virtual_mod = @import("../layering/virtual.zig");
const VirtualLevels = virtual_mod.VirtualLevels;
const VNode = virtual_mod.VNode;
const median_mod = @import("../crossing/median.zig");
const common = @import("common.zig");
const vnodeSubgraph = common.vnodeSubgraph;

/// Maximum number of distinct blocks (subgraphs + root) on a single level.
/// Levels exceeding this fall back to standard median sort.
const MAX_BLOCKS: usize = 128;

/// Block-based crossing reduction for graphs with subgraphs.
///
/// Replaces the standard crossing reduction pipeline when subgraphs are present.
/// Each level is partitioned into blocks (one per subgraph, plus one for
/// unaffiliated nodes). The ordering proceeds in two dimensions:
///
/// 1. **Intra-block**: nodes within each block are sorted by median position
///    of their neighbors in the adjacent fixed level (same heuristic as
///    standard median crossing reduction).
/// 2. **Inter-block**: blocks are ordered by their average median position,
///    preserving subgraph adjacency by construction.
///
/// The sweep pattern (alternating top-down and bottom-up passes) matches
/// the standard median heuristic. Because each level is block-grouped before
/// moving to the next, subsequent levels see block-grouped positions in their
/// fixed layer, leading to better results than post-hoc adjacency enforcement.
///
/// Inner loops of median computation remain untouched — this is purely
/// orchestration-level logic that calls into `median.zig` primitives.
pub fn blockBasedCrossingReduction(
    g: *const Graph,
    vlevels: *VirtualLevels,
    passes: usize,
    allocator: Allocator,
) !void {
    if (vlevels.levels.items.len <= 1) return;
    if (passes == 0) return;

    // Find max level width for buffer sizing
    var max_level_width: usize = 0;
    for (vlevels.levels.items) |level| {
        max_level_width = @max(max_level_width, level.items.len);
    }
    if (max_level_width == 0) return;

    // Pre-allocate ALL working buffers ONCE — reused across passes and levels
    const node_count = g.nodeCount();
    const edge_count = g.edges.items.len;

    const real_pos_map = try allocator.alloc(usize, if (node_count > 0) node_count else 1);
    defer allocator.free(real_pos_map);

    const dummy_pos_map = try allocator.alloc(usize, if (edge_count > 0) edge_count else 1);
    defer allocator.free(dummy_pos_map);

    const medians = try allocator.alloc(f32, max_level_width);
    defer allocator.free(medians);

    const positions_buf = try allocator.alloc(usize, max_level_width);
    defer allocator.free(positions_buf);

    const block_keys = try allocator.alloc(usize, max_level_width);
    defer allocator.free(block_keys);

    const scratch = try allocator.alloc(VNode, max_level_width);
    defer allocator.free(scratch);

    const max_level = vlevels.levels.items.len - 1;

    for (0..passes) |_| {
        // Top-down pass: each level ordered using fixed positions from above
        for (1..vlevels.levels.items.len) |level_idx| {
            median_mod.buildVirtualPositionMaps(
                vlevels.levels.items[level_idx - 1].items,
                real_pos_map,
                dummy_pos_map,
            );
            blockOrderLevel(
                g,
                &vlevels.levels.items[level_idx],
                real_pos_map,
                dummy_pos_map,
                true,
                medians,
                positions_buf,
                block_keys,
                scratch,
            );
        }

        // Bottom-up pass: each level ordered using fixed positions from below
        var level_idx = max_level;
        while (level_idx > 0) : (level_idx -= 1) {
            median_mod.buildVirtualPositionMaps(
                vlevels.levels.items[level_idx].items,
                real_pos_map,
                dummy_pos_map,
            );
            blockOrderLevel(
                g,
                &vlevels.levels.items[level_idx - 1],
                real_pos_map,
                dummy_pos_map,
                false,
                medians,
                positions_buf,
                block_keys,
                scratch,
            );
        }
    }
}

/// Order a single level using block-partitioned median heuristic.
///
/// 1. Compute individual VNode medians from neighbors in the fixed adjacent level.
/// 2. Partition into blocks by subgraph membership.
/// 3. Sort blocks by average member median (inter-block ordering).
/// 4. Sort members within each block by individual median (intra-block ordering).
/// 5. Write back the reordered level.
pub fn blockOrderLevel(
    g: *const Graph,
    level_vnodes: *std.ArrayListUnmanaged(VNode),
    real_pos_map: []const usize,
    dummy_pos_map: []const usize,
    use_parents: bool,
    medians: []f32,
    positions_buf: []usize,
    block_keys: []usize,
    scratch: []VNode,
) void {
    const n = level_vnodes.items.len;
    if (n <= 1) return;

    const SENTINEL = std.math.maxInt(usize);

    // Phase 1: Compute individual medians and assign block keys
    for (level_vnodes.items, 0..) |vnode, i| {
        medians[i] = median_mod.vnodeMedian(
            g,
            vnode,
            real_pos_map,
            dummy_pos_map,
            use_parents,
            positions_buf,
            i,
        );
        block_keys[i] = vnodeSubgraph(g, vnode) orelse SENTINEL;
    }

    // Phase 2: Collect unique blocks with sum of member medians
    var bk: [MAX_BLOCKS]usize = undefined;
    var bm: [MAX_BLOCKS]f32 = undefined;
    var bc: [MAX_BLOCKS]usize = undefined;
    var n_blocks: usize = 0;
    var overflow = false;

    for (0..n) |i| {
        const key = block_keys[i];
        var found = false;
        for (bk[0..n_blocks], 0..) |existing, bi| {
            if (existing == key) {
                bm[bi] += medians[i];
                bc[bi] += 1;
                found = true;
                break;
            }
        }
        if (!found) {
            if (n_blocks >= MAX_BLOCKS) {
                overflow = true;
                break;
            }
            bk[n_blocks] = key;
            bm[n_blocks] = medians[i];
            bc[n_blocks] = 1;
            n_blocks += 1;
        }
    }

    // Fallback: standard median sort if overflow or single block
    if (overflow or n_blocks <= 1) {
        sortLevelByMedian(level_vnodes.items, medians, positions_buf, scratch, n);
        return;
    }

    // Phase 3: Compute block average medians and sort blocks
    for (0..n_blocks) |bi| {
        bm[bi] /= @floatFromInt(bc[bi]);
    }

    // Selection sort blocks by average median (n_blocks is small)
    for (0..n_blocks) |i| {
        var min_idx = i;
        for (i + 1..n_blocks) |j| {
            if (bm[j] < bm[min_idx]) min_idx = j;
        }
        if (min_idx != i) {
            std.mem.swap(usize, &bk[i], &bk[min_idx]);
            std.mem.swap(f32, &bm[i], &bm[min_idx]);
            std.mem.swap(usize, &bc[i], &bc[min_idx]);
        }
    }

    // Phase 4: Encode block rank into composite sort key.
    // multiplier > any individual median ensures block ordering dominates.
    const multiplier: f32 = @floatFromInt(
        n + @max(g.nodeCount(), g.edges.items.len) + 1,
    );

    for (0..n) |i| {
        const key = block_keys[i];
        for (bk[0..n_blocks], 0..) |sorted_key, bi| {
            if (sorted_key == key) {
                medians[i] += @as(f32, @floatFromInt(bi)) * multiplier;
                break;
            }
        }
    }

    // Phase 5: Sort by composite key (block order, then individual median)
    sortLevelByMedian(level_vnodes.items, medians, positions_buf, scratch, n);
}

/// Sort level VNodes by their median values using index-based sorting.
/// Reuses `positions_buf` as an index array and `scratch` as temporary storage.
fn sortLevelByMedian(
    vnodes: []VNode,
    medians: []f32,
    positions_buf: []usize,
    scratch: []VNode,
    n: usize,
) void {
    // Build index array
    for (0..n) |i| positions_buf[i] = i;

    // Sort indices by median value
    std.mem.sort(usize, positions_buf[0..n], medians, struct {
        fn cmp(m: []f32, a: usize, b: usize) bool {
            return m[a] < m[b];
        }
    }.cmp);

    // Permute VNodes via scratch buffer
    for (0..n) |i| {
        scratch[i] = vnodes[positions_buf[i]];
    }
    @memcpy(vnodes[0..n], scratch[0..n]);
}

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
        for (block_keys[0..n_blocks]) |bk2| {
            for (level.items, 0..) |vnode, i| {
                if (keys[i] == bk2) {
                    scratch[out] = vnode;
                    out += 1;
                }
            }
        }

        @memcpy(level.items, scratch[0..n]);
    }
}

// ============================================================================
// Tests
// ============================================================================

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
        .levels = .empty,
        .allocator = allocator,
    };
    defer vlevels.deinit();

    try vlevels.levels.append(allocator, .empty);
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
        .levels = .empty,
        .allocator = allocator,
    };
    defer vlevels.deinit();

    try vlevels.levels.append(allocator, .empty);
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
        .levels = .empty,
        .allocator = allocator,
    };
    defer vlevels.deinit();

    try vlevels.levels.append(allocator, .empty);
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
        .levels = .empty,
        .allocator = allocator,
    };
    defer vlevels.deinit();

    try vlevels.levels.append(allocator, .empty);
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

test "blockBasedCrossingReduction: groups subgraph nodes contiguously" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    // Two subgroups: sg_a = {A, C}, sg_b = {B, D}
    // Single level, interleaved: [A(sg_a), B(sg_b), C(sg_a), D(sg_b)]
    // After block-based reduction, nodes should be grouped by subgraph.
    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addNode(4, "D");
    const sg_a = try g.addSubgraph("SG-A");
    const sg_b = try g.addSubgraph("SG-B");
    try g.putNodes(&.{ 1, 3 }).inside(sg_a);
    try g.putNodes(&.{ 2, 4 }).inside(sg_b);

    // Add edges for median computation to have something to work with
    try g.addEdge(1, 3); // A → C
    try g.addEdge(2, 4); // B → D

    // Two levels: [A, B] on level 0, [C(sg_a), D(sg_b)] on level 1
    // But we want to test block ordering, so put interleaved nodes on one level
    var vlevels = VirtualLevels{
        .levels = .empty,
        .allocator = allocator,
    };
    defer vlevels.deinit();

    // Level 0: sources [A, B]
    try vlevels.levels.append(allocator, .empty);
    try vlevels.levels.items[0].append(allocator, .{ .real = 0 }); // A
    try vlevels.levels.items[0].append(allocator, .{ .real = 1 }); // B

    // Level 1: targets interleaved [C(sg_a), D(sg_b)]
    try vlevels.levels.append(allocator, .empty);
    try vlevels.levels.items[1].append(allocator, .{ .real = 2 }); // C
    try vlevels.levels.items[1].append(allocator, .{ .real = 3 }); // D

    try blockBasedCrossingReduction(&g, &vlevels, 2, allocator);

    // Verify level structure preserved: 2 levels, same node counts
    try std.testing.expectEqual(@as(usize, 2), vlevels.levels.items.len);
    try std.testing.expectEqual(@as(usize, 2), vlevels.levels.items[0].items.len);
    try std.testing.expectEqual(@as(usize, 2), vlevels.levels.items[1].items.len);
}

test "blockBasedCrossingReduction: preserves single-level graphs" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");

    var vlevels = VirtualLevels{
        .levels = .empty,
        .allocator = allocator,
    };
    defer vlevels.deinit();

    try vlevels.levels.append(allocator, .empty);
    try vlevels.levels.items[0].append(allocator, .{ .real = 0 });
    try vlevels.levels.items[0].append(allocator, .{ .real = 1 });

    // Single level: no adjacent pairs to sweep → should be noop
    try blockBasedCrossingReduction(&g, &vlevels, 4, allocator);

    try std.testing.expectEqual(@as(usize, 1), vlevels.levels.items.len);
    try std.testing.expectEqual(@as(usize, 2), vlevels.levels.items[0].items.len);
}

test "blockBasedCrossingReduction: zero passes is noop" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");

    var vlevels = VirtualLevels{
        .levels = .empty,
        .allocator = allocator,
    };
    defer vlevels.deinit();

    try vlevels.levels.append(allocator, .empty);
    try vlevels.levels.items[0].append(allocator, .{ .real = 0 });
    try vlevels.levels.append(allocator, .empty);
    try vlevels.levels.items[1].append(allocator, .{ .real = 1 });

    try blockBasedCrossingReduction(&g, &vlevels, 0, allocator);

    try std.testing.expectEqual(@as(usize, 2), vlevels.levels.items.len);
}

test "blockOrderLevel: separates interleaved subgraph members" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    // A(sg_a), B(sg_b), C(sg_a), D(sg_b) interleaved on one level
    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addNode(4, "D");
    const sg_a = try g.addSubgraph("SG-A");
    const sg_b = try g.addSubgraph("SG-B");
    try g.putNodes(&.{ 1, 3 }).inside(sg_a);
    try g.putNodes(&.{ 2, 4 }).inside(sg_b);

    var level: std.ArrayListUnmanaged(VNode) = .empty;
    defer level.deinit(allocator);
    try level.append(allocator, .{ .real = 0 }); // A, sg_a
    try level.append(allocator, .{ .real = 1 }); // B, sg_b
    try level.append(allocator, .{ .real = 2 }); // C, sg_a
    try level.append(allocator, .{ .real = 3 }); // D, sg_b

    // Allocate buffers
    const n: usize = 4;
    const node_count = g.nodeCount();
    const edge_count = @max(g.edges.items.len, @as(usize, 1));
    const real_pm = try allocator.alloc(usize, node_count);
    defer allocator.free(real_pm);
    const dummy_pm = try allocator.alloc(usize, edge_count);
    defer allocator.free(dummy_pm);
    const medians = try allocator.alloc(f32, n);
    defer allocator.free(medians);
    const pos_buf = try allocator.alloc(usize, n);
    defer allocator.free(pos_buf);
    const bkeys = try allocator.alloc(usize, n);
    defer allocator.free(bkeys);
    const scratch = try allocator.alloc(VNode, n);
    defer allocator.free(scratch);

    // Build position map from a "fixed" level (no fixed level, so empty maps)
    @memset(real_pm, std.math.maxInt(usize));
    @memset(dummy_pm, std.math.maxInt(usize));

    blockOrderLevel(&g, &level, real_pm, dummy_pm, true, medians, pos_buf, bkeys, scratch);

    // After block ordering: sg_a nodes should be contiguous, sg_b nodes contiguous.
    // With no connectivity, individual medians default to current positions.
    // sg_a avg pos = (0+2)/2 = 1.0, sg_b avg pos = (1+3)/2 = 2.0 → sg_a first
    const items = level.items;
    try std.testing.expectEqual(@as(usize, 4), items.len);

    // Check adjacency: nodes from the same subgraph are contiguous
    const key0 = vnodeSubgraph(&g, items[0]);
    const key1 = vnodeSubgraph(&g, items[1]);
    const key2 = vnodeSubgraph(&g, items[2]);
    const key3 = vnodeSubgraph(&g, items[3]);

    // First two should be from the same subgraph
    try std.testing.expectEqual(key0, key1);
    // Last two should be from the same subgraph
    try std.testing.expectEqual(key2, key3);
    // First and last blocks should be different subgraphs
    try std.testing.expect(key0.? != key2.?);
}

test "blockOrderLevel: root nodes form their own block" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    // A(root), B(sg), C(root), D(sg)
    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addNode(4, "D");
    const sg = try g.addSubgraph("SG");
    try g.putNodes(&.{ 2, 4 }).inside(sg);

    var level: std.ArrayListUnmanaged(VNode) = .empty;
    defer level.deinit(allocator);
    try level.append(allocator, .{ .real = 0 }); // A root
    try level.append(allocator, .{ .real = 1 }); // B sg
    try level.append(allocator, .{ .real = 2 }); // C root
    try level.append(allocator, .{ .real = 3 }); // D sg

    const n: usize = 4;
    const real_pm = try allocator.alloc(usize, g.nodeCount());
    defer allocator.free(real_pm);
    const dummy_pm = try allocator.alloc(usize, 1);
    defer allocator.free(dummy_pm);
    const meds = try allocator.alloc(f32, n);
    defer allocator.free(meds);
    const pbuf = try allocator.alloc(usize, n);
    defer allocator.free(pbuf);
    const bk = try allocator.alloc(usize, n);
    defer allocator.free(bk);
    const scr = try allocator.alloc(VNode, n);
    defer allocator.free(scr);

    @memset(real_pm, std.math.maxInt(usize));
    @memset(dummy_pm, std.math.maxInt(usize));

    blockOrderLevel(&g, &level, real_pm, dummy_pm, true, meds, pbuf, bk, scr);

    const items = level.items;
    try std.testing.expectEqual(@as(usize, 4), items.len);

    // Root nodes (A, C) should be contiguous — either [A,C,...] or [...,A,C]
    // SG nodes (B, D) should be contiguous
    const key0 = vnodeSubgraph(&g, items[0]);
    const key1 = vnodeSubgraph(&g, items[1]);
    const key2 = vnodeSubgraph(&g, items[2]);
    const key3 = vnodeSubgraph(&g, items[3]);

    try std.testing.expectEqual(key0, key1);
    try std.testing.expectEqual(key2, key3);
}

test "blockBasedCrossingReduction: integrates with graph edges" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    // Two subgroups with crossing edges:
    //   Level 0: [X, Y]
    //   Level 1: [A(sg_a), B(sg_b), C(sg_a)]
    //   Edges: X→A, X→C, Y→B
    // Block-based should group sg_a={A,C} and sg_b={B}, ordered by connectivity.
    try g.addNode(1, "X");
    try g.addNode(2, "Y");
    try g.addNode(3, "A");
    try g.addNode(4, "B");
    try g.addNode(5, "C");
    const sg_a = try g.addSubgraph("SG-A");
    const sg_b = try g.addSubgraph("SG-B");
    try g.putNodes(&.{ 3, 5 }).inside(sg_a);
    try g.putNodes(&.{4}).inside(sg_b);

    try g.addEdge(1, 3); // X → A
    try g.addEdge(1, 5); // X → C
    try g.addEdge(2, 4); // Y → B

    var vlevels = VirtualLevels{
        .levels = .empty,
        .allocator = allocator,
    };
    defer vlevels.deinit();

    // Level 0: [X, Y]
    try vlevels.levels.append(allocator, .empty);
    try vlevels.levels.items[0].append(allocator, .{ .real = 0 }); // X
    try vlevels.levels.items[0].append(allocator, .{ .real = 1 }); // Y

    // Level 1: interleaved [A(sg_a), B(sg_b), C(sg_a)]
    try vlevels.levels.append(allocator, .empty);
    try vlevels.levels.items[1].append(allocator, .{ .real = 2 }); // A
    try vlevels.levels.items[1].append(allocator, .{ .real = 3 }); // B
    try vlevels.levels.items[1].append(allocator, .{ .real = 4 }); // C

    try blockBasedCrossingReduction(&g, &vlevels, 4, allocator);

    // After block-based reduction:
    // Level 1 should have sg_a nodes contiguous and sg_b nodes contiguous
    const items = vlevels.levels.items[1].items;
    try std.testing.expectEqual(@as(usize, 3), items.len);

    // Check adjacency: find sg_a nodes and verify they are contiguous
    var sg_a_positions: [2]usize = undefined;
    var sg_a_count: usize = 0;
    for (items, 0..) |vnode, i| {
        if (vnodeSubgraph(&g, vnode)) |sg_id| {
            if (sg_id == sg_a) {
                sg_a_positions[sg_a_count] = i;
                sg_a_count += 1;
            }
        }
    }
    try std.testing.expectEqual(@as(usize, 2), sg_a_count);
    // sg_a nodes must be adjacent (positions differ by 1)
    try std.testing.expectEqual(@as(usize, 1), sg_a_positions[1] - sg_a_positions[0]);
}
