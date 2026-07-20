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

    const children = g.getChildren(idx_a);
    try std.testing.expectEqual(@as(usize, 3), children.len);
    try std.testing.expectEqual(idx_c, children[0]);
    try std.testing.expectEqual(idx_b, children[1]);
    try std.testing.expectEqual(idx_d, children[2]);

    const parents = g.getParents(idx_b);
    try std.testing.expectEqual(@as(usize, 1), parents.len);
    try std.testing.expectEqual(idx_a, parents[0]);

    // Out-of-range index degrades to an empty slice, not a panic.
    try std.testing.expectEqual(@as(usize, 0), g.getChildren(999).len);
    try std.testing.expectEqual(@as(usize, 0), g.getParents(999).len);
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
    _ = g.getChildren(0);
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
