//! Simple left-to-right positioning
//!
//! Assigns x-coordinates to nodes by packing left-to-right
//! with fixed spacing. This is the simplest positioning algorithm.
//!
//! ## Algorithm
//!
//! For each level:
//! 1. Calculate total width of nodes + spacing
//! 2. Center the level horizontally
//! 3. Assign x-coordinates left to right

const std = @import("std");
const Allocator = std.mem.Allocator;
const graph_mod = @import("../../core/graph.zig");
const Graph = graph_mod.Graph;

// Use shared types
const common = @import("common.zig");
pub const Config = common.Config;
pub const PositionAssignment = common.PositionAssignment(usize);

/// Compute node positions using simple left-to-right packing.
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

    // Allocate position arrays
    const x = try allocator.alloc(usize, node_count);
    const y = try allocator.alloc(usize, node_count);
    const center_x = try allocator.alloc(usize, node_count);
    @memset(x, 0);
    @memset(y, 0);
    @memset(center_x, 0);

    // Calculate width of each level
    var level_widths = try allocator.alloc(usize, levels.len);
    defer allocator.free(level_widths);

    var max_width: usize = 0;
    for (levels, 0..) |level, level_idx| {
        var width: usize = 0;
        for (level.items, 0..) |node_idx, pos| {
            const node = g.nodeAt(node_idx) orelse continue;
            if (pos > 0) {
                width += config.node_spacing;
            }
            width += node.width;
        }
        level_widths[level_idx] = width;
        max_width = @max(max_width, width);
    }

    // Assign positions
    var current_y: usize = 0;
    for (levels, 0..) |level, level_idx| {
        // Center this level
        const level_width = level_widths[level_idx];
        const offset = (max_width - level_width) / 2;

        var current_x = offset;
        for (level.items) |node_idx| {
            const node = g.nodeAt(node_idx) orelse continue;

            x[node_idx] = current_x;
            y[node_idx] = current_y;
            center_x[node_idx] = current_x + node.width / 2;

            current_x += node.width + config.node_spacing;
        }

        // Move to next level
        if (level_idx < levels.len - 1) {
            current_y += 1 + config.level_spacing; // 1 for node height
        }
    }

    // Calculate total dimensions
    // Node height = 1 line
    const total_height = if (levels.len > 0)
        current_y + 1 // Last level + node height
    else
        0;

    return .{
        .x = x,
        .y = y,
        .center_x = center_x,
        .total_width = max_width,
        .total_height = total_height,
        .allocator = allocator,
    };
}

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

test "simple positioning: centering" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "Wide Node Here");
    try g.addNode(2, "X");
    try g.addEdge(1, 2);

    var level0: std.ArrayListUnmanaged(usize) = .{};
    try level0.append(allocator, 0);
    defer level0.deinit(allocator);

    var level1: std.ArrayListUnmanaged(usize) = .{};
    try level1.append(allocator, 1);
    defer level1.deinit(allocator);

    const levels = [_]std.ArrayListUnmanaged(usize){ level0, level1 };

    var pos = try compute(&g, &levels, .{}, allocator);
    defer pos.deinit();

    // Narrow node should be centered under wide node
    const wide_center = pos.center_x[0];
    const narrow_center = pos.center_x[1];

    // Centers should be close (within a few chars due to centering)
    const diff = if (wide_center > narrow_center)
        wide_center - narrow_center
    else
        narrow_center - wide_center;

    try std.testing.expect(diff <= 1); // Should be well-centered
}
