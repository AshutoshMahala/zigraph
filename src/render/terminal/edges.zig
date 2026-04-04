//! Edge painting for the terminal renderer.
//!
//! Contains `paintEdge` and the directional draw helpers:
//! `drawDirectVertical`, `drawDirectHorizontal`, `drawDirectManhattan`.
//!
//! All painting functions are weight-aware: they produce light (─│), heavy (━┃),
//! double (═║), or dashed (┈┊) characters and correctly merge junctions when
//! edges of different weights cross.

const std = @import("std");
const ir_mod = @import("../../core/ir.zig");
const LayoutEdge = ir_mod.LayoutEdge(usize);
const Buffer2D = @import("buffer.zig").Buffer2D;
const config_mod = @import("config.zig");
const LineWeight = config_mod.LineWeight;
const MarkerShape = config_mod.MarkerShape;
const CellColor = config_mod.CellColor;
const Color = config_mod.Color;
const resolveColor = config_mod.resolveColor;
const resolveColorAt = config_mod.resolveColorAt;
const j = @import("junctions.zig");
const mergeJunctionWeighted = j.mergeJunctionWeighted;
const ArmWeight = j.ArmWeight;
const DirWeights = j.DirWeights;
const Direction = j.Direction;
const markerChar = j.markerChar;

/// Gradient-aware edge color resolver.
/// For non-gradient colors returns a flat CellColor; for gradients, interpolates
/// based on the cell's y-position relative to the edge's vertical span.
pub const EdgeColor = struct {
    color: Color,
    from_y: usize,
    to_y: usize,

    /// Build from a `Color` and the edge's y-span.
    pub fn init(color: Color, from_y: usize, to_y: usize) EdgeColor {
        return .{ .color = color, .from_y = from_y, .to_y = to_y };
    }

    /// Build from a flat `CellColor` (no gradient).
    pub fn flat(cc: CellColor) EdgeColor {
        // Wrap the CellColor as the equivalent Color union member.
        const c: Color = switch (cc.tag) {
            .default, ._reserved => .default,
            .ansi => .{ .ansi256 = cc.ansiIndex() },
            .rgb => .{ .rgb = .{ .r = cc.r(), .g = cc.g(), .b = cc.b() } },
        };
        return .{ .color = c, .from_y = 0, .to_y = 0 };
    }

    /// Resolve color at vertical position `y`.
    pub fn at(self: EdgeColor, y: usize) CellColor {
        return switch (self.color) {
            .gradient => {
                if (self.from_y == self.to_y) return resolveColorAt(self.color, 0.5);
                const span: f32 = @floatFromInt(self.to_y - self.from_y);
                const pos: f32 = @floatFromInt(if (y >= self.from_y) y - self.from_y else 0);
                return resolveColorAt(self.color, std.math.clamp(pos / span, 0.0, 1.0));
            },
            else => resolveColor(self.color),
        };
    }

    /// Resolve color at horizontal position `x` within [lo_x, hi_x].
    /// Used for purely horizontal edges where y doesn't vary.
    pub fn atX(self: EdgeColor, x: usize, lo_x: usize, hi_x: usize) CellColor {
        return switch (self.color) {
            .gradient => {
                if (lo_x == hi_x) return resolveColorAt(self.color, 0.5);
                const span: f32 = @floatFromInt(hi_x - lo_x);
                const pos: f32 = @floatFromInt(if (x >= lo_x) x - lo_x else 0);
                return resolveColorAt(self.color, std.math.clamp(pos / span, 0.0, 1.0));
            },
            else => resolveColor(self.color),
        };
    }
};

/// Paint an edge onto the buffer.
/// Color, weight, and markers come from the style function.
/// Accepts a `Color` union to support per-cell gradient interpolation.
pub fn paintEdge(buffer: *Buffer2D, edge: *const LayoutEdge, color: Color, weight: LineWeight, marker_end: MarkerShape, marker_start: MarkerShape) void {
    const ec = EdgeColor.init(color, edge.from_y, edge.to_y);
    const arm = ArmWeight.fromLineWeight(weight);
    switch (edge.path) {
        .direct => {
            const x0 = edge.from_x;
            const y0 = edge.from_y;
            const x1 = edge.to_x;
            const y1 = edge.to_y;

            if (x0 == x1 and y0 == y1) return; // degenerate

            if (x0 == x1) {
                drawDirectVertical(buffer, x0, y0, y1, ec, weight, edge.directed, marker_end);
            } else if (y0 == y1) {
                drawDirectHorizontal(buffer, y0, x0, x1, ec, weight, edge.directed, marker_end);
            } else {
                drawDirectManhattan(buffer, x0, y0, x1, y1, ec, weight, edge.directed, edge.reversed, marker_end, marker_start);
            }
        },
        .corner => |corner| {
            paintCornerEdge(buffer, edge, corner.horizontal_y, ec, arm, marker_end, marker_start);
        },
        .side_channel => |sc| {
            paintSideChannelEdge(buffer, edge, sc.channel_x, sc.start_y, sc.end_y, ec, arm, marker_end, marker_start);
        },
        .multi_segment => {
            paintMultiSegmentEdge(buffer, edge, ec, arm, marker_end, marker_start);
        },
        .spline => {
            paintSplineEdge(buffer, edge, ec, arm, marker_end, marker_start);
        },
        .bus => |bus| {
            paintBusEdge(buffer, edge, bus, ec, arm, marker_end, marker_start);
        },
    }
}

// ── Directional draw helpers ────────────────────────────────────────────────

/// Draw a pure-vertical direct edge between y_from and y_to at column x.
pub fn drawDirectVertical(buffer: *Buffer2D, x: usize, y_from: usize, y_to: usize, ec: EdgeColor, weight: LineWeight, directed: bool, marker_end: MarkerShape) void {
    if (y_from == y_to) return;
    const lo = @min(y_from, y_to);
    const hi = @max(y_from, y_to);
    const going_down = y_to > y_from;
    const arrow_y = if (going_down) hi - 1 else lo;
    const arm = ArmWeight.fromLineWeight(weight);
    const arrow_ch: ?u21 = if (directed)
        markerChar(marker_end, if (going_down) .down else .up, arm)
    else
        null;

    var y = lo;
    while (y < hi) : (y += 1) {
        if (arrow_ch != null and y == arrow_y) {
            buffer.setWithColor(x, y, arrow_ch.?, ec.at(y));
        } else {
            drawLineCell(buffer, x, y, true, ec.at(y), arm);
        }
    }
}

/// Draw a pure-horizontal direct edge between x_from and x_to at row y.
pub fn drawDirectHorizontal(buffer: *Buffer2D, y: usize, x_from: usize, x_to: usize, ec: EdgeColor, weight: LineWeight, directed: bool, marker_end: MarkerShape) void {
    if (x_from == x_to) return;
    const lo = @min(x_from, x_to);
    const hi = @max(x_from, x_to);
    const going_right = x_to > x_from;
    const arrow_x = if (going_right) hi - 1 else lo;
    const arm = ArmWeight.fromLineWeight(weight);
    const arrow_ch: ?u21 = if (directed)
        markerChar(marker_end, if (going_right) .right else .left, arm)
    else
        null;

    var x = lo;
    while (x < hi) : (x += 1) {
        const cc = ec.atX(x, lo, hi);
        if (arrow_ch != null and x == arrow_x) {
            buffer.setWithColor(x, y, arrow_ch.?, cc);
        } else {
            drawLineCell(buffer, x, y, false, cc, arm);
        }
    }
}

/// Draw a Manhattan Z-shaped route between (x0,y0) and (x1,y1).
/// Route: (x0,y0) → (x0,mid_y) → (x1,mid_y) → (x1,y1)
pub fn drawDirectManhattan(buffer: *Buffer2D, x0: usize, y0: usize, x1: usize, y1: usize, ec: EdgeColor, weight: LineWeight, directed: bool, reversed: bool, marker_end: MarkerShape, marker_start: MarkerShape) void {
    const lo_y = @min(y0, y1);
    const hi_y = @max(y0, y1);
    const mid_y = lo_y + (hi_y - lo_y) / 2;
    const arm = ArmWeight.fromLineWeight(weight);

    // --- Segment 1: vertical at x0 between y0 and mid_y (exclusive of both) ---
    drawVerticalSegment(buffer, x0, @min(y0, mid_y), @max(y0, mid_y), ec, arm);

    // --- Corner 1 at (x0, mid_y) ---
    {
        const cc = ec.at(mid_y);
        const cur = buffer.get(x0, mid_y);
        buffer.setWithColor(x0, mid_y, mergeJunctionWeighted(cur, .{
            .up = if (y0 < mid_y) arm else .none,
            .down = if (y0 > mid_y) arm else .none,
            .right = if (x1 > x0) arm else .none,
            .left = if (x1 < x0) arm else .none,
        }), cc);
    }

    // --- Segment 2: horizontal at mid_y (exclusive of x0 and x1) ---
    {
        const lo_x = @min(x0, x1);
        const hi_x = @max(x0, x1);
        const cc = ec.at(mid_y);
        if (hi_x > lo_x + 1) {
            var x = lo_x + 1;
            while (x < hi_x) : (x += 1) {
                drawLineCell(buffer, x, mid_y, false, cc, arm);
            }
        }
    }

    // --- Corner 2 at (x1, mid_y) ---
    {
        const cc = ec.at(mid_y);
        const cur = buffer.get(x1, mid_y);
        buffer.setWithColor(x1, mid_y, mergeJunctionWeighted(cur, .{
            .up = if (y1 < mid_y) arm else .none,
            .down = if (y1 > mid_y) arm else .none,
            .right = if (x0 > x1) arm else .none,
            .left = if (x0 < x1) arm else .none,
        }), cc);
    }

    // --- Segment 3: vertical at x1 between mid_y and y1 (exclusive of both) ---
    drawVerticalSegment(buffer, x1, @min(mid_y, y1), @max(mid_y, y1), ec, arm);

    // --- Arrow ---
    if (directed) {
        drawManhattanArrow(buffer, x0, y0, x1, y1, mid_y, ec, reversed, marker_end, marker_start, arm);
    }
}

// ── Private path-type helpers ───────────────────────────────────────────────

fn paintCornerEdge(buffer: *Buffer2D, edge: *const LayoutEdge, h_y: usize, ec: EdgeColor, arm: ArmWeight, marker_end: MarkerShape, marker_start: MarkerShape) void {
    const x1 = edge.from_x;
    const x2 = edge.to_x;
    const min_x = @min(x1, x2);
    const max_x = @max(x1, x2);

    // Vertical from source to horizontal
    // Assumes top-down layout: reversed marker points upward.
    var y = edge.from_y;
    while (y < h_y) : (y += 1) {
        if (edge.reversed and edge.directed and y == edge.from_y) {
            if (markerChar(marker_start, .up, arm)) |ch| {
                buffer.setWithColor(x1, y, ch, ec.at(y));
            } else {
                drawLineCell(buffer, x1, y, true, ec.at(y), arm);
            }
        } else {
            drawLineCell(buffer, x1, y, true, ec.at(y), arm);
        }
    }

    // Horizontal segment
    {
        const cc = ec.at(h_y);
        var x = min_x;
        while (x <= max_x) : (x += 1) {
            if (x != x1 and x != x2) {
                drawLineCell(buffer, x, h_y, false, cc, arm);
            }
        }
    }

    // Junction at source x
    {
        const cc = ec.at(h_y);
        const current1 = buffer.get(x1, h_y);
        buffer.setWithColor(x1, h_y, mergeJunctionWeighted(current1, .{
            .up = arm,
            .right = if (x1 < x2) arm else .none,
            .left = if (x1 > x2) arm else .none,
        }), cc);
    }

    // Corner at target x
    {
        const cc = ec.at(h_y);
        const current2 = buffer.get(x2, h_y);
        buffer.setWithColor(x2, h_y, mergeJunctionWeighted(current2, .{
            .down = arm,
            .right = if (x1 > x2) arm else .none,
            .left = if (x1 < x2) arm else .none,
        }), cc);
    }

    // Vertical from horizontal to target
    y = h_y + 1;
    while (y < edge.to_y) : (y += 1) {
        if (!edge.reversed and edge.directed and y == edge.to_y - 1) {
            if (markerChar(marker_end, .down, arm)) |ch| {
                buffer.setWithColor(x2, y, ch, ec.at(y));
            } else {
                drawLineCell(buffer, x2, y, true, ec.at(y), arm);
            }
        } else {
            drawLineCell(buffer, x2, y, true, ec.at(y), arm);
        }
    }
}

/// Paint a bus-style fan-out edge.
///
/// Stem edges draw: vertical trunk from parent -> bus_y, horizontal bus across
/// all sibling_xs, with a T-junction at the stem and drop junctions at each child.
/// Non-stem edges draw: vertical drop from bus_y+1 -> child, with arrow marker.
fn paintBusEdge(
    buffer: *Buffer2D,
    edge: *const LayoutEdge,
    bus: anytype,
    ec: EdgeColor,
    arm: ArmWeight,
    marker_end: MarkerShape,
    marker_start: MarkerShape,
) void {
    const h_y = bus.horizontal_y;

    if (bus.is_stem) {
        // --- Stem edge: draw trunk + full horizontal bus ---

        // 1. Vertical trunk from parent center_x, from_y to h_y
        const trunk_x = edge.from_x;
        var y = edge.from_y;
        while (y < h_y) : (y += 1) {
            if (edge.reversed and edge.directed and y == edge.from_y) {
                if (markerChar(marker_start, .up, arm)) |ch| {
                    buffer.setWithColor(trunk_x, y, ch, ec.at(y));
                } else {
                    drawLineCell(buffer, trunk_x, y, true, ec.at(y), arm);
                }
            } else {
                drawLineCell(buffer, trunk_x, y, true, ec.at(y), arm);
            }
        }

        // 2. Find bus extents from sibling_xs
        const sibling_xs = bus.sibling_xs[0..bus.sibling_count];
        var min_x: usize = trunk_x;
        var max_x: usize = trunk_x;
        for (sibling_xs) |sx| {
            min_x = @min(min_x, sx);
            max_x = @max(max_x, sx);
        }

        // 3. Horizontal bus line at h_y
        {
            const cc = ec.at(h_y);
            var x = min_x;
            while (x <= max_x) : (x += 1) {
                drawLineCell(buffer, x, h_y, false, cc, arm);
            }
        }

        // 4. Junction where trunk meets bus (up + left + right, maybe down)
        {
            const cc = ec.at(h_y);
            const current = buffer.get(trunk_x, h_y);
            buffer.setWithColor(trunk_x, h_y, mergeJunctionWeighted(current, .{
                .up = arm,
                .left = if (trunk_x > min_x) arm else .none,
                .right = if (trunk_x < max_x) arm else .none,
                .down = blk: {
                    // Check if trunk_x is also a child position
                    for (sibling_xs) |sx| {
                        if (sx == trunk_x) break :blk arm;
                    }
                    break :blk .none;
                },
            }), cc);
        }

        // 5. Junctions at each child drop-off point
        for (sibling_xs) |child_x| {
            if (child_x == trunk_x) continue; // Already handled above
            const cc = ec.at(h_y);
            const current = buffer.get(child_x, h_y);
            buffer.setWithColor(child_x, h_y, mergeJunctionWeighted(current, .{
                .down = arm,
                .left = if (child_x > min_x) arm else .none,
                .right = if (child_x < max_x) arm else .none,
            }), cc);
        }
    }

    // --- All edges (stem and non-stem): draw vertical drop to child ---
    {
        const h_y_start = bus.horizontal_y + 1;
        var y2 = h_y_start;
        while (y2 < edge.to_y) : (y2 += 1) {
            if (!edge.reversed and edge.directed and y2 == edge.to_y - 1) {
                if (markerChar(marker_end, .down, arm)) |ch| {
                    buffer.setWithColor(edge.to_x, y2, ch, ec.at(y2));
                } else {
                    drawLineCell(buffer, edge.to_x, y2, true, ec.at(y2), arm);
                }
            } else {
                drawLineCell(buffer, edge.to_x, y2, true, ec.at(y2), arm);
            }
        }
    }
}

fn paintSideChannelEdge(buffer: *Buffer2D, edge: *const LayoutEdge, ch_x: usize, start_y: usize, end_y: usize, ec: EdgeColor, arm: ArmWeight, marker_end: MarkerShape, marker_start: MarkerShape) void {
    const x1 = edge.from_x;
    const x2 = edge.to_x;

    // Vertical from source to start_y
    // Assumes top-down layout: reversed marker points upward.
    var y = edge.from_y + 1;
    const first_vert_start = edge.from_y + 1;
    while (y < start_y) : (y += 1) {
        if (edge.reversed and edge.directed and y == first_vert_start) {
            if (markerChar(marker_start, .up, arm)) |ch| {
                buffer.setWithColor(x1, y, ch, ec.at(y));
            } else {
                drawLineCell(buffer, x1, y, true, ec.at(y), arm);
            }
        } else {
            drawLineCell(buffer, x1, y, true, ec.at(y), arm);
        }
    }

    // Horizontal at start_y
    {
        const min_x1 = @min(x1, ch_x);
        const max_x1 = @max(x1, ch_x);
        const cc = ec.at(start_y);
        var x = min_x1;
        while (x <= max_x1) : (x += 1) {
            drawLineCell(buffer, x, start_y, false, cc, arm);
        }
    }

    // Vertical in channel
    y = start_y + 1;
    while (y < end_y) : (y += 1) {
        drawLineCell(buffer, ch_x, y, true, ec.at(y), arm);
    }

    // Horizontal at end_y
    {
        const min_x2 = @min(ch_x, x2);
        const max_x2 = @max(ch_x, x2);
        const cc = ec.at(end_y);
        var x = min_x2;
        while (x <= max_x2) : (x += 1) {
            drawLineCell(buffer, x, end_y, false, cc, arm);
        }
    }

    // Vertical from end_y to target
    y = end_y + 1;
    while (y < edge.to_y) : (y += 1) {
        if (!edge.reversed and edge.directed and y == edge.to_y - 1) {
            if (markerChar(marker_end, .down, arm)) |ch| {
                buffer.setWithColor(x2, y, ch, ec.at(y));
            } else {
                drawLineCell(buffer, x2, y, true, ec.at(y), arm);
            }
        } else {
            drawLineCell(buffer, x2, y, true, ec.at(y), arm);
        }
    }
}

fn paintMultiSegmentEdge(buffer: *Buffer2D, edge: *const LayoutEdge, ec: EdgeColor, arm: ArmWeight, marker_end: MarkerShape, marker_start: MarkerShape) void {
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
            if (markerChar(marker_start, .up, arm)) |ch| {
                buffer.setWithColor(x1, y, ch, ec.at(y));
            } else {
                drawLineCell(buffer, x1, y, true, ec.at(y), arm);
            }
        } else {
            drawLineCell(buffer, x1, y, true, ec.at(y), arm);
        }
    }

    // Horizontal segment (fill spaces and cross subgraph borders)
    {
        const cc = ec.at(h_y);
        var x = min_x;
        while (x <= max_x) : (x += 1) {
            if (x != x1 and x != x2) {
                drawLineCell(buffer, x, h_y, false, cc, arm);
            }
        }
    }

    // Junction at source x
    {
        const cc = ec.at(h_y);
        const current1 = buffer.get(x1, h_y);
        buffer.setWithColor(x1, h_y, mergeJunctionWeighted(current1, .{
            .up = arm,
            .right = if (x1 < x2) arm else .none,
            .left = if (x1 > x2) arm else .none,
        }), cc);
    }

    // Corner at target x
    {
        const cc = ec.at(h_y);
        const current2 = buffer.get(x2, h_y);
        buffer.setWithColor(x2, h_y, mergeJunctionWeighted(current2, .{
            .down = arm,
            .right = if (x1 > x2) arm else .none,
            .left = if (x1 < x2) arm else .none,
        }), cc);
    }

    // Vertical from horizontal to target
    y = h_y + 1;
    while (y < edge.to_y) : (y += 1) {
        if (!edge.reversed and edge.directed and y == edge.to_y - 1) {
            if (markerChar(marker_end, .down, arm)) |ch| {
                buffer.setWithColor(x2, y, ch, ec.at(y));
            } else {
                drawLineCell(buffer, x2, y, true, ec.at(y), arm);
            }
        } else {
            drawLineCell(buffer, x2, y, true, ec.at(y), arm);
        }
    }
}

fn paintSplineEdge(buffer: *Buffer2D, edge: *const LayoutEdge, ec: EdgeColor, arm: ArmWeight, marker_end: MarkerShape, marker_start: MarkerShape) void {
    const x = edge.from_x;
    // Assumes top-down layout: reversed marker points upward.
    var y = edge.from_y;
    while (y < edge.to_y) : (y += 1) {
        if (edge.reversed and edge.directed and y == edge.from_y) {
            if (markerChar(marker_start, .up, arm)) |ch| {
                buffer.setWithColor(x, y, ch, ec.at(y));
            } else {
                drawLineCell(buffer, x, y, true, ec.at(y), arm);
            }
        } else if (!edge.reversed and edge.directed and y == edge.to_y - 1) {
            if (markerChar(marker_end, .down, arm)) |ch| {
                buffer.setWithColor(x, y, ch, ec.at(y));
            } else {
                drawLineCell(buffer, x, y, true, ec.at(y), arm);
            }
        } else {
            drawLineCell(buffer, x, y, true, ec.at(y), arm);
        }
    }
    // Handle horizontal offset with corner if needed
    if (edge.from_x != edge.to_x) {
        const min_x = @min(edge.from_x, edge.to_x);
        const max_x = @max(edge.from_x, edge.to_x);
        const mid_y = edge.from_y + (edge.to_y - edge.from_y) / 2;
        const cc = ec.at(mid_y);
        var hx = min_x;
        while (hx <= max_x) : (hx += 1) {
            drawLineCell(buffer, hx, mid_y, false, cc, arm);
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
fn drawVerticalSegment(buffer: *Buffer2D, x: usize, lo: usize, hi: usize, ec: EdgeColor, arm: ArmWeight) void {
    if (hi > lo + 1) {
        var y = lo + 1;
        while (y < hi) : (y += 1) {
            drawLineCell(buffer, x, y, true, ec.at(y), arm);
        }
    }
}

/// Draw the arrow for a Manhattan route.
fn drawManhattanArrow(buffer: *Buffer2D, x0: usize, y0: usize, x1: usize, y1: usize, mid_y: usize, ec: EdgeColor, reversed: bool, marker_end: MarkerShape, marker_start: MarkerShape, arm: ArmWeight) void {
    if (reversed) {
        // Reversed: marker_start at FROM end, pointing away from target
        const shape = marker_start;
        if (y0 != mid_y) {
            const dir: Direction = if (y0 < mid_y) .up else .down;
            if (markerChar(shape, dir, arm)) |ch| {
                buffer.setWithColor(x0, y0, ch, ec.at(y0));
            }
        } else {
            const dir: Direction = if (x1 > x0) .left else .right;
            if (markerChar(shape, dir, arm)) |ch| {
                buffer.setWithColor(x0, y0, ch, ec.at(y0));
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
            if (markerChar(shape, dir, arm)) |ch| {
                buffer.setWithColor(x1, arrow_y, ch, ec.at(arrow_y));
            }
        } else {
            const going_right = x1 > x0;
            if (going_right and x1 == 0) return;
            if (!going_right and x1 >= buffer.width) return;
            const arrow_x = if (going_right) x1 - 1 else x1 + 1;
            const dir: Direction = if (going_right) .right else .left;
            if (markerChar(shape, dir, arm)) |ch| {
                if (arrow_x < buffer.width) {
                    buffer.setWithColor(arrow_x, y1, ch, ec.at(y1));
                }
            }
        }
    }
}
