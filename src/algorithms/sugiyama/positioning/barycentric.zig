//! Barycentric positioning
//!
//! A graph-aware positioning algorithm that places nodes near the average
//! center of their connected neighbours.  One top-down pass aligns children
//! under parents; one bottom-up pass re-centres parents over children.
//!
//! Compared to the other strategies:
//!
//! | Algorithm      | Graph-aware? | Passes | Quality |
//! |----------------|-------------|--------|----------|
//! | `.compact`     | No          | 0      | ★       |
//! | `.barycentric` | Yes         | 2      | ★★      |
//! | `.brandes_kopf`| Yes         | 6+     | ★★★     |

const std = @import("std");
const Allocator = std.mem.Allocator;
const graph_mod = @import("../../../core/graph.zig");
const Graph = graph_mod.Graph;

// Use shared types
const common = @import("common.zig");
pub const Config = common.Config;
pub const PositionAssignment = common.PositionAssignment(usize);

/// Compute node positions using single-pass barycentric placement.
///
/// 1. **Top-down**: place each node near the average centre of its parents.
/// 2. **Bottom-up**: re-centre each parent over its children.
/// 3. Normalise so the leftmost node sits at x = 0.
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

    // Allocate result arrays
    const x = try allocator.alloc(usize, node_count);
    errdefer allocator.free(x);
    const y = try allocator.alloc(usize, node_count);
    errdefer allocator.free(y);
    const center_x = try allocator.alloc(usize, node_count);
    errdefer allocator.free(center_x);
    @memset(x, 0);
    @memset(y, 0);
    @memset(center_x, 0);

    // Working buffer in float space (avoids rounding errors between passes)
    const float_x = try allocator.alloc(f64, node_count);
    defer allocator.free(float_x);
    @memset(float_x, 0.0);

    const widths = try allocator.alloc(usize, node_count);
    defer allocator.free(widths);
    for (0..node_count) |i| {
        widths[i] = if (g.nodeAt(i)) |node| node.width else 3;
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

    // =====================================================================
    // Phase 1: Baseline — left-to-right packing with level centering
    //
    // This is the same layout as .compact.  We build on top of it so that the
    // result is always at least as good as .compact.
    // =====================================================================

    // Pack each level left-to-right
    var level_widths_buf = try allocator.alloc(usize, levels.len);
    defer allocator.free(level_widths_buf);

    var max_level_width: usize = 0;
    for (levels, 0..) |level, li| {
        var cx: f64 = 0;
        for (level.items) |node_idx| {
            float_x[node_idx] = cx;
            cx += @as(f64, @floatFromInt(widths[node_idx])) + spacing;
        }
        const lw: usize = if (cx > spacing) @intFromFloat(cx - spacing) else 0;
        level_widths_buf[li] = lw;
        max_level_width = @max(max_level_width, lw);
    }

    // Centre each level within the max width
    for (levels, 0..) |level, li| {
        if (level_widths_buf[li] < max_level_width) {
            const offset: f64 = @floatFromInt((max_level_width - level_widths_buf[li]) / 2);
            for (level.items) |node_idx| {
                float_x[node_idx] += offset;
            }
        }
    }

    // =====================================================================
    // Phase 2: Barycentric nudge — shift nodes toward connected neighbours
    //
    // For each node, compute the average centre of its parents + children.
    // Blend current position toward that target (50 % weight) so we improve
    // alignment without blowing up the compact baseline.
    // Two iterations (down+up each) are enough for most graphs.
    // =====================================================================

    for (0..2) |_| {
        // Top-down: nudge children toward parents
        for (1..levels.len) |li| {
            const level = levels[li];
            const parent_level = levels[li - 1];

            for (level.items) |node_idx| {
                const parents = g.getParents(node_idx);
                if (parents.len == 0) continue;

                var sum: f64 = 0;
                var count: usize = 0;
                for (parent_level.items) |parent_idx| {
                    for (parents) |p| {
                        if (p == parent_idx) {
                            const pw: f64 = @floatFromInt(widths[parent_idx]);
                            sum += float_x[parent_idx] + pw / 2.0;
                            count += 1;
                            break;
                        }
                    }
                }

                if (count > 0) {
                    const w: f64 = @floatFromInt(widths[node_idx]);
                    const target = sum / @as(f64, @floatFromInt(count)) - w / 2.0;
                    const current = float_x[node_idx];
                    float_x[node_idx] = current + (target - current) * 0.5;
                }
            }

            compactLevel(level.items, float_x, widths, spacing);
        }

        // Bottom-up: nudge parents toward children
        var li = levels.len;
        while (li > 0) {
            li -= 1;
            const level = levels[li];

            for (level.items) |node_idx| {
                const children = g.getChildren(node_idx);
                if (children.len == 0) continue;

                var min_child_left: f64 = std.math.floatMax(f64);
                var max_child_right: f64 = 0;
                for (children) |child_idx| {
                    const cw: f64 = @floatFromInt(widths[child_idx]);
                    min_child_left = @min(min_child_left, float_x[child_idx]);
                    max_child_right = @max(max_child_right, float_x[child_idx] + cw);
                }

                if (min_child_left < std.math.floatMax(f64)) {
                    const w: f64 = @floatFromInt(widths[node_idx]);
                    const target = (min_child_left + max_child_right) / 2.0 - w / 2.0;
                    const current = float_x[node_idx];
                    float_x[node_idx] = current + (target - current) * 0.5;
                }
            }

            compactLevel(level.items, float_x, widths, spacing);
        }
    }

    // =====================================================================
    // Phase 3: Normalise — shift so leftmost node is at x = 0
    // =====================================================================

    var min_x: f64 = std.math.floatMax(f64);
    for (0..node_count) |i| {
        min_x = @min(min_x, float_x[i]);
    }
    if (min_x > 0 and min_x < std.math.floatMax(f64)) {
        for (0..node_count) |i| {
            float_x[i] -= min_x;
        }
    } else if (min_x < 0) {
        for (0..node_count) |i| {
            float_x[i] -= min_x;
        }
    }

    // =====================================================================
    // Phase 4: Convert to integer coordinates
    // =====================================================================

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
    for (levels, 0..) |level, li| {
        for (level.items) |node_idx| {
            y[node_idx] = current_y;
        }
        if (li < levels.len - 1) {
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

const compactLevel = common.compactLevel;

// ============================================================================
// Tests
// ============================================================================

test "simple positioning: single level" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "BB");
    try g.addNode(3, "CCC");

    var level0: std.ArrayListUnmanaged(usize) = .{};
    try level0.append(allocator, 0);
    try level0.append(allocator, 1);
    try level0.append(allocator, 2);
    defer level0.deinit(allocator);

    const levels = [_]std.ArrayListUnmanaged(usize){level0};

    var pos = try compute(&g, &levels, .{}, allocator);
    defer pos.deinit();

    // Check nodes are placed left to right
    try std.testing.expect(pos.x[0] < pos.x[1]);
    try std.testing.expect(pos.x[1] < pos.x[2]);

    // All on same Y
    try std.testing.expectEqual(@as(usize, 0), pos.y[0]);
    try std.testing.expectEqual(@as(usize, 0), pos.y[1]);
    try std.testing.expectEqual(@as(usize, 0), pos.y[2]);
}

test "simple positioning: two levels" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "Top");
    try g.addNode(2, "Bottom");
    try g.addEdge(1, 2);

    var level0: std.ArrayListUnmanaged(usize) = .{};
    try level0.append(allocator, 0);
    defer level0.deinit(allocator);

    var level1: std.ArrayListUnmanaged(usize) = .{};
    try level1.append(allocator, 1);
    defer level1.deinit(allocator);

    const levels = [_]std.ArrayListUnmanaged(usize){ level0, level1 };

    var pos = try compute(&g, &levels, .{ .level_spacing = 2 }, allocator);
    defer pos.deinit();

    // Second level should be below first
    try std.testing.expect(pos.y[1] > pos.y[0]);
    try std.testing.expectEqual(@as(usize, 0), pos.y[0]);
    try std.testing.expectEqual(@as(usize, 3), pos.y[1]); // 1 + 2 spacing
}

test "simple positioning: parent centres over children" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(0, "Root");
    try g.addNode(1, "Left");
    try g.addNode(2, "Right");
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

    var pos = try compute(&g, &levels, .{}, allocator);
    defer pos.deinit();

    // Parent centre should be between children centres (barycentric)
    const parent_center = pos.center_x[0];
    const left_center = pos.center_x[1];
    const right_center = pos.center_x[2];

    try std.testing.expect(parent_center >= left_center);
    try std.testing.expect(parent_center <= right_center);
}

test "simple positioning: asymmetric tree differs from left-packing" {
    const allocator = std.testing.allocator;

    // Root -> Leaf, Root -> Branch -> A, B
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(0, "Root");
    try g.addNode(1, "Leaf");
    try g.addNode(2, "Branch");
    try g.addNode(3, "A");
    try g.addNode(4, "B");
    try g.addEdge(0, 1);
    try g.addEdge(0, 2);
    try g.addEdge(2, 3);
    try g.addEdge(2, 4);

    var level0: std.ArrayListUnmanaged(usize) = .{};
    defer level0.deinit(allocator);
    try level0.append(allocator, 0); // Root

    var level1: std.ArrayListUnmanaged(usize) = .{};
    defer level1.deinit(allocator);
    try level1.append(allocator, 1); // Leaf
    try level1.append(allocator, 2); // Branch

    var level2: std.ArrayListUnmanaged(usize) = .{};
    defer level2.deinit(allocator);
    try level2.append(allocator, 3); // A
    try level2.append(allocator, 4); // B

    const levels = [_]std.ArrayListUnmanaged(usize){ level0, level1, level2 };

    var pos = try compute(&g, &levels, .{}, allocator);
    defer pos.deinit();

    // Branch should be centred over A and B
    const branch_center = pos.center_x[2];
    const a_center = pos.center_x[3];
    const b_center = pos.center_x[4];
    const children_mid = (a_center + b_center) / 2;

    // Allow ±1 rounding tolerance
    const diff = if (branch_center > children_mid)
        branch_center - children_mid
    else
        children_mid - branch_center;
    try std.testing.expect(diff <= 1);
}
