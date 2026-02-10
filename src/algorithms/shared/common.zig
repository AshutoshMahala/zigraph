//! Common FDG types and utilities
//!
//! Shared infrastructure for all force-directed graph layout algorithms.
//! This module provides initialization strategies, convergence checking,
//! and the output type that all FDG algorithms produce.
//!
//! ## Standalone Usage
//!
//! Users can call FDG algorithms directly without going through the
//! top-level `layout()` / `layoutTyped()` pipeline:
//!
//! ```zig
//! const fdg = @import("zigraph").fdg;
//! var result = try fdg.fruchterman_reingold.compute(&graph, allocator, .{});
//! defer result.deinit();
//! // result.positions[i] is a Vec2 in Q16.16 for node index i
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;
const fp = @import("fixed_point.zig");
const FP = fp.FP;
const Vec2 = fp.Vec2;

// ============================================================================
// Configuration
// ============================================================================

/// Algorithm variant — controls the speed/quality trade-off.
pub const Variant = enum {
    /// Exact computation. Best quality, higher cost.
    standard,
    /// Approximations for scale. Good quality, much faster for large graphs.
    fast,
};

/// Convergence criteria — first condition met stops iteration.
pub const Convergence = struct {
    /// Hard limit on iteration count.
    max_iterations: u32 = 300,

    /// Stop when the maximum node displacement in a single iteration
    /// falls below this threshold (Q16.16).
    /// Default: ~0.01 = 655 in Q16.16.
    min_displacement: FP = 655,
};

/// Node initialization strategy.
pub const Initializer = enum {
    /// Deterministic grid placement. No randomness.
    grid,
    /// Grid with seeded random jitter to break symmetry.
    grid_jitter,
};

// ============================================================================
// Output type
// ============================================================================

/// Result of an FDG layout computation.
///
/// Contains Q16.16 fixed-point positions for each node, indexed by
/// node index (same as `Graph.nodeAt(idx)`). The caller is responsible
/// for converting to their desired coordinate type.
///
/// This type is algorithm-agnostic — FR, SM, and SA all produce it.
pub const PositionResult = struct {
    /// Q16.16 position for each node (indexed by node index).
    positions: []Vec2,

    /// Bounding box width in Q16.16.
    width: FP,
    /// Bounding box height in Q16.16.
    height: FP,

    /// Number of iterations actually performed.
    iterations: u32,

    /// Allocator used (for deinit).
    allocator: Allocator,

    pub fn deinit(self: *PositionResult) void {
        self.allocator.free(self.positions);
    }

    /// Compute bounding box from current positions.
    /// Updates width and height fields.
    pub fn computeBounds(self: *PositionResult) void {
        if (self.positions.len == 0) {
            self.width = fp.ZERO;
            self.height = fp.ZERO;
            return;
        }

        var min_x: FP = fp.MAX;
        var min_y: FP = fp.MAX;
        var max_x: FP = fp.MIN;
        var max_y: FP = fp.MIN;

        for (self.positions) |pos| {
            min_x = fp.min(min_x, pos.x);
            min_y = fp.min(min_y, pos.y);
            max_x = fp.max(max_x, pos.x);
            max_y = fp.max(max_y, pos.y);
        }

        self.width = fp.sub(max_x, min_x);
        self.height = fp.sub(max_y, min_y);
    }

    /// Normalize positions so that the minimum x,y is at (margin, margin)
    /// and positions are non-negative. This prepares positions for
    /// conversion to unsigned coordinate types.
    pub fn normalize(self: *PositionResult, margin: FP) void {
        if (self.positions.len == 0) return;

        var min_x: FP = fp.MAX;
        var min_y: FP = fp.MAX;

        for (self.positions) |pos| {
            min_x = fp.min(min_x, pos.x);
            min_y = fp.min(min_y, pos.y);
        }

        const offset_x = fp.sub(margin, min_x);
        const offset_y = fp.sub(margin, min_y);

        for (self.positions) |*pos| {
            pos.x = fp.add(pos.x, offset_x);
            pos.y = fp.add(pos.y, offset_y);
        }

        self.computeBounds();
    }
};

// ============================================================================
// Initialization strategies
// ============================================================================

/// Initialize node positions on a grid.
///
/// Places nodes on a ceil(sqrt(N)) × ceil(sqrt(N)) grid with the
/// given spacing. Fully deterministic — no randomness.
pub fn initGrid(n: usize, spacing: FP, allocator: Allocator) ![]Vec2 {
    const positions = try allocator.alloc(Vec2, n);
    errdefer allocator.free(positions);

    if (n == 0) return positions;

    const cols = isqrtCeil(n);

    for (0..n) |i| {
        const col: i32 = @intCast(i % cols);
        const row: i32 = @intCast(i / cols);
        positions[i] = Vec2.init(
            fp.mul(fp.fromInt(col), spacing),
            fp.mul(fp.fromInt(row), spacing),
        );
    }

    return positions;
}

/// Initialize node positions on a grid with seeded random jitter.
///
/// Same as `initGrid` but adds a small random displacement to each
/// node to break symmetry. The jitter magnitude is `spacing / 4`.
/// Deterministic for a given seed.
pub fn initGridJitter(n: usize, spacing: FP, seed: u64, allocator: Allocator) ![]Vec2 {
    const positions = try initGrid(n, spacing, allocator);

    const jitter_range = fp.div(spacing, fp.fromInt(4));
    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();

    for (positions) |*pos| {
        // Random value in [-jitter_range, +jitter_range]
        const rx = randomFP(random, jitter_range);
        const ry = randomFP(random, jitter_range);
        pos.x = fp.add(pos.x, rx);
        pos.y = fp.add(pos.y, ry);
    }

    return positions;
}

// ============================================================================
// Helpers
// ============================================================================

/// Ceiling integer square root (for grid dimensions).
fn isqrtCeil(n: usize) usize {
    if (n == 0) return 0;
    var x: usize = 1;
    while (x * x < n) : (x += 1) {}
    return x;
}

/// Generate a random Q16.16 value in [-range, +range].
fn randomFP(random: std.Random, range: FP) FP {
    // Generate uniform random in [0, 2*range], then subtract range
    const double_range: u32 = @intCast(fp.abs(range) * 2);
    if (double_range == 0) return fp.ZERO;
    const raw = random.intRangeAtMost(u32, 0, double_range);
    return @as(FP, @intCast(raw)) - fp.abs(range);
}

/// Check convergence: returns true if the maximum displacement is below threshold.
pub fn isConverged(displacements: []const Vec2, threshold: FP) bool {
    var max_disp: FP = fp.ZERO;
    for (displacements) |d| {
        const len = d.length();
        max_disp = fp.max(max_disp, len);
    }
    return max_disp < threshold;
}

// ============================================================================
// Tests
// ============================================================================

test "initGrid: basic layout" {
    const allocator = std.testing.allocator;
    const positions = try initGrid(4, fp.fromInt(10), allocator);
    defer allocator.free(positions);

    // 4 nodes → 2×2 grid
    try std.testing.expectEqual(@as(usize, 4), positions.len);
    // (0,0), (10,0), (0,10), (10,10)
    try std.testing.expectEqual(fp.ZERO, positions[0].x);
    try std.testing.expectEqual(fp.ZERO, positions[0].y);
    try std.testing.expectEqual(fp.fromInt(10), positions[1].x);
    try std.testing.expectEqual(fp.ZERO, positions[1].y);
    try std.testing.expectEqual(fp.ZERO, positions[2].x);
    try std.testing.expectEqual(fp.fromInt(10), positions[2].y);
    try std.testing.expectEqual(fp.fromInt(10), positions[3].x);
    try std.testing.expectEqual(fp.fromInt(10), positions[3].y);
}

test "initGrid: empty" {
    const allocator = std.testing.allocator;
    const positions = try initGrid(0, fp.fromInt(10), allocator);
    defer allocator.free(positions);
    try std.testing.expectEqual(@as(usize, 0), positions.len);
}

test "initGridJitter: deterministic" {
    const allocator = std.testing.allocator;
    const a = try initGridJitter(10, fp.fromInt(10), 42, allocator);
    defer allocator.free(a);
    const b = try initGridJitter(10, fp.fromInt(10), 42, allocator);
    defer allocator.free(b);

    // Same seed → same positions
    for (a, b) |pa, pb| {
        try std.testing.expectEqual(pa.x, pb.x);
        try std.testing.expectEqual(pa.y, pb.y);
    }
}

test "initGridJitter: different seeds differ" {
    const allocator = std.testing.allocator;
    const a = try initGridJitter(10, fp.fromInt(10), 42, allocator);
    defer allocator.free(a);
    const b = try initGridJitter(10, fp.fromInt(10), 99, allocator);
    defer allocator.free(b);

    var any_differ = false;
    for (a, b) |pa, pb| {
        if (pa.x != pb.x or pa.y != pb.y) {
            any_differ = true;
            break;
        }
    }
    try std.testing.expect(any_differ);
}

test "PositionResult: normalize" {
    const allocator = std.testing.allocator;
    var positions = try allocator.alloc(Vec2, 3);
    positions[0] = Vec2.init(fp.fromInt(-5), fp.fromInt(-3));
    positions[1] = Vec2.init(fp.fromInt(0), fp.fromInt(0));
    positions[2] = Vec2.init(fp.fromInt(10), fp.fromInt(7));

    var result = PositionResult{
        .positions = positions,
        .width = fp.ZERO,
        .height = fp.ZERO,
        .iterations = 0,
        .allocator = allocator,
    };
    defer result.deinit();

    result.normalize(fp.fromInt(1));

    // Min should now be at margin (1)
    try std.testing.expectEqual(fp.fromInt(1), result.positions[0].x);
    try std.testing.expectEqual(fp.fromInt(1), result.positions[0].y);
    // Max should be at 1 + (10 - (-5)) = 16, 1 + (7 - (-3)) = 11
    try std.testing.expectEqual(fp.fromInt(16), result.positions[2].x);
    try std.testing.expectEqual(fp.fromInt(11), result.positions[2].y);
}

test "isConverged" {
    var disps = [_]Vec2{
        Vec2.init(fp.fromFloat(0.005), fp.fromFloat(0.003)),
        Vec2.init(fp.fromFloat(0.001), fp.fromFloat(0.002)),
    };
    try std.testing.expect(isConverged(&disps, fp.fromFloat(0.01)));
    try std.testing.expect(!isConverged(&disps, fp.fromFloat(0.001)));
}
