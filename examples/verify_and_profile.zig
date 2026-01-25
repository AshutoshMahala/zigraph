//! Verification and Memory Profiling
//!
//! This example verifies that graphs render correctly and measures memory usage
//! at each stage of the pipeline.
//!
//! Run with: zig build run-verify

const std = @import("std");
const zigraph = @import("zigraph");

const MemStats = struct {
    graph_bytes: usize = 0,
    layout_bytes: usize = 0,
    render_bytes: usize = 0,
    output_bytes: usize = 0,
};

pub fn main() !void {
    const page_alloc = std.heap.page_allocator;

    std.debug.print("\n", .{});
    std.debug.print("╔════════════════════════════════════════════════════════════╗\n", .{});
    std.debug.print("║  zigraph Verification & Memory Profiling                   ║\n", .{});
    std.debug.print("╚════════════════════════════════════════════════════════════╝\n", .{});
    std.debug.print("\n", .{});

    // Test 1: Simple chain - verify it renders correctly
    std.debug.print("=== Test 1: Simple Chain (3 nodes) ===\n\n", .{});
    try verifyAndProfile(page_alloc, "Simple Chain", buildSimpleChain);

    // Test 2: Diamond - verify merge point renders
    std.debug.print("\n=== Test 2: Diamond (4 nodes) ===\n\n", .{});
    try verifyAndProfile(page_alloc, "Diamond", buildDiamond);

    // Test 3: Wide fan - verify all children render
    std.debug.print("\n=== Test 3: Wide Fan (6 nodes) ===\n\n", .{});
    try verifyAndProfile(page_alloc, "Wide Fan", buildWideFan);

    // Test 4: Binary tree - verify tree structure
    std.debug.print("\n=== Test 4: Binary Tree (7 nodes) ===\n\n", .{});
    try verifyAndProfile(page_alloc, "Binary Tree", buildBinaryTree);

    // Test 5: Larger graph - memory profile
    std.debug.print("\n=== Test 5: Memory Profile at Scale ===\n\n", .{});
    try memoryProfileAtScale(page_alloc);

    // Test 6: Arena vs Heap comparison
    std.debug.print("\n=== Test 6: Arena vs Heap Allocator Comparison ===\n\n", .{});
    try arenaVsHeapBenchmark(page_alloc);

    std.debug.print("\n=== All Tests Complete ===\n\n", .{});
}

fn verifyAndProfile(
    page_alloc: std.mem.Allocator,
    name: []const u8,
    builder: fn (*zigraph.Graph) anyerror!void,
) !void {
    // Use counting allocator to track memory
    var counting = CountingAllocator.init(page_alloc);
    const allocator = counting.allocator();

    var stats = MemStats{};

    // Stage 1: Build graph
    counting.reset();
    var graph = zigraph.Graph.init(allocator);
    defer graph.deinit();
    try builder(&graph);
    stats.graph_bytes = counting.total_allocated;

    std.debug.print("Graph: {d} nodes, {d} edges\n", .{ graph.nodeCount(), graph.edges.items.len });

    // Stage 2: Layout
    counting.reset();
    var ir = try zigraph.layout(&graph, allocator, .{});
    defer ir.deinit();
    stats.layout_bytes = counting.total_allocated;

    // Stage 3: Render
    counting.reset();
    const output = try zigraph.unicode.render(&ir, allocator);
    defer allocator.free(output);
    stats.render_bytes = counting.total_allocated;
    stats.output_bytes = output.len;

    // Print the actual output for visual verification
    std.debug.print("\nRendered output:\n", .{});
    std.debug.print("────────────────────────────────────────\n", .{});
    std.debug.print("{s}\n", .{output});
    std.debug.print("────────────────────────────────────────\n", .{});

    // Print memory stats
    std.debug.print("\nMemory usage for '{s}':\n", .{name});
    std.debug.print("  Graph build:    {d:>8} bytes\n", .{stats.graph_bytes});
    std.debug.print("  Layout:         {d:>8} bytes\n", .{stats.layout_bytes});
    std.debug.print("  Render:         {d:>8} bytes\n", .{stats.render_bytes});
    std.debug.print("  Output string:  {d:>8} bytes\n", .{stats.output_bytes});
    std.debug.print("  ─────────────────────────────\n", .{});
    std.debug.print("  Total peak:     {d:>8} bytes\n", .{stats.graph_bytes + stats.layout_bytes + stats.render_bytes});
}

fn memoryProfileAtScale(page_alloc: std.mem.Allocator) !void {
    const sizes = [_]usize{ 100, 500, 1000, 5000, 10000, 20000 };

    std.debug.print("┌─────────┬─────────────┬─────────────┬─────────────┬─────────────┐\n", .{});
    std.debug.print("│  Nodes  │  Graph (KB) │ Layout (KB) │ Render (KB) │  Total (KB) │\n", .{});
    std.debug.print("├─────────┼─────────────┼─────────────┼─────────────┼─────────────┤\n", .{});

    for (sizes) |node_count| {
        var counting = CountingAllocator.init(page_alloc);
        const allocator = counting.allocator();

        var stats = MemStats{};

        // Build graph
        counting.reset();
        var graph = zigraph.Graph.init(allocator);

        // Create layered structure (10 nodes per layer)
        const layer_size: usize = 10;
        for (1..node_count + 1) |i| {
            var buf: [8]u8 = undefined;
            const label = std.fmt.bufPrint(&buf, "{d}", .{i}) catch "?";
            try graph.addNode(i, label);
        }

        // Connect layers
        for (1..node_count - layer_size + 1) |i| {
            if (i + layer_size <= node_count) try graph.addEdge(i, i + layer_size);
        }

        stats.graph_bytes = counting.total_allocated;

        // Layout
        counting.reset();
        var ir = try zigraph.layout(&graph, allocator, .{});
        stats.layout_bytes = counting.total_allocated;

        // Render
        counting.reset();
        const output = try zigraph.unicode.render(&ir, allocator);
        stats.render_bytes = counting.total_allocated;
        stats.output_bytes = output.len;

        const total_kb = (stats.graph_bytes + stats.layout_bytes + stats.render_bytes) / 1024;
        const graph_kb = stats.graph_bytes / 1024;
        const layout_kb = stats.layout_bytes / 1024;
        const render_kb = stats.render_bytes / 1024;

        std.debug.print("│ {d:>6}  │ {d:>10}  │ {d:>10}  │ {d:>10}  │ {d:>10}  │\n", .{
            node_count,
            graph_kb,
            layout_kb,
            render_kb,
            total_kb,
        });

        // Cleanup
        allocator.free(output);
        ir.deinit();
        graph.deinit();
    }

    std.debug.print("└─────────┴─────────────┴─────────────┴─────────────┴─────────────┘\n", .{});

    // Detailed breakdown for 1000 nodes
    std.debug.print("\n=== Detailed Layout Memory Breakdown (1000 nodes) ===\n\n", .{});
    try detailedLayoutProfile(page_alloc, 1000);
}

fn detailedLayoutProfile(page_alloc: std.mem.Allocator, node_count: usize) !void {
    var counting = CountingAllocator.init(page_alloc);
    const allocator = counting.allocator();

    // Build graph
    var graph = zigraph.Graph.init(allocator);
    defer graph.deinit();

    const layer_size: usize = 10;
    for (1..node_count + 1) |i| {
        var buf: [8]u8 = undefined;
        const label = std.fmt.bufPrint(&buf, "{d}", .{i}) catch "?";
        try graph.addNode(i, label);
    }
    for (1..node_count - layer_size + 1) |i| {
        if (i + layer_size <= node_count) try graph.addEdge(i, i + layer_size);
    }

    std.debug.print("Graph built: {d} nodes, {d} edges\n", .{ graph.nodeCount(), graph.edges.items.len });

    // Stage 1: Layering
    counting.reset();
    var layer_assignment = try zigraph.layering.longest_path.compute(&graph, allocator);
    const layering_bytes = counting.total_allocated;
    std.debug.print("  Layering:     {d:>8} bytes ({d} KB)\n", .{ layering_bytes, layering_bytes / 1024 });

    // Stage 2: Organize levels
    counting.reset();
    var levels = try zigraph.layering.longest_path.organizeLevels(&layer_assignment, allocator);
    const organize_bytes = counting.total_allocated;
    std.debug.print("  Organize:     {d:>8} bytes ({d} KB)\n", .{ organize_bytes, organize_bytes / 1024 });

    std.debug.print("  Levels: {d}\n", .{levels.items.len});
    var total_in_levels: usize = 0;
    for (levels.items) |level| {
        total_in_levels += level.items.len;
    }
    std.debug.print("  Nodes in levels: {d}\n", .{total_in_levels});

    // Stage 3: Crossing reduction
    counting.reset();
    try zigraph.crossing.median.reduce(&graph, levels.items, 4, allocator);
    const crossing_bytes = counting.total_allocated;
    std.debug.print("  Crossing:     {d:>8} bytes ({d} KB)\n", .{ crossing_bytes, crossing_bytes / 1024 });

    // Stage 4: Positioning
    counting.reset();
    var positions = try zigraph.positioning.brandes_kopf.compute(&graph, levels.items, .{}, allocator);
    defer positions.deinit();
    const positioning_bytes = counting.total_allocated;
    std.debug.print("  Positioning:  {d:>8} bytes ({d} KB)\n", .{ positioning_bytes, positioning_bytes / 1024 });

    std.debug.print("  Total width: {d}, height: {d}\n", .{ positions.total_width, positions.total_height });

    // Cleanup
    layer_assignment.deinit();
    for (levels.items) |*level| level.deinit(allocator);
    levels.deinit(allocator);
}

// Graph builders for verification
fn buildSimpleChain(graph: *zigraph.Graph) !void {
    try graph.addNode(1, "Parse");
    try graph.addNode(2, "Compile");
    try graph.addNode(3, "Link");
    try graph.addEdge(1, 2);
    try graph.addEdge(2, 3);
}

fn buildDiamond(graph: *zigraph.Graph) !void {
    try graph.addNode(1, "Root");
    try graph.addNode(2, "Left");
    try graph.addNode(3, "Right");
    try graph.addNode(4, "Merge");
    try graph.addEdge(1, 2);
    try graph.addEdge(1, 3);
    try graph.addEdge(2, 4);
    try graph.addEdge(3, 4);
}

fn buildWideFan(graph: *zigraph.Graph) !void {
    try graph.addNode(1, "Root");
    try graph.addNode(2, "A");
    try graph.addNode(3, "B");
    try graph.addNode(4, "C");
    try graph.addNode(5, "D");
    try graph.addNode(6, "End");
    try graph.addEdge(1, 2);
    try graph.addEdge(1, 3);
    try graph.addEdge(1, 4);
    try graph.addEdge(1, 5);
    try graph.addEdge(2, 6);
    try graph.addEdge(3, 6);
    try graph.addEdge(4, 6);
    try graph.addEdge(5, 6);
}

fn buildBinaryTree(graph: *zigraph.Graph) !void {
    try graph.addNode(1, "Root");
    try graph.addNode(2, "L");
    try graph.addNode(3, "R");
    try graph.addNode(4, "LL");
    try graph.addNode(5, "LR");
    try graph.addNode(6, "RL");
    try graph.addNode(7, "RR");
    try graph.addEdge(1, 2);
    try graph.addEdge(1, 3);
    try graph.addEdge(2, 4);
    try graph.addEdge(2, 5);
    try graph.addEdge(3, 6);
    try graph.addEdge(3, 7);
}

/// Benchmark arena allocator vs general purpose heap allocator
fn arenaVsHeapBenchmark(page_alloc: std.mem.Allocator) !void {
    const sizes = [_]usize{ 100, 500, 1000, 5000 };

    std.debug.print("┌─────────┬────────────────────┬────────────────────┬─────────────┐\n", .{});
    std.debug.print("│  Nodes  │   GPA Time (µs)    │  Arena Time (µs)   │   Speedup   │\n", .{});
    std.debug.print("├─────────┼────────────────────┼────────────────────┼─────────────┤\n", .{});

    for (sizes) |node_count| {
        // Benchmark GPA (General Purpose Allocator)
        const gpa_time = try benchmarkWithAllocator(page_alloc, node_count, false);

        // Benchmark Arena
        const arena_time = try benchmarkWithAllocator(page_alloc, node_count, true);

        const speedup: f32 = if (arena_time > 0)
            @as(f32, @floatFromInt(gpa_time)) / @as(f32, @floatFromInt(arena_time))
        else
            0.0;

        std.debug.print("│ {d:>6}  │ {d:>17}  │ {d:>17}  │ {d:>9.2}x  │\n", .{
            node_count,
            gpa_time,
            arena_time,
            speedup,
        });
    }

    std.debug.print("└─────────┴────────────────────┴────────────────────┴─────────────┘\n", .{});

    std.debug.print("\nNote: Arena is faster because it bulk-frees instead of tracking individual allocations.\n", .{});
    std.debug.print("For batch graph operations (layout once, render, discard), use arena.\n", .{});
}

fn benchmarkWithAllocator(page_alloc: std.mem.Allocator, node_count: usize, use_arena: bool) !u64 {
    const iterations = 5;
    var total_time: u64 = 0;

    for (0..iterations) |_| {
        if (use_arena) {
            // Arena allocator path
            var arena = std.heap.ArenaAllocator.init(page_alloc);
            defer arena.deinit();
            const allocator = arena.allocator();

            const start = std.time.nanoTimestamp();

            var graph = zigraph.Graph.init(allocator);
            const layer_size: usize = 10;
            for (1..node_count + 1) |i| {
                var buf: [8]u8 = undefined;
                const label = std.fmt.bufPrint(&buf, "{d}", .{i}) catch "?";
                try graph.addNode(i, label);
            }
            for (1..node_count - layer_size + 1) |i| {
                if (i + layer_size <= node_count) try graph.addEdge(i, i + layer_size);
            }

            var ir = try zigraph.layout(&graph, allocator, .{});
            _ = try zigraph.unicode.render(&ir, allocator);
            // Arena frees everything at once when it goes out of scope

            const end = std.time.nanoTimestamp();
            total_time += @as(u64, @intCast(@divFloor(end - start, 1000)));
        } else {
            // GPA path
            var gpa = std.heap.GeneralPurposeAllocator(.{}){};
            defer _ = gpa.deinit();
            const allocator = gpa.allocator();

            const start = std.time.nanoTimestamp();

            var graph = zigraph.Graph.init(allocator);
            defer graph.deinit();

            const layer_size: usize = 10;
            for (1..node_count + 1) |i| {
                var buf: [8]u8 = undefined;
                const label = std.fmt.bufPrint(&buf, "{d}", .{i}) catch "?";
                try graph.addNode(i, label);
            }
            for (1..node_count - layer_size + 1) |i| {
                if (i + layer_size <= node_count) try graph.addEdge(i, i + layer_size);
            }

            var ir = try zigraph.layout(&graph, allocator, .{});
            defer ir.deinit();
            const output = try zigraph.unicode.render(&ir, allocator);
            defer allocator.free(output);

            const end = std.time.nanoTimestamp();
            total_time += @as(u64, @intCast(@divFloor(end - start, 1000)));
        }
    }

    return total_time / iterations;
}

/// Simple counting allocator wrapper to track memory usage
const CountingAllocator = struct {
    parent: std.mem.Allocator,
    total_allocated: usize,
    current_allocated: usize,
    peak_allocated: usize,

    fn init(parent: std.mem.Allocator) CountingAllocator {
        return .{
            .parent = parent,
            .total_allocated = 0,
            .current_allocated = 0,
            .peak_allocated = 0,
        };
    }

    fn reset(self: *CountingAllocator) void {
        self.total_allocated = 0;
    }

    fn allocator(self: *CountingAllocator) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .remap = remap,
                .free = free,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        const result = self.parent.rawAlloc(len, ptr_align, ret_addr);
        if (result != null) {
            self.total_allocated += len;
            self.current_allocated += len;
            if (self.current_allocated > self.peak_allocated) {
                self.peak_allocated = self.current_allocated;
            }
        }
        return result;
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        if (self.parent.rawResize(buf, buf_align, new_len, ret_addr)) {
            if (new_len > buf.len) {
                const diff = new_len - buf.len;
                self.total_allocated += diff;
                self.current_allocated += diff;
            } else {
                const diff = buf.len - new_len;
                self.current_allocated -|= diff;
            }
            if (self.current_allocated > self.peak_allocated) {
                self.peak_allocated = self.current_allocated;
            }
            return true;
        }
        return false;
    }

    fn remap(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        const result = self.parent.rawRemap(buf, buf_align, new_len, ret_addr);
        if (result != null) {
            if (new_len > buf.len) {
                const diff = new_len - buf.len;
                self.total_allocated += diff;
                self.current_allocated += diff;
            } else {
                const diff = buf.len - new_len;
                self.current_allocated -|= diff;
            }
            if (self.current_allocated > self.peak_allocated) {
                self.peak_allocated = self.current_allocated;
            }
        }
        return result;
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, ret_addr: usize) void {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        self.current_allocated -|= buf.len;
        self.parent.rawFree(buf, buf_align, ret_addr);
    }
};
