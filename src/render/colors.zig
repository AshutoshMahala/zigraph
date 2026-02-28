//! Color Palettes for Graph Visualization
//!
//! **This file is a backward-compatibility re-export.**
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

// Re-export everything from the new color module.
// Internal imports (`@import("colors.zig")` from svg/config.zig and unicode.zig)
// see the same public API as before.
pub usingnamespace @import("color/mod.zig");
