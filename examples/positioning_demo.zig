//! Example: Positioning Algorithms
//!
//! Demonstrates the three positioning algorithms side-by-side:
//!   - `.compact`     — left-to-right packing (default, collision-free)
//!   - `.barycentric` — barycentric nudge on top of `.compact` baseline
//!   - `.brandes_kopf` — widest-level-first + iterative refinement
//!
//! Run with: zig build run-positioning

const std = @import("std");
const zigraph = @import("zigraph");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    std.debug.print("\n", .{});
    std.debug.print("╔════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║  Positioning Algorithms Demo                               ║\n", .{});
    std.debug.print("╚════════════════════════════════════════════════════════════╝\n", .{});

    // =========================================================================
    // Graph 1: Asymmetric tree — one branch much wider than the other
    // This is where Brandes-Köpf really shines: it centers parents over children.
    // =========================================================================
    std.debug.print("\n┌─────────────────────────────────────────────────────────────┐\n", .{});
    std.debug.print("│  Graph 1: Asymmetric Tree                                   │\n", .{});
    std.debug.print("└─────────────────────────────────────────────────────────────┘\n", .{});

    var tree = zigraph.Graph.init(allocator);
    defer tree.deinit();

    try tree.addNode(1, "Root");
    try tree.addNode(2, "Leaf");
    try tree.addNode(3, "Branch");
    try tree.addNode(4, "W");
    try tree.addNode(5, "X");
    try tree.addNode(6, "Y");
    try tree.addNode(7, "Z");

    try tree.addEdge(1, 2); // Root → Leaf (just one child, no grandchildren)
    try tree.addEdge(1, 3); // Root → Branch (has 4 grandchildren)
    try tree.addEdge(3, 4);
    try tree.addEdge(3, 5);
    try tree.addEdge(3, 6);
    try tree.addEdge(3, 7);

    try renderAllPositionings(&tree, allocator);

    // =========================================================================
    // Graph 2: Diamond DAG — shows convergence behavior
    // =========================================================================
    std.debug.print("\n┌─────────────────────────────────────────────────────────────┐\n", .{});
    std.debug.print("│  Graph 2: Diamond DAG                                       │\n", .{});
    std.debug.print("└─────────────────────────────────────────────────────────────┘\n", .{});

    var diamond = zigraph.Graph.init(allocator);
    defer diamond.deinit();

    try diamond.addNode(1, "Start");
    try diamond.addNode(2, "Parse");
    try diamond.addNode(3, "Validate");
    try diamond.addNode(4, "Transform");
    try diamond.addNode(5, "Merge");
    try diamond.addNode(6, "Output");

    try diamond.addEdge(1, 2);
    try diamond.addEdge(1, 3);
    try diamond.addEdge(2, 4);
    try diamond.addEdge(3, 4);
    try diamond.addEdge(3, 5);
    try diamond.addEdge(4, 6);
    try diamond.addEdge(5, 6);

    try renderAllPositionings(&diamond, allocator);

    // =========================================================================
    // Graph 3: Wide fan-out — shows how each handles many children
    // =========================================================================
    std.debug.print("\n┌─────────────────────────────────────────────────────────────┐\n", .{});
    std.debug.print("│  Graph 3: Wide Fan-out                                      │\n", .{});
    std.debug.print("└─────────────────────────────────────────────────────────────┘\n", .{});

    var fan = zigraph.Graph.init(allocator);
    defer fan.deinit();

    try fan.addNode(1, "Hub");
    try fan.addNode(2, "A");
    try fan.addNode(3, "B");
    try fan.addNode(4, "C");
    try fan.addNode(5, "D");
    try fan.addNode(6, "E");
    try fan.addNode(7, "Sink");

    try fan.addEdge(1, 2);
    try fan.addEdge(1, 3);
    try fan.addEdge(1, 4);
    try fan.addEdge(1, 5);
    try fan.addEdge(1, 6);
    try fan.addEdge(2, 7);
    try fan.addEdge(3, 7);
    try fan.addEdge(4, 7);
    try fan.addEdge(5, 7);
    try fan.addEdge(6, 7);

    try renderAllPositionings(&fan, allocator);

    // =========================================================================
    // Summary
    // =========================================================================
    std.debug.print("\n┌─────────────────────────────────────────────────────────────┐\n", .{});
    std.debug.print("│  Summary                                                    │\n", .{});
    std.debug.print("└─────────────────────────────────────────────────────────────┘\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  .compact      Default. Left-to-right packing respecting crossing\n", .{});
    std.debug.print("                order. Fast, guaranteed no overlaps. Best general choice.\n\n", .{});
    std.debug.print("  .barycentric  Starts from .compact baseline, then nudges nodes toward\n", .{});
    std.debug.print("                connected neighbours. Compact, graph-aware.\n\n", .{});
    std.debug.print("  .brandes_kopf Places the widest level first, centres parents over\n", .{});
    std.debug.print("                children and vice versa. Best for trees/DAGs.\n\n", .{});
    std.debug.print("  Recommendation: use .compact (the default) unless you have a specific\n", .{});
    std.debug.print("  reason to try the others.\n", .{});

    std.debug.print("\n=== Done ===\n", .{});
}

fn renderAllPositionings(g: *const zigraph.Graph, allocator: std.mem.Allocator) !void {
    const configs = [_]struct { name: []const u8, pos: zigraph.Positioning }{
        .{ .name = "positioning = .compact (default)", .pos = .compact },
        .{ .name = "positioning = .barycentric", .pos = .barycentric },
        .{ .name = "positioning = .brandes_kopf", .pos = .brandes_kopf },
    };

    for (configs) |cfg| {
        std.debug.print("\n--- {s} ---\n\n", .{cfg.name});

        const output = zigraph.render(g, allocator, .{
            .positioning = cfg.pos,
        }) catch |err| {
            std.debug.print("  (error: {s})\n", .{@errorName(err)});
            continue;
        };
        defer allocator.free(output);
        std.debug.print("{s}\n", .{output});
    }
}
