//! Crossing Reduction Pipeline
//!
//! Provides a pluggable system for crossing reduction algorithms.
//! Users can compose sequences of reducers, use presets, or bring their own.
//!
//! ## Usage
//!
//! ```zig
//! const crossing = @import("zigraph").crossing;
//!
//! // Use a preset
//! .crossing_reducers = &crossing.balanced,
//!
//! // Custom sequence
//! .crossing_reducers = &[_]crossing.Reducer{
//!     crossing.median(4),
//!     crossing.adjacentExchange(2),
//! },
//!
//! // Bring your own algorithm
//! .crossing_reducers = &[_]crossing.Reducer{
//!     crossing.median(4),
//!     .{ .runFn = myCustomReducer, .passes = 10 },
//! },
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;
const graph_mod = @import("../../core/graph.zig");
const Graph = graph_mod.Graph;
const virtual_mod = @import("../layering/virtual.zig");
const VirtualLevels = virtual_mod.VirtualLevels;

const median_mod = @import("median.zig");
const adjacent_exchange_mod = @import("adjacent_exchange.zig");

/// A crossing reduction step that can be composed into a pipeline.
///
/// Each reducer receives access to its own configuration via `self`,
/// allowing algorithms to be parameterized and reusable.
pub const Reducer = struct {
    /// The reduction function.
    /// Receives self to access passes and context.
    runFn: *const fn (
        self: *const Reducer,
        levels: *VirtualLevels,
        g: *const Graph,
        allocator: Allocator,
    ) anyerror!void,

    /// Number of passes (interpretation is algorithm-specific).
    /// For median: number of up/down sweep pairs.
    /// For adjacent exchange: number of full refinement rounds.
    passes: usize = 1,

    /// Optional context pointer for custom reducers.
    /// Use @ptrCast and @alignCast to recover your config type.
    context: ?*const anyopaque = null,

    /// Execute this reducer.
    pub fn run(self: *const Reducer, levels: *VirtualLevels, g: *const Graph, allocator: Allocator) !void {
        return self.runFn(self, levels, g, allocator);
    }
};

// ============================================================================
// Built-in Reducer Factories
// ============================================================================

/// Create a median heuristic reducer.
///
/// The median heuristic orders nodes by the median position of their
/// neighbors in the adjacent (fixed) layer. Very effective for most graphs.
///
/// Passes: number of up/down sweep pairs. More passes = potentially fewer crossings.
pub fn median(passes: usize) Reducer {
    return .{
        .runFn = medianRun,
        .passes = passes,
    };
}

/// Create an adjacent exchange reducer.
///
/// Swaps adjacent nodes when it reduces crossings. Best used as a
/// refinement step after median. Skips large layers (>20 nodes) for performance.
///
/// Passes: number of full refinement rounds over all layers.
pub fn adjacentExchange(passes: usize) Reducer {
    return .{
        .runFn = adjacentExchangeRun,
        .passes = passes,
    };
}

// ============================================================================
// Built-in Runner Implementations
// ============================================================================

fn medianRun(self: *const Reducer, levels: *VirtualLevels, g: *const Graph, allocator: Allocator) !void {
    try median_mod.reduceVirtual(g, levels, self.passes, allocator);
}

fn adjacentExchangeRun(self: *const Reducer, levels: *VirtualLevels, g: *const Graph, _: Allocator) !void {
    adjacent_exchange_mod.refine(g, levels, self.passes);
}

// ============================================================================
// Presets
// ============================================================================

/// Fast preset: minimal crossing reduction for quick layouts.
/// Good for previews or when layout speed is critical.
pub const fast = [_]Reducer{
    median(2),
};

/// Balanced preset: good quality with reasonable performance.
/// Default for most use cases.
pub const balanced = [_]Reducer{
    median(4),
    adjacentExchange(2),
};

/// Quality preset: more passes for better crossing reduction.
/// Use when visual quality is more important than speed.
pub const quality = [_]Reducer{
    median(8),
    adjacentExchange(4),
    median(2), // polish pass
};

/// No crossing reduction. Nodes stay in insertion order.
/// Useful for debugging or when order is already optimal.
pub const none = [_]Reducer{};

// ============================================================================
// Pipeline Runner
// ============================================================================

/// Reducer validation errors (WDP compliant)
pub const ReducerError = error{
    /// Reducer corrupted level structure [E.Layout.Reducer.003 = INVALID]
    ReducerCorruptedLevels,
    /// Reducer changed node count in level [E.Layout.Reducer.002 = MISMATCH]
    ReducerCorruptedNodeCount,
    /// Reducer created duplicate node [E.Layout.Reducer.007 = DUPLICATE]
    ReducerDuplicateNode,
    /// Reducer lost a node [E.Layout.Reducer.001 = MISSING]
    ReducerMissingNode,
};

/// Snapshot of VirtualLevels state for validation.
/// Used to verify reducers don't corrupt the level structure.
const LevelSnapshot = struct {
    level_count: usize,
    level_sizes: [64]usize, // Support up to 64 levels
    total_nodes: usize,

    fn capture(levels: *const VirtualLevels) LevelSnapshot {
        var snapshot = LevelSnapshot{
            .level_count = levels.levels.items.len,
            .level_sizes = [_]usize{0} ** 64,
            .total_nodes = 0,
        };

        for (levels.levels.items, 0..) |level, i| {
            if (i < 64) {
                snapshot.level_sizes[i] = level.items.len;
                snapshot.total_nodes += level.items.len;
            }
        }

        return snapshot;
    }

    /// Validate that levels match the snapshot (same structure, possibly reordered).
    fn validate(self: *const LevelSnapshot, levels: *const VirtualLevels) ReducerError!void {
        // Check level count unchanged
        if (levels.levels.items.len != self.level_count) {
            return error.ReducerCorruptedLevels;
        }

        // Check each level has same node count (order may differ)
        var current_total: usize = 0;
        for (levels.levels.items, 0..) |level, i| {
            if (i < 64) {
                if (level.items.len != self.level_sizes[i]) {
                    return error.ReducerCorruptedNodeCount;
                }
                current_total += level.items.len;
            }
        }

        // Check total node count
        if (current_total != self.total_nodes) {
            return error.ReducerMissingNode;
        }
    }
};

/// Run a sequence of crossing reducers with validation.
///
/// After each reducer runs, validates that the VirtualLevels structure
/// is intact (same levels, same nodes per level). Reducers may only
/// reorder nodes within levels, not add/remove/move nodes between levels.
///
/// Returns WDP-compliant errors if a reducer corrupts the structure:
/// - ReducerCorruptedLevels [E.Layout.Reducer.003 = INVALID]: Level count changed
/// - ReducerCorruptedNodeCount [E.Layout.Reducer.002 = MISMATCH]: Node count in level changed
/// - ReducerMissingNode [E.Layout.Reducer.001 = MISSING]: Total node count decreased
pub fn runPipeline(
    reducers: []const Reducer,
    levels: *VirtualLevels,
    g: *const Graph,
    allocator: Allocator,
) !void {
    for (reducers) |*reducer| {
        // Capture state before reducer runs
        const snapshot = LevelSnapshot.capture(levels);

        // Run the reducer
        try reducer.run(levels, g, allocator);

        // Validate state after reducer (debug builds only for performance)
        if (std.debug.runtime_safety) {
            try snapshot.validate(levels);
        }
    }
}

// ============================================================================
// Tests
// ============================================================================

test "reducer factory creates valid reducers" {
    const m = median(4);
    try std.testing.expectEqual(@as(usize, 4), m.passes);
    try std.testing.expect(m.runFn == medianRun);

    const ae = adjacentExchange(2);
    try std.testing.expectEqual(@as(usize, 2), ae.passes);
    try std.testing.expect(ae.runFn == adjacentExchangeRun);
}

test "presets have expected lengths" {
    try std.testing.expectEqual(@as(usize, 1), fast.len);
    try std.testing.expectEqual(@as(usize, 2), balanced.len);
    try std.testing.expectEqual(@as(usize, 3), quality.len);
    try std.testing.expectEqual(@as(usize, 0), none.len);
}

test "LevelSnapshot validation detects level corruption" {
    const allocator = std.testing.allocator;

    // Create mock VirtualLevels structure manually
    var levels = VirtualLevels{
        .levels = .{},
        .allocator = allocator,
    };
    defer levels.deinit();

    // Add two levels with 2 and 3 nodes respectively
    try levels.levels.append(allocator, .{});
    try levels.levels.append(allocator, .{});
    try levels.levels.items[0].append(allocator, .{ .real = 0 });
    try levels.levels.items[0].append(allocator, .{ .real = 1 });
    try levels.levels.items[1].append(allocator, .{ .real = 2 });
    try levels.levels.items[1].append(allocator, .{ .real = 3 });
    try levels.levels.items[1].append(allocator, .{ .real = 4 });

    // Capture snapshot
    const snapshot = LevelSnapshot.capture(&levels);

    // Unchanged levels should validate
    try snapshot.validate(&levels);
    try std.testing.expectEqual(@as(usize, 2), snapshot.level_count);
    try std.testing.expectEqual(@as(usize, 5), snapshot.total_nodes);
    try std.testing.expectEqual(@as(usize, 2), snapshot.level_sizes[0]);
    try std.testing.expectEqual(@as(usize, 3), snapshot.level_sizes[1]);

    // Add an extra level - should detect corruption
    try levels.levels.append(allocator, .{});
    try std.testing.expectError(error.ReducerCorruptedLevels, snapshot.validate(&levels));

    // Remove the extra level, but change node count in level 1
    _ = levels.levels.pop();
    _ = levels.levels.items[1].pop();
    try std.testing.expectError(error.ReducerCorruptedNodeCount, snapshot.validate(&levels));
}
