//! Comptime Graph Example
//!
//! This example demonstrates building and rendering a graph
//! entirely at compile time. The output is embedded in the
//! binary as a string literal - zero runtime cost!
//!
//! Run with: zig build run-comptime-example

const std = @import("std");
const zigraph = @import("zigraph");
const ComptimeGraph = zigraph.ComptimeGraph;

// Build the diagram at compile time
const git_workflow: []const u8 = blk: {
    var g = ComptimeGraph.init();
    g.nodeLabeled(1, "main");
    g.nodeLabeled(2, "develop");
    g.nodeLabeled(3, "feature");
    g.nodeLabeled(4, "hotfix");
    g.edge(1, 2);
    g.edge(2, 3);
    g.edge(1, 4);
    break :blk g.render();
};

const simple_pipeline: []const u8 = blk: {
    var g = ComptimeGraph.init();
    g.nodeLabeled(1, "Build");
    g.nodeLabeled(2, "Test");
    g.nodeLabeled(3, "Deploy");
    g.edge(1, 2);
    g.edge(2, 3);
    break :blk g.render();
};

const diamond_dag: []const u8 = blk: {
    var g = ComptimeGraph.init();
    g.edge(1, 2);
    g.edge(1, 3);
    g.edge(2, 4);
    g.edge(3, 4);
    break :blk g.render();
};

pub fn main() void {
    std.debug.print("=== Comptime Graph Examples ===\n\n", .{});

    std.debug.print("Git Workflow (computed at compile time):\n", .{});
    std.debug.print("{s}\n", .{git_workflow});

    std.debug.print("CI Pipeline:\n", .{});
    std.debug.print("{s}\n", .{simple_pipeline});

    std.debug.print("Diamond DAG:\n", .{});
    std.debug.print("{s}\n", .{diamond_dag});

    // Show that it's truly comptime - print the embedded string's length
    std.debug.print("Sizes (embedded in binary at compile time):\n", .{});
    std.debug.print("  git_workflow: {d} bytes\n", .{git_workflow.len});
    std.debug.print("  simple_pipeline: {d} bytes\n", .{simple_pipeline.len});
    std.debug.print("  diamond_dag: {d} bytes\n", .{diamond_dag.len});
}
