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
