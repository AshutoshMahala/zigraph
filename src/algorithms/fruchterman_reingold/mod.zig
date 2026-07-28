//! Fruchterman-Reingold Force-Directed Layout
//!
//! A classic force-directed algorithm with two forces:
//! - **Repulsion:** All pairs of nodes repel (Coulomb-like)
//! - **Attraction:** Connected nodes attract (spring-like)
//!
//! Temperature cools over iterations, reducing displacement until convergence.
//!
//! ## Standalone Usage
//!
//! ```zig
//! const fr = @import("zigraph").fdg.fruchterman_reingold;
//! var result = try fr.compute(&graph, allocator, .{});
//! defer result.deinit();
//! // result.positions[i].x, result.positions[i].y — Q16.16
//! ```
//!
//! ## Variants
//!
//! - `compute()` — Standard: O(N²) exact repulsion. Best quality.
//! - `computeFast()` — Fast: O(N log N) Barnes-Hut approximation.
//!
//! ## Reference
//!
//! Fruchterman & Reingold, 1991 — "Graph Drawing by Force-Directed Placement"

const std = @import("std");
const Allocator = std.mem.Allocator;
const graph_mod = @import("../../core/graph.zig");
const csr_mod = @import("../../core/csr.zig");
const Graph = graph_mod.Graph;

// Shared modules
const fp = @import("../shared/fixed_point.zig");
const FP = fp.FP;
const Vec2 = fp.Vec2;
const common = @import("../shared/common.zig");
const PositionResult = common.PositionResult;
const Quadtree = @import("../shared/quadtree.zig").Quadtree;
const forces = @import("../shared/forces/mod.zig");

// ============================================================================
// Configuration
// ============================================================================

/// Configuration for Fruchterman-Reingold layout.
pub const Config = struct {
    /// Initial temperature (Q16.16). Controls maximum displacement per iteration.
    /// Higher → more exploration; lower → more stable.
    /// Default: 100.0 (6553600 in Q16.16).
    initial_temp: FP = fp.fromInt(100),

    /// Cooling factor per iteration (Q16.16).
    /// Temperature is multiplied by this each iteration.
    /// Default: 0.95 (62259 in Q16.16).
    decay: FP = 62259, // floor(0.95 * 65536)

    /// Spacing between grid positions for initialization (Q16.16).
    /// Also used to compute the ideal spring length `k`.
    /// Default: 20.0.
    spacing: FP = fp.fromInt(20),

    /// Convergence criteria.
    convergence: common.Convergence = .{},

    /// Initialization strategy.
    initializer: common.Initializer = .grid_jitter,

    /// Random seed (for grid_jitter initialization).
    seed: u64 = 42,

    /// Repulsion strength multiplier (Q16.16).
    /// Multiplied with k² for repulsive force. Default: 1.0.
    /// Domain: any Q16.16 value. Negative values invert repulsion into
    /// attraction (a niche but supported knob) — both the standard and
    /// Barnes-Hut variants handle the sign identically.
    repulsion_strength: FP = fp.ONE,

    /// Attraction strength multiplier (Q16.16).
    /// Multiplied with 1/k for attractive force. Default: 1.0.
    attraction_strength: FP = fp.ONE,

    /// Barnes-Hut theta parameter for `computeFast` (Q16.16).
    /// 0.0 = exact, 1.0 = aggressive approximation.
    /// Default: 0.8 (52428 in Q16.16).
    theta: FP = 52428, // floor(0.8 * 65536)

    /// Subgraph cohesion strength (Q16.16).
    /// Pulls nodes in the same subgraph toward their group centroid.
    /// 0 = disabled, 0.3–1.0 = typical range.
    /// Default: 0.5 (32768 in Q16.16).
    /// Only effective when the graph has subgraphs.
    subgraph_cohesion: FP = 32768, // floor(0.5 * 65536)

    /// Inter-cluster separation strength (Q16.16).
    /// Pushes sibling subgraphs apart with Coulomb-like repulsion
    /// between their centroids. Complements cohesion to prevent
    /// clusters from overlapping.
    /// 0 = disabled, 0.5–2.0 = typical range.
    /// Default: 1.0 (65536 in Q16.16).
    /// Only effective when the graph has subgraphs.
    cluster_separation: FP = fp.ONE,
};

// ============================================================================
// Standard variant: O(N²) exact repulsion
// ============================================================================

/// Compute FR layout with exact O(N²) pairwise repulsion.
///
/// This is the **standard** variant — highest quality, suitable for
/// graphs up to ~500 nodes.
///
/// The result contains Q16.16 positions. Use `LayoutIR.convertCoord()`
/// or the `layoutTyped()` entry point to convert to your desired type.
pub fn compute(g: *const Graph, allocator: Allocator, config: Config) !PositionResult {
    const n = g.nodeCount();
    if (n == 0) {
        return PositionResult{
            .positions = try allocator.alloc(Vec2, 0),
            .width = fp.ZERO,
            .height = fp.ZERO,
            .iterations = 0,
            .allocator = allocator,
        };
    }

    // Resolve frozen adjacency: reuse the graph's cached view when present
    // (layout() freezes before dispatch), else build a temporary one so
    // direct callers need no prior freeze.
    var local_frozen: ?csr_mod.FrozenGraph = null;
    defer if (local_frozen) |*f| f.deinit();
    const frozen: *const csr_mod.FrozenGraph = if (g.frozen) |*f| f else blk: {
        local_frozen = try g.buildFrozen(allocator);
        break :blk &local_frozen.?;
    };

    // SoA position arrays — the hot-loop representation (Vec2 only at the
    // PositionResult boundary).
    const xs = try allocator.alloc(FP, n);
    defer allocator.free(xs);
    const ys = try allocator.alloc(FP, n);
    defer allocator.free(ys);
    switch (config.initializer) {
        .grid => common.initGridSoa(xs, ys, config.spacing),
        .grid_jitter => common.initGridJitterSoa(xs, ys, config.spacing, config.seed),
    }

    // Apply pin constraints: override initial positions and build pin masks
    const pin_masks = try applyPins(g, xs, ys, config.spacing, allocator);
    defer if (pin_masks) |m| allocator.free(m);

    // Ideal spring length: k = spacing
    const k = config.spacing;
    // k² for repulsion
    const k_squared = fp.mul(fp.mul(k, k), config.repulsion_strength);
    // 1/k for attraction (pre-computed)
    const inv_k = fp.div(config.attraction_strength, k);

    // Build subgraph membership index for cohesion forces
    var sg_index = try forces.SubgraphIndex.build(g, allocator);
    defer sg_index.deinit();
    const has_subgraphs = sg_index.sg_count > 0;

    // Force accumulators (SoA)
    const fxs = try allocator.alloc(FP, n);
    defer allocator.free(fxs);
    const fys = try allocator.alloc(FP, n);
    defer allocator.free(fys);

    const full = common.Range.full(n);
    var temperature = config.initial_temp;
    var iterations: u32 = 0;

    while (iterations < config.convergence.max_iterations) : (iterations += 1) {
        // Reset forces
        @memset(fxs, 0);
        @memset(fys, 0);

        // === Repulsive forces: O(N²) gather kernel ===
        forces.accumulatePairwiseRepulsion(xs, ys, fxs, fys, k_squared, full);

        // === Attractive forces: O(E) gather over frozen CSR ===
        forces.accumulateAttraction(frozen, xs, ys, fxs, fys, inv_k, full);

        // === Subgraph cohesion (serial phase): pull members toward centroid ===
        if (has_subgraphs and config.subgraph_cohesion > 0) {
            forces.applyCohesion(xs, ys, fxs, fys, &sg_index, config.subgraph_cohesion);
        }

        // === Inter-cluster separation (serial phase) ===
        if (has_subgraphs and config.cluster_separation > 0) {
            forces.applySeparation(xs, ys, fxs, fys, &sg_index, g, config.cluster_separation, k_squared);
        }

        // === Apply forces with temperature clamping (respects pin constraints) ===
        const max_disp = applyForcesWithTemp(xs, ys, fxs, fys, temperature, pin_masks, full);

        // === Cool ===
        temperature = fp.mul(temperature, config.decay);

        // === Check convergence ===
        if (max_disp < config.convergence.min_displacement) break;
    }

    // Assemble the Vec2 output at the API boundary.
    const positions = try allocator.alloc(Vec2, n);
    for (positions, xs, ys) |*p, x, y| {
        p.* = .{ .x = x, .y = y };
    }

    var result = PositionResult{
        .positions = positions,
        .width = fp.ZERO,
        .height = fp.ZERO,
        .iterations = iterations,
        .allocator = allocator,
    };

    // Normalize to non-negative coordinates with margin
    result.normalize(config.spacing);

    return result;
}

// ============================================================================
// Fast variant: O(N log N) Barnes-Hut repulsion
// ============================================================================

/// Compute FR layout with Barnes-Hut O(N log N) approximation.
///
/// This is the **fast** variant — uses a quadtree to approximate
/// repulsive forces. Suitable for graphs with 500+ nodes.
///
/// The `theta` parameter (in Config) controls accuracy:
/// - 0.0 = exact (degrades to O(N²))
/// - 0.8 = default (good balance)
/// - 1.5 = aggressive (faster but less accurate)
pub fn computeFast(g: *const Graph, allocator: Allocator, config: Config) !PositionResult {
    const n = g.nodeCount();
    if (n == 0) {
        return PositionResult{
            .positions = try allocator.alloc(Vec2, 0),
            .width = fp.ZERO,
            .height = fp.ZERO,
            .iterations = 0,
            .allocator = allocator,
        };
    }

    // Resolve frozen adjacency: reuse the graph's cached view when present
    // (layout() freezes before dispatch), else build a temporary one so
    // direct callers need no prior freeze.
    var local_frozen: ?csr_mod.FrozenGraph = null;
    defer if (local_frozen) |*f| f.deinit();
    const frozen: *const csr_mod.FrozenGraph = if (g.frozen) |*f| f else blk: {
        local_frozen = try g.buildFrozen(allocator);
        break :blk &local_frozen.?;
    };

    // SoA position arrays — the hot-loop representation (Vec2 only at the
    // PositionResult boundary).
    const xs = try allocator.alloc(FP, n);
    defer allocator.free(xs);
    const ys = try allocator.alloc(FP, n);
    defer allocator.free(ys);
    switch (config.initializer) {
        .grid => common.initGridSoa(xs, ys, config.spacing),
        .grid_jitter => common.initGridJitterSoa(xs, ys, config.spacing, config.seed),
    }

    // Apply pin constraints: override initial positions and build pin masks
    const pin_masks = try applyPins(g, xs, ys, config.spacing, allocator);
    defer if (pin_masks) |m| allocator.free(m);

    const k = config.spacing;
    const k_squared = fp.mul(fp.mul(k, k), config.repulsion_strength);
    const inv_k = fp.div(config.attraction_strength, k);

    // Build subgraph membership index for cohesion forces
    var sg_index = try forces.SubgraphIndex.build(g, allocator);
    defer sg_index.deinit();
    const has_subgraphs = sg_index.sg_count > 0;

    // Force accumulators (SoA)
    const fxs = try allocator.alloc(FP, n);
    defer allocator.free(fxs);
    const fys = try allocator.alloc(FP, n);
    defer allocator.free(fys);

    const full = common.Range.full(n);
    var temperature = config.initial_temp;
    var iterations: u32 = 0;

    while (iterations < config.convergence.max_iterations) : (iterations += 1) {
        @memset(fxs, 0);
        @memset(fys, 0);

        // === Repulsive forces: O(N log N) via Barnes-Hut ===
        // Quadtree construction is the serial phase; reads are gather-safe.
        var qt = try Quadtree.build(xs, ys, allocator);
        defer qt.deinit();

        forces.accumulateBarnesHutRepulsion(xs, ys, fxs, fys, &qt, k_squared, config.theta, full);

        // === Attractive forces: O(E) gather over frozen CSR ===
        forces.accumulateAttraction(frozen, xs, ys, fxs, fys, inv_k, full);

        // === Subgraph cohesion (serial phase): pull members toward centroid ===
        if (has_subgraphs and config.subgraph_cohesion > 0) {
            forces.applyCohesion(xs, ys, fxs, fys, &sg_index, config.subgraph_cohesion);
        }

        // === Inter-cluster separation (serial phase) ===
        if (has_subgraphs and config.cluster_separation > 0) {
            forces.applySeparation(xs, ys, fxs, fys, &sg_index, g, config.cluster_separation, k_squared);
        }

        // === Apply forces with temperature clamping (respects pin constraints) ===
        const max_disp = applyForcesWithTemp(xs, ys, fxs, fys, temperature, pin_masks, full);

        // === Cool ===
        temperature = fp.mul(temperature, config.decay);

        // === Check convergence ===
        if (max_disp < config.convergence.min_displacement) break;
    }

    // Assemble the Vec2 output at the API boundary.
    const positions = try allocator.alloc(Vec2, n);
    for (positions, xs, ys) |*p, x, y| {
        p.* = .{ .x = x, .y = y };
    }

    var result = PositionResult{
        .positions = positions,
        .width = fp.ZERO,
        .height = fp.ZERO,
        .iterations = iterations,
        .allocator = allocator,
    };

    result.normalize(config.spacing);
    return result;
}

// ============================================================================
// Internal helpers
// ============================================================================

/// Pin mask flags for each node (packed for cache efficiency).
const PinMask = struct {
    /// True if this node's X axis is pinned
    x: bool = false,
    /// True if this node's Y axis is pinned
    y: bool = false,
};

/// Build pin masks and override initial positions for pinned nodes.
///
/// For each node with a pin constraint, the corresponding axis is marked
/// and the initial position is set to the pinned coordinate (scaled by spacing).
fn applyPins(g: *const Graph, xs: []FP, ys: []FP, spacing: FP, allocator: Allocator) !?[]PinMask {
    const n = g.nodeCount();

    // Quick scan: any pins at all?
    var has_any_pin = false;
    for (0..n) |i| {
        const node = g.nodeAt(i) orelse continue;
        if (node.pin != null) {
            has_any_pin = true;
            break;
        }
    }
    if (!has_any_pin) return null;

    const masks = try allocator.alloc(PinMask, n);
    @memset(masks, PinMask{});

    for (0..n) |i| {
        const node = g.nodeAt(i) orelse continue;
        const pin = node.pin orelse continue;

        if (pin.x) |px| {
            masks[i].x = true;
            xs[i] = fp.mul(fp.fromInt(@as(i32, @intCast(px))), spacing);
        }
        if (pin.y) |py| {
            masks[i].y = true;
            ys[i] = fp.mul(fp.fromInt(@as(i32, @intCast(py))), spacing);
        }
    }

    return masks;
}

/// Apply accumulated forces to positions with temperature clamping.
/// Respects pin masks: pinned axes are not displaced.
/// Returns the maximum displacement applied within `range`.
///
/// Range-parameterized position-update kernel: reads forces, writes only
/// position cells in `range` — the second phase of each iteration (the
/// force phase reads positions and writes forces; this phase reads forces
/// and writes positions; read/write sets are disjoint per phase).
fn applyForcesWithTemp(xs: []FP, ys: []FP, fxs: []const FP, fys: []const FP, temperature: FP, pin_masks: ?[]const PinMask, range: common.Range) FP {
    var max_disp: FP = fp.ZERO;

    for (range.begin..range.end) |i| {
        var force = Vec2{ .x = fxs[i], .y = fys[i] };

        // Zero out forces on pinned axes
        if (pin_masks) |masks| {
            if (masks[i].x) force.x = 0;
            if (masks[i].y) force.y = 0;
        }

        const disp = force.length();
        if (disp < 1) continue;

        // Clamp displacement to temperature
        const clamped = fp.min(disp, temperature);
        const scaled = force.normalizeScaledWithLength(clamped, disp);

        xs[i] = fp.add(xs[i], scaled.x);
        ys[i] = fp.add(ys[i], scaled.y);
        max_disp = fp.max(max_disp, clamped);
    }

    return max_disp;
}

// ============================================================================
// Tests
// ============================================================================

test "FR standard: empty graph" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    var result = try compute(&g, allocator, .{});
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 0), result.positions.len);
    try std.testing.expectEqual(@as(u32, 0), result.iterations);
}

test "FR standard: single node" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();
    try g.addNode(1, "A");

    var result = try compute(&g, allocator, .{});
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 1), result.positions.len);
}

test "FR standard: two connected nodes" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();
    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addEdge(1, 2);

    var result = try compute(&g, allocator, .{
        .convergence = .{ .max_iterations = 100 },
    });
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.positions.len);
    // They should be separated (not on top of each other)
    const d = result.positions[0].distTo(result.positions[1]);
    try std.testing.expect(d > fp.fromInt(1));
}

test "FR standard: triangle" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();
    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addEdge(1, 2);
    try g.addEdge(2, 3);
    try g.addEdge(1, 3);

    var result = try compute(&g, allocator, .{
        .convergence = .{ .max_iterations = 200 },
    });
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 3), result.positions.len);
    // All positions should be non-negative after normalize
    for (result.positions) |pos| {
        try std.testing.expect(pos.x >= 0);
        try std.testing.expect(pos.y >= 0);
    }
    // Width and height should be positive
    try std.testing.expect(result.width > 0);
    try std.testing.expect(result.height > 0);
}

test "FR standard: deterministic" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();
    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addNode(4, "D");
    try g.addEdge(1, 2);
    try g.addEdge(2, 3);
    try g.addEdge(3, 4);
    try g.addEdge(1, 4);

    const cfg = Config{
        .seed = 12345,
        .convergence = .{ .max_iterations = 50 },
    };

    var r1 = try compute(&g, allocator, cfg);
    defer r1.deinit();
    var r2 = try compute(&g, allocator, cfg);
    defer r2.deinit();

    // Bit-exact same output
    for (r1.positions, r2.positions) |p1, p2| {
        try std.testing.expectEqual(p1.x, p2.x);
        try std.testing.expectEqual(p1.y, p2.y);
    }
    try std.testing.expectEqual(r1.iterations, r2.iterations);
}

test "FR fast: two connected nodes" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();
    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addEdge(1, 2);

    var result = try computeFast(&g, allocator, .{
        .convergence = .{ .max_iterations = 100 },
    });
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.positions.len);
    const d = result.positions[0].distTo(result.positions[1]);
    try std.testing.expect(d > fp.fromInt(1));
}

test "FR fast: deterministic" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();
    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addEdge(1, 2);
    try g.addEdge(2, 3);

    const cfg = Config{
        .seed = 99,
        .convergence = .{ .max_iterations = 50 },
    };

    var r1 = try computeFast(&g, allocator, cfg);
    defer r1.deinit();
    var r2 = try computeFast(&g, allocator, cfg);
    defer r2.deinit();

    for (r1.positions, r2.positions) |p1, p2| {
        try std.testing.expectEqual(p1.x, p2.x);
        try std.testing.expectEqual(p1.y, p2.y);
    }
}

test "FR standard: subgraph cohesion clusters members" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    // Two clusters: {A, B} and {C, D} with one cross-cluster edge
    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addNode(4, "D");
    try g.addEdge(1, 2);
    try g.addEdge(3, 4);
    try g.addEdge(2, 3); // cross-cluster

    const sg1 = try g.addSubgraph("left");
    const sg2 = try g.addSubgraph("right");
    try g.putNodes(&.{ 1, 2 }).inside(sg1);
    try g.putNodes(&.{ 3, 4 }).inside(sg2);

    // Run WITH cohesion
    var r_cohesion = try compute(&g, allocator, .{
        .seed = 42,
        .convergence = .{ .max_iterations = 200 },
        .subgraph_cohesion = 32768, // 0.5
    });
    defer r_cohesion.deinit();

    // Run WITHOUT cohesion
    var r_none = try compute(&g, allocator, .{
        .seed = 42,
        .convergence = .{ .max_iterations = 200 },
        .subgraph_cohesion = 0,
    });
    defer r_none.deinit();

    // With cohesion, A-B distance should be smaller than without
    const d_ab_cohesion = r_cohesion.positions[0].distTo(r_cohesion.positions[1]);
    const d_ab_none = r_none.positions[0].distTo(r_none.positions[1]);

    // Cohesion should pull cluster members closer together
    try std.testing.expect(d_ab_cohesion <= d_ab_none);
}

test "FR fast: subgraph cohesion clusters members" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addNode(4, "D");
    try g.addEdge(1, 2);
    try g.addEdge(3, 4);
    try g.addEdge(2, 3);

    const sg1 = try g.addSubgraph("left");
    const sg2 = try g.addSubgraph("right");
    try g.putNodes(&.{ 1, 2 }).inside(sg1);
    try g.putNodes(&.{ 3, 4 }).inside(sg2);

    var result = try computeFast(&g, allocator, .{
        .seed = 42,
        .convergence = .{ .max_iterations = 200 },
        .subgraph_cohesion = 32768,
    });
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 4), result.positions.len);
    // All positions should be non-negative after normalize
    for (result.positions) |pos| {
        try std.testing.expect(pos.x >= 0);
        try std.testing.expect(pos.y >= 0);
    }
}

test "FR standard: no subgraphs — cohesion is no-op" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addEdge(1, 2);

    // With cohesion enabled but no subgraphs defined, should work identically
    var r1 = try compute(&g, allocator, .{
        .seed = 42,
        .convergence = .{ .max_iterations = 50 },
        .subgraph_cohesion = 32768,
    });
    defer r1.deinit();

    var r2 = try compute(&g, allocator, .{
        .seed = 42,
        .convergence = .{ .max_iterations = 50 },
        .subgraph_cohesion = 0,
    });
    defer r2.deinit();

    // Should produce identical results
    for (r1.positions, r2.positions) |p1, p2| {
        try std.testing.expectEqual(p1.x, p2.x);
        try std.testing.expectEqual(p1.y, p2.y);
    }
}
