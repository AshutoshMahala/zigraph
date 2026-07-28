//! Passive-parallelism contract tests.
//!
//! zigraph never spawns threads, but guarantees that callers can: independent
//! graphs must be fully isolated (no shared mutable state anywhere in the
//! library), and results must be identical however the work is scheduled.
//!
//! Stage A scope: per-graph diagnostics isolation, clear-on-entry semantics,
//! accessor behavior, and batch parallelism (N graphs on N threads produce
//! byte-identical output to serial runs). Later stages add partition-shuffle
//! tests for range kernels.

const std = @import("std");
const builtin = @import("builtin");
const zigraph = @import("root.zig");
const Graph = zigraph.Graph;
const Code = zigraph.Code;

// ============================================================================
// Diagnostics isolation
// ============================================================================

test "diagnostics: interleaved failures on two graphs never contaminate" {
    const allocator = std.testing.allocator;

    var a = Graph.initWithOptions(allocator, .{ .max_nodes = 1 });
    defer a.deinit();
    var b = Graph.init(allocator);
    defer b.deinit();

    // A fails with a node-limit error...
    try a.addNode(1, "a1");
    try std.testing.expectError(error.NodeLimitExceeded, a.addNode(2, "a2"));

    // ...then B fails with a different error...
    try b.addNode(1, "b1");
    try std.testing.expectError(error.NodeNotFound, b.addDiEdge(1, 99));

    // ...and each graph still reports its own error, not the other's.
    const da = a.lastDiagnostic().?;
    try std.testing.expectEqualStrings(Code.NODE_LIMIT_EXCEEDED, da.code);
    try std.testing.expect(da.nodes == null);

    const db = b.lastDiagnostic().?;
    try std.testing.expectEqualStrings(Code.NODE_NOT_FOUND, db.code);
    try std.testing.expectEqual(@as(usize, 99), db.nodes.?[0]);

    // A second failure on B leaves A untouched.
    try std.testing.expectError(error.NodeNotFound, b.addDiEdge(98, 1));
    try std.testing.expectEqualStrings(Code.NODE_LIMIT_EXCEEDED, a.lastDiagnostic().?.code);
    try std.testing.expectEqual(@as(usize, 98), b.lastDiagnostic().?.nodes.?[0]);
}

test "diagnostics: cleared at the start of every fallible operation" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "one");
    try std.testing.expectError(error.NodeNotFound, g.addDiEdge(1, 99));
    try std.testing.expect(g.lastDiagnostic() != null);

    // A later successful operation clears the stale error.
    try g.addNode(2, "two");
    try std.testing.expect(g.lastDiagnostic() == null);

    // Same via the layout entry point: fail once, succeed once.
    try g.addDiEdge(1, 2);
    try g.addDiEdge(2, 1); // cycle
    try std.testing.expectError(error.CycleDetected, zigraph.layout(&g, allocator, .{}));
    try std.testing.expectEqualStrings(Code.CYCLE_DETECTED, g.lastDiagnostic().?.code);

    var ir = try zigraph.layout(&g, allocator, .{ .cycle_breaking = .depth_first });
    ir.deinit();
    try std.testing.expect(g.lastDiagnostic() == null);
}

test "diagnostics: layout cycle error carries detail and node IDs" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();
    try g.addNode(1, "alpha");
    try g.addNode(2, "beta");
    try g.addDiEdge(1, 2);
    try g.addDiEdge(2, 1);

    try std.testing.expectError(error.CycleDetected, zigraph.layout(&g, allocator, .{}));

    const d = g.lastDiagnostic().?;
    try std.testing.expectEqualStrings(Code.CYCLE_DETECTED, d.code);
    try std.testing.expect(d.detail != null); // human-readable path via labels
    try std.testing.expect(d.nodes != null); // machine-readable node IDs
    try std.testing.expect(d.src != null);
}

// ============================================================================
// Accessor behavior
// ============================================================================

test "accessors: neighbor order matches insertion order, out-of-range is empty" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();
    try g.addNode(10, "a");
    try g.addNode(20, "b");
    try g.addNode(30, "c");
    try g.addNode(40, "d");

    // Deliberately non-monotonic insertion order: 30, 20, 40.
    try g.addDiEdge(10, 30);
    try g.addDiEdge(10, 20);
    try g.addDiEdge(10, 40);

    const idx_a = g.nodeIndex(10).?;
    const idx_b = g.nodeIndex(20).?;
    const idx_c = g.nodeIndex(30).?;
    const idx_d = g.nodeIndex(40).?;

    const children = try g.getChildren(idx_a);
    try std.testing.expectEqual(@as(usize, 3), children.len);
    try std.testing.expectEqual(idx_c, children[0]);
    try std.testing.expectEqual(idx_b, children[1]);
    try std.testing.expectEqual(idx_d, children[2]);

    const parents = try g.getParents(idx_b);
    try std.testing.expectEqual(@as(usize, 1), parents.len);
    try std.testing.expectEqual(idx_a, parents[0]);

    // Out-of-range index degrades to an empty slice, not a panic.
    try std.testing.expectEqual(@as(usize, 0), (try g.getChildren(999)).len);
    try std.testing.expectEqual(@as(usize, 0), (try g.getParents(999)).len);
}

// ============================================================================
// Freeze semantics
// ============================================================================

test "freeze: mutation invalidates the cached view, refreeze reflects it" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();
    try g.addNode(1, "a");
    try g.addNode(2, "b");
    try g.addDiEdge(1, 2);

    const f1 = try g.ensureFrozen();
    try std.testing.expectEqual(@as(usize, 1), f1.children(0).len);

    // Mutating drops the cache; the next freeze sees the new edge.
    try g.addNode(3, "c");
    try g.addDiEdge(1, 3);
    try std.testing.expect(g.frozen == null);

    const f2 = try g.ensureFrozen();
    try std.testing.expectEqual(@as(usize, 2), f2.children(0).len);

    // Repeated freezes without mutation reuse the same cached view.
    const f3 = try g.ensureFrozen();
    try std.testing.expectEqual(@intFromPtr(f2), @intFromPtr(f3));
}

test "freeze: failed mutation leaves the live frozen view intact" {
    const allocator = std.testing.allocator;

    var g = Graph.initWithOptions(allocator, .{ .max_nodes = 2, .max_edges = 1 });
    defer g.deinit();
    try g.addNode(1, "a");
    try g.addNode(2, "b");
    try g.addDiEdge(1, 2);

    const frozen = try g.ensureFrozen();
    const before = frozen.children(0);

    // Mutations that fail their preconditions must not touch the cache:
    // the previously returned view (and slices into it) stay valid.
    try std.testing.expectError(error.NodeLimitExceeded, g.addNode(3, "c"));
    try std.testing.expectError(error.EdgeLimitExceeded, g.addDiEdge(2, 1));
    try std.testing.expectError(error.NodeNotFound, g.addDiEdge(1, 99));

    try std.testing.expect(g.frozen != null);
    const after = try g.ensureFrozen();
    try std.testing.expectEqual(@intFromPtr(frozen), @intFromPtr(after));
    try std.testing.expectEqual(before.ptr, after.children(0).ptr);
    try std.testing.expectEqualSlices(zigraph.NodeIndex, before, after.children(0));
}

fn workerSumDegrees(frozen: *const zigraph.FrozenGraph, out_sum: *usize) void {
    var sum: usize = 0;
    for (0..frozen.node_count) |i| {
        sum += frozen.children(i).len + frozen.parents(i).len;
    }
    out_sum.* = sum;
}

test "freeze: one frozen view is safely shared by concurrent readers" {
    if (@import("builtin").single_threaded) return error.SkipZigTest;
    const allocator = std.testing.allocator;

    var g = try buildVariant(allocator, 2);
    defer g.deinit();
    const frozen = try g.ensureFrozen();

    // Serial reference: total degree = 2 * edge count.
    var expected: usize = 0;
    workerSumDegrees(frozen, &expected);
    try std.testing.expectEqual(2 * g.edgeCount(), expected);

    // Many readers of the same immutable view, no synchronization.
    const n_readers = 8;
    var sums = [_]usize{0} ** n_readers;
    var threads: [n_readers]std.Thread = undefined;
    var spawned: usize = 0;
    for (0..n_readers) |i| {
        threads[i] = std.Thread.spawn(.{}, workerSumDegrees, .{ frozen, &sums[i] }) catch break;
        spawned += 1;
    }
    for (threads[0..spawned]) |*t| t.join();

    try std.testing.expect(spawned > 0);
    for (sums[0..spawned]) |s| {
        try std.testing.expectEqual(expected, s);
    }
}

// ============================================================================
// Partition invariance (the contract's keystone)
// ============================================================================

const fdg = zigraph.fdg;
const FP = fdg.fixed_point.FP;
const fpm = fdg.fixed_point;
const Range = fdg.common.Range;

/// Run the full force pass (all five gather kernels) over the given ranges.
fn forcePassRanges(
    frozen: *const zigraph.FrozenGraph,
    qt: *const fdg.quadtree.Quadtree,
    xs: []const FP,
    ys: []const FP,
    fxs: []FP,
    fys: []FP,
    ranges: []const Range,
) void {
    const k_squared = fpm.fromInt(100);
    const inv_k = fpm.div(fpm.ONE, fpm.fromInt(10));
    const theta = fpm.fromFloat(0.8);
    const center = fpm.Vec2{ .x = fpm.fromInt(5), .y = fpm.fromInt(5) };
    const gravity_strength = fpm.div(fpm.ONE, fpm.fromInt(10));
    for (ranges) |r| {
        fdg.forces.accumulatePairwiseRepulsion(xs, ys, fxs, fys, k_squared, r);
        fdg.forces.accumulateAttraction(frozen, xs, ys, fxs, fys, inv_k, r);
        fdg.forces.accumulateBarnesHutRepulsion(xs, ys, fxs, fys, qt, k_squared, theta, r);
        fdg.forces.accumulateGravity(xs, ys, fxs, fys, center, gravity_strength, r);
        fdg.forces.accumulateStrongGravity(xs, ys, fxs, fys, center, gravity_strength, r);
    }
}

/// The pre-Stage-D scatter loops, reproduced as a reference model: each
/// pair/edge computed once, written to both endpoints.
///
/// Uses raw `+|`/`-|` (the historical semantics) while the gather kernels
/// use `accumAdd`/`accumSub`, whose test-build instrumentation panics on
/// saturation *before* any comparison runs. The equivalence this test
/// proves is therefore "bit-identical on non-saturating workloads" — it
/// does not (and cannot) claim order-insensitivity at saturation, where
/// attraction's changed per-cell order could legitimately differ.
fn legacyScatterReference(
    frozen: *const zigraph.FrozenGraph,
    xs: []const FP,
    ys: []const FP,
    fxs: []FP,
    fys: []FP,
) void {
    const Vec2 = fpm.Vec2;
    const k_squared = fpm.fromInt(100);
    const inv_k = fpm.div(fpm.ONE, fpm.fromInt(10));
    const n = xs.len;
    // Repulsion: i<j scatter (historical applyPairwise).
    for (0..n) |i| {
        for ((i + 1)..n) |j| {
            const delta = Vec2{ .x = xs[i] -| xs[j], .y = ys[i] -| ys[j] };
            const d = delta.length();
            if (d < 2) continue;
            const force_vec = delta.normalizeScaled(fpm.div(k_squared, d));
            fxs[i] = fxs[i] +| force_vec.x;
            fys[i] = fys[i] +| force_vec.y;
            fxs[j] = fxs[j] -| force_vec.x;
            fys[j] = fys[j] -| force_vec.y;
        }
    }
    // Attraction: per-edge scatter in edge orientation (historical
    // applyBetween over adjacency).
    for (0..n) |u| {
        for (frozen.children(u)) |v| {
            if (u == v) continue;
            const delta = Vec2{ .x = xs[u] -| xs[v], .y = ys[u] -| ys[v] };
            const d = delta.length();
            if (d < 2) continue;
            const force_vec = delta.normalizeScaled(fpm.mul(d, inv_k));
            fxs[u] = fxs[u] -| force_vec.x;
            fys[u] = fys[u] -| force_vec.y;
            fxs[v] = fxs[v] +| force_vec.x;
            fys[v] = fys[v] +| force_vec.y;
        }
    }
}

test "gather kernels are bit-identical to the legacy scatter loops" {
    const allocator = std.testing.allocator;

    for (0..8) |seed| {
        var g = try buildVariant(allocator, seed);
        defer g.deinit();
        const frozen = try g.ensureFrozen();
        const n = g.nodeCount();

        const xs = try allocator.alloc(FP, n);
        defer allocator.free(xs);
        const ys = try allocator.alloc(FP, n);
        defer allocator.free(ys);
        fdg.common.initGridJitterSoa(xs, ys, fpm.fromInt(10), seed);

        const scatter_fxs = try allocator.alloc(FP, n);
        defer allocator.free(scatter_fxs);
        const scatter_fys = try allocator.alloc(FP, n);
        defer allocator.free(scatter_fys);
        @memset(scatter_fxs, 0);
        @memset(scatter_fys, 0);
        legacyScatterReference(frozen, xs, ys, scatter_fxs, scatter_fys);

        const gather_fxs = try allocator.alloc(FP, n);
        defer allocator.free(gather_fxs);
        const gather_fys = try allocator.alloc(FP, n);
        defer allocator.free(gather_fys);
        @memset(gather_fxs, 0);
        @memset(gather_fys, 0);
        const full = Range.full(n);
        fdg.forces.accumulatePairwiseRepulsion(xs, ys, gather_fxs, gather_fys, fpm.fromInt(100), full);
        fdg.forces.accumulateAttraction(frozen, xs, ys, gather_fxs, gather_fys, fpm.div(fpm.ONE, fpm.fromInt(10)), full);

        try std.testing.expectEqualSlices(FP, scatter_fxs, gather_fxs);
        try std.testing.expectEqualSlices(FP, scatter_fys, gather_fys);
    }
}

/// Assert partition invariance of the full force pass on one graph:
/// random chunkings of [0, n), executed in shuffled order, must be
/// byte-identical to a single full-range pass.
fn checkPartitionInvariance(allocator: std.mem.Allocator, random: std.Random, g: *Graph, position_seed: u64) !void {
    const frozen = try g.ensureFrozen();
    const n = g.nodeCount();

    // Deterministic jittered SoA positions.
    const xs = try allocator.alloc(FP, n);
    defer allocator.free(xs);
    const ys = try allocator.alloc(FP, n);
    defer allocator.free(ys);
    fdg.common.initGridJitterSoa(xs, ys, fpm.fromInt(10), position_seed);

    var qt = try fdg.quadtree.Quadtree.build(xs, ys, allocator);
    defer qt.deinit();

    // Reference: one full range.
    const ref_fxs = try allocator.alloc(FP, n);
    defer allocator.free(ref_fxs);
    const ref_fys = try allocator.alloc(FP, n);
    defer allocator.free(ref_fys);
    @memset(ref_fxs, 0);
    @memset(ref_fys, 0);
    forcePassRanges(frozen, &qt, xs, ys, ref_fxs, ref_fys, &.{Range.full(n)});

    // Trials: random chunk boundaries, executed in shuffled order.
    const fxs = try allocator.alloc(FP, n);
    defer allocator.free(fxs);
    const fys = try allocator.alloc(FP, n);
    defer allocator.free(fys);

    for (0..6) |_| {
        // Random partition of [0, n) into 1..5 chunks.
        var ranges_buf: [5]Range = undefined;
        const n_chunks = random.intRangeAtMost(usize, 1, 5);
        var cuts_buf: [6]u32 = undefined;
        cuts_buf[0] = 0;
        for (1..n_chunks) |c| {
            cuts_buf[c] = random.intRangeAtMost(u32, 0, @intCast(n));
        }
        cuts_buf[n_chunks] = @intCast(n);
        std.mem.sort(u32, cuts_buf[0 .. n_chunks + 1], {}, std.sort.asc(u32));
        for (0..n_chunks) |c| {
            ranges_buf[c] = .{ .begin = cuts_buf[c], .end = cuts_buf[c + 1] };
        }
        random.shuffle(Range, ranges_buf[0..n_chunks]);

        @memset(fxs, 0);
        @memset(fys, 0);
        forcePassRanges(frozen, &qt, xs, ys, fxs, fys, ranges_buf[0..n_chunks]);

        try std.testing.expectEqualSlices(FP, ref_fxs, fxs);
        try std.testing.expectEqualSlices(FP, ref_fys, fys);
    }
}

/// A larger random graph than buildVariant's small chains/fans, so the
/// partition corpus also covers graphs with hundreds of nodes/edges.
fn buildRandomGraph(allocator: std.mem.Allocator, random: std.Random, n: usize, m: usize) !Graph {
    var g = Graph.init(allocator);
    errdefer g.deinit();
    for (0..n) |i| try g.addNode(i, "r");
    for (0..m) |_| {
        const a = random.intRangeLessThan(usize, 0, n);
        const b = random.intRangeLessThan(usize, 0, n);
        try g.addDiEdge(a, b);
    }
    return g;
}

test "partition invariance: any chunking of the force pass is bit-identical" {
    const allocator = std.testing.allocator;
    var prng = std.Random.DefaultPrng.init(0xD1_5EED);
    const random = prng.random();

    // Small structured variants (chains + fans).
    for (0..8) |seed| {
        var g = try buildVariant(allocator, seed);
        defer g.deinit();
        try checkPartitionInvariance(allocator, random, &g, 42);
    }

    // Larger random graphs — the corpus the contract doc's claims rest on.
    for ([_][2]usize{ .{ 40, 100 }, .{ 80, 250 }, .{ 150, 500 } }) |shape| {
        var g = try buildRandomGraph(allocator, random, shape[0], shape[1]);
        defer g.deinit();
        try checkPartitionInvariance(allocator, random, &g, shape[0]);
    }
}

fn forcePassWorker(
    frozen: *const zigraph.FrozenGraph,
    qt: *const fdg.quadtree.Quadtree,
    xs: []const FP,
    ys: []const FP,
    fxs: []FP,
    fys: []FP,
    range: Range,
) void {
    forcePassRanges(frozen, qt, xs, ys, fxs, fys, &.{range});
}

test "partition invariance: threads writing disjoint ranges of one array" {
    if (@import("builtin").single_threaded) return error.SkipZigTest;
    const allocator = std.testing.allocator;

    var g = try buildVariant(allocator, 3);
    defer g.deinit();
    const frozen = try g.ensureFrozen();
    const n = g.nodeCount();

    const init_positions = try fdg.common.initGridJitter(n, fpm.fromInt(10), 7, allocator);
    defer allocator.free(init_positions);
    const xs = try allocator.alloc(FP, n);
    defer allocator.free(xs);
    const ys = try allocator.alloc(FP, n);
    defer allocator.free(ys);
    for (init_positions, 0..) |p, i| {
        xs[i] = p.x;
        ys[i] = p.y;
    }

    var qt = try fdg.quadtree.Quadtree.build(xs, ys, allocator);
    defer qt.deinit();

    // Serial reference.
    const ref_fxs = try allocator.alloc(FP, n);
    defer allocator.free(ref_fxs);
    const ref_fys = try allocator.alloc(FP, n);
    defer allocator.free(ref_fys);
    @memset(ref_fxs, 0);
    @memset(ref_fys, 0);
    forcePassRanges(frozen, &qt, xs, ys, ref_fxs, ref_fys, &.{Range.full(n)});

    // Concurrent: one SHARED output array, threads own disjoint ranges.
    const fxs = try allocator.alloc(FP, n);
    defer allocator.free(fxs);
    const fys = try allocator.alloc(FP, n);
    defer allocator.free(fys);
    @memset(fxs, 0);
    @memset(fys, 0);

    const n_workers = @min(n, 4);
    var threads: [4]std.Thread = undefined;
    var spawned: usize = 0;
    const chunk = n / n_workers;
    const rangeFor = struct {
        fn f(w: usize, ch: usize, nw: usize, total: usize) Range {
            const begin: u32 = @intCast(w * ch);
            const end: u32 = if (w == nw - 1) @intCast(total) else @intCast((w + 1) * ch);
            return .{ .begin = begin, .end = end };
        }
    }.f;
    for (0..n_workers) |w| {
        threads[w] = std.Thread.spawn(.{}, forcePassWorker, .{
            frozen, &qt, xs, ys, fxs, fys, rangeFor(w, chunk, n_workers, n),
        }) catch break;
        spawned += 1;
    }
    for (threads[0..spawned]) |*t| t.join();
    // If some spawns failed, run their ranges serially — partition
    // invariance is scheduler-independent, so the result must still match.
    for (spawned..n_workers) |w| {
        forcePassWorker(frozen, &qt, xs, ys, fxs, fys, rangeFor(w, chunk, n_workers, n));
    }

    try std.testing.expectEqualSlices(FP, ref_fxs, fxs);
    try std.testing.expectEqualSlices(FP, ref_fys, fys);
}

// ============================================================================
// Batch parallelism (tests only — `std` is not a dependency)
// ============================================================================

/// Build a small deterministic graph variant. Each seed produces a different
/// chain + fan shape so per-thread outputs genuinely differ.
fn buildVariant(allocator: std.mem.Allocator, seed: usize) !Graph {
    var g = Graph.init(allocator);
    errdefer g.deinit();

    const chain_len = 3 + (seed % 4);
    var id: usize = 1;
    while (id < chain_len) : (id += 1) {
        try g.addEdgeAutoCreate(id, id + 1);
    }
    // Fan out from the chain head.
    const fan = 2 + (seed % 3);
    var f: usize = 0;
    while (f < fan) : (f += 1) {
        try g.addEdgeAutoCreate(1, 100 + f);
    }
    return g;
}

fn renderVariant(allocator: std.mem.Allocator, seed: usize) ![]u8 {
    var g = try buildVariant(allocator, seed);
    defer g.deinit();
    return try zigraph.render(&g, allocator, .{});
}

fn workerRender(slot: *?[]u8, seed: usize) void {
    // Each worker uses the thread-safe page allocator; isolation from other
    // workers is the property under test, not allocator behavior.
    slot.* = renderVariant(std.heap.page_allocator, seed) catch null;
}

test "batch parallelism: concurrent layouts are byte-identical to serial" {
    if (builtin.single_threaded) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const n_workers = 8;

    // Serial reference outputs.
    var expected: [n_workers][]u8 = undefined;
    for (0..n_workers) |i| {
        expected[i] = try renderVariant(allocator, i);
    }
    defer for (0..n_workers) |i| allocator.free(expected[i]);

    // Concurrent runs of the same work, one graph per thread. If a spawn
    // fails partway, join the workers that did start (their result slots
    // point into this frame) before skipping.
    var results: [n_workers]?[]u8 = @splat(null);
    defer for (0..n_workers) |i| {
        if (results[i]) |r| std.heap.page_allocator.free(r);
    };

    var threads: [n_workers]std.Thread = undefined;
    var spawned: usize = 0;
    for (0..n_workers) |i| {
        threads[i] = std.Thread.spawn(.{}, workerRender, .{ &results[i], i }) catch break;
        spawned += 1;
    }
    for (threads[0..spawned]) |*t| t.join();
    if (spawned < n_workers) return error.SkipZigTest; // could not exercise concurrency

    for (0..n_workers) |i| {
        try std.testing.expect(results[i] != null); // worker did not error
        try std.testing.expectEqualStrings(expected[i], results[i].?);
    }
}

// ============================================================================
// Diagnostics semantics edge cases
// ============================================================================

test "diagnostics: read-only queries never modify the captured diagnostic" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();
    try g.addNode(1, "one");
    try g.addNode(2, "two");
    try g.addDiEdge(1, 2);

    // Capture an error, then run every read-only query.
    try std.testing.expectError(error.NodeNotFound, g.addDiEdge(1, 99));
    try std.testing.expectEqualStrings(Code.NODE_NOT_FOUND, g.lastDiagnostic().?.code);

    var vr = try g.validate(allocator);
    vr.deinit();
    _ = try g.hasCycle(allocator);
    var roots = try g.findRoots(allocator);
    roots.deinit(allocator);
    var leaves = try g.findLeaves(allocator);
    leaves.deinit(allocator);
    _ = try g.getChildren(0);
    _ = g.nodeCount();

    // The stale diagnostic is still there — read-only queries are inert.
    try std.testing.expectEqualStrings(Code.NODE_NOT_FOUND, g.lastDiagnostic().?.code);

    // Explicit clear resets it.
    g.clearDiagnostics();
    try std.testing.expect(g.lastDiagnostic() == null);
}

test "diagnostics: allocation failure propagates without capture" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var g = Graph.init(failing.allocator());
    defer g.deinit();

    // The op clears on entry, then OOMs before any capture site — so the
    // diagnostic is null. This is the documented (deliberate) OOM behavior:
    // allocation failures carry no diagnostic context.
    try std.testing.expectError(error.OutOfMemory, g.addNode(1, "one"));
    try std.testing.expect(g.lastDiagnostic() == null);
}
