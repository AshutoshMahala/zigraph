//! Brandes-Köpf positioning algorithm
//!
//! A high-quality positioning algorithm that produces balanced layouts
//! by centering parents over their children (or children under parents).
//!
//! ## Algorithm Overview
//!
//! 1. Place leaf nodes (bottom level) left-to-right
//! 2. Work upward, centering each parent over its children
//! 3. Work downward, shifting children to reduce edge lengths
//! 4. Iterate to converge on a balanced layout
//!
//! ## References
//!
//! Brandes, U. & Köpf, B. (2001). "Fast and Simple Horizontal Coordinate Assignment"

const std = @import("std");
const Allocator = std.mem.Allocator;
const graph_mod = @import("../../core/graph.zig");
const Graph = graph_mod.Graph;

// Use shared types
const common = @import("common.zig");
pub const Config = common.Config;
pub const PositionAssignment = common.PositionAssignment;

/// Compute node positions using Brandes-Köpf algorithm.
pub fn compute(
    g: *const Graph,
    levels: []const std.ArrayListUnmanaged(usize),
    config: Config,
    allocator: Allocator,
) !PositionAssignment {
    const node_count = g.nodeCount();

    if (node_count == 0) {
        return .{
            .x = &.{},
            .y = &.{},
            .center_x = &.{},
            .total_width = 0,
            .total_height = 0,
            .allocator = allocator,
        };
    }

    const x = try allocator.alloc(usize, node_count);
    errdefer allocator.free(x);
    const y = try allocator.alloc(usize, node_count);
    errdefer allocator.free(y);
    const center_x = try allocator.alloc(usize, node_count);
    errdefer allocator.free(center_x);

    @memset(x, 0);
    @memset(y, 0);
    @memset(center_x, 0);

    const float_x = try allocator.alloc(f64, node_count);
    defer allocator.free(float_x);
    @memset(float_x, 0.0);

    const widths = try allocator.alloc(usize, node_count);
    defer allocator.free(widths);
    for (0..node_count) |i| {
        if (g.nodeAt(i)) |node| {
            widths[i] = node.width;
        } else {
            widths[i] = 3;
        }
    }

    const spacing: f64 = @floatFromInt(config.node_spacing);

    if (levels.len == 0) {
        return .{
            .x = x,
            .y = y,
            .center_x = center_x,
            .total_width = 0,
            .total_height = 0,
            .allocator = allocator,
        };
    }

    // =========================================================================
    // Phase 1: Initial bottom-up placement
    // Start from the deepest level and work up, centering parents over children
    // =========================================================================

    // First, place the bottom level left-to-right
    const bottom_level = levels[levels.len - 1];
    var current_x: f64 = 0;
    for (bottom_level.items) |node_idx| {
        float_x[node_idx] = current_x;
        const w: f64 = @floatFromInt(widths[node_idx]);
        current_x += w + spacing;
    }

    // Work upward: center each parent over its children
    if (levels.len > 1) {
        var level_idx = levels.len - 1;
        while (level_idx > 0) {
            level_idx -= 1;
            const level = levels[level_idx];
            const child_level = levels[level_idx + 1];

            // For each node in this level, compute its ideal position
            for (level.items) |node_idx| {
                const children = g.getChildren(node_idx);
                const w: f64 = @floatFromInt(widths[node_idx]);

                if (children.len > 0) {
                    // Find children that are in the next level
                    var min_child_left: f64 = std.math.floatMax(f64);
                    var max_child_right: f64 = 0;
                    var found_children: usize = 0;

                    for (child_level.items) |child_idx| {
                        for (children) |c| {
                            if (c == child_idx) {
                                const cw: f64 = @floatFromInt(widths[child_idx]);
                                min_child_left = @min(min_child_left, float_x[child_idx]);
                                max_child_right = @max(max_child_right, float_x[child_idx] + cw);
                                found_children += 1;
                                break;
                            }
                        }
                    }

                    if (found_children > 0) {
                        // Center over children
                        const children_center = (min_child_left + max_child_right) / 2.0;
                        float_x[node_idx] = children_center - w / 2.0;
                    }
                }
            }

            // Ensure no overlaps within this level
            compactLevel(level.items, float_x, widths, spacing);
        }
    }

    // =========================================================================
    // Phase 2: Top-down refinement
    // Push children toward their parent centers
    // =========================================================================

    for (0..3) |_| {
        // Top-down pass
        for (levels, 0..) |level, level_idx| {
            if (level_idx == 0) continue;

            const parent_level = levels[level_idx - 1];

            for (level.items) |node_idx| {
                const parents = g.getParents(node_idx);
                if (parents.len == 0) continue;

                // Find the center of parents
                var parent_center_sum: f64 = 0;
                var parent_count: usize = 0;

                for (parent_level.items) |parent_idx| {
                    for (parents) |p| {
                        if (p == parent_idx) {
                            const pw: f64 = @floatFromInt(widths[parent_idx]);
                            parent_center_sum += float_x[parent_idx] + pw / 2.0;
                            parent_count += 1;
                            break;
                        }
                    }
                }

                if (parent_count > 0) {
                    const w: f64 = @floatFromInt(widths[node_idx]);
                    const parent_center = parent_center_sum / @as(f64, @floatFromInt(parent_count));
                    const current_center = float_x[node_idx] + w / 2.0;

                    // If parent is to the right, shift right (always ok)
                    // If parent is to the left, we can shift left only if space allows
                    const shift = parent_center - current_center;
                    if (shift > 0) {
                        float_x[node_idx] += shift;
                    }
                }
            }

            // Compact to fix overlaps
            compactLevel(level.items, float_x, widths, spacing);
        }

        // Bottom-up pass to re-center parents
        var level_idx = levels.len;
        while (level_idx > 0) {
            level_idx -= 1;
            const level = levels[level_idx];

            for (level.items) |node_idx| {
                const children = g.getChildren(node_idx);
                if (children.len == 0) continue;

                const w: f64 = @floatFromInt(widths[node_idx]);

                // Find span of children
                var min_child_left: f64 = std.math.floatMax(f64);
                var max_child_right: f64 = 0;

                for (children) |child_idx| {
                    const cw: f64 = @floatFromInt(widths[child_idx]);
                    min_child_left = @min(min_child_left, float_x[child_idx]);
                    max_child_right = @max(max_child_right, float_x[child_idx] + cw);
                }

                if (min_child_left < std.math.floatMax(f64)) {
                    const children_center = (min_child_left + max_child_right) / 2.0;
                    const ideal_x = children_center - w / 2.0;

                    // Only shift right (to center over children that moved right)
                    if (ideal_x > float_x[node_idx]) {
                        float_x[node_idx] = ideal_x;
                    }
                }
            }

            compactLevel(level.items, float_x, widths, spacing);
        }
    }

    // =========================================================================
    // Phase 3: Normalize - shift everything so leftmost is at 0
    // =========================================================================

    var min_x: f64 = std.math.floatMax(f64);
    var max_x: f64 = 0;
    for (0..node_count) |i| {
        min_x = @min(min_x, float_x[i]);
        const w: f64 = @floatFromInt(widths[i]);
        max_x = @max(max_x, float_x[i] + w);
    }
    if (min_x > 0 and min_x < std.math.floatMax(f64)) {
        for (0..node_count) |i| {
            float_x[i] -= min_x;
        }
        max_x -= min_x;
    }

    // =========================================================================
    // Phase 3.5: Center levels within the overall width
    // This reduces left-bias from bottom-up placement
    // =========================================================================

    for (levels) |level| {
        if (level.items.len == 0) continue;

        // Find this level's extent
        var level_min: f64 = std.math.floatMax(f64);
        var level_max: f64 = 0;
        for (level.items) |node_idx| {
            level_min = @min(level_min, float_x[node_idx]);
            const w: f64 = @floatFromInt(widths[node_idx]);
            level_max = @max(level_max, float_x[node_idx] + w);
        }

        // Shift this level to center it within max_x
        const level_width = level_max - level_min;
        const ideal_left = (max_x - level_width) / 2.0;
        const shift = ideal_left - level_min;

        // Center levels that have significant empty space on the left
        // (shift > 2 means there's at least 2 units of potential centering)
        if (shift > 2.0) {
            for (level.items) |node_idx| {
                float_x[node_idx] += shift;
            }
        }
    }

    // =========================================================================
    // Phase 4: Convert to integers
    // =========================================================================

    var max_width: usize = 0;
    for (levels) |level| {
        var level_right: usize = 0;
        for (level.items) |node_idx| {
            const fx = float_x[node_idx];
            const ix: usize = @intFromFloat(@max(0, @round(fx)));
            x[node_idx] = ix;
            center_x[node_idx] = ix + widths[node_idx] / 2;
            level_right = @max(level_right, ix + widths[node_idx]);
        }
        max_width = @max(max_width, level_right);
    }

    // Y coordinates
    var current_y: usize = 0;
    for (levels, 0..) |level, level_idx| {
        for (level.items) |node_idx| {
            y[node_idx] = current_y;
        }
        if (level_idx < levels.len - 1) {
            current_y += 1 + config.level_spacing;
        }
    }

    const total_height = if (levels.len > 0) current_y + 1 else 0;

    return .{
        .x = x,
        .y = y,
        .center_x = center_x,
        .total_width = max_width,
        .total_height = total_height,
        .allocator = allocator,
    };
}

/// Ensure nodes in a level don't overlap, maintaining their order
fn compactLevel(nodes: []const usize, float_x: []f64, widths: []const usize, spacing: f64) void {
    var prev_right: f64 = 0;
    for (nodes, 0..) |node_idx, pos| {
        const w: f64 = @floatFromInt(widths[node_idx]);

        if (pos == 0) {
            // First node: ensure non-negative
            if (float_x[node_idx] < 0) {
                float_x[node_idx] = 0;
            }
        } else {
            // Ensure spacing from previous node
            const min_x = prev_right + spacing;
            if (float_x[node_idx] < min_x) {
                float_x[node_idx] = min_x;
            }
        }

        prev_right = float_x[node_idx] + w;
    }
}

// ============================================================================
// Tests
// ============================================================================

test "brandes_kopf: empty graph" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    const levels = [_]std.ArrayListUnmanaged(usize){};
    var result = try compute(&g, &levels, .{}, allocator);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 0), result.total_width);
}

test "brandes_kopf: single node" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "Test");

    var level0: std.ArrayListUnmanaged(usize) = .{};
    defer level0.deinit(allocator);
    try level0.append(allocator, 0);

    const levels = [_]std.ArrayListUnmanaged(usize){level0};
    var result = try compute(&g, &levels, .{}, allocator);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 0), result.x[0]);
}

test "brandes_kopf: binary tree centering" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(0, "R");
    try g.addNode(1, "L");
    try g.addNode(2, "R");
    try g.addEdge(0, 1);
    try g.addEdge(0, 2);

    var level0: std.ArrayListUnmanaged(usize) = .{};
    defer level0.deinit(allocator);
    try level0.append(allocator, 0);

    var level1: std.ArrayListUnmanaged(usize) = .{};
    defer level1.deinit(allocator);
    try level1.append(allocator, 1);
    try level1.append(allocator, 2);

    const levels = [_]std.ArrayListUnmanaged(usize){ level0, level1 };
    var result = try compute(&g, &levels, .{}, allocator);
    defer result.deinit();

    // Parent center should be between children centers
    const parent_center = result.center_x[0];
    const left_center = result.center_x[1];
    const right_center = result.center_x[2];

    try std.testing.expect(parent_center >= left_center);
    try std.testing.expect(parent_center <= right_center);
}
