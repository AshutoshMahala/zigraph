//! Integration tests for the SVG renderer.
//!
//! Extracted from mod.zig to keep it focused on the render pipeline.
//! These tests exercise the full render() path end-to-end.

const std = @import("std");
const ir_mod = @import("../../core/ir.zig");
const LayoutIR = ir_mod.LayoutIR(usize);
const mod = @import("mod.zig");
const render = mod.render;
const config_mod = @import("config.zig");
const NodeStyleContext = config_mod.NodeStyleContext;
const NodeStyle = config_mod.NodeStyle;
const SubgraphStyleContext = config_mod.SubgraphStyleContext;
const SubgraphStyle = config_mod.SubgraphStyle;
const EdgeStyleContext = config_mod.EdgeStyleContext;
const EdgeLabelStyle = config_mod.EdgeLabelStyle;

test "svg: basic render" {
    const allocator = std.testing.allocator;

    var layout = LayoutIR.init(allocator);
    defer layout.deinit();

    try layout.addNode(.{
        .id = 1,
        .label = "Test",
        .x = 0,
        .y = 0,
        .width = 6,
        .center_x = 3,
        .level = 0,
        .level_position = 0,
    });

    layout.setDimensions(10, 5);

    const svg = try render(&layout, allocator, .{});
    defer allocator.free(svg);

    // Should contain SVG structure
    try std.testing.expect(std.mem.indexOf(u8, svg, "<svg") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "</svg>") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "Test") != null);
}

test "svg: edge rendering" {
    const allocator = std.testing.allocator;

    var layout = LayoutIR.init(allocator);
    defer layout.deinit();

    try layout.addNode(.{
        .id = 1,
        .label = "A",
        .x = 0,
        .y = 0,
        .width = 3,
        .center_x = 1,
        .level = 0,
        .level_position = 0,
    });
    try layout.addNode(.{
        .id = 2,
        .label = "B",
        .x = 0,
        .y = 2,
        .width = 3,
        .center_x = 1,
        .level = 1,
        .level_position = 0,
    });

    try layout.addEdge(.{
        .from_id = 1,
        .to_id = 2,
        .from_x = 1,
        .from_y = 1,
        .to_x = 1,
        .to_y = 2,
        .path = .direct,
        .edge_index = 0,
    });

    layout.setDimensions(5, 5);

    const svg = try render(&layout, allocator, .{});
    defer allocator.free(svg);

    // Should contain line element for direct edge
    try std.testing.expect(std.mem.indexOf(u8, svg, "<line") != null);
}

test "svg: corner edge rendering" {
    const allocator = std.testing.allocator;

    var layout = LayoutIR.init(allocator);
    defer layout.deinit();

    try layout.addNode(.{
        .id = 1,
        .label = "A",
        .x = 0,
        .y = 0,
        .width = 3,
        .center_x = 1,
        .level = 0,
        .level_position = 0,
    });
    try layout.addNode(.{
        .id = 2,
        .label = "B",
        .x = 5,
        .y = 4,
        .width = 3,
        .center_x = 6,
        .level = 1,
        .level_position = 0,
    });

    try layout.addEdge(.{
        .from_id = 1,
        .to_id = 2,
        .from_x = 1,
        .from_y = 1,
        .to_x = 6,
        .to_y = 4,
        .path = .{ .corner = .{ .horizontal_y = 2 } },
        .edge_index = 0,
    });

    layout.setDimensions(10, 6);

    // Disable stitch_splines so the per-edge renderEdge path (which handles
    // .corner routing) is exercised instead of the stitched spline path.
    const svg = try render(&layout, allocator, .{ .stitch_splines = false });
    defer allocator.free(svg);

    // Corner edges use path elements with L-shaped segments
    try std.testing.expect(std.mem.indexOf(u8, svg, "<path") != null);
}

test "svg: multiple nodes and edges" {
    const allocator = std.testing.allocator;

    var layout = LayoutIR.init(allocator);
    defer layout.deinit();

    // Build a small diamond: A -> B, A -> C, B -> D, C -> D
    try layout.addNode(.{
        .id = 1,
        .label = "A",
        .x = 5,
        .y = 0,
        .width = 3,
        .center_x = 6,
        .level = 0,
        .level_position = 0,
    });
    try layout.addNode(.{
        .id = 2,
        .label = "B",
        .x = 0,
        .y = 4,
        .width = 3,
        .center_x = 1,
        .level = 1,
        .level_position = 0,
    });
    try layout.addNode(.{
        .id = 3,
        .label = "C",
        .x = 10,
        .y = 4,
        .width = 3,
        .center_x = 11,
        .level = 1,
        .level_position = 1,
    });
    try layout.addNode(.{
        .id = 4,
        .label = "D",
        .x = 5,
        .y = 8,
        .width = 3,
        .center_x = 6,
        .level = 2,
        .level_position = 0,
    });

    for ([_]struct { from: usize, to: usize, idx: usize }{
        .{ .from = 1, .to = 2, .idx = 0 },
        .{ .from = 1, .to = 3, .idx = 1 },
        .{ .from = 2, .to = 4, .idx = 2 },
        .{ .from = 3, .to = 4, .idx = 3 },
    }) |e| {
        try layout.addEdge(.{
            .from_id = e.from,
            .to_id = e.to,
            .from_x = 6,
            .from_y = 1,
            .to_x = 6,
            .to_y = 4,
            .path = .direct,
            .edge_index = e.idx,
        });
    }

    layout.setDimensions(15, 10);

    const svg = try render(&layout, allocator, .{});
    defer allocator.free(svg);

    // Should contain all 4 node labels
    try std.testing.expect(std.mem.indexOf(u8, svg, ">A<") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, ">B<") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, ">C<") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, ">D<") != null);
    // Should have valid SVG structure
    try std.testing.expect(std.mem.indexOf(u8, svg, "<svg") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "</svg>") != null);
}

test "svg: empty layout" {
    const allocator = std.testing.allocator;

    var layout = LayoutIR.init(allocator);
    defer layout.deinit();

    layout.setDimensions(0, 0);

    const svg = try render(&layout, allocator, .{});
    defer allocator.free(svg);

    // Should still produce valid SVG
    try std.testing.expect(std.mem.indexOf(u8, svg, "<svg") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "</svg>") != null);
}

test "svg: colored edges" {
    const allocator = std.testing.allocator;

    var layout = LayoutIR.init(allocator);
    defer layout.deinit();

    try layout.addNode(.{
        .id = 1,
        .label = "A",
        .x = 0,
        .y = 0,
        .width = 3,
        .center_x = 1,
        .level = 0,
        .level_position = 0,
    });
    try layout.addNode(.{
        .id = 2,
        .label = "B",
        .x = 0,
        .y = 4,
        .width = 3,
        .center_x = 1,
        .level = 1,
        .level_position = 0,
    });

    try layout.addEdge(.{
        .from_id = 1,
        .to_id = 2,
        .from_x = 1,
        .from_y = 1,
        .to_x = 1,
        .to_y = 4,
        .path = .direct,
        .edge_index = 0,
    });

    layout.setDimensions(5, 5);

    // Default edge_style_fn does palette cycling (equivalent to old color_edges=true)
    const svg_out = try render(&layout, allocator, .{});
    defer allocator.free(svg_out);

    // Should contain colored stroke from palette
    try std.testing.expect(std.mem.indexOf(u8, svg_out, "stroke=") != null);
    // Should contain marker definitions with zg-m- prefix
    try std.testing.expect(std.mem.indexOf(u8, svg_out, "zg-m-") != null);
}

test "svg: subgraph rendering" {
    const allocator = std.testing.allocator;

    var layout = LayoutIR.init(allocator);
    defer layout.deinit();

    try layout.addNode(.{
        .id = 1,
        .label = "A",
        .x = 5,
        .y = 3,
        .width = 3,
        .center_x = 6,
        .level = 0,
        .level_position = 0,
    });
    try layout.addNode(.{
        .id = 2,
        .label = "B",
        .x = 5,
        .y = 7,
        .width = 3,
        .center_x = 6,
        .level = 1,
        .level_position = 0,
    });

    // Add a subgraph bounding box
    try layout.subgraphs.append(allocator, .{
        .id = 0,
        .parent_id = null,
        .label = "cluster",
        .x = 3,
        .y = 1,
        .width = 10,
        .height = 10,
    });

    layout.setDimensions(20, 15);

    const svg = try render(&layout, allocator, .{});
    defer allocator.free(svg);

    // Should contain subgraph group and rect
    try std.testing.expect(std.mem.indexOf(u8, svg, "id=\"subgraphs\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "stroke-dasharray") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "cluster") != null);
}

test "svg: subgraph rendering disabled" {
    const allocator = std.testing.allocator;

    var layout = LayoutIR.init(allocator);
    defer layout.deinit();

    try layout.subgraphs.append(allocator, .{
        .id = 0,
        .parent_id = null,
        .label = "hidden",
        .x = 0,
        .y = 0,
        .width = 5,
        .height = 5,
    });

    layout.setDimensions(10, 10);

    const svg = try render(&layout, allocator, .{ .show_subgraphs = false });
    defer allocator.free(svg);

    // Should NOT contain subgraph elements
    try std.testing.expect(std.mem.indexOf(u8, svg, "id=\"subgraphs\"") == null);
}

test "svg: global_style and global_script injection" {
    const allocator = std.testing.allocator;

    var layout = LayoutIR.init(allocator);
    defer layout.deinit();

    layout.setDimensions(5, 5);

    const style_content = "<style>.node:hover { opacity: 0.8; }</style>";
    const script_content = "<script>console.log('hello');</script>";

    const svg = try render(&layout, allocator, .{
        .global_style = style_content,
        .global_script = script_content,
    });
    defer allocator.free(svg);

    // Style should be inside <defs>
    const defs_end = std.mem.indexOf(u8, svg, "</defs>").?;
    const style_pos = std.mem.indexOf(u8, svg, ".node:hover").?;
    try std.testing.expect(style_pos < defs_end);

    // Script should be after </g> (nodes group) and before </svg>
    const svg_end = std.mem.indexOf(u8, svg, "</svg>").?;
    const script_pos = std.mem.indexOf(u8, svg, "console.log").?;
    try std.testing.expect(script_pos < svg_end);
    try std.testing.expect(script_pos > defs_end);
}

test "svg: global_style and global_script null by default" {
    const allocator = std.testing.allocator;

    var layout = LayoutIR.init(allocator);
    defer layout.deinit();

    layout.setDimensions(5, 5);

    const svg = try render(&layout, allocator, .{});
    defer allocator.free(svg);

    // Should NOT contain <style> or <script> tags
    try std.testing.expect(std.mem.indexOf(u8, svg, "<style>") == null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "<script>") == null);
}

test "svg: node_style_fn shapes" {
    const allocator = std.testing.allocator;

    var layout = LayoutIR.init(allocator);
    defer layout.deinit();

    try layout.addNode(.{
        .id = 1,
        .label = "Hello",
        .x = 0,
        .y = 0,
        .width = 7,
        .center_x = 3,
        .level = 0,
        .level_position = 0,
    });

    layout.setDimensions(10, 5);

    // Test default (rounded_rectangle)
    const svg_default = try render(&layout, allocator, .{});
    defer allocator.free(svg_default);
    // Should have <g transform=...> wrapper and <rect with rx
    try std.testing.expect(std.mem.indexOf(u8, svg_default, "<g transform=") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg_default, "rx=\"4\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg_default, ">Hello<") != null);

    // Test diamond shape
    const svg_diamond = try render(&layout, allocator, .{
        .node_style_fn = &config_mod.shapes.diamond,
    });
    defer allocator.free(svg_diamond);
    try std.testing.expect(std.mem.indexOf(u8, svg_diamond, "<polygon") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg_diamond, ">Hello<") != null);

    // Test ellipse shape
    const svg_ellipse = try render(&layout, allocator, .{
        .node_style_fn = &config_mod.shapes.ellipse,
    });
    defer allocator.free(svg_ellipse);
    try std.testing.expect(std.mem.indexOf(u8, svg_ellipse, "<ellipse") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg_ellipse, ">Hello<") != null);
}

test "svg: custom node_style_fn" {
    const allocator = std.testing.allocator;

    var layout = LayoutIR.init(allocator);
    defer layout.deinit();

    try layout.addNode(.{
        .id = 1,
        .label = "Custom",
        .x = 0,
        .y = 0,
        .width = 8,
        .center_x = 4,
        .level = 0,
        .level_position = 0,
    });

    layout.setDimensions(10, 5);

    const svg = try render(&layout, allocator, .{
        .node_style_fn = &struct {
            fn style(_: NodeStyleContext) NodeStyle {
                return .{
                    .shape_svg = "<circle cx=\"40\" cy=\"10\" r=\"10\"/><text x=\"40\" y=\"14\" text-anchor=\"middle\" fill=\"#333\" stroke=\"none\">Custom</text>",
                    .fill = "#ff0000",
                    .stroke = "#00ff00",
                };
            }
        }.style,
    });
    defer allocator.free(svg);

    try std.testing.expect(std.mem.indexOf(u8, svg, "fill=\"#ff0000\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "stroke=\"#00ff00\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, ">Custom<") != null);
}

test "svg: custom subgraph_style_fn" {
    const allocator = std.testing.allocator;

    var layout = LayoutIR.init(allocator);
    defer layout.deinit();

    try layout.addNode(.{
        .id = 1,
        .label = "A",
        .x = 2,
        .y = 2,
        .width = 3,
        .center_x = 3,
        .level = 0,
        .level_position = 0,
    });

    // Root-level subgraph
    try layout.subgraphs.append(allocator, .{
        .id = 0,
        .parent_id = null,
        .label = "Root",
        .x = 1,
        .y = 1,
        .width = 8,
        .height = 6,
    });

    // Nested subgraph (depth 1)
    try layout.subgraphs.append(allocator, .{
        .id = 1,
        .parent_id = 0,
        .label = "Nested",
        .x = 2,
        .y = 2,
        .width = 5,
        .height = 3,
    });

    layout.setDimensions(15, 10);

    const svg = try render(&layout, allocator, .{
        .subgraph_style_fn = &struct {
            fn style(ctx: SubgraphStyleContext) SubgraphStyle {
                if (ctx.depth == 0) {
                    return .{
                        .box_svg = std.fmt.allocPrint(ctx.arena,
                            \\<rect x="0" y="0" width="{d}" height="{d}" rx="8" ry="8"/>
                            \\<text x="8" y="16" font-family="monospace" font-size="12" fill="#e5484d" stroke="none">{s}</text>
                        , .{ ctx.width, ctx.height, ctx.label }) catch "",
                        .fill = "#fce8e8",
                        .stroke = "#e5484d",
                    };
                }
                return .{
                    .box_svg = std.fmt.allocPrint(ctx.arena,
                        \\<rect x="0" y="0" width="{d}" height="{d}" rx="4" ry="4"/>
                        \\<text x="4" y="13" font-family="monospace" font-size="11" fill="#30a46c" stroke="none">{s}</text>
                    , .{ ctx.width, ctx.height, ctx.label }) catch "",
                    .fill = "#e6f4ea",
                    .stroke = "#30a46c",
                };
            }
        }.style,
    });
    defer allocator.free(svg);

    // Root subgraph should use red style
    try std.testing.expect(std.mem.indexOf(u8, svg, "fill=\"#fce8e8\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "stroke=\"#e5484d\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, ">Root<") != null);

    // Nested subgraph should use green style
    try std.testing.expect(std.mem.indexOf(u8, svg, "fill=\"#e6f4ea\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "stroke=\"#30a46c\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, ">Nested<") != null);

    // Both should be inside the subgraphs group
    try std.testing.expect(std.mem.indexOf(u8, svg, "id=\"subgraphs\"") != null);
}

test "svg: subgraph depth computation" {
    const allocator = std.testing.allocator;

    var layout = LayoutIR.init(allocator);
    defer layout.deinit();

    // Three-level nesting: root → mid → deep
    try layout.subgraphs.append(allocator, .{
        .id = 10,
        .parent_id = null,
        .label = "root",
        .x = 0,
        .y = 0,
        .width = 20,
        .height = 15,
    });
    try layout.subgraphs.append(allocator, .{
        .id = 20,
        .parent_id = 10,
        .label = "mid",
        .x = 1,
        .y = 1,
        .width = 15,
        .height = 10,
    });
    try layout.subgraphs.append(allocator, .{
        .id = 30,
        .parent_id = 20,
        .label = "deep",
        .x = 2,
        .y = 2,
        .width = 10,
        .height = 5,
    });

    layout.setDimensions(25, 20);

    // Use a style fn that encodes depth into the fill color for testing
    const svg = try render(&layout, allocator, .{
        .subgraph_style_fn = &struct {
            fn style(ctx: SubgraphStyleContext) SubgraphStyle {
                const fills = [_][]const u8{ "#depth0", "#depth1", "#depth2" };
                return .{
                    .box_svg = std.fmt.allocPrint(ctx.arena,
                        \\<rect x="0" y="0" width="{d}" height="{d}"/>
                    , .{ ctx.width, ctx.height }) catch "",
                    .fill = fills[ctx.depth % fills.len],
                };
            }
        }.style,
    });
    defer allocator.free(svg);

    try std.testing.expect(std.mem.indexOf(u8, svg, "fill=\"#depth0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "fill=\"#depth1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "fill=\"#depth2\"") != null);
}

test "svg: edge label default inherits edge stroke" {
    const allocator = std.testing.allocator;

    var layout = LayoutIR.init(allocator);
    defer layout.deinit();

    try layout.addNode(.{ .id = 1, .label = "A", .x = 0, .y = 0, .width = 3, .center_x = 1, .level = 0, .level_position = 0 });
    try layout.addNode(.{ .id = 2, .label = "B", .x = 0, .y = 2, .width = 3, .center_x = 1, .level = 1, .level_position = 0 });

    try layout.addEdge(.{
        .from_id = 1,
        .to_id = 2,
        .from_x = 1,
        .from_y = 0,
        .to_x = 1,
        .to_y = 2,
        .path = .direct,
        .edge_index = 0,
        .label = "depends",
        .directed = true,
    });

    layout.setDimensions(5, 5);

    // Default: label color follows edge stroke from defaultEdgeStyle (radix palette index 0)
    const svg = try render(&layout, allocator, .{ .stitch_splines = false });
    defer allocator.free(svg);

    // Should contain the label text
    try std.testing.expect(std.mem.indexOf(u8, svg, "depends") != null);
    // Should contain font-family="monospace" (default)
    try std.testing.expect(std.mem.indexOf(u8, svg, "font-family=\"monospace\"") != null);
    // Should contain font-size="12" (default)
    try std.testing.expect(std.mem.indexOf(u8, svg, "font-size=\"12\"") != null);
}

test "svg: custom edge_label_style_fn" {
    const allocator = std.testing.allocator;

    var layout = LayoutIR.init(allocator);
    defer layout.deinit();

    try layout.addNode(.{ .id = 1, .label = "A", .x = 0, .y = 0, .width = 3, .center_x = 1, .level = 0, .level_position = 0 });
    try layout.addNode(.{ .id = 2, .label = "B", .x = 0, .y = 2, .width = 3, .center_x = 1, .level = 1, .level_position = 0 });

    try layout.addEdge(.{
        .from_id = 1,
        .to_id = 2,
        .from_x = 1,
        .from_y = 0,
        .to_x = 1,
        .to_y = 2,
        .path = .direct,
        .edge_index = 0,
        .label = "critical",
        .directed = true,
    });

    layout.setDimensions(5, 5);

    const svg = try render(&layout, allocator, .{
        .stitch_splines = false,
        .edge_label_style_fn = &struct {
            fn style(_: EdgeStyleContext) EdgeLabelStyle {
                return .{
                    .color = "#e5484d",
                    .font_family = "sans-serif",
                    .font_size = 16,
                    .extra_attrs = "font-weight=\"bold\"",
                };
            }
        }.style,
    });
    defer allocator.free(svg);

    // Custom color
    try std.testing.expect(std.mem.indexOf(u8, svg, "fill=\"#e5484d\"") != null);
    // Custom font
    try std.testing.expect(std.mem.indexOf(u8, svg, "font-family=\"sans-serif\"") != null);
    // Custom size
    try std.testing.expect(std.mem.indexOf(u8, svg, "font-size=\"16\"") != null);
    // Extra attrs
    try std.testing.expect(std.mem.indexOf(u8, svg, "font-weight=\"bold\"") != null);
    // Label text
    try std.testing.expect(std.mem.indexOf(u8, svg, "critical") != null);
}

test "svg: edge label on_path override" {
    const allocator = std.testing.allocator;

    var layout = LayoutIR.init(allocator);
    defer layout.deinit();

    try layout.addNode(.{ .id = 1, .label = "A", .x = 0, .y = 0, .width = 3, .center_x = 1, .level = 0, .level_position = 0 });
    try layout.addNode(.{ .id = 2, .label = "B", .x = 0, .y = 2, .width = 3, .center_x = 1, .level = 1, .level_position = 0 });

    try layout.addEdge(.{
        .from_id = 1,
        .to_id = 2,
        .from_x = 1,
        .from_y = 0,
        .to_x = 1,
        .to_y = 2,
        .path = .direct,
        .edge_index = 0,
        .label = "flows",
        .directed = true,
    });

    layout.setDimensions(5, 5);

    // Global labels_on_path=false, but per-edge override to true
    const svg = try render(&layout, allocator, .{
        .stitch_splines = false,
        .labels_on_path = false,
        .edge_label_style_fn = &struct {
            fn style(_: EdgeStyleContext) EdgeLabelStyle {
                return .{ .on_path = true };
            }
        }.style,
    });
    defer allocator.free(svg);

    // Should use textPath (on_path=true override)
    try std.testing.expect(std.mem.indexOf(u8, svg, "<textPath") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "edgepath") != null);
}

// ─── XML escaping tests ─────────────────────────────────────────────────────

const helpers = @import("helpers.zig");

test "helpers: xmlEscape escapes all special characters" {
    const allocator = std.testing.allocator;
    const result = helpers.xmlEscape(allocator, "A<B>&C\"D'E");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("A&lt;B&gt;&amp;C&quot;D&apos;E", result);
}

test "helpers: xmlEscape returns original when no escaping needed" {
    const allocator = std.testing.allocator;
    const input = "Hello World";
    const result = helpers.xmlEscape(allocator, input);
    // Should return the same pointer (no allocation)
    try std.testing.expectEqual(input.ptr, result.ptr);
}

test "helpers: writeXmlEscaped streams escaped output" {
    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();
    try helpers.writeXmlEscaped(writer, "<script>alert('xss')</script>");
    const written = fbs.getWritten();
    try std.testing.expectEqualStrings("&lt;script&gt;alert(&apos;xss&apos;)&lt;/script&gt;", written);
}

test "svg: node labels are XML-escaped" {
    const allocator = std.testing.allocator;

    var layout = LayoutIR.init(allocator);
    defer layout.deinit();

    try layout.addNode(.{
        .id = 1,
        .label = "A<B>&C",
        .x = 0,
        .y = 0,
        .width = 8,
        .center_x = 4,
        .level = 0,
        .level_position = 0,
    });

    layout.setDimensions(12, 5);

    const svg = try render(&layout, allocator, .{});
    defer allocator.free(svg);

    // The label should be escaped in the SVG output
    try std.testing.expect(std.mem.indexOf(u8, svg, "A&lt;B&gt;&amp;C") != null);
    // The raw unescaped form should NOT appear
    try std.testing.expect(std.mem.indexOf(u8, svg, "A<B>&C") == null);
}

test "svg: edge labels are XML-escaped" {
    const allocator = std.testing.allocator;

    var layout = LayoutIR.init(allocator);
    defer layout.deinit();

    try layout.addNode(.{ .id = 1, .label = "Src", .x = 0, .y = 0, .width = 5, .center_x = 2, .level = 0, .level_position = 0 });
    try layout.addNode(.{ .id = 2, .label = "Dst", .x = 0, .y = 2, .width = 5, .center_x = 2, .level = 1, .level_position = 0 });
    try layout.addEdge(.{
        .from_id = 1,
        .to_id = 2,
        .from_x = 2,
        .from_y = 1,
        .to_x = 2,
        .to_y = 2,
        .label = "<danger>&\"alert\"",
        .directed = true,
        .edge_index = 0,
        .reversed = false,
        .path = .direct,
    });

    layout.setDimensions(8, 5);

    const svg = try render(&layout, allocator, .{});
    defer allocator.free(svg);

    // The edge label should be escaped
    try std.testing.expect(std.mem.indexOf(u8, svg, "&lt;danger&gt;&amp;&quot;alert&quot;") != null);
}

test "svg: circle shape preset" {
    const allocator = std.testing.allocator;

    var layout = LayoutIR.init(allocator);
    defer layout.deinit();

    try layout.addNode(.{
        .id = 1,
        .label = "O",
        .x = 0,
        .y = 0,
        .width = 4,
        .center_x = 2,
        .level = 0,
        .level_position = 0,
    });

    layout.setDimensions(8, 5);

    const svg = try render(&layout, allocator, .{
        .node_style_fn = &config_mod.shapes.circle,
    });
    defer allocator.free(svg);

    // Should contain a <circle> element
    try std.testing.expect(std.mem.indexOf(u8, svg, "<circle") != null);
}
