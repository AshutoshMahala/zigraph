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

        try g.addDiEdgeLabeled(1, 2, "HTTP");
        try g.addDiEdgeLabeled(2, 3, "auth");
        try g.addDiEdgeLabeled(2, 4, "query");
        try g.addDiEdgeLabeled(3, 5, "read");
        try g.addDiEdgeLabeled(4, 5, "write");
        try g.addDiEdgeLabeled(4, 6, "cache");

        const backend = try g.addSubgraph("Backend");
        const data = try g.addSubgraph("Data Layer");
        try g.putSubgraphs(&.{data}).inside(backend);
        try g.putNodes(&.{ 3, 4 }).inside(backend);
        try g.putNodes(&.{ 5, 6 }).inside(data);

        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        // Unicode to terminal (with colors!)
        const unicode = try zigraph.unicode.renderGenericWithConfig(usize, &ir, allocator, .{
            .edge_palette = &zigraph.colors.ansi,
        });
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

    // ═══════════════════════════════════════════
    // Example 4: Complex multi-parent hierarchy
    // ═══════════════════════════════════════════
    {
        std.debug.print("Example 4: Complex Multi-Parent Hierarchy (colored)\n", .{});
        std.debug.print("═══════════════════════════════════════════════════\n\n", .{});
        std.debug.print("Three parent subgraphs, each with 2 child subgraphs.\n\n", .{});

        var g = zigraph.Graph.init(allocator);
        defer g.deinit();

        // ── Frontend (top) ──
        try g.addNode(1, "WebApp");
        try g.addNode(2, "Mobile");
        try g.addNode(3, "Gateway");

        // ── Backend (middle) ──
        try g.addNode(4, "AuthSvc");
        try g.addNode(5, "UserSvc");
        try g.addNode(6, "Worker");

        // ── Data (bottom) ──
        try g.addNode(7, "Postgres");
        try g.addNode(8, "Redis");

        // Edges — strictly top→bottom flow
        try g.addDiEdge(1, 3); // WebApp → Gateway
        try g.addDiEdge(2, 3); // Mobile → Gateway
        try g.addDiEdge(3, 4); // Gateway → AuthSvc
        try g.addDiEdge(3, 5); // Gateway → UserSvc
        try g.addDiEdge(4, 6); // AuthSvc → Worker
        try g.addDiEdge(5, 6); // UserSvc → Worker
        try g.addDiEdge(6, 7); // Worker → Postgres
        try g.addDiEdge(6, 8); // Worker → Redis

        // ── Subgraph hierarchy ──
        const frontend = try g.addSubgraph("Frontend");
        const ui = try g.addSubgraph("UI");
        const routing = try g.addSubgraph("Routing");
        try g.putSubgraphs(&.{ ui, routing }).inside(frontend);
        try g.putNodes(&.{ 1, 2 }).inside(ui);
        try g.putNodes(&.{3}).inside(routing);

        const backend = try g.addSubgraph("Backend");
        const services = try g.addSubgraph("Services");
        const processing = try g.addSubgraph("Processing");
        try g.putSubgraphs(&.{ services, processing }).inside(backend);
        try g.putNodes(&.{ 4, 5 }).inside(services);
        try g.putNodes(&.{6}).inside(processing);

        const data = try g.addSubgraph("Data");
        const databases = try g.addSubgraph("Databases");
        const cache = try g.addSubgraph("Cache");
        try g.putSubgraphs(&.{ databases, cache }).inside(data);
        try g.putNodes(&.{7}).inside(databases);
        try g.putNodes(&.{8}).inside(cache);

        // Layout
        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        // Unicode with colors
        const unicode = try zigraph.unicode.renderGenericWithConfig(usize, &ir, allocator, .{
            .edge_palette = &zigraph.colors.ansi,
        });
        defer allocator.free(unicode);
        std.debug.print("{s}\n", .{unicode});

        // SVG
        const svg_output = try zigraph.svg.render(&ir, allocator, .{
            .color_edges = true,
        });
        defer allocator.free(svg_output);

        {
            const file = try std.fs.cwd().createFile("subgraph_complex.svg", .{});
            defer file.close();
            try file.writeAll(svg_output);
        }
        std.debug.print("  → Wrote subgraph_complex.svg ({d} bytes)\n", .{svg_output.len});

        std.debug.print("\nSubgraph bounding boxes:\n", .{});
        for (ir.getSubgraphs()) |sg| {
            std.debug.print("  [{s}] id={d} parent={?d} x={d} y={d} w={d} h={d}\n", .{
                sg.label, sg.id, sg.parent_id, sg.x, sg.y, sg.width, sg.height,
            });
        }
        std.debug.print("\n", .{});
    }

    // ═══════════════════════════════════════════
    // Example 5: Horizontal sibling subgraphs
    // ═══════════════════════════════════════════
    {
        std.debug.print("Example 5: Horizontal Sibling Subgraphs\n", .{});
        std.debug.print("════════════════════════════════════════\n\n", .{});
        std.debug.print("Frontend fans out to two backend services side-by-side,\n", .{});
        std.debug.print("each with internal API + DB subgraphs. Monitoring below.\n\n", .{});

        var g = zigraph.Graph.init(allocator);
        defer g.deinit();

        // ── Nodes ──
        try g.addNode(1, "Frontend");

        // Order Service (left)
        try g.addNode(10, "OrderAPI");
        try g.addNode(11, "OrderWorker");
        try g.addNode(12, "OrderDB");

        // Payment Service (right)
        try g.addNode(20, "PaymentAPI");
        try g.addNode(21, "PaymentProc");
        try g.addNode(22, "PaymentDB");

        // Monitoring (bottom)
        try g.addNode(30, "Metrics");
        try g.addNode(31, "Alerts");

        // ── Edges ──
        // Frontend fans out to both services
        try g.addDiEdge(1, 10); // Frontend → OrderAPI
        try g.addDiEdge(1, 20); // Frontend → PaymentAPI

        // Order Service internal flow
        try g.addDiEdge(10, 11); // OrderAPI → OrderWorker
        try g.addDiEdge(11, 12); // OrderWorker → OrderDB

        // Payment Service internal flow
        try g.addDiEdge(20, 21); // PaymentAPI → PaymentProc
        try g.addDiEdge(21, 22); // PaymentProc → PaymentDB

        // Both DBs feed into Monitoring
        try g.addDiEdge(12, 30); // OrderDB → Metrics
        try g.addDiEdge(22, 30); // PaymentDB → Metrics
        try g.addDiEdge(30, 31); // Metrics → Alerts

        // ── Subgraph hierarchy ──
        // Order Service parent with two child subgraphs
        const order_svc = try g.addSubgraph("OrderService");
        const order_api = try g.addSubgraph("API");
        const order_data = try g.addSubgraph("Data");
        try g.putSubgraphs(&.{ order_api, order_data }).inside(order_svc);
        try g.putNodes(&.{ 10, 11 }).inside(order_api);
        try g.putNodes(&.{12}).inside(order_data);

        // Payment Service parent with two child subgraphs
        const pay_svc = try g.addSubgraph("PaymentService");
        const pay_api = try g.addSubgraph("Processing");
        const pay_data = try g.addSubgraph("Storage");
        try g.putSubgraphs(&.{ pay_api, pay_data }).inside(pay_svc);
        try g.putNodes(&.{ 20, 21 }).inside(pay_api);
        try g.putNodes(&.{22}).inside(pay_data);

        // Monitoring (standalone parent, vertically below)
        const monitoring = try g.addSubgraph("Monitoring");
        try g.putNodes(&.{ 30, 31 }).inside(monitoring);

        // Layout
        var ir = try zigraph.layout(&g, allocator, .{});
        defer ir.deinit();

        // Unicode with colors
        const unicode = try zigraph.unicode.renderGenericWithConfig(usize, &ir, allocator, .{
            .edge_palette = &zigraph.colors.ansi,
        });
        defer allocator.free(unicode);
        std.debug.print("{s}\n", .{unicode});

        // SVG
        const svg_output = try zigraph.svg.render(&ir, allocator, .{
            .color_edges = true,
        });
        defer allocator.free(svg_output);

        {
            const file = try std.fs.cwd().createFile("subgraph_horizontal.svg", .{});
            defer file.close();
            try file.writeAll(svg_output);
        }
        std.debug.print("  → Wrote subgraph_horizontal.svg ({d} bytes)\n", .{svg_output.len});

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
