//! Example: Layout Presets
//!
//! Demonstrates the curated preset configurations for common use cases.
//! Presets provide sensible defaults so you don't need to configure each option.

const std = @import("std");
const zigraph = @import("zigraph");
const presets = zigraph.presets;

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("\n", .{});
    std.debug.print("╔════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║  Layout Presets Demo                                       ║\n", .{});
    std.debug.print("╚════════════════════════════════════════════════════════════╝\n", .{});

    // Build a sample DAG for Sugiyama demos
    var dag = zigraph.Graph.init(allocator);
    defer dag.deinit();

    // Diamond pattern with branches
    try dag.addNode(1, "A");
    try dag.addNode(2, "B");
    try dag.addNode(3, "C");
    try dag.addNode(4, "D");
    try dag.addNode(5, "E");
    try dag.addNode(6, "F");

    try dag.addEdge(1, 2);
    try dag.addEdge(1, 3);
    try dag.addEdge(2, 4);
    try dag.addEdge(3, 4);
    try dag.addEdge(2, 5);
    try dag.addEdge(3, 6);

    // =========================================================================
    // Sugiyama Presets
    // =========================================================================

    std.debug.print("\n┌─────────────────────────────────────────────────────────────┐\n", .{});
    std.debug.print("│  SUGIYAMA PRESETS (hierarchical layout for DAGs)            │\n", .{});
    std.debug.print("└─────────────────────────────────────────────────────────────┘\n", .{});

    // Standard preset
    std.debug.print("\n=== presets.sugiyama.standard() ===\n", .{});
    std.debug.print("Balanced quality and speed. Good for most use cases.\n\n", .{});
    {
        const output = try zigraph.render(&dag, allocator, presets.sugiyama.standard());
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // Fast preset
    std.debug.print("\n=== presets.sugiyama.fast() ===\n", .{});
    std.debug.print("Fastest. Single median pass, minimal processing.\n\n", .{});
    {
        const output = try zigraph.render(&dag, allocator, presets.sugiyama.fast());
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // Quality preset
    std.debug.print("\n=== presets.sugiyama.quality() ===\n", .{});
    std.debug.print("Best quality. Network simplex layering, more crossing passes, spline routing.\n\n", .{});
    {
        const output = try zigraph.render(&dag, allocator, presets.sugiyama.quality());
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // =========================================================================
    // Force-Directed Presets
    // =========================================================================

    std.debug.print("\n┌─────────────────────────────────────────────────────────────┐\n", .{});
    std.debug.print("│  FORCE-DIRECTED PRESETS (any graph type)                    │\n", .{});
    std.debug.print("└─────────────────────────────────────────────────────────────┘\n", .{});

    // Build a graph for FDG (works with any graph, including cyclic)
    var graph = zigraph.Graph.init(allocator);
    defer graph.deinit();

    try graph.addNode(1, "A");
    try graph.addNode(2, "B");
    try graph.addNode(3, "C");
    try graph.addNode(4, "D");
    try graph.addEdge(1, 2);
    try graph.addEdge(2, 3);
    try graph.addEdge(3, 4);
    try graph.addEdge(4, 1); // cycle! FDG handles this fine

    // FDG Standard preset
    std.debug.print("\n=== presets.fdg_presets.standard() ===\n", .{});
    std.debug.print("Fruchterman-Reingold with exact O(N²) forces. Up to ~500 nodes.\n\n", .{});
    {
        const output = try zigraph.render(&graph, allocator, presets.fdg_presets.standard());
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // FDG Fast preset
    std.debug.print("\n=== presets.fdg_presets.fast() ===\n", .{});
    std.debug.print("Barnes-Hut O(N log N) approximation. Scales to 10k+ nodes.\n\n", .{});
    {
        const output = try zigraph.render(&graph, allocator, presets.fdg_presets.fast());
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }

    // =========================================================================
    // Preset Metadata
    // =========================================================================

    std.debug.print("\n┌─────────────────────────────────────────────────────────────┐\n", .{});
    std.debug.print("│  PRESET METADATA                                            │\n", .{});
    std.debug.print("└─────────────────────────────────────────────────────────────┘\n", .{});

    std.debug.print("\nPresets include metadata for validation:\n\n", .{});

    const sug = presets.sugiyama.preset(.standard);
    std.debug.print("  {s}:\n", .{sug.name});
    std.debug.print("    Requirements: non_empty={}, acyclic={}, all_directed={}\n", .{
        sug.requirements.non_empty,
        sug.requirements.acyclic,
        sug.requirements.all_directed,
    });

    const fdg_p = presets.fdg_presets.preset(.fast);
    std.debug.print("  {s}:\n", .{fdg_p.name});
    std.debug.print("    Requirements: non_empty={}, acyclic={}, all_directed={}\n", .{
        fdg_p.requirements.non_empty,
        fdg_p.requirements.acyclic,
        fdg_p.requirements.all_directed,
    });

    std.debug.print("\n=== Done ===\n", .{});
}
