//! Edge painting for the terminal renderer.
//!
//! Contains `paintEdge` and the directional draw helpers:
//! `drawDirectVertical`, `drawDirectHorizontal`, `drawDirectManhattan`.

const ir_mod = @import("../../core/ir.zig");
const LayoutEdge = ir_mod.LayoutEdge(usize);
const Buffer2D = @import("buffer.zig").Buffer2D;
const config_mod = @import("config.zig");
const LineWeight = config_mod.LineWeight;
const j = @import("junctions.zig");
const mergeJunction = j.mergeJunction;
const mergeWithDoubleLine = j.mergeWithDoubleLine;
const isSubgraphBorderChar = j.isSubgraphBorderChar;
const CP_V_LINE = j.CP_V_LINE;
const CP_H_LINE = j.CP_H_LINE;
const CP_V_LINE_DASH = j.CP_V_LINE_DASH;
const CP_H_LINE_DASH = j.CP_H_LINE_DASH;
const CP_ARROW_DOWN = j.CP_ARROW_DOWN;
const CP_ARROW_UP = j.CP_ARROW_UP;
const CP_ARROW_RIGHT = j.CP_ARROW_RIGHT;
const CP_ARROW_LEFT = j.CP_ARROW_LEFT;
const CP_ARROW_DOWN_DASH = j.CP_ARROW_DOWN_DASH;
const CP_ARROW_UP_DASH = j.CP_ARROW_UP_DASH;
const CP_ARROW_RIGHT_DASH = j.CP_ARROW_RIGHT_DASH;
const CP_ARROW_LEFT_DASH = j.CP_ARROW_LEFT_DASH;

/// Paint an edge onto the buffer.
/// Color and weight come from the style function; reversed flag from the edge itself.
pub fn paintEdge(buffer: *Buffer2D, edge: *const LayoutEdge, color: u8, weight: LineWeight) void {
    const dashed = weight == .dashed;
    switch (edge.path) {
        .direct => {
            const x0 = edge.from_x;
            const y0 = edge.from_y;
            const x1 = edge.to_x;
            const y1 = edge.to_y;

            if (x0 == x1 and y0 == y1) return; // degenerate

            if (x0 == x1) {
                drawDirectVertical(buffer, x0, y0, y1, color, weight, edge.directed);
            } else if (y0 == y1) {
                drawDirectHorizontal(buffer, y0, x0, x1, color, weight, edge.directed);
            } else {
                drawDirectManhattan(buffer, x0, y0, x1, y1, color, weight, edge.directed, edge.reversed);
            }
        },
        .corner => |corner| {
            paintCornerEdge(buffer, edge, corner.horizontal_y, color, dashed);
        },
        .side_channel => |sc| {
            paintSideChannelEdge(buffer, edge, sc.channel_x, sc.start_y, sc.end_y, color, dashed);
        },
        .multi_segment => {
            paintMultiSegmentEdge(buffer, edge, color, dashed);
        },
        .spline => {
            paintSplineEdge(buffer, edge, color, dashed);
        },
    }
}

// ── Directional draw helpers ────────────────────────────────────────────────

/// Draw a pure-vertical direct edge between y_from and y_to at column x.
/// Dashed weight uses dashed arrow characters (⇣/⇡).
pub fn drawDirectVertical(buffer: *Buffer2D, x: usize, y_from: usize, y_to: usize, color: u8, weight: LineWeight, directed: bool) void {
    if (y_from == y_to) return;
    const lo = @min(y_from, y_to);
    const hi = @max(y_from, y_to);
    const going_down = y_to > y_from;
    const arrow_y = if (going_down) hi - 1 else lo;
    const dashed = weight == .dashed;
    const arrow_char: u21 = if (going_down)
        (if (dashed) CP_ARROW_DOWN_DASH else CP_ARROW_DOWN)
    else
        (if (dashed) CP_ARROW_UP_DASH else CP_ARROW_UP);

    var y = lo;
    while (y < hi) : (y += 1) {
        if (directed and y == arrow_y) {
            buffer.setWithColor(x, y, arrow_char, color);
        } else if (dashed) {
            const cur = buffer.get(x, y);
            if (isSubgraphBorderChar(cur)) {
                buffer.setWithColor(x, y, mergeWithDoubleLine(cur, true, true, false, false), color);
            } else {
                buffer.setWithColor(x, y, CP_V_LINE_DASH, color);
            }
        } else {
            const cur = buffer.get(x, y);
            buffer.setWithColor(x, y, mergeJunction(cur, true, true, false, false), color);
        }
    }
}

/// Draw a pure-horizontal direct edge between x_from and x_to at row y.
/// Dashed weight uses dashed arrow and line characters (⇢/⇠, ┈).
pub fn drawDirectHorizontal(buffer: *Buffer2D, y: usize, x_from: usize, x_to: usize, color: u8, weight: LineWeight, directed: bool) void {
    if (x_from == x_to) return;
    const lo = @min(x_from, x_to);
    const hi = @max(x_from, x_to);
    const going_right = x_to > x_from;
    const arrow_x = if (going_right) hi - 1 else lo;
    const dashed = weight == .dashed;
    const arrow_char: u21 = if (going_right)
        (if (dashed) CP_ARROW_RIGHT_DASH else CP_ARROW_RIGHT)
    else
        (if (dashed) CP_ARROW_LEFT_DASH else CP_ARROW_LEFT);

    var x = lo;
    while (x < hi) : (x += 1) {
        if (directed and x == arrow_x) {
            buffer.setWithColor(x, y, arrow_char, color);
        } else if (dashed) {
            const cur = buffer.get(x, y);
            if (isSubgraphBorderChar(cur)) {
                buffer.setWithColor(x, y, mergeWithDoubleLine(cur, false, false, true, true), color);
            } else {
                buffer.setWithColor(x, y, CP_H_LINE_DASH, color);
            }
        } else {
            const cur = buffer.get(x, y);
            buffer.setWithColor(x, y, mergeJunction(cur, false, false, true, true), color);
        }
    }
}

/// Draw a Manhattan Z-shaped route between (x0,y0) and (x1,y1).
/// Route: (x0,y0) → (x0,mid_y) → (x1,mid_y) → (x1,y1)
pub fn drawDirectManhattan(buffer: *Buffer2D, x0: usize, y0: usize, x1: usize, y1: usize, color: u8, weight: LineWeight, directed: bool, reversed: bool) void {
    const lo_y = @min(y0, y1);
    const hi_y = @max(y0, y1);
    const mid_y = lo_y + (hi_y - lo_y) / 2;
    const dashed = weight == .dashed;

    // --- Segment 1: vertical at x0 between y0 and mid_y (exclusive of both) ---
    drawVerticalSegment(buffer, x0, @min(y0, mid_y), @max(y0, mid_y), color, dashed);

    // --- Corner 1 at (x0, mid_y) ---
    {
        const cur = buffer.get(x0, mid_y);
        buffer.setWithColor(x0, mid_y, mergeJunction(cur, y0 < mid_y, y0 > mid_y, x1 > x0, x1 < x0), color);
    }

    // --- Segment 2: horizontal at mid_y (exclusive of x0 and x1) ---
    {
        const lo_x = @min(x0, x1);
        const hi_x = @max(x0, x1);
        if (hi_x > lo_x + 1) {
            var x = lo_x + 1;
            while (x < hi_x) : (x += 1) {
                if (dashed) {
                    const cur = buffer.get(x, mid_y);
                    if (isSubgraphBorderChar(cur)) {
                        buffer.setWithColor(x, mid_y, mergeWithDoubleLine(cur, false, false, true, true), color);
                    } else {
                        buffer.setWithColor(x, mid_y, CP_H_LINE_DASH, color);
                    }
                } else {
                    const cur = buffer.get(x, mid_y);
                    buffer.setWithColor(x, mid_y, mergeJunction(cur, false, false, true, true), color);
                }
            }
        }
    }

    // --- Corner 2 at (x1, mid_y) ---
    {
        const cur = buffer.get(x1, mid_y);
        buffer.setWithColor(x1, mid_y, mergeJunction(cur, y1 < mid_y, y1 > mid_y, x0 > x1, x0 < x1), color);
    }

    // --- Segment 3: vertical at x1 between mid_y and y1 (exclusive of both) ---
    drawVerticalSegment(buffer, x1, @min(mid_y, y1), @max(mid_y, y1), color, dashed);

    // --- Arrow ---
    if (directed) {
        drawManhattanArrow(buffer, x0, y0, x1, y1, mid_y, color, dashed, reversed);
    }
}

// ── Private path-type helpers ───────────────────────────────────────────────

fn paintCornerEdge(buffer: *Buffer2D, edge: *const LayoutEdge, h_y: usize, color: u8, dashed: bool) void {
    const x1 = edge.from_x;
    const x2 = edge.to_x;
    const min_x = @min(x1, x2);
    const max_x = @max(x1, x2);

    // Vertical from source to horizontal
    var y = edge.from_y;
    while (y < h_y) : (y += 1) {
        if (edge.reversed and edge.directed and y == edge.from_y) {
            buffer.setWithColor(x1, y, if (dashed) CP_ARROW_UP_DASH else CP_ARROW_UP, color);
        } else if (dashed) {
            const current = buffer.get(x1, y);
            if (isSubgraphBorderChar(current)) {
                buffer.setWithColor(x1, y, mergeWithDoubleLine(current, true, true, false, false), color);
            } else {
                buffer.setWithColor(x1, y, CP_V_LINE_DASH, color);
            }
        } else {
            const current = buffer.get(x1, y);
            buffer.setWithColor(x1, y, mergeJunction(current, true, true, false, false), color);
        }
    }

    // Horizontal segment
    var x = min_x;
    while (x <= max_x) : (x += 1) {
        if (x != x1 and x != x2) {
            if (dashed) {
                const current = buffer.get(x, h_y);
                if (isSubgraphBorderChar(current)) {
                    buffer.setWithColor(x, h_y, mergeWithDoubleLine(current, false, false, true, true), color);
                } else {
                    buffer.setWithColor(x, h_y, CP_H_LINE_DASH, color);
                }
            } else {
                const current = buffer.get(x, h_y);
                buffer.setWithColor(x, h_y, mergeJunction(current, false, false, true, true), color);
            }
        }
    }

    // Junction at source x
    const current1 = buffer.get(x1, h_y);
    buffer.setWithColor(x1, h_y, mergeJunction(current1, true, false, x1 < x2, x1 > x2), color);

    // Corner at target x
    const current2 = buffer.get(x2, h_y);
    buffer.setWithColor(x2, h_y, mergeJunction(current2, false, true, x1 > x2, x1 < x2), color);

    // Vertical from horizontal to target
    y = h_y + 1;
    while (y < edge.to_y) : (y += 1) {
        if (!edge.reversed and edge.directed and y == edge.to_y - 1) {
            buffer.setWithColor(x2, y, if (dashed) CP_ARROW_DOWN_DASH else CP_ARROW_DOWN, color);
        } else if (dashed) {
            const current = buffer.get(x2, y);
            if (isSubgraphBorderChar(current)) {
                buffer.setWithColor(x2, y, mergeWithDoubleLine(current, true, true, false, false), color);
            } else {
                buffer.setWithColor(x2, y, CP_V_LINE_DASH, color);
            }
        } else {
            const current = buffer.get(x2, y);
            buffer.setWithColor(x2, y, mergeJunction(current, true, true, false, false), color);
        }
    }
}

fn paintSideChannelEdge(buffer: *Buffer2D, edge: *const LayoutEdge, ch_x: usize, start_y: usize, end_y: usize, color: u8, dashed: bool) void {
    const x1 = edge.from_x;
    const x2 = edge.to_x;

    // Vertical from source to start_y
    var y = edge.from_y + 1;
    const first_vert_start = edge.from_y + 1;
    while (y < start_y) : (y += 1) {
        if (edge.reversed and edge.directed and y == first_vert_start) {
            buffer.setWithColor(x1, y, if (dashed) CP_ARROW_UP_DASH else CP_ARROW_UP, color);
        } else if (dashed) {
            const current = buffer.get(x1, y);
            if (isSubgraphBorderChar(current)) {
                buffer.setWithColor(x1, y, mergeWithDoubleLine(current, true, true, false, false), color);
            } else {
                buffer.setWithColor(x1, y, CP_V_LINE_DASH, color);
            }
        } else {
            const current = buffer.get(x1, y);
            buffer.setWithColor(x1, y, mergeJunction(current, true, true, false, false), color);
        }
    }

    // Horizontal at start_y
    {
        const min_x1 = @min(x1, ch_x);
        const max_x1 = @max(x1, ch_x);
        var x = min_x1;
        while (x <= max_x1) : (x += 1) {
            if (dashed) {
                const current = buffer.get(x, start_y);
                if (isSubgraphBorderChar(current)) {
                    buffer.setWithColor(x, start_y, mergeWithDoubleLine(current, false, false, true, true), color);
                } else {
                    buffer.setWithColor(x, start_y, CP_H_LINE_DASH, color);
                }
            } else {
                const current = buffer.get(x, start_y);
                buffer.setWithColor(x, start_y, mergeJunction(current, false, false, true, true), color);
            }
        }
    }

    // Vertical in channel
    y = start_y + 1;
    while (y < end_y) : (y += 1) {
        if (dashed) {
            const current = buffer.get(ch_x, y);
            if (isSubgraphBorderChar(current)) {
                buffer.setWithColor(ch_x, y, mergeWithDoubleLine(current, true, true, false, false), color);
            } else {
                buffer.setWithColor(ch_x, y, CP_V_LINE_DASH, color);
            }
        } else {
            const current = buffer.get(ch_x, y);
            buffer.setWithColor(ch_x, y, mergeJunction(current, true, true, false, false), color);
        }
    }

    // Horizontal at end_y
    {
        const min_x2 = @min(ch_x, x2);
        const max_x2 = @max(ch_x, x2);
        var x = min_x2;
        while (x <= max_x2) : (x += 1) {
            if (dashed) {
                const current = buffer.get(x, end_y);
                if (isSubgraphBorderChar(current)) {
                    buffer.setWithColor(x, end_y, mergeWithDoubleLine(current, false, false, true, true), color);
                } else {
                    buffer.setWithColor(x, end_y, CP_H_LINE_DASH, color);
                }
            } else {
                const current = buffer.get(x, end_y);
                buffer.setWithColor(x, end_y, mergeJunction(current, false, false, true, true), color);
            }
        }
    }

    // Vertical from end_y to target
    y = end_y + 1;
    while (y < edge.to_y) : (y += 1) {
        if (!edge.reversed and edge.directed and y == edge.to_y - 1) {
            buffer.setWithColor(x2, y, if (dashed) CP_ARROW_DOWN_DASH else CP_ARROW_DOWN, color);
        } else if (dashed) {
            const current = buffer.get(x2, y);
            if (isSubgraphBorderChar(current)) {
                buffer.setWithColor(x2, y, mergeWithDoubleLine(current, true, true, false, false), color);
            } else {
                buffer.setWithColor(x2, y, CP_V_LINE_DASH, color);
            }
        } else {
            const current = buffer.get(x2, y);
            buffer.setWithColor(x2, y, mergeJunction(current, true, true, false, false), color);
        }
    }
}

fn paintMultiSegmentEdge(buffer: *Buffer2D, edge: *const LayoutEdge, color: u8, dashed: bool) void {
    const x1 = edge.from_x;
    const x2 = edge.to_x;
    const h_y = edge.from_y + 1;
    const min_x = @min(x1, x2);
    const max_x = @max(x1, x2);

    // Vertical from source to horizontal
    var y = edge.from_y;
    while (y < h_y) : (y += 1) {
        if (edge.reversed and edge.directed and y == edge.from_y) {
            buffer.setWithColor(x1, y, if (dashed) CP_ARROW_UP_DASH else CP_ARROW_UP, color);
        } else if (dashed) {
            const current = buffer.get(x1, y);
            if (isSubgraphBorderChar(current)) {
                buffer.setWithColor(x1, y, mergeWithDoubleLine(current, true, true, false, false), color);
            } else {
                buffer.setWithColor(x1, y, CP_V_LINE_DASH, color);
            }
        } else {
            const current = buffer.get(x1, y);
            buffer.setWithColor(x1, y, mergeJunction(current, true, true, false, false), color);
        }
    }

    // Horizontal segment (fill spaces and cross subgraph borders)
    var x = min_x;
    while (x <= max_x) : (x += 1) {
        if (x != x1 and x != x2) {
            const current = buffer.get(x, h_y);
            if (isSubgraphBorderChar(current)) {
                buffer.setWithColor(x, h_y, mergeJunction(current, false, false, true, true), color);
            } else if (current == ' ') {
                if (dashed) {
                    buffer.setWithColor(x, h_y, CP_H_LINE_DASH, color);
                } else {
                    buffer.setWithColor(x, h_y, CP_H_LINE, color);
                }
            }
        }
    }

    // Junction at source x
    const current1 = buffer.get(x1, h_y);
    buffer.setWithColor(x1, h_y, mergeJunction(current1, true, false, x1 < x2, x1 > x2), color);

    // Corner at target x
    const current2 = buffer.get(x2, h_y);
    buffer.setWithColor(x2, h_y, mergeJunction(current2, false, true, x1 > x2, x1 < x2), color);

    // Vertical from horizontal to target
    y = h_y + 1;
    while (y < edge.to_y) : (y += 1) {
        if (!edge.reversed and edge.directed and y == edge.to_y - 1) {
            buffer.setWithColor(x2, y, if (dashed) CP_ARROW_DOWN_DASH else CP_ARROW_DOWN, color);
        } else if (dashed) {
            const current = buffer.get(x2, y);
            if (isSubgraphBorderChar(current)) {
                buffer.setWithColor(x2, y, mergeWithDoubleLine(current, true, true, false, false), color);
            } else {
                buffer.setWithColor(x2, y, CP_V_LINE_DASH, color);
            }
        } else {
            const current = buffer.get(x2, y);
            buffer.setWithColor(x2, y, mergeJunction(current, true, true, false, false), color);
        }
    }
}

fn paintSplineEdge(buffer: *Buffer2D, edge: *const LayoutEdge, color: u8, dashed: bool) void {
    const x = edge.from_x;
    var y = edge.from_y;
    while (y < edge.to_y) : (y += 1) {
        if (edge.reversed and edge.directed and y == edge.from_y) {
            buffer.setWithColor(x, y, if (dashed) CP_ARROW_UP_DASH else CP_ARROW_UP, color);
        } else if (!edge.reversed and edge.directed and y == edge.to_y - 1) {
            buffer.setWithColor(x, y, if (dashed) CP_ARROW_DOWN_DASH else CP_ARROW_DOWN, color);
        } else if (dashed) {
            buffer.setWithColor(x, y, CP_V_LINE_DASH, color);
        } else {
            const current = buffer.get(x, y);
            buffer.setWithColor(x, y, mergeJunction(current, true, true, false, false), color);
        }
    }
    // Handle horizontal offset with corner if needed
    if (edge.from_x != edge.to_x) {
        const min_x = @min(edge.from_x, edge.to_x);
        const max_x = @max(edge.from_x, edge.to_x);
        const mid_y = edge.from_y + (edge.to_y - edge.from_y) / 2;
        var hx = min_x;
        while (hx <= max_x) : (hx += 1) {
            if (buffer.get(hx, mid_y) == ' ') {
                buffer.setWithColor(hx, mid_y, CP_H_LINE, color);
            }
        }
    }
}

// ── Shared internal helpers ─────────────────────────────────────────────────

/// Draw a vertical segment between (x, lo+1) and (x, hi-1) — exclusive of both endpoints.
fn drawVerticalSegment(buffer: *Buffer2D, x: usize, lo: usize, hi: usize, color: u8, dashed: bool) void {
    if (hi > lo + 1) {
        var y = lo + 1;
        while (y < hi) : (y += 1) {
            if (dashed) {
                const cur = buffer.get(x, y);
                if (isSubgraphBorderChar(cur)) {
                    buffer.setWithColor(x, y, mergeWithDoubleLine(cur, true, true, false, false), color);
                } else {
                    buffer.setWithColor(x, y, CP_V_LINE_DASH, color);
                }
            } else {
                const cur = buffer.get(x, y);
                buffer.setWithColor(x, y, mergeJunction(cur, true, true, false, false), color);
            }
        }
    }
}

/// Draw the arrow for a Manhattan route.
fn drawManhattanArrow(buffer: *Buffer2D, x0: usize, y0: usize, x1: usize, y1: usize, mid_y: usize, color: u8, dashed: bool, reversed: bool) void {
    if (reversed) {
        // Reversed: arrow at FROM end (y0) pointing upward
        if (y0 != mid_y) {
            const going_up_s1 = y0 < mid_y;
            if (going_up_s1) {
                buffer.setWithColor(x0, y0, if (dashed) CP_ARROW_UP_DASH else CP_ARROW_UP, color);
            } else {
                buffer.setWithColor(x0, y0, if (dashed) CP_ARROW_DOWN_DASH else CP_ARROW_DOWN, color);
            }
        } else {
            const going_right = x1 > x0;
            if (going_right) {
                buffer.setWithColor(x0, y0, if (dashed) CP_ARROW_LEFT_DASH else CP_ARROW_LEFT, color);
            } else {
                buffer.setWithColor(x0, y0, if (dashed) CP_ARROW_RIGHT_DASH else CP_ARROW_RIGHT, color);
            }
        }
    } else {
        // Normal: arrow one cell before target at TO end
        if (y1 != mid_y) {
            const going_down_s3 = y1 > mid_y;
            const arrow_y = if (going_down_s3) y1 - 1 else y1 + 1;
            const arrow_char: u21 = if (going_down_s3) CP_ARROW_DOWN else CP_ARROW_UP;
            buffer.setWithColor(x1, arrow_y, arrow_char, color);
        } else {
            const going_right = x1 > x0;
            const arrow_x = if (going_right) x1 - 1 else x1 + 1;
            const arrow_char: u21 = if (going_right) CP_ARROW_RIGHT else CP_ARROW_LEFT;
            if (arrow_x < buffer.width) {
                buffer.setWithColor(arrow_x, y1, arrow_char, color);
            }
        }
    }
}
