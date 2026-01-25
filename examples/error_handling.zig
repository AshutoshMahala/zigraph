//! Example: Error handling for empty and cyclic graphs
//!
//! Demonstrates how zigraph handles invalid graphs with WDP-compliant errors.
//!
//! WDP (Waddling Diagnostic Protocol) provides structured error codes:
//!   Format: Severity.Component.Primary.Sequence
//!   Example: E.Graph.Node.001 = Error in Graph component, Node primary, sequence 001 (MISSING)
//!
//! Namespace: zigraph

const std = @import("std");
const zigraph = @import("zigraph");
const errors = zigraph.errors;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("\n", .{});
    std.debug.print("╔══════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║  zigraph Error Handling Demo (WDP Level 0)                   ║\n", .{});
    std.debug.print("║  Namespace: {s}                                             ║\n", .{errors.NAMESPACE});
    std.debug.print("╚══════════════════════════════════════════════════════════════╝\n", .{});

    // =========================================================================
    // Example 1: Empty graph
    // =========================================================================
    std.debug.print("\n=== Example 1: Empty Graph ===\n\n", .{});
    {
        var g = zigraph.Graph.init(allocator);
        defer g.deinit();

        // Try to layout an empty graph
        const result = zigraph.layout(&g, allocator, .{});

        if (result) |*ir| {
            var layout_ir = ir.*;
            defer layout_ir.deinit();
            std.debug.print("Layout succeeded (unexpected!)\n", .{});
        } else |err| {
            switch (err) {
                error.EmptyGraph => {
                    std.debug.print("  Code: {s}\n", .{errors.Code.EMPTY_GRAPH});
                    std.debug.print("  Desc: Graph has no nodes (MISSING)\n", .{});
                    std.debug.print("  Fix:  Add nodes before calling layout()\n", .{});
                },
                else => std.debug.print("Unexpected error: {}\n", .{err}),
            }
        }
    }

    // =========================================================================
    // Example 2: Cyclic graph
    // =========================================================================
    std.debug.print("\n=== Example 2: Cyclic Graph ===\n\n", .{});
    {
        var g = zigraph.Graph.init(allocator);
        defer g.deinit();

        // Create a cycle: A -> B -> C -> A
        try g.addNode(1, "A");
        try g.addNode(2, "B");
        try g.addNode(3, "C");
        try g.addEdge(1, 2);
        try g.addEdge(2, 3);
        try g.addEdge(3, 1); // Creates cycle!

        // Try to layout
        const result = zigraph.layout(&g, allocator, .{});

        if (result) |*ir| {
            var layout_ir = ir.*;
            defer layout_ir.deinit();
            std.debug.print("Layout succeeded (unexpected!)\n", .{});
        } else |err| {
            switch (err) {
                error.CycleDetected => {
                    std.debug.print("  Code: {s}\n", .{errors.Code.CYCLE_DETECTED});
                    std.debug.print("  Desc: Graph contains a cycle (INVALID DAG)\n", .{});
                    std.debug.print("  Fix:  Remove cyclic edges or use a different algorithm\n", .{});
                },
                else => std.debug.print("Unexpected error: {}\n", .{err}),
            }
        }

        // Get detailed cycle information
        std.debug.print("\n  Detailed validation:\n", .{});
        var validation = try g.validate(allocator);
        defer validation.deinit();

        switch (validation) {
            .ok => std.debug.print("  Graph is valid\n", .{}),
            .empty => std.debug.print("  [{s}] Graph is empty\n", .{errors.Code.EMPTY_GRAPH}),
            .cycle => |info| {
                std.debug.print("  Cycle path: ", .{});
                for (info.path, 0..) |node_idx, i| {
                    if (i > 0) std.debug.print(" -> ", .{});
                    if (g.nodeAt(node_idx)) |node| {
                        std.debug.print("[{s}]", .{node.label});
                    }
                }
                std.debug.print("\n", .{});
            },
        }
    }

    // =========================================================================
    // Example 3: Valid graph (for comparison)
    // =========================================================================
    std.debug.print("\n=== Example 3: Valid DAG ===\n\n", .{});
    {
        var g = zigraph.Graph.init(allocator);
        defer g.deinit();

        // Create a valid DAG
        try g.addNode(1, "Start");
        try g.addNode(2, "Middle");
        try g.addNode(3, "End");
        try g.addEdge(1, 2);
        try g.addEdge(2, 3);

        // Validate first (optional but recommended)
        var validation = try g.validate(allocator);
        defer validation.deinit();

        if (validation == .ok) {
            std.debug.print("Graph validation: OK\n\n", .{});

            // Now layout with confidence
            const output = try zigraph.render(&g, allocator, .{});
            defer allocator.free(output);
            std.debug.print("{s}\n", .{output});
        }
    }

    std.debug.print("=== Done ===\n", .{});
}
