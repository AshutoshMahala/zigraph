//! SVG gradient generation from colormaps.
//!
//! Produces `<linearGradient>` and `<radialGradient>` SVG elements that can be
//! injected into `<defs>` via `NodeStyle.defs`, `EdgeStyle.defs`, or `global_style`.
//!
//! ## Usage
//!
//! ```zig
//! const gradient = @import("zigraph").color.gradient;
//! const ColorMap = @import("zigraph").color.ColorMap;
//!
//! fn styledNode(ctx: NodeStyleContext) NodeStyle {
//!     // Inject a radial gradient def, reference it via fill
//!     const id = std.fmt.allocPrint(ctx.arena, "heat-{d}", .{ctx.node_id}) catch "heat";
//!     return .{
//!         .defs = gradient.radialGradient(ctx.arena, id, ColorMap.turbo, 0.7) catch null,
//!         .fill = std.fmt.allocPrint(ctx.arena, "url(#{s})", .{id}) catch "#f00",
//!     };
//! }
//! ```

const std = @import("std");
const Allocator = std.mem.Allocator;
const Color = @import("Color.zig");
const colormaps = @import("colormaps.zig");
const ColorMap = colormaps.ColorMap;

/// Generate a `<linearGradient>` SVG element from a colormap.
///
/// - `id`: gradient element id (referenced as `fill="url(#id)"`)
/// - `cmap`: the colormap to sample
/// - `n_stops`: number of color stops (8–16 is usually enough)
/// - `direction`: `.horizontal`, `.vertical`, `.diagonal`
pub fn linearGradient(
    allocator: Allocator,
    id: []const u8,
    cmap: ColorMap,
    n_stops: usize,
    direction: Direction,
) ![]const u8 {
    var buf: std.ArrayListUnmanaged(u8) = .{};
    const writer = buf.writer(allocator);

    const coords = direction.coords();
    try writer.print(
        \\<linearGradient id="{s}" x1="{s}" y1="{s}" x2="{s}" y2="{s}">
    , .{ id, coords.x1, coords.y1, coords.x2, coords.y2 });

    const actual_stops = @max(n_stops, 2);
    for (0..actual_stops) |i| {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(actual_stops - 1));
        const c = cmap.sample(t);
        const hex = c.toHex();
        const pct = @as(usize, @intFromFloat(@round(t * 100.0)));
        try writer.print(
            \\<stop offset="{d}%" stop-color="{s}"/>
        , .{ pct, hex });
    }

    try writer.writeAll("</linearGradient>");
    return buf.toOwnedSlice(allocator);
}

/// Configuration for radial gradient geometry.
///
/// Defaults to centered (`cx="50%" cy="50%" r="50%"`).
/// Override for off-center light sources:
/// ```zig
/// // Top-left highlight (3D lighting effect)
/// .{ .cx = "30%", .cy = "25%", .r = "70%" }
/// ```
pub const RadialConfig = struct {
    cx: []const u8 = "50%",
    cy: []const u8 = "50%",
    r: []const u8 = "50%",
    /// SVG `fx`/`fy` focal point (null = same as cx/cy).
    fx: ?[]const u8 = null,
    fy: ?[]const u8 = null,
};

/// Generate a `<radialGradient>` SVG element from a colormap.
///
/// Maps `t=0.0` (center) to `t=inner_t` in the colormap and `t=1.0` (edge) to
/// the opposite end. Set `inner_t > 0.5` for hot-center (red inner, blue outer).
///
/// - `id`: gradient element id
/// - `cmap`: the colormap to sample
/// - `inner_t`: colormap position at the center (0.0–1.0)
///   - `1.0` → hot center (e.g., red inner → blue outer for turbo)
///   - `0.0` → cold center (e.g., blue inner → red outer for turbo)
/// - `radial_cfg`: optional geometry override (null = centered 50%/50%/50%)
pub fn radialGradient(
    allocator: Allocator,
    id: []const u8,
    cmap: ColorMap,
    inner_t: f32,
) ![]const u8 {
    return radialGradientEx(allocator, id, cmap, inner_t, .{});
}

/// Extended radial gradient with configurable center/radius/focal point.
pub fn radialGradientEx(
    allocator: Allocator,
    id: []const u8,
    cmap: ColorMap,
    inner_t: f32,
    cfg: RadialConfig,
) ![]const u8 {
    var buf: std.ArrayListUnmanaged(u8) = .{};
    const writer = buf.writer(allocator);

    try writer.print(
        \\<radialGradient id="{s}" cx="{s}" cy="{s}" r="{s}"
    , .{ id, cfg.cx, cfg.cy, cfg.r });
    if (cfg.fx) |fx| try writer.print(" fx=\"{s}\"", .{fx});
    if (cfg.fy) |fy| try writer.print(" fy=\"{s}\"", .{fy});
    try writer.writeAll(">");

    const n_stops: usize = 10;
    for (0..n_stops) |i| {
        const radius_t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n_stops - 1));
        // Map radius position to colormap position
        // At radius=0 (center) → inner_t, at radius=1 (edge) → 1-inner_t
        const cmap_t = inner_t + (1.0 - 2.0 * inner_t) * radius_t;
        const actual_t = @max(0.0, @min(1.0, cmap_t));
        const c = cmap.sample(actual_t);
        const hex = c.toHex();
        const pct = @as(usize, @intFromFloat(@round(radius_t * 100.0)));
        try writer.print(
            \\<stop offset="{d}%" stop-color="{s}"/>
        , .{ pct, hex });
    }

    try writer.writeAll("</radialGradient>");
    return buf.toOwnedSlice(allocator);
}

/// Generate a `<radialGradient>` that fades from `center_color` to transparent.
///
/// Useful for heatmap glow effects — a colored center with gaussian-blur falloff.
///
/// - `id`: gradient element id
/// - `center_color`: the glow color at the center
/// - `opacity`: peak opacity at center (0.0–1.0)
/// - Use `glowGradientEx` for off-center focal points.
pub fn glowGradient(
    allocator: Allocator,
    id: []const u8,
    center_color: Color,
    opacity: f32,
) ![]const u8 {
    return glowGradientEx(allocator, id, center_color, opacity, .{});
}

/// Extended glow gradient with configurable geometry.
pub fn glowGradientEx(
    allocator: Allocator,
    id: []const u8,
    center_color: Color,
    opacity: f32,
    cfg: RadialConfig,
) ![]const u8 {
    var buf: std.ArrayListUnmanaged(u8) = .{};
    const writer = buf.writer(allocator);
    const hex = center_color.toHex();

    try writer.print(
        \\<radialGradient id="{s}" cx="{s}" cy="{s}" r="{s}"
    , .{ id, cfg.cx, cfg.cy, cfg.r });
    if (cfg.fx) |fx| try writer.print(" fx=\"{s}\"", .{fx});
    if (cfg.fy) |fy| try writer.print(" fy=\"{s}\"", .{fy});
    try writer.writeAll(">");

    // 5 stops: solid center → fast falloff → transparent edge
    const opacities = [5]f32{ opacity, opacity * 0.7, opacity * 0.3, opacity * 0.1, 0.0 };
    const offsets = [5][]const u8{ "0%", "25%", "50%", "75%", "100%" };

    for (opacities, offsets) |op, offset| {
        try writer.print(
            \\<stop offset="{s}" stop-color="{s}" stop-opacity="{d:.2}"/>
        , .{ offset, hex, op });
    }

    try writer.writeAll("</radialGradient>");
    return buf.toOwnedSlice(allocator);
}

/// Gradient direction.
pub const Direction = enum {
    /// Left to right (x1=0, x2=1)
    horizontal,
    /// Top to bottom (y1=0, y2=1)
    vertical,
    /// Top-left to bottom-right
    diagonal,

    const Coords = struct { x1: []const u8, y1: []const u8, x2: []const u8, y2: []const u8 };

    fn coords(self: Direction) Coords {
        return switch (self) {
            .horizontal => .{ .x1 = "0%", .y1 = "0%", .x2 = "100%", .y2 = "0%" },
            .vertical => .{ .x1 = "0%", .y1 = "0%", .x2 = "0%", .y2 = "100%" },
            .diagonal => .{ .x1 = "0%", .y1 = "0%", .x2 = "100%", .y2 = "100%" },
        };
    }
};

// ════════════════════════════════════════════════════════════════════════════
// Tests
// ════════════════════════════════════════════════════════════════════════════

test "linearGradient produces valid SVG" {
    var buf: [4096]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const alloc = fba.allocator();

    const svg = try linearGradient(alloc, "grad1", ColorMap.viridis, 4, .horizontal);
    try std.testing.expect(std.mem.startsWith(u8, svg, "<linearGradient"));
    try std.testing.expect(std.mem.endsWith(u8, svg, "</linearGradient>"));
    try std.testing.expect(std.mem.indexOf(u8, svg, "id=\"grad1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "stop-color") != null);
}

test "radialGradient produces valid SVG" {
    var buf: [4096]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const alloc = fba.allocator();

    const svg = try radialGradient(alloc, "heat1", ColorMap.turbo, 0.8);
    try std.testing.expect(std.mem.startsWith(u8, svg, "<radialGradient"));
    try std.testing.expect(std.mem.endsWith(u8, svg, "</radialGradient>"));
    try std.testing.expect(std.mem.indexOf(u8, svg, "id=\"heat1\"") != null);
}

test "glowGradient has opacity falloff" {
    var buf: [4096]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const alloc = fba.allocator();

    const svg = try glowGradient(alloc, "glow1", Color.fromHex("#ef4444"), 0.6);
    try std.testing.expect(std.mem.startsWith(u8, svg, "<radialGradient"));
    try std.testing.expect(std.mem.indexOf(u8, svg, "stop-opacity") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "0.00") != null); // transparent edge
}

test "linearGradient direction coords" {
    var buf: [4096]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const alloc = fba.allocator();

    const h = try linearGradient(alloc, "h", ColorMap.viridis, 2, .horizontal);
    try std.testing.expect(std.mem.indexOf(u8, h, "x2=\"100%\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, h, "y2=\"0%\"") != null);
}

test "radialGradientEx with custom center" {
    var buf: [4096]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const alloc = fba.allocator();

    const svg = try radialGradientEx(alloc, "light", ColorMap.turbo, 0.8, .{
        .cx = "30%",
        .cy = "25%",
        .r = "70%",
        .fx = "20%",
        .fy = "15%",
    });
    try std.testing.expect(std.mem.indexOf(u8, svg, "cx=\"30%\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "cy=\"25%\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "r=\"70%\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "fx=\"20%\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "fy=\"15%\"") != null);
}

test "radialGradient default is centered" {
    var buf: [4096]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const alloc = fba.allocator();

    const svg = try radialGradient(alloc, "default", ColorMap.turbo, 0.8);
    try std.testing.expect(std.mem.indexOf(u8, svg, "cx=\"50%\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "cy=\"50%\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg, "r=\"50%\"") != null);
    // Should NOT have fx/fy when using defaults
    try std.testing.expect(std.mem.indexOf(u8, svg, "fx=") == null);
}
