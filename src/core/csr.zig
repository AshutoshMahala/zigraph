//! Compressed Sparse Row adjacency — the freeze-point representation.
//!
//! This is the frozen, shareable adjacency structure from the
//! passive-parallelism contract: built once from the edge list when layout
//! begins, then immutable — any number of threads may read it concurrently
//! with no synchronization. Three contiguous arrays per direction replace
//! the per-node ArrayList-of-ArrayLists. Retained bytes per edge are
//! comparable to the old representation (u32 target + u32 edge_id per
//! direction vs. one usize entry); the wins are locality (sequential scans
//! over contiguous memory instead of a pointer-chase per node), zero
//! per-node allocations/headers/growth slack, and immutability.
//!
//! Neighbor lists preserve edge-insertion order exactly (the counting-sort
//! fill walks edges in order), so freezing is invisible to layout output.
//!
//! Dependency-neutral: imports only `index.zig`, so `graph.zig`,
//! `validation.zig`, and the layout pipeline can all consume it.

const std = @import("std");
const Allocator = std.mem.Allocator;
const core_index = @import("index.zig");
pub const NodeIndex = core_index.NodeIndex;

/// One direction of adjacency in CSR form.
///
/// Node `i`'s neighbors are `targets[offsets[i]..offsets[i+1]]`, in
/// edge-insertion order. `edge_ids` parallels `targets`: the position of the
/// originating edge in the graph's edge list (for label / directedness /
/// reversed lookups).
pub const Csr = struct {
    /// Length `node_count + 1`; `offsets[node_count]` == total entries.
    offsets: []u32,
    /// Neighbor indices, grouped by source node, edge-insertion order.
    targets: []NodeIndex,
    /// For each entry in `targets`, the index of the edge that produced it.
    edge_ids: []u32,

    pub fn nodeCount(self: *const Csr) usize {
        return self.offsets.len - 1;
    }

    /// Neighbors of node `idx`. Out-of-range indices yield an empty slice.
    pub fn neighbors(self: *const Csr, idx: usize) []const NodeIndex {
        if (idx >= self.nodeCount()) return &.{};
        return self.targets[self.offsets[idx]..self.offsets[idx + 1]];
    }

    /// Edge indices incident to node `idx` (parallel to `neighbors`).
    pub fn edgeIds(self: *const Csr, idx: usize) []const u32 {
        if (idx >= self.nodeCount()) return &.{};
        return self.edge_ids[self.offsets[idx]..self.offsets[idx + 1]];
    }

    fn deinit(self: *Csr, allocator: Allocator) void {
        allocator.free(self.offsets);
        allocator.free(self.targets);
        allocator.free(self.edge_ids);
    }
};

/// Frozen adjacency in both directions, built once at the freeze point.
///
/// `out.neighbors(i)` are node i's children, `in.neighbors(i)` its parents —
/// byte-identical in content and order to the pre-freeze ArrayList adjacency
/// they replace. Undirected edges appear exactly like directed ones (stored
/// once, from → to), matching historical behavior.
pub const FrozenGraph = struct {
    allocator: Allocator,
    node_count: usize,
    out: Csr,
    in: Csr,

    pub const BuildError = error{ EndpointOutOfRange, OutOfMemory };

    /// Build both CSR directions from edge endpoint pairs (`[from, to]`
    /// internal indices, in edge order). Six exact-size retained
    /// allocations (plus three transient build buffers); nothing grows,
    /// nothing is reallocated — arena-friendly.
    ///
    /// Endpoints are validated: any index `>= node_count` returns
    /// `error.EndpointOutOfRange` before anything is allocated.
    pub fn build(allocator: Allocator, node_count: usize, endpoints: []const [2]NodeIndex) BuildError!FrozenGraph {
        std.debug.assert(node_count <= core_index.index_capacity);
        std.debug.assert(endpoints.len <= core_index.index_capacity);
        for (endpoints) |e| {
            if (e[0] >= node_count or e[1] >= node_count) return error.EndpointOutOfRange;
        }
        const n = node_count;
        const m = endpoints.len;

        var out = try buildDirection(allocator, n, m, endpoints, 0, 1);
        errdefer out.deinit(allocator);
        const in = try buildDirection(allocator, n, m, endpoints, 1, 0);

        return .{ .allocator = allocator, .node_count = n, .out = out, .in = in };
    }

    fn buildDirection(
        allocator: Allocator,
        n: usize,
        m: usize,
        endpoints: []const [2]NodeIndex,
        comptime src_slot: usize,
        comptime dst_slot: usize,
    ) !Csr {
        const offsets = try allocator.alloc(u32, n + 1);
        errdefer allocator.free(offsets);
        const targets = try allocator.alloc(NodeIndex, m);
        errdefer allocator.free(targets);
        const edge_ids = try allocator.alloc(u32, m);
        errdefer allocator.free(edge_ids);

        // Count degrees.
        @memset(offsets, 0);
        for (endpoints) |e| offsets[e[src_slot] + 1] += 1;
        // Prefix-sum into offsets.
        var sum: u32 = 0;
        for (offsets) |*o| {
            sum += o.*;
            o.* = sum;
        }
        // offsets[i] is now the END of node i-1's range == start of node i's;
        // fill walking edges in insertion order using a cursor copy.
        const cursors = try allocator.alloc(u32, n);
        defer allocator.free(cursors);
        @memcpy(cursors, offsets[0..n]);
        for (endpoints, 0..) |e, edge_idx| {
            const src = e[src_slot];
            targets[cursors[src]] = e[dst_slot];
            edge_ids[cursors[src]] = @intCast(edge_idx);
            cursors[src] += 1;
        }

        return .{ .offsets = offsets, .targets = targets, .edge_ids = edge_ids };
    }

    /// Children of node `idx` (edge-insertion order; empty when out of range).
    pub fn children(self: *const FrozenGraph, idx: usize) []const NodeIndex {
        return self.out.neighbors(idx);
    }

    /// Parents of node `idx` (edge-insertion order; empty when out of range).
    pub fn parents(self: *const FrozenGraph, idx: usize) []const NodeIndex {
        return self.in.neighbors(idx);
    }

    pub fn deinit(self: *FrozenGraph) void {
        self.out.deinit(self.allocator);
        self.in.deinit(self.allocator);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "csr: empty graph" {
    var fg = try FrozenGraph.build(std.testing.allocator, 0, &.{});
    defer fg.deinit();
    try std.testing.expectEqual(@as(usize, 0), fg.node_count);
    try std.testing.expectEqual(@as(usize, 0), fg.children(0).len);
    try std.testing.expectEqual(@as(usize, 0), fg.parents(999).len);
}

test "csr: nodes without edges" {
    var fg = try FrozenGraph.build(std.testing.allocator, 3, &.{});
    defer fg.deinit();
    for (0..3) |i| {
        try std.testing.expectEqual(@as(usize, 0), fg.children(i).len);
        try std.testing.expectEqual(@as(usize, 0), fg.parents(i).len);
    }
}

test "csr: neighbor order matches edge-insertion order" {
    // Node 0's children inserted as 2, 1, 3 — order must be preserved.
    var fg = try FrozenGraph.build(std.testing.allocator, 4, &.{
        .{ 0, 2 },
        .{ 0, 1 },
        .{ 3, 0 },
        .{ 0, 3 },
        .{ 1, 3 },
    });
    defer fg.deinit();

    try std.testing.expectEqualSlices(NodeIndex, &.{ 2, 1, 3 }, fg.children(0));
    try std.testing.expectEqualSlices(NodeIndex, &.{3}, fg.children(1));
    try std.testing.expectEqualSlices(NodeIndex, &.{0}, fg.children(3));

    try std.testing.expectEqualSlices(NodeIndex, &.{3}, fg.parents(0));
    try std.testing.expectEqualSlices(NodeIndex, &.{0}, fg.parents(1));
    try std.testing.expectEqualSlices(NodeIndex, &.{0}, fg.parents(2));
    try std.testing.expectEqualSlices(NodeIndex, &.{ 0, 1 }, fg.parents(3));
}

test "csr: edge_ids map entries back to originating edges" {
    var fg = try FrozenGraph.build(std.testing.allocator, 3, &.{
        .{ 0, 1 }, // edge 0
        .{ 0, 2 }, // edge 1
        .{ 1, 2 }, // edge 2
    });
    defer fg.deinit();

    try std.testing.expectEqualSlices(u32, &.{ 0, 1 }, fg.out.edgeIds(0));
    try std.testing.expectEqualSlices(u32, &.{2}, fg.out.edgeIds(1));
    // In-direction: node 2's parents come from edges 1 and 2.
    try std.testing.expectEqualSlices(u32, &.{ 1, 2 }, fg.in.edgeIds(2));
}

test "csr: out-of-range endpoints are rejected" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.EndpointOutOfRange, FrozenGraph.build(allocator, 2, &.{.{ 0, 2 }}));
    try std.testing.expectError(error.EndpointOutOfRange, FrozenGraph.build(allocator, 0, &.{.{ 0, 0 }}));
    try std.testing.expectError(error.EndpointOutOfRange, FrozenGraph.build(allocator, 3, &.{ .{ 0, 1 }, .{ 5, 1 } }));
}

fn buildSmallForOomCheck(allocator: Allocator) !void {
    var fg = try FrozenGraph.build(allocator, 4, &.{ .{ 0, 1 }, .{ 1, 2 }, .{ 2, 3 }, .{ 0, 3 } });
    fg.deinit();
}

test "csr: allocation failure at any point leaks nothing" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, buildSmallForOomCheck, .{});
}

test "csr: randomized equivalence with reference append-order adjacency" {
    const allocator = std.testing.allocator;
    var prng = std.Random.DefaultPrng.init(0xC5A5EED);
    const random = prng.random();

    for (0..25) |_| {
        const n = random.intRangeAtMost(usize, 1, 40);
        const m = random.intRangeAtMost(usize, 0, 120);

        const endpoints = try allocator.alloc([2]NodeIndex, m);
        defer allocator.free(endpoints);

        // Reference model: naive per-node lists, appended in edge order —
        // the exact semantics of the pre-CSR adjacency representation.
        const ref_children = try allocator.alloc(std.ArrayListUnmanaged(NodeIndex), n);
        const ref_parents = try allocator.alloc(std.ArrayListUnmanaged(NodeIndex), n);
        for (ref_children) |*l| l.* = .empty;
        for (ref_parents) |*l| l.* = .empty;
        defer {
            for (ref_children) |*l| l.deinit(allocator);
            for (ref_parents) |*l| l.deinit(allocator);
            allocator.free(ref_children);
            allocator.free(ref_parents);
        }

        for (endpoints) |*e| {
            const from = random.intRangeLessThan(NodeIndex, 0, @intCast(n));
            const to = random.intRangeLessThan(NodeIndex, 0, @intCast(n));
            e.* = .{ from, to };
            try ref_children[from].append(allocator, to);
            try ref_parents[to].append(allocator, from);
        }

        var fg = try FrozenGraph.build(allocator, n, endpoints);
        defer fg.deinit();

        for (0..n) |i| {
            try std.testing.expectEqualSlices(NodeIndex, ref_children[i].items, fg.children(i));
            try std.testing.expectEqualSlices(NodeIndex, ref_parents[i].items, fg.parents(i));
        }
    }
}

test "csr: self-loop appears in both directions" {
    var fg = try FrozenGraph.build(std.testing.allocator, 2, &.{
        .{ 1, 1 },
    });
    defer fg.deinit();
    try std.testing.expectEqualSlices(NodeIndex, &.{1}, fg.children(1));
    try std.testing.expectEqualSlices(NodeIndex, &.{1}, fg.parents(1));
    try std.testing.expectEqual(@as(usize, 0), fg.children(0).len);
}
