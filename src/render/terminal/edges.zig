//! Edge painting for the terminal renderer.
//!
//! Contains `paintEdge` and the directional draw helpers:
//! `drawDirectVertical`, `drawDirectHorizontal`, `drawDirectManhattan`.
//!
//! All painting functions are weight-aware: they produce light (─│), heavy (━┃),
//! double (═║), or dashed (┈┊) characters and correctly merge junctions when
//! edges of different weights cross.

const ir_mod = @import("../../core/ir.zig");
const LayoutEdge = ir_mod.LayoutEdge(usize);
const Buffer2D = @import("buffer.zig").Buffer2D;
const config_mod = @import("config.zig");
const LineWeight = config_mod.LineWeight;
const MarkerShape = config_mod.MarkerShape;
const CellColor = config_mod.CellColor;
const j = @import("junctions.zig");
const mergeJunctionWeighted = j.mergeJunctionWeighted;
const ArmWeight = j.ArmWeight;
const DirWeights = j.DirWeights;
const Direction = j.Direction;
const markerChar = j.markerChar;

/// Paint an edge onto the buffer.
/// Color, weight, and markers come from the style function.
pub fn paintEdge(buffer: *Buffer2D, edge: *const LayoutEdge, color: CellColor, weight: LineWeight, marker_end: MarkerShape, marker_start: MarkerShape) void {
    const arm = ArmWeight.fromLineWeight(weight);
    switch (edge.path) {
        .direct => {
            const x0 = edge.from_x;
            const y0 = edge.from_y;
            const x1 = edge.to_x;
            const y1 = edge.to_y;

            if (x0 == x1 and y0 == y1) return; // degenerate

            if (x0 == x1) {
                drawDirectVertical(buffer, x0, y0, y1, color, weight, edge.directed, marker_end);
            } else if (y0 == y1) {
                drawDirectHorizontal(buffer, y0, x0, x1, color, weight, edge.directed, marker_end);
            } else {
                drawDirectManhattan(buffer, x0, y0, x1, y1, color, weight, edge.directed, edge.reversed, marker_end, marker_start);
            }
        },
        .corner => |corner| {
            paintCornerEdge(buffer, edge, corner.horizontal_y, color, arm, marker_end, marker_start);
        },
        .side_channel => |sc| {
            paintSideChannelEdge(buffer, edge, sc.channel_x, sc.start_y, sc.end_y, color, arm, marker_end, marker_start);
        },
        .multi_segment => {
            paintMultiSegmentEdge(buffer, edge, color, arm, marker_end, marker_start);
        },
        .spline => {
            paintSplineEdge(buffer, edge, color, arm, marker_end, marker_start);
        },
    }
}

// ── Directional draw helpers ────────────────────────────────────────────────

/// Draw a pure-vertical direct edge between y_from and y_to at column x.
pub fn drawDirectVertical(buffer: *Buffer2D, x: usize, y_from: usize, y_to: usize, color: CellColor, weight: LineWeight, directed: bool, marker_end: MarkerShape) void {
    if (y_from == y_to) return;
    const lo = @min(y_from, y_to);
    const hi = @max(y_from, y_to);
    const going_down = y_to > y_from;
    const arrow_y = if (going_down) hi - 1 else lo;
    const arm = ArmWeight.fromLineWeight(weight);
    const arrow_ch: ?u21 = if (directed)
        markerChar(marker_end, if (going_down) .down else .up)
    else
        null;

    var y = lo;
    while (y < hi) : (y += 1) {
        if (arrow_ch != null and y == arrow_y) {
            buffer.setWithColor(x, y, arrow_ch.?, color);
        } else {
            drawLineCell(buffer, x, y, true, color, arm);
        }
    }
}

/// Draw a pure-horizontal direct edge between x_from and x_to at row y.
pub fn drawDirectHorizontal(buffer: *Buffer2D, y: usize, x_from: usize, x_to: usize, color: CellColor, weight: LineWeight, directed: bool, marker_end: MarkerShape) void {
    if (x_from == x_to) return;
    const lo = @min(x_from, x_to);
    const hi = @max(x_from, x_to);
    const going_right = x_to > x_from;
    const arrow_x = if (going_right) hi - 1 else lo;
    const arm = ArmWeight.fromLineWeight(weight);
    const arrow_ch: ?u21 = if (directed)
        markerChar(marker_end, if (going_right) .right else .left)
    else
        null;

    var x = lo;
    while (x < hi) : (x += 1) {
        if (arrow_ch != null and x == arrow_x) {
            buffer.setWithColor(x, y, arrow_ch.?, color);
        } else {
            drawLineCell(buffer, x, y, false, color, arm);
        }
    }
}

/// Draw a Manhattan Z-shaped route between (x0,y0) and (x1,y1).
/// Route: (x0,y0) → (x0,mid_y) → (x1,mid_y) → (x1,y1)
pub fn drawDirectManhattan(buffer: *Buffer2D, x0: usize, y0: usize, x1: usize, y1: usize, color: CellColor, weight: LineWeight, directed: bool, reversed: bool, marker_end: MarkerShape, marker_start: MarkerShape) void {
    const lo_y = @min(y0, y1);
    const hi_y = @max(y0, y1);
    const mid_y = lo_y + (hi_y - lo_y) / 2;
    const arm = ArmWeight.fromLineWeight(weight);

    // --- Segment 1: vertical at x0 between y0 and mid_y (exclusive of both) ---
    drawVerticalSegment(buffer, x0, @min(y0, mid_y), @max(y0, mid_y), color, arm);

    // --- Corner 1 at (x0, mid_y) ---
    {
        const cur = buffer.get(x0, mid_y);
        buffer.setWithColor(x0, mid_y, mergeJunctionWeighted(cur, .{
            .up = if (y0 < mid_y) arm else .none,
            .down = if (y0 > mid_y) arm else .none,
            .right = if (x1 > x0) arm else .none,
            .left = if (x1 < x0) arm else .none,
        }), color);
    }

    // --- Segment 2: horizontal at mid_y (exclusive of x0 and x1) ---
    {
        const lo_x = @min(x0, x1);
        const hi_x = @max(x0, x1);
        if (hi_x > lo_x + 1) {
            var x = lo_x + 1;
            while (x < hi_x) : (x += 1) {
                drawLineCell(buffer, x, mid_y, false, color, arm);
            }
        }
    }

    // --- Corner 2 at (x1, mid_y) ---
    {
        const cur = buffer.get(x1, mid_y);
        buffer.setWithColor(x1, mid_y, mergeJunctionWeighted(cur, .{
            .up = if (y1 < mid_y) arm else .none,
            .down = if (y1 > mid_y) arm else .none,
            .right = if (x0 > x1) arm else .none,
            .left = if (x0 < x1) arm else .none,
        }), color);
    }

    // --- Segment 3: vertical at x1 between mid_y and y1 (exclusive of both) ---
    drawVerticalSegment(buffer, x1, @min(mid_y, y1), @max(mid_y, y1), color, arm);

    // --- Arrow ---
    if (directed) {
        drawManhattanArrow(buffer, x0, y0, x1, y1, mid_y, color, reversed, marker_end, marker_start);
    }
}

// ── Private path-type helpers ───────────────────────────────────────────────

fn paintCornerEdge(buffer: *Buffer2D, edge: *const LayoutEdge, h_y: usize, color: CellColor, arm: ArmWeight, marker_end: MarkerShape, marker_start: MarkerShape) void {
    const x1 = edge.from_x;
    const x2 = edge.to_x;
    const min_x = @min(x1, x2);
    const max_x = @max(x1, x2);

    // Vertical from source to horizontal
    // Assumes top-down layout: reversed marker points upward.
    var y = edge.from_y;
    while (y < h_y) : (y += 1) {
        if (edge.reversed and edge.directed and y == edge.from_y) {
            if (markerChar(marker_start, .up)) |ch| {
                buffer.setWithColor(x1, y, ch, color);
            } else {
                drawLineCell(buffer, x1, y, true, color, arm);
            }
        } else {
            drawLineCell(buffer, x1, y, true, color, arm);
        }
    }

    // Horizontal segment
    var x = min_x;
    while (x <= max_x) : (x += 1) {
        if (x != x1 and x != x2) {
            drawLineCell(buffer, x, h_y, false, color, arm);
        }
    }

    // Junction at source x
    const current1 = buffer.get(x1, h_y);
    buffer.setWithColor(x1, h_y, mergeJunctionWeighted(current1, .{
        .up = arm,
        .right = if (x1 < x2) arm else .none,
        .left = if (x1 > x2) arm else .none,
    }), color);

    // Corner at target x
    const current2 = buffer.get(x2, h_y);
    buffer.setWithColor(x2, h_y, mergeJunctionWeighted(current2, .{
        .down = arm,
        .right = if (x1 > x2) arm else .none,
        .left = if (x1 < x2) arm else .none,
    }), color);

    // Vertical from horizontal to target
    y = h_y + 1;
    while (y < edge.to_y) : (y += 1) {
        if (!edge.reversed and edge.directed and y == edge.to_y - 1) {
            if (markerChar(marker_end, .down)) |ch| {
                buffer.setWithColor(x2, y, ch, color);
            } else {
                drawLineCell(buffer, x2, y, true, color, arm);
            }
        } else {
            drawLineCell(buffer, x2, y, true, color, arm);
        }
    }
}

fn paintSideChannelEdge(buffer: *Buffer2D, edge: *const LayoutEdge, ch_x: usize, start_y: usize, end_y: usize, color: CellColor, arm: ArmWeight, marker_end: MarkerShape, marker_start: MarkerShape) void {
    const x1 = edge.from_x;
    const x2 = edge.to_x;

    // Vertical from source to start_y
    // Assumes top-down layout: reversed marker points upward.
    var y = edge.from_y + 1;
    const first_vert_start = edge.from_y + 1;
    while (y < start_y) : (y += 1) {
        if (edge.reversed and edge.directed and y == first_vert_start) {
            if (markerChar(marker_start, .up)) |ch| {
                buffer.setWithColor(x1, y, ch, color);
            } else {
                drawLineCell(buffer, x1, y, true, color, arm);
            }
        } else {
            drawLineCell(buffer, x1, y, true, color, arm);
        }
    }

    // Horizontal at start_y
    {
        const min_x1 = @min(x1, ch_x);
        const max_x1 = @max(x1, ch_x);
        var x = min_x1;
        while (x <= max_x1) : (x += 1) {
            drawLineCell(buffer, x, start_y, false, color, arm);
        }
    }

    // Vertical in channel
    y = start_y + 1;
    while (y < end_y) : (y += 1) {
        drawLineCell(buffer, ch_x, y, true, color, arm);
    }

    // Horizontal at end_y
    {
        const min_x2 = @min(ch_x, x2);
        const max_x2 = @max(ch_x, x2);
        var x = min_x2;
        while (x <= max_x2) : (x += 1) {
            drawLineCell(buffer, x, end_y, false, color, arm);
        }
    }

    // Vertical from end_y to target
    y = end_y + 1;
    while (y < edge.to_y) : (y += 1) {
        if (!edge.reversed and edge.directed and y == edge.to_y - 1) {
            if (markerChar(marker_end, .down)) |ch| {
                buffer.setWithColor(x2, y, ch, color);
            } else {
                drawLineCell(buffer, x2, y, true, color, arm);
            }
        } else {
            drawLineCell(buffer, x2, y, true, color, arm);
        }
    }
}

fn paintMultiSegmentEdge(buffer: *Buffer2D, edge: *const LayoutEdge, color: CellColor, arm: ArmWeight, marker_end: MarkerShape, marker_start: MarkerShape) void {
    const x1 = edge.from_x;
    const x2 = edge.to_x;
    const h_y = edge.from_y + 1;
    const min_x = @min(x1, x2);
    const max_x = @max(x1, x2);

    // Vertical from source to horizontal
    // Assumes top-down layout: reversed marker points upward.
    var y = edge.from_y;
    while (y < h_y) : (y += 1) {
        if (edge.reversed and edge.directed and y == edge.from_y) {
            if (markerChar(marker_start, .up)) |ch| {
                buffer.setWithColor(x1, y, ch, color);
            } else {
                drawLineCell(buffer, x1, y, true, color, arm);
            }
        } else {
            drawLineCell(buffer, x1, y, true, color, arm);
        }
    }

    // Horizontal segment (fill spaces and cross subgraph borders)
    var x = min_x;
    while (x <= max_x) : (x += 1) {
        if (x != x1 and x != x2) {
            drawLineCell(buffer, x, h_y, false, color, arm);
        }
    }

    // Junction at source x
    const current1 = buffer.get(x1, h_y);
    buffer.setWithColor(x1, h_y, mergeJunctionWeighted(current1, .{
        .up = arm,
        .right = if (x1 < x2) arm else .none,
        .left = if (x1 > x2) arm else .none,
    }), color);

    // Corner at target x
    const current2 = buffer.get(x2, h_y);
    buffer.setWithColor(x2, h_y, mergeJunctionWeighted(current2, .{
        .down = arm,
        .right = if (x1 > x2) arm else .none,
        .left = if (x1 < x2) arm else .none,
    }), color);

    // Vertical from horizontal to target
    y = h_y + 1;
    while (y < edge.to_y) : (y += 1) {
        if (!edge.reversed and edge.directed and y == edge.to_y - 1) {
            if (markerChar(marker_end, .down)) |ch| {
                buffer.setWithColor(x2, y, ch, color);
            } else {
                drawLineCell(buffer, x2, y, true, color, arm);
            }
        } else {
            drawLineCell(buffer, x2, y, true, color, arm);
        }
    }
}

fn paintSplineEdge(buffer: *Buffer2D, edge: *const LayoutEdge, color: CellColor, arm: ArmWeight, marker_end: MarkerShape, marker_start: MarkerShape) void {
    const x = edge.from_x;
    // Assumes top-down layout: reversed marker points upward.
    var y = edge.from_y;
    while (y < edge.to_y) : (y += 1) {
        if (edge.reversed and edge.directed and y == edge.from_y) {
            if (markerChar(marker_start, .up)) |ch| {
                buffer.setWithColor(x, y, ch, color);
            } else {
                drawLineCell(buffer, x, y, true, color, arm);
            }
        } else if (!edge.reversed and edge.directed and y == edge.to_y - 1) {
            if (markerChar(marker_end, .down)) |ch| {
                buffer.setWithColor(x, y, ch, color);
            } else {
                drawLineCell(buffer, x, y, true, color, arm);
            }
        } else {
            drawLineCell(buffer, x, y, true, color, arm);
        }
    }
    // Handle horizontal offset with corner if needed
    if (edge.from_x != edge.to_x) {
        const min_x = @min(edge.from_x, edge.to_x);
        const max_x = @max(edge.from_x, edge.to_x);
        const mid_y = edge.from_y + (edge.to_y - edge.from_y) / 2;
        var hx = min_x;
        while (hx <= max_x) : (hx += 1) {
            drawLineCell(buffer, hx, mid_y, false, color, arm);
        }
    }
}

// ── Shared internal helpers ─────────────────────────────────────────────────

/// Draw a single line cell (vertical or horizontal), handling weight variants
/// and subgraph border crossings via weight-aware junction merging.
fn drawLineCell(buffer: *Buffer2D, x: usize, y: usize, vertical: bool, color: CellColor, arm: ArmWeight) void {
    const new_dirs = DirWeights{
        .up = if (vertical) arm else .none,
        .down = if (vertical) arm else .none,
        .right = if (!vertical) arm else .none,
        .left = if (!vertical) arm else .none,
    };
    const cur = buffer.get(x, y);
    buffer.setWithColor(x, y, mergeJunctionWeighted(cur, new_dirs), color);
}

/// Draw a vertical segment between (x, lo+1) and (x, hi-1) — exclusive of both endpoints.
fn drawVerticalSegment(buffer: *Buffer2D, x: usize, lo: usize, hi: usize, color: CellColor, arm: ArmWeight) void {
    if (hi > lo + 1) {
        var y = lo + 1;
        while (y < hi) : (y += 1) {
            drawLineCell(buffer, x, y, true, color, arm);
        }
    }
}

/// Draw the arrow for a Manhattan route.
fn drawManhattanArrow(buffer: *Buffer2D, x0: usize, y0: usize, x1: usize, y1: usize, mid_y: usize, color: CellColor, reversed: bool, marker_end: MarkerShape, marker_start: MarkerShape) void {
    if (reversed) {
        // Reversed: marker_start at FROM end, pointing away from target
        const shape = marker_start;
        if (y0 != mid_y) {
            const dir: Direction = if (y0 < mid_y) .up else .down;
            if (markerChar(shape, dir)) |ch| {
                buffer.setWithColor(x0, y0, ch, color);
            }
        } else {
            const dir: Direction = if (x1 > x0) .left else .right;
            if (markerChar(shape, dir)) |ch| {
                buffer.setWithColor(x0, y0, ch, color);
            }
        }
    } else {
        // Normal: marker_end one cell before target at TO end
        const shape = marker_end;
        if (y1 != mid_y) {
            const going_down_s3 = y1 > mid_y;
            if (going_down_s3 and y1 == 0) return;
            if (!going_down_s3 and y1 >= buffer.height) return;
            const arrow_y = if (going_down_s3) y1 - 1 else y1 + 1;
            const dir: Direction = if (going_down_s3) .down else .up;
            if (markerChar(shape, dir)) |ch| {
                buffer.setWithColor(x1, arrow_y, ch, color);
            }
        } else {
            const going_right = x1 > x0;
            if (going_right and x1 == 0) return;
            if (!going_right and x1 >= buffer.width) return;
            const arrow_x = if (going_right) x1 - 1 else x1 + 1;
            const dir: Direction = if (going_right) .right else .left;
            if (markerChar(shape, dir)) |ch| {
                if (arrow_x < buffer.width) {
                    buffer.setWithColor(arrow_x, y1, ch, color);
                }
            }
        }
    }
}
