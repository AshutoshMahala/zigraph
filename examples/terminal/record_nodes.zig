//! Record Node Demo — ER-diagram style entity boxes via paint_fn.
//!
//! Demonstrates how `paint_fn` on `TerminalNodeStyle` replaces the old
//! low-level Buffer2D workflow.  Each entity declares its fields up front;
//! dimensions are auto-computed, and the layout engine routes edges around
//! the full node height.  No manual RenderPlan or Buffer2D needed.
//!
//! Run with: zig build run-terminal-record-nodes

const std = @import("std");
const zigraph = @import("zigraph");
const T = zigraph.terminal;

// ── Entity model ─────────────────────────────────────────────────────────────

pub const FieldKind = enum { normal, pk, fk };

pub const Field = struct {
    text: []const u8,
    kind: FieldKind = .normal,
};

pub const Entity = struct {
    name: []const u8,
    fields: []const Field,

    /// Box width: longest content line + 2 border columns.
    pub fn boxWidth(self: Entity) usize {
        var max_len: usize = self.name.len;
        for (self.fields) |f| {
            if (f.text.len > max_len) max_len = f.text.len;
        }
        return max_len + 2;
    }

    /// Box height: top border + header + separator + fields + bottom border.
    pub fn boxHeight(self: Entity) usize {
        return 4 + self.fields.len;
    }

    pub fn nodeOptions(self: Entity) zigraph.NodeOptions {
        return .{
            .label = self.name,
            .width = self.boxWidth(),
            .height = self.boxHeight(),
        };
    }

    /// Paint the entity record box into a Buffer2D.
    pub fn paint(self: Entity, buf: *T.Buffer2D, ctx: T.NodePaintContext) void {
        const x = ctx.x;
        const w = ctx.width;
        const inner = if (w >= 2) w - 2 else 0;
        var row = ctx.y;

        // Top border
        buf.setWithColor(x, row, 0x250C, BORDER_CC); // ┌
        for (1..w - 1) |c| buf.setWithColor(x + c, row, 0x2500, BORDER_CC); // ─
        buf.setWithColor(x + w - 1, row, 0x2510, BORDER_CC); // ┐
        row += 1;

        // Header row (centered label)
        buf.setWithColor(x, row, 0x2502, BORDER_CC); // │
        const pad = if (inner > self.name.len) (inner - self.name.len) / 2 else 0;
        var col: usize = 0;
        while (col < pad) : (col += 1) buf.set(x + 1 + col, row, ' ');
        for (self.name) |c| {
            buf.setWithColor(x + 1 + col, row, c, LABEL_CC);
            col += 1;
        }
        while (col < inner) : (col += 1) buf.set(x + 1 + col, row, ' ');
        buf.setWithColor(x + w - 1, row, 0x2502, BORDER_CC); // │
        row += 1;

        // Separator
        buf.setWithColor(x, row, 0x251C, BORDER_CC); // ├
        for (1..w - 1) |c| buf.setWithColor(x + c, row, 0x2500, BORDER_CC); // ─
        buf.setWithColor(x + w - 1, row, 0x2524, BORDER_CC); // ┤
        row += 1;

        // Field rows
        for (self.fields) |field| {
            buf.setWithColor(x, row, 0x2502, BORDER_CC); // │

            const fc: T.CellColor = switch (field.kind) {
                .pk => PK_CC,
                .fk => FK_CC,
                .normal => FIELD_CC,
            };

            col = 0;
            for (field.text) |c| {
                if (col >= inner) break;
                buf.setWithColor(x + 1 + col, row, c, fc);
                col += 1;
            }
            while (col < inner) : (col += 1) buf.set(x + 1 + col, row, ' ');
            buf.setWithColor(x + w - 1, row, 0x2502, BORDER_CC); // │
            row += 1;
        }

        // Bottom border
        buf.setWithColor(x, row, 0x2514, BORDER_CC); // └
        for (1..w - 1) |c| buf.setWithColor(x + c, row, 0x2500, BORDER_CC); // ─
        buf.setWithColor(x + w - 1, row, 0x2518, BORDER_CC); // ┘
    }
};

// ── Color palette ─────────────────────────────────────────────────────────────

pub const BORDER_CC = T.CellColor.rgb(70, 130, 180); // steel-blue
pub const LABEL_CC = T.CellColor.rgb(255, 255, 255); // white
pub const PK_CC = T.CellColor.rgb(255, 215, 0); // gold
pub const FK_CC = T.CellColor.rgb(100, 220, 140); // mint-green
pub const FIELD_CC = T.CellColor.rgb(185, 195, 210); // soft-white

// ── Entity data ───────────────────────────────────────────────────────────────

const person = Entity{
    .name = "Person",
    .fields = &.{
        .{ .text = "id: INTEGER", .kind = .pk },
        .{ .text = "name: VARCHAR" },
        .{ .text = "email: TEXT" },
    },
};

const address = Entity{
    .name = "Address",
    .fields = &.{
        .{ .text = "id: INTEGER", .kind = .pk },
        .{ .text = "person_id: INT", .kind = .fk },
        .{ .text = "street: VARCHAR" },
        .{ .text = "city: TEXT" },
    },
};

const order = Entity{
    .name = "Order",
    .fields = &.{
        .{ .text = "id: INTEGER", .kind = .pk },
        .{ .text = "person_id: INT", .kind = .fk },
        .{ .text = "total: DECIMAL" },
        .{ .text = "date: DATE" },
    },
};

// ── Paint function wrappers (one per entity, file-scope comptime data) ────────

fn paintPerson(buf: *T.Buffer2D, ctx: T.NodePaintContext) void {
    person.paint(buf, ctx);
}
fn paintAddress(buf: *T.Buffer2D, ctx: T.NodePaintContext) void {
    address.paint(buf, ctx);
}
fn paintOrder(buf: *T.Buffer2D, ctx: T.NodePaintContext) void {
    order.paint(buf, ctx);
}

fn nodeStyle(ctx: T.NodeStyleContext) T.TerminalNodeStyle {
    if (std.mem.eql(u8, ctx.label, "Person"))
        return .{ .border = .none, .paint_fn = &paintPerson };
    if (std.mem.eql(u8, ctx.label, "Address"))
        return .{ .border = .none, .paint_fn = &paintAddress };
    if (std.mem.eql(u8, ctx.label, "Order"))
        return .{ .border = .none, .paint_fn = &paintOrder };
    return .{ .border = .single_box };
}

// ── Main ──────────────────────────────────────────────────────────────────────

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    std.debug.print(
        \\
        \\Terminal Record Node Demo
        \\===========================
        \\ER-diagram style entities using paint_fn + auto dimensions
        \\
        \\
    , .{});

    // ── Build graph (dimensions auto-computed from entity data) ────────────────

    var g = zigraph.Graph.init(alloc);
    defer g.deinit();

    try g.addNode(1, person.nodeOptions());
    try g.addNode(2, address.nodeOptions());
    try g.addNode(3, order.nodeOptions());

    // ── Layout ────────────────────────────────────────────────────────────────

    var ir = try zigraph.layout(&g, alloc, .{});
    defer ir.deinit();

    // ── Render (one call) ─────────────────────────────────────────────────────

    const output = try T.renderWithConfig(&ir, alloc, .{
        .node_style_fn = &nodeStyle,
        .color_mode = .truecolor,
    });
    defer alloc.free(output);

    std.debug.print("{s}\n", .{output});

    // ── Legend ────────────────────────────────────────────────────────────────

    const legend_width: usize = 36;
    for (0..legend_width) |_| std.debug.print("\xe2\x94\x80", .{});
    std.debug.print("\n", .{});
    std.debug.print("\x1b[38;2;255;215;0m  \xe2\x97\x86  Primary Key (PK)\x1b[0m\n", .{});
    std.debug.print("\x1b[38;2;100;220;140m  \xe2\x97\x87  Foreign Key (FK)\x1b[0m\n", .{});
    std.debug.print("\x1b[38;2;185;195;210m  \xc2\xb7  Regular field\x1b[0m\n", .{});
    for (0..legend_width) |_| std.debug.print("\xe2\x94\x80", .{});
    std.debug.print("\n", .{});
}
