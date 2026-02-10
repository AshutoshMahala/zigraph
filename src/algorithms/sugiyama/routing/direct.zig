//! Direct edge routing
//!
//! Routes edges as straight lines between node centers.
//! This is the simplest routing algorithm.
//!
//! For adjacent levels, edges are drawn as vertical lines.
//! For skip-level edges, edges go through intermediate space.
//! With dummy nodes, skip-level edges use multi-segment paths.

const std = @import("std");
const Allocator = std.mem.Allocator;
const graph_mod = @import("../../../core/graph.zig");
const Graph = graph_mod.Graph;
const ir_mod = @import("../../../core/ir.zig");
const LayoutEdge = ir_mod.LayoutEdge(usize);
const EdgePath = ir_mod.EdgePath(usize);
const LayoutNode = ir_mod.LayoutNode(usize);
const virtual_mod = @import("../layering/virtual.zig");
const DummyPositions = virtual_mod.DummyPositions;

/// Route all edges using direct (straight-line) routing.
///
/// Returns a list of LayoutEdge with path information.
/// Edges from the same source are staggered to different horizontal rows.
pub fn route(
    g: *const Graph,
    nodes: []const LayoutNode,
    node_id_to_ir_index: *const std.AutoHashMapUnmanaged(usize, usize),
    allocator: Allocator,
) !std.ArrayListUnmanaged(LayoutEdge) {
    var edges: std.ArrayListUnmanaged(LayoutEdge) = .{};

    // Per-level slot counter: all edges originating from the same level share
    // a counter so they get unique horizontal rows (handles both fan-out and fan-in).
    var max_level: usize = 0;
    for (nodes) |n| {
        if (n.level > max_level) max_level = n.level;
    }
    var level_slot_counts = try allocator.alloc(usize, max_level + 1);
    defer allocator.free(level_slot_counts);
    @memset(level_slot_counts, 0);

    for (g.edges.items, 0..) |edge, edge_index| {
        // Look up node positions from IR
        const from_ir_idx = node_id_to_ir_index.get(edge.from) orelse continue;
        const to_ir_idx = node_id_to_ir_index.get(edge.to) orelse continue;

        const from_node = &nodes[from_ir_idx];
        const to_node = &nodes[to_ir_idx];

        const slot = level_slot_counts[from_node.level];
        level_slot_counts[from_node.level] += 1;

        // Determine path type
        const level_diff = if (to_node.level > from_node.level)
            to_node.level - from_node.level
        else
            0;

        const from_y_edge = from_node.y + 1; // Row just below source
        const to_y_edge = to_node.y; // Row of target

        const path: EdgePath = if (from_node.center_x == to_node.center_x) blk: {
            break :blk .{ .direct = {} };
        } else if (level_diff <= 1) blk: {
            const available = if (to_y_edge > from_y_edge + 1) to_y_edge - from_y_edge - 1 else 1;
            const base_h_y = from_y_edge + 1;
            const h_y = base_h_y + (slot % available);
            break :blk .{ .corner = .{ .horizontal_y = h_y } };
        } else blk: {
            const available = if (to_y_edge > from_y_edge + 1) to_y_edge - from_y_edge - 1 else 1;
            const base_h_y = from_y_edge + 1;
            const h_y = base_h_y + (slot % available);
            break :blk .{ .corner = .{ .horizontal_y = h_y } };
        };

        try edges.append(allocator, .{
            .from_id = edge.from,
            .to_id = edge.to,
            .from_x = from_node.center_x,
            .from_y = from_node.y + 1, // Bottom of source node
            .to_x = to_node.center_x,
            .to_y = to_node.y, // Top of target node
            .path = path,
            .edge_index = edge_index,
            .directed = edge.directed,
        });
    }

    return edges;
}

/// Route edges with dummy node support for proper multi-segment paths.
///
/// For skip-level edges, routes through the dummy node positions computed
/// during virtual level layout. This produces proper orthogonal routing.
///
/// Edges that share a source or target are staggered onto different horizontal
/// rows so they don't overlap visually.
pub fn routeWithDummies(
    g: *const Graph,
    nodes: []const LayoutNode,
    node_id_to_ir_index: *const std.AutoHashMapUnmanaged(usize, usize),
    dummy_positions: *const DummyPositions,
    allocator: Allocator,
) !std.ArrayListUnmanaged(LayoutEdge) {
    var edges: std.ArrayListUnmanaged(LayoutEdge) = .{};
    errdefer {
        for (edges.items) |*e| e.path.deinit();
        edges.deinit(allocator);
    }

    // Per-level slot counter: all edges originating from the same level share
    // a counter so they get unique horizontal rows (handles both fan-out and fan-in).
    var max_level: usize = 0;
    for (nodes) |n| {
        if (n.level > max_level) max_level = n.level;
    }
    var level_slot_counts = try allocator.alloc(usize, max_level + 1);
    defer allocator.free(level_slot_counts);
    @memset(level_slot_counts, 0);

    for (g.edges.items, 0..) |edge, edge_index| {
        // Look up node positions from IR
        const from_ir_idx = node_id_to_ir_index.get(edge.from) orelse continue;
        const to_ir_idx = node_id_to_ir_index.get(edge.to) orelse continue;

        const from_node = &nodes[from_ir_idx];
        const to_node = &nodes[to_ir_idx];

        const from_y_edge = from_node.y + 1;
        const to_y_edge = to_node.y;

        // Slot for this edge: nth edge from this level
        const slot = level_slot_counts[from_node.level];
        level_slot_counts[from_node.level] += 1;

        // Check for dummy waypoints
        const waypoints = dummy_positions.getWaypoints(edge_index);

        const path: EdgePath = if (waypoints.len > 0) blk: {
            // Multi-segment path through dummy nodes
            var ms_waypoints: std.ArrayListUnmanaged(EdgePath.Waypoint) = .{};
            errdefer ms_waypoints.deinit(allocator);

            // Start point
            var curr_x = from_node.center_x;
            var curr_y = from_y_edge;
            try ms_waypoints.append(allocator, .{ .x = curr_x, .y = curr_y });

            // Route through each dummy waypoint
            for (waypoints) |wp| {
                const target_x = wp.x;
                const target_y = wp.level;

                if (curr_y != target_y) {
                    try ms_waypoints.append(allocator, .{ .x = curr_x, .y = target_y });
                    curr_y = target_y;
                }

                if (curr_x != target_x) {
                    try ms_waypoints.append(allocator, .{ .x = target_x, .y = curr_y });
                    curr_x = target_x;
                }
            }

            // Route to endpoint
            const end_x = to_node.center_x;
            const end_y = to_y_edge;

            if (curr_y != end_y) {
                try ms_waypoints.append(allocator, .{ .x = curr_x, .y = end_y });
                curr_y = end_y;
            }

            if (curr_x != end_x) {
                try ms_waypoints.append(allocator, .{ .x = end_x, .y = curr_y });
            }

            break :blk .{
                .multi_segment = .{
                    .waypoints = ms_waypoints,
                    .allocator = allocator,
                },
            };
        } else if (from_node.center_x == to_node.center_x) blk: {
            break :blk .{ .direct = {} };
        } else blk: {
            // Stagger horizontal_y by slot so edges from the same source
            // don't all land on the same row
            const available = if (to_y_edge > from_y_edge + 1) to_y_edge - from_y_edge - 1 else 1;
            const base_h_y = from_y_edge + 1;
            const h_y = base_h_y + (slot % available);
            break :blk .{ .corner = .{ .horizontal_y = h_y } };
        };

        try edges.append(allocator, .{
            .from_id = edge.from,
            .to_id = edge.to,
            .from_x = from_node.center_x,
            .from_y = from_y_edge,
            .to_x = to_node.center_x,
            .to_y = to_y_edge,
            .path = path,
            .edge_index = edge_index,
            .directed = edge.directed,
        });
    }

    return edges;
}

// ============================================================================
// Tests
// ============================================================================

test "direct routing: adjacent levels" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addEdge(1, 2);

    // Simulated layout nodes
    const nodes = [_]LayoutNode{
        .{ .id = 1, .label = "A", .x = 0, .y = 0, .width = 3, .center_x = 1, .level = 0, .level_position = 0 },
        .{ .id = 2, .label = "B", .x = 0, .y = 3, .width = 3, .center_x = 1, .level = 1, .level_position = 0 },
    };

    var id_map: std.AutoHashMapUnmanaged(usize, usize) = .{};
    defer id_map.deinit(allocator);
    try id_map.put(allocator, 1, 0);
    try id_map.put(allocator, 2, 1);

    var edges = try route(&g, &nodes, &id_map, allocator);
    defer edges.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), edges.items.len);
    try std.testing.expectEqual(EdgePath.direct, edges.items[0].path);
}

test "direct routing: skip level with offset" {
    const allocator = std.testing.allocator;

    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "C");
    try g.addEdge(1, 2);
    try g.addEdge(2, 3);
    try g.addEdge(1, 3); // Skip-level edge

    // Simulated layout: A at top, B middle, C bottom
    // A and C have different X positions
    const nodes = [_]LayoutNode{
        .{ .id = 1, .label = "A", .x = 0, .y = 0, .width = 3, .center_x = 1, .level = 0, .level_position = 0 },
        .{ .id = 2, .label = "B", .x = 5, .y = 3, .width = 3, .center_x = 6, .level = 1, .level_position = 0 },
        .{ .id = 3, .label = "C", .x = 10, .y = 6, .width = 3, .center_x = 11, .level = 2, .level_position = 0 },
    };

    var id_map: std.AutoHashMapUnmanaged(usize, usize) = .{};
    defer id_map.deinit(allocator);
    try id_map.put(allocator, 1, 0);
    try id_map.put(allocator, 2, 1);
    try id_map.put(allocator, 3, 2);

    var edges = try route(&g, &nodes, &id_map, allocator);
    defer edges.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 3), edges.items.len);

    // Find the skip-level edge (1 -> 3)
    for (edges.items) |e| {
        if (e.from_id == 1 and e.to_id == 3) {
            // Should be corner routing due to skip + different X
            try std.testing.expect(e.path == .corner);
        }
    }
}
