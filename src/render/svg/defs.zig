//! SVG `<defs>` helpers: marker definitions and user-provided defs collection.
//!
//! Extracted from mod.zig to keep the render pipeline focused on orchestration.

const std = @import("std");
const types = @import("../types.zig");
const MarkerShape = types.MarkerShape;

/// A unique (color, shape) pair for a `<marker>` definition.
pub const MarkerDef = struct { color: []const u8, shape: MarkerShape };

/// Find an existing (color, shape) marker or add a new one. Returns the index.
pub fn findOrAddMarker(
    markers: *[128]MarkerDef,
    count: *usize,
    color: []const u8,
    shape: MarkerShape,
) usize {
    for (markers[0..count.*], 0..) |m, i| {
        if (m.shape == shape and std.mem.eql(u8, m.color, color)) return i;
    }
    if (count.* >= 128) return 0; // safety cap
    markers[count.*] = .{ .color = color, .shape = shape };
    count.* += 1;
    return count.* - 1;
}

/// Write a single `<marker>` definition for the given shape and color.
pub fn writeMarkerDef(writer: anytype, id: usize, shape: MarkerShape, color: []const u8, size: usize) !void {
    const half = size / 2;
    switch (shape) {
        .none => {},
        .arrow => {
            try writer.print(
                \\    <marker id="zg-m-{d}" markerWidth="{d}" markerHeight="{d}" 
                \\            refX="{d}" refY="{d}" orient="auto" markerUnits="userSpaceOnUse">
                \\      <polygon points="0 0, {d} {d}, 0 {d}" fill="{s}"/>
                \\    </marker>
                \\
            , .{ id, size, size, size, half, size, half, size, color });
        },
        .open_arrow => {
            try writer.print(
                \\    <marker id="zg-m-{d}" markerWidth="{d}" markerHeight="{d}" 
                \\            refX="{d}" refY="{d}" orient="auto" markerUnits="userSpaceOnUse">
                \\      <polygon points="0 0, {d} {d}, 0 {d}" fill="white" stroke="{s}" stroke-width="1"/>
                \\    </marker>
                \\
            , .{ id, size, size, size, half, size, half, size, color });
        },
        .diamond => {
            try writer.print(
                \\    <marker id="zg-m-{d}" markerWidth="{d}" markerHeight="{d}" 
                \\            refX="{d}" refY="{d}" orient="auto" markerUnits="userSpaceOnUse">
                \\      <polygon points="{d} 0, {d} {d}, {d} {d}, 0 {d}" fill="{s}"/>
                \\    </marker>
                \\
            , .{ id, size, size, size, half, half, size, half, half, size, half, color });
        },
        .open_diamond => {
            try writer.print(
                \\    <marker id="zg-m-{d}" markerWidth="{d}" markerHeight="{d}" 
                \\            refX="{d}" refY="{d}" orient="auto" markerUnits="userSpaceOnUse">
                \\      <polygon points="{d} 0, {d} {d}, {d} {d}, 0 {d}" fill="white" stroke="{s}" stroke-width="1"/>
                \\    </marker>
                \\
            , .{ id, size, size, size, half, half, size, half, half, size, half, color });
        },
        .circle => {
            try writer.print(
                \\    <marker id="zg-m-{d}" markerWidth="{d}" markerHeight="{d}" 
                \\            refX="{d}" refY="{d}" orient="auto" markerUnits="userSpaceOnUse">
                \\      <circle cx="{d}" cy="{d}" r="{d}" fill="{s}"/>
                \\    </marker>
                \\
            , .{ id, size, size, size, half, half, half, half, color });
        },
        .open_circle => {
            try writer.print(
                \\    <marker id="zg-m-{d}" markerWidth="{d}" markerHeight="{d}" 
                \\            refX="{d}" refY="{d}" orient="auto" markerUnits="userSpaceOnUse">
                \\      <circle cx="{d}" cy="{d}" r="{d}" fill="white" stroke="{s}" stroke-width="1"/>
                \\    </marker>
                \\
            , .{ id, size, size, size, half, half, half, half, color });
        },
    }
}
