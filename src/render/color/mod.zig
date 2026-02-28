//! Color system for zigraph — numeric color math + scientific colormaps.
//!
//! ## Module structure
//!
//! - `Color`     — RGBA struct with sRGB ↔ Oklab ↔ HSL conversions, lerp, darken/lighten
//! - `ColorMap`  — Continuous 0→1 maps (viridis, inferno, turbo, coolwarm, …)
//! - `gradient`  — SVG `<linearGradient>` / `<radialGradient>` generation
//! - `palettes`  — Discrete hex palettes (radix, vibrant, …) + ANSI codes
//!
//! ## Quick start
//!
//! ```zig
//! const color = @import("zigraph").color;
//! const Color = color.Color;
//! const ColorMap = color.ColorMap;
//!
//! // Comptime: zero-cost hex string in .rodata
//! const teal = comptime Color.fromHex("#12a594").darken(0.2).toHex();
//!
//! // Comptime: pre-baked 64-stop turbo palette
//! const heat_lut = comptime ColorMap.turbo.quantize(64);
//!
//! // Runtime: sample continuous colormap
//! const c = ColorMap.viridis.sample(0.7);
//! const hex = c.toHexAlloc(ctx.arena) catch "#999";
//! ```

pub const Color = @import("Color.zig");
pub const colormaps = @import("colormaps.zig");
pub const ColorMap = colormaps.ColorMap;
pub const gradient = @import("gradient.zig");
pub const palettes = @import("palettes.zig");

// Re-export frequently used palette functions at module level\n// so `zigraph.color.get(&zigraph.color.radix, i)` works directly.
pub const get = palettes.get;
pub const getAnsi = palettes.getAnsi;
pub const isValidHex = palettes.isValidHex;
pub const hexToAnsi256 = palettes.hexToAnsi256;
pub const escape = palettes.escape;

// Re-export all palette arrays at module level.
pub const radix = palettes.radix;
pub const vibrant = palettes.vibrant;
pub const monochrome = palettes.monochrome;
pub const pastel = palettes.pastel;
pub const dark_mode = palettes.dark_mode;
pub const colorblind_safe = palettes.colorblind_safe;
pub const categorical = palettes.categorical;
pub const semantic = palettes.semantic;
pub const ansi = palettes.ansi;
pub const ansi_dark = palettes.ansi_dark;
pub const ansi_light = palettes.ansi_light;

// ── Comptime test inclusion ────────────────────────────────────────────────
comptime {
    _ = Color;
    _ = colormaps;
    _ = gradient;
    _ = palettes;
}
