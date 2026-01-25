//! Color Palettes for Graph Visualization
//!
//! Provides pre-defined color palettes for edge and node coloring.
//! These can be used by any renderer (SVG, JSON, HTML, etc.)
//!
//! ## Usage
//!
//! ```zig
//! const colors = @import("zigraph").colors;
//!
//! // Use a built-in palette
//! const palette = colors.radix;
//!
//! // Get color by index (cycles through palette)
//! const edge_color = colors.get(palette, edge_index);
//!
//! // Or use your own custom palette
//! const my_palette = [_][]const u8{ "#ff0000", "#00ff00", "#0000ff" };
//! const color = colors.get(&my_palette, index);
//! ```

const std = @import("std");

/// Get a color from a palette by index (cycles through palette)
pub fn get(palette: []const []const u8, index: usize) []const u8 {
    return palette[index % palette.len];
}

// ============================================================================
// Built-in Palettes
// ============================================================================

/// Radix UI Colors (shade 9) - Professional, balanced saturation
/// Best for: dashboards, documentation, professional reports
/// https://www.radix-ui.com/colors
pub const radix = [_][]const u8{
    "#3e63dd", // Blue
    "#e54d2e", // Tomato
    "#30a46c", // Green
    "#f76b15", // Orange
    "#8e4ec6", // Purple
    "#12a594", // Teal
    "#e93d82", // Pink
    "#ffe629", // Yellow
    "#7ce2fe", // Sky
    "#f5d90a", // Amber
    "#89ddff", // Cyan
    "#d6409f", // Plum
    "#46a758", // Grass
    "#6e56cf", // Violet
    "#e5484d", // Red
    "#0090ff", // Blue bright
};

/// Vibrant saturated colors - High contrast, attention-grabbing
/// Best for: presentations, marketing materials, accessibility
pub const vibrant = [_][]const u8{
    "#e6194b", // Red
    "#3cb44b", // Green
    "#4363d8", // Blue
    "#f58231", // Orange
    "#911eb4", // Purple
    "#42d4f4", // Cyan
    "#f032e6", // Magenta
    "#bfef45", // Lime
    "#fabed4", // Pink
    "#469990", // Teal
    "#dcbeff", // Lavender
    "#9a6324", // Brown
};

/// Monochrome blue/gray - Formal, understated
/// Best for: academic papers, formal documentation, print
pub const monochrome = [_][]const u8{
    "#1e3a5f", // Dark navy
    "#3d5a80", // Steel blue
    "#5c7a99", // Slate
    "#7b9ab3", // Cadet blue
    "#9ab8cc", // Light steel
    "#2c4a6b", // Prussian
    "#4a6a8a", // Air force blue
    "#6889a9", // Shadow blue
};

/// Pastel soft colors - Gentle, calming
/// Best for: educational materials, light themes
pub const pastel = [_][]const u8{
    "#a8dadc", // Powder blue
    "#f4a261", // Sandy brown
    "#e9c46a", // Saffron
    "#2a9d8f", // Persian green
    "#e76f51", // Burnt sienna
    "#b5838d", // Puce
    "#6d6875", // Old lavender
    "#e5989b", // Shimmering blush
    "#b8c0ff", // Periwinkle
    "#ffd6ff", // Pink lace
};

/// Dark mode optimized - Works well on dark backgrounds
/// Best for: dark theme UIs, terminal visualizations
pub const dark_mode = [_][]const u8{
    "#5ccfe6", // Cyan
    "#bae67e", // Lime
    "#ffd580", // Peach
    "#d4bfff", // Lavender
    "#f28779", // Salmon
    "#73d0ff", // Sky blue
    "#95e6cb", // Mint
    "#ffcc66", // Amber
    "#f29e74", // Apricot
    "#dfbfff", // Mauve
};

/// Colorblind-safe palette (Okabe-Ito)
/// Best for: accessibility, scientific publications
/// https://jfly.uni-koeln.de/color/
pub const colorblind_safe = [_][]const u8{
    "#0072b2", // Blue
    "#e69f00", // Orange
    "#009e73", // Bluish green
    "#cc79a7", // Reddish purple
    "#56b4e9", // Sky blue
    "#d55e00", // Vermillion
    "#f0e442", // Yellow
    "#000000", // Black
};

/// Categorical (D3/Tableau inspired) - Maximally distinct
/// Best for: many categories that need to be distinguishable
pub const categorical = [_][]const u8{
    "#4e79a7", // Steel blue
    "#f28e2c", // Orange
    "#e15759", // Red
    "#76b7b2", // Teal
    "#59a14f", // Green
    "#edc949", // Yellow
    "#af7aa1", // Purple
    "#ff9da7", // Pink
    "#9c755f", // Brown
    "#bab0ab", // Gray
};

// ============================================================================
// Semantic Colors (for specific meanings)
// ============================================================================

/// Semantic colors for status/meaning-based coloring
pub const semantic = struct {
    pub const success = "#30a46c"; // Green
    pub const warning = "#f76b15"; // Orange
    pub const error_ = "#e5484d"; // Red (error is reserved keyword)
    pub const info = "#3e63dd"; // Blue
    pub const neutral = "#666666"; // Gray
    pub const highlight = "#ffe629"; // Yellow
};

// ============================================================================
// ANSI Terminal Colors (256-color palette)
// ============================================================================

/// ANSI 256-color codes optimized for terminal edge coloring
/// These are pre-selected to look good on both light and dark terminals
pub const ansi = [_]u8{
    39,  // Blue
    203, // Red/Tomato
    35,  // Green
    208, // Orange
    134, // Purple
    37,  // Teal/Cyan
    205, // Pink
    220, // Yellow
    81,  // Sky blue
    214, // Amber
    123, // Light cyan
    170, // Plum
    71,  // Grass green
    99,  // Violet
    196, // Bright red
    33,  // Bright blue
};

/// ANSI palette optimized for dark terminals (brighter colors)
pub const ansi_dark = [_]u8{
    81,  // Bright cyan
    156, // Lime green
    222, // Peach/lightorange
    183, // Lavender
    210, // Salmon/light red
    117, // Sky blue
    121, // Mint
    221, // Amber
    216, // Apricot
    189, // Mauve
    87,  // Turquoise
    147, // Light purple
};

/// ANSI palette optimized for light terminals (darker colors)
pub const ansi_light = [_]u8{
    27,  // Dark blue
    124, // Dark red
    22,  // Dark green
    166, // Dark orange
    91,  // Dark purple
    30,  // Dark teal
    125, // Dark pink
    136, // Dark yellow
    24,  // Dark steel blue
    130, // Brown
    23,  // Dark cyan
    54,  // Dark violet
};

/// Get an ANSI color code from the palette by index (cycles through)
pub fn getAnsi(palette: []const u8, index: usize) u8 {
    return palette[index % palette.len];
}

/// Convert hex color string to approximate ANSI 256-color code
/// Uses color cube (16-231) and grayscale (232-255) ranges
pub fn hexToAnsi256(hex: []const u8) u8 {
    // Parse hex color
    if (hex.len != 7 or hex[0] != '#') return 7; // Default white

    const r = std.fmt.parseInt(u8, hex[1..3], 16) catch return 7;
    const g = std.fmt.parseInt(u8, hex[3..5], 16) catch return 7;
    const b = std.fmt.parseInt(u8, hex[5..7], 16) catch return 7;

    // Check if grayscale (r ≈ g ≈ b)
    const max_diff = @max(@max(
        if (r > g) r - g else g - r,
        if (g > b) g - b else b - g,
    ), if (r > b) r - b else b - r);

    if (max_diff < 20) {
        // Grayscale: map to 232-255 (24 shades)
        const avg = (@as(u16, r) + @as(u16, g) + @as(u16, b)) / 3;
        if (avg < 8) return 16; // Black
        if (avg > 248) return 231; // White
        return @intCast(232 + (avg - 8) / 10);
    }

    // Color cube: 6x6x6 (codes 16-231)
    // Each component maps to 0-5
    const r6: u8 = if (r < 48) 0 else if (r < 115) 1 else @intCast((r - 35) / 40);
    const g6: u8 = if (g < 48) 0 else if (g < 115) 1 else @intCast((g - 35) / 40);
    const b6: u8 = if (b < 48) 0 else if (b < 115) 1 else @intCast((b - 35) / 40);

    return 16 + @as(u8, 36) * @min(r6, 5) + @as(u8, 6) * @min(g6, 5) + @min(b6, 5);
}

/// ANSI escape sequence helpers
pub const escape = struct {
    /// Reset all formatting
    pub const reset = "\x1b[0m";

    /// Format foreground color using 256-color palette
    /// Returns a comptime-known format string for runtime color value
    pub fn fg256(color: u8) [11]u8 {
        var buf: [11]u8 = undefined;
        _ = std.fmt.bufPrint(&buf, "\x1b[38;5;{d:0>3}m", .{color}) catch unreachable;
        return buf;
    }
};

// ============================================================================
// Utility Functions
// ============================================================================

/// Check if a color string is valid hex format (#RGB or #RRGGBB)
pub fn isValidHex(color: []const u8) bool {
    if (color.len != 4 and color.len != 7) return false;
    if (color[0] != '#') return false;
    for (color[1..]) |c| {
        if (!std.ascii.isHex(c)) return false;
    }
    return true;
}

// ============================================================================
// Tests
// ============================================================================

test "get cycles through palette" {
    const palette = [_][]const u8{ "#aa", "#bb", "#cc" };
    try std.testing.expectEqualStrings("#aa", get(&palette, 0));
    try std.testing.expectEqualStrings("#bb", get(&palette, 1));
    try std.testing.expectEqualStrings("#cc", get(&palette, 2));
    try std.testing.expectEqualStrings("#aa", get(&palette, 3)); // cycles
    try std.testing.expectEqualStrings("#bb", get(&palette, 4));
}

test "isValidHex" {
    try std.testing.expect(isValidHex("#fff"));
    try std.testing.expect(isValidHex("#ffffff"));
    try std.testing.expect(isValidHex("#3e63dd"));
    try std.testing.expect(!isValidHex("fff"));
    try std.testing.expect(!isValidHex("#gg0000"));
    try std.testing.expect(!isValidHex("#ff"));
}

test "all palettes have valid colors" {
    const palettes = [_][]const []const u8{
        &radix,
        &vibrant,
        &monochrome,
        &pastel,
        &dark_mode,
        &colorblind_safe,
        &categorical,
    };
    for (palettes) |palette| {
        for (palette) |color| {
            try std.testing.expect(isValidHex(color));
        }
    }
}

test "getAnsi cycles through palette" {
    try std.testing.expectEqual(@as(u8, 39), getAnsi(&ansi, 0));
    try std.testing.expectEqual(@as(u8, 203), getAnsi(&ansi, 1));
    try std.testing.expectEqual(@as(u8, 39), getAnsi(&ansi, 16)); // cycles
}

test "hexToAnsi256 basic colors" {
    // Red should map to red area of color cube
    const red_ansi = hexToAnsi256("#ff0000");
    try std.testing.expect(red_ansi >= 16 and red_ansi <= 231);

    // Pure blue
    const blue_ansi = hexToAnsi256("#0000ff");
    try std.testing.expect(blue_ansi >= 16 and blue_ansi <= 231);

    // Gray should map to grayscale range
    const gray_ansi = hexToAnsi256("#808080");
    try std.testing.expect(gray_ansi >= 232 or gray_ansi == 16 or gray_ansi == 231);
}

test "hexToAnsi256 invalid input" {
    try std.testing.expectEqual(@as(u8, 7), hexToAnsi256("invalid"));
    try std.testing.expectEqual(@as(u8, 7), hexToAnsi256("#gg0000"));
}

test "escape.fg256 produces valid escape sequence" {
    const seq = escape.fg256(39);
    try std.testing.expectEqual(@as(u8, 0x1b), seq[0]); // ESC
    try std.testing.expectEqual(@as(u8, '['), seq[1]);
}

