//! Post-layout direction transform for the zgraph DSL.
//!
//! The Sugiyama layout engine always produces top-down coordinates.
//! This module repositions nodes and edges in the IR to achieve
//! left-right, bottom-up, or right-left flow.
//!
//! For left-right and right-left, positions are recomputed from each
//! node's `level` (column) and `level_position` (row) metadata, with
//! edges routed from the right side of source nodes to the left side
//! of target nodes. The terminal renderer's `.direct` path handles
//! horizontal, vertical, and Manhattan (L-shaped) routing automatically.
//!
//! Known limitation: cross-row edges in horizontal modes arrive with
//! a vertical final segment (down-arrow instead of right-arrow). This
//! is inherent to the core terminal renderer's Manhattan routing, which
//! always ends with a vertical segment. The edge connectivity is correct;
//! only the arrow glyph direction is affected.

const std = @import("std");
const zigraph = @import("zigraph");
const ast = @import("ast.zig");

const IR = zigraph.LayoutIR(usize);

/// Reposition IR nodes and edges for the requested flow direction.
/// Mutates the IR in-place. Top-down is a no-op (layout default).
pub fn applyDirection(ir: *IR, direction: ast.Direction) void {
    switch (direction) {
        .top_down => return,
        .left_right => applyLeftRight(ir),
        .bottom_up => applyBottomUp(ir),
        .right_left => applyRightLeft(ir),
    }
}

/// Recompute positions so levels flow left-to-right as columns.
fn applyLeftRight(ir: *IR) void {
    const edge_gap: usize = 3;
    const row_gap: usize = 1;

    var max_w: usize = 1;
    var max_h: usize = 1;
    for (ir.nodes.items) |node| {
        if (node.width > max_w) max_w = node.width;
        if (node.height > max_h) max_h = node.height;
    }

    const col_stride = max_w + edge_gap;
    const row_stride = max_h + row_gap;

    for (ir.nodes.items) |*node| {
        node.x = node.level * col_stride;
        node.y = node.level_position * row_stride;
        node.center_x = node.x + node.width / 2;
        node.center_y = node.y + node.height / 2;
    }

    for (ir.edges.items) |*edge| {
        if (ir.nodeById(edge.from_id)) |src| {
            if (ir.nodeById(edge.to_id)) |tgt| {
                edge.from_x = src.x + src.width;
                edge.from_y = src.center_y;
                edge.to_x = tgt.x;
                edge.to_y = tgt.center_y;
                edge.label_x = (edge.from_x + edge.to_x) / 2;
                edge.label_y = (edge.from_y + edge.to_y) / 2;
            }
        }
        edge.path.deinit();
        edge.path = .{ .direct = {} };
    }

    for (ir.subgraphs.items) |*sg| {
        const old_x = sg.x;
        const old_w = sg.width;
        sg.x = sg.y;
        sg.y = old_x;
        sg.width = sg.height;
        sg.height = old_w;
    }

    recalcDimensions(ir);
}

/// Flip the Y axis so flow goes bottom-to-top.
fn applyBottomUp(ir: *IR) void {
    const max_y = ir.height;

    for (ir.nodes.items) |*node| {
        const bottom = node.y + node.height;
        node.y = if (max_y >= bottom) max_y - bottom else 0;
        node.center_y = if (max_y >= node.center_y) max_y - node.center_y else 0;
    }

    for (ir.edges.items) |*edge| {
        edge.from_y = if (max_y >= edge.from_y) max_y - edge.from_y else 0;
        edge.to_y = if (max_y >= edge.to_y) max_y - edge.to_y else 0;
        edge.label_y = if (max_y >= edge.label_y) max_y - edge.label_y else 0;
        edge.path.deinit();
        edge.path = .{ .direct = {} };
    }

    for (ir.subgraphs.items) |*sg| {
        const bottom = sg.y + sg.height;
        sg.y = if (max_y >= bottom) max_y - bottom else 0;
    }
}

/// Left-right positioning, then mirror the X axis for right-to-left flow.
fn applyRightLeft(ir: *IR) void {
    applyLeftRight(ir);

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
    }

    for (ir.subgraphs.items) |*sg| {
        const right = sg.x + sg.width;
        sg.x = if (max_x >= right) max_x - right else 0;
    }
}

fn recalcDimensions(ir: *IR) void {
    var max_w: usize = 0;
    var max_h: usize = 0;
    for (ir.nodes.items) |node| {
        const r = node.x + node.width;
        const b = node.y + node.height;
        if (r > max_w) max_w = r;
        if (b > max_h) max_h = b;
    }
    for (ir.subgraphs.items) |sg| {
        const r = sg.x + sg.width;
        const b = sg.y + sg.height;
        if (r > max_w) max_w = r;
        if (b > max_h) max_h = b;
    }
    ir.width = max_w;
    ir.height = max_h;
}

// ── Tests ────────────────────────────────────────────────────────────────────

test "top_down is a no-op" {
    const allocator = std.testing.allocator;
    var ir = IR.init(allocator);
    defer ir.deinit();

    try ir.addNode(.{
        .id = 1, .label = "A",
        .x = 10, .y = 20, .width = 6, .height = 2,
        .center_x = 13, .center_y = 21,
        .level = 0, .level_position = 0,
    });
    ir.setDimensions(80, 40);

    applyDirection(&ir, .top_down);

    try std.testing.expectEqual(@as(usize, 10), ir.nodes.items[0].x);
    try std.testing.expectEqual(@as(usize, 20), ir.nodes.items[0].y);
    try std.testing.expectEqual(@as(usize, 80), ir.width);
    try std.testing.expectEqual(@as(usize, 40), ir.height);
}

test "left_right places levels as columns" {
    const allocator = std.testing.allocator;
    var ir = IR.init(allocator);
    defer ir.deinit();

    try ir.addNode(.{
        .id = 1, .label = "A",
        .x = 0, .y = 0, .width = 3, .height = 1,
        .center_x = 1, .center_y = 0,
        .level = 0, .level_position = 0,
    });
    try ir.addNode(.{
        .id = 2, .label = "B",
        .x = 0, .y = 3, .width = 3, .height = 1,
        .center_x = 1, .center_y = 3,
        .level = 1, .level_position = 0,
    });
    ir.setDimensions(3, 4);

    applyDirection(&ir, .left_right);

    // col_stride = 3 (max width) + 3 (edge gap) = 6
    const a = &ir.nodes.items[0];
    try std.testing.expectEqual(@as(usize, 0), a.x);
    try std.testing.expectEqual(@as(usize, 0), a.y);
    try std.testing.expectEqual(@as(usize, 3), a.width);
    try std.testing.expectEqual(@as(usize, 1), a.height);

    const b = &ir.nodes.items[1];
    try std.testing.expectEqual(@as(usize, 6), b.x);
    try std.testing.expectEqual(@as(usize, 0), b.y);

    try std.testing.expectEqual(@as(usize, 9), ir.width);
    try std.testing.expectEqual(@as(usize, 1), ir.height);
}

test "left_right routes edges horizontally" {
    const allocator = std.testing.allocator;
    var ir = IR.init(allocator);
    defer ir.deinit();

    try ir.addNode(.{
        .id = 1, .label = "A",
        .x = 0, .y = 0, .width = 3, .height = 1,
        .center_x = 1, .center_y = 0,
        .level = 0, .level_position = 0,
    });
    try ir.addNode(.{
        .id = 2, .label = "B",
        .x = 0, .y = 3, .width = 3, .height = 1,
        .center_x = 1, .center_y = 3,
        .level = 1, .level_position = 0,
    });
    try ir.addEdge(.{
        .from_id = 1, .to_id = 2,
        .from_x = 1, .from_y = 1,
        .to_x = 1, .to_y = 3,
        .label_x = 1, .label_y = 2,
        .path = .{ .corner = .{ .horizontal_y = 2 } },
        .edge_index = 0,
    });
    ir.setDimensions(3, 4);

    applyDirection(&ir, .left_right);

    const edge = &ir.edges.items[0];
    try std.testing.expectEqual(@as(usize, 3), edge.from_x);
    try std.testing.expectEqual(@as(usize, 0), edge.from_y);
    try std.testing.expectEqual(@as(usize, 6), edge.to_x);
    try std.testing.expectEqual(@as(usize, 0), edge.to_y);
    try std.testing.expect(edge.path == .direct);
}

test "bottom_up flips Y axis" {
    const allocator = std.testing.allocator;
    var ir = IR.init(allocator);
    defer ir.deinit();

    try ir.addNode(.{
        .id = 1, .label = "A",
        .x = 5, .y = 0, .width = 4, .height = 2,
        .center_x = 7, .center_y = 1,
        .level = 0, .level_position = 0,
    });
    ir.setDimensions(80, 40);

    applyDirection(&ir, .bottom_up);

    try std.testing.expectEqual(@as(usize, 80), ir.width);
    try std.testing.expectEqual(@as(usize, 40), ir.height);

    const node = &ir.nodes.items[0];
    try std.testing.expectEqual(@as(usize, 5), node.x);
    try std.testing.expectEqual(@as(usize, 38), node.y);
    try std.testing.expectEqual(@as(usize, 39), node.center_y);
}
