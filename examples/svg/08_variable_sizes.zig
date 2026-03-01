//! # 08 — Variable Node Sizes
//!
//! Demonstrates nodes with different widths and heights in both
//! Sugiyama (hierarchical) and Force-Directed (FDG) layouts.
//!
//! **What you'll learn:** `NodeOptions` for explicit width/height,
//! how variable-sized nodes affect layout spacing and edge routing,
//! and how to make nodes collapsible/expandable in the browser.
//!
//! Outputs:
//! - `08a_variable_sizes_sugiyama.svg` — static SVG
//! - `08b_variable_sizes_fdg.svg`      — static SVG
//! - `08c_collapsible.html`            — interactive: click nodes to collapse/expand
//!
//! Run: `zig build run-svg_08_variable_sizes`

const std = @import("std");
const zigraph = @import("zigraph");

fn writeSvg(name: []const u8, svg_data: []const u8) !void {
    var path_buf: [256]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "assets/gallery/{s}.svg", .{name}) catch return;
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    try file.writeAll(svg_data);
    std.debug.print("  ✓ {s} ({d} bytes)\n", .{ path, svg_data.len });
}

// ── Custom node style that shows the dimensions ────────────────────────────

fn sizedNodeStyle(ctx: zigraph.NodeStyleContext) zigraph.NodeStyle {
    // Color-code by height: tall nodes get blue, normal get green, wide get orange
    const fill: []const u8 = if (ctx.height > 80) "#dbeafe" // tall → blue
        else if (ctx.width > 150) "#ffedd5" // wide → orange
        else "#dcfce7"; // normal → green

    const stroke: []const u8 = if (ctx.height > 80) "#3b82f6" else if (ctx.width > 150) "#f97316" else "#22c55e";

    // Build SVG with dimensions shown
    const svg = std.fmt.allocPrint(ctx.arena,
        \\<rect x="0" y="0" width="{d}" height="{d}" rx="6" ry="6"/>
        \\<text x="{d}" y="{d}" text-anchor="middle" font-family="monospace" font-size="12" fill="#333" stroke="none">{s}</text>
        \\<text x="{d}" y="{d}" text-anchor="middle" font-family="monospace" font-size="9" fill="#999" stroke="none">{d}×{d}px</text>
    , .{
        ctx.width,           ctx.height,
        ctx.width / 2,       ctx.height / 2,
        ctx.label,           ctx.width / 2,
        ctx.height / 2 + 16, ctx.width,
        ctx.height,
    }) catch "";

    return .{ .shape_svg = svg, .fill = fill, .stroke = stroke };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n── 08: Variable Node Sizes ──\n\n", .{});

    // ──────────────────────────────────────────────────────────────────────
    //  Sugiyama layout with mixed sizes
    // ──────────────────────────────────────────────────────────────────────
    {
        var g = zigraph.Graph.init(allocator);
        defer g.deinit();

        // Mix of sizes: default, tall card, wide banner, small chip
        try g.addNode(1, "Start"); // default size
        try g.addNode(2, zigraph.NodeOptions{ .label = "Tall Card", .width = 12, .height = 4 });
        try g.addNode(3, zigraph.NodeOptions{ .label = "Wide Banner", .width = 20, .height = 1 });
        try g.addNode(4, "Normal");
        try g.addNode(5, zigraph.NodeOptions{ .label = "Dashboard", .width = 18, .height = 5 });
        try g.addNode(6, "End");

        try g.addEdge(1, 2);
        try g.addEdge(1, 3);
        try g.addEdge(2, 4);
        try g.addEdge(3, 4);
        try g.addEdge(4, 5);
        try g.addEdge(5, 6);

        var ir = try zigraph.layout(&g, allocator, .{
            .routing = .spline,
        });
        defer ir.deinit();

        const svg = try zigraph.svg.render(&ir, allocator, .{
            .node_style_fn = &sizedNodeStyle,
            .stitch_splines = true,
        });
        defer allocator.free(svg);

        try writeSvg("08a_variable_sizes_sugiyama", svg);
    }

    // ──────────────────────────────────────────────────────────────────────
    //  FDG layout with mixed sizes
    // ──────────────────────────────────────────────────────────────────────
    {
        var g = zigraph.Graph.init(allocator);
        defer g.deinit();

        try g.addNode(1, "Hub");
        try g.addNode(2, zigraph.NodeOptions{ .label = "Service A", .width = 14, .height = 3 });
        try g.addNode(3, zigraph.NodeOptions{ .label = "Service B", .width = 14, .height = 3 });
        try g.addNode(4, zigraph.NodeOptions{ .label = "Database", .width = 18, .height = 4 });
        try g.addNode(5, "Cache");
        try g.addNode(6, "Logger");

        try g.addEdge(1, 2);
        try g.addEdge(1, 3);
        try g.addEdge(2, 4);
        try g.addEdge(3, 4);
        try g.addEdge(2, 5);
        try g.addEdge(3, 6);

        var ir = try zigraph.layout(&g, allocator, .{
            .algorithm = .{ .fruchterman_reingold = .{} },
        });
        defer ir.deinit();

        const svg = try zigraph.svg.render(&ir, allocator, .{
            .node_style_fn = &sizedNodeStyle,
        });
        defer allocator.free(svg);

        try writeSvg("08b_variable_sizes_fdg", svg);
    }

    // ──────────────────────────────────────────────────────────────────────
    //  Interactive HTML: click to collapse/expand children
    // ──────────────────────────────────────────────────────────────────────
    {
        var g = zigraph.Graph.init(allocator);
        defer g.deinit();

        // A deeper graph that benefits from collapsing
        //        Controller
        //       /     |     \
        //    Auth   Logic   Notify
        //    |       / \       |
        //   Users  Calc  Store Email
        //                  |
        //                 DB
        try g.addNode(1, zigraph.NodeOptions{ .label = "Controller", .width = 14, .height = 2 });
        try g.addNode(2, "Auth");
        try g.addNode(3, zigraph.NodeOptions{ .label = "Logic", .width = 12, .height = 3 });
        try g.addNode(4, "Notify");
        try g.addNode(5, "Users");
        try g.addNode(6, "Calc");
        try g.addNode(7, zigraph.NodeOptions{ .label = "Store", .width = 14, .height = 2 });
        try g.addNode(8, "Email");
        try g.addNode(9, zigraph.NodeOptions{ .label = "DB", .width = 16, .height = 3 });

        try g.addEdge(1, 2);
        try g.addEdge(1, 3);
        try g.addEdge(1, 4);
        try g.addEdge(2, 5);
        try g.addEdge(3, 6);
        try g.addEdge(3, 7);
        try g.addEdge(4, 8);
        try g.addEdge(7, 9);

        var ir = try zigraph.layout(&g, allocator, .{ .routing = .spline });
        defer ir.deinit();

        const nodes = ir.getNodes();
        const edges = ir.getEdges();
        const cw: usize = 10;
        const lh: usize = 24;
        const pad: usize = 20;
        const svg_w = ir.getWidth() * cw + pad * 2 + 60;
        const svg_h = ir.getHeight() * lh + pad * 2 + 60;

        const file = try std.fs.cwd().createFile("assets/gallery/08c_collapsible.html", .{});
        defer file.close();
        const w = file.writer();

        // ── HTML + CSS ──
        try w.writeAll(
            \\<!DOCTYPE html>
            \\<html lang="en">
            \\<head>
            \\<meta charset="UTF-8">
            \\<meta name="viewport" content="width=device-width, initial-scale=1.0">
            \\<title>zigraph — Collapsible Nodes</title>
            \\<style>
            \\  * { margin: 0; padding: 0; box-sizing: border-box; }
            \\  body { font-family: system-ui, sans-serif; background: #f8fafc; }
            \\  header { background: #1e293b; color: white; padding: 12px 24px; }
            \\  header h1 { font-size: 18px; font-weight: 600; }
            \\  header .hint { font-size: 13px; color: #94a3b8; margin-top: 2px; }
            \\  #canvas { width: 100%; height: calc(100vh - 56px); }
            \\  .node-group { cursor: pointer; }
            \\  .node-group:hover rect { filter: brightness(0.93); }
            \\  .node-group.collapsed rect { stroke-dasharray: 6,3; }
            \\  .node-group.collapsed .badge { display: block; }
            \\  .node-group.hidden { display: none; }
            \\  .edge-line.hidden { display: none; }
            \\  .badge { display: none; font-size: 10px; font-weight: bold; }
            \\  .collapse-icon { font-size: 13px; font-family: monospace; fill: #666; }
            \\</style>
            \\</head>
            \\<body>
            \\<header>
            \\  <h1>zigraph — Variable Sizes + Collapse/Expand</h1>
            \\  <div class="hint">Click a node to collapse its children • Click again to expand</div>
            \\</header>
            \\
        );

        // ── SVG ──
        try w.print(
            \\<svg id="canvas" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {d} {d}">
            \\<rect width="100%" height="100%" fill="#f8fafc"/>
            \\
            \\<defs>
            \\  <marker id="arrow" markerWidth="8" markerHeight="8" refX="8" refY="4"
            \\          orient="auto" markerUnits="userSpaceOnUse">
            \\    <polygon points="0 0, 8 4, 0 8" fill="#94a3b8"/>
            \\  </marker>
            \\</defs>
            \\
            \\<g id="edges">
            \\
        , .{ svg_w, svg_h });

        // Edges
        for (edges) |edge| {
            const fx = edge.from_x * cw + pad;
            const fy = edge.from_y * lh + pad;
            const tx = edge.to_x * cw + pad;
            const ty = edge.to_y * lh + pad;
            try w.print(
                \\  <line class="edge-line" data-from="{d}" data-to="{d}"
                \\        x1="{d}" y1="{d}" x2="{d}" y2="{d}"
                \\        stroke="#94a3b8" stroke-width="1.5" marker-end="url(#arrow)"/>
                \\
            , .{ edge.from_id, edge.to_id, fx, fy, tx, ty });
        }

        try w.writeAll("</g>\n\n<g id=\"nodes\">\n");

        // Build adjacency: who are each node's direct children?
        // We encode this as data-children="2,3,4" on each node group.
        var children_buf: [9][64]u8 = undefined;
        var children_lens: [9]usize = .{ 0, 0, 0, 0, 0, 0, 0, 0, 0 };

        // edges in IR: from_id → to_id
        for (edges) |edge| {
            // Find parent index (from_id maps to index from_id-1)
            const pi = edge.from_id -| 1;
            if (pi < 9) {
                const len = children_lens[pi];
                if (len < 60) {
                    if (len > 0) {
                        children_buf[pi][len] = ',';
                        children_lens[pi] += 1;
                    }
                    const written = std.fmt.bufPrint(children_buf[pi][children_lens[pi]..], "{d}", .{edge.to_id}) catch "";
                    children_lens[pi] += written.len;
                }
            }
        }

        // Nodes
        for (nodes) |node| {
            if (node.kind != .explicit and node.kind != .implicit) continue;
            const px = node.x * cw + pad;
            const py = node.y * lh + pad;
            const pw = node.width * cw;
            const ph = node.height * lh;

            // Color by size
            const fill: []const u8 = if (ph > 60) "#dbeafe" else if (pw > 140) "#ffedd5" else "#dcfce7";
            const stroke: []const u8 = if (ph > 60) "#3b82f6" else if (pw > 140) "#f97316" else "#22c55e";

            const ci = node.id -| 1;
            const child_str: []const u8 = if (ci < 9) children_buf[ci][0..children_lens[ci]] else "";
            const has_children = child_str.len > 0;

            try w.print(
                \\  <g class="node-group" data-id="{d}" data-children="{s}"
                \\     transform="translate({d},{d})">
                \\    <rect x="0" y="0" width="{d}" height="{d}" rx="6" ry="6"
                \\          fill="{s}" stroke="{s}" stroke-width="1.5"/>
                \\    <text x="{d}" y="{d}" text-anchor="middle" font-family="monospace"
                \\          font-size="12" fill="#333" stroke="none">{s}</text>
                \\    <text x="{d}" y="{d}" text-anchor="middle" font-family="monospace"
                \\          font-size="9" fill="#999" stroke="none">{d}×{d}px</text>
                \\
            , .{
                node.id,     child_str,
                px,          py,
                pw,          ph,
                fill,        stroke,
                pw / 2,      ph / 2,
                node.label,  pw / 2,
                ph / 2 + 16, pw,
                ph,
            });

            // Collapse/expand indicator (only for nodes with children)
            if (has_children) {
                try w.print(
                    \\    <text class="collapse-icon" x="{d}" y="14" text-anchor="end">▼</text>
                    \\    <text class="badge" x="{d}" y="14" fill="#dc2626">●</text>
                    \\
                , .{ pw - 4, pw - 4 });
            }

            try w.writeAll("  </g>\n");
        }

        try w.writeAll("</g>\n</svg>\n\n");

        // ── JavaScript ──
        try w.writeAll(
            \\<script>
            \\(function() {
            \\  const collapsed = new Set();
            \\  const hidden = new Set();
            \\
            \\  function getChildren(id) {
            \\    const el = document.querySelector(`.node-group[data-id="${id}"]`);
            \\    if (!el) return [];
            \\    const c = el.getAttribute('data-children');
            \\    if (!c) return [];
            \\    return c.split(',').map(Number).filter(n => n > 0);
            \\  }
            \\
            \\  // Recursively collect all descendants
            \\  function descendants(id) {
            \\    const result = [];
            \\    const stack = getChildren(id);
            \\    while (stack.length) {
            \\      const cid = stack.pop();
            \\      if (result.includes(cid)) continue;
            \\      result.push(cid);
            \\      stack.push(...getChildren(cid));
            \\    }
            \\    return result;
            \\  }
            \\
            \\  function updateVisibility() {
            \\    // Recompute hidden set from all collapsed nodes
            \\    hidden.clear();
            \\    for (const cid of collapsed) {
            \\      for (const d of descendants(cid)) hidden.add(d);
            \\    }
            \\
            \\    // Apply to nodes
            \\    document.querySelectorAll('.node-group').forEach(el => {
            \\      const id = parseInt(el.getAttribute('data-id'));
            \\      el.classList.toggle('hidden', hidden.has(id));
            \\    });
            \\
            \\    // Apply to edges: hide if either endpoint is hidden
            \\    document.querySelectorAll('.edge-line').forEach(el => {
            \\      const from = parseInt(el.getAttribute('data-from'));
            \\      const to   = parseInt(el.getAttribute('data-to'));
            \\      el.classList.toggle('hidden', hidden.has(from) || hidden.has(to));
            \\    });
            \\  }
            \\
            \\  document.getElementById('nodes').addEventListener('click', (evt) => {
            \\    const group = evt.target.closest('.node-group');
            \\    if (!group) return;
            \\    const id = parseInt(group.getAttribute('data-id'));
            \\    const children = getChildren(id);
            \\    if (children.length === 0) return; // leaf node, nothing to collapse
            \\
            \\    if (collapsed.has(id)) {
            \\      collapsed.delete(id);
            \\      group.classList.remove('collapsed');
            \\      // Update icon
            \\      const icon = group.querySelector('.collapse-icon');
            \\      if (icon) icon.textContent = '▼';
            \\    } else {
            \\      collapsed.add(id);
            \\      group.classList.add('collapsed');
            \\      const icon = group.querySelector('.collapse-icon');
            \\      if (icon) icon.textContent = '►';
            \\    }
            \\    updateVisibility();
            \\  });
            \\})();
            \\</script>
            \\</body>
            \\</html>
            \\
        );

        std.debug.print("  ✓ assets/gallery/08c_collapsible.html\n", .{});
    }

    std.debug.print("\n  Variable-sized nodes laid out with Sugiyama and FDG.\n", .{});
    std.debug.print("  Color coding: green=normal, blue=tall, orange=wide.\n", .{});
    std.debug.print("  Open 08c_collapsible.html in a browser for collapse/expand.\n\n", .{});
}
