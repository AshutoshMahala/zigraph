//! Direction transform for the zgraph DSL.
//!
//! The layout engine (Sugiyama) always produces top-down flow.
//! This module rotates or flips the coordinate space of the IR in-place
//! to support other flow directions.
//!
//! Phase 1 limitation: edge path internals (corner, side_channel, etc.) are
//! reset to `.direct` for non-top-down directions because the path types
//! encode assumptions about the flow axis. Full path rotation is a Phase 2
//! improvement.

const std = @import("std");
const zigraph = @import("zigraph");
const ast = @import("ast.zig");

const IR = zigraph.LayoutIR(usize);

/// Apply a direction transform to the laid-out IR, mutating it in-place.
/// The layout engine always produces top-down flow. This function rotates
/// the coordinate space for other directions.
pub fn applyDirection(ir: *IR, direction: ast.Direction) void {
    switch (direction) {
        .top_down => return, // default, no transform
        .left_right => applyLeftRight(ir),
        .bottom_up => applyBottomUp(ir),
        .right_left => applyRightLeft(ir),
    }
}

fn applyLeftRight(ir: *IR) void {
    // Swap X↔Y for all nodes
    for (ir.nodes.items) |*node| {
        const old_x = node.x;
        const old_y = node.y;
        const old_w = node.width;
        const old_h = node.height;
        const old_cx = node.center_x;
        const old_cy = node.center_y;
        node.x = old_y;
        node.y = old_x;
        node.width = old_h;
        node.height = old_w;
        node.center_x = old_cy;
        node.center_y = old_cx;
    }

    // Swap X↔Y for all edges; reset path to direct (Phase 1 limitation)
    for (ir.edges.items) |*edge| {
        const old_fx = edge.from_x;
        const old_fy = edge.from_y;
        const old_tx = edge.to_x;
        const old_ty = edge.to_y;
        const old_lx = edge.label_x;
        const old_ly = edge.label_y;
        edge.from_x = old_fy;
        edge.from_y = old_fx;
        edge.to_x = old_ty;
        edge.to_y = old_tx;
        edge.label_x = old_ly;
        edge.label_y = old_lx;
        // Reset path to direct — path internals encode top-down assumptions
        edge.path.deinit();
        edge.path = .{ .direct = {} };
    }

    // Swap X↔Y for subgraphs
    for (ir.subgraphs.items) |*sg| {
        const old_x = sg.x;
        const old_y = sg.y;
        const old_w = sg.width;
        const old_h = sg.height;
        sg.x = old_y;
        sg.y = old_x;
        sg.width = old_h;
        sg.height = old_w;
    }

    // Swap IR dimensions
    const old_w = ir.width;
    ir.width = ir.height;
    ir.height = old_w;
}

fn applyBottomUp(ir: *IR) void {
    const max_y = ir.height;

    for (ir.nodes.items) |*node| {
        // Flip so that high-Y items go to the top. Guard against underflow.
        const bottom = node.y + node.height;
        node.y = if (max_y >= bottom) max_y - bottom else 0;
        node.center_y = if (max_y >= node.center_y) max_y - node.center_y else 0;
    }

    for (ir.edges.items) |*edge| {
        edge.from_y = if (max_y >= edge.from_y) max_y - edge.from_y else 0;
        edge.to_y = if (max_y >= edge.to_y) max_y - edge.to_y else 0;
        edge.label_y = if (max_y >= edge.label_y) max_y - edge.label_y else 0;
        // Reset path to direct — path internals encode top-down assumptions
        edge.path.deinit();
        edge.path = .{ .direct = {} };
    }

    for (ir.subgraphs.items) |*sg| {
        const bottom = sg.y + sg.height;
        sg.y = if (max_y >= bottom) max_y - bottom else 0;
    }
    // Height is unchanged (dimensions stay the same; content is flipped)
}

fn applyRightLeft(ir: *IR) void {
    // First swap X↔Y (like left-right); this also updates ir.width/ir.height
    applyLeftRight(ir);

    // Then flip X axis in the new coordinate space
    const max_x = ir.width;

    for (ir.nodes.items) |*node| {
        const right = node.x + node.width;
        node.x = if (max_x >= right) max_x - right else 0;
        node.center_x = if (max_x >= node.center_x) max_x - node.center_x else 0;
    }

    for (ir.edges.items) |*edge| {
        edge.from_x = if (max_x >= edge.from_x) max_x - edge.from_x else 0;
        edge.to_x = if (max_x >= edge.to_x) max_x - edge.to_x else 0;
        edge.label_x = if (max_x >= edge.label_x) max_x - edge.label_x else 0;
        // Paths are already .direct from applyLeftRight; no deinit needed
    }

    for (ir.subgraphs.items) |*sg| {
        const right = sg.x + sg.width;
        sg.x = if (max_x >= right) max_x - right else 0;
    }
    // Width is unchanged
}

// ============================================================================
// Tests
// ============================================================================

test "applyDirection top_down is a no-op" {
    const allocator = std.testing.allocator;
    var ir = IR.init(allocator);
    defer ir.deinit();

    try ir.addNode(.{
        .id = 1,
        .label = "A",
        .x = 10,
        .y = 20,
        .width = 6,
        .height = 2,
        .center_x = 13,
        .center_y = 21,
        .level = 0,
        .level_position = 0,
    });
    ir.setDimensions(80, 40);

    applyDirection(&ir, .top_down);

    try std.testing.expectEqual(@as(usize, 10), ir.nodes.items[0].x);
    try std.testing.expectEqual(@as(usize, 20), ir.nodes.items[0].y);
    try std.testing.expectEqual(@as(usize, 80), ir.width);
    try std.testing.expectEqual(@as(usize, 40), ir.height);
}

test "applyDirection left_right swaps width and height" {
    const allocator = std.testing.allocator;
    var ir = IR.init(allocator);
    defer ir.deinit();

    try ir.addNode(.{
        .id = 1,
        .label = "A",
        .x = 5,
        .y = 10,
        .width = 4,
        .height = 2,
        .center_x = 7,
        .center_y = 11,
        .level = 0,
        .level_position = 0,
    });
    ir.setDimensions(80, 40);

    applyDirection(&ir, .left_right);

    // IR dimensions should be swapped
    try std.testing.expectEqual(@as(usize, 40), ir.width);
    try std.testing.expectEqual(@as(usize, 80), ir.height);

    // Node x/y should be swapped
    const node = &ir.nodes.items[0];
    try std.testing.expectEqual(@as(usize, 10), node.x); // old y
    try std.testing.expectEqual(@as(usize, 5), node.y);  // old x
    try std.testing.expectEqual(@as(usize, 2), node.width);  // old height
    try std.testing.expectEqual(@as(usize, 4), node.height); // old width
    try std.testing.expectEqual(@as(usize, 11), node.center_x); // old center_y
    try std.testing.expectEqual(@as(usize, 7), node.center_y);  // old center_x
}

test "applyDirection left_right swaps edge endpoints and resets path" {
    const allocator = std.testing.allocator;
    var ir = IR.init(allocator);
    defer ir.deinit();

    try ir.addNode(.{
        .id = 1, .label = "A",
        .x = 0, .y = 0, .width = 4, .height = 2,
        .center_x = 2, .center_y = 1,
        .level = 0, .level_position = 0,
    });
    try ir.addEdge(.{
        .from_id = 1, .to_id = 2,
        .from_x = 10, .from_y = 20,
        .to_x = 30, .to_y = 40,
        .label_x = 15, .label_y = 25,
        .path = .{ .corner = .{ .horizontal_y = 30 } },
        .edge_index = 0,
    });
    ir.setDimensions(80, 40);

    applyDirection(&ir, .left_right);

    const edge = &ir.edges.items[0];
    try std.testing.expectEqual(@as(usize, 20), edge.from_x); // old from_y
    try std.testing.expectEqual(@as(usize, 10), edge.from_y); // old from_x
    try std.testing.expectEqual(@as(usize, 40), edge.to_x);   // old to_y
    try std.testing.expectEqual(@as(usize, 30), edge.to_y);   // old to_x
    try std.testing.expectEqual(@as(usize, 25), edge.label_x); // old label_y
    try std.testing.expectEqual(@as(usize, 15), edge.label_y); // old label_x
    try std.testing.expect(edge.path == .direct);
}

test "applyDirection bottom_up flips Y axis" {
    const allocator = std.testing.allocator;
    var ir = IR.init(allocator);
    defer ir.deinit();

    // Node at y=0, height=2 with max_y=40 → flipped y = 40 - (0+2) = 38
    try ir.addNode(.{
        .id = 1, .label = "A",
        .x = 5, .y = 0, .width = 4, .height = 2,
        .center_x = 7, .center_y = 1,
        .level = 0, .level_position = 0,
    });
    ir.setDimensions(80, 40);

    applyDirection(&ir, .bottom_up);

    // Dimensions unchanged
    try std.testing.expectEqual(@as(usize, 80), ir.width);
    try std.testing.expectEqual(@as(usize, 40), ir.height);

    const node = &ir.nodes.items[0];
    try std.testing.expectEqual(@as(usize, 5), node.x);   // x unchanged
    try std.testing.expectEqual(@as(usize, 38), node.y);  // 40 - (0+2) = 38
    try std.testing.expectEqual(@as(usize, 39), node.center_y); // 40 - 1 = 39
}
