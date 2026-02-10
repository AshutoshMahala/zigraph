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

/// Validate that a type is suitable as a coordinate type.
/// Coord must be an integer or floating-point numeric type.
fn validateCoordType(comptime Coord: type) void {
    const valid = switch (@typeInfo(Coord)) {
        .int, .float => true,
        else => false,
    };
    if (!valid) {
        @compileError("Coord must be a numeric type (integer or float), got: " ++ @typeName(Coord));
    }
}

/// Convert a coordinate value between numeric types.
/// Handles int→int, int→float, float→int (with rounding), and float→float.
pub fn coordCast(comptime Target: type, comptime Source: type, val: Source) Target {
    if (Source == Target) return val;
    return switch (@typeInfo(Source)) {
        .int => switch (@typeInfo(Target)) {
            .int => @intCast(val),
            .float => @floatFromInt(val),
            else => @compileError("coordCast: unsupported target type: " ++ @typeName(Target)),
        },
        .float => switch (@typeInfo(Target)) {
            .int => @intFromFloat(@round(val)),
            .float => @floatCast(val),
            else => @compileError("coordCast: unsupported target type: " ++ @typeName(Target)),
        },
        else => @compileError("coordCast: unsupported source type: " ++ @typeName(Source)),
    };
}

/// A node in the laid-out graph with computed position and dimensions.
/// Parameterized by `Coord` for flexible spatial precision (e.g., usize, u16, f32).
pub fn LayoutNode(comptime Coord: type) type {
    comptime validateCoordType(Coord);
    return struct {
        /// Original node ID from the Graph (or synthetic ID for dummies)
        id: usize,
        /// Node label text
        label: []const u8,
        /// X coordinate (left edge)
        x: Coord,
        /// Y coordinate (top edge)
        y: Coord,
        /// Width (including brackets for text renderers)
        width: Coord,
        /// Center X coordinate (for edge routing)
        center_x: Coord,
        /// The level (depth) this node is at
        level: usize,
        /// Position within the level (0-indexed from left)
        level_position: usize,
        /// How this node was created (explicit, implicit, or dummy)
        kind: NodeKind = .explicit,
        /// For dummy nodes: the edge index this dummy belongs to
        edge_index: ?usize = null,
    };
}

/// How an edge is routed between nodes.
/// Parameterized by `Coord` for flexible spatial precision.
pub fn EdgePath(comptime Coord: type) type {
    comptime validateCoordType(Coord);
    return union(enum) {
        /// Direct vertical connection (nodes are horizontally aligned or adjacent levels)
        direct: void,

        /// L-shaped connection with a horizontal segment
        corner: struct {
            /// Y coordinate of the horizontal segment
            horizontal_y: Coord,
        },

        /// Routed through a side channel (for skip-level edges)
        side_channel: struct {
            /// X coordinate of the vertical channel
            channel_x: Coord,
            /// Starting Y of the channel
            start_y: Coord,
            /// Ending Y of the channel
            end_y: Coord,
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
            cp1_x: Coord,
            cp1_y: Coord,
            /// Second control point (near target)
            cp2_x: Coord,
            cp2_y: Coord,
        },

        const Self = @This();

        pub const Waypoint = struct {
            x: Coord,
            y: Coord,
        };

        /// Free any allocated memory in the path.
        pub fn deinit(self: *Self) void {
            switch (self.*) {
                .multi_segment => |*ms| ms.waypoints.deinit(ms.allocator),
                else => {},
            }
        }
    };
}

/// A routed edge in the layout with path information.
/// Parameterized by `Coord` for flexible spatial precision.
pub fn LayoutEdge(comptime Coord: type) type {
    comptime validateCoordType(Coord);
    return struct {
        /// Source node ID
        from_id: usize,
        /// Target node ID
        to_id: usize,
        /// Source node's center X coordinate
        from_x: Coord,
        /// Source node's bottom Y coordinate
        from_y: Coord,
        /// Target node's center X coordinate
        to_x: Coord,
        /// Target node's top Y coordinate
        to_y: Coord,
        /// How the edge is routed
        path: EdgePath(Coord),
        /// Edge index (for consistent coloring)
        edge_index: usize,
        /// Whether this edge is directed (arrow) or undirected (no arrow)
        directed: bool = true,
        /// Optional edge label text (e.g., "depends on")
        label: ?[]const u8 = null,
        /// Computed label X position (set during layout)
        label_x: Coord = 0,
        /// Computed label Y position (set during layout)
        label_y: Coord = 0,
    };
}

/// Intermediate representation of a laid-out graph.
/// Parameterized by `Coord` for flexible spatial precision.
///
/// This is the output of the layout algorithm and input to renderers.
/// It contains all the information needed to draw the graph in any format.
pub fn LayoutIR(comptime Coord: type) type {
    comptime validateCoordType(Coord);
    const Node = LayoutNode(Coord);
    const Edge = LayoutEdge(Coord);

    return struct {
        allocator: Allocator,

        /// All nodes with their computed positions
        nodes: std.ArrayListUnmanaged(Node),
        /// All edges with routing information
        edges: std.ArrayListUnmanaged(Edge),
        /// Total width
        width: Coord,
        /// Total height
        height: Coord,
        /// Number of levels in the layout
        level_count: usize,
        /// Nodes organized by level (indices into `nodes`)
        levels: std.ArrayListUnmanaged(std.ArrayListUnmanaged(usize)),
        /// O(1) lookup from node ID to index in nodes vec
        id_to_index: std.AutoHashMapUnmanaged(usize, usize),

        const Self = @This();

        /// Initialize an empty IR.
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

        /// Get the total width of the layout.
        pub fn getWidth(self: *const Self) Coord {
            return self.width;
        }

        /// Get the total height of the layout.
        pub fn getHeight(self: *const Self) Coord {
            return self.height;
        }

        /// Get the number of levels (depth) in the graph.
        pub fn getLevelCount(self: *const Self) usize {
            return self.level_count;
        }

        /// Get all laid-out nodes.
        pub fn getNodes(self: *const Self) []const Node {
            return self.nodes.items;
        }

        /// Get all routed edges.
        pub fn getEdges(self: *const Self) []const Edge {
            return self.edges.items;
        }

        /// Get a node by its ID.
        pub fn nodeById(self: *const Self, id: usize) ?*const Node {
            const idx = self.id_to_index.get(id) orelse return null;
            if (idx >= self.nodes.items.len) return null;
            return &self.nodes.items[idx];
        }

        /// Get nodes at a specific level.
        pub fn nodesAtLevel(self: *const Self, level: usize) []const usize {
            if (level >= self.levels.items.len) return &.{};
            return self.levels.items[level].items;
        }

        // ====================================================================
        // Builder methods (used by layout algorithms)
        // ====================================================================

        /// Add a node to the IR.
        pub fn addNode(self: *Self, node: Node) !void {
            const idx = self.nodes.items.len;
            try self.nodes.append(self.allocator, node);
            try self.id_to_index.put(self.allocator, node.id, idx);
        }

        /// Add an edge to the IR.
        pub fn addEdge(self: *Self, edge: Edge) !void {
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
        pub fn setDimensions(self: *Self, width: Coord, height: Coord) void {
            self.width = width;
            self.height = height;
        }

        // ====================================================================
        // Conversion methods
        // ====================================================================

        /// Convert this IR to use a different coordinate type.
        /// Returns a new independently-owned IR. Caller must deinit.
        /// Useful for rendering: convert any Coord IR to usize for Unicode, etc.
        pub fn convertCoord(self: *const Self, comptime Target: type, target_allocator: Allocator) !LayoutIR(Target) {
            comptime validateCoordType(Target);
            const TargetIR = LayoutIR(Target);
            const TargetPath = EdgePath(Target);

            var result = TargetIR.init(target_allocator);
            errdefer result.deinit();

            // Pre-allocate capacity
            try result.nodes.ensureTotalCapacity(target_allocator, self.nodes.items.len);
            try result.edges.ensureTotalCapacity(target_allocator, self.edges.items.len);

            // Convert nodes (addNode also populates id_to_index)
            for (self.nodes.items) |node| {
                try result.addNode(.{
                    .id = node.id,
                    .label = node.label,
                    .x = coordCast(Target, Coord, node.x),
                    .y = coordCast(Target, Coord, node.y),
                    .width = coordCast(Target, Coord, node.width),
                    .center_x = coordCast(Target, Coord, node.center_x),
                    .level = node.level,
                    .level_position = node.level_position,
                    .kind = node.kind,
                    .edge_index = node.edge_index,
                });
            }

            // Convert edges (deep-copy multi_segment waypoints)
            for (self.edges.items) |edge| {
                const converted_path: TargetPath = switch (edge.path) {
                    .direct => .{ .direct = {} },
                    .corner => |c| .{ .corner = .{
                        .horizontal_y = coordCast(Target, Coord, c.horizontal_y),
                    } },
                    .side_channel => |sc| .{ .side_channel = .{
                        .channel_x = coordCast(Target, Coord, sc.channel_x),
                        .start_y = coordCast(Target, Coord, sc.start_y),
                        .end_y = coordCast(Target, Coord, sc.end_y),
                    } },
                    .multi_segment => |ms| blk: {
                        var waypoints: std.ArrayListUnmanaged(TargetPath.Waypoint) = .{};
                        errdefer waypoints.deinit(target_allocator);
                        try waypoints.ensureTotalCapacity(target_allocator, ms.waypoints.items.len);
                        for (ms.waypoints.items) |wp| {
                            waypoints.appendAssumeCapacity(.{
                                .x = coordCast(Target, Coord, wp.x),
                                .y = coordCast(Target, Coord, wp.y),
                            });
                        }
                        break :blk .{ .multi_segment = .{
                            .waypoints = waypoints,
                            .allocator = target_allocator,
                        } };
                    },
                    .spline => |sp| .{ .spline = .{
                        .cp1_x = coordCast(Target, Coord, sp.cp1_x),
                        .cp1_y = coordCast(Target, Coord, sp.cp1_y),
                        .cp2_x = coordCast(Target, Coord, sp.cp2_x),
                        .cp2_y = coordCast(Target, Coord, sp.cp2_y),
                    } },
                };

                // If append fails, clean up the path (not yet owned by result)
                result.edges.append(target_allocator, .{
                    .from_id = edge.from_id,
                    .to_id = edge.to_id,
                    .from_x = coordCast(Target, Coord, edge.from_x),
                    .from_y = coordCast(Target, Coord, edge.from_y),
                    .to_x = coordCast(Target, Coord, edge.to_x),
                    .to_y = coordCast(Target, Coord, edge.to_y),
                    .path = converted_path,
                    .edge_index = edge.edge_index,
                    .directed = edge.directed,
                    .label = edge.label,
                    .label_x = coordCast(Target, Coord, edge.label_x),
                    .label_y = coordCast(Target, Coord, edge.label_y),
                }) catch |err| {
                    var p = converted_path;
                    p.deinit();
                    return err;
                };
            }

            // Deep-copy levels (indices are always usize, no conversion needed)
            try result.levels.ensureTotalCapacity(target_allocator, self.levels.items.len);
            for (self.levels.items) |level| {
                var new_level: std.ArrayListUnmanaged(usize) = .{};
                try new_level.appendSlice(target_allocator, level.items);
                result.levels.appendAssumeCapacity(new_level);
            }
            result.level_count = self.level_count;

            // Convert dimensions
            result.width = coordCast(Target, Coord, self.width);
            result.height = coordCast(Target, Coord, self.height);

            return result;
        }
    };
}

// ============================================================================
// Tests
// ============================================================================

// Test-local type instantiations (usize coordinates)
const TestLayoutIR = LayoutIR(usize);
const TestEdgePath = EdgePath(usize);

test "LayoutIR: basic operations" {
    const allocator = std.testing.allocator;

    var layout_ir = TestLayoutIR.init(allocator);
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

    var layout_ir = TestLayoutIR.init(allocator);
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

    var waypoints: std.ArrayListUnmanaged(TestEdgePath.Waypoint) = .{};
    try waypoints.append(allocator, .{ .x = 1, .y = 2 });
    try waypoints.append(allocator, .{ .x = 3, .y = 4 });

    var path = TestEdgePath{ .multi_segment = .{ .waypoints = waypoints, .allocator = allocator } };
    path.deinit(); // Should not leak
}

test "coordCast: int to int" {
    try std.testing.expectEqual(@as(u16, 42), coordCast(u16, usize, 42));
    try std.testing.expectEqual(@as(u32, 100), coordCast(u32, u16, 100));
}

test "coordCast: int to float" {
    try std.testing.expectEqual(@as(f32, 42.0), coordCast(f32, usize, 42));
    try std.testing.expectEqual(@as(f64, 255.0), coordCast(f64, u8, 255));
}

test "coordCast: float to int" {
    try std.testing.expectEqual(@as(usize, 3), coordCast(usize, f32, 3.4));
    try std.testing.expectEqual(@as(u16, 4), coordCast(u16, f64, 3.6));
}

test "coordCast: float to float" {
    const result = coordCast(f32, f64, 3.14);
    try std.testing.expect(@abs(result - 3.14) < 0.001);
}

test "coordCast: identity" {
    try std.testing.expectEqual(@as(usize, 99), coordCast(usize, usize, 99));
    try std.testing.expectEqual(@as(f32, 1.5), coordCast(f32, f32, 1.5));
}

test "convertCoord: usize to u16" {
    const allocator = std.testing.allocator;

    var source = TestLayoutIR.init(allocator);
    defer source.deinit();

    try source.addNode(.{
        .id = 1,
        .label = "Test",
        .x = 10,
        .y = 20,
        .width = 6,
        .center_x = 13,
        .level = 0,
        .level_position = 0,
    });
    try source.addEdge(.{
        .from_id = 1,
        .to_id = 2,
        .from_x = 13,
        .from_y = 21,
        .to_x = 13,
        .to_y = 24,
        .path = .{ .corner = .{ .horizontal_y = 22 } },
        .edge_index = 0,
    });
    source.setDimensions(80, 40);
    try source.addNodeToLevel(0, 0);

    var converted = try source.convertCoord(u16, allocator);
    defer converted.deinit();

    // Verify nodes
    try std.testing.expectEqual(@as(usize, 1), converted.nodes.items.len);
    try std.testing.expectEqual(@as(u16, 10), converted.nodes.items[0].x);
    try std.testing.expectEqual(@as(u16, 20), converted.nodes.items[0].y);
    try std.testing.expectEqual(@as(u16, 6), converted.nodes.items[0].width);
    try std.testing.expectEqual(@as(usize, 1), converted.nodes.items[0].id); // stays usize

    // Verify edges
    try std.testing.expectEqual(@as(usize, 1), converted.edges.items.len);
    try std.testing.expectEqual(@as(u16, 13), converted.edges.items[0].from_x);
    const path = converted.edges.items[0].path;
    switch (path) {
        .corner => |c| try std.testing.expectEqual(@as(u16, 22), c.horizontal_y),
        else => return error.TestUnexpectedResult,
    }

    // Verify dimensions
    try std.testing.expectEqual(@as(u16, 80), converted.width);
    try std.testing.expectEqual(@as(u16, 40), converted.height);

    // Verify levels were copied
    try std.testing.expectEqual(@as(usize, 1), converted.level_count);
    try std.testing.expectEqual(@as(usize, 1), converted.levels.items[0].items.len);
}

test "convertCoord: usize to f32" {
    const allocator = std.testing.allocator;

    var source = TestLayoutIR.init(allocator);
    defer source.deinit();

    try source.addNode(.{
        .id = 1,
        .label = "Float",
        .x = 50,
        .y = 100,
        .width = 8,
        .center_x = 54,
        .level = 0,
        .level_position = 0,
    });
    source.setDimensions(200, 150);

    var converted = try source.convertCoord(f32, allocator);
    defer converted.deinit();

    try std.testing.expectEqual(@as(f32, 50.0), converted.nodes.items[0].x);
    try std.testing.expectEqual(@as(f32, 200.0), converted.width);
    try std.testing.expectEqual(@as(f32, 150.0), converted.height);
}

// JSON export tests moved to render/json.zig
