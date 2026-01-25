//! Intermediate Representation for graph layout
//!
//! This module provides renderer-agnostic layout data structures.
//! The IR is the STABLE CONTRACT between layout algorithms and renderers.
//!
//! Shape mirrors Rust ascii-dag's LayoutIR for cross-language compatibility.
//!
//! ## Architecture
//!
//! ```text
//! Graph → [Layout Algorithm] → LayoutIR → [Renderer] → Output
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;
const graph_mod = @import("graph.zig");
pub const NodeKind = graph_mod.NodeKind;

/// A node in the laid-out graph with computed position and dimensions.
pub const LayoutNode = struct {
    /// Original node ID from the Graph (or synthetic ID for dummies)
    id: usize,
    /// Node label text
    label: []const u8,
    /// X coordinate (left edge, in character cells)
    x: usize,
    /// Y coordinate (top edge, in lines)
    y: usize,
    /// Width in character cells (including brackets)
    width: usize,
    /// Center X coordinate (for edge routing)
    center_x: usize,
    /// The level (depth) this node is at
    level: usize,
    /// Position within the level (0-indexed from left)
    level_position: usize,
    /// How this node was created (explicit, implicit, or dummy)
    kind: NodeKind = .explicit,
    /// For dummy nodes: the edge index this dummy belongs to
    edge_index: ?usize = null,
};

/// How an edge is routed between nodes.
pub const EdgePath = union(enum) {
    /// Direct vertical connection (nodes are horizontally aligned or adjacent levels)
    direct: void,

    /// L-shaped connection with a horizontal segment
    corner: struct {
        /// Y coordinate of the horizontal segment
        horizontal_y: usize,
    },

    /// Routed through a side channel (for skip-level edges)
    side_channel: struct {
        /// X coordinate of the vertical channel
        channel_x: usize,
        /// Starting Y of the channel
        start_y: usize,
        /// Ending Y of the channel
        end_y: usize,
    },

    /// Multi-segment path through dummy nodes
    multi_segment: struct {
        /// Waypoints: (x, y) coordinates the edge passes through
        waypoints: std.ArrayListUnmanaged(Waypoint),
        /// Allocator used for waypoints (needed for deinit)
        allocator: Allocator,
    },

    /// Cubic bezier spline curve
    /// Control points define the curve shape for smooth edges
    spline: struct {
        /// First control point (near source)
        cp1_x: usize,
        cp1_y: usize,
        /// Second control point (near target)
        cp2_x: usize,
        cp2_y: usize,
    },

    pub const Waypoint = struct {
        x: usize,
        y: usize,
    };

    /// Free any allocated memory in the path.
    pub fn deinit(self: *EdgePath) void {
        switch (self.*) {
            .multi_segment => |*ms| ms.waypoints.deinit(ms.allocator),
            else => {},
        }
    }
};

/// A routed edge in the layout with path information.
pub const LayoutEdge = struct {
    /// Source node ID
    from_id: usize,
    /// Target node ID
    to_id: usize,
    /// Source node's center X coordinate
    from_x: usize,
    /// Source node's bottom Y coordinate
    from_y: usize,
    /// Target node's center X coordinate
    to_x: usize,
    /// Target node's top Y coordinate
    to_y: usize,
    /// How the edge is routed
    path: EdgePath,
    /// Edge index (for consistent coloring)
    edge_index: usize,
};

/// Intermediate representation of a laid-out graph.
///
/// This is the output of the layout algorithm and input to renderers.
/// It contains all the information needed to draw the graph in any format.
pub const LayoutIR = struct {
    allocator: Allocator,

    /// All nodes with their computed positions
    nodes: std.ArrayListUnmanaged(LayoutNode),
    /// All edges with routing information
    edges: std.ArrayListUnmanaged(LayoutEdge),
    /// Total width in character cells
    width: usize,
    /// Total height in lines
    height: usize,
    /// Number of levels in the layout
    level_count: usize,
    /// Nodes organized by level (indices into `nodes`)
    levels: std.ArrayListUnmanaged(std.ArrayListUnmanaged(usize)),
    /// O(1) lookup from node ID to index in nodes vec
    id_to_index: std.AutoHashMapUnmanaged(usize, usize),

    const Self = @This();

    /// Initialize an empty LayoutIR.
    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .nodes = .{},
            .edges = .{},
            .width = 0,
            .height = 0,
            .level_count = 0,
            .levels = .{},
            .id_to_index = .{},
        };
    }

    /// Free all memory used by the IR.
    pub fn deinit(self: *Self) void {
        // Free edge paths that have allocations
        for (self.edges.items) |*edge| {
            edge.path.deinit();
        }
        self.edges.deinit(self.allocator);

        // Free level lists
        for (self.levels.items) |*level| {
            level.deinit(self.allocator);
        }
        self.levels.deinit(self.allocator);

        self.id_to_index.deinit(self.allocator);
        self.nodes.deinit(self.allocator);
    }

    /// Get the total width of the layout in character cells.
    pub fn getWidth(self: *const Self) usize {
        return self.width;
    }

    /// Get the total height of the layout in lines.
    pub fn getHeight(self: *const Self) usize {
        return self.height;
    }

    /// Get the number of levels (depth) in the graph.
    pub fn getLevelCount(self: *const Self) usize {
        return self.level_count;
    }

    /// Get all laid-out nodes.
    pub fn getNodes(self: *const Self) []const LayoutNode {
        return self.nodes.items;
    }

    /// Get all routed edges.
    pub fn getEdges(self: *const Self) []const LayoutEdge {
        return self.edges.items;
    }

    /// Get a node by its ID.
    pub fn nodeById(self: *const Self, id: usize) ?*const LayoutNode {
        const idx = self.id_to_index.get(id) orelse return null;
        if (idx >= self.nodes.items.len) return null;
        return &self.nodes.items[idx];
    }

    /// Get nodes at a specific level.
    pub fn nodesAtLevel(self: *const Self, level: usize) []const usize {
        if (level >= self.levels.items.len) return &.{};
        return self.levels.items[level].items;
    }

    // ========================================================================
    // Builder methods (used by layout algorithms)
    // ========================================================================

    /// Add a node to the IR.
    pub fn addNode(self: *Self, node: LayoutNode) !void {
        const idx = self.nodes.items.len;
        try self.nodes.append(self.allocator, node);
        try self.id_to_index.put(self.allocator, node.id, idx);
    }

    /// Add an edge to the IR.
    pub fn addEdge(self: *Self, edge: LayoutEdge) !void {
        try self.edges.append(self.allocator, edge);
    }

    /// Ensure we have at least `count` levels.
    pub fn ensureLevels(self: *Self, count: usize) !void {
        while (self.levels.items.len < count) {
            try self.levels.append(self.allocator, .{});
        }
        self.level_count = @max(self.level_count, count);
    }

    /// Add a node index to a level.
    pub fn addNodeToLevel(self: *Self, level: usize, node_index: usize) !void {
        try self.ensureLevels(level + 1);
        try self.levels.items[level].append(self.allocator, node_index);
    }

    /// Set the final dimensions.
    pub fn setDimensions(self: *Self, width: usize, height: usize) void {
        self.width = width;
        self.height = height;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "LayoutIR: basic operations" {
    const allocator = std.testing.allocator;

    var layout_ir = LayoutIR.init(allocator);
    defer layout_ir.deinit();

    // Add a node
    try layout_ir.addNode(.{
        .id = 1,
        .label = "Test",
        .x = 0,
        .y = 0,
        .width = 6,
        .center_x = 3,
        .level = 0,
        .level_position = 0,
    });

    try std.testing.expectEqual(@as(usize, 1), layout_ir.getNodes().len);

    // Add to level
    try layout_ir.addNodeToLevel(0, 0);
    try std.testing.expectEqual(@as(usize, 1), layout_ir.getLevelCount());
    try std.testing.expectEqual(@as(usize, 1), layout_ir.nodesAtLevel(0).len);

    // Set dimensions
    layout_ir.setDimensions(80, 24);
    try std.testing.expectEqual(@as(usize, 80), layout_ir.getWidth());
    try std.testing.expectEqual(@as(usize, 24), layout_ir.getHeight());
}

test "LayoutIR: node lookup by ID" {
    const allocator = std.testing.allocator;

    var layout_ir = LayoutIR.init(allocator);
    defer layout_ir.deinit();

    try layout_ir.addNode(.{
        .id = 42,
        .label = "Answer",
        .x = 10,
        .y = 5,
        .width = 8,
        .center_x = 14,
        .level = 2,
        .level_position = 1,
    });

    const node = layout_ir.nodeById(42);
    try std.testing.expect(node != null);
    try std.testing.expectEqualStrings("Answer", node.?.label);
    try std.testing.expectEqual(@as(usize, 10), node.?.x);

    // Non-existent node
    try std.testing.expect(layout_ir.nodeById(999) == null);
}

test "EdgePath: deinit frees multi_segment waypoints" {
    const allocator = std.testing.allocator;

    var waypoints: std.ArrayListUnmanaged(EdgePath.Waypoint) = .{};
    try waypoints.append(allocator, .{ .x = 1, .y = 2 });
    try waypoints.append(allocator, .{ .x = 3, .y = 4 });

    var path = EdgePath{ .multi_segment = .{ .waypoints = waypoints, .allocator = allocator } };
    path.deinit(); // Should not leak
}

// JSON export tests moved to render/json.zig
