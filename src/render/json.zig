//! JSON Renderer
//!
//! Renders LayoutIR as JSON for external tool consumption.
//! Use this to integrate with SVG renderers, web UIs, React components, etc.
//!
//! ## Schema (v1.0)
//!
//! ```json
//! {
//!   "version": "1.0",
//!   "width": 120,
//!   "height": 40,
//!   "level_count": 4,
//!   "nodes": [
//!     {"id": 1, "label": "A", "x": 10, "y": 0, "width": 3, "center_x": 11, "level": 0, "level_position": 0}
//!   ],
//!   "edges": [
//!     {"from": 1, "to": 2, "from_x": 11, "from_y": 1, "to_x": 20, "to_y": 3, "path": {"type": "direct"}}
//!   ]
//! }
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;
const ir_mod = @import("../core/ir.zig");
const LayoutIR = ir_mod.LayoutIR;
const EdgePath = ir_mod.EdgePath;

/// Current JSON schema version
pub const VERSION = "1.0";

/// Render LayoutIR as JSON string.
///
/// Returns a heap-allocated JSON string. Caller owns the memory.
pub fn render(layout_ir: *const LayoutIR, allocator: Allocator) ![]u8 {
    var buffer: std.ArrayListUnmanaged(u8) = .{};
    errdefer buffer.deinit(allocator);

    const writer = buffer.writer(allocator);

    // Start object
    try writer.writeAll("{\n");
    try writer.print("  \"version\": \"{s}\",\n", .{VERSION});
    try writer.print("  \"width\": {d},\n", .{layout_ir.width});
    try writer.print("  \"height\": {d},\n", .{layout_ir.height});
    try writer.print("  \"level_count\": {d},\n", .{layout_ir.level_count});

    // Nodes array
    try writer.writeAll("  \"nodes\": [\n");
    for (layout_ir.nodes.items, 0..) |node, i| {
        try writer.writeAll("    {");
        try writer.print("\"id\": {d}, ", .{node.id});
        try writer.print("\"label\": \"{s}\", ", .{node.label});
        try writer.print("\"x\": {d}, ", .{node.x});
        try writer.print("\"y\": {d}, ", .{node.y});
        try writer.print("\"width\": {d}, ", .{node.width});
        try writer.print("\"center_x\": {d}, ", .{node.center_x});
        try writer.print("\"level\": {d}, ", .{node.level});
        try writer.print("\"level_position\": {d}", .{node.level_position});
        try writer.writeAll("}");
        if (i < layout_ir.nodes.items.len - 1) try writer.writeAll(",");
        try writer.writeAll("\n");
    }
    try writer.writeAll("  ],\n");

    // Edges array
    try writer.writeAll("  \"edges\": [\n");
    for (layout_ir.edges.items, 0..) |edge, i| {
        try writer.writeAll("    {");
        try writer.print("\"from\": {d}, ", .{edge.from_id});
        try writer.print("\"to\": {d}, ", .{edge.to_id});
        try writer.print("\"from_x\": {d}, ", .{edge.from_x});
        try writer.print("\"from_y\": {d}, ", .{edge.from_y});
        try writer.print("\"to_x\": {d}, ", .{edge.to_x});
        try writer.print("\"to_y\": {d}, ", .{edge.to_y});

        // Path
        try writer.writeAll("\"path\": ");
        switch (edge.path) {
            .direct => try writer.writeAll("{\"type\": \"direct\"}"),
            .corner => |c| try writer.print("{{\"type\": \"corner\", \"horizontal_y\": {d}}}", .{c.horizontal_y}),
            .side_channel => |sc| try writer.print("{{\"type\": \"side_channel\", \"channel_x\": {d}, \"start_y\": {d}, \"end_y\": {d}}}", .{ sc.channel_x, sc.start_y, sc.end_y }),
            .multi_segment => |ms| {
                try writer.writeAll("{\"type\": \"multi_segment\", \"waypoints\": [");
                for (ms.waypoints.items, 0..) |wp, wi| {
                    try writer.print("[{d}, {d}]", .{ wp.x, wp.y });
                    if (wi < ms.waypoints.items.len - 1) try writer.writeAll(", ");
                }
                try writer.writeAll("]}");
            },
            .spline => |sp| try writer.print("{{\"type\": \"spline\", \"cp1_x\": {d}, \"cp1_y\": {d}, \"cp2_x\": {d}, \"cp2_y\": {d}}}", .{ sp.cp1_x, sp.cp1_y, sp.cp2_x, sp.cp2_y }),
        }

        // Label (optional)
        if (edge.label) |label| {
            try writer.writeAll(", \"label\": \"");
            try writer.writeAll(label);
            try writer.print("\", \"label_x\": {d}, \"label_y\": {d}", .{ edge.label_x, edge.label_y });
        }

        try writer.writeAll("}");
        if (i < layout_ir.edges.items.len - 1) try writer.writeAll(",");
        try writer.writeAll("\n");
    }
    try writer.writeAll("  ]\n");

    try writer.writeAll("}\n");

    return buffer.toOwnedSlice(allocator);
}

// ============================================================================
// Tests
// ============================================================================

test "json: render basic layout" {
    const allocator = std.testing.allocator;

    var layout_ir = LayoutIR.init(allocator);
    defer layout_ir.deinit();

    try layout_ir.addNode(.{
        .id = 1,
        .label = "A",
        .x = 0,
        .y = 0,
        .width = 3,
        .center_x = 1,
        .level = 0,
        .level_position = 0,
    });

    try layout_ir.addEdge(.{
        .from_id = 1,
        .to_id = 2,
        .from_x = 1,
        .from_y = 1,
        .to_x = 1,
        .to_y = 3,
        .path = .direct,
        .edge_index = 0,
    });

    layout_ir.setDimensions(10, 5);

    const json = try render(&layout_ir, allocator);
    defer allocator.free(json);

    // Verify expected fields
    try std.testing.expect(std.mem.indexOf(u8, json, "\"version\": \"1.0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"nodes\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"edges\":") != null);
}
