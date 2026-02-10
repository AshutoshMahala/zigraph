//! Attraction Force
//!
//! Spring-like attractive force between connected nodes.
//! Force magnitude: f = d / k where d = distance, k = ideal spring length.
//!
//! Used by: Fruchterman-Reingold, ForceAtlas2 (with linlog option).

const fp = @import("../fixed_point.zig");
const FP = fp.FP;
const Vec2 = fp.Vec2;

/// Apply attraction forces for all edges.
///
/// For each edge (u, v), computes spring force f = d × inv_k
/// and applies it symmetrically: u pulled toward v, v pulled toward u.
///
/// Arguments:
///   - positions: Node positions (read-only).
///   - forces: Force accumulators (modified in-place).
///   - edges: Iterator or slice yielding (source, target) pairs.
///   - inv_k: Pre-computed 1/k (or strength/k for weighted attraction).
pub fn applyEdges(
    positions: []const Vec2,
    forces: []Vec2,
    edges: anytype,
    inv_k: FP,
) void {
    for (edges) |edge| {
        const u = edge[0];
        const v = edge[1];
        applyBetween(positions, forces, u, v, inv_k);
    }
}

/// Apply attraction between a single pair of connected nodes.
///
/// Useful when iterating edges via adjacency lists (avoid double-counting).
pub fn applyBetween(
    positions: []const Vec2,
    forces: []Vec2,
    u: usize,
    v: usize,
    inv_k: FP,
) void {
    const delta = positions[u].subVec(positions[v]);
    const d = delta.length();
    if (d < 2) return; // Coincident — skip

    // f_att = d × inv_k (proportional to distance)
    const force_mag = fp.mul(d, inv_k);
    const force_vec = delta.normalizeScaled(force_mag);

    // Attraction: pull u toward v (subtract), pull v toward u (add)
    forces[u] = forces[u].subVec(force_vec);
    forces[v] = forces[v].addVec(force_vec);
}

/// Apply attraction with logarithmic scaling (LinLog mode).
///
/// Force magnitude: f = log(1 + d) × inv_k
/// This reduces the pull on long edges, useful for clustered layouts.
pub fn applyBetweenLinLog(
    positions: []const Vec2,
    forces: []Vec2,
    u: usize,
    v: usize,
    inv_k: FP,
) void {
    const delta = positions[u].subVec(positions[v]);
    const d = delta.length();
    if (d < 2) return;

    // f_att = log(1 + d) × inv_k
    // Approximate log(1 + d) in fixed-point: use d / (1 + d/2) ≈ 2d / (2 + d)
    const two = fp.fromInt(2);
    const log_approx = fp.div(fp.mul(two, d), fp.add(two, d));
    const force_mag = fp.mul(log_approx, inv_k);
    const force_vec = delta.normalizeScaled(force_mag);

    forces[u] = forces[u].subVec(force_vec);
    forces[v] = forces[v].addVec(force_vec);
}

// ============================================================================
// Tests
// ============================================================================

const std = @import("std");
const testing = std.testing;

test "attraction: connected nodes pulled together" {
    var positions = [_]Vec2{
        .{ .x = fp.ZERO, .y = fp.ZERO },
        .{ .x = fp.fromInt(100), .y = fp.ZERO },
    };
    var forces = [_]Vec2{ .{}, .{} };

    const k = fp.fromInt(20);
    const inv_k = fp.div(fp.ONE, k);

    applyBetween(&positions, &forces, 0, 1, inv_k);

    // Node 0 should be pulled right (toward node 1)
    try testing.expect(forces[0].x > 0);
    // Node 1 should be pulled left (toward node 0)
    try testing.expect(forces[1].x < 0);
}

test "attraction: coincident nodes skipped" {
    var positions = [_]Vec2{
        .{ .x = fp.ZERO, .y = fp.ZERO },
        .{ .x = fp.ZERO, .y = fp.ZERO },
    };
    var forces = [_]Vec2{ .{}, .{} };

    applyBetween(&positions, &forces, 0, 1, fp.fromInt(1));

    try testing.expectEqual(@as(FP, 0), forces[0].x);
    try testing.expectEqual(@as(FP, 0), forces[1].x);
}
