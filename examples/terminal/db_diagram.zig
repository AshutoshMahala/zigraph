//! Database ER Diagram — CRM schema with real edge routing.
//!
//! Builds on the record-node technique from record_nodes.zig and wires the
//! entities together with proper graph edges so the layout engine routes
//! connecting lines between the tables.
//!
//! ## The gap-fill strategy
//!
//! The terminal renderer places each level's header boxes (3 rows each) and
//! leaves `level_spacing` IR rows of empty space between consecutive levels
//! for edge routing.  After Y-expansion those IR rows become rendered rows.
//!
//! For level-0 entities that have field rows below their header, those field
//! rows land *inside* that gap.  We therefore choose:
//!
//!   level_spacing  ≥  max_fields_at_level_0  +  2
//!
//! so the record body fits entirely within the gap.  The bottom edge of the
//! record box sits at `rendered_y + 2 + 1 + fields.len = rendered_y + 3 + N`.
//! One extra gap row below that is left free for the edge branch character.
//!
//! For the last level (no further levels below) the field rows extend beyond
//! `plan.height`, so the Buffer2D is allocated taller by `max_last_fields + 1`.
//!
//! ## Z-order painting
//!
//!  Z1  edge routes     — painted first via plan.edge_plans
//!  Z4  header boxes    — overwrites edge markers inside node boundaries
//!  Z5  field rows      — overwrites residual edge chars inside entity boxes
//!
//! The edge chars that pass through the entity interior are replaced by field
//! text; chars in the free gap row(s) between entities remain visible as
//! connectors.
//!
//! Run with: zig build run-terminal-db-diagram

const std = @import("std");
const zigraph = @import("zigraph");
const T = zigraph.terminal;

// ── Entity model ─────────────────────────────────────────────────────────────

const FieldKind = enum { normal, pk, fk };

const Field = struct {
    text: []const u8,
    kind: FieldKind = .normal,
};

const Entity = struct {
    node_id: usize,
    name: []const u8,
    fields: []const Field,
};

// ── Schema: CRM (customers → orders, customers → addresses) ──────────────────

const customers_fields = [_]Field{
    .{ .text = "id: INTEGER", .kind = .pk },
    .{ .text = "name: VARCHAR" },
    .{ .text = "email: TEXT" },
    .{ .text = "phone: VARCHAR" },
};

const orders_fields = [_]Field{
    .{ .text = "id: INTEGER", .kind = .pk },
    .{ .text = "customer_id: INT", .kind = .fk },
    .{ .text = "total: DECIMAL" },
    .{ .text = "status: VARCHAR" },
    .{ .text = "date: DATE" },
};

const addresses_fields = [_]Field{
    .{ .text = "id: INTEGER", .kind = .pk },
    .{ .text = "customer_id: INT", .kind = .fk },
    .{ .text = "street: VARCHAR" },
    .{ .text = "city: VARCHAR" },
    .{ .text = "zip: VARCHAR" },
};

const schema = [_]Entity{
    .{ .node_id = 1, .name = "customers", .fields = &customers_fields },
    .{ .node_id = 2, .name = "orders", .fields = &orders_fields },
    .{ .node_id = 3, .name = "addresses", .fields = &addresses_fields },
};

// ── Color palette ─────────────────────────────────────────────────────────────

const HEADER_BORDER = T.Color{ .rgb = .{ .r = 70, .g = 130, .b = 180 } };
const HEADER_TEXT = T.Color{ .rgb = .{ .r = 255, .g = 255, .b = 255 } };
const EDGE_COLOR = T.Color{ .rgb = .{ .r = 110, .g = 160, .b = 220 } };

const PK_CC = T.CellColor.rgb(255, 215, 0); // gold
const FK_CC = T.CellColor.rgb(100, 220, 140); // mint-green
const FIELD_CC = T.CellColor.rgb(185, 195, 210); // soft-white

fn nodeStyle(_: T.NodeStyleContext) T.TerminalNodeStyle {
    return .{
        .border = .single_box,
        .border_color = HEADER_BORDER,
        .text_color = HEADER_TEXT,
    };
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

    const stdout = std.io.getStdOut().writer();

    try stdout.writeAll(
        \\╔════════════════════════════════════════════════════════════╗
        \\║  Terminal DB Diagram — CRM Schema                          ║
        \\║  customers ──► orders / addresses   (1:N FK relationships) ║
        \\╚════════════════════════════════════════════════════════════╝
        \\
        \\
    );

    // ── Box widths: widen each node to fit its longest field text ─────────────

    var widths: [schema.len]usize = undefined;
    var max_fields_level0: usize = 0; // customers is level 0
    var max_fields_level1: usize = 0; // orders, addresses are level 1

    for (schema, 0..) |e, i| {
        var max_len: usize = e.name.len;
        for (e.fields) |f| {
            if (f.text.len > max_len) max_len = f.text.len;
        }
        widths[i] = max_len + 2; // +2 for │ borders
    }
    // customers (node_id=1) is at level 0; orders and addresses at level 1.
    max_fields_level0 = customers_fields.len; // 4
    for (schema[1..]) |e| {
        if (e.fields.len > max_fields_level1) max_fields_level1 = e.fields.len;
    }

    // ── level_spacing: ensure gap rows fit the level-0 entity fields ─────────
    //
    // After Y-expansion a 3-row header at rendered_y=R occupies rows R, R+1, R+2.
    // sep_y = R+2 (bottom border is overpainting to ├──┤).
    // Field rows: R+3 … R+2+max_fields_level0.
    // Closing border: R+3+max_fields_level0.
    //
    // Level-1 rendered_y = ir_y_level1 + cumulative_extra[1]
    //                    = (1 + eff_spacing) + 2.
    // Required: (1 + eff_spacing + 2) > (R + 3 + max_fields_level0)
    //         → eff_spacing  > max_fields_level0  (with R=0)
    //         → use eff_spacing = max_fields_level0 + 2  (one gap row between)
    //
    const level_spacing: usize = max_fields_level0 + 2; // = 6

    // extra_rows: field rows for level-1 entities extend below plan.height
    const extra_rows: usize = max_fields_level1 + 1; // = 6

    // ── Build graph ───────────────────────────────────────────────────────────

    var g = zigraph.Graph.init(alloc);
    defer g.deinit();

    for (schema, 0..) |e, i| {
        try g.addNode(e.node_id, zigraph.NodeOptions{ .label = e.name, .width = widths[i] });
    }

    // FK relationships: customers → orders, customers → addresses
    try g.addEdge(1, 2);
    try g.addEdge(1, 3);

    // ── Layout ────────────────────────────────────────────────────────────────

    var ir = try zigraph.layout(&g, alloc, .{ .level_spacing = level_spacing });
    defer ir.deinit();

    // ── Render plan ───────────────────────────────────────────────────────────

    const cfg = T.Config{
        .node_style_fn = nodeStyle,
        .edge_style_fn = edgeStyle,
        .color_mode = .truecolor,
    };

    var plan = try T.RenderPlan.build(alloc, &ir, cfg);
    defer plan.deinit();

    // ── Extended buffer ───────────────────────────────────────────────────────

    var buf = try T.Buffer2D.init(alloc, plan.width, plan.height + extra_rows);
    defer buf.deinit(alloc);

    // ── Z1: Paint edges (route lines between levels) ──────────────────────────

    for (plan.edge_plans) |ep| {
        T.paintEdge(&buf, &ep.edge, ep.color, ep.weight, ep.marker_end, ep.marker_start);
    }

    // ── Z4: Paint header boxes (overwrites edge markers inside box footprint) ─

    const nodes = ir.getNodes();
    for (plan.node_plans) |np| {
        const node = &nodes[np.node_index];
        T.paintNode(&buf, node, false, np.style, np.rendered_y, np.level_height);
    }

    // ── Z5: Extend each header into a full record box ─────────────────────────

    const border_cc = T.resolveColorAt(HEADER_BORDER, 0.0);

    for (schema) |entity| {
        const np: T.NodePlan = blk: {
            for (plan.node_plans) |p| {
                if (p.node_id == entity.node_id) break :blk p;
            }
            continue;
        };

        const node = &nodes[np.node_index];
        const w = node.width;

        // Overpaint bottom border corners → T-junction separator (├──┤)
        const sep_y = np.rendered_y + 2;
        buf.set(node.x, sep_y, '├');
        buf.set(node.x + w - 1, sep_y, '┤');

        // Field rows
        for (entity.fields, 0..) |field, fi| {
            const fy = sep_y + 1 + fi;
            buf.setWithColor(node.x, fy, '│', border_cc);

            const fc: T.CellColor = switch (field.kind) {
                .pk => PK_CC,
                .fk => FK_CC,
                .normal => FIELD_CC,
            };

            var lx = node.x + 1;
            for (field.text) |c| {
                if (lx >= node.x + w - 1) break;
                buf.setWithColor(lx, fy, c, fc);
                lx += 1;
            }

            // Explicitly clear remaining inner cells so edge-routing chars
            // that may have been painted through the entity interior earlier
            // (Z1 runs before Z5) don't bleed into the padded area.
            while (lx < node.x + w - 1) : (lx += 1) {
                buf.set(lx, fy, ' ');
            }

            buf.setWithColor(node.x + w - 1, fy, '│', border_cc);
        }

        // Closing bottom border
        const bottom_y = sep_y + 1 + entity.fields.len;
        buf.setWithColor(node.x, bottom_y, '└', border_cc);
        for (1..w - 1) |col| {
            buf.setWithColor(node.x + col, bottom_y, '─', border_cc);
        }
        buf.setWithColor(node.x + w - 1, bottom_y, '┘', border_cc);
    }

    // ── Serialize ─────────────────────────────────────────────────────────────

    try T.serializeBuffer(&buf, stdout, cfg, plan.height + extra_rows);

    // ── Legend ────────────────────────────────────────────────────────────────

    try stdout.writeAll("\n");
    const lw: usize = 46;
    for (0..lw) |_| try stdout.writeByte('-');
    try stdout.writeAll("\n");
    try stdout.writeAll("\x1b[38;2;255;215;0m  [PK]  Primary Key\x1b[0m\n");
    try stdout.writeAll("\x1b[38;2;100;220;140m  [FK]  Foreign Key (→ customers.id)\x1b[0m\n");
    try stdout.writeAll("\x1b[38;2;185;195;210m  [ ]   Regular column\x1b[0m\n");
    for (0..lw) |_| try stdout.writeByte('-');
    try stdout.writeAll("\n");
}
