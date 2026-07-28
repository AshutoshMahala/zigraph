//! Gravity Force (SoA gather kernels)
//!
//! Pulls all nodes toward a center point to prevent drift.
//! Used by ForceAtlas2 to keep disconnected components together.
//!
//! Fruchterman-Reingold typically doesn't use gravity, but it's provided
//! for future algorithms and custom configurations.
//!
//! Both kernels are gather-only and range-parameterized: node `i` reads
//! frozen positions and a precomputed center, writing only its own cell.
//! `computeCentroid` is the serial reduction that produces the center —
//! run it once per iteration before fanning out ranges.

const std = @import("std");
const fp = @import("../fixed_point.zig");
const FP = fp.FP;
const Vec2 = fp.Vec2;
const common = @import("../common.zig");
const Range = common.Range;

/// Accumulate gravity toward a center point for nodes in `range`.
///
/// Each node is pulled toward `center` with force magnitude = `strength × d`.
pub fn accumulateToCenter(
    xs: []const FP,
    ys: []const FP,
    fxs: []FP,
    fys: []FP,
    center: Vec2,
    strength: FP,
    range: Range,
) void {
    common.assertShape(xs, ys, fxs, fys, range);
    for (range.begin..range.end) |i| {
        const delta = Vec2{ .x = fp.sub(center.x, xs[i]), .y = fp.sub(center.y, ys[i]) };
        const d = delta.length();
        if (d < 2) continue;

        const force_mag = fp.mul(strength, d);
        const force_vec = delta.normalizeScaledWithLength(force_mag, d);

        fxs[i] = fp.accumAdd(fxs[i], force_vec.x);
        fys[i] = fp.accumAdd(fys[i], force_vec.y);
    }
}

/// Accumulate strong gravity (ForceAtlas2 style) for nodes in `range`.
///
/// Force is constant regardless of distance: f = strength.
/// This prevents nodes from flying off to infinity.
pub fn accumulateStrongGravity(
    xs: []const FP,
    ys: []const FP,
    fxs: []FP,
    fys: []FP,
    center: Vec2,
    strength: FP,
    range: Range,
) void {
    common.assertShape(xs, ys, fxs, fys, range);
    for (range.begin..range.end) |i| {
        const delta = Vec2{ .x = fp.sub(center.x, xs[i]), .y = fp.sub(center.y, ys[i]) };
        const d = delta.length();
        if (d < 2) continue;

        // Force magnitude is constant (strong gravity)
        const force_vec = delta.normalizeScaledWithLength(strength, d);
        fxs[i] = fp.accumAdd(fxs[i], force_vec.x);
        fys[i] = fp.accumAdd(fys[i], force_vec.y);
    }
}

/// Compute the centroid (center of mass) of all positions.
///
/// Serial reduction — run once per iteration, before range fan-out.
pub fn computeCentroid(xs: []const FP, ys: []const FP) Vec2 {
    if (xs.len == 0) return Vec2{};

    var sum_x: i64 = 0;
    var sum_y: i64 = 0;

    for (xs, ys) |x, y| {
        sum_x += x;
        sum_y += y;
    }

    const n: i64 = @intCast(xs.len);
    return Vec2{
        .x = @intCast(@divTrunc(sum_x, n)),
        .y = @intCast(@divTrunc(sum_y, n)),
    };
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "gravity: nodes pulled toward center" {
    const xs = [_]FP{ fp.fromInt(-50), fp.fromInt(50) };
    const ys = [_]FP{ fp.ZERO, fp.ZERO };
    var fxs = [_]FP{ 0, 0 };
    var fys = [_]FP{ 0, 0 };

    const center = Vec2{ .x = fp.ZERO, .y = fp.ZERO };
    const strength = fp.div(fp.ONE, fp.fromInt(10)); // 0.1

    accumulateToCenter(&xs, &ys, &fxs, &fys, center, strength, Range.full(2));

    // Node 0 (left) should be pulled right
    try testing.expect(fxs[0] > 0);
    // Node 1 (right) should be pulled left
    try testing.expect(fxs[1] < 0);
}

test "centroid: computed correctly" {
    const xs = [_]FP{ fp.fromInt(-10), fp.fromInt(10) };
    const ys = [_]FP{ fp.fromInt(-10), fp.fromInt(10) };

    const center = computeCentroid(&xs, &ys);

    try testing.expectEqual(@as(FP, 0), center.x);
    try testing.expectEqual(@as(FP, 0), center.y);
}

test "centroid: single node" {
    const xs = [_]FP{fp.fromInt(42)};
    const ys = [_]FP{fp.fromInt(17)};

    const center = computeCentroid(&xs, &ys);

    try testing.expectEqual(fp.fromInt(42), center.x);
    try testing.expectEqual(fp.fromInt(17), center.y);
}
