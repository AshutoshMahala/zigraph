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

/// Validate and escape a gradient ID for safe SVG attribute interpolation.
/// Only allows alphanumeric characters, hyphens, underscores, and dots.
/// Returns the original string if valid, or a safe fallback if invalid.
fn sanitizeId(allocator: Allocator, raw: []const u8) []const u8 {
    for (raw) |c| {
        switch (c) {
            'a'...'z', 'A'...'Z', '0'...'9', '-', '_', '.' => {},
            else => {
                // Contains unsafe chars — allocate a filtered copy
                var buf = allocator.alloc(u8, raw.len) catch return "grad";
                var len: usize = 0;
                for (raw) |ch| {
                    switch (ch) {
                        'a'...'z', 'A'...'Z', '0'...'9', '-', '_', '.' => {
                            buf[len] = ch;
                            len += 1;
                        },
                        else => {},
                    }
                }
                if (len == 0) return "grad";
                return buf[0..len];
            },
        }
    }
    return raw; // All chars safe — no allocation needed
}

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
    var buf = std.Io.Writer.Allocating.init(allocator);
    errdefer buf.deinit();
    const writer = &buf.writer;

    const safe_id = sanitizeId(allocator, id);
    const coords = direction.coords();
    try writer.print(
        \\<linearGradient id="{s}" x1="{s}" y1="{s}" x2="{s}" y2="{s}">
    , .{ safe_id, coords.x1, coords.y1, coords.x2, coords.y2 });

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
    return buf.toOwnedSlice();
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
    const safe_id = sanitizeId(allocator, id);
    var buf = std.Io.Writer.Allocating.init(allocator);
    errdefer buf.deinit();
    const writer = &buf.writer;

    try writer.print(
        \\<radialGradient id="{s}" cx="{s}" cy="{s}" r="{s}"
    , .{ safe_id, cfg.cx, cfg.cy, cfg.r });
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
    return buf.toOwnedSlice();
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
    const safe_id = sanitizeId(allocator, id);
    var buf = std.Io.Writer.Allocating.init(allocator);
    errdefer buf.deinit();
    const writer = &buf.writer;
    const hex = center_color.toHex();

    try writer.print(
        \\<radialGradient id="{s}" cx="{s}" cy="{s}" r="{s}"
    , .{ safe_id, cfg.cx, cfg.cy, cfg.r });
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
    return buf.toOwnedSlice();
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

test "sanitizeId strips unsafe characters" {
    var buf: [4096]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const alloc = fba.allocator();

    // Safe id passes through unchanged
    const safe = sanitizeId(alloc, "my-gradient_1");
    try std.testing.expectEqualStrings("my-gradient_1", safe);

    // Unsafe chars stripped
    const cleaned = sanitizeId(alloc, "grad<script>");
    try std.testing.expect(std.mem.indexOf(u8, cleaned, "<") == null);
    try std.testing.expect(std.mem.indexOf(u8, cleaned, ">") == null);
    try std.testing.expect(cleaned.len > 0);
}

test "linearGradient sanitizes id with special chars" {
    var buf: [8192]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const alloc = fba.allocator();

    const svg = try linearGradient(alloc, "test\"><script>", ColorMap.turbo, 4, .vertical);
    // The output must NOT contain unescaped quotes or angle brackets in the id attribute
    try std.testing.expect(std.mem.indexOf(u8, svg, "<script>") == null);
}
