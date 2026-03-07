//! Numeric color type with perceptual color space support.
//!
//! `Color` stores RGBA as `f32` (0.0–1.0) and provides:
//!   - **Conversions:** sRGB ↔ linear RGB ↔ Oklab ↔ HSL ↔ hex string
//!   - **Interpolation:** `lerp()` in Oklab space (perceptually uniform)
//!   - **Operations:** darken, lighten, saturate, desaturate, withAlpha
//!   - **Comptime hex:** `toHex()` returns `[7]u8`, `toHex8()` returns `[9]u8` — zero-cost at comptime
//!   - **Runtime hex:** `toHexAlloc(arena)` auto-picks 6 vs 8 digit based on alpha
//!
//! ## Comptime usage (zero allocation)
//!
//! ```zig
//! const red = comptime Color.fromHex("#e54d2e");
//! const dark_red = comptime red.darken(0.3);
//! const hex = comptime dark_red.toHex();     // [7]u8 in .rodata
//! // &hex coerces to []const u8 — use directly in style structs
//! ```
//!
//! ## Runtime usage (arena allocation)
//!
//! ```zig
//! fn heatNode(ctx: NodeStyleContext) NodeStyle {
//!     const t = @as(f32, @floatFromInt(ctx.node_id)) / @as(f32, @floatFromInt(ctx.total_nodes));
//!     const c = Color.fromHex("#3b82f6").lerp(Color.fromHex("#ef4444"), t);
//!     return .{ .fill = c.toHexAlloc(ctx.arena) catch "#999" };
//! }
//! ```

const std = @import("std");
const math = std.math;
const Allocator = std.mem.Allocator;

const Color = @This();

/// Red component (0.0–1.0, sRGB)
r: f32,
/// Green component (0.0–1.0, sRGB)
g: f32,
/// Blue component (0.0–1.0, sRGB)
b: f32,
/// Alpha component (0.0 = transparent, 1.0 = opaque)
a: f32 = 1.0,

// ════════════════════════════════════════════════════════════════════════════
// Constructors
// ════════════════════════════════════════════════════════════════════════════

/// Create a color from sRGB components (0.0–1.0).
pub fn rgb(r: f32, g: f32, b: f32) Color {
    return .{ .r = r, .g = g, .b = b, .a = 1.0 };
}

/// Create a color from sRGBA components (0.0–1.0).
pub fn rgba(r: f32, g: f32, b: f32, a: f32) Color {
    return .{ .r = r, .g = g, .b = b, .a = a };
}

/// Create a color from 0–255 integer components.
pub fn rgb8(r: u8, g: u8, b: u8) Color {
    return .{
        .r = @as(f32, @floatFromInt(r)) / 255.0,
        .g = @as(f32, @floatFromInt(g)) / 255.0,
        .b = @as(f32, @floatFromInt(b)) / 255.0,
        .a = 1.0,
    };
}

/// Parse a hex color string (`#rrggbb`, `#rrggbbaa`, or `#rgb`).
/// Returns black on invalid input.
pub fn fromHex(hex: []const u8) Color {
    return parseHex(hex) orelse rgb(0, 0, 0);
}

/// Parse a hex color string, returning null on invalid input.
/// Accepts `#rrggbb`, `#rrggbbaa`, or `#rgb`.
pub fn parseHex(hex: []const u8) ?Color {
    if (hex.len == 9 and hex[0] == '#') {
        const r = parseHexPair(hex[1], hex[2]);
        const g = parseHexPair(hex[3], hex[4]);
        const b = parseHexPair(hex[5], hex[6]);
        const a = parseHexPair(hex[7], hex[8]);
        var c = rgb8(r, g, b);
        c.a = @as(f32, @floatFromInt(a)) / 255.0;
        return c;
    }
    if (hex.len == 7 and hex[0] == '#') {
        const r = parseHexPair(hex[1], hex[2]);
        const g = parseHexPair(hex[3], hex[4]);
        const b = parseHexPair(hex[5], hex[6]);
        return rgb8(r, g, b);
    }
    if (hex.len == 4 and hex[0] == '#') {
        const r = parseHexDigit(hex[1]);
        const g = parseHexDigit(hex[2]);
        const b = parseHexDigit(hex[3]);
        return rgb8(r | (r << 4), g | (g << 4), b | (b << 4));
    }
    return null;
}

/// Create a color from HSL values.
/// - `h`: hue in degrees (0–360)
/// - `s`: saturation (0.0–1.0)
/// - `l`: lightness (0.0–1.0)
pub fn fromHsl(h: f32, s: f32, l: f32) Color {
    if (s == 0) return rgb(l, l, l);

    const q: f32 = if (l < 0.5) l * (1.0 + s) else l + s - l * s;
    const p: f32 = 2.0 * l - q;
    const h_norm = h / 360.0;

    return rgb(
        hueToRgb(p, q, h_norm + 1.0 / 3.0),
        hueToRgb(p, q, h_norm),
        hueToRgb(p, q, h_norm - 1.0 / 3.0),
    );
}

/// Create a color from Oklab L,a,b components.
/// - `L`: perceptual lightness (0.0–1.0)
/// - `a_`: green-red axis (~-0.5 to +0.5)
/// - `b_`: blue-yellow axis (~-0.5 to +0.5)
pub fn fromOklab(L: f32, a_: f32, b_: f32) Color {
    const l_ = L + 0.3963377774 * a_ + 0.2158037573 * b_;
    const m_ = L - 0.1055613458 * a_ - 0.0638541728 * b_;
    const s_ = L - 0.0894841775 * a_ - 1.2914855480 * b_;

    const l = l_ * l_ * l_;
    const m = m_ * m_ * m_;
    const s = s_ * s_ * s_;

    const r_lin = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s;
    const g_lin = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s;
    const b_lin = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s;

    return rgb(
        linearToSrgb(clamp01(r_lin)),
        linearToSrgb(clamp01(g_lin)),
        linearToSrgb(clamp01(b_lin)),
    );
}

// ════════════════════════════════════════════════════════════════════════════
// Conversion — to other formats
// ════════════════════════════════════════════════════════════════════════════

/// Convert to `#rrggbb` hex string. Works at comptime (zero allocation).
///
/// Comptime: `const hex = comptime color.toHex();` → `[7]u8` in .rodata
/// Then `&hex` coerces to `[]const u8`.
///
/// Note: Alpha is ignored — use `toHex8()` for `#rrggbbaa` when alpha < 1.0.
pub fn toHex(self: Color) [7]u8 {
    const r_byte: u8 = @intFromFloat(@round(clamp01(self.r) * 255.0));
    const g_byte: u8 = @intFromFloat(@round(clamp01(self.g) * 255.0));
    const b_byte: u8 = @intFromFloat(@round(clamp01(self.b) * 255.0));

    var buf: [7]u8 = undefined;
    buf[0] = '#';
    buf[1] = hex_lut[r_byte >> 4];
    buf[2] = hex_lut[r_byte & 0x0f];
    buf[3] = hex_lut[g_byte >> 4];
    buf[4] = hex_lut[g_byte & 0x0f];
    buf[5] = hex_lut[b_byte >> 4];
    buf[6] = hex_lut[b_byte & 0x0f];
    return buf;
}

/// Convert to `#rrggbbaa` hex string with alpha channel.
/// Works at comptime (zero allocation).
///
/// Comptime: `const hex = comptime color.withAlpha(0.5).toHex8();` → `[9]u8` in .rodata
pub fn toHex8(self: Color) [9]u8 {
    const r_byte: u8 = @intFromFloat(@round(clamp01(self.r) * 255.0));
    const g_byte: u8 = @intFromFloat(@round(clamp01(self.g) * 255.0));
    const b_byte: u8 = @intFromFloat(@round(clamp01(self.b) * 255.0));
    const a_byte: u8 = @intFromFloat(@round(clamp01(self.a) * 255.0));

    var buf: [9]u8 = undefined;
    buf[0] = '#';
    buf[1] = hex_lut[r_byte >> 4];
    buf[2] = hex_lut[r_byte & 0x0f];
    buf[3] = hex_lut[g_byte >> 4];
    buf[4] = hex_lut[g_byte & 0x0f];
    buf[5] = hex_lut[b_byte >> 4];
    buf[6] = hex_lut[b_byte & 0x0f];
    buf[7] = hex_lut[a_byte >> 4];
    buf[8] = hex_lut[a_byte & 0x0f];
    return buf;
}

/// Convert to hex string, allocated from an arena.
/// Returns `#rrggbb` for fully opaque colors, `#rrggbbaa` when alpha < 1.0.
///
/// Use in style functions: `return .{ .fill = color.toHexAlloc(ctx.arena) catch "#999" };`
pub fn toHexAlloc(self: Color, allocator: Allocator) ![]const u8 {
    if (self.a >= 1.0 - 1e-4) {
        const hex = self.toHex();
        const slice = try allocator.alloc(u8, 7);
        @memcpy(slice, &hex);
        return slice;
    } else {
        const hex = self.toHex8();
        const slice = try allocator.alloc(u8, 9);
        @memcpy(slice, &hex);
        return slice;
    }
}

/// Oklab representation: perceptual lightness + a (green-red) + b (blue-yellow).
pub const Oklab = struct { L: f32, a: f32, b: f32 };

/// Convert to Oklab color space (perceptually uniform).
pub fn toOklab(self: Color) Oklab {
    const r_lin = srgbToLinear(self.r);
    const g_lin = srgbToLinear(self.g);
    const b_lin = srgbToLinear(self.b);

    const l = 0.4122214708 * r_lin + 0.5363325363 * g_lin + 0.0514459929 * b_lin;
    const m = 0.2119034982 * r_lin + 0.6806995451 * g_lin + 0.1073969566 * b_lin;
    const s = 0.0883024619 * r_lin + 0.2220049174 * g_lin + 0.6896926358 * b_lin;

    const l_ = cbrt(l);
    const m_ = cbrt(m);
    const s_ = cbrt(s);

    return .{
        .L = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
        .a = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
        .b = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_,
    };
}

/// HSL representation: hue (0–360), saturation (0–1), lightness (0–1).
pub const Hsl = struct { h: f32, s: f32, l: f32 };

/// Convert to HSL color space.
pub fn toHsl(self: Color) Hsl {
    const max_c = @max(self.r, @max(self.g, self.b));
    const min_c = @min(self.r, @min(self.g, self.b));
    const delta = max_c - min_c;
    const l = (max_c + min_c) / 2.0;

    if (delta == 0) return .{ .h = 0, .s = 0, .l = l };

    const s: f32 = if (l < 0.5) delta / (max_c + min_c) else delta / (2.0 - max_c - min_c);

    var h: f32 = 0;
    if (max_c == self.r) {
        h = (self.g - self.b) / delta;
        if (self.g < self.b) h += 6.0;
    } else if (max_c == self.g) {
        h = (self.b - self.r) / delta + 2.0;
    } else {
        h = (self.r - self.g) / delta + 4.0;
    }
    h *= 60.0;

    return .{ .h = h, .s = s, .l = l };
}

// ════════════════════════════════════════════════════════════════════════════
// Operations — produce new colors
// ════════════════════════════════════════════════════════════════════════════

/// Interpolate between two colors in Oklab space (perceptually uniform).
/// `t = 0.0` → self, `t = 1.0` → other.
pub fn lerp(self: Color, other: Color, t: f32) Color {
    const a = self.toOklab();
    const b = other.toOklab();
    const ct = clamp01(t);

    return fromOklab(
        a.L + (b.L - a.L) * ct,
        a.a + (b.a - a.a) * ct,
        a.b + (b.b - a.b) * ct,
    ).withAlpha(self.a + (other.a - self.a) * ct);
}

/// Darken the color by `amount` (0.0 = no change, 1.0 = black).
/// Operates in Oklab space for perceptual uniformity.
pub fn darken(self: Color, amount: f32) Color {
    const lab = self.toOklab();
    return fromOklab(lab.L * (1.0 - clamp01(amount)), lab.a, lab.b).withAlpha(self.a);
}

/// Lighten the color by `amount` (0.0 = no change, 1.0 = white).
/// Operates in Oklab space for perceptual uniformity.
pub fn lighten(self: Color, amount: f32) Color {
    const lab = self.toOklab();
    const new_L = lab.L + (1.0 - lab.L) * clamp01(amount);
    return fromOklab(new_L, lab.a, lab.b).withAlpha(self.a);
}

/// Desaturate the color by `amount` (0.0 = no change, 1.0 = fully gray).
/// Operates in HSL space.
pub fn desaturate(self: Color, amount: f32) Color {
    const hsl = self.toHsl();
    return fromHsl(hsl.h, hsl.s * (1.0 - clamp01(amount)), hsl.l).withAlpha(self.a);
}

/// Saturate the color by `amount` (0.0 = no change, 1.0 = max saturation).
/// Operates in HSL space.
pub fn saturate(self: Color, amount: f32) Color {
    const hsl = self.toHsl();
    const new_s = hsl.s + (1.0 - hsl.s) * clamp01(amount);
    return fromHsl(hsl.h, new_s, hsl.l).withAlpha(self.a);
}

/// Set the alpha channel.
pub fn withAlpha(self: Color, a: f32) Color {
    return .{ .r = self.r, .g = self.g, .b = self.b, .a = clamp01(a) };
}

// ════════════════════════════════════════════════════════════════════════════
// Named colors
// ════════════════════════════════════════════════════════════════════════════

pub const black = rgb(0, 0, 0);
pub const white = rgb(1, 1, 1);
pub const transparent = rgba(0, 0, 0, 0);

// ════════════════════════════════════════════════════════════════════════════
// Internal helpers
// ════════════════════════════════════════════════════════════════════════════

const hex_lut = "0123456789abcdef";

fn clamp01(v: f32) f32 {
    return @max(0.0, @min(1.0, v));
}

fn srgbToLinear(c: f32) f32 {
    @setEvalBranchQuota(10000);
    if (c <= 0.04045) return c / 12.92;
    return math.pow(f32, (c + 0.055) / 1.055, 2.4);
}

fn linearToSrgb(c: f32) f32 {
    @setEvalBranchQuota(10000);
    if (c <= 0.0031308) return c * 12.92;
    return 1.055 * math.pow(f32, c, 1.0 / 2.4) - 0.055;
}

fn cbrt(x: f32) f32 {
    @setEvalBranchQuota(10000);
    if (x == 0) return 0;
    if (x > 0) return math.pow(f32, x, 1.0 / 3.0);
    return -math.pow(f32, -x, 1.0 / 3.0);
}

fn hueToRgb(p: f32, q: f32, t_in: f32) f32 {
    var t = t_in;
    if (t < 0) t += 1.0;
    if (t > 1) t -= 1.0;
    if (t < 1.0 / 6.0) return p + (q - p) * 6.0 * t;
    if (t < 1.0 / 2.0) return q;
    if (t < 2.0 / 3.0) return p + (q - p) * (2.0 / 3.0 - t) * 6.0;
    return p;
}

fn parseHexDigit(c: u8) u8 {
    if (c >= '0' and c <= '9') return c - '0';
    if (c >= 'a' and c <= 'f') return c - 'a' + 10;
    if (c >= 'A' and c <= 'F') return c - 'A' + 10;
    return 0;
}

fn parseHexPair(hi: u8, lo: u8) u8 {
    return (parseHexDigit(hi) << 4) | parseHexDigit(lo);
}

// ════════════════════════════════════════════════════════════════════════════
// Tests
// ════════════════════════════════════════════════════════════════════════════

test "fromHex and toHex round-trip" {
    const cases = [_][]const u8{ "#000000", "#ffffff", "#3b82f6", "#e54d2e", "#30a46c" };
    for (cases) |hex| {
        const c = fromHex(hex);
        const result = c.toHex();
        try std.testing.expectEqualStrings(hex, &result);
    }
}

test "fromHex short form (#rgb)" {
    const c = fromHex("#f00");
    try std.testing.expectEqualStrings("#ff0000", &c.toHex());

    const c2 = fromHex("#abc");
    try std.testing.expectEqualStrings("#aabbcc", &c2.toHex());
}

test "fromHex invalid input returns black" {
    const c = fromHex("invalid");
    try std.testing.expectEqualStrings("#000000", &c.toHex());
}

test "comptime hex generation" {
    const hex = comptime fromHex("#3b82f6").toHex();
    try std.testing.expectEqualStrings("#3b82f6", &hex);

    // Comptime color math → hex in .rodata
    const dark = comptime fromHex("#3b82f6").darken(0.3).toHex();
    try std.testing.expect(dark[0] == '#');
    // Should be darker (lower hex values for R, G)
}

test "comptime lerp" {
    const mid = comptime fromHex("#000000").lerp(fromHex("#ffffff"), 0.5).toHex();
    // Oklab midpoint of black→white should be a gray
    // All three channels should be equal (neutral gray)
    const r = parseHexPair(mid[1], mid[2]);
    const g = parseHexPair(mid[3], mid[4]);
    const b = parseHexPair(mid[5], mid[6]);
    try std.testing.expect(r == g and g == b); // must be neutral
    try std.testing.expect(r > 50 and r < 230); // some kind of gray
}

test "black and white Oklab round-trip" {
    const b = Color.black.toOklab();
    try std.testing.expect(@abs(b.L) < 0.01);

    const w = Color.white.toOklab();
    try std.testing.expect(@abs(w.L - 1.0) < 0.01);
    try std.testing.expect(@abs(w.a) < 0.01);
    try std.testing.expect(@abs(w.b) < 0.01);
}

test "HSL round-trip" {
    const cases = [_]Color{
        fromHex("#ff0000"), // pure red
        fromHex("#00ff00"), // pure green
        fromHex("#0000ff"), // pure blue
        fromHex("#808080"), // gray
    };
    for (cases) |c| {
        const hsl = c.toHsl();
        const back = fromHsl(hsl.h, hsl.s, hsl.l);
        try std.testing.expect(@abs(c.r - back.r) < 0.02);
        try std.testing.expect(@abs(c.g - back.g) < 0.02);
        try std.testing.expect(@abs(c.b - back.b) < 0.02);
    }
}

test "darken and lighten" {
    const c = fromHex("#3b82f6");
    const darker = c.darken(0.5);
    const lighter = c.lighten(0.5);

    const c_lab = c.toOklab();
    const d_lab = darker.toOklab();
    const l_lab = lighter.toOklab();

    try std.testing.expect(d_lab.L < c_lab.L); // darker has lower lightness
    try std.testing.expect(l_lab.L > c_lab.L); // lighter has higher lightness
}

test "lerp boundaries" {
    const c1 = fromHex("#ff0000");
    const c2 = fromHex("#0000ff");

    // t=0 → should be very close to c1
    const at0 = c1.lerp(c2, 0.0);
    try std.testing.expect(@abs(at0.r - c1.r) < 0.02);

    // t=1 → should be very close to c2
    const at1 = c1.lerp(c2, 1.0);
    try std.testing.expect(@abs(at1.b - c2.b) < 0.02);
}

test "withAlpha preserves color" {
    const c = fromHex("#3b82f6");
    const semi = c.withAlpha(0.5);
    try std.testing.expect(@abs(semi.r - c.r) < 0.001);
    try std.testing.expect(@abs(semi.g - c.g) < 0.001);
    try std.testing.expect(@abs(semi.b - c.b) < 0.001);
    try std.testing.expect(@abs(semi.a - 0.5) < 0.001);
}

test "toHexAlloc runtime" {
    var buf: [256]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const alloc = fba.allocator();

    const c = fromHex("#3b82f6");
    const hex = try c.toHexAlloc(alloc);
    try std.testing.expectEqualStrings("#3b82f6", hex);
}

test "toHex8 with alpha" {
    const c = comptime fromHex("#3b82f6").withAlpha(0.5);
    const hex8 = comptime c.toHex8();
    try std.testing.expectEqual(@as(usize, 9), hex8.len);
    try std.testing.expectEqual(@as(u8, '#'), hex8[0]);
    // Alpha 0.5 → ~128 → 0x80
    try std.testing.expectEqualStrings("#3b82f680", &hex8);
}

test "toHexAlloc auto-picks 6 vs 8 digit" {
    var buf: [256]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const alloc = fba.allocator();

    // Opaque → 7 chars (#rrggbb)
    const opaque_hex = try fromHex("#ff0000").toHexAlloc(alloc);
    try std.testing.expectEqual(@as(usize, 7), opaque_hex.len);

    // Semi-transparent → 9 chars (#rrggbbaa)
    const semi_hex = try fromHex("#ff0000").withAlpha(0.5).toHexAlloc(alloc);
    try std.testing.expectEqual(@as(usize, 9), semi_hex.len);
}

test "fromHex parses 8-digit hex with alpha" {
    const c = fromHex("#3b82f680");
    try std.testing.expect(@abs(c.r - 0.231) < 0.01);
    try std.testing.expect(@abs(c.g - 0.510) < 0.01);
    try std.testing.expect(@abs(c.b - 0.965) < 0.01);
    try std.testing.expect(@abs(c.a - 0.502) < 0.01);
}

test "rgb8 constructor" {
    const c = rgb8(255, 128, 0);
    try std.testing.expect(@abs(c.r - 1.0) < 0.005);
    try std.testing.expect(@abs(c.g - 0.502) < 0.005);
    try std.testing.expect(@abs(c.b) < 0.005);
}

test "parseHex returns null for invalid input" {
    try std.testing.expect(parseHex("invalid") == null);
    try std.testing.expect(parseHex("") == null);
    try std.testing.expect(parseHex("#gg0000") != null); // parseHexDigit returns 0 for invalid digits
}

test "parseHex returns color for valid input" {
    const c = parseHex("#ff0000") orelse unreachable;
    try std.testing.expect(@abs(c.r - 1.0) < 0.005);
    try std.testing.expect(@abs(c.g) < 0.005);
    try std.testing.expect(@abs(c.b) < 0.005);
}
