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

test "terminal render: simple chain" {
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

test "terminal render: empty graph" {
    const allocator = std.testing.allocator;

    var layout_ir = LayoutIR.init(allocator);
    defer layout_ir.deinit();

    const output = try render(&layout_ir, allocator);
    defer allocator.free(output);

    try std.testing.expectEqual(@as(usize, 0), output.len);
}

test "terminal render: subgraph box" {
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

test "terminal render: subgraph disabled" {
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

test "terminal render: edge crosses subgraph border cleanly" {
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

// ── Weight-aware junction tests ─────────────────────────────────────────────

const mergeJunctionWeighted = mod.mergeJunctionWeighted;
const ArmWeight = mod.ArmWeight;
const DirWeights = mod.DirWeights;
const decomposeChar = mod.decomposeChar;
const lookupChar = mod.lookupChar;
const CP_HV_V_LINE = mod.CP_HV_V_LINE;
const CP_HV_H_LINE = mod.CP_HV_H_LINE;
const CP_HV_CORNER_UR = mod.CP_HV_CORNER_UR;
const CP_HV_CROSS = mod.CP_HV_CROSS;
const CP_DB_V_LINE = mod.CP_DB_V_LINE;
const CP_DB_H_LINE = mod.CP_DB_H_LINE;

test "decomposeChar: light lines" {
    const v = decomposeChar('│');
    try std.testing.expectEqual(ArmWeight.light, v.up);
    try std.testing.expectEqual(ArmWeight.light, v.down);
    try std.testing.expectEqual(ArmWeight.none, v.left);
    try std.testing.expectEqual(ArmWeight.none, v.right);

    const h = decomposeChar('─');
    try std.testing.expectEqual(ArmWeight.none, h.up);
    try std.testing.expectEqual(ArmWeight.none, h.down);
    try std.testing.expectEqual(ArmWeight.light, h.left);
    try std.testing.expectEqual(ArmWeight.light, h.right);
}

test "decomposeChar: heavy lines" {
    const v = decomposeChar('┃');
    try std.testing.expectEqual(ArmWeight.heavy, v.up);
    try std.testing.expectEqual(ArmWeight.heavy, v.down);

    const h = decomposeChar('━');
    try std.testing.expectEqual(ArmWeight.heavy, h.left);
    try std.testing.expectEqual(ArmWeight.heavy, h.right);
}

test "decomposeChar: double lines" {
    const v = decomposeChar('║');
    try std.testing.expectEqual(ArmWeight.double, v.up);
    try std.testing.expectEqual(ArmWeight.double, v.down);

    const h = decomposeChar('═');
    try std.testing.expectEqual(ArmWeight.double, h.left);
    try std.testing.expectEqual(ArmWeight.double, h.right);
}

test "decomposeChar: dashed lines" {
    // Dashed chars decompose as light (dashed is a visual variant, not a junction weight)
    const v = decomposeChar('┊');
    try std.testing.expectEqual(ArmWeight.light, v.up);
    try std.testing.expectEqual(ArmWeight.light, v.down);

    const h = decomposeChar('┈');
    try std.testing.expectEqual(ArmWeight.light, h.left);
    try std.testing.expectEqual(ArmWeight.light, h.right);
}

test "decomposeChar: space returns all none" {
    const s = decomposeChar(' ');
    try std.testing.expectEqual(ArmWeight.none, s.up);
    try std.testing.expectEqual(ArmWeight.none, s.down);
    try std.testing.expectEqual(ArmWeight.none, s.left);
    try std.testing.expectEqual(ArmWeight.none, s.right);
}

test "lookupChar: heavy vertical" {
    try std.testing.expectEqual(CP_HV_V_LINE, lookupChar(.{ .up = .heavy, .down = .heavy }));
}

test "lookupChar: heavy horizontal" {
    try std.testing.expectEqual(CP_HV_H_LINE, lookupChar(.{ .left = .heavy, .right = .heavy }));
}

test "lookupChar: double vertical" {
    try std.testing.expectEqual(CP_DB_V_LINE, lookupChar(.{ .up = .double, .down = .double }));
}

test "lookupChar: double horizontal" {
    try std.testing.expectEqual(CP_DB_H_LINE, lookupChar(.{ .left = .double, .right = .double }));
}

test "lookupChar: heavy corner (└ variant)" {
    // up + right → └-like corner (CP_HV_CORNER_DR in naming convention)
    try std.testing.expectEqual(mod.CP_HV_CORNER_DR, lookupChar(.{ .up = .heavy, .right = .heavy }));
}

test "lookupChar: heavy crossing" {
    try std.testing.expectEqual(CP_HV_CROSS, lookupChar(.{ .up = .heavy, .down = .heavy, .left = .heavy, .right = .heavy }));
}

test "lookupChar: dashed → light for junction resolution" {
    // Dashed effective weight is light, so junctions use light chars
    const result = lookupChar(.{ .up = .dashed, .down = .dashed });
    try std.testing.expectEqual(@as(u21, '│'), result);
}

test "mergeJunctionWeighted: heavy vertical crossing light horizontal" {
    // Heavy │ + light ─ → mixed crossing
    const result = mergeJunctionWeighted('┃', .{ .left = .light, .right = .light });
    const dw = decomposeChar(result);
    try std.testing.expectEqual(ArmWeight.heavy, dw.up);
    try std.testing.expectEqual(ArmWeight.heavy, dw.down);
    try std.testing.expectEqual(ArmWeight.light, dw.left);
    try std.testing.expectEqual(ArmWeight.light, dw.right);
}

test "mergeJunctionWeighted: light vertical crossing heavy horizontal" {
    const result = mergeJunctionWeighted('│', .{ .left = .heavy, .right = .heavy });
    const dw = decomposeChar(result);
    try std.testing.expectEqual(ArmWeight.light, dw.up);
    try std.testing.expectEqual(ArmWeight.light, dw.down);
    try std.testing.expectEqual(ArmWeight.heavy, dw.left);
    try std.testing.expectEqual(ArmWeight.heavy, dw.right);
}

test "mergeJunctionWeighted: marker chars are protected" {
    // Arrow char should not be overwritten
    try std.testing.expectEqual(@as(u21, '↓'), mergeJunctionWeighted('↓', .{ .left = .heavy, .right = .heavy }));
    try std.testing.expectEqual(@as(u21, '↑'), mergeJunctionWeighted('↑', .{ .up = .light, .down = .light }));
}

test "mergeJunctionWeighted: space + heavy vertical" {
    try std.testing.expectEqual(CP_HV_V_LINE, mergeJunctionWeighted(' ', .{ .up = .heavy, .down = .heavy }));
}

test "mergeJunctionWeighted: double horiz + light down = ╤" {
    // This is the key subgraph border crossing case
    try std.testing.expectEqual(CP_MIX_T_DOWN_DH, mergeJunctionWeighted(CP_SG_H, .{ .down = .light }));
}

test "ArmWeight.merge: heavier weight wins" {
    try std.testing.expectEqual(ArmWeight.heavy, ArmWeight.merge(.light, .heavy));
    try std.testing.expectEqual(ArmWeight.heavy, ArmWeight.merge(.heavy, .none));
    try std.testing.expectEqual(ArmWeight.double, ArmWeight.merge(.double, .light));
    try std.testing.expectEqual(ArmWeight.light, ArmWeight.merge(.light, .none));
}

test "ArmWeight.fromLineWeight roundtrip" {
    const lw = @import("config.zig").LineWeight;
    try std.testing.expectEqual(ArmWeight.light, ArmWeight.fromLineWeight(lw.light));
    try std.testing.expectEqual(ArmWeight.heavy, ArmWeight.fromLineWeight(lw.heavy));
    try std.testing.expectEqual(ArmWeight.double, ArmWeight.fromLineWeight(lw.double));
    try std.testing.expectEqual(ArmWeight.dashed, ArmWeight.fromLineWeight(lw.dashed));
}
