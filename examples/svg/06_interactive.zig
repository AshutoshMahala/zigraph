//! # 06 — Interactive
//!
//! Hover highlights + click-to-log using `global_style` and `global_script`.
//! Open the SVG in a browser and try hovering over nodes and clicking them.
//!
//! **What you'll learn:** `global_style` for CSS hover effects,
//! `global_script` for JavaScript interactivity, `extra_attrs` for
//! adding CSS classes and data attributes to elements.
//!
//! Run: `zig build run-svg-06`

const std = @import("std");
const zigraph = @import("zigraph");

fn writeSvg(io: std.Io, name: []const u8, svg: []const u8) !void {
    var path_buf: [256]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "assets/gallery/{s}.svg", .{name}) catch return;
    var file = try std.Io.Dir.cwd().createFile(io, path, .{});
    defer file.close(io);
    var wbuf: [4096]u8 = undefined;
    var fw = std.Io.File.writer(file, io, &wbuf);
    try fw.interface.writeAll(svg);
    std.debug.print("  ✓ {s} ({d} bytes)\n", .{ path, svg.len });
}

// ── Node style with CSS class + data attribute ─────────────────────────────

fn interactiveNode(ctx: zigraph.NodeStyleContext) zigraph.NodeStyle {
    // Add a CSS class so global_style can target it,
    // plus a data-id for the click handler.
    const extra = std.fmt.allocPrint(ctx.arena,
        "class=\"node\" data-id=\"{d}\"", .{ctx.node_id},
    ) catch null;

    var style = zigraph.shapes.rounded_rectangle(ctx);
    style.fill = "#f0f9ff";
    style.stroke = "#0284c7";
    style.extra_attrs = extra;
    return style;
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    std.debug.print("\n── 06: Interactive ──\n\n", .{});

    var g = zigraph.Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "Click me!");
    try g.addNode(2, "Hover here");
    try g.addNode(3, "Try both");
    try g.addNode(4, "Output");

    try g.addEdge(1, 3);
    try g.addEdge(2, 3);
    try g.addEdge(3, 4);

    var ir = try zigraph.layout(&g, allocator, .{});
    defer ir.deinit();

    const svg = try zigraph.svg.render(&ir, allocator, .{
        .node_style_fn = &interactiveNode,
        .edge_style_fn = &zigraph.svg.monoEdgeStyle,

        // CSS transitions for smooth hover effects
        .global_style =
            \\<style>
            \\  .node { cursor: pointer; transition: all 0.2s ease; }
            \\  .node:hover { filter: brightness(0.92); transform-origin: center; }
            \\  .node:hover rect { stroke-width: 2.5; }
            \\  .node.selected rect { stroke: #dc2626; stroke-width: 2.5; }
            \\  .node.selected text { fill: #dc2626; }
            \\</style>
        ,

        // Click handler: toggle "selected" class, log to console
        .global_script =
            \\<script>
            \\  document.querySelectorAll('.node').forEach(el => {
            \\    el.addEventListener('click', () => {
            \\      el.classList.toggle('selected');
            \\      const id = el.getAttribute('data-id');
            \\      const label = el.querySelector('text')?.textContent;
            \\      console.log(`Node ${id} (${label}): ${el.classList.contains('selected') ? 'selected' : 'deselected'}`);
            \\    });
            \\  });
            \\</script>
        ,
    });
    defer allocator.free(svg);

    try writeSvg(io, "06_interactive", svg);
    std.debug.print("\n  Open 06_interactive.svg in a browser.\n", .{});
    std.debug.print("  Hover for highlight, click to toggle selection.\n\n", .{});
}
