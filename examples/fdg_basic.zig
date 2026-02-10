//! Force-Directed Graph (FDG) Layout — Basic Example
//!
//! Demonstrates force-directed layout with terminal (Unicode) and SVG output.
//! FDG algorithms work on any graph — they don't require a DAG.
//!
//! Run with: zig build run-fdg

const std = @import("std");
const zigraph = @import("zigraph");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print(
        \\zigraph - Force-Directed Graph Layout
        \\======================================
        \\
        \\
    , .{});

    // ── Example 1: Terminal (Unicode) rendering ─────────────────────
    {
        std.debug.print("Example 1: FR → Unicode (terminal)\n", .{});
        std.debug.print("------------------------------------\n\n", .{});

        var graph = zigraph.Graph.init(allocator);
        defer graph.deinit();

        // A cycle! Not a DAG. FR handles this just fine.
        try graph.addNode(1, "Zig");
        try graph.addNode(2, "Fast");
        try graph.addNode(3, "Safe");
        try graph.addNode(4, "Simple");
        try graph.addEdge(1, 2);
        try graph.addEdge(2, 3);
        try graph.addEdge(3, 4);
        try graph.addEdge(4, 1); // cycle!
        try graph.addEdge(1, 3); // cross edge

        const output = try zigraph.render(&graph, allocator, .{
            .algorithm = .{ .fruchterman_reingold = .{} },
        });
        defer allocator.free(output);

        std.debug.print("{s}\n\n", .{output});
    }

    // ── Example 2: SVG export ───────────────────────────────────────
    {
        std.debug.print("Example 2: FR → SVG export\n", .{});
        std.debug.print("---------------------------\n", .{});

        var graph = zigraph.Graph.init(allocator);
        defer graph.deinit();

        // 6-node ring with cross edges — cycles everywhere
        const labels = [_][]const u8{ "A", "B", "C", "D", "E", "F" };
        for (labels, 1..) |label, id| {
            try graph.addNode(id, label);
        }
        try graph.addEdge(1, 2);
        try graph.addEdge(2, 3);
        try graph.addEdge(3, 4);
        try graph.addEdge(4, 5);
        try graph.addEdge(5, 6);
        try graph.addEdge(6, 1); // ring
        try graph.addEdge(1, 4); // cross
        try graph.addEdge(2, 5); // cross

        const svg_output = try zigraph.exportSvg(&graph, allocator, .{
            .algorithm = .{ .fruchterman_reingold = .{} },
        });
        defer allocator.free(svg_output);

        // Write SVG to file
        const cwd = std.fs.cwd();
        cwd.writeFile(.{ .sub_path = "fdg_example.svg", .data = svg_output }) catch |err| {
            std.debug.print("  Could not write fdg_example.svg: {}\n", .{err});
        };
        std.debug.print("  Wrote fdg_example.svg ({d} bytes)\n\n", .{svg_output.len});
    }

    // ── Example 3: FR-Fast (Barnes-Hut) terminal rendering ─────────
    {
        std.debug.print("Example 3: FR-Fast (Barnes-Hut) → Unicode\n", .{});
        std.debug.print("-------------------------------------------\n\n", .{});

        var graph = zigraph.Graph.init(allocator);
        defer graph.deinit();

        try graph.addNode(1, "Hub");
        try graph.addNode(2, "N1");
        try graph.addNode(3, "N2");
        try graph.addNode(4, "N3");
        try graph.addNode(5, "N4");
        try graph.addEdge(1, 2);
        try graph.addEdge(1, 3);
        try graph.addEdge(1, 4);
        try graph.addEdge(1, 5);
        try graph.addEdge(2, 3);
        try graph.addEdge(4, 5);

        const output = try zigraph.render(&graph, allocator, .{
            .algorithm = .{ .fruchterman_reingold_fast = .{} },
        });
        defer allocator.free(output);

        std.debug.print("{s}\n\n", .{output});
    }

    // ── Example 4: Standalone usage + determinism ───────────────────
    {
        std.debug.print("Example 4: Standalone FR + determinism check\n", .{});
        std.debug.print("----------------------------------------------\n", .{});

        var graph = zigraph.Graph.init(allocator);
        defer graph.deinit();

        try graph.addNode(1, "X");
        try graph.addNode(2, "Y");
        try graph.addNode(3, "Z");
        try graph.addEdge(1, 2);
        try graph.addEdge(2, 3);
        try graph.addEdge(3, 1);

        const fr = zigraph.fdg.fruchterman_reingold;
        const fp = zigraph.fdg.fixed_point;

        var r1 = try fr.compute(&graph, allocator, .{ .seed = 42 });
        defer r1.deinit();
        var r2 = try fr.compute(&graph, allocator, .{ .seed = 42 });
        defer r2.deinit();

        std.debug.print("  Iterations: {d}\n", .{r1.iterations});
        for (r1.positions, 0..) |pos, i| {
            const node = graph.nodeAt(i) orelse continue;
            std.debug.print("  [{s}] x={d:.1} y={d:.1}\n", .{
                node.label,
                fp.toFloat(pos.x),
                fp.toFloat(pos.y),
            });
        }

        var identical = true;
        for (r1.positions, r2.positions) |p1, p2| {
            if (p1.x != p2.x or p1.y != p2.y) {
                identical = false;
                break;
            }
        }
        std.debug.print("  Deterministic (seed=42): {}\n\n", .{identical});
    }

    std.debug.print("Done.\n", .{});
}
