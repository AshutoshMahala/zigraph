//! Integration tests for the terminal renderer.

const std = @import("std");
const ir_mod = @import("../../core/ir.zig");
const LayoutIR = ir_mod.LayoutIR(usize);
const mod = @import("mod.zig");
const render = mod.render;
const renderWithConfig = mod.renderWithConfig;
const mergeJunction = mod.mergeJunction;
const CP_SG_H = mod.CP_SG_H;
const CP_SG_V = mod.CP_SG_V;
const CP_MIX_CROSS_DH = mod.CP_MIX_CROSS_DH;
const CP_MIX_CROSS_DV = mod.CP_MIX_CROSS_DV;
const CP_MIX_T_DOWN_DH = mod.CP_MIX_T_DOWN_DH;
const CP_MIX_T_UP_DH = mod.CP_MIX_T_UP_DH;
const CP_MIX_T_RIGHT_DV = mod.CP_MIX_T_RIGHT_DV;
const CP_MIX_T_LEFT_DV = mod.CP_MIX_T_LEFT_DV;

test "unicode render: simple chain" {
    const allocator = std.testing.allocator;

    var layout_ir = LayoutIR.init(allocator);
    defer layout_ir.deinit();

    // Add nodes
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
    try layout_ir.addNode(.{
        .id = 2,
        .label = "B",
        .x = 0,
        .y = 3,
        .width = 3,
        .center_x = 1,
        .level = 1,
        .level_position = 0,
    });

    // Add edge
    try layout_ir.addEdge(.{
        .from_id = 1,
        .to_id = 2,
        .from_x = 1,
        .from_y = 0,
        .to_x = 1,
        .to_y = 3,
        .path = .{ .direct = {} },
        .edge_index = 0,
    });

    layout_ir.setDimensions(3, 4);

    const output = try render(&layout_ir, allocator);
    defer allocator.free(output);

    // Check output contains nodes
    try std.testing.expect(std.mem.indexOf(u8, output, "[A]") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "[B]") != null);

    // Check output contains arrow
    try std.testing.expect(std.mem.indexOf(u8, output, "↓") != null);
}

test "unicode render: empty graph" {
    const allocator = std.testing.allocator;

    var layout_ir = LayoutIR.init(allocator);
    defer layout_ir.deinit();

    const output = try render(&layout_ir, allocator);
    defer allocator.free(output);

    try std.testing.expectEqual(@as(usize, 0), output.len);
}

test "unicode render: subgraph box" {
    const allocator = std.testing.allocator;

    var layout_ir = LayoutIR.init(allocator);
    defer layout_ir.deinit();

    try layout_ir.addNode(.{
        .id = 1,
        .label = "A",
        .x = 3,
        .y = 2,
        .width = 3,
        .center_x = 4,
        .level = 0,
        .level_position = 0,
    });

    try layout_ir.subgraphs.append(allocator, .{
        .id = 0,
        .parent_id = null,
        .label = "SG",
        .x = 1,
        .y = 0,
        .width = 8,
        .height = 5,
    });

    layout_ir.setDimensions(12, 6);

    const output = try render(&layout_ir, allocator);
    defer allocator.free(output);

    // Should contain double-line box characters
    try std.testing.expect(std.mem.indexOf(u8, output, "\xe2\x95\x94") != null); // ╔
    try std.testing.expect(std.mem.indexOf(u8, output, "\xe2\x95\x97") != null); // ╗
    try std.testing.expect(std.mem.indexOf(u8, output, "\xe2\x95\x9a") != null); // ╚
    try std.testing.expect(std.mem.indexOf(u8, output, "\xe2\x95\x9d") != null); // ╝
    // Should contain label
    try std.testing.expect(std.mem.indexOf(u8, output, "SG") != null);
    // Should contain node
    try std.testing.expect(std.mem.indexOf(u8, output, "[A]") != null);
}

test "unicode render: subgraph disabled" {
    const allocator = std.testing.allocator;

    var layout_ir = LayoutIR.init(allocator);
    defer layout_ir.deinit();

    try layout_ir.subgraphs.append(allocator, .{
        .id = 0,
        .parent_id = null,
        .label = "hidden",
        .x = 0,
        .y = 0,
        .width = 5,
        .height = 5,
    });

    layout_ir.setDimensions(8, 6);

    const output = try renderWithConfig(&layout_ir, allocator, .{ .show_subgraphs = false });
    defer allocator.free(output);

    // Should NOT contain double-line box characters
    try std.testing.expect(std.mem.indexOf(u8, output, "\xe2\x95\x94") == null); // ╔
}

test "mergeJunction: vertical edge crossing horizontal subgraph border" {
    // Single vertical edge (│) crossing double horizontal border (═) → ╪
    try std.testing.expectEqual(CP_MIX_CROSS_DH, mergeJunction(CP_SG_H, true, true, false, false));
}

test "mergeJunction: horizontal edge crossing vertical subgraph border" {
    // Single horizontal edge (─) crossing double vertical border (║) → ╫
    try std.testing.expectEqual(CP_MIX_CROSS_DV, mergeJunction(CP_SG_V, false, false, true, true));
}

test "mergeJunction: edge enters from above double horizontal border" {
    // Edge only goes down from ═ → ╤
    try std.testing.expectEqual(CP_MIX_T_DOWN_DH, mergeJunction(CP_SG_H, false, true, false, false));
}

test "mergeJunction: edge enters from below double horizontal border" {
    // Edge only comes up to ═ → ╧
    try std.testing.expectEqual(CP_MIX_T_UP_DH, mergeJunction(CP_SG_H, true, false, false, false));
}

test "mergeJunction: edge goes right from vertical subgraph border" {
    // Edge goes right from ║ → ╞
    try std.testing.expectEqual(CP_MIX_T_RIGHT_DV, mergeJunction(CP_SG_V, false, false, true, false));
}

test "mergeJunction: edge goes left from vertical subgraph border" {
    // Edge goes left from ║ → ╡
    try std.testing.expectEqual(CP_MIX_T_LEFT_DV, mergeJunction(CP_SG_V, false, false, false, true));
}

test "mergeJunction: T-junction upgrades to full crossing" {
    // ╤ + from_above → ╪
    try std.testing.expectEqual(CP_MIX_CROSS_DH, mergeJunction(CP_MIX_T_DOWN_DH, true, false, false, false));
    // ╧ + to_below → ╪
    try std.testing.expectEqual(CP_MIX_CROSS_DH, mergeJunction(CP_MIX_T_UP_DH, false, true, false, false));
    // ╞ + to_left → ╫
    try std.testing.expectEqual(CP_MIX_CROSS_DV, mergeJunction(CP_MIX_T_RIGHT_DV, false, false, false, true));
    // ╡ + to_right → ╫
    try std.testing.expectEqual(CP_MIX_CROSS_DV, mergeJunction(CP_MIX_T_LEFT_DV, false, false, true, false));
}

test "mergeJunction: double horizontal border without perpendicular stays" {
    // ═ with only horizontal directions → stays ═
    try std.testing.expectEqual(CP_SG_H, mergeJunction(CP_SG_H, false, false, true, true));
}

test "mergeJunction: double vertical border without perpendicular stays" {
    // ║ with only vertical directions → stays ║
    try std.testing.expectEqual(CP_SG_V, mergeJunction(CP_SG_V, true, true, false, false));
}

test "unicode render: edge crosses subgraph border cleanly" {
    const allocator = std.testing.allocator;

    var layout_ir = LayoutIR.init(allocator);
    defer layout_ir.deinit();

    // Node above the subgraph
    try layout_ir.addNode(.{
        .id = 1,
        .label = "A",
        .x = 3,
        .y = 0,
        .width = 3,
        .center_x = 4,
        .level = 0,
        .level_position = 0,
    });

    // Node inside the subgraph
    try layout_ir.addNode(.{
        .id = 2,
        .label = "B",
        .x = 3,
        .y = 4,
        .width = 3,
        .center_x = 4,
        .level = 1,
        .level_position = 0,
    });

    // Subgraph box covering B
    try layout_ir.subgraphs.append(allocator, .{
        .id = 0,
        .parent_id = null,
        .label = "SG",
        .x = 1,
        .y = 2,
        .width = 8,
        .height = 5,
    });

    // Edge from A to B (crosses the top border at y=2, x=4)
    try layout_ir.addEdge(.{
        .from_id = 1,
        .to_id = 2,
        .from_x = 4,
        .from_y = 1,
        .to_x = 4,
        .to_y = 4,
        .path = .{ .direct = {} },
        .edge_index = 0,
    });

    layout_ir.setDimensions(12, 8);

    const output = try render(&layout_ir, allocator);
    defer allocator.free(output);

    // Should contain the mixed crossing character ╪ (U+256A = 0xE2 0x95 0xAA)
    try std.testing.expect(std.mem.indexOf(u8, output, "\xe2\x95\xaa") != null);
    // Should still contain subgraph corners
    try std.testing.expect(std.mem.indexOf(u8, output, "\xe2\x95\x94") != null); // ╔
    try std.testing.expect(std.mem.indexOf(u8, output, "\xe2\x95\x97") != null); // ╗
}
