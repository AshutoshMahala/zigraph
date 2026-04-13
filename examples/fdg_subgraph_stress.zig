//! FDG Subgraph Stress Test
//!
//! Exercises force-directed layout with subgraphs at escalating complexity:
//! tier structure mirrors asciidag_stress.zig, but all layouts use
//! Fruchterman-Reingold (standard & Barnes-Hut).
//!
//! Tiers test:
//!   1. Microservices  — 12 nodes, 4 flat subgraphs
//!   2. Platform       — 20 nodes, 8 subgraphs, depth 2
//!   3. Cloud Infra    — ~30 nodes, 12 subgraphs, depth 3
//!   4. Enterprise     — ~50 nodes, 16 subgraphs, depth 3
//!   5. Megacorp       — ~80 nodes, 24 subgraphs, depth 4
//!
//! Additional stress scenarios:
//!   - Cyclic subgraph clusters (FDG handles cycles natively)
//!   - Dense cross-cluster connectivity
//!   - Singleton subgraphs
//!   - Deeply nested chain (depth 6)
//!   - Many small subgraphs (30 pairs)
//!   - Cohesion strength sweep (0.0 to 2.0)
//!   - Large scale: 200-node clustered graph
//!
//! Run with: zig build run-fdg-subgraph-stress

const std = @import("std");
const zigraph = @import("zigraph");
const time = std.time;

const Graph = zigraph.Graph;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const stdout = std.fs.File.stdout().deprecatedWriter();

    try stdout.writeAll(
        \\╔══════════════════════════════════════════════════════════╗
        \\║   zigraph — FDG Subgraph Stress Test                    ║
        \\║   FR standard (O(N²)) + FR-Fast Barnes-Hut (O(N·logN)) ║
        \\╚══════════════════════════════════════════════════════════╝
        \\
        \\
    );

    // ── Subgraph tiers (Sugiyama tiers re-used under FDG) ─────────────────
    try stdout.writeAll("═══ SUBGRAPH TIERS (FR standard) ════════════════════════════\n\n");

    try runFdg(stdout, allocator, "Tier 1 · Microservices (12 nodes, 4 subgraphs, depth 1)", buildTier1, .{});
    try runFdg(stdout, allocator, "Tier 2 · Platform (20 nodes, 8 subgraphs, depth 2)", buildTier2, .{});
    try runFdg(stdout, allocator, "Tier 3 · Cloud Infra (~30 nodes, 12 subgraphs, depth 3)", buildTier3, .{});
    try runFdg(stdout, allocator, "Tier 4 · Enterprise (~50 nodes, 16 subgraphs, depth 3)", buildTier4, .{});
    try runFdgSuppressed(stdout, allocator, "Tier 5 · Megacorp (~80 nodes, 24 subgraphs, depth 4)", buildTier5, .{});

    // ── Same tiers with Barnes-Hut ────────────────────────────────────────
    try stdout.writeAll("═══ SUBGRAPH TIERS (FR-Fast / Barnes-Hut) ═══════════════════\n\n");

    try runFdgFast(stdout, allocator, "Tier 3 · Cloud Infra (Barnes-Hut)", buildTier3, .{});
    try runFdgFast(stdout, allocator, "Tier 4 · Enterprise (Barnes-Hut)", buildTier4, .{});
    try runFdgFastSuppressed(stdout, allocator, "Tier 5 · Megacorp (Barnes-Hut)", buildTier5, .{});

    // ── FDG-specific scenarios ────────────────────────────────────────────
    try stdout.writeAll("═══ FDG-SPECIFIC SCENARIOS ══════════════════════════════════\n\n");

    try runFdg(stdout, allocator, "Cyclic Clusters (3 clusters, back-edges)", buildCyclicClusters, .{});
    try runFdg(stdout, allocator, "Dense Cross-Cluster (3 clusters, many inter-edges)", buildDenseCrossCluster, .{});
    try runFdg(stdout, allocator, "Singleton Subgraphs (5 lone nodes in own subgraphs)", buildSingletonSubgraphs, .{});
    try runFdg(stdout, allocator, "Deep Nesting (depth 6, linear chain)", buildDeepNesting, .{});
    try runFdg(stdout, allocator, "Many Small Subgraphs (30 pairs, 60 nodes)", buildManySmallSubgraphs, .{});
    try runFdg(stdout, allocator, "Mixed: Subgraph + Free Nodes", buildMixedFreeNodes, .{});
    try runFdg(stdout, allocator, "Overlapping Clusters (stress inter-cluster separation)", buildOverlappingClusters, .{});

    // ── Cohesion strength sweep ──────────────────────────────────────────
    try stdout.writeAll("═══ COHESION STRENGTH SWEEP ═════════════════════════════════\n\n");
    try stdout.writeAll("Same graph (Tier 2) at different subgraph_cohesion values.\n");
    try stdout.writeAll("Watch how cluster tightness changes.\n\n");

    const fp = zigraph.fdg.fixed_point;
    const cohesion_values = [_]struct { label: []const u8, value: fp.FP }{
        .{ .label = "0.0 (disabled)", .value = 0 },
        .{ .label = "0.3 (light)", .value = 19660 }, // 0.3 * 65536
        .{ .label = "0.5 (default)", .value = 32768 },
        .{ .label = "1.0 (strong)", .value = 65536 },
        .{ .label = "2.0 (very strong)", .value = 131072 },
    };

    for (cohesion_values) |cv| {
        var name_buf: [80]u8 = undefined;
        const name = std.fmt.bufPrint(&name_buf, "Tier 2 · cohesion = {s}", .{cv.label}) catch "cohesion sweep";
        try runFdg(stdout, allocator, name, buildTier2, .{
            .subgraph_cohesion = cv.value,
        });
    }

    // ── Large scale (output suppressed) ──────────────────────────────────
    try stdout.writeAll("═══ LARGE SCALE (output suppressed) ═════════════════════════\n\n");

    try runFdgSuppressed(stdout, allocator, "200 nodes · 10 clusters · FR standard", buildLargeClustered, .{});
    try runFdgFastSuppressed(stdout, allocator, "200 nodes · 10 clusters · FR-Fast", buildLargeClustered, .{});
    try runFdgFastSuppressed(stdout, allocator, "500 nodes · 25 clusters · FR-Fast", buildVeryLargeClustered, .{});

    try stdout.writeAll("\nDone.\n");
}

// ── Runner helpers ────────────────────────────────────────────────────────────

const FrConfig = zigraph.fdg.fruchterman_reingold.Config;

fn runFdg(
    writer: anytype,
    allocator: std.mem.Allocator,
    name: []const u8,
    comptime buildFn: fn (std.mem.Allocator) anyerror!Graph,
    fr_overrides: FrConfig,
) !void {
    try printHeader(writer, name);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const graph_alloc = arena.allocator();

    var graph = buildFn(graph_alloc) catch |err| {
        try writer.print("  [BUILD ERROR: {}]\n\n", .{err});
        return;
    };
    defer graph.deinit();

    const t0 = time.nanoTimestamp();
    var ir = zigraph.layout(&graph, allocator, .{
        .algorithm = .{ .fruchterman_reingold = fr_overrides },
    }) catch |err| {
        try writer.print("  [LAYOUT ERROR: {}]\n\n", .{err});
        return;
    };
    defer ir.deinit();
    const layout_ns = @as(u64, @intCast(time.nanoTimestamp() - t0));

    // Print subgraph bounding boxes
    const subgraphs = ir.getSubgraphs();
    if (subgraphs.len > 0) {
        try writer.print("  Subgraph bounding boxes ({d}):\n", .{subgraphs.len});
        for (subgraphs) |sg| {
            try writer.print("    [{s}] id={d} parent={?d}  x={d} y={d} w={d} h={d}\n", .{
                sg.label, sg.id, sg.parent_id, sg.x, sg.y, sg.width, sg.height,
            });
        }
        try writer.print("\n", .{});
    }

    // Render terminal output
    const t1 = time.nanoTimestamp();
    const output = zigraph.terminal.render(&ir, allocator) catch |err| {
        try writer.print("  [RENDER ERROR: {}]\n\n", .{err});
        return;
    };
    defer allocator.free(output);
    const render_ns = @as(u64, @intCast(time.nanoTimestamp() - t1));

    const lines = std.mem.count(u8, output, "\n");
    var max_w: usize = 0;
    var it = std.mem.splitScalar(u8, output, '\n');
    while (it.next()) |line| {
        if (line.len > max_w) max_w = line.len;
    }

    try writer.print("{s}\n", .{output});
    try writer.print("  [{d} chars, {d}×{d}, layout {d}µs, render {d}µs]\n\n", .{
        output.len,
        max_w,
        lines,
        layout_ns / std.time.ns_per_us,
        render_ns / std.time.ns_per_us,
    });
}

fn runFdgFast(
    writer: anytype,
    allocator: std.mem.Allocator,
    name: []const u8,
    comptime buildFn: fn (std.mem.Allocator) anyerror!Graph,
    fr_overrides: FrConfig,
) !void {
    try printHeader(writer, name);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const graph_alloc = arena.allocator();

    var graph = buildFn(graph_alloc) catch |err| {
        try writer.print("  [BUILD ERROR: {}]\n\n", .{err});
        return;
    };
    defer graph.deinit();

    const t0 = time.nanoTimestamp();
    var ir = zigraph.layout(&graph, allocator, .{
        .algorithm = .{ .fruchterman_reingold_fast = fr_overrides },
    }) catch |err| {
        try writer.print("  [LAYOUT ERROR: {}]\n\n", .{err});
        return;
    };
    defer ir.deinit();
    const layout_ns = @as(u64, @intCast(time.nanoTimestamp() - t0));

    const t1 = time.nanoTimestamp();
    const output = zigraph.terminal.render(&ir, allocator) catch |err| {
        try writer.print("  [RENDER ERROR: {}]\n\n", .{err});
        return;
    };
    defer allocator.free(output);
    const render_ns = @as(u64, @intCast(time.nanoTimestamp() - t1));

    const lines = std.mem.count(u8, output, "\n");
    var max_w: usize = 0;
    var it = std.mem.splitScalar(u8, output, '\n');
    while (it.next()) |line| {
        if (line.len > max_w) max_w = line.len;
    }

    try writer.print("{s}\n", .{output});
    try writer.print("  [{d} chars, {d}×{d}, layout {d}µs, render {d}µs]\n\n", .{
        output.len,
        max_w,
        lines,
        layout_ns / std.time.ns_per_us,
        render_ns / std.time.ns_per_us,
    });
}

fn runFdgSuppressed(
    writer: anytype,
    allocator: std.mem.Allocator,
    name: []const u8,
    comptime buildFn: fn (std.mem.Allocator) anyerror!Graph,
    fr_overrides: FrConfig,
) !void {
    try writer.print("  {s}\n", .{name});

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const graph_alloc = arena.allocator();

    var graph = buildFn(graph_alloc) catch |err| {
        try writer.print("  [BUILD ERROR: {}]\n\n", .{err});
        return;
    };
    defer graph.deinit();

    const t0 = time.nanoTimestamp();
    var ir = zigraph.layout(&graph, allocator, .{
        .algorithm = .{ .fruchterman_reingold = fr_overrides },
    }) catch |err| {
        try writer.print("  [LAYOUT ERROR: {}]\n\n", .{err});
        return;
    };
    defer ir.deinit();
    const layout_ns = @as(u64, @intCast(time.nanoTimestamp() - t0));

    const t1 = time.nanoTimestamp();
    const output = zigraph.terminal.render(&ir, allocator) catch |err| {
        try writer.print("  [RENDER ERROR: {}]\n\n", .{err});
        return;
    };
    defer allocator.free(output);
    const render_ns = @as(u64, @intCast(time.nanoTimestamp() - t1));

    const subgraphs = ir.getSubgraphs();
    try writer.print("  (suppressed — {d} chars, {d} subgraphs, layout {d}µs, render {d}µs)\n\n", .{
        output.len,
        subgraphs.len,
        layout_ns / std.time.ns_per_us,
        render_ns / std.time.ns_per_us,
    });
}

fn runFdgFastSuppressed(
    writer: anytype,
    allocator: std.mem.Allocator,
    name: []const u8,
    comptime buildFn: fn (std.mem.Allocator) anyerror!Graph,
    fr_overrides: FrConfig,
) !void {
    try writer.print("  {s}\n", .{name});

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const graph_alloc = arena.allocator();

    var graph = buildFn(graph_alloc) catch |err| {
        try writer.print("  [BUILD ERROR: {}]\n\n", .{err});
        return;
    };
    defer graph.deinit();

    const t0 = time.nanoTimestamp();
    var ir = zigraph.layout(&graph, allocator, .{
        .algorithm = .{ .fruchterman_reingold_fast = fr_overrides },
    }) catch |err| {
        try writer.print("  [LAYOUT ERROR: {}]\n\n", .{err});
        return;
    };
    defer ir.deinit();
    const layout_ns = @as(u64, @intCast(time.nanoTimestamp() - t0));

    const t1 = time.nanoTimestamp();
    const output = zigraph.terminal.render(&ir, allocator) catch |err| {
        try writer.print("  [RENDER ERROR: {}]\n\n", .{err});
        return;
    };
    defer allocator.free(output);
    const render_ns = @as(u64, @intCast(time.nanoTimestamp() - t1));

    const subgraphs = ir.getSubgraphs();
    try writer.print("  (suppressed — {d} chars, {d} subgraphs, layout {d}µs, render {d}µs)\n\n", .{
        output.len,
        subgraphs.len,
        layout_ns / std.time.ns_per_us,
        render_ns / std.time.ns_per_us,
    });
}

fn printHeader(writer: anytype, name: []const u8) !void {
    try writer.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    try writer.print("  {s}\n", .{name});
    try writer.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n", .{});
}

// ══════════════════════════════════════════════════════════════════════════════
//  TIER BUILDERS (same topology as asciidag_stress, edges are bidirectional
//  for FDG since it handles undirected graphs naturally)
// ══════════════════════════════════════════════════════════════════════════════

// ── Tier 1: Microservices (12 nodes, 4 subgraphs, depth 1) ──────────────────

fn buildTier1(allocator: std.mem.Allocator) !Graph {
    var g = Graph.init(allocator);
    errdefer g.deinit();

    try g.addNode(1, "API-GW");
    try g.addNode(10, "AuthSvc");
    try g.addNode(11, "TokenStore");
    try g.addNode(20, "UserSvc");
    try g.addNode(21, "UserDB");
    try g.addNode(30, "OrderSvc");
    try g.addNode(31, "OrderDB");
    try g.addNode(32, "OrderQueue");
    try g.addNode(40, "NotifySvc");
    try g.addNode(41, "EmailGW");
    try g.addNode(42, "PushGW");

    try g.addEdge(1, 10);
    try g.addEdge(1, 20);
    try g.addEdge(1, 30);
    try g.addEdge(10, 11);
    try g.addEdge(20, 21);
    try g.addEdge(30, 31);
    try g.addEdge(30, 32);
    try g.addEdge(32, 40);
    try g.addEdge(40, 41);
    try g.addEdge(40, 42);

    const auth = try g.addSubgraph("Auth");
    const users = try g.addSubgraph("Users");
    const orders = try g.addSubgraph("Orders");
    const notify = try g.addSubgraph("Notifications");
    try g.putNodes(&.{ 10, 11 }).inside(auth);
    try g.putNodes(&.{ 20, 21 }).inside(users);
    try g.putNodes(&.{ 30, 31, 32 }).inside(orders);
    try g.putNodes(&.{ 40, 41, 42 }).inside(notify);

    return g;
}

// ── Tier 2: Platform (20 nodes, 8 subgraphs, depth 2) ───────────────────────

fn buildTier2(allocator: std.mem.Allocator) !Graph {
    var g = Graph.init(allocator);
    errdefer g.deinit();

    try g.addNode(1, "LoadBalancer");
    try g.addNode(2, "CDN");
    try g.addNode(10, "WebApp");
    try g.addNode(11, "MobileAPI");
    try g.addNode(12, "SSR-Engine");
    try g.addNode(20, "AuthSvc");
    try g.addNode(21, "SessionDB");
    try g.addNode(22, "UserSvc");
    try g.addNode(23, "ProfileDB");
    try g.addNode(30, "Analytics");
    try g.addNode(31, "Warehouse");
    try g.addNode(32, "ETL");
    try g.addNode(40, "Prometheus");
    try g.addNode(41, "Grafana");
    try g.addNode(42, "AlertMgr");
    try g.addNode(43, "PagerDuty");
    try g.addNode(50, "FluentBit");
    try g.addNode(51, "ElasticSearch");
    try g.addNode(52, "Kibana");

    try g.addEdge(1, 10);
    try g.addEdge(1, 11);
    try g.addEdge(2, 12);
    try g.addEdge(10, 20);
    try g.addEdge(11, 20);
    try g.addEdge(12, 22);
    try g.addEdge(20, 21);
    try g.addEdge(22, 23);
    try g.addEdge(20, 30);
    try g.addEdge(22, 30);
    try g.addEdge(30, 31);
    try g.addEdge(30, 32);
    try g.addEdge(31, 40);
    try g.addEdge(40, 41);
    try g.addEdge(40, 42);
    try g.addEdge(42, 43);
    try g.addEdge(32, 50);
    try g.addEdge(50, 51);
    try g.addEdge(51, 52);

    const frontend = try g.addSubgraph("Frontend");
    const backend = try g.addSubgraph("Backend");
    const core = try g.addSubgraph("Core");
    const data = try g.addSubgraph("Data Pipeline");
    const infra = try g.addSubgraph("Infra");
    const monitoring = try g.addSubgraph("Monitoring");
    const logging = try g.addSubgraph("Logging");
    const observability = try g.addSubgraph("Observability");

    try g.putNodes(&.{ 10, 11, 12 }).inside(frontend);
    try g.putNodes(&.{ 20, 21, 22, 23 }).inside(core);
    try g.putNodes(&.{ 30, 31, 32 }).inside(data);
    try g.putSubgraphs(&.{ core, data }).inside(backend);
    try g.putNodes(&.{ 40, 41, 42, 43 }).inside(monitoring);
    try g.putNodes(&.{ 50, 51, 52 }).inside(logging);
    try g.putSubgraphs(&.{ monitoring, logging }).inside(observability);
    try g.putSubgraphs(&.{observability}).inside(infra);

    return g;
}

// ── Tier 3: Cloud Infra (~30 nodes, 12 subgraphs, depth 3) ──────────────────

fn buildTier3(allocator: std.mem.Allocator) !Graph {
    var g = Graph.init(allocator);
    errdefer g.deinit();

    // Ingress
    try g.addNode(1, "ALB");
    try g.addNode(2, "WAF");
    try g.addEdge(1, 2);

    // Region A — AZ1
    try g.addNode(10, "Web-A1");
    try g.addNode(11, "App-A1");
    try g.addNode(12, "DB-A1");
    try g.addEdge(2, 10);
    try g.addEdge(10, 11);
    try g.addEdge(11, 12);

    // Region A — AZ2
    try g.addNode(13, "Web-A2");
    try g.addNode(14, "App-A2");
    try g.addNode(15, "DB-A2");
    try g.addEdge(2, 13);
    try g.addEdge(13, 14);
    try g.addEdge(14, 15);

    // Region B — AZ1
    try g.addNode(20, "Web-B1");
    try g.addNode(21, "App-B1");
    try g.addNode(22, "Redis-B1");
    try g.addNode(23, "DB-B1");
    try g.addEdge(2, 20);
    try g.addEdge(20, 21);
    try g.addEdge(21, 22);
    try g.addEdge(22, 23);

    // Region B — AZ2
    try g.addNode(24, "Web-B2");
    try g.addNode(25, "App-B2");
    try g.addNode(26, "Redis-B2");
    try g.addNode(27, "DB-B2");
    try g.addEdge(2, 24);
    try g.addEdge(24, 25);
    try g.addEdge(25, 26);
    try g.addEdge(26, 27);

    // Shared services
    try g.addNode(30, "RabbitMQ");
    try g.addNode(31, "S3-Bucket");
    try g.addNode(32, "Vault");
    try g.addEdge(11, 30);
    try g.addEdge(21, 30);
    try g.addEdge(30, 31);

    // CI/CD
    try g.addNode(40, "Jenkins");
    try g.addNode(41, "ArgoCD");
    try g.addNode(42, "ECR");
    try g.addEdge(40, 42);
    try g.addEdge(42, 41);
    try g.addEdge(41, 10);
    try g.addEdge(41, 20);

    // Monitoring
    try g.addNode(50, "Prometheus");
    try g.addNode(51, "Grafana");
    try g.addNode(52, "Loki");
    try g.addEdge(50, 51);
    try g.addEdge(52, 51);
    try g.addEdge(11, 50);
    try g.addEdge(21, 52);

    // Subgraphs
    const az_a1 = try g.addSubgraph("AZ-1 (A)");
    const az_a2 = try g.addSubgraph("AZ-2 (A)");
    const region_a = try g.addSubgraph("us-east-1");
    try g.putNodes(&.{ 10, 11, 12 }).inside(az_a1);
    try g.putNodes(&.{ 13, 14, 15 }).inside(az_a2);
    try g.putSubgraphs(&.{ az_a1, az_a2 }).inside(region_a);

    const az_b1 = try g.addSubgraph("AZ-1 (B)");
    const az_b2 = try g.addSubgraph("AZ-2 (B)");
    const region_b = try g.addSubgraph("eu-west-1");
    try g.putNodes(&.{ 20, 21, 22, 23 }).inside(az_b1);
    try g.putNodes(&.{ 24, 25, 26, 27 }).inside(az_b2);
    try g.putSubgraphs(&.{ az_b1, az_b2 }).inside(region_b);

    const shared = try g.addSubgraph("Shared Services");
    try g.putNodes(&.{ 30, 31, 32 }).inside(shared);

    const cicd = try g.addSubgraph("CI/CD");
    try g.putNodes(&.{ 40, 41, 42 }).inside(cicd);

    const obs = try g.addSubgraph("Observability");
    try g.putNodes(&.{ 50, 51, 52 }).inside(obs);

    return g;
}

// ── Tier 4: Enterprise (~50 nodes, 16 subgraphs, depth 3) ───────────────────

fn buildTier4(allocator: std.mem.Allocator) !Graph {
    var g = Graph.init(allocator);
    errdefer g.deinit();

    // Entry
    try g.addNode(1, "Portal");
    try g.addNode(2, "MobileApp");

    // Auth
    try g.addNode(10, "AuthGW");
    try g.addNode(11, "OAuth2");
    try g.addNode(12, "LDAP");
    try g.addNode(13, "MFA");

    // Customer
    try g.addNode(20, "CustAPI");
    try g.addNode(21, "CustSvc");
    try g.addNode(22, "CustDB");
    try g.addNode(23, "CustCache");

    // Product
    try g.addNode(30, "ProdAPI");
    try g.addNode(31, "Catalog");
    try g.addNode(32, "Inventory");
    try g.addNode(33, "Pricing");
    try g.addNode(34, "ProdDB");

    // Order
    try g.addNode(40, "OrderAPI");
    try g.addNode(41, "OrderSvc");
    try g.addNode(42, "OrderDB");
    try g.addNode(43, "CartSvc");
    try g.addNode(44, "CartDB");

    // Payment
    try g.addNode(50, "PayGW");
    try g.addNode(51, "PayProc");
    try g.addNode(52, "PayDB");
    try g.addNode(53, "FraudDet");

    // Shipping
    try g.addNode(60, "ShipAPI");
    try g.addNode(61, "ShipSvc");
    try g.addNode(62, "ShipDB");
    try g.addNode(63, "Tracking");

    // Messaging
    try g.addNode(70, "Kafka");
    try g.addNode(71, "SchemaReg");

    // Data Platform
    try g.addNode(80, "Spark");
    try g.addNode(81, "DataLake");
    try g.addNode(82, "Airflow");
    try g.addNode(83, "Redshift");

    // Observability
    try g.addNode(90, "Prometheus");
    try g.addNode(91, "Grafana");
    try g.addNode(92, "Jaeger");
    try g.addNode(93, "ELK");
    try g.addNode(94, "PagerDuty");

    // DevOps
    try g.addNode(100, "GitHub");
    try g.addNode(101, "CI-Runner");
    try g.addNode(102, "Terraform");
    try g.addNode(103, "K8s");
    try g.addNode(104, "Helm");

    // Notifications
    try g.addNode(110, "NotifSvc");
    try g.addNode(111, "EmailGW");
    try g.addNode(112, "SMS-GW");
    try g.addNode(113, "PushSvc");

    // Entry → Auth
    try g.addEdge(1, 10);
    try g.addEdge(2, 10);
    try g.addEdge(10, 11);
    try g.addEdge(10, 12);
    try g.addEdge(11, 13);

    // Auth → domains
    try g.addEdge(10, 20);
    try g.addEdge(10, 30);
    try g.addEdge(10, 40);

    // Customer
    try g.addEdge(20, 21);
    try g.addEdge(21, 22);
    try g.addEdge(21, 23);

    // Product
    try g.addEdge(30, 31);
    try g.addEdge(30, 32);
    try g.addEdge(31, 33);
    try g.addEdge(31, 34);
    try g.addEdge(32, 34);

    // Order
    try g.addEdge(40, 41);
    try g.addEdge(40, 43);
    try g.addEdge(41, 42);
    try g.addEdge(43, 44);
    try g.addEdge(41, 50);
    try g.addEdge(41, 60);

    // Payment
    try g.addEdge(50, 51);
    try g.addEdge(51, 52);
    try g.addEdge(51, 53);

    // Shipping
    try g.addEdge(60, 61);
    try g.addEdge(61, 62);
    try g.addEdge(61, 63);

    // Messaging
    try g.addEdge(41, 70);
    try g.addEdge(51, 70);
    try g.addEdge(61, 70);
    try g.addEdge(70, 71);

    // Data
    try g.addEdge(70, 80);
    try g.addEdge(80, 81);
    try g.addEdge(82, 80);
    try g.addEdge(81, 83);

    // Observability
    try g.addEdge(70, 90);
    try g.addEdge(90, 91);
    try g.addEdge(90, 92);
    try g.addEdge(90, 93);
    try g.addEdge(91, 94);

    // Notifications
    try g.addEdge(41, 110);
    try g.addEdge(110, 111);
    try g.addEdge(110, 112);
    try g.addEdge(110, 113);

    // DevOps
    try g.addEdge(100, 101);
    try g.addEdge(101, 104);
    try g.addEdge(104, 103);
    try g.addEdge(102, 103);

    // Subgraphs
    const sg_auth = try g.addSubgraph("Identity");
    try g.putNodes(&.{ 10, 11, 12, 13 }).inside(sg_auth);

    const sg_cust = try g.addSubgraph("Customer");
    try g.putNodes(&.{ 20, 21, 22, 23 }).inside(sg_cust);

    const sg_catalog = try g.addSubgraph("Catalog");
    try g.putNodes(&.{ 31, 33, 34 }).inside(sg_catalog);
    const sg_prod = try g.addSubgraph("Product");
    try g.putNodes(&.{ 30, 32 }).inside(sg_prod);
    try g.putSubgraphs(&.{sg_catalog}).inside(sg_prod);

    const sg_cart = try g.addSubgraph("Cart");
    try g.putNodes(&.{ 43, 44 }).inside(sg_cart);
    const sg_order = try g.addSubgraph("Orders");
    try g.putNodes(&.{ 40, 41, 42 }).inside(sg_order);
    try g.putSubgraphs(&.{sg_cart}).inside(sg_order);

    const sg_pay = try g.addSubgraph("Payments");
    try g.putNodes(&.{ 50, 51, 52, 53 }).inside(sg_pay);

    const sg_ship = try g.addSubgraph("Shipping");
    try g.putNodes(&.{ 60, 61, 62, 63 }).inside(sg_ship);

    const sg_msg = try g.addSubgraph("Messaging");
    try g.putNodes(&.{ 70, 71 }).inside(sg_msg);

    const sg_dp = try g.addSubgraph("Data Platform");
    try g.putNodes(&.{ 80, 81, 82, 83 }).inside(sg_dp);

    const sg_mon = try g.addSubgraph("Monitoring");
    try g.putNodes(&.{ 90, 91, 92, 93, 94 }).inside(sg_mon);
    const sg_obs = try g.addSubgraph("Observability");
    try g.putSubgraphs(&.{sg_mon}).inside(sg_obs);

    const sg_notif = try g.addSubgraph("Notifications");
    try g.putNodes(&.{ 110, 111, 112, 113 }).inside(sg_notif);

    const sg_devops = try g.addSubgraph("DevOps");
    try g.putNodes(&.{ 100, 101, 102, 103, 104 }).inside(sg_devops);

    return g;
}

// ── Tier 5: Megacorp (~80 nodes, 24 subgraphs, depth 4) ─────────────────────

fn buildTier5(allocator: std.mem.Allocator) !Graph {
    var g = Graph.init(allocator);
    errdefer g.deinit();

    // Global entry
    try g.addNode(1, "Route53");
    try g.addNode(2, "CloudFront");
    try g.addNode(3, "WAF");
    try g.addEdge(1, 2);
    try g.addEdge(2, 3);

    // US Region — Frontend
    try g.addNode(10, "US-Web");
    try g.addNode(11, "US-Mobile");
    try g.addNode(12, "US-SSR");
    try g.addEdge(3, 10);
    try g.addEdge(3, 11);
    try g.addEdge(10, 12);

    // US Region — Auth
    try g.addNode(13, "US-Auth");
    try g.addNode(14, "US-Token");
    try g.addNode(15, "US-MFA");
    try g.addEdge(10, 13);
    try g.addEdge(11, 13);
    try g.addEdge(13, 14);
    try g.addEdge(13, 15);

    // US Region — Business
    try g.addNode(16, "US-Orders");
    try g.addNode(17, "US-Pay");
    try g.addNode(18, "US-Inv");
    try g.addNode(19, "US-Ship");
    try g.addEdge(13, 16);
    try g.addEdge(16, 17);
    try g.addEdge(16, 18);
    try g.addEdge(16, 19);

    // US Region — Data
    try g.addNode(20, "US-Postgres");
    try g.addNode(21, "US-Redis");
    try g.addNode(22, "US-S3");
    try g.addEdge(16, 20);
    try g.addEdge(17, 20);
    try g.addEdge(13, 21);
    try g.addEdge(18, 22);

    // EU Region
    try g.addNode(30, "EU-Web");
    try g.addNode(31, "EU-Auth");
    try g.addNode(32, "EU-Orders");
    try g.addNode(33, "EU-Pay");
    try g.addNode(34, "EU-Ship");
    try g.addNode(35, "EU-Postgres");
    try g.addNode(36, "EU-Redis");
    try g.addEdge(3, 30);
    try g.addEdge(30, 31);
    try g.addEdge(31, 32);
    try g.addEdge(32, 33);
    try g.addEdge(32, 34);
    try g.addEdge(32, 35);
    try g.addEdge(31, 36);

    // APAC Region
    try g.addNode(40, "AP-Web");
    try g.addNode(41, "AP-Auth");
    try g.addNode(42, "AP-Orders");
    try g.addNode(43, "AP-Postgres");
    try g.addEdge(3, 40);
    try g.addEdge(40, 41);
    try g.addEdge(41, 42);
    try g.addEdge(42, 43);

    // Messaging
    try g.addNode(50, "Kafka-1");
    try g.addNode(51, "Kafka-2");
    try g.addNode(52, "Zookeeper");
    try g.addNode(53, "SchemaReg");
    try g.addEdge(16, 50);
    try g.addEdge(32, 50);
    try g.addEdge(50, 51);
    try g.addEdge(50, 52);
    try g.addEdge(51, 53);

    // Data Platform
    try g.addNode(60, "Spark");
    try g.addNode(61, "Flink");
    try g.addNode(62, "Airflow");
    try g.addNode(63, "DataLake");
    try g.addNode(64, "Redshift");
    try g.addNode(65, "Tableau");
    try g.addEdge(51, 60);
    try g.addEdge(51, 61);
    try g.addEdge(62, 60);
    try g.addEdge(60, 63);
    try g.addEdge(61, 63);
    try g.addEdge(63, 64);
    try g.addEdge(64, 65);

    // ML Platform
    try g.addNode(70, "MLflow");
    try g.addNode(71, "SageMaker");
    try g.addNode(72, "ModelReg");
    try g.addNode(73, "Inference");
    try g.addEdge(63, 70);
    try g.addEdge(70, 71);
    try g.addEdge(71, 72);
    try g.addEdge(72, 73);

    // Observability
    try g.addNode(80, "Prometheus");
    try g.addNode(81, "Grafana");
    try g.addNode(82, "Jaeger");
    try g.addNode(83, "Loki");
    try g.addNode(84, "Cortex");
    try g.addNode(85, "PagerDuty");
    try g.addNode(86, "OpsGenie");
    try g.addEdge(16, 80);
    try g.addEdge(32, 80);
    try g.addEdge(80, 84);
    try g.addEdge(84, 81);
    try g.addEdge(80, 82);
    try g.addEdge(80, 83);
    try g.addEdge(81, 85);
    try g.addEdge(81, 86);

    // Security
    try g.addNode(90, "Vault");
    try g.addNode(91, "CertMgr");
    try g.addNode(92, "GuardDuty");
    try g.addNode(93, "Inspector");
    try g.addEdge(13, 90);
    try g.addEdge(31, 90);
    try g.addEdge(90, 91);
    try g.addEdge(90, 92);
    try g.addEdge(92, 93);

    // DevOps
    try g.addNode(100, "GitHub");
    try g.addNode(101, "Actions");
    try g.addNode(102, "ECR");
    try g.addNode(103, "ArgoCD");
    try g.addNode(104, "Terraform");
    try g.addNode(105, "EKS-US");
    try g.addNode(106, "EKS-EU");
    try g.addNode(107, "EKS-AP");
    try g.addEdge(100, 101);
    try g.addEdge(101, 102);
    try g.addEdge(102, 103);
    try g.addEdge(103, 105);
    try g.addEdge(103, 106);
    try g.addEdge(103, 107);
    try g.addEdge(104, 105);
    try g.addEdge(104, 106);
    try g.addEdge(104, 107);

    // Notifications
    try g.addNode(110, "SNS");
    try g.addNode(111, "SES");
    try g.addNode(112, "Slack");
    try g.addEdge(85, 110);
    try g.addEdge(110, 111);
    try g.addEdge(110, 112);

    // Subgraph hierarchy
    const us_fe = try g.addSubgraph("US-Frontend");
    try g.putNodes(&.{ 10, 11, 12 }).inside(us_fe);
    const us_au = try g.addSubgraph("US-Auth");
    try g.putNodes(&.{ 13, 14, 15 }).inside(us_au);
    const us_biz = try g.addSubgraph("US-Business");
    try g.putNodes(&.{ 16, 17, 18, 19 }).inside(us_biz);
    const us_data = try g.addSubgraph("US-Data");
    try g.putNodes(&.{ 20, 21, 22 }).inside(us_data);
    const region_us = try g.addSubgraph("US-East");
    try g.putSubgraphs(&.{ us_fe, us_au, us_biz, us_data }).inside(region_us);

    const eu_svc = try g.addSubgraph("EU-Services");
    try g.putNodes(&.{ 30, 31, 32, 33, 34 }).inside(eu_svc);
    const eu_db = try g.addSubgraph("EU-Data");
    try g.putNodes(&.{ 35, 36 }).inside(eu_db);
    const region_eu = try g.addSubgraph("EU-West");
    try g.putSubgraphs(&.{ eu_svc, eu_db }).inside(region_eu);

    const region_ap = try g.addSubgraph("APAC");
    try g.putNodes(&.{ 40, 41, 42, 43 }).inside(region_ap);

    const sg_msg = try g.addSubgraph("Event Bus");
    try g.putNodes(&.{ 50, 51, 52, 53 }).inside(sg_msg);

    const sg_ingest = try g.addSubgraph("Ingestion");
    try g.putNodes(&.{ 60, 61 }).inside(sg_ingest);
    const sg_store = try g.addSubgraph("Storage");
    try g.putNodes(&.{ 63, 64 }).inside(sg_store);
    const sg_dp = try g.addSubgraph("Data Platform");
    try g.putNodes(&.{ 62, 65 }).inside(sg_dp);
    try g.putSubgraphs(&.{ sg_ingest, sg_store }).inside(sg_dp);

    const sg_ml = try g.addSubgraph("ML Platform");
    try g.putNodes(&.{ 70, 71, 72, 73 }).inside(sg_ml);

    const sg_metrics = try g.addSubgraph("Metrics");
    try g.putNodes(&.{ 80, 84, 81 }).inside(sg_metrics);
    const sg_tracing = try g.addSubgraph("Tracing");
    try g.putNodes(&.{ 82, 83 }).inside(sg_tracing);
    const sg_alert = try g.addSubgraph("Alerting");
    try g.putNodes(&.{ 85, 86 }).inside(sg_alert);
    const sg_obs = try g.addSubgraph("Observability");
    try g.putSubgraphs(&.{ sg_metrics, sg_tracing, sg_alert }).inside(sg_obs);

    const sg_sec = try g.addSubgraph("Security");
    try g.putNodes(&.{ 90, 91, 92, 93 }).inside(sg_sec);

    const sg_cicd = try g.addSubgraph("CI/CD");
    try g.putNodes(&.{ 100, 101, 102, 103 }).inside(sg_cicd);
    const sg_infra = try g.addSubgraph("Infrastructure");
    try g.putNodes(&.{ 104, 105, 106, 107 }).inside(sg_infra);
    const sg_devops = try g.addSubgraph("Platform Eng");
    try g.putSubgraphs(&.{ sg_cicd, sg_infra }).inside(sg_devops);

    const sg_notif = try g.addSubgraph("Notifications");
    try g.putNodes(&.{ 110, 111, 112 }).inside(sg_notif);

    return g;
}

// ══════════════════════════════════════════════════════════════════════════════
//  FDG-SPECIFIC SCENARIOS
// ══════════════════════════════════════════════════════════════════════════════

// Cycles between clusters — FDG handles natively, no cycle-breaking needed
fn buildCyclicClusters(allocator: std.mem.Allocator) !Graph {
    var g = Graph.init(allocator);
    errdefer g.deinit();

    // Cluster A: web tier
    try g.addNode(1, "WebApp");
    try g.addNode(2, "CDN");
    try g.addNode(3, "Cache");
    try g.addEdge(1, 2);
    try g.addEdge(1, 3);

    // Cluster B: API tier
    try g.addNode(10, "API");
    try g.addNode(11, "AuthSvc");
    try g.addNode(12, "RateLimit");
    try g.addEdge(10, 11);
    try g.addEdge(10, 12);

    // Cluster C: data tier
    try g.addNode(20, "Postgres");
    try g.addNode(21, "Redis");
    try g.addNode(22, "S3");
    try g.addEdge(20, 21);
    try g.addEdge(20, 22);

    // Cross-cluster edges with cycles
    try g.addEdge(1, 10); // Web → API
    try g.addEdge(10, 20); // API → Data
    try g.addEdge(21, 3); // Data.Redis → Web.Cache (back-edge!)
    try g.addEdge(22, 2); // Data.S3 → Web.CDN (back-edge!)

    const web = try g.addSubgraph("Web Tier");
    const api = try g.addSubgraph("API Tier");
    const data = try g.addSubgraph("Data Tier");
    try g.putNodes(&.{ 1, 2, 3 }).inside(web);
    try g.putNodes(&.{ 10, 11, 12 }).inside(api);
    try g.putNodes(&.{ 20, 21, 22 }).inside(data);

    return g;
}

// Dense connectivity between clusters — stress the inter-cluster separation gap
fn buildDenseCrossCluster(allocator: std.mem.Allocator) !Graph {
    var g = Graph.init(allocator);
    errdefer g.deinit();

    // Three clusters of 4 nodes each
    const clusters = [_]struct { base: usize, prefix: []const u8 }{
        .{ .base = 0, .prefix = "A" },
        .{ .base = 10, .prefix = "B" },
        .{ .base = 20, .prefix = "C" },
    };

    var label_buf: [8]u8 = undefined;

    for (clusters) |cl| {
        for (0..4) |i| {
            const lbl = try std.fmt.bufPrint(&label_buf, "{s}{d}", .{ cl.prefix, i });
            try g.addNode(cl.base + i, try allocator.dupe(u8, lbl));
        }
        // Internal ring
        try g.addEdge(cl.base, cl.base + 1);
        try g.addEdge(cl.base + 1, cl.base + 2);
        try g.addEdge(cl.base + 2, cl.base + 3);
        try g.addEdge(cl.base + 3, cl.base);
    }

    // Dense cross-cluster: every A node connects to every B node
    for (0..4) |i| {
        for (0..4) |j| {
            try g.addEdge(i, 10 + j);
        }
    }
    // B→C: star from B0 to all C
    for (0..4) |j| {
        try g.addEdge(10, 20 + j);
    }
    // C→A: one diagonal
    try g.addEdge(20, 3);
    try g.addEdge(23, 0);

    const sg_a = try g.addSubgraph("Cluster A");
    const sg_b = try g.addSubgraph("Cluster B");
    const sg_c = try g.addSubgraph("Cluster C");
    try g.putNodes(&.{ 0, 1, 2, 3 }).inside(sg_a);
    try g.putNodes(&.{ 10, 11, 12, 13 }).inside(sg_b);
    try g.putNodes(&.{ 20, 21, 22, 23 }).inside(sg_c);

    return g;
}

// Singleton subgraphs — tests edge case of cohesion skip for single-member groups
fn buildSingletonSubgraphs(allocator: std.mem.Allocator) !Graph {
    var g = Graph.init(allocator);
    errdefer g.deinit();

    try g.addNode(1, "Hub");
    try g.addNode(2, "Alpha");
    try g.addNode(3, "Beta");
    try g.addNode(4, "Gamma");
    try g.addNode(5, "Delta");
    try g.addNode(6, "Epsilon");

    // Star from hub
    try g.addEdge(1, 2);
    try g.addEdge(1, 3);
    try g.addEdge(1, 4);
    try g.addEdge(1, 5);
    try g.addEdge(1, 6);
    // Ring among satellites
    try g.addEdge(2, 3);
    try g.addEdge(3, 4);
    try g.addEdge(4, 5);
    try g.addEdge(5, 6);
    try g.addEdge(6, 2);

    // Each satellite in its own singleton subgraph
    const sg_a = try g.addSubgraph("Α");
    const sg_b = try g.addSubgraph("Β");
    const sg_g = try g.addSubgraph("Γ");
    const sg_d = try g.addSubgraph("Δ");
    const sg_e = try g.addSubgraph("Ε");
    try g.putNodes(&.{2}).inside(sg_a);
    try g.putNodes(&.{3}).inside(sg_b);
    try g.putNodes(&.{4}).inside(sg_g);
    try g.putNodes(&.{5}).inside(sg_d);
    try g.putNodes(&.{6}).inside(sg_e);

    return g;
}

// Deeply nested subgraphs (depth 6) — linear nesting chain
fn buildDeepNesting(allocator: std.mem.Allocator) !Graph {
    var g = Graph.init(allocator);
    errdefer g.deinit();

    // 12 nodes in a chain
    var label_buf: [12]u8 = undefined;
    for (0..12) |i| {
        const lbl = try std.fmt.bufPrint(&label_buf, "N{d}", .{i});
        try g.addNode(i, try allocator.dupe(u8, lbl));
        if (i > 0) try g.addEdge(i - 1, i);
    }
    // Cross edges for visual interest
    try g.addEdge(0, 5);
    try g.addEdge(3, 9);
    try g.addEdge(6, 11);

    // Depth 6 nesting: L0 > L1 > L2 > L3 > L4 > L5
    const l5 = try g.addSubgraph("L5-Core");
    try g.putNodes(&.{ 5, 6 }).inside(l5);

    const l4 = try g.addSubgraph("L4-Inner");
    try g.putNodes(&.{ 4, 7 }).inside(l4);
    try g.putSubgraphs(&.{l5}).inside(l4);

    const l3 = try g.addSubgraph("L3-Middle");
    try g.putNodes(&.{ 3, 8 }).inside(l3);
    try g.putSubgraphs(&.{l4}).inside(l3);

    const l2 = try g.addSubgraph("L2-Outer");
    try g.putNodes(&.{ 2, 9 }).inside(l2);
    try g.putSubgraphs(&.{l3}).inside(l2);

    const l1 = try g.addSubgraph("L1-Shell");
    try g.putNodes(&.{ 1, 10 }).inside(l1);
    try g.putSubgraphs(&.{l2}).inside(l1);

    const l0 = try g.addSubgraph("L0-Root");
    try g.putNodes(&.{ 0, 11 }).inside(l0);
    try g.putSubgraphs(&.{l1}).inside(l0);

    return g;
}

// Many small subgraphs — 30 pairs (60 nodes), tests cohesion index scalability
fn buildManySmallSubgraphs(allocator: std.mem.Allocator) !Graph {
    var g = Graph.init(allocator);
    errdefer g.deinit();

    var label_buf: [16]u8 = undefined;

    for (0..30) |i| {
        const a = i * 2;
        const b = i * 2 + 1;
        const lbl_a = try std.fmt.bufPrint(&label_buf, "P{d}a", .{i});
        try g.addNode(a, try allocator.dupe(u8, lbl_a));
        const lbl_b = try std.fmt.bufPrint(&label_buf, "P{d}b", .{i});
        try g.addNode(b, try allocator.dupe(u8, lbl_b));
        try g.addEdge(a, b);

        // Chain pairs together
        if (i > 0) {
            try g.addEdge((i - 1) * 2 + 1, a);
        }

        const sg_lbl = try std.fmt.bufPrint(&label_buf, "Pair-{d}", .{i});
        const sg = try g.addSubgraph(try allocator.dupe(u8, sg_lbl));
        try g.putNodes(&.{ a, b }).inside(sg);
    }

    // A few cross-pair edges for extra connectivity
    try g.addEdge(0, 20);
    try g.addEdge(10, 40);
    try g.addEdge(30, 50);

    return g;
}

// Mix of subgraph nodes and free (ungrouped) nodes
fn buildMixedFreeNodes(allocator: std.mem.Allocator) !Graph {
    var g = Graph.init(allocator);
    errdefer g.deinit();

    // Free nodes (not in any subgraph)
    try g.addNode(1, "Router");
    try g.addNode(2, "Firewall");
    try g.addNode(3, "DNS");
    try g.addEdge(1, 2);
    try g.addEdge(2, 3);
    try g.addEdge(3, 1);

    // Cluster A
    try g.addNode(10, "Web-1");
    try g.addNode(11, "Web-2");
    try g.addNode(12, "LB");
    try g.addEdge(10, 12);
    try g.addEdge(11, 12);

    // Cluster B
    try g.addNode(20, "DB-Primary");
    try g.addNode(21, "DB-Replica");
    try g.addNode(22, "DB-Backup");
    try g.addEdge(20, 21);
    try g.addEdge(20, 22);

    // Free → cluster edges
    try g.addEdge(1, 12); // Router → LB
    try g.addEdge(12, 20); // LB → DB-Primary
    try g.addEdge(2, 10); // Firewall → Web-1

    const sg_web = try g.addSubgraph("Web Servers");
    const sg_db = try g.addSubgraph("Database");
    try g.putNodes(&.{ 10, 11, 12 }).inside(sg_web);
    try g.putNodes(&.{ 20, 21, 22 }).inside(sg_db);

    return g;
}

// Specifically designed to stress the inter-cluster separation gap:
// Three tightly connected clusters with minimal cross-edges
fn buildOverlappingClusters(allocator: std.mem.Allocator) !Graph {
    var g = Graph.init(allocator);
    errdefer g.deinit();

    // Cluster A: complete graph on 5 nodes (10 edges)
    for (0..5) |i| {
        var buf: [4]u8 = undefined;
        const lbl = try std.fmt.bufPrint(&buf, "A{d}", .{i});
        try g.addNode(i, try allocator.dupe(u8, lbl));
    }
    for (0..5) |i| {
        for (i + 1..5) |j| {
            try g.addEdge(i, j);
        }
    }

    // Cluster B: complete on 5 nodes
    for (0..5) |i| {
        var buf: [4]u8 = undefined;
        const lbl = try std.fmt.bufPrint(&buf, "B{d}", .{i});
        try g.addNode(10 + i, try allocator.dupe(u8, lbl));
    }
    for (0..5) |i| {
        for (i + 1..5) |j| {
            try g.addEdge(10 + i, 10 + j);
        }
    }

    // Cluster C: complete on 5 nodes
    for (0..5) |i| {
        var buf: [4]u8 = undefined;
        const lbl = try std.fmt.bufPrint(&buf, "C{d}", .{i});
        try g.addNode(20 + i, try allocator.dupe(u8, lbl));
    }
    for (0..5) |i| {
        for (i + 1..5) |j| {
            try g.addEdge(20 + i, 20 + j);
        }
    }

    // Only 1 cross-edge per cluster pair — should they still separate?
    try g.addEdge(0, 10); // A0 → B0
    try g.addEdge(10, 20); // B0 → C0
    try g.addEdge(20, 0); // C0 → A0 (cycle)

    const sg_a = try g.addSubgraph("Cluster A");
    const sg_b = try g.addSubgraph("Cluster B");
    const sg_c = try g.addSubgraph("Cluster C");
    try g.putNodes(&.{ 0, 1, 2, 3, 4 }).inside(sg_a);
    try g.putNodes(&.{ 10, 11, 12, 13, 14 }).inside(sg_b);
    try g.putNodes(&.{ 20, 21, 22, 23, 24 }).inside(sg_c);

    return g;
}

// ══════════════════════════════════════════════════════════════════════════════
//  LARGE-SCALE BUILDERS
// ══════════════════════════════════════════════════════════════════════════════

// 200 nodes in 10 clusters of 20, with cross-cluster edges
fn buildLargeClustered(allocator: std.mem.Allocator) !Graph {
    var g = Graph.init(allocator);
    errdefer g.deinit();

    const clusters = 10;
    const per_cluster = 20;
    var label_buf: [16]u8 = undefined;

    // Create nodes and intra-cluster chain
    for (0..clusters) |c| {
        const base = c * per_cluster;
        for (0..per_cluster) |i| {
            const lbl = try std.fmt.bufPrint(&label_buf, "C{d}N{d}", .{ c, i });
            try g.addNode(base + i, try allocator.dupe(u8, lbl));
            if (i > 0) try g.addEdge(base + i - 1, base + i);
        }
        // Close the intra-cluster ring
        try g.addEdge(base + per_cluster - 1, base);

        // Register subgraph
        const sg_lbl = try std.fmt.bufPrint(&label_buf, "Cluster-{d}", .{c});
        const sg = try g.addSubgraph(try allocator.dupe(u8, sg_lbl));
        var node_ids: [per_cluster]usize = undefined;
        for (0..per_cluster) |i| node_ids[i] = base + i;
        try g.putNodes(&node_ids).inside(sg);
    }

    // Cross-cluster: connect cluster i → i+1 via first nodes
    for (0..clusters - 1) |c| {
        try g.addEdge(c * per_cluster, (c + 1) * per_cluster);
    }
    // Close the ring of clusters
    try g.addEdge((clusters - 1) * per_cluster, 0);

    // A few more cross-cluster edges for density
    for (0..clusters) |c| {
        const next = (c + 2) % clusters;
        try g.addEdge(c * per_cluster + 5, next * per_cluster + 10);
    }

    return g;
}

// 500 nodes in 25 clusters of 20
fn buildVeryLargeClustered(allocator: std.mem.Allocator) !Graph {
    var g = Graph.init(allocator);
    errdefer g.deinit();

    const clusters = 25;
    const per_cluster = 20;
    var label_buf: [16]u8 = undefined;

    for (0..clusters) |c| {
        const base = c * per_cluster;
        for (0..per_cluster) |i| {
            const lbl = try std.fmt.bufPrint(&label_buf, "C{d}N{d}", .{ c, i });
            try g.addNode(base + i, try allocator.dupe(u8, lbl));
            if (i > 0) try g.addEdge(base + i - 1, base + i);
        }
        try g.addEdge(base + per_cluster - 1, base);

        const sg_lbl = try std.fmt.bufPrint(&label_buf, "Cluster-{d}", .{c});
        const sg = try g.addSubgraph(try allocator.dupe(u8, sg_lbl));
        var node_ids: [per_cluster]usize = undefined;
        for (0..per_cluster) |i| node_ids[i] = base + i;
        try g.putNodes(&node_ids).inside(sg);
    }

    // Ring of clusters
    for (0..clusters - 1) |c| {
        try g.addEdge(c * per_cluster, (c + 1) * per_cluster);
    }
    try g.addEdge((clusters - 1) * per_cluster, 0);

    // Skip-1 cross-cluster
    for (0..clusters) |c| {
        const next = (c + 2) % clusters;
        try g.addEdge(c * per_cluster + 3, next * per_cluster + 7);
    }

    return g;
}
