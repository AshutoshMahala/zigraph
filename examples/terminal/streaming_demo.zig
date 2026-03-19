//! Streaming render demo — writes graph output directly to stdout
//! without accumulating the full string in memory.
//!
//! Run with: zig build run-streaming-demo

const std = @import("std");
const zigraph = @import("zigraph");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const stdout = std.io.getStdOut().writer();

    try stdout.writeAll(
        \\zigraph — Streaming Render Demo
        \\================================
        \\
        \\This demo renders directly to stdout using the streaming API.
        \\No intermediate string buffer is allocated for the rendered output.
        \\
        \\
    );

    // Build a graph
    var graph = zigraph.Graph.init(allocator);
    defer graph.deinit();

    try graph.addNode(1, "Input");
    try graph.addNode(2, "Parse");
    try graph.addNode(3, "Validate");
    try graph.addNode(4, "Transform");
    try graph.addNode(5, "Output");
    try graph.addEdge(1, 2);
    try graph.addEdge(2, 3);
    try graph.addEdge(2, 4);
    try graph.addEdge(3, 5);
    try graph.addEdge(4, 5);

    // Compute layout (produces a LayoutIR)
    var layout_ir = try zigraph.layout(&graph, allocator, .{});
    defer layout_ir.deinit();

    // Stream-render directly to stdout — no intermediate []u8 allocation
    try zigraph.terminal.renderStreaming(&layout_ir, stdout, allocator);

    try stdout.writeAll(
        \\
        \\You can also use renderStreamingWithConfig for custom styles,
        \\or write to any writer (file, network socket, buffered writer, etc.)
        \\
    );
}
