//! Color Palettes for Graph Visualization
//!
//! **This file is a backward-compatibility shim.**
//! All functionality now lives in `color/` (Color struct, colormaps, palettes, gradients).
//!
//! Existing code using `colors.get(&colors.radix, i)` continues to work unchanged.
//! New code should prefer `@import("color/mod.zig")` for the full API.
//!
//! ## Usage
//!
//! ```zig
//! const colors = @import("zigraph").colors;
//!
//! // Use a built-in palette (unchanged)
//! const palette = colors.radix;
//! const edge_color = colors.get(palette, edge_index);
//!
//! // New: numeric color math
//! const color = @import("zigraph").color;
//! const c = color.Color.fromHex("#3b82f6").darken(0.3);
//! const hex = c.toHexAlloc(arena) catch "#999";
//! ```

// Explicit re-exports from color/mod.zig — avoids `usingnamespace` which
// was removed in Zig 0.11+. Each symbol is forwarded individually so that
// old code importing `colors.get(...)` or `colors.radix` keeps working.
const mod = @import("color/mod.zig");

// Types
pub const Color = mod.Color;
pub const colormaps = mod.colormaps;
pub const ColorMap = mod.ColorMap;
pub const gradient = mod.gradient;
pub const RadialConfig = mod.RadialConfig;
pub const palettes = mod.palettes;

// Palette accessor functions
pub const get = mod.get;
pub const getAnsi = mod.getAnsi;
pub const isValidHex = mod.isValidHex;
pub const hexToAnsi256 = mod.hexToAnsi256;
pub const escape = mod.escape;

// Palette arrays
pub const radix = mod.radix;
pub const vibrant = mod.vibrant;
pub const monochrome = mod.monochrome;
pub const pastel = mod.pastel;
pub const dark_mode = mod.dark_mode;
pub const colorblind_safe = mod.colorblind_safe;
pub const categorical = mod.categorical;
pub const semantic = mod.semantic;
pub const Scale = mod.Scale;
pub const scale = mod.scale;
pub const ansi = mod.ansi;
pub const ansi_dark = mod.ansi_dark;
pub const ansi_light = mod.ansi_light;
