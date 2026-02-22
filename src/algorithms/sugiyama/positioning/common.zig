//! Common positioning types
//!
//! Shared types used by all positioning algorithms.

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Configuration for positioning algorithms
pub const Config = struct {
    /// Minimum horizontal gap between nodes (in character cells)
    node_spacing: usize = 3,
    /// Vertical gap between levels (in lines)
    level_spacing: usize = 2,
};

/// Ensure nodes in a level don't overlap, maintaining their order.
///
/// Uses symmetric (bidirectional) compaction: a forward pass pushes right,
/// a backward pass pushes left, and the average gives a balanced result
/// that avoids systematic left- or right-bias.
pub fn compactLevel(nodes: []const usize, float_x: []f64, widths: []const usize, spacing: f64) void {
    if (nodes.len == 0) return;

    // --- Forward pass: push right to fix overlaps ---
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

/// Result of positioning computation, parameterized by coordinate type.
///
/// Contains computed x/y coordinates for each node in the graph.
/// Indexed by node index (not node ID).
pub fn PositionAssignment(comptime Coord: type) type {
    return struct {
        /// X coordinate for each node (indexed by node index)
        x: []Coord,
        /// Y coordinate for each node (indexed by node index)
        y: []Coord,
        /// Center X for each node (indexed by node index)
        center_x: []Coord,
        /// Total width of the layout
        total_width: Coord,
        /// Total height of the layout
        total_height: Coord,
        /// Allocator used
        allocator: Allocator,

        pub fn deinit(self: *@This()) void {
            if (self.x.len > 0) self.allocator.free(self.x);
            if (self.y.len > 0) self.allocator.free(self.y);
            if (self.center_x.len > 0) self.allocator.free(self.center_x);
        }
    };
}
