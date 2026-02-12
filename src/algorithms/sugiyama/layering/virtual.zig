//! Virtual node support for proper edge routing
//!
//! In the Sugiyama framework, edges that span multiple levels need "dummy nodes"
//! inserted at intermediate levels. This allows:
//! 1. Crossing reduction to optimize the position of long edges
//! 2. Proper edge routing through intermediate levels
//!
//! ## Virtual Node Types
//!
//! - Real: An actual graph node
//! - Dummy: A placeholder for an edge at an intermediate level
//!
//! ## Usage
//!
//! After layer assignment but before crossing reduction:
//! 1. Call `buildVirtualLevels` to create levels with dummy nodes
//! 2. Run crossing reduction on virtual levels
//! 3. Extract real node positions and dummy positions for routing

const std = @import("std");
const Allocator = std.mem.Allocator;
const graph_mod = @import("../../../core/graph.zig");
const Graph = graph_mod.Graph;

/// A virtual node - either a real node or a dummy for edge routing.
pub const VNode = union(enum) {
    /// A real graph node (stores node index)
    real: usize,
    /// A dummy node for edge routing (stores edge index)
    dummy: usize,

    /// Get the real node index if this is a real node
    pub fn realIndex(self: VNode) ?usize {
        return switch (self) {
            .real => |idx| idx,
            .dummy => null,
        };
    }

    /// Get the edge index if this is a dummy node
    pub fn dummyEdge(self: VNode) ?usize {
        return switch (self) {
            .real => null,
            .dummy => |edge_idx| edge_idx,
        };
    }

    /// Width of this virtual node for positioning
    pub fn width(self: VNode, g: *const Graph) usize {
        return switch (self) {
            .real => |idx| if (g.nodeAt(idx)) |node| node.width else 3,
            .dummy => 1, // Minimal width for dummy nodes
        };
    }
};

/// Virtual levels containing both real and dummy nodes
pub const VirtualLevels = struct {
    /// Each level contains VNodes (real or dummy)
    levels: std.ArrayListUnmanaged(std.ArrayListUnmanaged(VNode)),
    /// Allocator used
    allocator: Allocator,

    pub fn deinit(self: *VirtualLevels) void {
        for (self.levels.items) |*level| {
            level.deinit(self.allocator);
        }
        self.levels.deinit(self.allocator);
    }

    /// Get the number of levels
    pub fn levelCount(self: *const VirtualLevels) usize {
        return self.levels.items.len;
    }
};

/// Build virtual levels with dummy nodes for skip-level edges.
///
/// For each edge that spans multiple levels, insert dummy nodes at intermediate levels.
/// This allows crossing reduction to properly position long edges.
pub fn buildVirtualLevels(
    g: *const Graph,
    node_levels: []const usize,
    max_level: usize,
    allocator: Allocator,
) !VirtualLevels {
    const level_count = max_level + 1;

    // Initialize empty levels
    var levels: std.ArrayListUnmanaged(std.ArrayListUnmanaged(VNode)) = .{};
    try levels.ensureTotalCapacity(allocator, level_count);
    for (0..level_count) |_| {
        try levels.append(allocator, .{});
    }

    // Add real nodes to their levels
    for (node_levels, 0..) |level, node_idx| {
        try levels.items[level].append(allocator, .{ .real = node_idx });
    }

    // Insert dummy nodes for skip-level edges
    for (g.edges.items, 0..) |edge, edge_idx| {
        const from_idx = g.nodeIndex(edge.from) orelse continue;
        const to_idx = g.nodeIndex(edge.to) orelse continue;

        const from_level = node_levels[from_idx];
        const to_level = node_levels[to_idx];

        // Skip-level edge: insert dummy at each intermediate level
        if (to_level > from_level + 1) {
            var level = from_level + 1;
            while (level < to_level) : (level += 1) {
                try levels.items[level].append(allocator, .{ .dummy = edge_idx });
            }
        }
    }

    return .{
        .levels = levels,
        .allocator = allocator,
    };
}

/// Extract real node levels from virtual levels.
/// Returns a slice where result[level] contains node indices at that level.
pub fn extractRealNodeLevels(
    virtual_levels: *const VirtualLevels,
    allocator: Allocator,
) !std.ArrayListUnmanaged(std.ArrayListUnmanaged(usize)) {
    var result: std.ArrayListUnmanaged(std.ArrayListUnmanaged(usize)) = .{};
    try result.ensureTotalCapacity(allocator, virtual_levels.levels.items.len);

    for (virtual_levels.levels.items) |level| {
        var real_level: std.ArrayListUnmanaged(usize) = .{};
        for (level.items) |vnode| {
            if (vnode.realIndex()) |idx| {
                try real_level.append(allocator, idx);
            }
        }
        try result.append(allocator, real_level);
    }

    return result;
}

/// Position assignment for virtual nodes (real + dummy)
pub const VirtualPositions = struct {
    /// X position for each VNode at each level: positions[level][pos_in_level]
    x: std.ArrayListUnmanaged(std.ArrayListUnmanaged(usize)),
    /// Total width of layout
    total_width: usize,
    /// Total height of layout
    total_height: usize,
    /// Allocator
    allocator: Allocator,

    pub fn deinit(self: *VirtualPositions) void {
        for (self.x.items) |*level| {
            level.deinit(self.allocator);
        }
        self.x.deinit(self.allocator);
    }
};

/// Dummy node positions for routing: edge_idx -> list of (level, x) waypoints
pub const DummyPositions = struct {
    /// For each edge, the waypoints through dummy nodes
    waypoints: std.ArrayListUnmanaged(std.ArrayListUnmanaged(Waypoint)),
    allocator: Allocator,

    pub const Waypoint = struct {
        level: usize,
        x: usize,
    };

    pub fn deinit(self: *DummyPositions) void {
        for (self.waypoints.items) |*wps| {
            wps.deinit(self.allocator);
        }
        self.waypoints.deinit(self.allocator);
    }

    /// Get waypoints for an edge (sorted by level)
    pub fn getWaypoints(self: *const DummyPositions, edge_idx: usize) []const Waypoint {
        if (edge_idx < self.waypoints.items.len) {
            return self.waypoints.items[edge_idx].items;
        }
        return &.{};
    }
};

/// Extract dummy node positions from virtual levels after positioning.
///
/// Call this after crossing reduction and positioning to get the waypoints
/// for each edge that routes through dummy nodes.
pub fn extractDummyPositions(
    virtual_levels: *const VirtualLevels,
    positions: *const VirtualPositions,
    edge_count: usize,
    level_spacing: usize,
    allocator: Allocator,
) !DummyPositions {
    // Initialize empty waypoint lists for each edge
    var waypoints: std.ArrayListUnmanaged(std.ArrayListUnmanaged(DummyPositions.Waypoint)) = .{};
    try waypoints.ensureTotalCapacity(allocator, edge_count);
    for (0..edge_count) |_| {
        try waypoints.append(allocator, .{});
    }

    // Collect dummy positions from each level
    for (virtual_levels.levels.items, 0..) |level, level_idx| {
        for (level.items, 0..) |vnode, pos| {
            if (vnode.dummyEdge()) |edge_idx| {
                if (edge_idx < waypoints.items.len and pos < positions.x.items[level_idx].items.len) {
                    const x = positions.x.items[level_idx].items[pos];
                    const y = level_idx * (1 + level_spacing);
                    try waypoints.items[edge_idx].append(allocator, .{
                        .level = y,
                        .x = x,
                    });
                }
            }
        }
    }

    // Sort waypoints by level for each edge
    for (waypoints.items) |*wps| {
        std.mem.sort(DummyPositions.Waypoint, wps.items, {}, struct {
            fn lessThan(_: void, a: DummyPositions.Waypoint, b: DummyPositions.Waypoint) bool {
                return a.level < b.level;
            }
        }.lessThan);
    }

    return .{
        .waypoints = waypoints,
        .allocator = allocator,
    };
}

/// Compute positions for virtual levels (both real and dummy nodes).
///
/// Uses a simple left-to-right placement with centering.
/// This is a convenience wrapper that calls computeVirtualPositionsWithHints with no hints.
pub fn computeVirtualPositions(
    g: *const Graph,
    virtual_levels: *const VirtualLevels,
    node_spacing: usize,
    level_spacing: usize,
    allocator: Allocator,
) !VirtualPositions {
    return computeVirtualPositionsWithHints(g, virtual_levels, node_spacing, level_spacing, null, allocator);
}

/// Compute positions for virtual levels with optional x-coordinate hints from a positioning algorithm.
///
/// When `real_node_x_hints` is provided (indexed by node_idx), real nodes use those x-coordinates
/// and dummy nodes interpolate between adjacent real nodes on the edge path.
/// When null, uses simple left-to-right placement with centering (backward compatible).
///
/// This enables integration with brandes_kopf.compute() or simple.compute():
/// 1. Extract real-node levels via extractRealNodeLevels()
/// 2. Run positioning algorithm to get x-coordinates for real nodes
/// 3. Pass those x-coordinates here as hints
/// 4. Dummy nodes are automatically interpolated
pub fn computeVirtualPositionsWithHints(
    g: *const Graph,
    virtual_levels: *const VirtualLevels,
    node_spacing: usize,
    level_spacing: usize,
    real_node_x_hints: ?[]const usize,
    allocator: Allocator,
) !VirtualPositions {
    var x_positions: std.ArrayListUnmanaged(std.ArrayListUnmanaged(usize)) = .{};
    errdefer {
        for (x_positions.items) |*level| level.deinit(allocator);
        x_positions.deinit(allocator);
    }

    try x_positions.ensureTotalCapacity(allocator, virtual_levels.levels.items.len);

    var max_width: usize = 0;

    if (real_node_x_hints) |hints| {
        // =====================================================================
        // Hinted mode: use provided x-coordinates for real nodes
        // =====================================================================

        // First pass: place real nodes from hints, collect dummy node info
        for (virtual_levels.levels.items) |level| {
            var level_x: std.ArrayListUnmanaged(usize) = .{};
            try level_x.ensureTotalCapacity(allocator, level.items.len);

            for (level.items) |vnode| {
                const x: usize = switch (vnode) {
                    .real => |node_idx| if (node_idx < hints.len) hints[node_idx] else 0,
                    .dummy => 0, // Placeholder, will be computed below
                };
                try level_x.append(allocator, x);
            }
            try x_positions.append(allocator, level_x);
        }

        // Second pass: interpolate dummy positions for each edge
        // For skip-level edges, dummy nodes form a path between source and target.
        // We linearly interpolate x-coordinates between adjacent real nodes.
        for (g.edges.items, 0..) |edge, edge_idx| {
            const from_idx = g.nodeIndex(edge.from) orelse continue;
            const to_idx = g.nodeIndex(edge.to) orelse continue;

            const from_x: i64 = @intCast(if (from_idx < hints.len) hints[from_idx] else 0);
            const to_x: i64 = @intCast(if (to_idx < hints.len) hints[to_idx] else 0);

            // Find source and target levels
            var from_level: ?usize = null;
            var to_level: ?usize = null;

            for (virtual_levels.levels.items, 0..) |level, level_idx| {
                for (level.items) |vnode| {
                    if (vnode.realIndex()) |idx| {
                        if (idx == from_idx) from_level = level_idx;
                        if (idx == to_idx) to_level = level_idx;
                    }
                }
            }

            const src_level = from_level orelse continue;
            const dst_level = to_level orelse continue;
            if (dst_level <= src_level + 1) continue; // Not a skip-level edge

            // Interpolate x for dummy nodes at intermediate levels
            const total_span: i64 = @intCast(dst_level - src_level);
            for (virtual_levels.levels.items, 0..) |level, level_idx| {
                if (level_idx <= src_level or level_idx >= dst_level) continue;

                for (level.items, 0..) |vnode, pos| {
                    if (vnode.dummyEdge()) |eidx| {
                        if (eidx == edge_idx) {
                            // Linear interpolation
                            const t: i64 = @intCast(level_idx - src_level);
                            const interp_x = from_x + @divTrunc((to_x - from_x) * t, total_span);
                            x_positions.items[level_idx].items[pos] = @intCast(@max(0, interp_x));
                        }
                    }
                }
            }
        }

        // Compute max width from all positions
        for (virtual_levels.levels.items, 0..) |level, level_idx| {
            for (level.items, 0..) |vnode, pos| {
                const x = x_positions.items[level_idx].items[pos];
                const w = vnode.width(g);
                max_width = @max(max_width, x + w);
            }
        }

        // =================================================================
        // Compaction: fix overlaps while preserving crossing-reduction order
        //
        // The hints + interpolation can place two nodes at the same x.
        // Walk each level left-to-right and push nodes right as needed.
        // =================================================================
        max_width = 0;
        for (virtual_levels.levels.items, 0..) |level, level_idx| {
            var prev_right: usize = 0;
            for (level.items, 0..) |vnode, pos| {
                const w = vnode.width(g);
                const cur_x = x_positions.items[level_idx].items[pos];

                if (pos == 0) {
                    // First node — nothing to collide with
                    max_width = @max(max_width, cur_x + w);
                } else {
                    const min_x = prev_right + node_spacing;
                    if (cur_x < min_x) {
                        x_positions.items[level_idx].items[pos] = min_x;
                        max_width = @max(max_width, min_x + w);
                    } else {
                        max_width = @max(max_width, cur_x + w);
                    }
                }

                prev_right = x_positions.items[level_idx].items[pos] + w;
            }
        }
    } else {
        // =====================================================================
        // Default mode: simple left-to-right placement with centering
        // =====================================================================
        var level_widths = try allocator.alloc(usize, virtual_levels.levels.items.len);
        defer allocator.free(level_widths);

        for (virtual_levels.levels.items, 0..) |level, level_idx| {
            var level_x: std.ArrayListUnmanaged(usize) = .{};
            try level_x.ensureTotalCapacity(allocator, level.items.len);

            var x: usize = 0;
            for (level.items) |vnode| {
                try level_x.append(allocator, x);
                const w = vnode.width(g);
                x += w + node_spacing;
            }

            level_widths[level_idx] = if (x > node_spacing) x - node_spacing else 0;
            max_width = @max(max_width, level_widths[level_idx]);
            try x_positions.append(allocator, level_x);
        }

        // Second pass: center each level
        for (x_positions.items, 0..) |*level_x, level_idx| {
            const level_width = level_widths[level_idx];
            if (level_width < max_width) {
                const offset = (max_width - level_width) / 2;
                for (level_x.items) |*x| {
                    x.* += offset;
                }
            }
        }
    }

    // Compute total height
    const total_height = if (virtual_levels.levels.items.len > 0)
        (virtual_levels.levels.items.len - 1) * (1 + level_spacing) + 1
    else
        0;

    return .{
        .x = x_positions,
        .total_width = max_width,
        .total_height = total_height,
        .allocator = allocator,
    };
}

/// Result of extracting real node positions from virtual layout
pub const RealNodePositions = struct {
    /// X position for each real node (indexed by node_idx)
    x: []usize,
    /// Y position for each real node (indexed by node_idx)
    y: []usize,
    /// Center X for each real node
    center_x: []usize,
    /// Level for each real node
    level: []usize,
    /// Position within level for each real node
    level_position: []usize,
    /// Total width
    total_width: usize,
    /// Total height
    total_height: usize,
    /// Allocator
    allocator: Allocator,

    pub fn deinit(self: *RealNodePositions) void {
        self.allocator.free(self.x);
        self.allocator.free(self.y);
        self.allocator.free(self.center_x);
        self.allocator.free(self.level);
        self.allocator.free(self.level_position);
    }
};

/// Extract real node positions from virtual positions.
pub fn extractRealNodePositions(
    g: *const Graph,
    virtual_levels: *const VirtualLevels,
    virtual_positions: *const VirtualPositions,
    level_spacing: usize,
    allocator: Allocator,
) !RealNodePositions {
    const node_count = g.nodeCount();

    const x = try allocator.alloc(usize, node_count);
    errdefer allocator.free(x);
    const y = try allocator.alloc(usize, node_count);
    errdefer allocator.free(y);
    const center_x = try allocator.alloc(usize, node_count);
    errdefer allocator.free(center_x);
    const level = try allocator.alloc(usize, node_count);
    errdefer allocator.free(level);
    const level_position = try allocator.alloc(usize, node_count);
    errdefer allocator.free(level_position);

    @memset(x, 0);
    @memset(y, 0);
    @memset(center_x, 0);
    @memset(level, 0);
    @memset(level_position, 0);

    // Extract positions for real nodes
    for (virtual_levels.levels.items, 0..) |vlevel, level_idx| {
        var real_pos: usize = 0;
        for (vlevel.items, 0..) |vnode, pos| {
            if (vnode.realIndex()) |node_idx| {
                if (node_idx < node_count) {
                    const node_x = virtual_positions.x.items[level_idx].items[pos];
                    const width = vnode.width(g);

                    x[node_idx] = node_x;
                    y[node_idx] = level_idx * (1 + level_spacing);
                    center_x[node_idx] = node_x + width / 2;
                    level[node_idx] = level_idx;
                    level_position[node_idx] = real_pos;
                    real_pos += 1;
                }
            }
        }
    }

    return .{
        .x = x,
        .y = y,
        .center_x = center_x,
        .level = level,
        .level_position = level_position,
        .total_width = virtual_positions.total_width,
        .total_height = virtual_positions.total_height,
        .allocator = allocator,
    };
}

/// Extract dummy positions for routing based on real node positions from Brandes-Köpf.
///
/// For each skip-level edge, computes waypoints by linearly interpolating
/// between the source and target x-positions at each intermediate level.
pub fn extractDummyPositionsFromEdges(
    g: *const Graph,
    virtual_levels: *const VirtualLevels,
    real_positions: *const @import("../positioning/common.zig").PositionAssignment(usize),
    level_spacing: usize,
    allocator: Allocator,
) !DummyPositions {
    // Initialize empty waypoint lists for each edge
    var waypoints: std.ArrayListUnmanaged(std.ArrayListUnmanaged(DummyPositions.Waypoint)) = .{};
    errdefer {
        for (waypoints.items) |*wps| wps.deinit(allocator);
        waypoints.deinit(allocator);
    }

    try waypoints.ensureTotalCapacity(allocator, g.edges.items.len);
    for (0..g.edges.items.len) |_| {
        try waypoints.append(allocator, .{});
    }

    // For each edge, find its dummy nodes in the virtual levels and compute positions
    for (g.edges.items, 0..) |edge, edge_idx| {
        const from_idx = g.nodeIndex(edge.from) orelse continue;
        const to_idx = g.nodeIndex(edge.to) orelse continue;

        const from_x = real_positions.center_x[from_idx];
        const to_x = real_positions.center_x[to_idx];
        const from_y = real_positions.y[from_idx];
        const to_y = real_positions.y[to_idx];

        // Find dummy nodes for this edge in virtual levels
        for (virtual_levels.levels.items, 0..) |level, level_idx| {
            for (level.items) |vnode| {
                if (vnode.dummyEdge()) |dummy_edge_idx| {
                    if (dummy_edge_idx == edge_idx) {
                        // Compute y for this level
                        const dummy_y = level_idx * (1 + level_spacing);

                        // Interpolate x based on y position
                        const x = if (to_y > from_y) blk: {
                            const t_num = dummy_y - from_y;
                            const t_denom = to_y - from_y;
                            if (t_denom == 0) break :blk from_x;

                            if (to_x >= from_x) {
                                const dx = to_x - from_x;
                                break :blk from_x + (dx * t_num) / t_denom;
                            } else {
                                const dx = from_x - to_x;
                                break :blk from_x - (dx * t_num) / t_denom;
                            }
                        } else from_x;

                        try waypoints.items[edge_idx].append(allocator, .{
                            .level = dummy_y,
                            .x = x,
                        });
                    }
                }
            }
        }
    }

    // Sort waypoints by level for each edge
    for (waypoints.items) |*wps| {
        std.mem.sort(DummyPositions.Waypoint, wps.items, {}, struct {
            fn lessThan(_: void, a: DummyPositions.Waypoint, b: DummyPositions.Waypoint) bool {
                return a.level < b.level;
            }
        }.lessThan);
    }

    return .{
        .waypoints = waypoints,
        .allocator = allocator,
    };
}

// ============================================================================
// Tests
// ============================================================================

test "virtual: skip-level edge creates dummies" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    // A -> B -> C with A -> C skip edge
    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addEdge(1, 2);
    try g.addEdge(2, 3);
    try g.addEdge(1, 3); // Skip edge!

    const node_levels = [_]usize{ 0, 1, 2 }; // A=0, B=1, C=2

    var vlevels = try buildVirtualLevels(&g, &node_levels, 2, allocator);
    defer vlevels.deinit();

    // Level 0: just A
    try std.testing.expectEqual(@as(usize, 1), vlevels.levels.items[0].items.len);
    try std.testing.expectEqual(VNode{ .real = 0 }, vlevels.levels.items[0].items[0]);

    // Level 1: B + dummy for edge 2 (A->C)
    try std.testing.expectEqual(@as(usize, 2), vlevels.levels.items[1].items.len);

    // Level 2: just C
    try std.testing.expectEqual(@as(usize, 1), vlevels.levels.items[2].items.len);
    try std.testing.expectEqual(VNode{ .real = 2 }, vlevels.levels.items[2].items[0]);
}

test "virtual: adjacent edges no dummies" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addEdge(1, 2);

    const node_levels = [_]usize{ 0, 1 };

    var vlevels = try buildVirtualLevels(&g, &node_levels, 1, allocator);
    defer vlevels.deinit();

    // No dummies for adjacent levels
    try std.testing.expectEqual(@as(usize, 1), vlevels.levels.items[0].items.len);
    try std.testing.expectEqual(@as(usize, 1), vlevels.levels.items[1].items.len);
}
