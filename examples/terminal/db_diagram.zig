//! Database ER Diagram — CRM schema with real edge routing.
//!
//! Demonstrates `paint_fn` for ER-style entity nodes with colored field
//! annotations and proper edge routing.  The layout engine respects the
//! declared node height, so edges route around the full record box.
//!
//! Two sections:
//!   1. Sugiyama layout — customers → orders, customers → addresses
//!   2. FDG layout     — same entities with a cyclic FK back-edge
//!
//! Run with: zig build run-terminal-db-diagram

const std = @import("std");
const zigraph = @import("zigraph");
const T = zigraph.terminal;
const record = @import("record_nodes.zig");

const Entity = record.Entity;
const Field = record.Field;

const EDGE_COLOR = T.Color{ .rgb = .{ .r = 110, .g = 160, .b = 220 } };

// ── Schema data ───────────────────────────────────────────────────────────────

const customers = Entity{
    .name = "customers",
    .fields = &.{
        .{ .text = "id: INTEGER", .kind = .pk },
        .{ .text = "name: VARCHAR" },
        .{ .text = "email: TEXT" },
        .{ .text = "phone: VARCHAR" },
    },
};

const orders = Entity{
    .name = "orders",
    .fields = &.{
        .{ .text = "id: INTEGER", .kind = .pk },
        .{ .text = "customer_id: INT", .kind = .fk },
        .{ .text = "total: DECIMAL" },
        .{ .text = "status: VARCHAR" },
        .{ .text = "date: DATE" },
    },
};

const addresses = Entity{
    .name = "addresses",
    .fields = &.{
        .{ .text = "id: INTEGER", .kind = .pk },
        .{ .text = "customer_id: INT", .kind = .fk },
        .{ .text = "street: VARCHAR" },
        .{ .text = "city: VARCHAR" },
        .{ .text = "zip: VARCHAR" },
    },
};

// ── Paint wrappers ────────────────────────────────────────────────────────────

fn paintCustomers(buf: *T.Buffer2D, ctx: T.NodePaintContext) void {
    customers.paint(buf, ctx);
}
fn paintOrders(buf: *T.Buffer2D, ctx: T.NodePaintContext) void {
    orders.paint(buf, ctx);
}
fn paintAddresses(buf: *T.Buffer2D, ctx: T.NodePaintContext) void {
    addresses.paint(buf, ctx);
}

fn nodeStyle(ctx: T.NodeStyleContext) T.TerminalNodeStyle {
    if (std.mem.eql(u8, ctx.label, "customers"))
        return .{ .border = .none, .paint_fn = &paintCustomers };
    if (std.mem.eql(u8, ctx.label, "orders"))
        return .{ .border = .none, .paint_fn = &paintOrders };
    if (std.mem.eql(u8, ctx.label, "addresses"))
        return .{ .border = .none, .paint_fn = &paintAddresses };
    return .{ .border = .single_box };
}

fn edgeStyle(_: T.EdgeStyleContext) T.TerminalEdgeStyle {
    return .{
        .color = EDGE_COLOR,
        .marker_end = .arrow,
    };
}

// ── Main ──────────────────────────────────────────────────────────────────────

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    std.debug.print(
        \\
        \\Terminal DB Diagram -- CRM Schema
        \\====================================
        \\customers --> orders / addresses  (1:N FK relationships)
        \\
        \\
    , .{});

    // ── Section 1: Sugiyama layout ────────────────────────────────────────────

    {
        std.debug.print("Section 1: Sugiyama Layout\n", .{});
        std.debug.print("--------------------------\n\n", .{});

        var g = zigraph.Graph.init(alloc);
        defer g.deinit();

        try g.addNode(1, customers.nodeOptions());
        try g.addNode(2, orders.nodeOptions());
        try g.addNode(3, addresses.nodeOptions());

        try g.addEdge(1, 2);
        try g.addEdge(1, 3);

        var ir = try zigraph.layout(&g, alloc, .{});
        defer ir.deinit();

        const output = try T.renderWithConfig(&ir, alloc, .{
            .node_style_fn = &nodeStyle,
            .edge_style_fn = &edgeStyle,
            .color_mode = .truecolor,
        });
        defer alloc.free(output);

        std.debug.print("{s}\n", .{output});
    }

    // ── Legend ────────────────────────────────────────────────────────────────

    const lw: usize = 46;
    for (0..lw) |_| std.debug.print("-", .{});
    std.debug.print("\n", .{});
    std.debug.print("\x1b[38;2;255;215;0m  [PK]  Primary Key\x1b[0m\n", .{});
    std.debug.print("\x1b[38;2;100;220;140m  [FK]  Foreign Key\x1b[0m\n", .{});
    std.debug.print("\x1b[38;2;185;195;210m  [ ]   Regular column\x1b[0m\n", .{});
    for (0..lw) |_| std.debug.print("-", .{});
    std.debug.print("\n", .{});

    // ── Section 2: FDG layout (cyclic FKs) ────────────────────────────────────

    {
        std.debug.print(
            \\
            \\
            \\Section 2: FDG Layout (cyclic FK graph)
            \\----------------------------------------
            \\addresses --> customers back-edge creates a cycle;
            \\FDG handles it natively without cycle-breaking.
            \\
            \\
        , .{});

        var g2 = zigraph.Graph.init(alloc);
        defer g2.deinit();

        try g2.addNode(1, customers.nodeOptions());
        try g2.addNode(2, orders.nodeOptions());
        try g2.addNode(3, addresses.nodeOptions());

        try g2.addEdge(1, 2);
        try g2.addEdge(1, 3);
        try g2.addEdge(2, 3);
        try g2.addEdge(3, 1); // back-edge: cycle

        var ir2 = try zigraph.layout(&g2, alloc, .{
            .algorithm = .{ .fruchterman_reingold = .{} },
        });
        defer ir2.deinit();

        const output2 = try T.renderWithConfig(&ir2, alloc, .{
            .node_style_fn = &nodeStyle,
            .edge_style_fn = &edgeStyle,
            .color_mode = .truecolor,
        });
        defer alloc.free(output2);

        std.debug.print("{s}\n", .{output2});

        for (0..lw) |_| std.debug.print("-", .{});
        std.debug.print("\n", .{});
        std.debug.print("  FDG note: edges connect node tops (raw IR coords).\n", .{});
        std.debug.print("  Record-node field rows may overlap FDG edge lines\n", .{});
        std.debug.print("  when nodes are close -- known trade-off of free-form layout.\n", .{});
        for (0..lw) |_| std.debug.print("-", .{});
        std.debug.print("\n", .{});
    }
}
