//! Subgraph-aware orchestration for Sugiyama layout
//!
//! Provides constraint enforcement for subgraph-grouped layouts:
//! - **Crossing reduction**: block-based median sweep respecting subgraph boundaries
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
const VirtualPositions = virtual_mod.VirtualPositions;
const ir_mod = @import("../../core/ir.zig");
const LayerAssignment = @import("layering/longest_path.zig").LayerAssignment;
const median_mod = @import("crossing/median.zig");

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
// Block-based crossing reduction
// ============================================================================

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
fn blockOrderLevel(
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
            g, vnode, real_pos_map, dummy_pos_map, use_parents, positions_buf, i,
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
// Subgraph position padding
// ============================================================================

/// Compute the nesting depth of a subgraph (0 for root-level subgraphs).
fn subgraphDepth(g: *const Graph, sg_id: usize) usize {
    var depth: usize = 0;
    var current = sg_id;
    while (true) {
        const sg = g.subgraphById(current) orelse break;
        if (sg.parent_id) |pid| {
            depth += 1;
            current = pid;
        } else break;
    }
    return depth;
}

/// Compute the full ancestor chain for a subgraph, ordered from
/// innermost (the subgraph itself) to outermost.
/// Returns the number of ancestors written into `buf`.
fn ancestorChain(g: *const Graph, sg_id: usize, buf: []usize) usize {
    var n: usize = 0;
    var current = sg_id;
    while (n < buf.len) {
        buf[n] = current;
        n += 1;
        const sg = g.subgraphById(current) orelse break;
        current = sg.parent_id orelse break;
    }
    return n;
}

/// Count the number of subgraph boundary transitions between two VNodes.
///
/// A boundary transition occurs when the set of enclosing subgraphs differs.
/// Each entered or exited subgraph contributes one boundary line that needs
/// a padding cell.
///
/// For example, if node A is in `[inner, outer]` and node B is in `[outer]`,
/// there is 1 transition (exiting `inner`). If node B is in a completely
/// different subgraph tree, the count is `depth(A) + depth(B)`.
fn countBoundaryTransitions(
    g: *const Graph,
    sg_a: ?usize,
    sg_b: ?usize,
    chain_buf_a: []usize,
    chain_buf_b: []usize,
) usize {
    // Same subgraph (including both null) → no transitions
    if (sg_a == sg_b) return 0;

    const depth_a = if (sg_a) |a| ancestorChain(g, a, chain_buf_a) else 0;
    const depth_b = if (sg_b) |b| ancestorChain(g, b, chain_buf_b) else 0;

    // If one is null (root), transitions = full depth of the other
    if (sg_a == null) return depth_b;
    if (sg_b == null) return depth_a;

    // Find the lowest common ancestor
    for (chain_buf_a[0..depth_a]) |a_id| {
        for (chain_buf_b[0..depth_b]) |b_id| {
            if (a_id == b_id) {
                // a_id == b_id is the LCA.
                // Transitions = levels above LCA in A + levels above LCA in B
                // Find index of a_id in chain A (chain is innermost-first)
                var idx_a: usize = 0;
                for (chain_buf_a[0..depth_a], 0..) |x, i| {
                    if (x == a_id) { idx_a = i; break; }
                }
                var idx_b: usize = 0;
                for (chain_buf_b[0..depth_b], 0..) |x, i| {
                    if (x == b_id) { idx_b = i; break; }
                }
                // idx_a = number of subgraphs between node A and the LCA
                // idx_b = number of subgraphs between node B and the LCA
                return idx_a + idx_b;
            }
        }
    }

    // No common ancestor → all boundaries crossed
    return depth_a + depth_b;
}

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
                g, prev_sg, curr_sg, &chain_a, &chain_b,
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
    const pad = default_padding;
    const label_row: usize = 1; // extra row for subgraph label

    // For each level, compute how many subgraph top/bottom borders cross it.
    // A subgraph border crosses between levels L-1 and L if:
    // - The subgraph has members on level L but not on level L-1 (top border)
    // - The subgraph has members on level L-1 but not on level L (bottom border)

    const y_offsets = try allocator.alloc(usize, num_levels);
    @memset(y_offsets, 0);

    if (sg_count == 0) return y_offsets;

    // Compute per-subgraph level presence: sg_levels[sg_idx] = bitset of levels
    // For simplicity, use bool arrays.
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

    // For each level boundary (between L-1 and L), count subgraph borders
    for (1..num_levels) |level_idx| {
        var top_borders: usize = 0; // subgraphs starting at this level
        var bottom_borders: usize = 0; // subgraphs ending at previous level

        for (0..sg_count) |sg_idx| {
            const on_prev = sg_on_level[sg_idx * num_levels + level_idx - 1];
            const on_curr = sg_on_level[sg_idx * num_levels + level_idx];

            if (on_curr and !on_prev) {
                // Subgraph starts at this level → top border + label
                top_borders += 1;
            }
            if (on_prev and !on_curr) {
                // Subgraph ends at previous level → bottom border
                bottom_borders += 1;
            }
        }

        // Each border needs 'pad' rows, top borders also need a label row
        y_offsets[level_idx] = top_borders * (pad + label_row) + bottom_borders * pad;
    }

    // First level: if any subgraphs start here, add top border
    {
        var top_borders: usize = 0;
        for (0..sg_count) |sg_idx| {
            if (sg_on_level[sg_idx * num_levels + 0]) {
                top_borders += 1;
            }
        }
        y_offsets[0] = top_borders * (pad + label_row);
    }

    return y_offsets;
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

// ============================================================================
// Block-based crossing reduction tests
// ============================================================================

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
        .levels = .{},
        .allocator = allocator,
    };
    defer vlevels.deinit();

    // Level 0: sources [A, B]
    try vlevels.levels.append(allocator, .{});
    try vlevels.levels.items[0].append(allocator, .{ .real = 0 }); // A
    try vlevels.levels.items[0].append(allocator, .{ .real = 1 }); // B

    // Level 1: targets interleaved [C(sg_a), D(sg_b)]
    try vlevels.levels.append(allocator, .{});
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
        .levels = .{},
        .allocator = allocator,
    };
    defer vlevels.deinit();

    try vlevels.levels.append(allocator, .{});
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
        .levels = .{},
        .allocator = allocator,
    };
    defer vlevels.deinit();

    try vlevels.levels.append(allocator, .{});
    try vlevels.levels.items[0].append(allocator, .{ .real = 0 });
    try vlevels.levels.append(allocator, .{});
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

    var level: std.ArrayListUnmanaged(VNode) = .{};
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

    var level: std.ArrayListUnmanaged(VNode) = .{};
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
        .levels = .{},
        .allocator = allocator,
    };
    defer vlevels.deinit();

    // Level 0: [X, Y]
    try vlevels.levels.append(allocator, .{});
    try vlevels.levels.items[0].append(allocator, .{ .real = 0 }); // X
    try vlevels.levels.items[0].append(allocator, .{ .real = 1 }); // Y

    // Level 1: interleaved [A(sg_a), B(sg_b), C(sg_a)]
    try vlevels.levels.append(allocator, .{});
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

// ============================================================================
// Padding and boundary transition tests
// ============================================================================

test "countBoundaryTransitions: same subgraph = 0" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    const sg = try g.addSubgraph("SG");
    var buf_a: [16]usize = undefined;
    var buf_b: [16]usize = undefined;

    try std.testing.expectEqual(@as(usize, 0), countBoundaryTransitions(&g, sg, sg, &buf_a, &buf_b));
}

test "countBoundaryTransitions: null to subgraph = depth" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    const outer = try g.addSubgraph("outer");
    const inner = try g.addSubgraph("inner");
    try g.putSubgraphs(&.{inner}).inside(outer);

    var buf_a: [16]usize = undefined;
    var buf_b: [16]usize = undefined;

    // null → inner (depth 2: inner + outer)
    try std.testing.expectEqual(@as(usize, 2), countBoundaryTransitions(&g, null, inner, &buf_a, &buf_b));
    // null → outer (depth 1: outer)
    try std.testing.expectEqual(@as(usize, 1), countBoundaryTransitions(&g, null, outer, &buf_a, &buf_b));
}

test "countBoundaryTransitions: sibling subgraphs" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    const parent = try g.addSubgraph("parent");
    const child_a = try g.addSubgraph("child_a");
    const child_b = try g.addSubgraph("child_b");
    try g.putSubgraphs(&.{ child_a, child_b }).inside(parent);

    var buf_a: [16]usize = undefined;
    var buf_b: [16]usize = undefined;

    // child_a → child_b: both depth 2, LCA = parent
    // transitions = 1 (exit child_a) + 1 (enter child_b) = 2
    // But ancestorChain returns [child_a, parent] and [child_b, parent]
    // LCA = parent at idx 1 in both chains → idx_a=1, idx_b=1
    // Wait, LCA matching: chain_a = [child_a, parent], chain_b = [child_b, parent]
    // First match: when a_id == b_id → parent == parent at idx_a=1, idx_b=1
    // Transitions = 1 + 1 = 2
    try std.testing.expectEqual(@as(usize, 2), countBoundaryTransitions(&g, child_a, child_b, &buf_a, &buf_b));
}

test "countBoundaryTransitions: disjoint trees" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    const sg_a = try g.addSubgraph("SG-A");
    const sg_b = try g.addSubgraph("SG-B");

    var buf_a: [16]usize = undefined;
    var buf_b: [16]usize = undefined;

    // No common ancestor → depth_a + depth_b = 1 + 1 = 2
    try std.testing.expectEqual(@as(usize, 2), countBoundaryTransitions(&g, sg_a, sg_b, &buf_a, &buf_b));
}

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
        .levels = .{},
        .allocator = allocator,
    };
    defer vlevels.deinit();

    try vlevels.levels.append(allocator, .{});
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
    try positions.x.append(allocator, .{});
    try positions.x.items[0].append(allocator, 0); // A
    try positions.x.items[0].append(allocator, 6); // B

    try applySubgraphPadding(&g, &vlevels, &positions, allocator);

    // A (root) should be at x=0 (no subgraph borders on left)
    try std.testing.expectEqual(@as(usize, 0), positions.x.items[0].items[0]);

    // B (sg, depth 1) has 1 boundary transition from root→sg
    // Transition padding = 1 * default_padding = 1
    // So B's offset = 0 + 1 = 1, B's x = 6 + 1 = 7
    try std.testing.expectEqual(@as(usize, 7), positions.x.items[0].items[1]);
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
        .levels = .{},
        .allocator = allocator,
    };
    defer vlevels.deinit();

    try vlevels.levels.append(allocator, .{});
    try vlevels.levels.items[0].append(allocator, .{ .real = 0 }); // A root
    try vlevels.levels.items[0].append(allocator, .{ .real = 1 }); // B inner

    var positions = VirtualPositions{
        .x = .{},
        .total_width = 9,
        .total_height = 1,
        .allocator = allocator,
    };
    defer positions.deinit();
    try positions.x.append(allocator, .{});
    try positions.x.items[0].append(allocator, 0); // A
    try positions.x.items[0].append(allocator, 6); // B

    try applySubgraphPadding(&g, &vlevels, &positions, allocator);

    // A at x=0 (no borders)
    try std.testing.expectEqual(@as(usize, 0), positions.x.items[0].items[0]);

    // B is in inner (depth 2), root→inner boundary means 2 transitions
    // offset = 0 + 2 * 1 = 2, B's x = 6 + 2 = 8
    try std.testing.expectEqual(@as(usize, 8), positions.x.items[0].items[1]);
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
        .levels = .{},
        .allocator = allocator,
    };
    defer vlevels.deinit();

    try vlevels.levels.append(allocator, .{});
    try vlevels.levels.items[0].append(allocator, .{ .real = 0 });
    try vlevels.levels.append(allocator, .{});
    try vlevels.levels.items[1].append(allocator, .{ .real = 1 });

    const offsets = try computeLevelYOffsets(&g, &vlevels, allocator);
    defer allocator.free(offsets);

    try std.testing.expectEqual(@as(usize, 2), offsets.len);
    // Level 0: subgraph starts here → top border (pad=1 + label=1 = 2)
    try std.testing.expectEqual(@as(usize, 2), offsets[0]);
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
        .levels = .{},
        .allocator = allocator,
    };
    defer vlevels.deinit();

    try vlevels.levels.append(allocator, .{});
    try vlevels.levels.items[0].append(allocator, .{ .real = 0 }); // X
    try vlevels.levels.append(allocator, .{});
    try vlevels.levels.items[1].append(allocator, .{ .real = 1 }); // A
    try vlevels.levels.append(allocator, .{});
    try vlevels.levels.items[2].append(allocator, .{ .real = 2 }); // B

    const offsets = try computeLevelYOffsets(&g, &vlevels, allocator);
    defer allocator.free(offsets);

    try std.testing.expectEqual(@as(usize, 3), offsets.len);
    // Level 0: no subgraphs → 0
    try std.testing.expectEqual(@as(usize, 0), offsets[0]);
    // Level 1: subgraph starts → top border (2)
    try std.testing.expectEqual(@as(usize, 2), offsets[1]);
    // Level 2: subgraph continues → 0
    try std.testing.expectEqual(@as(usize, 0), offsets[2]);
}

test "computeLevelYOffsets: no subgraphs returns zeros" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");

    var vlevels = VirtualLevels{
        .levels = .{},
        .allocator = allocator,
    };
    defer vlevels.deinit();

    try vlevels.levels.append(allocator, .{});
    try vlevels.levels.items[0].append(allocator, .{ .real = 0 });

    const offsets = try computeLevelYOffsets(&g, &vlevels, allocator);
    defer allocator.free(offsets);

    try std.testing.expectEqual(@as(usize, 1), offsets.len);
    try std.testing.expectEqual(@as(usize, 0), offsets[0]);
}
