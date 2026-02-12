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
const graph_mod = @import("../../../core/graph.zig");
const Graph = graph_mod.Graph;

// Use shared types
const common = @import("common.zig");
pub const Config = common.Config;
pub const PositionAssignment = common.PositionAssignment(usize);

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
    // Phase 1: Initial placement from the widest level
    //
    // Place the widest level left-to-right, then work outward in both
    // directions: upward (centering parents over children) and downward
    // (centering children under parents).  This avoids the bias that
    // bottom-up-only or top-down-only placement creates on fan-in/out
    // graphs.
    // =========================================================================

    // Find the widest level (most nodes)
    var widest_level_idx: usize = 0;
    var widest_count: usize = 0;
    for (levels, 0..) |level, li| {
        if (level.items.len > widest_count) {
            widest_count = level.items.len;
            widest_level_idx = li;
        }
    }

    // Place the widest level left-to-right
    {
        var cx: f64 = 0;
        for (levels[widest_level_idx].items) |node_idx| {
            float_x[node_idx] = cx;
            cx += @as(f64, @floatFromInt(widths[node_idx])) + spacing;
        }
    }

    // Work upward from widest: center each parent over its children
    if (widest_level_idx > 0) {
        var level_idx = widest_level_idx;
        while (level_idx > 0) {
            level_idx -= 1;
            const level = levels[level_idx];
            const child_level = levels[level_idx + 1];

            for (level.items) |node_idx| {
                const children = g.getChildren(node_idx);
                const w: f64 = @floatFromInt(widths[node_idx]);

                if (children.len > 0) {
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
                        const children_center = (min_child_left + max_child_right) / 2.0;
                        float_x[node_idx] = children_center - w / 2.0;
                    }
                }
            }

            compactLevel(level.items, float_x, widths, spacing);
        }
    }

    // Work downward from widest: center each child under its parents
    if (widest_level_idx + 1 < levels.len) {
        for ((widest_level_idx + 1)..levels.len) |level_idx| {
            const level = levels[level_idx];
            const parent_level = levels[level_idx - 1];

            for (level.items) |node_idx| {
                const parents = g.getParents(node_idx);
                if (parents.len == 0) continue;

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
                    float_x[node_idx] = parent_center - w / 2.0;
                }
            }

            compactLevel(level.items, float_x, widths, spacing);
        }
    }

    // =========================================================================
    // Phase 2: Iterative refinement
    // Nudge nodes toward their connected neighbours (50% blend per pass)
    // to converge on balanced positions without destroying Phase 1 layout.
    // =========================================================================

    for (0..3) |_| {
        // Top-down pass: nudge children toward parent centres
        for (levels, 0..) |level, level_idx| {
            if (level_idx == 0) continue;

            const parent_level = levels[level_idx - 1];

            for (level.items) |node_idx| {
                const parents = g.getParents(node_idx);
                if (parents.len == 0) continue;

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
                    const target = parent_center_sum / @as(f64, @floatFromInt(parent_count)) - w / 2.0;
                    const current = float_x[node_idx];
                    float_x[node_idx] = current + (target - current) * 0.5;
                }
            }

            compactLevel(level.items, float_x, widths, spacing);
        }

        // Bottom-up pass: nudge parents toward child span centres
        // Filter children to the adjacent level to avoid cross-level pull.
        var level_idx = levels.len;
        while (level_idx > 0) {
            level_idx -= 1;
            const level = levels[level_idx];

            if (level_idx + 1 >= levels.len) {
                // Bottom level — no children level to inspect
                continue;
            }
            const child_level = levels[level_idx + 1];

            for (level.items) |node_idx| {
                const children = g.getChildren(node_idx);
                if (children.len == 0) continue;

                const w: f64 = @floatFromInt(widths[node_idx]);

                // Find span of children that are actually in the next level
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
                    const children_center = (min_child_left + max_child_right) / 2.0;
                    const target = children_center - w / 2.0;
                    const current = float_x[node_idx];
                    float_x[node_idx] = current + (target - current) * 0.5;
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

/// Ensure nodes in a level don't overlap, maintaining their order.
///
/// Uses symmetric (bidirectional) compaction: a forward pass pushes right,
/// a backward pass pushes left, and the average gives a balanced result
/// that avoids systematic left- or right-bias.
fn compactLevel(nodes: []const usize, float_x: []f64, widths: []const usize, spacing: f64) void {
    if (nodes.len == 0) return;

    // --- Forward pass: push right to fix overlaps (same as before) ---
    var prev_right: f64 = 0;
    for (nodes, 0..) |node_idx, pos| {
        const w: f64 = @floatFromInt(widths[node_idx]);
        if (pos == 0) {
            if (float_x[node_idx] < 0) float_x[node_idx] = 0;
        } else {
            const min_x = prev_right + spacing;
            if (float_x[node_idx] < min_x) {
                float_x[node_idx] = min_x;
            }
        }
        prev_right = float_x[node_idx] + w;
    }

    // --- Backward pass: push left from the right edge ---
    // Use the rightmost position from the forward pass as the boundary.
    const right_edge = prev_right;
    var next_left: f64 = right_edge;
    var i: usize = nodes.len;
    while (i > 0) {
        i -= 1;
        const node_idx = nodes[i];
        const w: f64 = @floatFromInt(widths[node_idx]);
        const max_x = next_left - w;
        if (float_x[node_idx] > max_x) {
            float_x[node_idx] = max_x;
        }
        next_left = float_x[node_idx] - spacing;
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
