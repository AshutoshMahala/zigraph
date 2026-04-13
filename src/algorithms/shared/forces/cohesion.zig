//! Subgraph Cohesion Force
//!
//! Pulls nodes in the same subgraph toward their group centroid.
//! This creates visual clustering — nodes in the same subgraph
//! naturally group together, making subgraph boundaries meaningful.
//!
//! The cohesion force is applied per-subgraph:
//! 1. Compute the centroid of all nodes in this subgraph.
//! 2. Pull each member toward the centroid with configurable strength.
//!
//! Nesting is handled by applying cohesion at each level independently
//! (leaf subgraphs first, then parents), so nested subgraphs cluster
//! within their parent's cluster.
//!
//! Used by: Fruchterman-Reingold (when graph has subgraphs).

const std = @import("std");
const fp = @import("../fixed_point.zig");
const FP = fp.FP;
const Vec2 = fp.Vec2;
const Allocator = std.mem.Allocator;
const graph_mod = @import("../../../core/graph.zig");
const Graph = graph_mod.Graph;

/// Pre-computed subgraph membership index for efficient per-subgraph iteration.
///
/// Maps each subgraph to both its direct node members and its transitive
/// (all-descendant) node members. Built once before the force loop and
/// reused every iteration.
///
/// `members[i]`     — nodes placed directly in subgraph i.
/// `transitive[i]`  — nodes in subgraph i or any of its descendants.
///
/// Transitive members are needed for parent subgraphs that contain only
/// child subgraphs (no direct nodes). Without them, cohesion and separation
/// forces would skip those parents entirely.
pub const SubgraphIndex = struct {
    /// For each subgraph (by subgraph array index): slice of direct node indices.
    members: [][]const usize,
    /// For each subgraph: slice of all descendant node indices (including direct).
    transitive: [][]const usize,
    /// Backing storage for direct member indices.
    storage: []usize,
    /// Backing storage for transitive member indices.
    trans_storage: []usize,
    /// Number of subgraphs.
    sg_count: usize,
    allocator: Allocator,

    pub fn build(g: *const Graph, allocator: Allocator) !SubgraphIndex {
        const sg_count = g.subgraphCount();
        if (sg_count == 0) {
            return SubgraphIndex{
                .members = &.{},
                .transitive = &.{},
                .storage = &.{},
                .trans_storage = &.{},
                .sg_count = 0,
                .allocator = allocator,
            };
        }

        const n = g.nodeCount();

        // ── Direct members ──────────────────────────────────────────────

        // Count members per subgraph
        const counts = try allocator.alloc(usize, sg_count);
        defer allocator.free(counts);
        @memset(counts, 0);

        for (0..n) |node_idx| {
            const node = g.nodeAt(node_idx) orelse continue;
            const sg_id = g.nodeSubgraph(node.id) orelse continue;
            const sg_idx = g.subgraph_id_to_index.get(sg_id) orelse continue;
            counts[sg_idx] += 1;
        }

        // Allocate storage
        var total: usize = 0;
        for (counts) |c| total += c;

        const storage = try allocator.alloc(usize, total);
        errdefer allocator.free(storage);

        // Build slices
        const members = try allocator.alloc([]const usize, sg_count);
        errdefer allocator.free(members);

        // Compute offsets
        const offsets = try allocator.alloc(usize, sg_count);
        defer allocator.free(offsets);
        var off: usize = 0;
        for (0..sg_count) |i| {
            offsets[i] = off;
            off += counts[i];
        }

        // Fill storage
        const cursors = try allocator.alloc(usize, sg_count);
        defer allocator.free(cursors);
        @memcpy(cursors, offsets);

        for (0..n) |node_idx| {
            const node = g.nodeAt(node_idx) orelse continue;
            const sg_id = g.nodeSubgraph(node.id) orelse continue;
            const sg_idx = g.subgraph_id_to_index.get(sg_id) orelse continue;
            storage[cursors[sg_idx]] = node_idx;
            cursors[sg_idx] += 1;
        }

        // Wire slices
        for (0..sg_count) |i| {
            members[i] = storage[offsets[i]..][0..counts[i]];
        }

        // ── Transitive members ──────────────────────────────────────────
        // For each node, walk up its subgraph ancestry chain and count it
        // as a transitive member of every ancestor subgraph.

        const trans_counts = try allocator.alloc(usize, sg_count);
        defer allocator.free(trans_counts);
        @memset(trans_counts, 0);

        const sg_items = g.subgraphs.items;

        for (0..n) |node_idx| {
            const node = g.nodeAt(node_idx) orelse continue;
            var sg_id_opt = g.nodeSubgraph(node.id);
            while (sg_id_opt) |sg_id| {
                const sg_idx = g.subgraph_id_to_index.get(sg_id) orelse break;
                trans_counts[sg_idx] += 1;
                if (sg_idx < sg_items.len) {
                    sg_id_opt = sg_items[sg_idx].parent_id;
                } else break;
            }
        }

        var trans_total: usize = 0;
        for (trans_counts[0..sg_count]) |c| trans_total += c;

        const trans_storage = try allocator.alloc(usize, trans_total);
        errdefer allocator.free(trans_storage);

        const transitive = try allocator.alloc([]const usize, sg_count);
        errdefer allocator.free(transitive);

        const trans_offsets = try allocator.alloc(usize, sg_count);
        defer allocator.free(trans_offsets);
        var toff: usize = 0;
        for (0..sg_count) |i| {
            trans_offsets[i] = toff;
            toff += trans_counts[i];
        }

        const trans_cursors = try allocator.alloc(usize, sg_count);
        defer allocator.free(trans_cursors);
        @memcpy(trans_cursors, trans_offsets);

        for (0..n) |node_idx| {
            const node = g.nodeAt(node_idx) orelse continue;
            var sg_id_opt = g.nodeSubgraph(node.id);
            while (sg_id_opt) |sg_id| {
                const sg_idx = g.subgraph_id_to_index.get(sg_id) orelse break;
                trans_storage[trans_cursors[sg_idx]] = node_idx;
                trans_cursors[sg_idx] += 1;
                if (sg_idx < sg_items.len) {
                    sg_id_opt = sg_items[sg_idx].parent_id;
                } else break;
            }
        }

        for (0..sg_count) |i| {
            transitive[i] = trans_storage[trans_offsets[i]..][0..trans_counts[i]];
        }

        return SubgraphIndex{
            .members = members,
            .transitive = transitive,
            .storage = storage,
            .trans_storage = trans_storage,
            .sg_count = sg_count,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SubgraphIndex) void {
        if (self.members.len > 0) self.allocator.free(self.members);
        if (self.storage.len > 0) self.allocator.free(self.storage);
        if (self.transitive.len > 0) self.allocator.free(self.transitive);
        if (self.trans_storage.len > 0) self.allocator.free(self.trans_storage);
        self.* = undefined;
    }
};

/// Apply subgraph cohesion forces.
///
/// For each subgraph, computes the centroid of its transitive members
/// (all descendant nodes), then pulls each member toward that centroid.
///
/// Using transitive members ensures parent subgraphs that contain only
/// child subgraphs (no direct nodes) still produce cohesion — pulling
/// all descendant nodes toward the parent's center.
///
/// The force magnitude is: `strength × distance_to_centroid`.
/// This is similar to gravity but per-subgraph rather than global.
///
/// Arguments:
///   - positions: Node positions (read-only for centroid; written via forces).
///   - forces: Force accumulators (modified in-place).
///   - index: Pre-built SubgraphIndex mapping subgraphs → member nodes.
///   - strength: Cohesion strength multiplier (Q16.16). Typical: 0.3–1.0.
pub fn applyCohesion(
    positions: []const Vec2,
    forces: []Vec2,
    index: *const SubgraphIndex,
    strength: FP,
) void {
    for (0..index.sg_count) |sg_idx| {
        const member_indices = index.transitive[sg_idx];
        if (member_indices.len <= 1) continue;

        // Compute centroid of this subgraph's members
        var sum_x: i64 = 0;
        var sum_y: i64 = 0;
        for (member_indices) |node_idx| {
            sum_x += positions[node_idx].x;
            sum_y += positions[node_idx].y;
        }
        const n_members: i64 = @intCast(member_indices.len);
        const centroid = Vec2{
            .x = @intCast(@divTrunc(sum_x, n_members)),
            .y = @intCast(@divTrunc(sum_y, n_members)),
        };

        // Pull each member toward centroid
        for (member_indices) |node_idx| {
            const delta = centroid.subVec(positions[node_idx]);
            const d = delta.length();
            if (d < 2) continue;

            const force_mag = fp.mul(strength, d);
            const force_vec = delta.normalizeScaled(force_mag);
            forces[node_idx] = forces[node_idx].addVec(force_vec);
        }
    }
}

/// Apply inter-cluster separation forces.
///
/// For each pair of subgraphs that share the same parent (or are both
/// root-level), computes a Coulomb-like repulsion between their centroids
/// and distributes the force evenly to all members.
///
/// This is the complement of `applyCohesion`: cohesion pulls members *in*,
/// separation pushes clusters *apart*.
///
/// Force magnitude per cluster pair: `strength × k² / d`
/// where d = centroid-to-centroid distance.
///
/// Arguments:
///   - positions: Node positions (read-only for centroids; written via forces).
///   - forces: Force accumulators (modified in-place).
///   - index: Pre-built SubgraphIndex mapping subgraphs → member nodes.
///   - graph: Graph reference for subgraph parent lookups.
///   - strength: Separation strength multiplier (Q16.16). Typical: 0.5–2.0.
///   - k_squared: Ideal spring length squared (same as repulsion k²).
pub fn applySeparation(
    positions: []const Vec2,
    forces: []Vec2,
    index: *const SubgraphIndex,
    graph: *const Graph,
    strength: FP,
    k_squared: FP,
) void {
    if (index.sg_count < 2) return;

    // Step 1: Compute centroids using transitive members (all descendants)
    var centroids: [MAX_SUBGRAPHS]Vec2 = undefined;
    var valid: [MAX_SUBGRAPHS]bool = undefined;
    var member_counts: [MAX_SUBGRAPHS]usize = undefined;
    const sg_count = @min(index.sg_count, MAX_SUBGRAPHS);

    for (0..sg_count) |sg_idx| {
        const members = index.transitive[sg_idx];
        if (members.len == 0) {
            valid[sg_idx] = false;
            member_counts[sg_idx] = 0;
            continue;
        }
        var sum_x: i64 = 0;
        var sum_y: i64 = 0;
        for (members) |node_idx| {
            sum_x += positions[node_idx].x;
            sum_y += positions[node_idx].y;
        }
        const n_members: i64 = @intCast(members.len);
        centroids[sg_idx] = Vec2{
            .x = @intCast(@divTrunc(sum_x, n_members)),
            .y = @intCast(@divTrunc(sum_y, n_members)),
        };
        valid[sg_idx] = true;
        member_counts[sg_idx] = members.len;
    }

    // Step 2: Get parent_id for each subgraph
    var parent_ids: [MAX_SUBGRAPHS]?usize = undefined;
    const sg_items = graph.subgraphs.items;
    for (0..sg_count) |sg_idx| {
        if (sg_idx < sg_items.len) {
            parent_ids[sg_idx] = sg_items[sg_idx].parent_id;
        } else {
            parent_ids[sg_idx] = null;
        }
    }

    // Step 3: For each pair of sibling subgraphs, apply centroid repulsion
    for (0..sg_count) |i| {
        if (!valid[i]) continue;
        for ((i + 1)..sg_count) |j| {
            if (!valid[j]) continue;

            // Only repel siblings (same parent)
            const same_parent = (parent_ids[i] == null and parent_ids[j] == null) or
                (parent_ids[i] != null and parent_ids[j] != null and
                    parent_ids[i].? == parent_ids[j].?);
            if (!same_parent) continue;

            const delta = centroids[i].subVec(centroids[j]);
            const d = delta.length();
            if (d < 2) continue;

            // Coulomb-like: f = strength * k² / d
            const base_force = fp.div(k_squared, d);
            const force_mag = fp.mul(strength, base_force);
            const force_vec = delta.normalizeScaled(force_mag);

            // Distribute evenly to transitive members of each subgraph
            const members_i = index.transitive[i];
            const members_j = index.transitive[j];
            const n_i: FP = fp.fromInt(@intCast(members_i.len));
            const n_j: FP = fp.fromInt(@intCast(members_j.len));
            const per_i = Vec2{
                .x = fp.div(force_vec.x, n_i),
                .y = fp.div(force_vec.y, n_i),
            };
            const per_j = Vec2{
                .x = fp.div(force_vec.x, n_j),
                .y = fp.div(force_vec.y, n_j),
            };

            // Push cluster i away from j (add force)
            for (members_i) |node_idx| {
                forces[node_idx] = forces[node_idx].addVec(per_i);
            }
            // Push cluster j away from i (subtract force)
            for (members_j) |node_idx| {
                forces[node_idx] = forces[node_idx].subVec(per_j);
            }
        }
    }
}

/// Maximum number of subgraphs supported for separation.
/// Stack-allocated to avoid per-iteration heap allocation.
const MAX_SUBGRAPHS: usize = 256;

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "cohesion: members pulled toward group centroid" {
    const allocator = testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C"); // not in subgraph

    const sg = try g.addSubgraph("cluster");
    try g.putNodes(&.{ 1, 2 }).inside(sg);

    var index = try SubgraphIndex.build(&g, allocator);
    defer index.deinit();

    try testing.expectEqual(@as(usize, 1), index.sg_count);
    try testing.expectEqual(@as(usize, 2), index.members[0].len);

    // Place A far left, B far right, C somewhere
    var positions = [_]Vec2{
        .{ .x = fp.fromInt(-50), .y = fp.ZERO }, // A
        .{ .x = fp.fromInt(50), .y = fp.ZERO }, // B
        .{ .x = fp.fromInt(100), .y = fp.fromInt(100) }, // C
    };
    var forces_arr = [_]Vec2{ .{}, .{}, .{} };

    const strength = fp.div(fp.ONE, fp.fromInt(2)); // 0.5

    applyCohesion(&positions, &forces_arr, &index, strength);

    // A (left) should be pulled right (toward centroid at x=0)
    try testing.expect(forces_arr[0].x > 0);
    // B (right) should be pulled left (toward centroid at x=0)
    try testing.expect(forces_arr[1].x < 0);
    // C is not in any subgraph — should have zero force
    try testing.expectEqual(@as(FP, 0), forces_arr[2].x);
    try testing.expectEqual(@as(FP, 0), forces_arr[2].y);
}

test "cohesion: single-member subgraph is skipped" {
    const allocator = testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    const sg = try g.addSubgraph("single");
    try g.putNodes(&.{1}).inside(sg);

    var index = try SubgraphIndex.build(&g, allocator);
    defer index.deinit();

    var positions = [_]Vec2{
        .{ .x = fp.fromInt(10), .y = fp.fromInt(20) },
    };
    var forces_arr = [_]Vec2{.{}};

    applyCohesion(&positions, &forces_arr, &index, fp.ONE);

    // Single member — no cohesion force
    try testing.expectEqual(@as(FP, 0), forces_arr[0].x);
    try testing.expectEqual(@as(FP, 0), forces_arr[0].y);
}

test "cohesion: empty graph produces empty index" {
    const allocator = testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    var index = try SubgraphIndex.build(&g, allocator);
    defer index.deinit();

    try testing.expectEqual(@as(usize, 0), index.sg_count);
}

test "cohesion: nested subgraphs index independently" {
    const allocator = testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");

    const outer = try g.addSubgraph("outer");
    const inner = try g.addSubgraph("inner");
    try g.putSubgraphs(&.{inner}).inside(outer);
    try g.putNodes(&.{1}).inside(outer);
    try g.putNodes(&.{ 2, 3 }).inside(inner);

    var index = try SubgraphIndex.build(&g, allocator);
    defer index.deinit();

    try testing.expectEqual(@as(usize, 2), index.sg_count);

    // outer should have 1 direct member (node 1)
    // inner should have 2 direct members (nodes 2, 3)
    var outer_count: usize = 0;
    var inner_count: usize = 0;
    for (0..index.sg_count) |i| {
        if (index.members[i].len == 1) outer_count += 1;
        if (index.members[i].len == 2) inner_count += 1;
    }
    try testing.expectEqual(@as(usize, 1), outer_count);
    try testing.expectEqual(@as(usize, 1), inner_count);

    // Transitive: outer should have 3 (node 1 + inner's 2, 3)
    // inner should have 2 (same as direct — leaf subgraph)
    var outer_trans: usize = 0;
    var inner_trans: usize = 0;
    for (0..index.sg_count) |i| {
        if (index.transitive[i].len == 3) outer_trans += 1;
        if (index.transitive[i].len == 2) inner_trans += 1;
    }
    try testing.expectEqual(@as(usize, 1), outer_trans);
    try testing.expectEqual(@as(usize, 1), inner_trans);
}
