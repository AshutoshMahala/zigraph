//! Subgraph bounding box computation.
//!
//! Computes bounding boxes for subgraphs bottom-up: leaf subgraphs get their
//! bbox from the envelope of direct member nodes plus padding, and parent
//! subgraphs expand to contain all child bboxes plus their own padding.

const std = @import("std");
const Allocator = std.mem.Allocator;
const graph_mod = @import("../../../core/graph.zig");
const Graph = graph_mod.Graph;
const ir_mod = @import("../../../core/ir.zig");
const common = @import("common.zig");
const default_padding = common.default_padding;

/// Compute subgraph bounding boxes and append them to the layout IR.
///
/// Processes the subgraph tree bottom-up:
/// 1. **Leaf subgraphs**: bbox = envelope of direct member nodes + padding
/// 2. **Parent subgraphs**: bbox = union of child bboxes + direct members + padding
///
/// Each nesting level adds `default_padding` cells on all sides, plus one
/// extra row at the top for the subgraph label.
pub fn computeBoundingBoxes(
    g: *const Graph,
    result: *ir_mod.LayoutIR(usize),
    allocator: Allocator,
) !void {
    const sg_count = g.subgraphCount();
    if (sg_count == 0) return;

    // Compute depth of each subgraph for bottom-up ordering
    const depths = try allocator.alloc(usize, sg_count);
    defer allocator.free(depths);
    const order = try allocator.alloc(usize, sg_count);
    defer allocator.free(order);

    for (g.subgraphs.items, 0..) |sg, i| {
        var depth: usize = 0;
        var current = sg.parent_id;
        while (current) |pid| {
            depth += 1;
            const parent = g.subgraphById(pid) orelse break;
            current = parent.parent_id;
        }
        depths[i] = depth;
        order[i] = i;
    }

    // Sort by depth descending (deepest = leaves first)
    std.mem.sort(usize, order, depths, struct {
        fn cmp(d: []usize, a: usize, b: usize) bool {
            return d[a] > d[b];
        }
    }.cmp);

    // Per-subgraph bounding accumulators (indexed by subgraph array index)
    const min_x = try allocator.alloc(usize, sg_count);
    defer allocator.free(min_x);
    const min_y = try allocator.alloc(usize, sg_count);
    defer allocator.free(min_y);
    const max_x = try allocator.alloc(usize, sg_count);
    defer allocator.free(max_x);
    const max_y = try allocator.alloc(usize, sg_count);
    defer allocator.free(max_y);
    const has_content = try allocator.alloc(bool, sg_count);
    defer allocator.free(has_content);

    @memset(min_x, std.math.maxInt(usize));
    @memset(min_y, std.math.maxInt(usize));
    @memset(max_x, 0);
    @memset(max_y, 0);
    @memset(has_content, false);

    // Pass 1: envelope of direct member nodes
    for (result.nodes.items) |node| {
        if (node.kind == .dummy) continue;
        const node_sg = g.nodeSubgraph(node.id) orelse continue;
        const sg_idx = g.subgraph_id_to_index.get(node_sg) orelse continue;

        has_content[sg_idx] = true;
        min_x[sg_idx] = @min(min_x[sg_idx], node.x);
        min_y[sg_idx] = @min(min_y[sg_idx], node.y);
        max_x[sg_idx] = @max(max_x[sg_idx], node.x + node.width);
        max_y[sg_idx] = @max(max_y[sg_idx], node.y + node.height); // node bottom edge
    }

    // Pass 2: bottom-up — pad each subgraph, then propagate to parent
    for (order) |sg_idx| {
        if (!has_content[sg_idx]) continue;

        const sg = g.subgraphs.items[sg_idx];
        const pad = default_padding;
        const label_row: usize = 1; // extra top row for label

        // Apply padding
        min_x[sg_idx] = if (min_x[sg_idx] >= pad) min_x[sg_idx] - pad else 0;
        min_y[sg_idx] = if (min_y[sg_idx] >= pad + label_row) min_y[sg_idx] - (pad + label_row) else 0;
        max_x[sg_idx] += pad;
        max_y[sg_idx] += pad;

        // Ensure minimum width accommodates the label text.
        // The renderer needs width >= label.len + 4 (2 for borders + 2 for spacing).
        if (sg.label.len > 0) {
            const min_label_width = sg.label.len + 4;
            const current_width = max_x[sg_idx] - min_x[sg_idx];
            if (current_width < min_label_width) {
                // Expand right side to fit the label
                max_x[sg_idx] += min_label_width - current_width;
            }
        }

        // Expand parent's accumulator
        if (sg.parent_id) |pid| {
            if (g.subgraph_id_to_index.get(pid)) |parent_idx| {
                has_content[parent_idx] = true;
                min_x[parent_idx] = @min(min_x[parent_idx], min_x[sg_idx]);
                min_y[parent_idx] = @min(min_y[parent_idx], min_y[sg_idx]);
                max_x[parent_idx] = @max(max_x[parent_idx], max_x[sg_idx]);
                max_y[parent_idx] = @max(max_y[parent_idx], max_y[sg_idx]);
            }
        }
    }

    // Emit SubgraphInfo entries to IR
    for (order) |sg_idx| {
        if (!has_content[sg_idx]) continue;
        const sg = g.subgraphs.items[sg_idx];

        try result.subgraphs.append(result.allocator, .{
            .id = sg.id,
            .parent_id = sg.parent_id,
            .label = sg.label,
            .x = min_x[sg_idx],
            .y = min_y[sg_idx],
            .width = max_x[sg_idx] - min_x[sg_idx],
            .height = max_y[sg_idx] - min_y[sg_idx],
        });
    }
}

// ============================================================================
// Tests
// ============================================================================

test "computeBoundingBoxes: simple flat subgraph" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "AA"); // width = 4 (label 2 + borders 2)
    try g.addNode(2, "BB");
    const sg = try g.addSubgraph("cluster");
    try g.putNodes(&.{ 1, 2 }).inside(sg);

    // Build a mock IR with positioned nodes
    var result = ir_mod.LayoutIR(usize).init(allocator);
    defer result.deinit();

    try result.addNode(.{
        .id = 1,
        .label = "AA",
        .x = 5,
        .y = 3,
        .width = 4,
        .center_x = 7,
        .level = 0,
        .level_position = 0,
        .kind = .explicit,
    });
    try result.addNode(.{
        .id = 2,
        .label = "BB",
        .x = 12,
        .y = 3,
        .width = 4,
        .center_x = 14,
        .level = 0,
        .level_position = 1,
        .kind = .explicit,
    });

    try computeBoundingBoxes(&g, &result, allocator);

    // Should have 1 subgraph bbox
    try std.testing.expectEqual(@as(usize, 1), result.subgraphs.items.len);
    const bbox = result.subgraphs.items[0];
    try std.testing.expectEqual(sg, bbox.id);
    try std.testing.expectEqualStrings("cluster", bbox.label);

    // Node envelope: x=[5, 16), y=[3, 4)
    // Padding: 2 cells each side, 1 extra top for label
    // min_x = 5 - 2 = 3, min_y = 3 - 3 = 0, max_x = 16 + 2 = 18, max_y = 4 + 2 = 6
    try std.testing.expectEqual(@as(usize, 3), bbox.x);
    try std.testing.expectEqual(@as(usize, 0), bbox.y);
    try std.testing.expectEqual(@as(usize, 15), bbox.width); // 18 - 3
    try std.testing.expectEqual(@as(usize, 6), bbox.height); // 6 - 0
}

test "computeBoundingBoxes: nested subgraphs" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    const outer = try g.addSubgraph("outer");
    const inner = try g.addSubgraph("inner");
    try g.putSubgraphs(&.{inner}).inside(outer);
    try g.putNodes(&.{ 1, 2 }).inside(inner);

    var result = ir_mod.LayoutIR(usize).init(allocator);
    defer result.deinit();

    try result.addNode(.{
        .id = 1,
        .label = "A",
        .x = 10,
        .y = 5,
        .width = 3,
        .center_x = 11,
        .level = 0,
        .level_position = 0,
        .kind = .explicit,
    });
    try result.addNode(.{
        .id = 2,
        .label = "B",
        .x = 16,
        .y = 5,
        .width = 3,
        .center_x = 17,
        .level = 0,
        .level_position = 1,
        .kind = .explicit,
    });

    try computeBoundingBoxes(&g, &result, allocator);

    // Should have 2 subgraph bboxes (inner first in bottom-up order)
    try std.testing.expectEqual(@as(usize, 2), result.subgraphs.items.len);

    // Find inner and outer by ID
    var inner_bbox: ?ir_mod.SubgraphInfo(usize) = null;
    var outer_bbox: ?ir_mod.SubgraphInfo(usize) = null;
    for (result.subgraphs.items) |sg_info| {
        if (sg_info.id == inner) inner_bbox = sg_info;
        if (sg_info.id == outer) outer_bbox = sg_info;
    }

    try std.testing.expect(inner_bbox != null);
    try std.testing.expect(outer_bbox != null);

    // Inner envelope: x=[10, 19), y=[5, 6), padded: x=[8, 21), y=[2, 8)
    const ib = inner_bbox.?;
    try std.testing.expectEqual(@as(usize, 8), ib.x);
    try std.testing.expectEqual(@as(usize, 2), ib.y);

    // Outer must fully contain inner (with additional padding)
    const ob = outer_bbox.?;
    try std.testing.expect(ob.x <= ib.x);
    try std.testing.expect(ob.y <= ib.y);
    try std.testing.expect(ob.x + ob.width >= ib.x + ib.width);
    try std.testing.expect(ob.y + ob.height >= ib.y + ib.height);
}

test "computeBoundingBoxes: empty subgraph produces no bbox" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    _ = try g.addSubgraph("empty"); // no nodes placed inside

    var result = ir_mod.LayoutIR(usize).init(allocator);
    defer result.deinit();

    try result.addNode(.{
        .id = 1,
        .label = "A",
        .x = 0,
        .y = 0,
        .width = 3,
        .center_x = 1,
        .level = 0,
        .level_position = 0,
        .kind = .explicit,
    });

    try computeBoundingBoxes(&g, &result, allocator);

    // Empty subgraph should NOT appear in output
    try std.testing.expectEqual(@as(usize, 0), result.subgraphs.items.len);
}

test "computeBoundingBoxes: skips dummy nodes" {
    const allocator = std.testing.allocator;
    var g = Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "A");
    try g.addNode(2, "B");
    const sg = try g.addSubgraph("SG");
    try g.putNodes(&.{1}).inside(sg);

    var result = ir_mod.LayoutIR(usize).init(allocator);
    defer result.deinit();

    // Real node in subgraph
    try result.addNode(.{
        .id = 1,
        .label = "A",
        .x = 5,
        .y = 3,
        .width = 3,
        .center_x = 6,
        .level = 0,
        .level_position = 0,
        .kind = .explicit,
    });
    // Dummy node at extreme position — should NOT affect bbox
    try result.addNode(.{
        .id = 0x80000000,
        .label = "O",
        .x = 100,
        .y = 100,
        .width = 1,
        .center_x = 100,
        .level = 1,
        .level_position = 0,
        .kind = .dummy,
    });
    // Real node NOT in subgraph
    try result.addNode(.{
        .id = 2,
        .label = "B",
        .x = 50,
        .y = 50,
        .width = 3,
        .center_x = 51,
        .level = 1,
        .level_position = 1,
        .kind = .explicit,
    });

    try computeBoundingBoxes(&g, &result, allocator);

    try std.testing.expectEqual(@as(usize, 1), result.subgraphs.items.len);
    const bbox = result.subgraphs.items[0];
    // Only node A (x=5, width=3) contributes: envelope x=[5,8), y=[3,4)
    // Padded: x=[3,10), y=[0,6)  → width=7, height=6
    try std.testing.expectEqual(@as(usize, 3), bbox.x);
    try std.testing.expectEqual(@as(usize, 0), bbox.y);
    try std.testing.expectEqual(@as(usize, 7), bbox.width);
    try std.testing.expectEqual(@as(usize, 6), bbox.height);
}
