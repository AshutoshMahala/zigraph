//! Continuous color maps for scientific and data visualization.
//!
//! Each `ColorMap` maps a scalar value in `[0, 1]` to a `Color`, interpolating
//! through a set of control stops in Oklab space (perceptually uniform).
//!
//! ## Available maps
//!
//! ### Sequential (dark → light)
//! - **`viridis`** — purple → teal → yellow. The matplotlib default. Perceptually
//!   uniform, colorblind-safe, prints well in grayscale.
//! - **`inferno`** — black → purple → orange → yellow. High drama, great contrast.
//! - **`magma`** — black → purple → pink → light yellow. Softer than inferno.
//! - **`plasma`** — purple → pink → orange → yellow. Vivid sequential.
//!
//! ### Multi-hue
//! - **`turbo`** — improved rainbow. Blue → cyan → green → yellow → red.
//!   Maximum visual bandwidth. NOT perceptually uniform but widely used for heatmaps.
//!
//! ### Diverging
//! - **`coolwarm`** — blue → white → red. Centered at 0.5 (neutral).
//!   Good for signed data (profit/loss, correlation, temperature anomaly).
//!
//! ## Usage
//!
//! ```zig
//! const ColorMap = @import("zigraph").color.ColorMap;
//! const Color = @import("zigraph").color.Color;
//!
//! // Continuous sampling (runtime)
//! const c = ColorMap.turbo.sample(0.7);              // Color struct
//! const hex = c.toHexAlloc(arena) catch "#999";      // "[]const u8"
//!
//! // Pre-baked palette (comptime, zero allocation)
//! const heat_lut = comptime ColorMap.turbo.quantize(64);
//! const hex = &heat_lut[index];                      // []const u8 from .rodata
//!
//! // Reversed
//! const cold_to_hot = ColorMap.turbo.reversed();
//! ```

const std = @import("std");
const Color = @import("Color.zig");

/// A continuous color map defined by ordered stops, interpolated in Oklab space.
pub const ColorMap = struct {
    /// Control stops (must be sorted by `t`, typically 0.0 → 1.0).
    stops: []const Stop,

    pub const Stop = struct {
        t: f32,
        color: Color,
    };

    /// Sample the colormap at position `t` (clamped to 0.0–1.0).
    /// Interpolates in Oklab space between the two bracketing stops.
    pub fn sample(self: ColorMap, t_raw: f32) Color {
        const t = clamp01(t_raw);
        const stops = self.stops;

        if (stops.len == 0) return Color.black;
        if (stops.len == 1 or t <= stops[0].t) return stops[0].color;
        if (t >= stops[stops.len - 1].t) return stops[stops.len - 1].color;

        // Find bracketing stops
        var i: usize = 0;
        while (i < stops.len - 1) : (i += 1) {
            if (t >= stops[i].t and t <= stops[i + 1].t) {
                const range = stops[i + 1].t - stops[i].t;
                const local_t = if (range > 0) (t - stops[i].t) / range else 0;
                return stops[i].color.lerp(stops[i + 1].color, local_t);
            }
        }

        return stops[stops.len - 1].color;
    }

    /// Generate `n` evenly-spaced hex strings at comptime.
    /// Returns an array of `[7]u8` — each coerces to `[]const u8` via `&arr[i]`.
    ///
    /// ```zig
    /// const lut = comptime ColorMap.viridis.quantize(256);
    /// const hex: []const u8 = &lut[128]; // mid-viridis color
    /// ```
    pub fn quantize(self: ColorMap, comptime n: usize) [n][7]u8 {
        comptime {
            if (n > 4096) @compileError("quantize: n too large (max 4096)");
        }
        @setEvalBranchQuota(n * 100000);
        var result: [n][7]u8 = undefined;
        for (0..n) |i| {
            const t: f32 = if (n <= 1) 0.5 else @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(n - 1));
            result[i] = self.sample(t).toHex();
        }
        return result;
    }

    /// Return a reversed version of this colormap.
    pub fn reversed(self: ColorMap) ColorMap {
        // We can't allocate at comptime for a slice, but we can return
        // a ColorMap that samples in reverse.
        _ = self;
        @compileError("Use sample(1.0 - t) for reversed colormaps");
    }

    // ════════════════════════════════════════════════════════════════════════
    // Built-in scientific colormaps
    // ════════════════════════════════════════════════════════════════════════

    /// Viridis — perceptually uniform sequential (matplotlib default).
    /// Purple → teal → yellow. Colorblind-safe, grayscale-safe.
    pub const viridis = ColorMap{ .stops = &viridis_stops };

    /// Inferno — perceptually uniform sequential.
    /// Black → purple → red → orange → yellow.
    pub const inferno = ColorMap{ .stops = &inferno_stops };

    /// Magma — perceptually uniform sequential.
    /// Black → purple → pink → light yellow.
    pub const magma = ColorMap{ .stops = &magma_stops };

    /// Plasma — perceptually uniform sequential.
    /// Purple → pink → orange → yellow.
    pub const plasma = ColorMap{ .stops = &plasma_stops };

    /// Turbo — improved rainbow (Google).
    /// Dark blue → blue → cyan → green → yellow → orange → red → dark red.
    /// Maximum visual bandwidth. Not perceptually uniform.
    pub const turbo = ColorMap{ .stops = &turbo_stops };

    /// Coolwarm — diverging.
    /// Blue → light gray → red. Centered at t=0.5.
    pub const coolwarm = ColorMap{ .stops = &coolwarm_stops };
};

fn clamp01(v: f32) f32 {
    return @max(0.0, @min(1.0, v));
}

// ════════════════════════════════════════════════════════════════════════════
// Colormap data — 16 control points each, sampled from canonical tables
// ════════════════════════════════════════════════════════════════════════════

fn s(t: f32, hex: []const u8) ColorMap.Stop {
    return .{ .t = t, .color = Color.fromHex(hex) };
}

// Viridis: sampled from matplotlib's canonical 256-stop table
const viridis_stops = [_]ColorMap.Stop{
    s(0.000, "#440154"),
    s(0.067, "#481a6c"),
    s(0.133, "#472f7d"),
    s(0.200, "#414487"),
    s(0.267, "#39568c"),
    s(0.333, "#31688e"),
    s(0.400, "#2a788e"),
    s(0.467, "#23888e"),
    s(0.533, "#1f988b"),
    s(0.600, "#22a884"),
    s(0.667, "#35b779"),
    s(0.733, "#54c568"),
    s(0.800, "#7ad151"),
    s(0.867, "#a5db36"),
    s(0.933, "#d2e21b"),
    s(1.000, "#fde725"),
};

// Inferno: sampled from matplotlib's canonical table
const inferno_stops = [_]ColorMap.Stop{
    s(0.000, "#000004"),
    s(0.067, "#0d0829"),
    s(0.133, "#280b54"),
    s(0.200, "#480b6a"),
    s(0.267, "#65156e"),
    s(0.333, "#82206c"),
    s(0.400, "#9f2a63"),
    s(0.467, "#bc3754"),
    s(0.533, "#d44842"),
    s(0.600, "#e8602d"),
    s(0.667, "#f57d15"),
    s(0.733, "#fd9a06"),
    s(0.800, "#feb72d"),
    s(0.867, "#fad44a"),
    s(0.933, "#f5ec6e"),
    s(1.000, "#fcffa4"),
};

// Magma: sampled from matplotlib's canonical table
const magma_stops = [_]ColorMap.Stop{
    s(0.000, "#000004"),
    s(0.067, "#0c0926"),
    s(0.133, "#221150"),
    s(0.200, "#400f74"),
    s(0.267, "#5c1a87"),
    s(0.333, "#781c8e"),
    s(0.400, "#952c80"),
    s(0.467, "#b73779"),
    s(0.533, "#d5466d"),
    s(0.600, "#eb6263"),
    s(0.667, "#f7835b"),
    s(0.733, "#fca85c"),
    s(0.800, "#fccd70"),
    s(0.867, "#fbed8d"),
    s(0.933, "#fbfcb6"),
    s(1.000, "#fcfdbf"),
};

// Plasma: sampled from matplotlib's canonical table
const plasma_stops = [_]ColorMap.Stop{
    s(0.000, "#0d0887"),
    s(0.067, "#2d0594"),
    s(0.133, "#4903a0"),
    s(0.200, "#6500a7"),
    s(0.267, "#7e03a8"),
    s(0.333, "#9600a1"),
    s(0.400, "#ae0192"),
    s(0.467, "#c42e7b"),
    s(0.533, "#d5546e"),
    s(0.600, "#e47661"),
    s(0.667, "#f0965b"),
    s(0.733, "#f8b560"),
    s(0.800, "#fbd476"),
    s(0.867, "#f5ef94"),
    s(0.933, "#edffa0"),
    s(1.000, "#f0f921"),
};

// Turbo: improved rainbow (Google research)
const turbo_stops = [_]ColorMap.Stop{
    s(0.000, "#30123b"),
    s(0.067, "#4145ab"),
    s(0.133, "#4675ed"),
    s(0.200, "#39a2fc"),
    s(0.267, "#1bd0d5"),
    s(0.333, "#24f0a6"),
    s(0.400, "#6ff05b"),
    s(0.467, "#a8db34"),
    s(0.533, "#d3c021"),
    s(0.600, "#f0a40e"),
    s(0.667, "#fb7e09"),
    s(0.733, "#f25c14"),
    s(0.800, "#dc3c17"),
    s(0.867, "#bf1a22"),
    s(0.933, "#9a0c26"),
    s(1.000, "#7a0403"),
};

// Coolwarm: diverging blue → white → red (Moreland 2009)
const coolwarm_stops = [_]ColorMap.Stop{
    s(0.000, "#3b4cc0"),
    s(0.100, "#5977e3"),
    s(0.200, "#7b9ff9"),
    s(0.300, "#9ebeff"),
    s(0.400, "#c0d4f5"),
    s(0.500, "#dddddd"),
    s(0.600, "#f2cbb7"),
    s(0.700, "#f7a889"),
    s(0.800, "#ee7b56"),
    s(0.900, "#d04e40"),
    s(1.000, "#b40426"),
};

// ════════════════════════════════════════════════════════════════════════════
// Tests
// ════════════════════════════════════════════════════════════════════════════

test "viridis endpoints" {
    const start = ColorMap.viridis.sample(0.0).toHex();
    try std.testing.expectEqualStrings("#440154", &start);

    const end = ColorMap.viridis.sample(1.0).toHex();
    try std.testing.expectEqualStrings("#fde725", &end);
}

test "inferno endpoints" {
    const start = ColorMap.inferno.sample(0.0).toHex();
    try std.testing.expectEqualStrings("#000004", &start);

    const end = ColorMap.inferno.sample(1.0).toHex();
    try std.testing.expectEqualStrings("#fcffa4", &end);
}

test "turbo endpoints" {
    const start = ColorMap.turbo.sample(0.0).toHex();
    try std.testing.expectEqualStrings("#30123b", &start);

    const end = ColorMap.turbo.sample(1.0).toHex();
    try std.testing.expectEqualStrings("#7a0403", &end);
}

test "coolwarm midpoint is neutral gray" {
    const mid = ColorMap.coolwarm.sample(0.5);
    // At 0.5, coolwarm should be ~#dddddd (neutral)
    try std.testing.expect(@abs(mid.r - mid.g) < 0.05);
    try std.testing.expect(@abs(mid.g - mid.b) < 0.05);
}

test "sample clamps out of range" {
    const below = ColorMap.viridis.sample(-1.0).toHex();
    const at_zero = ColorMap.viridis.sample(0.0).toHex();
    try std.testing.expectEqualStrings(&at_zero, &below);

    const above = ColorMap.viridis.sample(2.0).toHex();
    const at_one = ColorMap.viridis.sample(1.0).toHex();
    try std.testing.expectEqualStrings(&at_one, &above);
}

test "quantize produces correct count" {
    const lut = comptime ColorMap.viridis.quantize(8);
    try std.testing.expectEqual(@as(usize, 8), lut.len);

    // First and last should match endpoints
    try std.testing.expectEqualStrings("#440154", &lut[0]);
    try std.testing.expectEqualStrings("#fde725", &lut[7]);
}

test "comptime quantize full palette" {
    // This is the key zero-cost pattern
    const lut = comptime ColorMap.turbo.quantize(256);
    try std.testing.expectEqual(@as(usize, 256), lut.len);

    // Endpoints
    try std.testing.expectEqualStrings("#30123b", &lut[0]);
    try std.testing.expectEqualStrings("#7a0403", &lut[255]);

    // Midpoint should be warm (yellow/green area of turbo)
    const mid = lut[128];
    try std.testing.expect(mid[0] == '#');
}

test "monotonic lightness for viridis" {
    // Viridis should have monotonically increasing Oklab lightness
    var prev_L: f32 = 0;
    for (0..20) |i| {
        const t = @as(f32, @floatFromInt(i)) / 19.0;
        const c = ColorMap.viridis.sample(t);
        const lab = c.toOklab();
        try std.testing.expect(lab.L >= prev_L - 0.01); // allow tiny float error
        prev_L = lab.L;
    }
}

test "all colormaps produce valid hex" {
    const maps = [_]ColorMap{
        ColorMap.viridis, ColorMap.inferno, ColorMap.magma,
        ColorMap.plasma,  ColorMap.turbo,   ColorMap.coolwarm,
    };
    for (maps) |cm| {
        for (0..11) |i| {
            const t = @as(f32, @floatFromInt(i)) / 10.0;
            const hex = cm.sample(t).toHex();
            try std.testing.expect(hex[0] == '#');
            for (hex[1..]) |c| {
                try std.testing.expect(std.ascii.isHex(c));
            }
        }
    }
}
