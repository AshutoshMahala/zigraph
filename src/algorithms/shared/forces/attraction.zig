//! Attractive Forces (SoA gather kernel)
//!
//! Spring-like attraction along edges: f_att = d / k (proportional to
//! distance).
//!
//! Gather formulation over frozen CSR adjacency: node `u` visits its
//! incident edges from both directions (`children(u)` and `parents(u)`),
//! so each edge is processed twice — once per endpoint — but every write
//! lands in `u`'s own accumulator cell. This is the passive-parallelism
//! trade: ~2× the arithmetic of the historical scatter loop, in exchange
//! for race-free range partitioning and SIMD-friendly access.
//!
//! Each edge's force vector is computed in the **edge's own orientation**
//! (`from → to`), which both endpoints share — so the two per-endpoint
//! computations produce bit-identical vectors with opposite signs, exactly
//! matching the historical scatter results (which computed the vector once
//! in the same orientation and applied ±).

const std = @import("std");
const fp = @import("../fixed_point.zig");
const FP = fp.FP;
const Vec2 = fp.Vec2;
const FrozenGraph = @import("../../../core/csr.zig").FrozenGraph;
const common = @import("../common.zig");
const Range = common.Range;

/// Accumulate edge attraction into `fxs`/`fys` for nodes in `range`,
/// gathering over the frozen adjacency.
pub fn accumulateEdges(
    frozen: *const FrozenGraph,
    xs: []const FP,
    ys: []const FP,
    fxs: []FP,
    fys: []FP,
    inv_k: FP,
    range: Range,
) void {
    common.assertShape(xs, ys, fxs, fys, range);
    std.debug.assert(frozen.node_count == xs.len);
    for (range.begin..range.end) |u| {
        // Edges where u is the source: u = from, neighbor = to.
        for (frozen.children(u)) |v| {
            accumulateEndpoint(xs, ys, fxs, fys, inv_k, u, v, u, v);
        }
        // Edges where u is the target: neighbor = from, u = to.
        for (frozen.parents(u)) |v| {
            accumulateEndpoint(xs, ys, fxs, fys, inv_k, u, v, v, u);
        }
    }
}

/// Accumulate one edge's attraction contribution into node `u`'s cell.
/// The force vector is computed in the edge's `from → to` orientation;
/// `from` receives `-f` (pulled toward `to`), `to` receives `+f`.
fn accumulateEndpoint(
    xs: []const FP,
    ys: []const FP,
    fxs: []FP,
    fys: []FP,
    inv_k: FP,
    u: usize,
    v: usize,
    from: usize,
    to: usize,
) void {
    if (u == v) return; // Self-loop: no net force (historically d<2 skip)

    const delta = Vec2{ .x = fp.sub(xs[from], xs[to]), .y = fp.sub(ys[from], ys[to]) };
    const d = delta.length();
    if (d < 2) return; // Coincident — skip

    // f_att = d × inv_k (proportional to distance)
    const force_mag = fp.mul(d, inv_k);
    const force_vec = delta.normalizeScaledWithLength(force_mag, d);

    if (u == from) {
        fxs[u] = fp.accumSub(fxs[u], force_vec.x);
        fys[u] = fp.accumSub(fys[u], force_vec.y);
    } else {
        fxs[u] = fp.accumAdd(fxs[u], force_vec.x);
        fys[u] = fp.accumAdd(fys[u], force_vec.y);
    }
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

test "attraction: connected nodes pulled together" {
    const allocator = testing.allocator;
    var frozen = try FrozenGraph.build(allocator, 2, &.{.{ 0, 1 }});
    defer frozen.deinit();

    const xs = [_]FP{ fp.ZERO, fp.fromInt(100) };
    const ys = [_]FP{ fp.ZERO, fp.ZERO };
    var fxs = [_]FP{ 0, 0 };
    var fys = [_]FP{ 0, 0 };

    accumulateEdges(&frozen, &xs, &ys, &fxs, &fys, fp.div(fp.ONE, fp.fromInt(10)), Range.full(2));

    // Node 0 pulled right (toward 1), node 1 pulled left (toward 0).
    try testing.expect(fxs[0] > 0);
    try testing.expect(fxs[1] < 0);
    // Exact antisymmetry: both endpoints computed the same edge vector.
    try testing.expectEqual(fxs[0], -fxs[1]);
    try testing.expectEqual(fys[0], -fys[1]);
}

test "attraction: edge orientation does not break antisymmetry" {
    const allocator = testing.allocator;
    // Same topology, reversed edge orientation.
    var frozen = try FrozenGraph.build(allocator, 2, &.{.{ 1, 0 }});
    defer frozen.deinit();

    const xs = [_]FP{ fp.ZERO, fp.fromInt(100) };
    const ys = [_]FP{ fp.ZERO, fp.ZERO };
    var fxs = [_]FP{ 0, 0 };
    var fys = [_]FP{ 0, 0 };

    accumulateEdges(&frozen, &xs, &ys, &fxs, &fys, fp.div(fp.ONE, fp.fromInt(10)), Range.full(2));

    try testing.expect(fxs[0] > 0);
    try testing.expect(fxs[1] < 0);
    try testing.expectEqual(fxs[0], -fxs[1]);
}

test "attraction: self-loop contributes nothing" {
    const allocator = testing.allocator;
    var frozen = try FrozenGraph.build(allocator, 1, &.{.{ 0, 0 }});
    defer frozen.deinit();

    const xs = [_]FP{fp.fromInt(5)};
    const ys = [_]FP{fp.fromInt(5)};
    var fxs = [_]FP{0};
    var fys = [_]FP{0};

    accumulateEdges(&frozen, &xs, &ys, &fxs, &fys, fp.ONE, Range.full(1));

    try testing.expectEqual(fp.ZERO, fxs[0]);
    try testing.expectEqual(fp.ZERO, fys[0]);
}

test "attraction: partial range writes only its cells" {
    const allocator = testing.allocator;
    var frozen = try FrozenGraph.build(allocator, 3, &.{ .{ 0, 1 }, .{ 1, 2 } });
    defer frozen.deinit();

    const xs = [_]FP{ fp.ZERO, fp.fromInt(50), fp.fromInt(100) };
    const ys = [_]FP{ fp.ZERO, fp.ZERO, fp.ZERO };
    var fxs = [_]FP{ 0, 0, 0 };
    var fys = [_]FP{ 0, 0, 0 };

    accumulateEdges(&frozen, &xs, &ys, &fxs, &fys, fp.ONE, .{ .begin = 0, .end = 1 });

    try testing.expect(fxs[0] != 0); // in range: written
    try testing.expectEqual(fp.ZERO, fxs[1]); // out of range: untouched
    try testing.expectEqual(fp.ZERO, fxs[2]);
}
