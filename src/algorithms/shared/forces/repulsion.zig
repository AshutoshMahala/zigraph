//! Repulsive Forces (SoA gather kernels)
//!
//! All-pairs Coulomb-like repulsion: f_rep = k² / d.
//!
//! Both kernels are **gather-only** and range-parameterized per the
//! passive-parallelism contract: each output cell `i` in `[range.begin,
//! range.end)` is written by exactly this call, reading only the frozen
//! position arrays. Any partition of `[0, n)` produces bit-identical
//! results (accumulation per cell runs in a fixed, data-defined order and
//! is asserted non-saturating in safe builds).

const std = @import("std");
const fp = @import("../fixed_point.zig");
const FP = fp.FP;
const Vec2 = fp.Vec2;
const Quadtree = @import("../quadtree.zig").Quadtree;
const common = @import("../common.zig");
const Range = common.Range;

/// Accumulate exact O(N²) pairwise repulsion into `fxs`/`fys` for nodes in
/// `range`.
///
/// Gather formulation: node `i` sums contributions from every other node
/// `j` in ascending order — the same per-cell contribution order as the
/// historical `i<j` scatter loop, so results are bit-identical to it.
/// Each pair's force is computed in canonical (low index → high index)
/// orientation and sign-flipped for the higher endpoint, preserving exact
/// antisymmetry.
pub fn accumulatePairwise(
    xs: []const FP,
    ys: []const FP,
    fxs: []FP,
    fys: []FP,
    k_squared: FP,
    range: Range,
) void {
    common.assertShape(xs, ys, fxs, fys, range);
    const n = xs.len;
    for (range.begin..range.end) |i| {
        for (0..n) |j| {
            if (j == i) continue;

            // Canonical orientation: delta from the lower-indexed node.
            const a = @min(i, j);
            const b = @max(i, j);
            const delta = Vec2{ .x = fp.sub(xs[a], xs[b]), .y = fp.sub(ys[a], ys[b]) };
            const d = delta.length();
            if (d < 2) continue; // Coincident — skip

            // f_rep = k² / d
            const force_mag = fp.div(k_squared, d);
            const force_vec = delta.normalizeScaledWithLength(force_mag, d);

            if (i == a) {
                fxs[i] = fp.accumAdd(fxs[i], force_vec.x);
                fys[i] = fp.accumAdd(fys[i], force_vec.y);
            } else {
                fxs[i] = fp.accumSub(fxs[i], force_vec.x);
                fys[i] = fp.accumSub(fys[i], force_vec.y);
            }
        }
    }
}

/// Accumulate O(N log N) Barnes-Hut approximated repulsion for nodes in
/// `range`.
///
/// The quadtree must be built from the same `xs`/`ys` arrays and is
/// read-only here — already a pure gather.
pub fn accumulateBarnesHut(
    xs: []const FP,
    ys: []const FP,
    fxs: []FP,
    fys: []FP,
    quadtree: *const Quadtree,
    k_squared: FP,
    theta: FP,
    range: Range,
) void {
    common.assertShape(xs, ys, fxs, fys, range);
    for (range.begin..range.end) |i| {
        const f = quadtree.computeForce(Vec2{ .x = xs[i], .y = ys[i] }, k_squared, theta);
        fxs[i] = fp.accumAdd(fxs[i], f.x);
        fys[i] = fp.accumAdd(fys[i], f.y);
    }
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "pairwise repulsion: two nodes pushed apart" {
    const xs = [_]FP{ fp.ZERO, fp.fromInt(10) };
    const ys = [_]FP{ fp.ZERO, fp.ZERO };
    var fxs = [_]FP{ 0, 0 };
    var fys = [_]FP{ 0, 0 };

    accumulatePairwise(&xs, &ys, &fxs, &fys, fp.fromInt(100), Range.full(2));

    // Node 0 (left) pushed further left, node 1 (right) pushed right.
    try testing.expect(fxs[0] < 0);
    try testing.expect(fxs[1] > 0);
    // Exact antisymmetry.
    try testing.expectEqual(fxs[0], -fxs[1]);
    try testing.expectEqual(fys[0], -fys[1]);
}

test "pairwise repulsion: coincident nodes skipped" {
    const xs = [_]FP{ fp.fromInt(5), fp.fromInt(5) };
    const ys = [_]FP{ fp.fromInt(5), fp.fromInt(5) };
    var fxs = [_]FP{ 0, 0 };
    var fys = [_]FP{ 0, 0 };

    accumulatePairwise(&xs, &ys, &fxs, &fys, fp.fromInt(100), Range.full(2));

    try testing.expectEqual(fp.ZERO, fxs[0]);
    try testing.expectEqual(fp.ZERO, fys[1]);
}

test "pairwise repulsion: partial range writes only its cells" {
    const xs = [_]FP{ fp.ZERO, fp.fromInt(10), fp.fromInt(20) };
    const ys = [_]FP{ fp.ZERO, fp.ZERO, fp.ZERO };
    var fxs = [_]FP{ 0, 0, 0 };
    var fys = [_]FP{ 0, 0, 0 };

    accumulatePairwise(&xs, &ys, &fxs, &fys, fp.fromInt(100), .{ .begin = 1, .end = 2 });

    // Only cell 1 written.
    try testing.expectEqual(fp.ZERO, fxs[0]);
    try testing.expectEqual(fp.ZERO, fxs[2]);
    // Cell 1 is centered between equidistant neighbors: forces cancel.
    try testing.expectEqual(fp.ZERO, fxs[1]);
    try testing.expectEqual(fp.ZERO, fys[1]);
}
