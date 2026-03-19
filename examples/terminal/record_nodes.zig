//! Record Node Demo — ER-diagram style entity boxes with multiple field rows.
//!
//! Demonstrates the low-level terminal rendering API (Buffer2D, paintNode,
//! RenderPlan) to build nodes that go beyond the standard 3-row header box.
//!
//! The terminal renderer's node model is intentionally minimal: a 1-row or
//! 3-row box whose label is a single string.  Record-style "entity" nodes
//! (like those in ER diagrams) are not built in.  However, because the
//! painting functions and Buffer2D are part of the public API, we can:
//!
//!   1. Build a RenderPlan for the graph's header nodes.
//!   2. Allocate a Buffer2D that is taller than the plan height.
//!   3. Call paintNode normally to get the header boxes.
//!   4. Overpaint the header's bottom-border row to become a ├──┤ separator.
//!   5. Paint field rows (│ field text │) and a closing └──┘ into the
//!      extra rows below.
//!   6. Call serializeBuffer to produce the final terminal output.
//!
//! All entity nodes are placed at the same level (no inter-entity edges in
//! this example) so there is nothing below the header box to conflict with
//! the appended field rows.
//!
//! Run with: zig build run-terminal-record-nodes

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

// ── Color palette ─────────────────────────────────────────────────────────────

/// Steel-blue box border and separator lines.
const BORDER_COLOR = T.Color{ .rgb = .{ .r = 70, .g = 130, .b = 180 } };
/// White entity name in the header.
const LABEL_COLOR = T.Color{ .rgb = .{ .r = 255, .g = 255, .b = 255 } };
/// Gold: primary-key fields.
const PK_COLOR = T.CellColor.rgb(255, 215, 0);
/// Light-green: foreign-key fields.
const FK_COLOR = T.CellColor.rgb(100, 220, 140);
/// Soft white: regular fields.
const FIELD_COLOR = T.CellColor.rgb(185, 195, 210);

fn nodeStyle(_: T.NodeStyleContext) T.TerminalNodeStyle {
    return .{
        .border = .single_box,
        .border_color = BORDER_COLOR,
        .text_color = LABEL_COLOR,
    };
}

// ── Main ──────────────────────────────────────────────────────────────────────

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    std.debug.print(
        \\╔══════════════════════════════════════════════════════════════╗
        \\║  Terminal Record Node Demo                                   ║
        \\║  ER-diagram style entities using low-level Buffer2D API      ║
        \\╚══════════════════════════════════════════════════════════════╝
        \\
        \\
    , .{});

    // ── Entity data ───────────────────────────────────────────────────────────

    const person_fields = [_]Field{
        .{ .text = "id: INTEGER", .kind = .pk },
        .{ .text = "name: VARCHAR" },
        .{ .text = "email: TEXT" },
    };

    const address_fields = [_]Field{
        .{ .text = "id: INTEGER", .kind = .pk },
        .{ .text = "person_id: INT", .kind = .fk },
        .{ .text = "street: VARCHAR" },
        .{ .text = "city: TEXT" },
    };

    const order_fields = [_]Field{
        .{ .text = "id: INTEGER", .kind = .pk },
        .{ .text = "person_id: INT", .kind = .fk },
        .{ .text = "total: DECIMAL" },
        .{ .text = "date: DATE" },
    };

    const entities = [_]Entity{
        .{ .node_id = 1, .name = "Person", .fields = &person_fields },
        .{ .node_id = 2, .name = "Address", .fields = &address_fields },
        .{ .node_id = 3, .name = "Order", .fields = &order_fields },
    };

    // ── Compute box width per entity ──────────────────────────────────────────
    //
    // The node's box width (node.width in the IR) equals label.len + 2.
    // For the record rows to fit, the inner width (box_width - 2) must be >=
    // the longest field text.  Override width via NodeOptions.
    //
    var widths: [entities.len]usize = undefined;
    var max_fields: usize = 0;

    for (entities, 0..) |e, i| {
        var max_field_len: usize = e.name.len;
        for (e.fields) |f| {
            if (f.text.len > max_field_len) max_field_len = f.text.len;
        }
        // box_width = inner_width + 2 (one │ on each side)
        widths[i] = max_field_len + 2;
        if (e.fields.len > max_fields) max_fields = e.fields.len;
    }

    // ── Build graph ───────────────────────────────────────────────────────────
    //
    // No edges between entities: the layout places all nodes at level 0,
    // arranged horizontally.  The rendered buffer therefore has empty rows
    // below the header boxes — exactly where we paint the field rows.
    //
    var g = zigraph.Graph.init(alloc);
    defer g.deinit();

    for (entities, 0..) |e, i| {
        try g.addNode(e.node_id, zigraph.NodeOptions{ .label = e.name, .width = widths[i] });
    }

    // ── Layout ────────────────────────────────────────────────────────────────

    var ir = try zigraph.layout(&g, alloc, .{});
    defer ir.deinit();

    // ── Render plan (header boxes only) ───────────────────────────────────────

    const render_config = T.Config{
        .node_style_fn = nodeStyle,
        .color_mode = .truecolor,
    };

    var plan = try T.RenderPlan.build(alloc, &ir, render_config);
    defer plan.deinit();

    // ── Allocate extended Buffer2D ────────────────────────────────────────────
    //
    // plan.height covers the 3-row header boxes.
    // We add (max_fields + 1) extra rows: one per field plus a closing └──┘.
    //
    const extra_rows = max_fields + 1;
    var buf = try T.Buffer2D.init(alloc, plan.width, plan.height + extra_rows);
    defer buf.deinit(alloc);

    // ── Z4: Paint header boxes ────────────────────────────────────────────────

    const nodes = ir.getNodes();
    for (plan.node_plans) |np| {
        const node = &nodes[np.node_index];
        T.paintNode(&buf, node, false, np.style, np.rendered_y, np.level_height);
    }

    // ── Extend each entity with field rows ────────────────────────────────────

    // Resolved border CellColor for the new rows (solid colour → t=0 suffices).
    const border_cc = T.resolveColorAt(BORDER_COLOR, 0.0);

    for (entities) |entity| {
        // Locate the NodePlan for this entity.
        const np: T.NodePlan = blk: {
            for (plan.node_plans) |p| {
                if (p.node_id == entity.node_id) break :blk p;
            }
            continue; // entity not in graph — skip
        };

        const node = &nodes[np.node_index];
        const w = node.width;

        // paintNode places the bottom border at rendered_y + 2 (for single_box).
        const sep_y = np.rendered_y + 2;

        // ── Step A: overpaint box corners → separator (└──┘ becomes ├──┤) ──
        //
        // buf.set() only changes the glyph, not the color.  The colors from
        // paintNode (steel-blue gradient) are preserved automatically.
        //
        buf.set(node.x, sep_y, '├');
        buf.set(node.x + w - 1, sep_y, '┤');
        // The ─ glyphs in between are unchanged (paintNode already drew them).

        // ── Step B: field rows ─────────────────────────────────────────────
        for (entity.fields, 0..) |field, fi| {
            const fy = sep_y + 1 + fi;

            buf.setWithColor(node.x, fy, '│', border_cc);

            const fc: T.CellColor = switch (field.kind) {
                .pk => PK_COLOR,
                .fk => FK_COLOR,
                .normal => FIELD_COLOR,
            };

            // Write field text left-aligned, 1 cell from the left border.
            var lx = node.x + 1;
            for (field.text) |c| {
                if (lx >= node.x + w - 1) break; // truncate if somehow too wide
                buf.setWithColor(lx, fy, c, fc);
                lx += 1;
            }
            // Explicitly clear remaining inner cells (overwrites any residual
            // edge-routing chars if this pattern is reused with edges).
            while (lx < node.x + w - 1) : (lx += 1) {
                buf.set(lx, fy, ' ');
            }

            buf.setWithColor(node.x + w - 1, fy, '│', border_cc);
        }

        // ── Step C: closing bottom border └──┘ ────────────────────────────
        const bottom_y = sep_y + 1 + entity.fields.len;
        buf.setWithColor(node.x, bottom_y, '└', border_cc);
        for (1..w - 1) |col| {
            buf.setWithColor(node.x + col, bottom_y, '─', border_cc);
        }
        buf.setWithColor(node.x + w - 1, bottom_y, '┘', border_cc);
    }

    // ── Serialize ──────────────────────────────────────────────────────────────

    const stdout = std.io.getStdOut().writer();
    try T.serializeBuffer(&buf, stdout, render_config, plan.height + extra_rows);

    // ── Legend ────────────────────────────────────────────────────────────────

    const legend_width: usize = 36;
    std.debug.print("\n", .{});
    for (0..legend_width) |_| std.debug.print("─", .{});
    std.debug.print("\n", .{});

    // Print legend with ANSI colors matching the field colors
    std.debug.print("\x1b[38;2;255;215;0m  ◆  Primary Key (PK)\x1b[0m\n", .{});
    std.debug.print("\x1b[38;2;100;220;140m  ◇  Foreign Key (FK)\x1b[0m\n", .{});
    std.debug.print("\x1b[38;2;185;195;210m  ·  Regular field\x1b[0m\n", .{});

    for (0..legend_width) |_| std.debug.print("─", .{});
    std.debug.print("\n", .{});

    std.debug.print(
        \\
        \\  Technique: RenderPlan + extended Buffer2D + paintNode +
        \\  serializeBuffer.  Header boxes are painted by paintNode;
        \\  field rows are appended manually to the extra buffer rows.
        \\
    , .{});
}
