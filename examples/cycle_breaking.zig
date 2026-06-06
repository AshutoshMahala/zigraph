//! Cycle Breaking Demo
//!
//! Demonstrates how zigraph handles cyclic graphs using DFS-based cycle breaking.
//! Back edges are automatically detected, reversed for layering, and rendered
//! with distinct visual styling (dashed lines in SVG, dashed arrows in Unicode).
//!
//! Run with: zig build run-cycle

const std = @import("std");
const zigraph = @import("zigraph");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    std.debug.print(
        \\
        \\zigraph - Cycle Breaking Demo
        \\==============================
        \\
        \\
    , .{});

    // --- Example 1: Simple feedback loop ---
    {
        std.debug.print("Example 1: Simple Feedback Loop\n", .{});
        std.debug.print("--------------------------------\n", .{});

        var graph = zigraph.Graph.init(allocator);
        defer graph.deinit();

        try graph.addNode(1, "Input");
        try graph.addNode(2, "Process");
        try graph.addNode(3, "Output");

        try graph.addEdge(1, 2);
        try graph.addEdge(2, 3);
        try graph.addEdgeLabeled(3, 1, "feedback"); // Creates a cycle!

        const output = try zigraph.render(&graph, allocator, .{
            .cycle_breaking = .depth_first,
        });
        defer allocator.free(output);

        std.debug.print("{s}\n", .{output});
        std.debug.print("  (⇡ dashed arrow = reversed back edge)\n\n", .{});
    }

    // --- Example 2: Build system with retry ---
    {
        std.debug.print("Example 2: Build System with Retry\n", .{});
        std.debug.print("------------------------------------\n", .{});

        var graph = zigraph.Graph.init(allocator);
        defer graph.deinit();

        try graph.addNode(1, "Fetch");
        try graph.addNode(2, "Build");
        try graph.addNode(3, "Test");
        try graph.addNode(4, "Deploy");

        try graph.addEdge(1, 2);
        try graph.addEdge(2, 3);
        try graph.addEdge(3, 4);
        try graph.addEdgeLabeled(3, 1, "retry on fail"); // Test fails → restart
        try graph.addEdgeLabeled(4, 2, "hotfix"); // Deploy issue → rebuild

        var ir = try zigraph.layout(&graph, allocator, .{
            .cycle_breaking = .depth_first,
            .crossing_reducers = &zigraph.crossing.quality,
            .positioning = .brandes_kopf,
            .node_spacing = 4,
        });
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .edge_palette = &zigraph.color.ansi_dark,
        });
        defer allocator.free(output);

        std.debug.print("{s}\n", .{output});

        // SVG export showing dashed reversed edges
        const svg = try zigraph.svg.render(&ir, allocator, .{
            .stitch_splines = true,
        });
        defer allocator.free(svg);

        var f = try std.Io.Dir.cwd().createFile(io, "cycle_breaking.svg", .{});
        defer f.close(io);
        var wbuf1: [4096]u8 = undefined;
        var fw1 = std.Io.File.writer(f, io, &wbuf1);
        try fw1.interface.writeAll(svg);
        std.debug.print(">>> SVG exported to: cycle_breaking.svg\n", .{});
        std.debug.print("    (reversed edges rendered as dashed lines)\n\n", .{});
    }

    // --- Example 3: State machine ---
    {
        std.debug.print("Example 3: State Machine\n", .{});
        std.debug.print("-------------------------\n", .{});

        var graph = zigraph.Graph.init(allocator);
        defer graph.deinit();

        try graph.addNode(1, "Idle");
        try graph.addNode(2, "Running");
        try graph.addNode(3, "Paused");
        try graph.addNode(4, "Done");

        try graph.addEdgeLabeled(1, 2, "start");
        try graph.addEdgeLabeled(2, 3, "pause");
        try graph.addEdgeLabeled(3, 2, "resume"); // cycle: Paused ↔ Running
        try graph.addEdgeLabeled(2, 4, "finish");
        try graph.addEdgeLabeled(3, 4, "cancel");

        const output = try zigraph.render(&graph, allocator, .{
            .cycle_breaking = .depth_first,
            .node_spacing = 4,
        });
        defer allocator.free(output);

        std.debug.print("{s}\n\n", .{output});
    }

    // --- Example 4: Two-node cycle (A ↔ B) ---
    {
        std.debug.print("Example 4: Two-Node Cycle (A ↔ B)\n", .{});
        std.debug.print("-----------------------------------\n", .{});

        var graph = zigraph.Graph.init(allocator);
        defer graph.deinit();

        try graph.addNode(1, "A");
        try graph.addNode(2, "B");

        try graph.addEdgeLabeled(1, 2, "forward");
        try graph.addEdgeLabeled(2, 1, "back"); // cycle!

        var ir = try zigraph.layout(&graph, allocator, .{
            .cycle_breaking = .depth_first,
        });
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{});
        defer allocator.free(output);

        std.debug.print("{s}\n", .{output});

        const svg = try zigraph.svg.render(&ir, allocator, .{
            .stitch_splines = true,
        });
        defer allocator.free(svg);

        var f = try std.Io.Dir.cwd().createFile(io, "cycle_two_node.svg", .{});
        defer f.close(io);
        var wbuf2: [4096]u8 = undefined;
        var fw2 = std.Io.File.writer(f, io, &wbuf2);
        try fw2.interface.writeAll(svg);
        std.debug.print(">>> SVG exported to: cycle_two_node.svg\n\n", .{});
    }

    // --- Example 5: Self-loop (A → A) ---
    {
        std.debug.print("Example 5: Self-Loop (A → A)\n", .{});
        std.debug.print("-----------------------------\n", .{});

        var graph = zigraph.Graph.init(allocator);
        defer graph.deinit();

        try graph.addNode(1, "A");
        try graph.addNode(2, "B");

        try graph.addEdge(1, 2);
        try graph.addEdgeLabeled(1, 1, "self"); // self-loop!

        var ir = try zigraph.layout(&graph, allocator, .{
            .cycle_breaking = .depth_first,
        });
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{});
        defer allocator.free(output);

        std.debug.print("{s}\n", .{output});

        const svg = try zigraph.svg.render(&ir, allocator, .{
            .stitch_splines = true,
        });
        defer allocator.free(svg);

        var f = try std.Io.Dir.cwd().createFile(io, "cycle_self_loop.svg", .{});
        defer f.close(io);
        var wbuf3: [4096]u8 = undefined;
        var fw3 = std.Io.File.writer(f, io, &wbuf3);
        try fw3.interface.writeAll(svg);
        std.debug.print(">>> SVG exported to: cycle_self_loop.svg\n\n", .{});
    }

    // --- Example 5: Cyclic graph with subgraphs ---
    {
        std.debug.print("Example 5: Cycle inside Subgraph\n", .{});
        std.debug.print("---------------------------------\n", .{});

        var graph = zigraph.Graph.init(allocator);
        defer graph.deinit();

        try graph.addNode(1, "A");
        try graph.addNode(2, "B");
        try graph.addNode(3, "C");
        try graph.addNode(4, "D");

        try graph.addEdge(1, 2);
        try graph.addEdge(2, 3);
        try graph.addEdgeLabeled(3, 1, "back"); // cycle: A→B→C→A
        try graph.addEdge(2, 4); // D branches out

        const sg = try graph.addSubgraph("Loop");
        try graph.putNodes(&.{ 1, 2, 3 }).inside(sg);

        const output = try zigraph.render(&graph, allocator, .{
            .cycle_breaking = .depth_first,
            .edge_palette = &zigraph.color.ansi_dark,
        });
        defer allocator.free(output);

        std.debug.print("{s}\n", .{output});
        std.debug.print("  (Cycle A→B→C→A inside 'Loop' subgraph, D outside)\n\n", .{});
    }
}
