//! Fuzz harness for zigraph
//!
//! Run with: zig test -ffuzz src/fuzz_harness.zig
//!
//! Targets:
//!   graph_construction - Random node/edge sequences
//!   layout_pipeline    - Full layout pipeline
//!   svg_rendering      - SVG output
//!   unicode_rendering  - Unicode terminal output

const std = @import("std");
const Graph = @import("core/graph.zig").Graph;
const root = @import("root.zig");
const crossing = root.crossing;

// ============================================================================
// Fuzz Target: Graph Construction
// ============================================================================

/// Fuzz graph construction with arbitrary byte sequences.
/// Interprets bytes as commands: add node, add edge, etc.
pub fn fuzzGraphConstruction(data: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var graph = Graph.init(allocator);
    defer graph.deinit();

    var i: usize = 0;
    while (i + 2 < data.len) {
        const cmd = data[i];
        const arg1 = data[i + 1];
        const arg2 = data[i + 2];
        i += 3;

        switch (cmd % 4) {
            0 => {
                // Add node
                var label_buf: [32]u8 = undefined;
                const label = std.fmt.bufPrint(&label_buf, "N{d}", .{arg1}) catch "N?";
                graph.addNode(arg1, label) catch {};
            },
            1 => {
                // Add edge
                graph.addEdge(arg1, arg2) catch {};
            },
            2 => {
                // Query node count (exercises internal state)
                _ = graph.nodeCount();
            },
            3 => {
                // Query edge count
                _ = graph.edgeCount();
            },
            else => {},
        }
    }

    // Verify graph is in consistent state
    _ = graph.nodeCount();
    _ = graph.edgeCount();
}

// ============================================================================
// Fuzz Target: Layout Pipeline
// ============================================================================

/// Fuzz the full layout pipeline with random graphs.
pub fn fuzzLayoutPipeline(data: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var graph = Graph.init(allocator);
    defer graph.deinit();

    // Build graph from fuzz data
    var i: usize = 0;
    var node_count: u8 = 0;

    // First byte determines node count (1-64)
    if (data.len > 0) {
        node_count = @min(data[0] % 64 + 1, 64);
        i = 1;
    }

    // Add nodes
    for (0..node_count) |n| {
        var label_buf: [32]u8 = undefined;
        const label = std.fmt.bufPrint(&label_buf, "N{d}", .{n}) catch "N?";
        graph.addNode(n, label) catch {};
    }

    // Add edges from remaining data
    while (i + 1 < data.len) {
        const from = data[i] % node_count;
        const to = data[i + 1] % node_count;
        i += 2;

        if (from != to) {
            graph.addEdge(from, to) catch {};
        }
    }

    // Skip empty graphs
    if (graph.nodeCount() == 0) return;

    // Run layout with different configurations
    const config_byte = if (data.len > 0) data[data.len - 1] else 0;

    // Select crossing reducer based on fuzz input
    const reducers: []const crossing.Reducer = switch (config_byte % 4) {
        0 => &crossing.fast,
        1 => &crossing.balanced,
        2 => &crossing.quality,
        3 => &crossing.none,
        else => &crossing.balanced,
    };

    var result = root.layout(&graph, allocator, .{ .crossing_reducers = reducers }) catch |err| {
        // Expected errors are OK
        switch (err) {
            error.CycleDetected, error.EmptyGraph => return,
            else => return err,
        }
    };
    defer result.deinit();

    // Verify IR is valid
    if (result.nodes.items.len == 0 and graph.nodeCount() > 0) {
        return error.InvalidLayout;
    }
}

// ============================================================================
// Fuzz Target: SVG Rendering
// ============================================================================

/// Fuzz SVG rendering with random layouts.
pub fn fuzzSvgRendering(data: []const u8) !void {
    const svg = @import("render/svg.zig");

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var graph = Graph.init(allocator);
    defer graph.deinit();

    // Build small graph (SVG is expensive)
    const node_count: u8 = if (data.len > 0) @min(data[0] % 20 + 1, 20) else 3;

    for (0..node_count) |n| {
        var label_buf: [32]u8 = undefined;
        const label = std.fmt.bufPrint(&label_buf, "N{d}", .{n}) catch "N?";
        graph.addNode(n, label) catch {};
    }

    var i: usize = 1;
    while (i + 1 < data.len) {
        const from = data[i] % node_count;
        const to = data[i + 1] % node_count;
        i += 2;
        if (from != to) graph.addEdge(from, to) catch {};
    }

    if (graph.nodeCount() == 0) return;

    var result = root.layout(&graph, allocator, .{}) catch return;
    defer result.deinit();

    // Render to SVG
    const output = svg.render(&result, allocator, .{}) catch return;
    defer allocator.free(output);

    // Basic SVG validation
    if (output.len < 10) return error.InvalidSvg;
    if (!std.mem.startsWith(u8, output, "<svg")) return error.InvalidSvg;
    if (!std.mem.endsWith(u8, output, "</svg>\n")) return error.InvalidSvg;
}

// ============================================================================
// Fuzz Target: Unicode Rendering
// ============================================================================

/// Fuzz Unicode terminal rendering.
pub fn fuzzUnicodeRendering(data: []const u8) !void {
    const unicode = @import("render/unicode.zig");

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var graph = Graph.init(allocator);
    defer graph.deinit();

    // Build small graph
    const node_count: u8 = if (data.len > 0) @min(data[0] % 30 + 1, 30) else 3;

    for (0..node_count) |n| {
        var label_buf: [32]u8 = undefined;
        const label = std.fmt.bufPrint(&label_buf, "N{d}", .{n}) catch "N?";
        graph.addNode(n, label) catch {};
    }

    var i: usize = 1;
    while (i + 1 < data.len) {
        const from = data[i] % node_count;
        const to = data[i + 1] % node_count;
        i += 2;
        if (from != to) graph.addEdge(from, to) catch {};
    }

    if (graph.nodeCount() == 0) return;

    var result = root.layout(&graph, allocator, .{}) catch return;
    defer result.deinit();

    // Render to Unicode
    const output = unicode.render(&result, allocator) catch return;
    defer allocator.free(output);

    // Basic validation
    if (output.len == 0) return error.EmptyOutput;
}

// ============================================================================
// Fuzz Entry Points (Zig's built-in fuzzer)
// ============================================================================

fn fuzzGraphConstructionWrapper(_: void, input: []const u8) anyerror!void {
    return fuzzGraphConstruction(input);
}

fn fuzzLayoutPipelineWrapper(_: void, input: []const u8) anyerror!void {
    return fuzzLayoutPipeline(input);
}

fn fuzzSvgRenderingWrapper(_: void, input: []const u8) anyerror!void {
    return fuzzSvgRendering(input);
}

fn fuzzUnicodeRenderingWrapper(_: void, input: []const u8) anyerror!void {
    return fuzzUnicodeRendering(input);
}

test "fuzz graph construction" {
    try std.testing.fuzz({}, fuzzGraphConstructionWrapper, .{});
}

test "fuzz layout pipeline" {
    try std.testing.fuzz({}, fuzzLayoutPipelineWrapper, .{});
}

test "fuzz svg rendering" {
    try std.testing.fuzz({}, fuzzSvgRenderingWrapper, .{});
}

test "fuzz unicode rendering" {
    try std.testing.fuzz({}, fuzzUnicodeRenderingWrapper, .{});
}
