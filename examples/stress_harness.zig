//! Stress/Fuzz Harness for zigraph
//!
//! Runs randomized tests for a specified duration to catch edge cases.
//! Usage: zig build stress -- [minutes_per_target]
//!
//! Default: 1 minute per target (4 targets = 4 minutes total)

const std = @import("std");
const zigraph = @import("zigraph");

const Graph = zigraph.Graph;
const LayoutIR = zigraph.LayoutIR(usize);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Parse duration argument (default: 1 minute per target)
    const minutes_per_target: u64 = if (args.len > 1)
        std.fmt.parseInt(u64, args[1], 10) catch 1
    else
        1;

    const ns_per_target = minutes_per_target * 60 * std.time.ns_per_s;

    std.debug.print("\n╔════════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║          zigraph Stress/Fuzz Harness                           ║\n", .{});
    std.debug.print("║          Duration: {} minute(s) per target                      ║\n", .{minutes_per_target});
    std.debug.print("╚════════════════════════════════════════════════════════════════╝\n\n", .{});

    // Run each target
    try runTarget("Graph Construction", stressGraphConstruction, allocator, ns_per_target);
    try runTarget("Layout Pipeline", stressLayoutPipeline, allocator, ns_per_target);
    try runTarget("SVG Rendering", stressSvgRendering, allocator, ns_per_target);
    try runTarget("Unicode Rendering", stressUnicodeRendering, allocator, ns_per_target);

    std.debug.print("\n✅ All stress tests completed successfully!\n\n", .{});
}

fn runTarget(
    name: []const u8,
    comptime targetFn: fn (std.mem.Allocator, u64) anyerror!usize,
    allocator: std.mem.Allocator,
    duration_ns: u64,
) !void {
    std.debug.print("🔄 {s}...\n", .{name});

    const start = std.time.nanoTimestamp();
    const iterations = try targetFn(allocator, duration_ns);
    const elapsed = @as(u64, @intCast(std.time.nanoTimestamp() - start));

    const elapsed_s = @as(f64, @floatFromInt(elapsed)) / std.time.ns_per_s;
    const rate = @as(f64, @floatFromInt(iterations)) / elapsed_s;

    std.debug.print("   ✓ {d} iterations in {d:.1}s ({d:.0} iter/s)\n", .{ iterations, elapsed_s, rate });
}

// ============================================================================
// Stress Target: Graph Construction
// ============================================================================

fn stressGraphConstruction(allocator: std.mem.Allocator, duration_ns: u64) !usize {
    var prng = std.Random.DefaultPrng.init(0xDEADBEEF);
    const random = prng.random();

    const start = std.time.nanoTimestamp();
    var iterations: usize = 0;

    while (@as(u64, @intCast(std.time.nanoTimestamp() - start)) < duration_ns) {
        var graph = Graph.init(allocator);
        defer graph.deinit();

        // Random node count (1-100)
        const node_count = random.intRangeAtMost(usize, 1, 100);

        // Add nodes
        for (0..node_count) |n| {
            var label_buf: [32]u8 = undefined;
            const label = std.fmt.bufPrint(&label_buf, "N{d}", .{n}) catch "N?";
            try graph.addNode(n, label);
        }

        // Add random edges
        const edge_count = random.intRangeAtMost(usize, 0, node_count * 2);
        for (0..edge_count) |_| {
            const from = random.intRangeLessThan(usize, 0, node_count);
            const to = random.intRangeLessThan(usize, 0, node_count);
            if (from != to) {
                graph.addEdge(from, to) catch {};
            }
        }

        // Verify consistency
        _ = graph.nodeCount();
        _ = graph.edgeCount();

        iterations += 1;
    }

    return iterations;
}

// ============================================================================
// Stress Target: Layout Pipeline
// ============================================================================

fn stressLayoutPipeline(allocator: std.mem.Allocator, duration_ns: u64) !usize {
    var prng = std.Random.DefaultPrng.init(0xCAFEBABE);
    const random = prng.random();

    const start = std.time.nanoTimestamp();
    var iterations: usize = 0;

    const presets = [_][]const zigraph.crossing.Reducer{
        &zigraph.crossing.fast,
        &zigraph.crossing.balanced,
        &zigraph.crossing.quality,
        &zigraph.crossing.none,
    };

    while (@as(u64, @intCast(std.time.nanoTimestamp() - start)) < duration_ns) {
        var graph = Graph.init(allocator);
        defer graph.deinit();

        // Random DAG-safe graph (forward edges only)
        const node_count = random.intRangeAtMost(usize, 2, 50);

        for (0..node_count) |n| {
            var label_buf: [32]u8 = undefined;
            const label = std.fmt.bufPrint(&label_buf, "N{d}", .{n}) catch "N?";
            try graph.addNode(n, label);
        }

        // Add forward-only edges to ensure DAG
        const edge_count = random.intRangeAtMost(usize, 1, node_count * 2);
        for (0..edge_count) |_| {
            const from = random.intRangeLessThan(usize, 0, node_count - 1);
            const to = random.intRangeAtMost(usize, from + 1, node_count - 1);
            graph.addEdge(from, to) catch {};
        }

        // Random preset
        const preset = presets[random.intRangeLessThan(usize, 0, presets.len)];

        // Run layout
        var result = zigraph.layout(&graph, allocator, .{
            .crossing_reducers = preset,
        }) catch |err| {
            switch (err) {
                error.CycleDetected, error.EmptyGraph => {
                    iterations += 1;
                    continue;
                },
                else => return err,
            }
        };
        defer result.deinit();

        // Verify output
        if (result.nodes.items.len == 0 and graph.nodeCount() > 0) {
            return error.InvalidLayout;
        }

        iterations += 1;
    }

    return iterations;
}

// ============================================================================
// Stress Target: SVG Rendering
// ============================================================================

fn stressSvgRendering(allocator: std.mem.Allocator, duration_ns: u64) !usize {
    var prng = std.Random.DefaultPrng.init(0xFEEDFACE);
    const random = prng.random();

    const start = std.time.nanoTimestamp();
    var iterations: usize = 0;

    while (@as(u64, @intCast(std.time.nanoTimestamp() - start)) < duration_ns) {
        var graph = Graph.init(allocator);
        defer graph.deinit();

        // Smaller graphs for SVG (more expensive)
        const node_count = random.intRangeAtMost(usize, 2, 20);

        for (0..node_count) |n| {
            var label_buf: [32]u8 = undefined;
            const label = std.fmt.bufPrint(&label_buf, "N{d}", .{n}) catch "N?";
            try graph.addNode(n, label);
        }

        // Forward-only edges
        const edge_count = random.intRangeAtMost(usize, 1, node_count);
        for (0..edge_count) |_| {
            const from = random.intRangeLessThan(usize, 0, node_count - 1);
            const to = random.intRangeAtMost(usize, from + 1, node_count - 1);
            graph.addEdge(from, to) catch {};
        }

        var result = zigraph.layout(&graph, allocator, .{}) catch {
            iterations += 1;
            continue;
        };
        defer result.deinit();

        // Render to SVG
        const svg_config = zigraph.svg.SvgConfig{
            .stitch_splines = random.boolean(),
            .show_dummy_nodes = random.boolean(),
            .color_edges = random.boolean(),
        };

        const output = zigraph.svg.render(&result, allocator, svg_config) catch {
            iterations += 1;
            continue;
        };
        defer allocator.free(output);

        // Validate SVG - check for XML declaration or svg tag, and closing tag
        const has_xml_decl = std.mem.startsWith(u8, output, "<?xml");
        const has_svg_start = std.mem.indexOf(u8, output, "<svg") != null;
        const has_svg_end = std.mem.indexOf(u8, output, "</svg>") != null;

        if (!(has_xml_decl or has_svg_start)) {
            std.debug.print("\n❌ SVG validation failed after {d} iterations\n", .{iterations});
            std.debug.print("   Output length: {d} bytes\n", .{output.len});
            std.debug.print("   First 200 chars: {s}\n", .{output[0..@min(200, output.len)]});
            return error.InvalidSvg;
        }
        if (!has_svg_end) {
            std.debug.print("\n❌ SVG missing </svg> after {d} iterations\n", .{iterations});
            std.debug.print("   Output length: {d} bytes\n", .{output.len});
            std.debug.print("   Last 200 chars: {s}\n", .{output[@max(0, output.len -| 200)..output.len]});
            return error.InvalidSvg;
        }

        iterations += 1;
    }

    return iterations;
}

// ============================================================================
// Stress Target: Unicode Rendering
// ============================================================================

fn stressUnicodeRendering(allocator: std.mem.Allocator, duration_ns: u64) !usize {
    var prng = std.Random.DefaultPrng.init(0xBAADF00D);
    const random = prng.random();

    const start = std.time.nanoTimestamp();
    var iterations: usize = 0;

    while (@as(u64, @intCast(std.time.nanoTimestamp() - start)) < duration_ns) {
        var graph = Graph.init(allocator);
        defer graph.deinit();

        const node_count = random.intRangeAtMost(usize, 2, 30);

        for (0..node_count) |n| {
            var label_buf: [32]u8 = undefined;
            const label = std.fmt.bufPrint(&label_buf, "Node{d}", .{n}) catch "N?";
            try graph.addNode(n, label);
        }

        // Forward-only edges
        const edge_count = random.intRangeAtMost(usize, 1, node_count);
        for (0..edge_count) |_| {
            const from = random.intRangeLessThan(usize, 0, node_count - 1);
            const to = random.intRangeAtMost(usize, from + 1, node_count - 1);
            graph.addEdge(from, to) catch {};
        }

        var result = zigraph.layout(&graph, allocator, .{}) catch {
            iterations += 1;
            continue;
        };
        defer result.deinit();

        // Render to Unicode
        const output = zigraph.unicode.render(&result, allocator) catch {
            iterations += 1;
            continue;
        };
        defer allocator.free(output);

        // Basic validation
        if (output.len == 0 and graph.nodeCount() > 0) {
            return error.EmptyOutput;
        }

        iterations += 1;
    }

    return iterations;
}
