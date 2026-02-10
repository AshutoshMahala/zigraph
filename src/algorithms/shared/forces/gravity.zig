//! Gravity Force
//!
//! Pulls all nodes toward a center point to prevent drift.
//! Used by ForceAtlas2 to keep disconnected components together.
//!
//! Fruchterman-Reingold typically doesn't use gravity, but it's provided
//! for future algorithms and custom configurations.

const fp = @import("../fixed_point.zig");
const FP = fp.FP;
const Vec2 = fp.Vec2;

/// Apply gravity toward a center point.
///
/// Each node is pulled toward `center` with force magnitude = `strength × d`.
///
/// Arguments:
///   - positions: Node positions (read-only).
///   - forces: Force accumulators (modified in-place).
///   - center: The center point to pull toward (e.g., centroid of all nodes).
///   - strength: Gravity strength multiplier (Q16.16).
pub fn applyToCenter(
    positions: []const Vec2,
    forces: []Vec2,
    center: Vec2,
    strength: FP,
) void {
    for (0..positions.len) |i| {
        const delta = center.subVec(positions[i]); // Vector from node to center
        const d = delta.length();
        if (d < 2) continue;

        const force_mag = fp.mul(strength, d);
        const force_vec = delta.normalizeScaled(force_mag);

        forces[i] = forces[i].addVec(force_vec);
    }
}

/// Apply strong gravity (ForceAtlas2 style).
///
/// Force is constant regardless of distance: f = strength.
/// This prevents nodes from flying off to infinity.
pub fn applyStrongGravity(
    positions: []const Vec2,
    forces: []Vec2,
    center: Vec2,
    strength: FP,
) void {
    for (0..positions.len) |i| {
        const delta = center.subVec(positions[i]);
        const d = delta.length();
        if (d < 2) continue;

        // Force magnitude is constant (strong gravity)
        const force_vec = delta.normalizeScaled(strength);
        forces[i] = forces[i].addVec(force_vec);
    }
}

/// Compute the centroid (center of mass) of all positions.
///
/// Returns the average position of all nodes.
pub fn computeCentroid(positions: []const Vec2) Vec2 {
    if (positions.len == 0) return Vec2{};

    var sum_x: i64 = 0;
    var sum_y: i64 = 0;

    for (positions) |pos| {
        sum_x += pos.x;
        sum_y += pos.y;
    }

    const n: i64 = @intCast(positions.len);
    return Vec2{
        .x = @intCast(@divTrunc(sum_x, n)),
        .y = @intCast(@divTrunc(sum_y, n)),
    };
}

// ============================================================================
// Tests
// ============================================================================

const std = @import("std");
const testing = std.testing;

test "gravity: nodes pulled toward center" {
    var positions = [_]Vec2{
        .{ .x = fp.fromInt(-50), .y = fp.ZERO },
        .{ .x = fp.fromInt(50), .y = fp.ZERO },
    };
    var forces = [_]Vec2{ .{}, .{} };

    const center = Vec2{ .x = fp.ZERO, .y = fp.ZERO };
    const strength = fp.div(fp.ONE, fp.fromInt(10)); // 0.1

    applyToCenter(&positions, &forces, center, strength);

    // Node 0 (left) should be pulled right
    try testing.expect(forces[0].x > 0);
    // Node 1 (right) should be pulled left
    try testing.expect(forces[1].x < 0);
}

test "centroid: computed correctly" {
    const positions = [_]Vec2{
        .{ .x = fp.fromInt(-10), .y = fp.fromInt(-10) },
        .{ .x = fp.fromInt(10), .y = fp.fromInt(10) },
    };

    const center = computeCentroid(&positions);

    try testing.expectEqual(@as(FP, 0), center.x);
    try testing.expectEqual(@as(FP, 0), center.y);
}

test "centroid: single node" {
    const positions = [_]Vec2{
        .{ .x = fp.fromInt(42), .y = fp.fromInt(17) },
    };

    const center = computeCentroid(&positions);

    try testing.expectEqual(fp.fromInt(42), center.x);
    try testing.expectEqual(fp.fromInt(17), center.y);
}
