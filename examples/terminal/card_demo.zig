//! Card Node Demo — multi-line box nodes in graph layouts.
//!
//! Shows card nodes (nodes with header + content lines) in graph layouts
//! relevant to graph visualization and compiler pipelines.
//!
//! Run with: zig build run-terminal-card-demo

const std = @import("std");
const zigraph = @import("zigraph");

fn printSection(title: []const u8) void {
    std.debug.print("\n", .{});
    for (0..60) |_| std.debug.print("\xe2\x94\x80", .{});
    std.debug.print("\n  {s}\n", .{title});
    for (0..60) |_| std.debug.print("\xe2\x94\x80", .{});
    std.debug.print("\n\n", .{});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print(
        \\╔══════════════════════════════════════════════════════════╗
        \\║   zigraph — Card Node Demo                              ║
        \\╚══════════════════════════════════════════════════════════╝
        \\
    , .{});

    // ─────────────────────────────────────────────────────────────
    // 1) Compiler pipeline: Source → AST → IR → Machine Code
    // ─────────────────────────────────────────────────────────────
    {
        printSection("1) Compiler pipeline");

        var g = zigraph.Graph.init(allocator);
        defer g.deinit();

        const parse_lines: []const []const u8 = &.{ "tokenize", "build AST" };
        try g.addNode(1, zigraph.NodeOptions{
            .label = "Parser",
            .lines = parse_lines,
        });

        const sema_lines: []const []const u8 = &.{ "type checking", "comptime eval" };
        try g.addNode(2, zigraph.NodeOptions{
            .label = "Semantic Analysis",
            .lines = sema_lines,
        });

        const codegen_lines: []const []const u8 = &.{ "LLVM IR", "machine code" };
        try g.addNode(3, zigraph.NodeOptions{
            .label = "Code Generation",
            .lines = codegen_lines,
        });

        try g.addDiEdge(1, 2);
        try g.addDiEdge(2, 3);

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .color_mode = .ansi256,
            .node_style_fn = &cardNodeStyle,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // ─────────────────────────────────────────────────────────────
    // 2) zigraph render pipeline: Layout → Renderers
    // ─────────────────────────────────────────────────────────────
    {
        printSection("2) zigraph render pipeline");

        var g = zigraph.Graph.init(allocator);
        defer g.deinit();

        const graph_lines: []const []const u8 = &.{ "nodes, edges", "subgraphs" };
        try g.addNode(1, zigraph.NodeOptions{
            .label = "Graph",
            .lines = graph_lines,
        });

        const layout_lines: []const []const u8 = &.{ "layering", "crossing reduction", "positioning", "routing" };
        try g.addNode(2, zigraph.NodeOptions{
            .label = "Sugiyama",
            .lines = layout_lines,
        });

        const term_lines: []const []const u8 = &.{ "Buffer2D", "box-drawing", "ANSI color" };
        try g.addNode(3, zigraph.NodeOptions{
            .label = "Terminal",
            .lines = term_lines,
        });

        const svg_lines: []const []const u8 = &.{ "splines", "gradients" };
        try g.addNode(4, zigraph.NodeOptions{
            .label = "SVG",
            .lines = svg_lines,
        });

        const json_lines: []const []const u8 = &.{"schema v1.2"};
        try g.addNode(5, zigraph.NodeOptions{
            .label = "JSON",
            .lines = json_lines,
        });

        try g.addDiEdge(1, 2);
        try g.addDiEdge(2, 3);
        try g.addDiEdge(2, 4);
        try g.addDiEdge(2, 5);

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .color_mode = .ansi256,
            .node_style_fn = &cardNodeStyle,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // ─────────────────────────────────────────────────────────────
    // 3) Zig allocator hierarchy
    // ─────────────────────────────────────────────────────────────
    {
        printSection("3) Zig allocator hierarchy");

        var g = zigraph.Graph.init(allocator);
        defer g.deinit();

        const gpa_lines: []const []const u8 = &.{ "leak detection", "stack traces" };
        try g.addNode(1, zigraph.NodeOptions{
            .label = "GeneralPurpose",
            .lines = gpa_lines,
        });

        const arena_lines: []const []const u8 = &.{ "bulk free", "no per-item free" };
        try g.addNode(2, zigraph.NodeOptions{
            .label = "Arena",
            .lines = arena_lines,
        });

        const page_lines: []const []const u8 = &.{"mmap/VirtualAlloc"};
        try g.addNode(3, zigraph.NodeOptions{
            .label = "Page Allocator",
            .lines = page_lines,
        });

        try g.addDiEdge(1, 2);
        try g.addDiEdge(1, 3);

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
            .color_mode = .ansi256,
            .node_style_fn = &cardNodeStyle,
        });
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }
}

fn cardNodeStyle(_: zigraph.NodeStyleContext) zigraph.TerminalNodeStyle {
    return .{
        .border = .single_box,
        .text_color = .{ .ansi256 = 252 },
    };
}
