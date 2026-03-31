//! Discrete color palettes for categorical graph visualization.
//!
//! Pre-defined arrays of hex color strings for edge and node coloring.
//! These cycle via `get(palette, index)` — the original zigraph color API.
//!
//! For continuous/scientific color mapping, see `colormaps.zig` instead.
//!
//! ## Usage
//!
//! ```zig
//! const palettes = @import("zigraph").color.palettes;
//!
//! // Get color by cycling index
//! const edge_color = palettes.get(&palettes.radix, edge_index);
//!
//! // Or use your own palette
//! const my_palette = [_][]const u8{ "#ff0000", "#00ff00", "#0000ff" };
//! const color = palettes.get(&my_palette, index);
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
// Radix UI 12-Step Color Scales
// ============================================================================
//
// Full 12-step scales from Radix UI Colors (https://www.radix-ui.com/colors).
// Steps 1–2 are backgrounds, 3–5 are UI elements, 6–8 are borders,
// 9–10 are solid fills, 11 is low-contrast text, 12 is high-contrast text.
//
// Usage:
//   palettes.scale.blue.step9   // → "#3e63dd" (solid fill)
//   palettes.scale.red.step3    // → "#ffefef" (light background)
//   palettes.scale.green.all()  // → [12][]const u8 array

/// Color mode for light/dark theme selection.
pub const Mode = enum { light, dark };

/// A 12-step Radix color scale (single theme).
pub const Scale = struct {
    step1: []const u8,
    step2: []const u8,
    step3: []const u8,
    step4: []const u8,
    step5: []const u8,
    step6: []const u8,
    step7: []const u8,
    step8: []const u8,
    step9: []const u8,
    step10: []const u8,
    step11: []const u8,
    step12: []const u8,

    /// Return all 12 steps as an array (for palettes.get cycling).
    pub fn all(self: Scale) [12][]const u8 {
        return .{
            self.step1, self.step2,  self.step3,  self.step4,
            self.step5, self.step6,  self.step7,  self.step8,
            self.step9, self.step10, self.step11, self.step12,
        };
    }

    /// Get a step by 1-based index (clamped to 1–12).
    pub fn step(self: Scale, n: usize) []const u8 {
        const a = self.all();
        const idx = if (n == 0) 0 else if (n > 12) 11 else n - 1;
        return a[idx];
    }
};

/// A paired Radix color scale with light and dark variants.
///
/// ```zig
/// const red = palettes.scale.red;
/// const bg = red.light.step(2);      // "#fff8f8" — light mode
/// const bg_d = red.dark.step(2);     // "#291415" — dark mode
/// const active = red.forMode(.dark).step(9);  // "#e5484d"
/// ```
pub const DualScale = struct {
    light: Scale,
    dark: Scale,

    /// Select the scale for the given color mode.
    pub fn forMode(self: DualScale, mode: Mode) Scale {
        return switch (mode) {
            .light => self.light,
            .dark => self.dark,
        };
    }
};

/// Radix UI 12-step color scales — light + dark variants.
///
/// Each scale is a `DualScale` with `.light` and `.dark` sub-scales.
///
/// ```zig
/// const blue9 = palettes.scale.blue.light.step9;          // "#0090ff" (light)
/// const blue9d = palettes.scale.blue.dark.step9;          // "#0090ff" (dark)
/// const red_bg = palettes.scale.red.forMode(.dark).step(2); // "#291415"
/// const teal_all = palettes.scale.teal.light.all();       // [12][]const u8
/// ```
pub const scale = struct {
    pub const red: DualScale = .{
        .light = .{
            .step1 = "#fffcfc",
            .step2 = "#fff8f8",
            .step3 = "#ffefef",
            .step4 = "#ffe5e5",
            .step5 = "#fdd8d8",
            .step6 = "#f9c6c6",
            .step7 = "#f3aeaf",
            .step8 = "#eb9091",
            .step9 = "#e5484d",
            .step10 = "#dc3d43",
            .step11 = "#cd2b31",
            .step12 = "#381316",
        },
        .dark = .{
            .step1 = "#191111",
            .step2 = "#201314",
            .step3 = "#3b1219",
            .step4 = "#500f1c",
            .step5 = "#611623",
            .step6 = "#72232d",
            .step7 = "#8c333a",
            .step8 = "#b54548",
            .step9 = "#e5484d",
            .step10 = "#ec5d5e",
            .step11 = "#ff9592",
            .step12 = "#ffd1d9",
        },
    };
    pub const tomato: DualScale = .{
        .light = .{
            .step1 = "#fffcfc",
            .step2 = "#fff8f7",
            .step3 = "#fff0ee",
            .step4 = "#ffe6e2",
            .step5 = "#fdd8d3",
            .step6 = "#fac7be",
            .step7 = "#f3b0a2",
            .step8 = "#ea9280",
            .step9 = "#e54d2e",
            .step10 = "#db4324",
            .step11 = "#ca3214",
            .step12 = "#341711",
        },
        .dark = .{
            .step1 = "#181111",
            .step2 = "#1f1513",
            .step3 = "#391714",
            .step4 = "#4e1511",
            .step5 = "#5e1c16",
            .step6 = "#6e2920",
            .step7 = "#853a2d",
            .step8 = "#ac4d39",
            .step9 = "#e54d2e",
            .step10 = "#ec6142",
            .step11 = "#ff977d",
            .step12 = "#fbd3cb",
        },
    };
    pub const orange: DualScale = .{
        .light = .{
            .step1 = "#fefcfb",
            .step2 = "#fff9f5",
            .step3 = "#fff0e4",
            .step4 = "#ffe4ce",
            .step5 = "#ffd5b3",
            .step6 = "#ffc291",
            .step7 = "#f5a862",
            .step8 = "#ec8e2e",
            .step9 = "#f76b15",
            .step10 = "#ef5f00",
            .step11 = "#cc4e00",
            .step12 = "#582d1d",
        },
        .dark = .{
            .step1 = "#17120e",
            .step2 = "#1e160f",
            .step3 = "#331e0b",
            .step4 = "#462100",
            .step5 = "#562800",
            .step6 = "#66350c",
            .step7 = "#7e451d",
            .step8 = "#a35829",
            .step9 = "#f76b15",
            .step10 = "#ff801f",
            .step11 = "#ffa057",
            .step12 = "#ffe0c2",
        },
    };
    pub const amber: DualScale = .{
        .light = .{
            .step1 = "#fefdfb",
            .step2 = "#fefbe9",
            .step3 = "#fff7c2",
            .step4 = "#ffee9c",
            .step5 = "#fbe577",
            .step6 = "#f3d673",
            .step7 = "#e9c162",
            .step8 = "#e2a336",
            .step9 = "#ffc53d",
            .step10 = "#ffba18",
            .step11 = "#ab6400",
            .step12 = "#4f3422",
        },
        .dark = .{
            .step1 = "#16120c",
            .step2 = "#1d180f",
            .step3 = "#302008",
            .step4 = "#3f2700",
            .step5 = "#4d3000",
            .step6 = "#5c3d05",
            .step7 = "#714f19",
            .step8 = "#8f6424",
            .step9 = "#ffc53d",
            .step10 = "#ffd60a",
            .step11 = "#ffca16",
            .step12 = "#ffe7b3",
        },
    };
    pub const yellow: DualScale = .{
        .light = .{
            .step1 = "#fdfdf9",
            .step2 = "#fefce9",
            .step3 = "#fffab8",
            .step4 = "#fff394",
            .step5 = "#ffe770",
            .step6 = "#f3d768",
            .step7 = "#e4c767",
            .step8 = "#d5ae39",
            .step9 = "#ffe629",
            .step10 = "#ffdc00",
            .step11 = "#9e6c00",
            .step12 = "#473b1f",
        },
        .dark = .{
            .step1 = "#14120b",
            .step2 = "#1b180f",
            .step3 = "#2d2305",
            .step4 = "#362b00",
            .step5 = "#433500",
            .step6 = "#524202",
            .step7 = "#665417",
            .step8 = "#836a21",
            .step9 = "#ffe629",
            .step10 = "#ffff57",
            .step11 = "#f5e147",
            .step12 = "#f6eeb4",
        },
    };
    pub const green: DualScale = .{
        .light = .{
            .step1 = "#fbfefc",
            .step2 = "#f4fbf6",
            .step3 = "#e6f6eb",
            .step4 = "#d6f1df",
            .step5 = "#c3e9d0",
            .step6 = "#acdec0",
            .step7 = "#8cceb0",
            .step8 = "#5bb98b",
            .step9 = "#30a46c",
            .step10 = "#2b9a66",
            .step11 = "#218358",
            .step12 = "#193b2d",
        },
        .dark = .{
            .step1 = "#0e1512",
            .step2 = "#121b17",
            .step3 = "#132d21",
            .step4 = "#113b29",
            .step5 = "#174933",
            .step6 = "#20573e",
            .step7 = "#28684a",
            .step8 = "#2f7c57",
            .step9 = "#30a46c",
            .step10 = "#33b074",
            .step11 = "#3dd68c",
            .step12 = "#b1f1cb",
        },
    };
    pub const grass: DualScale = .{
        .light = .{
            .step1 = "#fbfefb",
            .step2 = "#f5fbf5",
            .step3 = "#e9f6e9",
            .step4 = "#daf1db",
            .step5 = "#c9e8ca",
            .step6 = "#b2ddb5",
            .step7 = "#94ce9a",
            .step8 = "#65ba74",
            .step9 = "#46a758",
            .step10 = "#3e9b4f",
            .step11 = "#2d8541",
            .step12 = "#203c25",
        },
        .dark = .{
            .step1 = "#0e1511",
            .step2 = "#141a15",
            .step3 = "#1b2a1e",
            .step4 = "#1d3a24",
            .step5 = "#25482d",
            .step6 = "#2d5736",
            .step7 = "#366740",
            .step8 = "#3e7949",
            .step9 = "#46a758",
            .step10 = "#53b365",
            .step11 = "#71d083",
            .step12 = "#c2f0c2",
        },
    };
    pub const teal: DualScale = .{
        .light = .{
            .step1 = "#fafefd",
            .step2 = "#f3fbf9",
            .step3 = "#e0f8f3",
            .step4 = "#ccf3ea",
            .step5 = "#b8eae0",
            .step6 = "#a1ded2",
            .step7 = "#83cdc1",
            .step8 = "#53b9ab",
            .step9 = "#12a594",
            .step10 = "#0d9b8a",
            .step11 = "#008573",
            .step12 = "#0d3d38",
        },
        .dark = .{
            .step1 = "#0d1514",
            .step2 = "#111c1b",
            .step3 = "#0d2d2a",
            .step4 = "#023b37",
            .step5 = "#084843",
            .step6 = "#145750",
            .step7 = "#1c6961",
            .step8 = "#207e73",
            .step9 = "#12a594",
            .step10 = "#0eb39e",
            .step11 = "#0bd8b6",
            .step12 = "#adf0dd",
        },
    };
    pub const cyan: DualScale = .{
        .light = .{
            .step1 = "#fafdfe",
            .step2 = "#f2fafb",
            .step3 = "#def7f9",
            .step4 = "#caf1f6",
            .step5 = "#b5e9f0",
            .step6 = "#9ddde7",
            .step7 = "#7dcedc",
            .step8 = "#3db9cf",
            .step9 = "#00a2c7",
            .step10 = "#0797b9",
            .step11 = "#107d98",
            .step12 = "#0d3c48",
        },
        .dark = .{
            .step1 = "#0b1518",
            .step2 = "#111b1f",
            .step3 = "#082c36",
            .step4 = "#003848",
            .step5 = "#004558",
            .step6 = "#045468",
            .step7 = "#12677e",
            .step8 = "#117d98",
            .step9 = "#00a2c7",
            .step10 = "#23afd0",
            .step11 = "#4ccce6",
            .step12 = "#b6ecf7",
        },
    };
    pub const blue: DualScale = .{
        .light = .{
            .step1 = "#fbfdff",
            .step2 = "#f4faff",
            .step3 = "#e6f4fe",
            .step4 = "#d5efff",
            .step5 = "#c2e5ff",
            .step6 = "#acd8fc",
            .step7 = "#8ec8f6",
            .step8 = "#5eb1ef",
            .step9 = "#0090ff",
            .step10 = "#0588f0",
            .step11 = "#0d74ce",
            .step12 = "#113264",
        },
        .dark = .{
            .step1 = "#0d1520",
            .step2 = "#111927",
            .step3 = "#0d2847",
            .step4 = "#003362",
            .step5 = "#004078",
            .step6 = "#104d93",
            .step7 = "#205d9e",
            .step8 = "#2870bd",
            .step9 = "#0090ff",
            .step10 = "#3b9eff",
            .step11 = "#70b8ff",
            .step12 = "#c2e6ff",
        },
    };
    pub const indigo: DualScale = .{
        .light = .{
            .step1 = "#fdfdfe",
            .step2 = "#f7f9ff",
            .step3 = "#edf2fe",
            .step4 = "#e1e9ff",
            .step5 = "#d2deff",
            .step6 = "#c1d0ff",
            .step7 = "#abbdf9",
            .step8 = "#8da4ef",
            .step9 = "#3e63dd",
            .step10 = "#3358d4",
            .step11 = "#3a5bc7",
            .step12 = "#1f2d5c",
        },
        .dark = .{
            .step1 = "#11131f",
            .step2 = "#141726",
            .step3 = "#182449",
            .step4 = "#1d2e62",
            .step5 = "#253974",
            .step6 = "#304384",
            .step7 = "#3a4f97",
            .step8 = "#435db1",
            .step9 = "#3e63dd",
            .step10 = "#5472e4",
            .step11 = "#9eb1ff",
            .step12 = "#d6e1ff",
        },
    };
    pub const violet: DualScale = .{
        .light = .{
            .step1 = "#fdfcfe",
            .step2 = "#faf8ff",
            .step3 = "#f4f0fe",
            .step4 = "#ebe4ff",
            .step5 = "#e1d9ff",
            .step6 = "#d4cafe",
            .step7 = "#c2b5f5",
            .step8 = "#aa99ec",
            .step9 = "#6e56cf",
            .step10 = "#654dc4",
            .step11 = "#6550b9",
            .step12 = "#2f265f",
        },
        .dark = .{
            .step1 = "#14121f",
            .step2 = "#1b1525",
            .step3 = "#291f43",
            .step4 = "#33255b",
            .step5 = "#3c2e6e",
            .step6 = "#473b7f",
            .step7 = "#544994",
            .step8 = "#6958ad",
            .step9 = "#6e56cf",
            .step10 = "#7d66d9",
            .step11 = "#baa7ff",
            .step12 = "#e2ddfe",
        },
    };
    pub const purple: DualScale = .{
        .light = .{
            .step1 = "#fefcfe",
            .step2 = "#fbf7fe",
            .step3 = "#f7edfc",
            .step4 = "#f2e2fc",
            .step5 = "#ead5f9",
            .step6 = "#dec4f4",
            .step7 = "#cfafe9",
            .step8 = "#bc93db",
            .step9 = "#8e4ec6",
            .step10 = "#8445bc",
            .step11 = "#793aaf",
            .step12 = "#38205c",
        },
        .dark = .{
            .step1 = "#18111b",
            .step2 = "#1e1523",
            .step3 = "#301c3b",
            .step4 = "#3d224e",
            .step5 = "#48295c",
            .step6 = "#54346b",
            .step7 = "#664282",
            .step8 = "#8457aa",
            .step9 = "#8e4ec6",
            .step10 = "#9a5cd0",
            .step11 = "#d19dff",
            .step12 = "#ecd9fa",
        },
    };
    pub const pink: DualScale = .{
        .light = .{
            .step1 = "#fffcfe",
            .step2 = "#fef7fb",
            .step3 = "#fee9f5",
            .step4 = "#fbdcef",
            .step5 = "#f6cee7",
            .step6 = "#efbfdd",
            .step7 = "#e4a9cf",
            .step8 = "#d68cbb",
            .step9 = "#d6409f",
            .step10 = "#cf3897",
            .step11 = "#c2298a",
            .step12 = "#651249",
        },
        .dark = .{
            .step1 = "#191117",
            .step2 = "#21121d",
            .step3 = "#37172f",
            .step4 = "#4b143d",
            .step5 = "#591c47",
            .step6 = "#692955",
            .step7 = "#833869",
            .step8 = "#a84882",
            .step9 = "#d6409f",
            .step10 = "#de51a8",
            .step11 = "#ff8dcc",
            .step12 = "#fdd1ea",
        },
    };
    pub const plum: DualScale = .{
        .light = .{
            .step1 = "#fefcff",
            .step2 = "#fdf7fd",
            .step3 = "#fbebfb",
            .step4 = "#f7def8",
            .step5 = "#f2d1f3",
            .step6 = "#e9c2ec",
            .step7 = "#deade3",
            .step8 = "#cf91d8",
            .step9 = "#ab4aba",
            .step10 = "#a144af",
            .step11 = "#953ea3",
            .step12 = "#53195d",
        },
        .dark = .{
            .step1 = "#181118",
            .step2 = "#201320",
            .step3 = "#351a35",
            .step4 = "#451d47",
            .step5 = "#512454",
            .step6 = "#5e3061",
            .step7 = "#734079",
            .step8 = "#92549c",
            .step9 = "#ab4aba",
            .step10 = "#b658c4",
            .step11 = "#e796f3",
            .step12 = "#f4d4f4",
        },
    };
    pub const gray: DualScale = .{
        .light = .{
            .step1 = "#fcfcfc",
            .step2 = "#f9f9f9",
            .step3 = "#f0f0f0",
            .step4 = "#e8e8e8",
            .step5 = "#e0e0e0",
            .step6 = "#d9d9d9",
            .step7 = "#cecece",
            .step8 = "#bbbbbb",
            .step9 = "#8d8d8d",
            .step10 = "#838383",
            .step11 = "#646464",
            .step12 = "#202020",
        },
        .dark = .{
            .step1 = "#111111",
            .step2 = "#191919",
            .step3 = "#222222",
            .step4 = "#2a2a2a",
            .step5 = "#313131",
            .step6 = "#3a3a3a",
            .step7 = "#484848",
            .step8 = "#606060",
            .step9 = "#6e6e6e",
            .step10 = "#7b7b7b",
            .step11 = "#b4b4b4",
            .step12 = "#eeeeee",
        },
    };
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
    39, // Blue
    203, // Red/Tomato
    35, // Green
    208, // Orange
    134, // Purple
    37, // Teal/Cyan
    205, // Pink
    220, // Yellow
    81, // Sky blue
    214, // Amber
    123, // Light cyan
    170, // Plum
    71, // Grass green
    99, // Violet
    196, // Bright red
    33, // Bright blue
};

/// ANSI palette optimized for dark terminals (brighter colors)
pub const ansi_dark = [_]u8{
    81, // Bright cyan
    156, // Lime green
    222, // Peach/lightorange
    183, // Lavender
    210, // Salmon/light red
    117, // Sky blue
    121, // Mint
    221, // Amber
    216, // Apricot
    189, // Mauve
    87, // Turquoise
    147, // Light purple
};

/// ANSI palette optimized for light terminals (darker colors)
pub const ansi_light = [_]u8{
    27, // Dark blue
    124, // Dark red
    22, // Dark green
    166, // Dark orange
    91, // Dark purple
    30, // Dark teal
    125, // Dark pink
    136, // Dark yellow
    24, // Dark steel blue
    130, // Brown
    23, // Dark cyan
    54, // Dark violet
};

/// Get an ANSI color code from the palette by index (cycles through)
pub fn getAnsi(palette: []const u8, index: usize) u8 {
    return palette[index % palette.len];
}

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
    pub fn fg256(color: u8) [11]u8 {
        var buf: [11]u8 = undefined;
        _ = std.fmt.bufPrint(&buf, "\x1b[38;5;{d:0>3}m", .{color}) catch unreachable;
        return buf;
    }

    /// Format background color using 256-color palette
    pub fn bg256(color: u8) [11]u8 {
        var buf: [11]u8 = undefined;
        _ = std.fmt.bufPrint(&buf, "\x1b[48;5;{d:0>3}m", .{color}) catch unreachable;
        return buf;
    }

    /// Format foreground color using 24-bit truecolor
    pub fn fgRgb(r: u8, g: u8, b: u8) [19]u8 {
        var buf: [19]u8 = undefined;
        _ = std.fmt.bufPrint(&buf, "\x1b[38;2;{d:0>3};{d:0>3};{d:0>3}m", .{ r, g, b }) catch unreachable;
        return buf;
    }

    /// Format background color using 24-bit truecolor
    pub fn bgRgb(r: u8, g: u8, b: u8) [19]u8 {
        var buf: [19]u8 = undefined;
        _ = std.fmt.bufPrint(&buf, "\x1b[48;2;{d:0>3};{d:0>3};{d:0>3}m", .{ r, g, b }) catch unreachable;
        return buf;
    }
};

/// Convert an ANSI 256 palette index to RGB values.
pub fn ansi256ToRgb(index: u8) struct { r: u8, g: u8, b: u8 } {
    // Standard 16 colors (approximate terminal defaults)
    const standard_16 = [16][3]u8{
        .{ 0, 0, 0 }, // 0: black
        .{ 128, 0, 0 }, // 1: red
        .{ 0, 128, 0 }, // 2: green
        .{ 128, 128, 0 }, // 3: yellow
        .{ 0, 0, 128 }, // 4: blue
        .{ 128, 0, 128 }, // 5: magenta
        .{ 0, 128, 128 }, // 6: cyan
        .{ 192, 192, 192 }, // 7: white
        .{ 128, 128, 128 }, // 8: bright black
        .{ 255, 0, 0 }, // 9: bright red
        .{ 0, 255, 0 }, // 10: bright green
        .{ 255, 255, 0 }, // 11: bright yellow
        .{ 0, 0, 255 }, // 12: bright blue
        .{ 255, 0, 255 }, // 13: bright magenta
        .{ 0, 255, 255 }, // 14: bright cyan
        .{ 255, 255, 255 }, // 15: bright white
    };

    if (index < 16) {
        return .{ .r = standard_16[index][0], .g = standard_16[index][1], .b = standard_16[index][2] };
    }

    // 6×6×6 color cube (indices 16-231)
    if (index < 232) {
        const ci = index - 16;
        const cube_values = [6]u8{ 0, 95, 135, 175, 215, 255 };
        return .{
            .r = cube_values[ci / 36],
            .g = cube_values[(ci % 36) / 6],
            .b = cube_values[ci % 6],
        };
    }

    // Grayscale ramp (indices 232-255)
    const gray = @as(u8, 8) + @as(u8, index - 232) * 10;
    return .{ .r = gray, .g = gray, .b = gray };
}

/// Convert RGB values to the nearest ANSI 256 palette index.
pub fn rgbToAnsi256(r: u8, g: u8, b: u8) u8 {
    // Check grayscale first (if r ≈ g ≈ b)
    if (r == g and g == b) {
        if (r < 4) return 16; // near-black → cube black
        if (r > 248) return 231; // near-white → cube white
        return @as(u8, @intCast((@as(u16, r) - 8 + 5) / 10)) + 232;
    }

    // Find nearest in the 6×6×6 color cube
    const cube_values = [6]u8{ 0, 95, 135, 175, 215, 255 };
    const ri = nearestCubeIndex(r, &cube_values);
    const gi = nearestCubeIndex(g, &cube_values);
    const bi = nearestCubeIndex(b, &cube_values);
    return 16 + @as(u8, ri) * 36 + @as(u8, gi) * 6 + @as(u8, bi);
}

fn nearestCubeIndex(val: u8, cube_values: *const [6]u8) u8 {
    var best: u8 = 0;
    var best_dist: u16 = 0xFFFF;
    for (cube_values, 0..) |cv, i| {
        const dist = if (val >= cv) @as(u16, val - cv) else @as(u16, cv - val);
        if (dist < best_dist) {
            best_dist = dist;
            best = @intCast(i);
        }
    }
    return best;
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
    const all_palettes = [_][]const []const u8{
        &radix,
        &vibrant,
        &monochrome,
        &pastel,
        &dark_mode,
        &colorblind_safe,
        &categorical,
    };
    for (all_palettes) |palette| {
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

test "radix scale step access" {
    // Direct field access via .light
    try std.testing.expectEqualStrings("#3e63dd", scale.indigo.light.step9);
    try std.testing.expectEqualStrings("#e5484d", scale.red.light.step9);
    try std.testing.expectEqualStrings("#30a46c", scale.green.light.step9);

    // Dark mode — same step9 semantics, different values at edges
    try std.testing.expectEqualStrings("#e5484d", scale.red.dark.step9);
    try std.testing.expectEqualStrings("#191111", scale.red.dark.step1);
    try std.testing.expectEqualStrings("#ffd1d9", scale.red.dark.step12);

    // 1-based step() accessor
    try std.testing.expectEqualStrings("#fbfdff", scale.blue.light.step(1));
    try std.testing.expectEqualStrings("#113264", scale.blue.light.step(12));

    // Clamping
    try std.testing.expectEqualStrings("#fbfdff", scale.blue.light.step(0));
    try std.testing.expectEqualStrings("#113264", scale.blue.light.step(99));
}

test "radix scale all() returns 12 valid hex colors" {
    const blue_all = scale.blue.light.all();
    try std.testing.expectEqual(@as(usize, 12), blue_all.len);
    for (blue_all) |hex| {
        try std.testing.expect(isValidHex(hex));
    }
    // Dark mode too
    const blue_dark_all = scale.blue.dark.all();
    try std.testing.expectEqual(@as(usize, 12), blue_dark_all.len);
    for (blue_dark_all) |hex| {
        try std.testing.expect(isValidHex(hex));
    }
}

test "radix scale cycling via get()" {
    const reds = scale.red.light.all();
    // Cycling works through the standard get() function
    try std.testing.expectEqualStrings(reds[0], get(&reds, 0));
    try std.testing.expectEqualStrings(reds[0], get(&reds, 12)); // cycles
}

test "radix dual scale forMode()" {
    const red = scale.red;
    const light = red.forMode(.light);
    const dark = red.forMode(.dark);

    // Light step1 is near-white, dark step1 is near-black
    try std.testing.expectEqualStrings("#fffcfc", light.step1);
    try std.testing.expectEqualStrings("#191111", dark.step1);

    // Step9 (the accent) is the same in both modes for red
    try std.testing.expectEqualStrings("#e5484d", light.step9);
    try std.testing.expectEqualStrings("#e5484d", dark.step9);

    // Light step12 is near-black, dark step12 is near-white
    try std.testing.expectEqualStrings("#381316", light.step12);
    try std.testing.expectEqualStrings("#ffd1d9", dark.step12);
}
