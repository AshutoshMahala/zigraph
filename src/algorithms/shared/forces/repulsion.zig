//! Repulsion Force
//!
//! Coulomb-like repulsive force between all node pairs.
//! Force magnitude: f = k² / d where d = distance between nodes.
//!
//! Used by: Fruchterman-Reingold, ForceAtlas2 (with different scaling).

const fp = @import("../fixed_point.zig");
const FP = fp.FP;
const Vec2 = fp.Vec2;
const Quadtree = @import("../quadtree.zig").Quadtree;

/// Apply O(N²) pairwise repulsion to all nodes.
///
/// For each pair (i, j), computes repulsive force f = k_squared / d
/// and applies it symmetrically: i pushed away from j, j pushed away from i.
///
/// Arguments:
///   - positions: Node positions (read-only).
///   - forces: Force accumulators (modified in-place).
///   - k_squared: Repulsion strength constant (typically k² × strength multiplier).
pub fn applyPairwise(
    positions: []const Vec2,
    forces: []Vec2,
    k_squared: FP,
) void {
    const n = positions.len;
    for (0..n) |i| {
        for ((i + 1)..n) |j| {
            const delta = positions[i].subVec(positions[j]);
            const d = delta.length();
            if (d < 2) continue; // Coincident — skip

            // f_rep = k² / d
            const force_mag = fp.div(k_squared, d);
            const force_vec = delta.normalizeScaled(force_mag);

            forces[i] = forces[i].addVec(force_vec);
            forces[j] = forces[j].subVec(force_vec);
        }
    }
}

/// Apply O(N log N) Barnes-Hut approximated repulsion.
///
/// Uses a quadtree to approximate distant clusters as single masses.
/// The theta parameter controls accuracy (0 = exact, higher = faster).
///
/// Arguments:
///   - positions: Node positions (read-only).
///   - forces: Force accumulators (modified in-place).
///   - quadtree: Pre-built quadtree for the current positions.
///   - k_squared: Repulsion strength constant.
///   - theta: Barnes-Hut opening angle (Q16.16).
pub fn applyBarnesHut(
    positions: []const Vec2,
    forces: []Vec2,
    quadtree: *const Quadtree,
    k_squared: FP,
    theta: FP,
) void {
    for (0..positions.len) |i| {
        forces[i] = forces[i].addVec(quadtree.computeForce(positions[i], k_squared, theta));
    }
}

// ============================================================================
// Tests
// ============================================================================

const std = @import("std");
const testing = std.testing;

test "pairwise repulsion: two nodes pushed apart" {
    var positions = [_]Vec2{
        .{ .x = fp.ZERO, .y = fp.ZERO },
        .{ .x = fp.fromInt(10), .y = fp.ZERO },
    };
    var forces = [_]Vec2{ .{}, .{} };

    const k = fp.fromInt(20);
    const k_squared = fp.mul(k, k); // 400 in Q16.16

    applyPairwise(&positions, &forces, k_squared);

    // Node 0 should be pushed left (negative x), node 1 pushed right
    try testing.expect(forces[0].x < 0);
    try testing.expect(forces[1].x > 0);
    try testing.expectEqual(@as(FP, 0), forces[0].y);
    try testing.expectEqual(@as(FP, 0), forces[1].y);
}

test "pairwise repulsion: coincident nodes skipped" {
    var positions = [_]Vec2{
        .{ .x = fp.ZERO, .y = fp.ZERO },
        .{ .x = fp.ZERO, .y = fp.ZERO }, // Same position
    };
    var forces = [_]Vec2{ .{}, .{} };

    applyPairwise(&positions, &forces, fp.fromInt(400));

    // No force applied (would be divide-by-zero otherwise)
    try testing.expectEqual(@as(FP, 0), forces[0].x);
    try testing.expectEqual(@as(FP, 0), forces[1].x);
}
