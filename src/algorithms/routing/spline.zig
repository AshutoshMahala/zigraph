//! Spline edge routing algorithm
//!
//! Routes edges using cubic bezier curves for smooth, aesthetically pleasing connections.
//! Control points are computed to create natural-looking curves that avoid overlapping.
//!
//! ## Algorithm
//!
//! For each edge from node A to node B:
//! 1. Compute vertical offset based on level distance
//! 2. Place control points to create smooth S-curve or direct curve
//! 3. Handle horizontal displacement gracefully
//!
//! ## Bezier Curve Basics
//!
//! A cubic bezier from P0 to P3 with control points P1, P2:
//! ```
//! B(t) = (1-t)³P0 + 3(1-t)²tP1 + 3(1-t)t²P2 + t³P3
//! ```
//!
//! In SVG: `<path d="M x0 y0 C x1 y1, x2 y2, x3 y3"/>`

const std = @import("std");
const Allocator = std.mem.Allocator;
const ir_mod = @import("../../core/ir.zig");
const LayoutEdge = ir_mod.LayoutEdge;
const EdgePath = ir_mod.EdgePath;
const LayoutNode = ir_mod.LayoutNode;
const graph_mod = @import("../../core/graph.zig");
const Graph = graph_mod.Graph;
const virtual_mod = @import("../layering/virtual.zig");
const DummyPositions = virtual_mod.DummyPositions;

/// Spline routing configuration
pub const SplineConfig = struct {
    /// Tension factor (0.0 = straight, 1.0 = maximum curve)
    /// Controls how far control points are placed from endpoints
    tension: f32 = 0.5,

    /// Minimum vertical offset for control points (in layout units)
    /// Ensures curves have some bend even for adjacent nodes
    min_control_offset: usize = 1,
};

/// Route edges using spline curves.
///
/// Converts direct/corner paths to smooth bezier curves.
/// Returns a new edge list with spline paths.
pub fn route(
    g: *const Graph,
    nodes: []const LayoutNode,
    id_to_index: *const std.AutoHashMapUnmanaged(usize, usize),
    allocator: Allocator,
    config: SplineConfig,
) !std.ArrayListUnmanaged(LayoutEdge) {
    var edges: std.ArrayListUnmanaged(LayoutEdge) = .{};
    errdefer edges.deinit(allocator);

    for (g.edges.items, 0..) |edge, edge_idx| {
        const from_idx = id_to_index.get(edge.from) orelse continue;
        const to_idx = id_to_index.get(edge.to) orelse continue;

        const from_node = nodes[from_idx];
        const to_node = nodes[to_idx];

        // Compute edge endpoints (center of nodes)
        const from_x = from_node.center_x;
        const from_y = from_node.y + 1; // Bottom of source node
        const to_x = to_node.center_x;
        const to_y = to_node.y; // Top of target node

        // Check for long (skip-level) edges
        const level_diff = if (to_node.level > from_node.level)
            to_node.level - from_node.level
        else
            0;

        // For long edges, use control points that guide the curve through intermediate space
        const control_points = computeControlPointsWithLevels(
            from_x,
            from_y,
            to_x,
            to_y,
            level_diff,
            config,
        );

        try edges.append(allocator, .{
            .from_id = edge.from,
            .to_id = edge.to,
            .from_x = from_x,
            .from_y = from_y,
            .to_x = to_x,
            .to_y = to_y,
            .path = .{
                .spline = .{
                    .cp1_x = control_points.cp1_x,
                    .cp1_y = control_points.cp1_y,
                    .cp2_x = control_points.cp2_x,
                    .cp2_y = control_points.cp2_y,
                },
            },
            .edge_index = edge_idx,
        });
    }

    return edges;
}

/// Route edges with dummy node support.
///
/// For skip-level edges, uses dummy waypoints to create splines that
/// follow the layout path through intermediate levels.
pub fn routeWithDummies(
    g: *const Graph,
    nodes: []const LayoutNode,
    id_to_index: *const std.AutoHashMapUnmanaged(usize, usize),
    dummy_positions: *const DummyPositions,
    allocator: Allocator,
    config: SplineConfig,
) !std.ArrayListUnmanaged(LayoutEdge) {
    var edges: std.ArrayListUnmanaged(LayoutEdge) = .{};
    errdefer edges.deinit(allocator);

    for (g.edges.items, 0..) |edge, edge_idx| {
        const from_idx = id_to_index.get(edge.from) orelse continue;
        const to_idx = id_to_index.get(edge.to) orelse continue;

        const from_node = nodes[from_idx];
        const to_node = nodes[to_idx];

        const from_x = from_node.center_x;
        const from_y = from_node.y + 1;
        const to_x = to_node.center_x;
        const to_y = to_node.y;

        // Check for dummy waypoints
        const waypoints = dummy_positions.getWaypoints(edge_idx);

        if (waypoints.len > 0) {
            // Multi-segment spline through dummy nodes
            // For now, use the first dummy as intermediate control point guidance
            const mid_wp = waypoints[waypoints.len / 2];

            // Create spline that goes through the middle waypoint
            const cp1_y = from_y + (mid_wp.level - from_y) / 2;
            const cp2_y = mid_wp.level + (to_y - mid_wp.level) / 2;

            try edges.append(allocator, .{
                .from_id = edge.from,
                .to_id = edge.to,
                .from_x = from_x,
                .from_y = from_y,
                .to_x = to_x,
                .to_y = to_y,
                .path = .{
                    .spline = .{
                        .cp1_x = mid_wp.x,
                        .cp1_y = cp1_y,
                        .cp2_x = mid_wp.x,
                        .cp2_y = cp2_y,
                    },
                },
                .edge_index = edge_idx,
            });
        } else {
            // No dummies - standard spline
            const level_diff = if (to_node.level > from_node.level)
                to_node.level - from_node.level
            else
                0;

            const control_points = computeControlPointsWithLevels(
                from_x,
                from_y,
                to_x,
                to_y,
                level_diff,
                config,
            );

            try edges.append(allocator, .{
                .from_id = edge.from,
                .to_id = edge.to,
                .from_x = from_x,
                .from_y = from_y,
                .to_x = to_x,
                .to_y = to_y,
                .path = .{
                    .spline = .{
                        .cp1_x = control_points.cp1_x,
                        .cp1_y = control_points.cp1_y,
                        .cp2_x = control_points.cp2_x,
                        .cp2_y = control_points.cp2_y,
                    },
                },
                .edge_index = edge_idx,
            });
        }
    }

    return edges;
}

const ControlPoints = struct {
    cp1_x: usize,
    cp1_y: usize,
    cp2_x: usize,
    cp2_y: usize,
};

/// Compute bezier control points for a smooth curve between two points.
/// Takes level difference into account to create better curves for long edges.
///
/// Strategy:
/// - For adjacent levels: standard S-curve
/// - For skip-level edges: control points guide curve through intermediate space
fn computeControlPointsWithLevels(
    from_x: usize,
    from_y: usize,
    to_x: usize,
    to_y: usize,
    level_diff: usize,
    config: SplineConfig,
) ControlPoints {
    // Vertical distance between nodes
    const dy: usize = if (to_y > from_y) to_y - from_y else from_y - to_y;

    // For long edges, we want control points closer to source/target y
    // to create a more vertical curve that goes "through" intermediate levels
    const tension = if (level_diff > 1)
        config.tension * 0.7 // Less horizontal spread for long edges
    else
        config.tension;

    // Control point vertical offset
    const offset_f: f32 = @as(f32, @floatFromInt(dy)) * tension;
    const offset: usize = @max(config.min_control_offset, @as(usize, @intFromFloat(offset_f)));

    // Horizontal difference
    const dx_signed: isize = @as(isize, @intCast(to_x)) - @as(isize, @intCast(from_x));

    if (dx_signed == 0) {
        // Vertical edge: control points straight down
        return .{
            .cp1_x = from_x,
            .cp1_y = from_y + offset,
            .cp2_x = to_x,
            .cp2_y = if (to_y > offset) to_y - offset else 0,
        };
    }

    // For long diagonal edges, make the curve more vertical by reducing horizontal spread
    const dx_abs = @abs(dx_signed);
    const horizontal_factor: f32 = if (level_diff > 1) 0.3 else 0.5;
    const h_offset_f = @as(f32, @floatFromInt(dx_abs)) * horizontal_factor;
    const h_offset: usize = @max(1, @as(usize, @intFromFloat(h_offset_f)));

    if (dx_signed > 0) {
        // Target is to the right
        return .{
            .cp1_x = from_x + h_offset,
            .cp1_y = from_y + offset,
            .cp2_x = if (to_x > h_offset) to_x - h_offset else 0,
            .cp2_y = if (to_y > offset) to_y - offset else 0,
        };
    } else {
        // Target is to the left
        return .{
            .cp1_x = if (from_x > h_offset) from_x - h_offset else 0,
            .cp1_y = from_y + offset,
            .cp2_x = to_x + h_offset,
            .cp2_y = if (to_y > offset) to_y - offset else 0,
        };
    }
}

// Backward compatibility alias
fn computeControlPoints(
    from_x: usize,
    from_y: usize,
    to_x: usize,
    to_y: usize,
    config: SplineConfig,
) ControlPoints {
    return computeControlPointsWithLevels(from_x, from_y, to_x, to_y, 1, config);
}

// ============================================================================
// Tests
// ============================================================================

test "spline: vertical edge control points" {
    const cp = computeControlPoints(10, 0, 10, 10, .{});
    // Same x, control points should be vertically aligned
    try std.testing.expectEqual(@as(usize, 10), cp.cp1_x);
    try std.testing.expectEqual(@as(usize, 10), cp.cp2_x);
    // CP1 below source, CP2 above target
    try std.testing.expect(cp.cp1_y > 0);
    try std.testing.expect(cp.cp2_y < 10);
}

test "spline: diagonal edge control points" {
    const cp = computeControlPoints(0, 0, 20, 10, .{});
    // CP1 should be offset right from source
    try std.testing.expect(cp.cp1_x > 0);
    // CP2 should be offset left from target
    try std.testing.expect(cp.cp2_x < 20);
}

test "spline: high tension creates more curve" {
    const low = computeControlPoints(10, 0, 10, 20, .{ .tension = 0.2 });
    const high = computeControlPoints(10, 0, 10, 20, .{ .tension = 0.8 });

    // Higher tension = larger control point offset
    try std.testing.expect(high.cp1_y > low.cp1_y);
}
