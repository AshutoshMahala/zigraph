//! Integration tests for the terminal renderer.

const std = @import("std");
const ir_mod = @import("../../core/ir.zig");
const LayoutIR = ir_mod.LayoutIR(usize);
const mod = @import("mod.zig");
const render = mod.render;
const renderWithConfig = mod.renderWithConfig;
const mergeJunction = mod.mergeJunction;
const Config = mod.Config;
const Color = mod.Color;
const CellColor = mod.CellColor;
const resolveColorAt = mod.resolveColorAt;
const Buffer2D = mod.Buffer2D;
const TerminalNodeStyle = mod.TerminalNodeStyle;
const colormaps = @import("../color/colormaps.zig");
const NodeStyleContext = @import("../../render/types.zig").NodeStyleContext;
const NodeBorder = @import("config.zig").NodeBorder;
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

// ── Topic 2: Node border style tests ────────────────────────────────────────

test "3-row single_box: chain A → B renders box borders" {
    const allocator = std.testing.allocator;

    var layout_ir = LayoutIR.init(allocator);
    defer layout_ir.deinit();

    try layout_ir.addNode(.{ .id = 1, .label = "A", .x = 0, .y = 0, .width = 3, .center_x = 1, .level = 0, .level_position = 0 });
    try layout_ir.addNode(.{ .id = 2, .label = "B", .x = 0, .y = 3, .width = 3, .center_x = 1, .level = 1, .level_position = 0 });

    try layout_ir.addEdge(.{
        .from_id = 1,
        .to_id = 2,
        .from_x = 1,
        .from_y = 1,
        .to_x = 1,
        .to_y = 3,
        .path = .{ .direct = {} },
        .edge_index = 0,
    });

    layout_ir.setDimensions(3, 4);

    const result = try renderWithConfig(&layout_ir, allocator, .{
        .node_style_fn = &struct {
            fn f(_: NodeStyleContext) TerminalNodeStyle {
                return .{ .border = .single_box };
            }
        }.f,
    });
    defer allocator.free(result);

    // Expected (expanded by 4 extra rows = 2 per level):
    // y0: ┌─┐
    // y1: │A│
    // y2: └─┘
    // y3:  │     (gap, edge)
    // y4:  ↓     (gap, edge)
    // y5: ┌─┐
    // y6: │B│
    // y7: └─┘
    var lines = std.mem.splitScalar(u8, result, '\n');
    const l0 = lines.next().?;
    try std.testing.expectEqualStrings("┌─┐", l0);
    const l1 = lines.next().?;
    try std.testing.expectEqualStrings("│A│", l1);
    const l2 = lines.next().?;
    try std.testing.expectEqualStrings("└─┘", l2);
    // Skip gap lines (edge segments)
    _ = lines.next(); // gap with │
    _ = lines.next(); // gap with ↓
    const l5 = lines.next().?;
    try std.testing.expectEqualStrings("┌─┐", l5);
    const l6 = lines.next().?;
    try std.testing.expectEqualStrings("│B│", l6);
    const l7 = lines.next().?;
    try std.testing.expectEqualStrings("└─┘", l7);
}

test "3-row heavy_box: correct characters" {
    const allocator = std.testing.allocator;

    var layout_ir = LayoutIR.init(allocator);
    defer layout_ir.deinit();

    try layout_ir.addNode(.{ .id = 1, .label = "X", .x = 0, .y = 0, .width = 3, .center_x = 1, .level = 0, .level_position = 0 });
    layout_ir.setDimensions(3, 1);

    const result = try renderWithConfig(&layout_ir, allocator, .{
        .node_style_fn = &struct {
            fn f(_: NodeStyleContext) TerminalNodeStyle {
                return .{ .border = .heavy_box };
            }
        }.f,
    });
    defer allocator.free(result);

    var lines = std.mem.splitScalar(u8, result, '\n');
    try std.testing.expectEqualStrings("┏━┓", lines.next().?);
    try std.testing.expectEqualStrings("┃X┃", lines.next().?);
    try std.testing.expectEqualStrings("┗━┛", lines.next().?);
}

test "3-row double_box: correct characters" {
    const allocator = std.testing.allocator;

    var layout_ir = LayoutIR.init(allocator);
    defer layout_ir.deinit();

    try layout_ir.addNode(.{ .id = 1, .label = "Y", .x = 0, .y = 0, .width = 3, .center_x = 1, .level = 0, .level_position = 0 });
    layout_ir.setDimensions(3, 1);

    const result = try renderWithConfig(&layout_ir, allocator, .{
        .node_style_fn = &struct {
            fn f(_: NodeStyleContext) TerminalNodeStyle {
                return .{ .border = .double_box };
            }
        }.f,
    });
    defer allocator.free(result);

    var lines = std.mem.splitScalar(u8, result, '\n');
    try std.testing.expectEqualStrings("╔═╗", lines.next().?);
    try std.testing.expectEqualStrings("║Y║", lines.next().?);
    try std.testing.expectEqualStrings("╚═╝", lines.next().?);
}

test "3-row rounded_box: correct characters" {
    const allocator = std.testing.allocator;

    var layout_ir = LayoutIR.init(allocator);
    defer layout_ir.deinit();

    try layout_ir.addNode(.{ .id = 1, .label = "Z", .x = 0, .y = 0, .width = 3, .center_x = 1, .level = 0, .level_position = 0 });
    layout_ir.setDimensions(3, 1);

    const result = try renderWithConfig(&layout_ir, allocator, .{
        .node_style_fn = &struct {
            fn f(_: NodeStyleContext) TerminalNodeStyle {
                return .{ .border = .rounded_box };
            }
        }.f,
    });
    defer allocator.free(result);

    var lines = std.mem.splitScalar(u8, result, '\n');
    try std.testing.expectEqualStrings("╭─╮", lines.next().?);
    try std.testing.expectEqualStrings("│Z│", lines.next().?);
    try std.testing.expectEqualStrings("╰─╯", lines.next().?);
}

test "3-row open_single: top-left and bottom-right corners only" {
    const allocator = std.testing.allocator;

    var layout_ir = LayoutIR.init(allocator);
    defer layout_ir.deinit();

    try layout_ir.addNode(.{ .id = 1, .label = "W", .x = 0, .y = 0, .width = 3, .center_x = 1, .level = 0, .level_position = 0 });
    layout_ir.setDimensions(3, 1);

    const result = try renderWithConfig(&layout_ir, allocator, .{
        .node_style_fn = &struct {
            fn f(_: NodeStyleContext) TerminalNodeStyle {
                return .{ .border = .open_single };
            }
        }.f,
    });
    defer allocator.free(result);

    var lines = std.mem.splitScalar(u8, result, '\n');
    const l0 = lines.next().?;
    try std.testing.expect(std.mem.startsWith(u8, l0, "┌"));
    const l1 = lines.next().?;
    try std.testing.expectEqualStrings("│W│", l1);
    const l2 = lines.next().?;
    try std.testing.expect(std.mem.endsWith(u8, l2, "┘"));
}

test "3-row open_heavy: heavy weight open corners" {
    const allocator = std.testing.allocator;

    var layout_ir = LayoutIR.init(allocator);
    defer layout_ir.deinit();

    try layout_ir.addNode(.{ .id = 1, .label = "H", .x = 0, .y = 0, .width = 3, .center_x = 1, .level = 0, .level_position = 0 });
    layout_ir.setDimensions(3, 1);

    const result = try renderWithConfig(&layout_ir, allocator, .{
        .node_style_fn = &struct {
            fn f(_: NodeStyleContext) TerminalNodeStyle {
                return .{ .border = .open_heavy };
            }
        }.f,
    });
    defer allocator.free(result);

    var lines = std.mem.splitScalar(u8, result, '\n');
    try std.testing.expect(std.mem.startsWith(u8, lines.next().?, "┏"));
    try std.testing.expectEqualStrings("┃H┃", lines.next().?);
    try std.testing.expect(std.mem.endsWith(u8, lines.next().?, "┛"));
}

test "3-row open_double: double weight open corners" {
    const allocator = std.testing.allocator;

    var layout_ir = LayoutIR.init(allocator);
    defer layout_ir.deinit();

    try layout_ir.addNode(.{ .id = 1, .label = "D", .x = 0, .y = 0, .width = 3, .center_x = 1, .level = 0, .level_position = 0 });
    layout_ir.setDimensions(3, 1);

    const result = try renderWithConfig(&layout_ir, allocator, .{
        .node_style_fn = &struct {
            fn f(_: NodeStyleContext) TerminalNodeStyle {
                return .{ .border = .open_double };
            }
        }.f,
    });
    defer allocator.free(result);

    var lines = std.mem.splitScalar(u8, result, '\n');
    try std.testing.expect(std.mem.startsWith(u8, lines.next().?, "╔"));
    try std.testing.expectEqualStrings("║D║", lines.next().?);
    try std.testing.expect(std.mem.endsWith(u8, lines.next().?, "╝"));
}

test "3-row open_rounded: rounded open corners" {
    const allocator = std.testing.allocator;

    var layout_ir = LayoutIR.init(allocator);
    defer layout_ir.deinit();

    try layout_ir.addNode(.{ .id = 1, .label = "R", .x = 0, .y = 0, .width = 3, .center_x = 1, .level = 0, .level_position = 0 });
    layout_ir.setDimensions(3, 1);

    const result = try renderWithConfig(&layout_ir, allocator, .{
        .node_style_fn = &struct {
            fn f(_: NodeStyleContext) TerminalNodeStyle {
                return .{ .border = .open_rounded };
            }
        }.f,
    });
    defer allocator.free(result);

    var lines = std.mem.splitScalar(u8, result, '\n');
    try std.testing.expect(std.mem.startsWith(u8, lines.next().?, "╭"));
    try std.testing.expectEqualStrings("│R│", lines.next().?);
    try std.testing.expect(std.mem.endsWith(u8, lines.next().?, "╯"));
}

test "node_presets.singleBox: explicit → closed, implicit → open" {
    const allocator = std.testing.allocator;

    var layout_ir = LayoutIR.init(allocator);
    defer layout_ir.deinit();

    // Explicit node
    try layout_ir.addNode(.{ .id = 1, .label = "E", .x = 0, .y = 0, .width = 3, .center_x = 1, .level = 0, .level_position = 0, .kind = .explicit });
    // Implicit node at level 1
    try layout_ir.addNode(.{ .id = 2, .label = "I", .x = 0, .y = 3, .width = 3, .center_x = 1, .level = 1, .level_position = 0, .kind = .implicit });

    try layout_ir.addEdge(.{
        .from_id = 1,
        .to_id = 2,
        .from_x = 1,
        .from_y = 1,
        .to_x = 1,
        .to_y = 3,
        .path = .{ .direct = {} },
        .edge_index = 0,
    });

    layout_ir.setDimensions(3, 4);

    const node_presets = @import("config.zig").node_presets;
    const result = try renderWithConfig(&layout_ir, allocator, .{
        .node_style_fn = &node_presets.singleBox,
    });
    defer allocator.free(result);

    var lines = std.mem.splitScalar(u8, result, '\n');
    // Explicit node: closed single_box
    try std.testing.expectEqualStrings("┌─┐", lines.next().?);
    try std.testing.expectEqualStrings("│E│", lines.next().?);
    try std.testing.expectEqualStrings("└─┘", lines.next().?);
    // Gap (edge)
    _ = lines.next();
    _ = lines.next();
    // Implicit node: open_single (no TR, no BL)
    const impl_top = lines.next().?;
    try std.testing.expect(std.mem.startsWith(u8, impl_top, "┌"));
    // Should NOT end with ┐
    try std.testing.expect(!std.mem.endsWith(u8, impl_top, "┐"));
    try std.testing.expectEqualStrings("│I│", lines.next().?);
    const impl_bot = lines.next().?;
    try std.testing.expect(std.mem.endsWith(u8, impl_bot, "┘"));
    // Should NOT start with └
    try std.testing.expect(!std.mem.startsWith(u8, impl_bot, "└"));
}

test "NodeBorder.openVariant and closedVariant" {
    try std.testing.expectEqual(NodeBorder.open_single, NodeBorder.single_box.openVariant());
    try std.testing.expectEqual(NodeBorder.open_heavy, NodeBorder.heavy_box.openVariant());
    try std.testing.expectEqual(NodeBorder.open_double, NodeBorder.double_box.openVariant());
    try std.testing.expectEqual(NodeBorder.open_rounded, NodeBorder.rounded_box.openVariant());

    try std.testing.expectEqual(NodeBorder.single_box, NodeBorder.open_single.closedVariant());
    try std.testing.expectEqual(NodeBorder.heavy_box, NodeBorder.open_heavy.closedVariant());
    try std.testing.expectEqual(NodeBorder.double_box, NodeBorder.open_double.closedVariant());
    try std.testing.expectEqual(NodeBorder.rounded_box, NodeBorder.open_rounded.closedVariant());

    // 1-row: open → angle, closed → bracket
    try std.testing.expectEqual(NodeBorder.angle, NodeBorder.bracket.openVariant());
    try std.testing.expectEqual(NodeBorder.bracket, NodeBorder.angle.closedVariant());

    // Idempotent
    try std.testing.expectEqual(NodeBorder.open_single, NodeBorder.open_single.openVariant());
    try std.testing.expectEqual(NodeBorder.single_box, NodeBorder.single_box.closedVariant());
}

test "1-row default: no Y expansion" {
    const allocator = std.testing.allocator;

    var layout_ir = LayoutIR.init(allocator);
    defer layout_ir.deinit();

    try layout_ir.addNode(.{ .id = 1, .label = "A", .x = 0, .y = 0, .width = 3, .center_x = 1, .level = 0, .level_position = 0 });
    try layout_ir.addNode(.{ .id = 2, .label = "B", .x = 0, .y = 3, .width = 3, .center_x = 1, .level = 1, .level_position = 0 });

    try layout_ir.addEdge(.{
        .from_id = 1,
        .to_id = 2,
        .from_x = 1,
        .from_y = 1,
        .to_x = 1,
        .to_y = 3,
        .path = .{ .direct = {} },
        .edge_index = 0,
    });

    layout_ir.setDimensions(3, 4);

    // Default config → bracket → 1-row → no expansion
    const result = try render(&layout_ir, allocator);
    defer allocator.free(result);

    var lines = std.mem.splitScalar(u8, result, '\n');
    try std.testing.expectEqualStrings("[A]", lines.next().?);
    _ = lines.next(); // edge
    _ = lines.next(); // edge
    try std.testing.expectEqualStrings("[B]", lines.next().?);
}

// ── Color system tests ──────────────────────────────────────────────────────

test "resolveColorAt: flat colors ignore t" {
    // .default always returns CellColor.none regardless of t
    const d0 = resolveColorAt(.default, 0.0);
    const d1 = resolveColorAt(.default, 1.0);
    try std.testing.expect(!d0.isSet());
    try std.testing.expect(!d1.isSet());

    // .ansi256 returns same value regardless of t
    const a0 = resolveColorAt(.{ .ansi256 = 196 }, 0.0);
    const a1 = resolveColorAt(.{ .ansi256 = 196 }, 1.0);
    try std.testing.expectEqual(CellColor.Tag.ansi, a0.tag);
    try std.testing.expectEqual(@as(u8, 196), a0.ansiIndex());
    try std.testing.expectEqual(@as(u32, @bitCast(a0)), @as(u32, @bitCast(a1)));

    // .rgb returns same value regardless of t
    const r0 = resolveColorAt(.{ .rgb = .{ .r = 255, .g = 128, .b = 0 } }, 0.0);
    const r1 = resolveColorAt(.{ .rgb = .{ .r = 255, .g = 128, .b = 0 } }, 0.7);
    try std.testing.expectEqual(CellColor.Tag.rgb, r0.tag);
    try std.testing.expectEqual(@as(u8, 255), r0.r());
    try std.testing.expectEqual(@as(u8, 128), r0.g());
    try std.testing.expectEqual(@as(u8, 0), r0.b());
    try std.testing.expectEqual(@as(u32, @bitCast(r0)), @as(u32, @bitCast(r1)));
}

test "resolveColorAt: gradient produces varying colors" {
    const grad: Color = .{ .gradient = .{
        .map = &colormaps.ColorMap.turbo,
        .from = 0.0,
        .to = 1.0,
    } };

    const c0 = resolveColorAt(grad, 0.0);
    const c5 = resolveColorAt(grad, 0.5);
    const c1 = resolveColorAt(grad, 1.0);

    // All must be RGB
    try std.testing.expectEqual(CellColor.Tag.rgb, c0.tag);
    try std.testing.expectEqual(CellColor.Tag.rgb, c5.tag);
    try std.testing.expectEqual(CellColor.Tag.rgb, c1.tag);

    // Different positions must produce different colors
    try std.testing.expect(@as(u32, @bitCast(c0)) != @as(u32, @bitCast(c5)));
    try std.testing.expect(@as(u32, @bitCast(c5)) != @as(u32, @bitCast(c1)));
    try std.testing.expect(@as(u32, @bitCast(c0)) != @as(u32, @bitCast(c1)));
}

test "resolveColorAt: gradient with sub-range maps correctly" {
    const grad: Color = .{ .gradient = .{
        .map = &colormaps.ColorMap.turbo,
        .from = 0.2,
        .to = 0.8,
    } };

    // t=0.0 maps to colormap position 0.2, t=1.0 maps to 0.8
    const at_start = resolveColorAt(grad, 0.0);
    const at_end = resolveColorAt(grad, 1.0);

    // Compare with direct full-range sampling at 0.2 and 0.8
    const full: Color = .{ .gradient = .{
        .map = &colormaps.ColorMap.turbo,
        .from = 0.0,
        .to = 1.0,
    } };
    const ref_start = resolveColorAt(full, 0.2);
    const ref_end = resolveColorAt(full, 0.8);

    try std.testing.expectEqual(@as(u32, @bitCast(ref_start)), @as(u32, @bitCast(at_start)));
    try std.testing.expectEqual(@as(u32, @bitCast(ref_end)), @as(u32, @bitCast(at_end)));
}

// ── Buffer2D bg plane tests ─────────────────────────────────────────────────

test "Buffer2D: bg plane is lazy" {
    const allocator = std.testing.allocator;
    var buf = try Buffer2D.init(allocator, 10, 5);
    defer buf.deinit(allocator);

    // Initially no bg plane
    try std.testing.expect(!buf.hasBgPlane());
    try std.testing.expectEqual(CellColor.none, buf.getBgColor(0, 0));
    try std.testing.expect(buf.getBgColorRow(0) == null);

    // After setBgColor, plane is allocated
    buf.setBgColor(3, 2, CellColor.ansi256(42));
    try std.testing.expect(buf.hasBgPlane());

    // Written value is readable
    try std.testing.expectEqual(@as(u8, 42), buf.getBgColor(3, 2).ansiIndex());

    // Other cells remain default
    try std.testing.expectEqual(CellColor.none, buf.getBgColor(0, 0));

    // Row access works
    const row = buf.getBgColorRow(2).?;
    try std.testing.expectEqual(@as(u8, 42), row[3].ansiIndex());
}

// ── paintNode color wiring test ─────────────────────────────────────────────

test "paintNode: border_color and text_color applied to correct cells" {
    const allocator = std.testing.allocator;
    var buf = try Buffer2D.init(allocator, 10, 3);
    defer buf.deinit(allocator);

    const node_render = @import("nodes.zig");

    // Fake a layout node at x=1 with label "AB", width=4 → [AB]
    const node = ir_mod.LayoutNode(usize){
        .id = 1,
        .label = "AB",
        .x = 1,
        .y = 0,
        .width = 4,
        .center_x = 2,
        .level = 0,
        .level_position = 0,
    };

    const style = TerminalNodeStyle{
        .border = .bracket,
        .border_color = .{ .ansi256 = 196 }, // red
        .text_color = .{ .ansi256 = 33 }, // blue
    };

    node_render.paintNode(&buf, &node, false, style, 0, 1);

    // '[' at x=1 should have border color (196)
    try std.testing.expectEqual(@as(u21, '['), buf.get(1, 0));
    try std.testing.expectEqual(@as(u8, 196), buf.getColor(1, 0).ansiIndex());

    // 'A' at x=2 should have text color (33)
    try std.testing.expectEqual(@as(u21, 'A'), buf.get(2, 0));
    try std.testing.expectEqual(@as(u8, 33), buf.getColor(2, 0).ansiIndex());

    // 'B' at x=3 should have text color (33)
    try std.testing.expectEqual(@as(u21, 'B'), buf.get(3, 0));
    try std.testing.expectEqual(@as(u8, 33), buf.getColor(3, 0).ansiIndex());

    // ']' at x=4 should have border color (196)
    try std.testing.expectEqual(@as(u21, ']'), buf.get(4, 0));
    try std.testing.expectEqual(@as(u8, 196), buf.getColor(4, 0).ansiIndex());
}

test "paintNode: bg_color populates bg plane" {
    const allocator = std.testing.allocator;
    var buf = try Buffer2D.init(allocator, 10, 3);
    defer buf.deinit(allocator);

    const node_render = @import("nodes.zig");

    const node = ir_mod.LayoutNode(usize){
        .id = 1,
        .label = "X",
        .x = 0,
        .y = 0,
        .width = 3,
        .center_x = 1,
        .level = 0,
        .level_position = 0,
    };

    const style = TerminalNodeStyle{
        .border = .bracket,
        .bg_color = .{ .rgb = .{ .r = 50, .g = 100, .b = 150 } },
    };

    try std.testing.expect(!buf.hasBgPlane());
    node_render.paintNode(&buf, &node, false, style, 0, 1);
    try std.testing.expect(buf.hasBgPlane());

    // All 3 cells of [X] should have bg color
    const bg0 = buf.getBgColor(0, 0);
    try std.testing.expectEqual(CellColor.Tag.rgb, bg0.tag);
    try std.testing.expectEqual(@as(u8, 50), bg0.r());
    try std.testing.expectEqual(@as(u8, 100), bg0.g());
}

// ── 1-row centering in multi-row level test ─────────────────────────────────

test "1-row node centered in 3-row level band" {
    const allocator = std.testing.allocator;

    var layout_ir = LayoutIR.init(allocator);
    defer layout_ir.deinit();

    // Two nodes at same level: one will be styled as single_box (3-row),
    // one as bracket (1-row). Use separate X positions.
    try layout_ir.addNode(.{ .id = 1, .label = "A", .x = 0, .y = 0, .width = 3, .center_x = 1, .level = 0, .level_position = 0 });
    try layout_ir.addNode(.{ .id = 2, .label = "B", .x = 6, .y = 0, .width = 3, .center_x = 7, .level = 0, .level_position = 1 });

    layout_ir.setDimensions(10, 3);

    const result = try renderWithConfig(&layout_ir, allocator, .{
        .node_style_fn = &struct {
            fn f(ctx: NodeStyleContext) TerminalNodeStyle {
                if (std.mem.eql(u8, ctx.label, "A"))
                    return .{ .border = .single_box };
                return .{ .border = .bracket };
            }
        }.f,
    });
    defer allocator.free(result);

    // Layout: 3-row band. A is 3-row box, B is 1-row centered at row 1.
    var lines = std.mem.splitScalar(u8, result, '\n');
    const row0 = lines.next().?;
    const row1 = lines.next().?;
    const row2 = lines.next().?;

    // Row 0: A's top border "┌─┐", B has "│" connector at center_x=7
    try std.testing.expect(row0.len >= 3);
    // Row 1: A's label "│A│", B has "[B]" centered
    try std.testing.expect(std.mem.indexOf(u8, row1, "[B]") != null);
    // Row 2: A's bottom border "└─┘", B has "│" connector at center_x=7
    try std.testing.expect(row2.len >= 3);

    // Verify A renders as 3-row box
    try std.testing.expect(std.mem.indexOf(u8, row0, "┌") != null);
    try std.testing.expect(std.mem.indexOf(u8, row2, "└") != null);
}

// ── Serialization bg escape test ────────────────────────────────────────────

test "serialization emits bg escape in truecolor mode" {
    const allocator = std.testing.allocator;

    var layout_ir = LayoutIR.init(allocator);
    defer layout_ir.deinit();

    try layout_ir.addNode(.{ .id = 1, .label = "X", .x = 0, .y = 0, .width = 3, .center_x = 1, .level = 0, .level_position = 0 });
    layout_ir.setDimensions(3, 1);

    const result = try renderWithConfig(&layout_ir, allocator, .{
        .color_mode = .truecolor,
        .node_style_fn = &struct {
            fn f(_: NodeStyleContext) TerminalNodeStyle {
                return .{
                    .border = .bracket,
                    .bg_color = .{ .rgb = .{ .r = 25, .g = 50, .b = 75 } },
                };
            }
        }.f,
    });
    defer allocator.free(result);

    // Must contain \x1b[48;2; (truecolor bg escape)
    try std.testing.expect(std.mem.indexOf(u8, result, "\x1b[48;2;") != null);
    // Must contain the RGB values 025;050;075
    try std.testing.expect(std.mem.indexOf(u8, result, "025;050;075") != null);
}

test "serialization omits bg escape when no bg_color set" {
    const allocator = std.testing.allocator;

    var layout_ir = LayoutIR.init(allocator);
    defer layout_ir.deinit();

    try layout_ir.addNode(.{ .id = 1, .label = "X", .x = 0, .y = 0, .width = 3, .center_x = 1, .level = 0, .level_position = 0 });
    layout_ir.setDimensions(3, 1);

    const result = try renderWithConfig(&layout_ir, allocator, .{
        .color_mode = .truecolor,
    });
    defer allocator.free(result);

    // Must NOT contain \x1b[48; (no bg escape)
    try std.testing.expect(std.mem.indexOf(u8, result, "\x1b[48;") == null);
}
