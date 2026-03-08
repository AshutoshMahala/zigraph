//! Node painting for the terminal renderer.

const ir_mod = @import("../../core/ir.zig");
const LayoutNode = ir_mod.LayoutNode(usize);
const Buffer2D = @import("buffer.zig").Buffer2D;
const config_mod = @import("config.zig");
const TerminalNodeStyle = config_mod.TerminalNodeStyle;

/// Paint a node onto the buffer.
/// Uses the style's border field for bracket/box selection.
/// Dummy nodes bypass the style system — they're layout artifacts.
pub fn paintNode(buffer: *Buffer2D, node: *const LayoutNode, show_dummy_nodes: bool, style: TerminalNodeStyle) void {
    const y = node.y;
    var x = node.x;

    // Dummy nodes: show as '◍' if debugging, skip if not
    if (node.kind == .dummy) {
        if (show_dummy_nodes) {
            for (node.label) |c| {
                buffer.set(x, y, c);
                x += 1;
            }
        }
        return;
    }

    // 1-row borders
    switch (style.border) {
        .bracket => {
            buffer.set(x, y, '[');
            x += 1;
            for (node.label) |c| {
                buffer.set(x, y, c);
                x += 1;
            }
            buffer.set(x, y, ']');
        },
        .angle => {
            buffer.set(x, y, '<');
            x += 1;
            for (node.label) |c| {
                buffer.set(x, y, c);
                x += 1;
            }
            buffer.set(x, y, '>');
        },
        .none => {
            for (node.label) |c| {
                buffer.set(x, y, c);
                x += 1;
            }
        },
        // 3-row variants — deferred (requires Y-expansion infrastructure)
        // For now, fall back to bracket for explicit, angle for implicit
        .single_box, .heavy_box, .double_box, .rounded_box, .open_box => {
            const open: u21 = if (node.kind == .implicit) '<' else '[';
            const close: u21 = if (node.kind == .implicit) '>' else ']';
            buffer.set(x, y, open);
            x += 1;
            for (node.label) |c| {
                buffer.set(x, y, c);
                x += 1;
            }
            buffer.set(x, y, close);
        },
    }
}
