//! Fuzz testing for zigraph
//!
//! These tests use random/adversarial inputs to find edge cases.
//! Run with: zig build test
//!
//! For coverage-guided fuzzing, use: zig build test -Dfuzz=true
//!
//! Fuzz targets:
//! 1. Graph construction - random node/edge sequences
//! 2. Cycle detection - random edges that may form cycles
//! 3. Layout pipeline - various graph shapes
//! 4. Unicode rendering - pathological labels
//! 5. JSON output - verify always produces valid JSON

const std = @import("std");
const zigraph = @import("root.zig");
const Graph = zigraph.Graph;

// ============================================================================
// Fuzz: Graph Construction
// ============================================================================

// Fuzz graph construction with random addNode/addEdge sequences.
// Ensures no crashes or memory leaks regardless of input order.
test "fuzz: graph construction" {
    const allocator = std.testing.allocator;

    // Seed patterns to test various edge cases
    const patterns = [_][]const u8{
        // Empty
        &.{},
        // Single node
        &.{0x01},
        // Linear chain
        &.{ 0x01, 0x02, 0x03, 0xE1, 0x02, 0xE2, 0x03 },
        // Diamond
        &.{ 0x01, 0x02, 0x03, 0x04, 0xE1, 0x02, 0xE1, 0x03, 0xE2, 0x04, 0xE3, 0x04 },
        // Self-loop attempt (should handle gracefully)
        &.{ 0x01, 0xE1, 0x01 },
        // Duplicate nodes
        &.{ 0x01, 0x01, 0x01 },
        // Duplicate edges
        &.{ 0x01, 0x02, 0xE1, 0x02, 0xE1, 0x02 },
        // Many nodes
        &.{ 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A },
        // Random-ish pattern
        &.{ 0xFF, 0xFE, 0x01, 0xE1, 0xFE, 0xEF, 0xFE },
    };

    for (patterns) |input| {
        try fuzzGraphConstruction(allocator, input);
    }
}

fn fuzzGraphConstruction(allocator: std.mem.Allocator, input: []const u8) !void {
    var graph = Graph.init(allocator);
    defer graph.deinit();

    var i: usize = 0;
    while (i < input.len) {
        const byte = input[i];

        if (byte >= 0xE0) {
            // Edge command: next two bytes are from/to
            if (i + 2 < input.len) {
                const from = input[i + 1];
                const to = input[i + 2];
                // Use addEdgeAutoCreate to handle missing nodes gracefully
                graph.addEdgeAutoCreate(from, to) catch {};
                i += 3;
            } else {
                i += 1;
            }
        } else {
            // Node command
            var label_buf: [8]u8 = undefined;
            const label = std.fmt.bufPrint(&label_buf, "N{d}", .{byte}) catch "N";
            graph.addNode(byte, label) catch {};
            i += 1;
        }
    }

    // Verify graph is in consistent state
    _ = graph.nodeCount();
    _ = graph.edges.items.len;
}

// ============================================================================
// Fuzz: Cycle Detection
// ============================================================================

// Fuzz cycle detection with random edges that may form cycles.
test "fuzz: cycle detection" {
    const allocator = std.testing.allocator;

    // Edge lists that may or may not form cycles
    const edge_sets = [_][]const [2]usize{
        // No edges
        &.{},
        // Linear (no cycle)
        &.{ .{ 1, 2 }, .{ 2, 3 }, .{ 3, 4 } },
        // Cycle
        &.{ .{ 1, 2 }, .{ 2, 3 }, .{ 3, 1 } },
        // Diamond (no cycle)
        &.{ .{ 1, 2 }, .{ 1, 3 }, .{ 2, 4 }, .{ 3, 4 } },
        // Complex cycle
        &.{ .{ 1, 2 }, .{ 2, 3 }, .{ 3, 4 }, .{ 4, 2 } },
        // Self-loop
        &.{.{ 1, 1 }},
        // Two-node cycle
        &.{ .{ 1, 2 }, .{ 2, 1 } },
        // Large graph with cycle
        &.{ .{ 1, 2 }, .{ 2, 3 }, .{ 3, 4 }, .{ 4, 5 }, .{ 5, 6 }, .{ 6, 7 }, .{ 7, 8 }, .{ 8, 9 }, .{ 9, 1 } },
    };

    for (edge_sets) |edges| {
        var graph = Graph.init(allocator);
        defer graph.deinit();

        for (edges) |edge| {
            try graph.addEdgeAutoCreate(edge[0], edge[1]);
        }

        // Should not crash
        const has_cycle = try graph.hasCycle(allocator);
        _ = has_cycle;

        // Validate should also work
        var validation = try graph.validate(allocator);
        defer validation.deinit();
    }
}

// ============================================================================
// Fuzz: Layout Pipeline
// ============================================================================

// Fuzz the entire layout pipeline with various graph shapes.
test "fuzz: layout pipeline" {
    const allocator = std.testing.allocator;

    // Various graph structures
    const graph_defs = [_]struct {
        nodes: usize,
        edges: []const [2]usize,
    }{
        // Empty (should error)
        .{ .nodes = 0, .edges = &.{} },
        // Single node
        .{ .nodes = 1, .edges = &.{} },
        // Two nodes, no edge
        .{ .nodes = 2, .edges = &.{} },
        // Simple chain
        .{ .nodes = 3, .edges = &.{ .{ 1, 2 }, .{ 2, 3 } } },
        // Wide graph (many nodes at same level)
        .{ .nodes = 5, .edges = &.{ .{ 1, 2 }, .{ 1, 3 }, .{ 1, 4 }, .{ 1, 5 } } },
        // Deep graph
        .{ .nodes = 10, .edges = &.{ .{ 1, 2 }, .{ 2, 3 }, .{ 3, 4 }, .{ 4, 5 }, .{ 5, 6 }, .{ 6, 7 }, .{ 7, 8 }, .{ 8, 9 }, .{ 9, 10 } } },
        // Complex diamond
        .{ .nodes = 7, .edges = &.{ .{ 1, 2 }, .{ 1, 3 }, .{ 2, 4 }, .{ 2, 5 }, .{ 3, 5 }, .{ 3, 6 }, .{ 4, 7 }, .{ 5, 7 }, .{ 6, 7 } } },
    };

    for (graph_defs) |def| {
        var graph = Graph.init(allocator);
        defer graph.deinit();

        // Add nodes
        for (1..def.nodes + 1) |i| {
            var buf: [16]u8 = undefined;
            const label = std.fmt.bufPrint(&buf, "N{d}", .{i}) catch "N";
            try graph.addNode(i, label);
        }

        // Add edges
        for (def.edges) |edge| {
            graph.addEdge(edge[0], edge[1]) catch {};
        }

        // Try layout (may fail for empty graphs)
        if (zigraph.layout(&graph, allocator, .{})) |result| {
            var ir = result;
            defer ir.deinit();

            // Verify basic invariants
            try std.testing.expect(ir.getNodes().len == graph.nodeCount());
            try std.testing.expect(ir.getLevelCount() > 0 or graph.nodeCount() == 0);
        } else |err| {
            // Empty graph error is expected
            if (def.nodes == 0) {
                try std.testing.expect(err == error.EmptyGraph);
            }
        }
    }
}

// ============================================================================
// Fuzz: Unicode Rendering
// ============================================================================

// Fuzz Unicode renderer with various label contents.
test "fuzz: unicode rendering" {
    const allocator = std.testing.allocator;

    // Pathological label strings
    const labels = [_][]const u8{
        "", // Empty
        "A", // Single char
        "Hello World", // Normal
        "A" ** 100, // Very long
        "🔥", // Emoji (multi-byte UTF-8)
        "日本語", // Non-ASCII
        "A\nB", // Newline (should be handled)
        "A\tB", // Tab
        "[]", // Brackets (edge case for rendering)
        "\"quotes\"", // Quotes
        "back\\slash", // Backslash
    };

    for (labels) |label| {
        var graph = Graph.init(allocator);
        defer graph.deinit();

        try graph.addNode(1, label);
        try graph.addNode(2, "End");
        try graph.addEdge(1, 2);

        // Should not crash
        if (zigraph.render(&graph, allocator, .{})) |output| {
            allocator.free(output);
        } else |_| {
            // Errors are acceptable for malformed input
        }
    }
}

// ============================================================================
// Fuzz: JSON Output
// ============================================================================

// Fuzz JSON renderer - verify output is always valid JSON structure.
test "fuzz: json output validity" {
    const allocator = std.testing.allocator;

    var graph = Graph.init(allocator);
    defer graph.deinit();

    // Build a simple graph
    try graph.addNode(1, "Start");
    try graph.addNode(2, "Middle");
    try graph.addNode(3, "End");
    try graph.addEdge(1, 2);
    try graph.addEdge(2, 3);

    const json_output = try zigraph.exportJson(&graph, allocator, .{});
    defer allocator.free(json_output);

    // Basic JSON structure checks
    try std.testing.expect(json_output.len > 0);
    try std.testing.expect(json_output[0] == '{');
    try std.testing.expect(json_output[json_output.len - 2] == '}'); // -2 for newline

    // Required fields present
    try std.testing.expect(std.mem.indexOf(u8, json_output, "\"version\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_output, "\"nodes\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_output, "\"edges\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_output, "\"width\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_output, "\"height\"") != null);
}

// Fuzz JSON with special characters in labels.
test "fuzz: json escaping" {
    const allocator = std.testing.allocator;

    // Labels that need JSON escaping
    const tricky_labels = [_][]const u8{
        "normal",
        "with space",
        "with\"quote",
        "with\\backslash",
        "with\nnewline",
        "with\ttab",
    };

    for (tricky_labels) |label| {
        var graph = Graph.init(allocator);
        defer graph.deinit();

        try graph.addNode(1, label);

        if (zigraph.exportJson(&graph, allocator, .{})) |json_output| {
            defer allocator.free(json_output);

            // Should produce parseable JSON
            try std.testing.expect(json_output.len > 0);
            try std.testing.expect(json_output[0] == '{');
        } else |_| {
            // Error is acceptable for unparseable labels
        }
    }
}

// ============================================================================
// Fuzz: Edge Cases
// ============================================================================

// Test boundary conditions.
test "fuzz: boundary conditions" {
    const allocator = std.testing.allocator;

    // Node ID edge cases
    const edge_case_ids = [_]usize{
        0, // Zero ID
        1, // Normal
        std.math.maxInt(usize) - 1, // Near max
        // Note: maxInt itself may cause issues with +1 operations
    };

    for (edge_case_ids) |id| {
        var graph = Graph.init(allocator);
        defer graph.deinit();

        graph.addNode(id, "Test") catch continue;
        try std.testing.expect(graph.nodeCount() == 1);
    }
}

// Test that all operations handle disconnected graphs.
test "fuzz: disconnected graph" {
    const allocator = std.testing.allocator;

    var graph = Graph.init(allocator);
    defer graph.deinit();

    // Multiple disconnected components
    try graph.addNode(1, "A1");
    try graph.addNode(2, "A2");
    try graph.addEdge(1, 2);

    try graph.addNode(10, "B1");
    try graph.addNode(11, "B2");
    try graph.addEdge(10, 11);

    try graph.addNode(100, "C1"); // Isolated node

    // Should layout without crash
    var result = try zigraph.layout(&graph, allocator, .{});
    defer result.deinit();

    try std.testing.expect(result.getNodes().len == 5);
}

// ============================================================================
// Stress: Large Graphs
// ============================================================================

// Stress test with larger graphs.
test "stress: 100 node graph" {
    const allocator = std.testing.allocator;

    var graph = Graph.init(allocator);
    defer graph.deinit();

    // Create 10 layers x 10 nodes
    const layers: usize = 10;
    const nodes_per_layer: usize = 10;

    var node_id: usize = 1;
    for (0..layers) |_| {
        for (0..nodes_per_layer) |_| {
            var buf: [8]u8 = undefined;
            const label = std.fmt.bufPrint(&buf, "{d}", .{node_id}) catch "?";
            try graph.addNode(node_id, label);
            node_id += 1;
        }
    }

    // Connect layers
    for (0..layers - 1) |layer| {
        const layer_start = layer * nodes_per_layer + 1;
        const next_layer_start = (layer + 1) * nodes_per_layer + 1;

        for (0..nodes_per_layer) |i| {
            // Connect to 2 nodes in next layer
            try graph.addEdge(layer_start + i, next_layer_start + (i % nodes_per_layer));
            try graph.addEdge(layer_start + i, next_layer_start + ((i + 1) % nodes_per_layer));
        }
    }

    try std.testing.expect(graph.nodeCount() == 100);

    // Should complete without timeout or OOM
    var result = try zigraph.layout(&graph, allocator, .{});
    defer result.deinit();

    try std.testing.expect(result.getNodes().len == 100);
    try std.testing.expect(result.getLevelCount() == 10);
}

// ============================================================================
// Fuzz: Crossing Reducers
// ============================================================================

// Test all crossing reducer presets don't crash.
test "fuzz: crossing reducer presets" {
    const allocator = std.testing.allocator;

    var graph = Graph.init(allocator);
    defer graph.deinit();

    // Build a graph with crossing potential
    try graph.addNode(1, "A");
    try graph.addNode(2, "B");
    try graph.addNode(3, "C");
    try graph.addNode(4, "D");
    try graph.addNode(5, "E");
    try graph.addNode(6, "F");

    // Crossing edges
    try graph.addEdge(1, 4);
    try graph.addEdge(1, 5);
    try graph.addEdge(2, 4);
    try graph.addEdge(2, 6);
    try graph.addEdge(3, 5);
    try graph.addEdge(3, 6);

    // Test each preset
    const presets = [_][]const zigraph.crossing.Reducer{
        &zigraph.crossing.none,
        &zigraph.crossing.fast,
        &zigraph.crossing.balanced,
        &zigraph.crossing.quality,
    };

    for (presets) |preset| {
        var result = try zigraph.layout(&graph, allocator, .{
            .crossing_reducers = preset,
        });
        defer result.deinit();

        try std.testing.expect(result.getNodes().len == 6);
    }
}

// Test custom crossing reducer sequence.
test "fuzz: custom crossing reducer sequence" {
    const allocator = std.testing.allocator;

    var graph = Graph.init(allocator);
    defer graph.deinit();

    try graph.addNode(1, "A");
    try graph.addNode(2, "B");
    try graph.addNode(3, "C");
    try graph.addEdge(1, 2);
    try graph.addEdge(1, 3);

    // Custom sequence: multiple median passes
    const custom = [_]zigraph.crossing.Reducer{
        zigraph.crossing.medianReducer(2),
        zigraph.crossing.adjacentExchangeReducer(1),
        zigraph.crossing.medianReducer(1),
        zigraph.crossing.adjacentExchangeReducer(1),
    };

    var result = try zigraph.layout(&graph, allocator, .{
        .crossing_reducers = &custom,
    });
    defer result.deinit();

    try std.testing.expect(result.getNodes().len == 3);
}

// ============================================================================
// Fuzz: SVG Rendering
// ============================================================================

// Test SVG rendering with various configurations.
test "fuzz: svg rendering" {
    const allocator = std.testing.allocator;

    var graph = Graph.init(allocator);
    defer graph.deinit();

    try graph.addNode(1, "Start");
    try graph.addNode(2, "Middle");
    try graph.addNode(3, "End");
    try graph.addEdge(1, 2);
    try graph.addEdge(2, 3);

    // Test both routing modes
    const routing_modes = [_]zigraph.Routing{ .direct, .spline };

    for (routing_modes) |routing| {
        var ir = try zigraph.layout(&graph, allocator, .{ .routing = routing });
        defer ir.deinit();

        const svg = try zigraph.svg.render(&ir, allocator, .{});
        defer allocator.free(svg);

        // Basic SVG structure
        try std.testing.expect(std.mem.indexOf(u8, svg, "<svg") != null);
        try std.testing.expect(std.mem.indexOf(u8, svg, "</svg>") != null);
    }
}

// Test SVG with control points visible.
test "fuzz: svg control points" {
    const allocator = std.testing.allocator;

    var graph = Graph.init(allocator);
    defer graph.deinit();

    try graph.addNode(1, "A");
    try graph.addNode(2, "B");
    try graph.addEdge(1, 2);

    var ir = try zigraph.layout(&graph, allocator, .{ .routing = .spline });
    defer ir.deinit();

    const svg = try zigraph.svg.render(&ir, allocator, .{
        .show_control_points = true,
        .show_dummy_nodes = true,
    });
    defer allocator.free(svg);

    try std.testing.expect(svg.len > 0);
}

// ============================================================================
// Fuzz: Randomized Stress Test
// ============================================================================

// Randomized graph construction and layout.
test "fuzz: randomized graphs" {
    const allocator = std.testing.allocator;

    var prng = std.Random.DefaultPrng.init(12345);
    const random = prng.random();

    // Run multiple random graphs
    for (0..10) |_| {
        var graph = Graph.init(allocator);
        defer graph.deinit();

        const node_count = random.intRangeAtMost(usize, 5, 50);

        // Add nodes
        for (1..node_count + 1) |i| {
            var buf: [8]u8 = undefined;
            const label = std.fmt.bufPrint(&buf, "{d}", .{i}) catch "?";
            try graph.addNode(i, label);
        }

        // Add random edges (DAG: only from lower to higher ID)
        const edge_count = random.intRangeAtMost(usize, node_count, node_count * 2);
        for (0..edge_count) |_| {
            const from = random.intRangeAtMost(usize, 1, node_count - 1);
            const to = random.intRangeAtMost(usize, from + 1, node_count);
            graph.addEdge(from, to) catch {};
        }

        // Should not crash - layout may include dummy nodes for skip-level edges
        if (zigraph.layout(&graph, allocator, .{})) |result| {
            var ir = result;
            defer ir.deinit();
            // IR nodes >= graph nodes (dummies may be added)
            try std.testing.expect(ir.getNodes().len >= graph.nodeCount());
        } else |_| {}
    }
}

// ============================================================================
// Fuzz: Wide Layer Stress (Adjacent Exchange)
// ============================================================================

// Test wide layers that trigger adjacent exchange skip logic.
test "fuzz: wide layer handling" {
    const allocator = std.testing.allocator;

    var graph = Graph.init(allocator);
    defer graph.deinit();

    // Create wide layer (25 nodes, > 20 threshold)
    try graph.addNode(1, "Root");

    for (2..27) |i| {
        var buf: [8]u8 = undefined;
        const label = std.fmt.bufPrint(&buf, "W{d}", .{i}) catch "?";
        try graph.addNode(i, label);
        try graph.addEdge(1, i);
    }

    // Should complete quickly (adjacent exchange skipped for wide layer)
    var result = try zigraph.layout(&graph, allocator, .{
        .crossing_reducers = &zigraph.crossing.quality,
    });
    defer result.deinit();

    try std.testing.expect(result.getNodes().len == 26);
}

// ============================================================================
// Property-Based Tests: Layout Invariants
// ============================================================================

// Verify that layout output preserves important invariants.
test "property: node count preserved in layout" {
    const allocator = std.testing.allocator;

    // Test various graph sizes
    const sizes = [_]usize{ 1, 2, 5, 10, 20, 50 };

    for (sizes) |n| {
        var graph = Graph.init(allocator);
        defer graph.deinit();

        // Create a chain of n nodes
        for (0..n) |i| {
            var buf: [16]u8 = undefined;
            const label = std.fmt.bufPrint(&buf, "N{d}", .{i}) catch "?";
            try graph.addNode(i, label);
            if (i > 0) {
                try graph.addEdge(i - 1, i);
            }
        }

        var result = try zigraph.layout(&graph, allocator, .{});
        defer result.deinit();

        // IR should have at least as many nodes (dummies may be added)
        try std.testing.expect(result.getNodes().len >= n);

        // Count real nodes (not dummies)
        var real_count: usize = 0;
        for (result.getNodes()) |node| {
            if (node.kind != .dummy) real_count += 1;
        }
        try std.testing.expectEqual(n, real_count);
    }
}

// Verify all coordinates are valid (non-negative).
test "property: coordinates are valid" {
    const allocator = std.testing.allocator;

    var graph = Graph.init(allocator);
    defer graph.deinit();

    // Create a complex graph
    for (0..10) |i| {
        var buf: [16]u8 = undefined;
        const label = std.fmt.bufPrint(&buf, "N{d}", .{i}) catch "?";
        try graph.addNode(i, label);
    }
    // Diamond pattern with skip edges
    try graph.addEdge(0, 1);
    try graph.addEdge(0, 2);
    try graph.addEdge(1, 3);
    try graph.addEdge(2, 3);
    try graph.addEdge(0, 4); // Skip to level 2
    try graph.addEdge(4, 5);
    try graph.addEdge(3, 5);

    var result = try zigraph.layout(&graph, allocator, .{});
    defer result.deinit();

    for (result.getNodes()) |node| {
        // All coordinates should be non-negative (usize is always >= 0)
        // Width should be positive
        try std.testing.expect(node.width > 0);
    }
}

// Verify edges reference valid node IDs.
test "property: edges reference valid nodes" {
    const allocator = std.testing.allocator;

    var graph = Graph.init(allocator);
    defer graph.deinit();

    try graph.addNode(1, "A");
    try graph.addNode(2, "B");
    try graph.addNode(3, "C");
    try graph.addEdge(1, 2);
    try graph.addEdge(2, 3);

    var result = try zigraph.layout(&graph, allocator, .{});
    defer result.deinit();

    // Build set of valid node IDs
    var node_ids = std.AutoHashMap(usize, void).init(allocator);
    defer node_ids.deinit();
    for (result.getNodes()) |node| {
        try node_ids.put(node.id, {});
    }

    // Verify all edges reference valid nodes
    for (result.edges.items) |edge| {
        try std.testing.expect(node_ids.contains(edge.from_id));
        try std.testing.expect(node_ids.contains(edge.to_id));
    }
}

// ============================================================================
// Cycle Detection: Obscure Edge Cases
// ============================================================================

// Self-loop detection.
test "cycle: self-loop detected" {
    const allocator = std.testing.allocator;

    var graph = Graph.init(allocator);
    defer graph.deinit();

    try graph.addNode(1, "A");
    try graph.addEdge(1, 1); // Self-loop

    var result = try graph.validate(allocator);
    defer result.deinit();

    try std.testing.expect(result == .cycle);
}

// Two-node cycle (A -> B -> A).
test "cycle: two-node cycle detected" {
    const allocator = std.testing.allocator;

    var graph = Graph.init(allocator);
    defer graph.deinit();

    try graph.addNode(1, "A");
    try graph.addNode(2, "B");
    try graph.addEdge(1, 2);
    try graph.addEdge(2, 1); // Creates cycle

    var result = try graph.validate(allocator);
    defer result.deinit();

    try std.testing.expect(result == .cycle);
}

// Large cycle (100 nodes in a ring).
test "cycle: large cycle detected" {
    const allocator = std.testing.allocator;

    var graph = Graph.init(allocator);
    defer graph.deinit();

    const n = 100;
    for (0..n) |i| {
        var buf: [16]u8 = undefined;
        const label = std.fmt.bufPrint(&buf, "N{d}", .{i}) catch "?";
        try graph.addNode(i, label);
    }

    // Create ring: 0 -> 1 -> 2 -> ... -> 99 -> 0
    for (0..n) |i| {
        try graph.addEdge(i, (i + 1) % n);
    }

    var result = try graph.validate(allocator);
    defer result.deinit();

    try std.testing.expect(result == .cycle);
}

// Late-added back edge creates cycle.
test "cycle: late back edge detected" {
    const allocator = std.testing.allocator;

    var graph = Graph.init(allocator);
    defer graph.deinit();

    // Build a valid DAG first
    //   0 -> 1 -> 2 -> 3 -> 4
    for (0..5) |i| {
        var buf: [16]u8 = undefined;
        const label = std.fmt.bufPrint(&buf, "N{d}", .{i}) catch "?";
        try graph.addNode(i, label);
    }
    try graph.addEdge(0, 1);
    try graph.addEdge(1, 2);
    try graph.addEdge(2, 3);
    try graph.addEdge(3, 4);

    // Verify it's valid
    var result1 = try graph.validate(allocator);
    defer result1.deinit();
    try std.testing.expect(result1 == .ok);

    // Now add a back edge: 4 -> 1
    try graph.addEdge(4, 1);

    // Should detect cycle
    var result2 = try graph.validate(allocator);
    defer result2.deinit();
    try std.testing.expect(result2 == .cycle);
}

// Subtle back edge in complex graph.
test "cycle: subtle back edge in complex graph" {
    const allocator = std.testing.allocator;

    var graph = Graph.init(allocator);
    defer graph.deinit();

    // Build complex DAG
    //       0
    //      /|\
    //     1 2 3
    //     |/| |
    //     4 5 6
    //      \|/
    //       7
    for (0..8) |i| {
        var buf: [16]u8 = undefined;
        const label = std.fmt.bufPrint(&buf, "N{d}", .{i}) catch "?";
        try graph.addNode(i, label);
    }
    try graph.addEdge(0, 1);
    try graph.addEdge(0, 2);
    try graph.addEdge(0, 3);
    try graph.addEdge(1, 4);
    try graph.addEdge(2, 4);
    try graph.addEdge(2, 5);
    try graph.addEdge(3, 6);
    try graph.addEdge(4, 7);
    try graph.addEdge(5, 7);
    try graph.addEdge(6, 7);

    // Valid so far
    var result1 = try graph.validate(allocator);
    defer result1.deinit();
    try std.testing.expect(result1 == .ok);

    // Add subtle back edge from 7 to 2 (through middle of graph)
    try graph.addEdge(7, 2);

    var result2 = try graph.validate(allocator);
    defer result2.deinit();
    try std.testing.expect(result2 == .cycle);
}

// Multiple disjoint cycles.
test "cycle: multiple disjoint components with cycles" {
    const allocator = std.testing.allocator;

    var graph = Graph.init(allocator);
    defer graph.deinit();

    // Component 1: valid chain 0 -> 1 -> 2
    for (0..3) |i| {
        var buf: [16]u8 = undefined;
        const label = std.fmt.bufPrint(&buf, "A{d}", .{i}) catch "?";
        try graph.addNode(i, label);
    }
    try graph.addEdge(0, 1);
    try graph.addEdge(1, 2);

    // Component 2: cycle 10 -> 11 -> 12 -> 10
    for (10..13) |i| {
        var buf: [16]u8 = undefined;
        const label = std.fmt.bufPrint(&buf, "B{d}", .{i}) catch "?";
        try graph.addNode(i, label);
    }
    try graph.addEdge(10, 11);
    try graph.addEdge(11, 12);
    try graph.addEdge(12, 10); // Cycle!

    var result = try graph.validate(allocator);
    defer result.deinit();

    try std.testing.expect(result == .cycle);
}

// Layout rejects cyclic graph.
test "cycle: layout rejects cyclic graph" {
    const allocator = std.testing.allocator;

    var graph = Graph.init(allocator);
    defer graph.deinit();

    try graph.addNode(1, "A");
    try graph.addNode(2, "B");
    try graph.addEdge(1, 2);
    try graph.addEdge(2, 1); // Cycle

    const result = zigraph.layout(&graph, allocator, .{});
    try std.testing.expectError(error.CycleDetected, result);
}

// ============================================================================
// Security: Resource Limits
// ============================================================================

// Verify max node limit is enforced.
test "security: max node limit enforced" {
    // Verify default constants exist and are reasonable
    try std.testing.expect(Graph.default_max_nodes == 100_000);
    try std.testing.expect(Graph.default_max_edges == 500_000);
    try std.testing.expect(Graph.default_max_edges >= Graph.default_max_nodes);

    // Verify configurable limits work
    const allocator = std.testing.allocator;
    var graph = Graph.initWithOptions(allocator, .{
        .max_nodes = 3,
        .max_edges = 2,
    });
    defer graph.deinit();

    // Add 3 nodes (at limit)
    try graph.addNode(1, "A");
    try graph.addNode(2, "B");
    try graph.addNode(3, "C");

    // 4th node should fail
    try std.testing.expectError(error.OutOfMemory, graph.addNode(4, "D"));

    // Add 2 edges (at limit)
    try graph.addEdge(1, 2);
    try graph.addEdge(2, 3);

    // 3rd edge should fail
    try std.testing.expectError(error.OutOfMemory, graph.addEdge(1, 3));
}
