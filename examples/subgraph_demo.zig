//! Subgraph Demo — hierarchical clustering with visual output
//!
//! Demonstrates subgraph support across all renderers:
//! 1. Unicode (terminal) — double-line box borders
//! 2. SVG (file) — dashed rounded rectangles
//! 3. JSON (file) — schema v1.2 with subgraph bounding boxes
//!
//! Run with: zig build run-subgraph

const std = @import("std");
const zigraph = @import("zigraph");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print(
        \\
        \\╔══════════════════════════════════════╗
        \\║   zigraph — Subgraph Demo            ║
        \\╚══════════════════════════════════════╝
        \\
        \\
    , .{});

    // ═══════════════════════════════════════════
    // Example 1: Flat subgraph (single cluster)
    // ═══════════════════════════════════════════
    {
        std.debug.print("Example 1: Flat Subgraph\n", .{});
        std.debug.print("════════════════════════\n\n", .{});
        std.debug.print("Graph: Gateway → [Auth, DB] (Auth & DB in 'backend' cluster)\n\n", .{});

        var g = zigraph.Graph.init(allocator);
        defer g.deinit();

        try g.addNode(1, "Gateway");
        try g.addNode(2, "Auth");
        try g.addNode(3, "DB");
        try g.addDiEdge(1, 2);
        try g.addDiEdge(2, 3);

        const backend = try g.addSubgraph("backend");
        try g.putNodes(&.{ 2, 3 }).inside(backend);

        // Unicode output
        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const unicode = try zigraph.unicode.renderGeneric(usize, &ir, allocator);
        defer allocator.free(unicode);
        std.debug.print("{s}\n", .{unicode});

        // Show subgraph bounding box info
        std.debug.print("Subgraph bounding boxes:\n", .{});
        for (ir.getSubgraphs()) |sg| {
            std.debug.print("  [{s}] id={d} parent={?d} x={d} y={d} w={d} h={d}\n", .{
                sg.label, sg.id, sg.parent_id, sg.x, sg.y, sg.width, sg.height,
            });
        }
        std.debug.print("\n", .{});
    }

    // ═══════════════════════════════════════════
    // Example 2: Nested subgraphs (hierarchy)
    // ═══════════════════════════════════════════
    {
        std.debug.print("Example 2: Nested Subgraphs\n", .{});
        std.debug.print("════════════════════════════\n\n", .{});
        std.debug.print("Graph: Client → API → [Auth → TokenStore] → UserDB\n", .{});
        std.debug.print("       'services' contains API, Auth, TokenStore, UserDB\n", .{});
        std.debug.print("       'auth' (nested inside services) contains Auth, TokenStore\n\n", .{});

        var g = zigraph.Graph.init(allocator);
        defer g.deinit();

        try g.addNode(1, "Client");
        try g.addNode(2, "API");
        try g.addNode(3, "Auth");
        try g.addNode(4, "TokenStore");
        try g.addNode(5, "UserDB");

        try g.addDiEdge(1, 2);
        try g.addDiEdge(2, 3);
        try g.addDiEdge(3, 4);
        try g.addDiEdge(2, 5);

        const services = try g.addSubgraph("services");
        const auth = try g.addSubgraph("auth");
        try g.putSubgraphs(&.{auth}).inside(services);
        try g.putNodes(&.{ 2, 5 }).inside(services);
        try g.putNodes(&.{ 3, 4 }).inside(auth);

        // Unicode output
        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        const unicode = try zigraph.unicode.renderGeneric(usize, &ir, allocator);
        defer allocator.free(unicode);
        std.debug.print("{s}\n", .{unicode});

        // Subgraph info
        std.debug.print("Subgraph bounding boxes:\n", .{});
        for (ir.getSubgraphs()) |sg| {
            std.debug.print("  [{s}] id={d} parent={?d} x={d} y={d} w={d} h={d}\n", .{
                sg.label, sg.id, sg.parent_id, sg.x, sg.y, sg.width, sg.height,
            });
        }
        std.debug.print("\n", .{});
    }

    // ═══════════════════════════════════════════
    // Example 3: SVG + JSON file export
    // ═══════════════════════════════════════════
    {
        std.debug.print("Example 3: SVG & JSON Export\n", .{});
        std.debug.print("════════════════════════════\n\n", .{});

        var g = zigraph.Graph.init(allocator);
        defer g.deinit();

        try g.addNode(1, "Frontend");
        try g.addNode(2, "API Gateway");
        try g.addNode(3, "Auth Service");
        try g.addNode(4, "User Service");
        try g.addNode(5, "Database");
        try g.addNode(6, "Cache");

        try g.addDiEdge(1, 2);
        try g.addDiEdge(2, 3);
        try g.addDiEdge(2, 4);
        try g.addDiEdge(3, 5);
        try g.addDiEdge(4, 5);
        try g.addDiEdge(4, 6);

        const backend = try g.addSubgraph("Backend");
        const data = try g.addSubgraph("Data Layer");
        try g.putSubgraphs(&.{data}).inside(backend);
        try g.putNodes(&.{ 3, 4 }).inside(backend);
        try g.putNodes(&.{ 5, 6 }).inside(data);

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        // Unicode to terminal
        const unicode = try zigraph.unicode.renderGeneric(usize, &ir, allocator);
        defer allocator.free(unicode);
        std.debug.print("{s}\n", .{unicode});

        // SVG to file
        const svg_output = try zigraph.svg.render(&ir, allocator, .{
            .color_edges = true,
        });
        defer allocator.free(svg_output);

        {
            const file = try std.fs.cwd().createFile("subgraph_demo.svg", .{});
            defer file.close();
            try file.writeAll(svg_output);
        }
        std.debug.print("  → Wrote subgraph_demo.svg ({d} bytes)\n", .{svg_output.len});

        // JSON to file
        const json_output = try zigraph.json.serialize(&ir, allocator);
        defer allocator.free(json_output);

        {
            const file = try std.fs.cwd().createFile("subgraph_demo.json", .{});
            defer file.close();
            try file.writeAll(json_output);
        }
        std.debug.print("  → Wrote subgraph_demo.json ({d} bytes)\n", .{json_output.len});

        std.debug.print("\nSubgraph bounding boxes:\n", .{});
        for (ir.getSubgraphs()) |sg| {
            std.debug.print("  [{s}] id={d} parent={?d} x={d} y={d} w={d} h={d}\n", .{
                sg.label, sg.id, sg.parent_id, sg.x, sg.y, sg.width, sg.height,
            });
        }
        std.debug.print("\n", .{});
    }

    std.debug.print("Done! Open subgraph_demo.svg in a browser to see the visual output.\n", .{});
}
