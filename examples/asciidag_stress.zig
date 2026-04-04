//! ascii-dag stress port — zigraph vs ascii-dag benchmark.
//!
//! Ports all stress tiers from ascii-dag's subgraph_stress.rs and
//! representative scenarios from stress_test.rs to compare rendering quality.
//!
//! Run with: zig build run-asciidag-stress

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
        \\╔══════════════════════════════════════════════════════╗
        \\║   zigraph — ascii-dag Stress Port                    ║
        \\║   Subgraph tiers + representative stress scenarios   ║
        \\╚══════════════════════════════════════════════════════╝
        \\
        \\
    );

    // ── Subgraph stress tiers (from ascii-dag/examples/subgraph_stress.rs) ──
    try stdout.writeAll("═══ SUBGRAPH STRESS TIERS ═══════════════════════════════════\n\n");

    try runTest(stdout, allocator, "Tier 1 · Microservices (12 nodes, 4 subgraphs, depth 1)", buildTier1);
    try runTest(stdout, allocator, "Tier 2 · Platform (20 nodes, 8 subgraphs, depth 2)", buildTier2);
    try runTest(stdout, allocator, "Tier 3 · Cloud Infra (~30 nodes, 12 subgraphs, depth 3)", buildTier3);
    try runTest(stdout, allocator, "Tier 4 · Enterprise (~50 nodes, 16 subgraphs, depth 3)", buildTier4);
    try runTest(stdout, allocator, "Tier 5 · Megacorp (~80 nodes, 24 subgraphs, depth 4)", buildTier5);

    // ── Representative scenarios from stress_test.rs ──
    try stdout.writeAll("═══ MISC STRESS SCENARIOS ════════════════════════════════════\n\n");

    try runTest(stdout, allocator, "Double Helix (20 nodes, 2 chains)", buildDoubleHelix);
    try runTest(stdout, allocator, "Skyscraper (50 nodes, deep chain)", buildSkyscraper);
    try runTest(stdout, allocator, "Wide Fan (52 nodes, source+50 workers+sink)", buildWideFan);
    try runTest(stdout, allocator, "Diamond Lattice (5×10 = 50 nodes)", buildDiamondLattice);
    try runTest(stdout, allocator, "Disconnected Islands (15 nodes, 5 components)", buildDisconnectedIslands);
    try runTest(stdout, allocator, "Skip-Level Nightmare (6 nodes, many skip edges)", buildSkipLevelNightmare);
    try runTest(stdout, allocator, "Verbose Label (4 nodes, long label)", buildVerboseLogger);
    try runTest(stdout, allocator, "Ouroboros (3 nodes, cycle)", buildOuroboros);

    try stdout.writeAll("═══ LARGE GRAPHS (output suppressed) ════════════════════════\n\n");
    try runLargeTest(stdout, allocator, "Massive Diamond ~20k nodes (142×142)", buildMassiveDiamond20k);
    try runLargeTest(stdout, allocator, "Massive Fan ~50k nodes", buildMassiveFan50k);

    try stdout.writeAll("\nDone.\n");
}

fn runTest(
    writer: anytype,
    allocator: std.mem.Allocator,
    name: []const u8,
    comptime buildFn: fn (std.mem.Allocator) anyerror!Graph,
) !void {
    try writer.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n", .{});
    try writer.print("  {s}\n", .{name});
    try writer.print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n", .{});

    var graph = buildFn(allocator) catch |err| {
        try writer.print("  [BUILD ERROR: {}]\n\n", .{err});
        return;
    };
    defer graph.deinit();

    const t0 = time.nanoTimestamp();
    const output = zigraph.render(&graph, allocator, .{}) catch |err| {
        try writer.print("  [RENDER ERROR: {}]\n\n", .{err});
        return;
    };
    const elapsed_ns = @as(u64, @intCast(time.nanoTimestamp() - t0));
    defer allocator.free(output);

    const lines = std.mem.count(u8, output, "\n");
    var max_w: usize = 0;
    var it = std.mem.splitScalar(u8, output, '\n');
    while (it.next()) |line| {
        if (line.len > max_w) max_w = line.len;
    }

    try writer.print("{s}\n", .{output});
    try writer.print("  [{d} chars, {d}×{d}, {d}µs]\n\n", .{
        output.len,                      max_w, lines,
        elapsed_ns / std.time.ns_per_us,
    });
}

fn runLargeTest(
    writer: anytype,
    allocator: std.mem.Allocator,
    name: []const u8,
    comptime buildFn: fn (std.mem.Allocator) anyerror!Graph,
) !void {
    try writer.print("  {s}\n", .{name});

    var graph = buildFn(allocator) catch |err| {
        try writer.print("  [BUILD ERROR: {}]\n\n", .{err});
        return;
    };
    defer graph.deinit();

    const t0 = time.nanoTimestamp();
    const output = zigraph.render(&graph, allocator, .{}) catch |err| {
        try writer.print("  [RENDER ERROR: {}]\n\n", .{err});
        return;
    };
    const elapsed_ns = @as(u64, @intCast(time.nanoTimestamp() - t0));
    defer allocator.free(output);

    try writer.print("  (output suppressed — {d} chars, {d}ms)\n\n", .{
        output.len, elapsed_ns / std.time.ns_per_ms,
    });
}

// ── Subgraph Tier 1: Microservices ─────────────────────────────────────────
// 12 nodes, 4 subgraphs, depth 1

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

    try g.addDiEdge(1, 10);
    try g.addDiEdge(1, 20);
    try g.addDiEdge(1, 30);
    try g.addDiEdge(10, 11);
    try g.addDiEdge(20, 21);
    try g.addDiEdge(30, 31);
    try g.addDiEdge(30, 32);
    try g.addDiEdge(32, 40);
    try g.addDiEdge(40, 41);
    try g.addDiEdge(40, 42);

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

// ── Subgraph Tier 2: Platform ───────────────────────────────────────────────
// 20 nodes, 8 subgraphs, depth 2

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

    try g.addDiEdge(1, 10);
    try g.addDiEdge(1, 11);
    try g.addDiEdge(2, 12);
    try g.addDiEdge(10, 20);
    try g.addDiEdge(11, 20);
    try g.addDiEdge(12, 22);
    try g.addDiEdge(20, 21);
    try g.addDiEdge(22, 23);
    try g.addDiEdge(20, 30);
    try g.addDiEdge(22, 30);
    try g.addDiEdge(30, 31);
    try g.addDiEdge(30, 32);
    try g.addDiEdge(31, 40);
    try g.addDiEdge(40, 41);
    try g.addDiEdge(40, 42);
    try g.addDiEdge(42, 43);
    try g.addDiEdge(32, 50);
    try g.addDiEdge(50, 51);
    try g.addDiEdge(51, 52);

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

// ── Subgraph Tier 3: Cloud Infra ────────────────────────────────────────────
// ~30 nodes, 12 subgraphs, depth 3

fn buildTier3(allocator: std.mem.Allocator) !Graph {
    var g = Graph.init(allocator);
    errdefer g.deinit();

    // Ingress
    try g.addNode(1, "ALB");
    try g.addNode(2, "WAF");
    try g.addDiEdge(1, 2);

    // Region A — AZ1
    try g.addNode(10, "Web-A1");
    try g.addNode(11, "App-A1");
    try g.addNode(12, "DB-A1");
    try g.addDiEdge(2, 10);
    try g.addDiEdge(10, 11);
    try g.addDiEdge(11, 12);

    // Region A — AZ2
    try g.addNode(13, "Web-A2");
    try g.addNode(14, "App-A2");
    try g.addNode(15, "DB-A2");
    try g.addDiEdge(2, 13);
    try g.addDiEdge(13, 14);
    try g.addDiEdge(14, 15);

    // Region B — AZ1
    try g.addNode(20, "Web-B1");
    try g.addNode(21, "App-B1");
    try g.addNode(22, "Redis-B1");
    try g.addNode(23, "DB-B1");
    try g.addDiEdge(2, 20);
    try g.addDiEdge(20, 21);
    try g.addDiEdge(21, 22);
    try g.addDiEdge(22, 23);

    // Region B — AZ2
    try g.addNode(24, "Web-B2");
    try g.addNode(25, "App-B2");
    try g.addNode(26, "Redis-B2");
    try g.addNode(27, "DB-B2");
    try g.addDiEdge(2, 24);
    try g.addDiEdge(24, 25);
    try g.addDiEdge(25, 26);
    try g.addDiEdge(26, 27);

    // Shared services
    try g.addNode(30, "RabbitMQ");
    try g.addNode(31, "S3-Bucket");
    try g.addNode(32, "Vault");
    try g.addDiEdge(11, 30);
    try g.addDiEdge(21, 30);
    try g.addDiEdge(30, 31);

    // CI/CD
    try g.addNode(40, "Jenkins");
    try g.addNode(41, "ArgoCD");
    try g.addNode(42, "ECR");
    try g.addDiEdge(40, 42);
    try g.addDiEdge(42, 41);
    try g.addDiEdge(41, 10);
    try g.addDiEdge(41, 20);

    // Monitoring
    try g.addNode(50, "Prometheus");
    try g.addNode(51, "Grafana");
    try g.addNode(52, "Loki");
    try g.addDiEdge(50, 51);
    try g.addDiEdge(52, 51);
    try g.addDiEdge(11, 50);
    try g.addDiEdge(21, 52);

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

// ── Subgraph Tier 4: Enterprise ─────────────────────────────────────────────
// ~50 nodes, 16 subgraphs, depth 3

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
    try g.addDiEdge(1, 10);
    try g.addDiEdge(2, 10);
    try g.addDiEdge(10, 11);
    try g.addDiEdge(10, 12);
    try g.addDiEdge(11, 13);

    // Auth → domains
    try g.addDiEdge(10, 20);
    try g.addDiEdge(10, 30);
    try g.addDiEdge(10, 40);

    // Customer
    try g.addDiEdge(20, 21);
    try g.addDiEdge(21, 22);
    try g.addDiEdge(21, 23);

    // Product
    try g.addDiEdge(30, 31);
    try g.addDiEdge(30, 32);
    try g.addDiEdge(31, 33);
    try g.addDiEdge(31, 34);
    try g.addDiEdge(32, 34);

    // Order
    try g.addDiEdge(40, 41);
    try g.addDiEdge(40, 43);
    try g.addDiEdge(41, 42);
    try g.addDiEdge(43, 44);
    try g.addDiEdge(41, 50);
    try g.addDiEdge(41, 60);

    // Payment
    try g.addDiEdge(50, 51);
    try g.addDiEdge(51, 52);
    try g.addDiEdge(51, 53);

    // Shipping
    try g.addDiEdge(60, 61);
    try g.addDiEdge(61, 62);
    try g.addDiEdge(61, 63);

    // Messaging
    try g.addDiEdge(41, 70);
    try g.addDiEdge(51, 70);
    try g.addDiEdge(61, 70);
    try g.addDiEdge(70, 71);

    // Data
    try g.addDiEdge(70, 80);
    try g.addDiEdge(80, 81);
    try g.addDiEdge(82, 80);
    try g.addDiEdge(81, 83);

    // Observability
    try g.addDiEdge(70, 90);
    try g.addDiEdge(90, 91);
    try g.addDiEdge(90, 92);
    try g.addDiEdge(90, 93);
    try g.addDiEdge(91, 94);

    // Notifications
    try g.addDiEdge(41, 110);
    try g.addDiEdge(110, 111);
    try g.addDiEdge(110, 112);
    try g.addDiEdge(110, 113);

    // DevOps
    try g.addDiEdge(100, 101);
    try g.addDiEdge(101, 104);
    try g.addDiEdge(104, 103);
    try g.addDiEdge(102, 103);

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

// ── Subgraph Tier 5: Megacorp ────────────────────────────────────────────────
// ~80 nodes, 24 subgraphs, depth 4

fn buildTier5(allocator: std.mem.Allocator) !Graph {
    var g = Graph.init(allocator);
    errdefer g.deinit();

    // Global entry
    try g.addNode(1, "Route53");
    try g.addNode(2, "CloudFront");
    try g.addNode(3, "WAF");
    try g.addDiEdge(1, 2);
    try g.addDiEdge(2, 3);

    // US Region — Frontend
    try g.addNode(10, "US-Web");
    try g.addNode(11, "US-Mobile");
    try g.addNode(12, "US-SSR");
    try g.addDiEdge(3, 10);
    try g.addDiEdge(3, 11);
    try g.addDiEdge(10, 12);

    // US Region — Auth
    try g.addNode(13, "US-Auth");
    try g.addNode(14, "US-Token");
    try g.addNode(15, "US-MFA");
    try g.addDiEdge(10, 13);
    try g.addDiEdge(11, 13);
    try g.addDiEdge(13, 14);
    try g.addDiEdge(13, 15);

    // US Region — Business
    try g.addNode(16, "US-Orders");
    try g.addNode(17, "US-Pay");
    try g.addNode(18, "US-Inv");
    try g.addNode(19, "US-Ship");
    try g.addDiEdge(13, 16);
    try g.addDiEdge(16, 17);
    try g.addDiEdge(16, 18);
    try g.addDiEdge(16, 19);

    // US Region — Data
    try g.addNode(20, "US-Postgres");
    try g.addNode(21, "US-Redis");
    try g.addNode(22, "US-S3");
    try g.addDiEdge(16, 20);
    try g.addDiEdge(17, 20);
    try g.addDiEdge(13, 21);
    try g.addDiEdge(18, 22);

    // EU Region
    try g.addNode(30, "EU-Web");
    try g.addNode(31, "EU-Auth");
    try g.addNode(32, "EU-Orders");
    try g.addNode(33, "EU-Pay");
    try g.addNode(34, "EU-Ship");
    try g.addNode(35, "EU-Postgres");
    try g.addNode(36, "EU-Redis");
    try g.addDiEdge(3, 30);
    try g.addDiEdge(30, 31);
    try g.addDiEdge(31, 32);
    try g.addDiEdge(32, 33);
    try g.addDiEdge(32, 34);
    try g.addDiEdge(32, 35);
    try g.addDiEdge(31, 36);

    // APAC Region
    try g.addNode(40, "AP-Web");
    try g.addNode(41, "AP-Auth");
    try g.addNode(42, "AP-Orders");
    try g.addNode(43, "AP-Postgres");
    try g.addDiEdge(3, 40);
    try g.addDiEdge(40, 41);
    try g.addDiEdge(41, 42);
    try g.addDiEdge(42, 43);

    // Messaging
    try g.addNode(50, "Kafka-1");
    try g.addNode(51, "Kafka-2");
    try g.addNode(52, "Zookeeper");
    try g.addNode(53, "SchemaReg");
    try g.addDiEdge(16, 50);
    try g.addDiEdge(32, 50);
    try g.addDiEdge(50, 51);
    try g.addDiEdge(50, 52);
    try g.addDiEdge(51, 53);

    // Data Platform
    try g.addNode(60, "Spark");
    try g.addNode(61, "Flink");
    try g.addNode(62, "Airflow");
    try g.addNode(63, "DataLake");
    try g.addNode(64, "Redshift");
    try g.addNode(65, "Tableau");
    try g.addDiEdge(51, 60);
    try g.addDiEdge(51, 61);
    try g.addDiEdge(62, 60);
    try g.addDiEdge(60, 63);
    try g.addDiEdge(61, 63);
    try g.addDiEdge(63, 64);
    try g.addDiEdge(64, 65);

    // ML Platform
    try g.addNode(70, "MLflow");
    try g.addNode(71, "SageMaker");
    try g.addNode(72, "ModelReg");
    try g.addNode(73, "Inference");
    try g.addDiEdge(63, 70);
    try g.addDiEdge(70, 71);
    try g.addDiEdge(71, 72);
    try g.addDiEdge(72, 73);

    // Observability
    try g.addNode(80, "Prometheus");
    try g.addNode(81, "Grafana");
    try g.addNode(82, "Jaeger");
    try g.addNode(83, "Loki");
    try g.addNode(84, "Cortex");
    try g.addNode(85, "PagerDuty");
    try g.addNode(86, "OpsGenie");
    try g.addDiEdge(16, 80);
    try g.addDiEdge(32, 80);
    try g.addDiEdge(80, 84);
    try g.addDiEdge(84, 81);
    try g.addDiEdge(80, 82);
    try g.addDiEdge(80, 83);
    try g.addDiEdge(81, 85);
    try g.addDiEdge(81, 86);

    // Security
    try g.addNode(90, "Vault");
    try g.addNode(91, "CertMgr");
    try g.addNode(92, "GuardDuty");
    try g.addNode(93, "Inspector");
    try g.addDiEdge(13, 90);
    try g.addDiEdge(31, 90);
    try g.addDiEdge(90, 91);
    try g.addDiEdge(90, 92);
    try g.addDiEdge(92, 93);

    // DevOps
    try g.addNode(100, "GitHub");
    try g.addNode(101, "Actions");
    try g.addNode(102, "ECR");
    try g.addNode(103, "ArgoCD");
    try g.addNode(104, "Terraform");
    try g.addNode(105, "EKS-US");
    try g.addNode(106, "EKS-EU");
    try g.addNode(107, "EKS-AP");
    try g.addDiEdge(100, 101);
    try g.addDiEdge(101, 102);
    try g.addDiEdge(102, 103);
    try g.addDiEdge(103, 105);
    try g.addDiEdge(103, 106);
    try g.addDiEdge(103, 107);
    try g.addDiEdge(104, 105);
    try g.addDiEdge(104, 106);
    try g.addDiEdge(104, 107);

    // Notifications
    try g.addNode(110, "SNS");
    try g.addNode(111, "SES");
    try g.addNode(112, "Slack");
    try g.addDiEdge(85, 110);
    try g.addDiEdge(110, 111);
    try g.addDiEdge(110, 112);

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

// ── Misc stress scenarios ───────────────────────────────────────────────────

fn buildDoubleHelix(allocator: std.mem.Allocator) !Graph {
    var g = Graph.init(allocator);
    errdefer g.deinit();
    for (0..10) |i| {
        try g.addNode(i * 2, "A");
        try g.addNode(i * 2 + 1, "B");
        if (i > 0) {
            try g.addDiEdge((i - 1) * 2, i * 2);
            try g.addDiEdge((i - 1) * 2 + 1, i * 2 + 1);
            if (i % 2 == 0) {
                try g.addDiEdge((i - 1) * 2, i * 2 + 1);
                try g.addDiEdge((i - 1) * 2 + 1, i * 2);
            }
        }
    }
    return g;
}

fn buildSkyscraper(allocator: std.mem.Allocator) !Graph {
    var g = Graph.init(allocator);
    errdefer g.deinit();
    var label_buf: [16]u8 = undefined;
    for (0..50) |i| {
        const lbl = try std.fmt.bufPrint(&label_buf, "F{d}", .{i});
        try g.addNode(i, try allocator.dupe(u8, lbl));
        if (i > 0) try g.addDiEdge(i - 1, i);
    }
    return g;
}

fn buildWideFan(allocator: std.mem.Allocator) !Graph {
    var g = Graph.init(allocator);
    errdefer g.deinit();
    try g.addNode(0, "Source");
    try g.addNode(1000, "Sink");
    var label_buf: [12]u8 = undefined;
    for (1..51) |i| {
        const lbl = try std.fmt.bufPrint(&label_buf, "W{d}", .{i});
        try g.addNode(i, try allocator.dupe(u8, lbl));
        try g.addDiEdge(0, i);
        try g.addDiEdge(i, 1000);
    }
    return g;
}

fn buildDiamondLattice(allocator: std.mem.Allocator) !Graph {
    var g = Graph.init(allocator);
    errdefer g.deinit();
    const width = 5;
    const height = 10;
    for (0..height) |y| {
        for (0..width) |x| {
            const id = y * width + x;
            try g.addNode(id, "♦");
            if (y > 0) {
                try g.addDiEdge((y - 1) * width + x, id);
                if (x > 0) try g.addDiEdge((y - 1) * width + (x - 1), id);
                if (x < width - 1) try g.addDiEdge((y - 1) * width + (x + 1), id);
            }
        }
    }
    return g;
}

fn buildDisconnectedIslands(allocator: std.mem.Allocator) !Graph {
    var g = Graph.init(allocator);
    errdefer g.deinit();
    for (0..5) |island| {
        const base = island * 10;
        try g.addNode(base, "Island");
        try g.addNode(base + 1, "Palm");
        try g.addNode(base + 2, "Coconuts");
        try g.addDiEdge(base, base + 1);
        try g.addDiEdge(base + 1, base + 2);
    }
    return g;
}

fn buildSkipLevelNightmare(allocator: std.mem.Allocator) !Graph {
    var g = Graph.init(allocator);
    errdefer g.deinit();
    try g.addNode(0, "Root");
    for (1..6) |i| {
        var buf: [4]u8 = undefined;
        const lbl = try std.fmt.bufPrint(&buf, "L{d}", .{i});
        try g.addNode(i, try allocator.dupe(u8, lbl));
        try g.addDiEdge(i - 1, i);
    }
    // Skip edges: 0→2, 0→3, 0→4, 0→5
    for (2..6) |i| try g.addDiEdge(0, i);
    try g.addDiEdge(1, 3);
    try g.addDiEdge(2, 5);
    return g;
}

fn buildVerboseLogger(allocator: std.mem.Allocator) !Graph {
    var g = Graph.init(allocator);
    errdefer g.deinit();
    try g.addNode(1, "A");
    try g.addNode(2, "B");
    try g.addNode(3, "Error: NullPointerException at line 55 (Critical Failure)");
    try g.addNode(4, "C");
    try g.addDiEdge(1, 2);
    try g.addDiEdge(1, 3);
    try g.addDiEdge(3, 4);
    return g;
}

fn buildOuroboros(allocator: std.mem.Allocator) !Graph {
    var g = Graph.init(allocator);
    errdefer g.deinit();
    try g.addNode(1, "Head");
    try g.addNode(2, "Body");
    try g.addNode(3, "Tail");
    try g.addDiEdge(1, 2);
    try g.addDiEdge(2, 3);
    try g.addDiEdge(3, 1); // cycle
    return g;
}

fn buildMassiveDiamond20k(allocator: std.mem.Allocator) !Graph {
    var g = Graph.init(allocator);
    errdefer g.deinit();
    const width = 142;
    const height = 142;
    for (0..height) |y| {
        for (0..width) |x| {
            const id = y * width + x;
            try g.addNode(id, ".");
            if (y < height - 1) {
                try g.addDiEdge(id, (y + 1) * width + x);
                if (x < width - 1) try g.addDiEdge(id, (y + 1) * width + (x + 1));
            }
        }
    }
    return g;
}

fn buildMassiveFan50k(allocator: std.mem.Allocator) !Graph {
    var g = Graph.init(allocator);
    errdefer g.deinit();
    const root = 0;
    const sink = 50001;
    try g.addNode(root, "S");
    try g.addNode(sink, "E");
    for (1..50001) |i| {
        try g.addNode(i, ".");
        try g.addDiEdge(root, i);
        try g.addDiEdge(i, sink);
    }
    return g;
}
