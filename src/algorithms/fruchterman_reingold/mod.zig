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
    repulsion_strength: FP = fp.ONE,

    /// Attraction strength multiplier (Q16.16).
    /// Multiplied with 1/k for attractive force. Default: 1.0.
    attraction_strength: FP = fp.ONE,

    /// Barnes-Hut theta parameter for `computeFast` (Q16.16).
    /// 0.0 = exact, 1.0 = aggressive approximation.
    /// Default: 0.8 (52428 in Q16.16).
    theta: FP = 52428, // floor(0.8 * 65536)
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

    // Initialize positions
    const positions = switch (config.initializer) {
        .grid => try common.initGrid(n, config.spacing, allocator),
        .grid_jitter => try common.initGridJitter(n, config.spacing, config.seed, allocator),
    };
    errdefer allocator.free(positions);

    // Ideal spring length: k = spacing
    const k = config.spacing;
    // k² for repulsion
    const k_squared = fp.mul(fp.mul(k, k), config.repulsion_strength);
    // 1/k for attraction (pre-computed)
    const inv_k = fp.div(config.attraction_strength, k);

    // Temporary force accumulator
    const force_accum = try allocator.alloc(Vec2, n);
    defer allocator.free(force_accum);

    var temperature = config.initial_temp;
    var iterations: u32 = 0;

    while (iterations < config.convergence.max_iterations) : (iterations += 1) {
        // Reset forces
        @memset(force_accum, Vec2{});

        // === Repulsive forces: O(N²) using shared force module ===
        forces.applyPairwiseRepulsion(positions, force_accum, k_squared);

        // === Attractive forces: O(E) ===
        // Iterate over edges via adjacency lists
        for (0..n) |u| {
            for (g.getChildren(u)) |v| {
                forces.applyAttraction(positions, force_accum, u, v, inv_k);
            }
        }

        // === Apply forces with temperature clamping ===
        const max_disp = applyForcesWithTemp(positions, force_accum, temperature);

        // === Cool ===
        temperature = fp.mul(temperature, config.decay);

        // === Check convergence ===
        if (max_disp < config.convergence.min_displacement) break;
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

    // Initialize positions
    const positions = switch (config.initializer) {
        .grid => try common.initGrid(n, config.spacing, allocator),
        .grid_jitter => try common.initGridJitter(n, config.spacing, config.seed, allocator),
    };
    errdefer allocator.free(positions);

    const k = config.spacing;
    const k_squared = fp.mul(fp.mul(k, k), config.repulsion_strength);
    const inv_k = fp.div(config.attraction_strength, k);

    const force_accum = try allocator.alloc(Vec2, n);
    defer allocator.free(force_accum);

    var temperature = config.initial_temp;
    var iterations: u32 = 0;

    while (iterations < config.convergence.max_iterations) : (iterations += 1) {
        @memset(force_accum, Vec2{});

        // === Repulsive forces: O(N log N) via Barnes-Hut ===
        var qt = try Quadtree.build(positions, allocator);
        defer qt.deinit();

        forces.applyBarnesHutRepulsion(positions, force_accum, &qt, k_squared, config.theta);

        // === Attractive forces: O(E) ===
        for (0..n) |u| {
            for (g.getChildren(u)) |v| {
                forces.applyAttraction(positions, force_accum, u, v, inv_k);
            }
        }

        // === Apply forces with temperature clamping ===
        const max_disp = applyForcesWithTemp(positions, force_accum, temperature);

        // === Cool ===
        temperature = fp.mul(temperature, config.decay);

        // === Check convergence ===
        if (max_disp < config.convergence.min_displacement) break;
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

/// Apply accumulated forces to positions with temperature clamping.
/// Returns the maximum displacement applied.
fn applyForcesWithTemp(positions: []Vec2, force_accum: []const Vec2, temperature: FP) FP {
    var max_disp: FP = fp.ZERO;

    for (0..positions.len) |i| {
        const disp = force_accum[i].length();
        if (disp < 1) continue;

        // Clamp displacement to temperature
        const clamped = fp.min(disp, temperature);
        const scaled = force_accum[i].normalizeScaled(clamped);

        positions[i] = positions[i].addVec(scaled);
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
