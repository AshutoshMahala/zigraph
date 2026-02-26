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
/// Maps each subgraph to the list of node indices it contains (direct members only).
/// Built once before the force loop and reused every iteration.
pub const SubgraphIndex = struct {
    /// For each subgraph (by subgraph array index): slice of node indices.
    members: [][]const usize,
    /// Backing storage for all member indices.
    storage: []usize,
    /// Number of subgraphs.
    sg_count: usize,
    allocator: Allocator,

    pub fn build(g: *const Graph, allocator: Allocator) !SubgraphIndex {
        const sg_count = g.subgraphCount();
        if (sg_count == 0) {
            return SubgraphIndex{
                .members = &.{},
                .storage = &.{},
                .sg_count = 0,
                .allocator = allocator,
            };
        }

        const n = g.nodeCount();

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

        return SubgraphIndex{
            .members = members,
            .storage = storage,
            .sg_count = sg_count,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SubgraphIndex) void {
        if (self.members.len > 0) self.allocator.free(self.members);
        if (self.storage.len > 0) self.allocator.free(self.storage);
        self.* = undefined;
    }
};

/// Apply subgraph cohesion forces.
///
/// For each subgraph, computes the centroid of its direct members,
/// then pulls each member toward that centroid.
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
        const member_indices = index.members[sg_idx];
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
}
