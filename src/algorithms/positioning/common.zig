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

/// Result of positioning computation
///
/// Contains computed x/y coordinates for each node in the graph.
/// Indexed by node index (not node ID).
pub const PositionAssignment = struct {
    /// X coordinate for each node (indexed by node index)
    x: []usize,
    /// Y coordinate for each node (indexed by node index)
    y: []usize,
    /// Center X for each node (indexed by node index)
    center_x: []usize,
    /// Total width of the layout
    total_width: usize,
    /// Total height of the layout
    total_height: usize,
    /// Allocator used
    allocator: Allocator,

    pub fn deinit(self: *PositionAssignment) void {
        if (self.x.len > 0) self.allocator.free(self.x);
        if (self.y.len > 0) self.allocator.free(self.y);
        if (self.center_x.len > 0) self.allocator.free(self.center_x);
    }
};
