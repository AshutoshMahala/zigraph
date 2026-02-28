# Color System

zigraph ships a composable color module at `zigraph.color` — four sub-modules covering the full spectrum from individual color manipulation to SVG gradient generation.

```text
zigraph.color
  ├── Color        ← RGBA struct with color-space math
  ├── ColorMap     ← Continuous 0→1 scientific colormaps
  ├── gradient     ← SVG <linearGradient> / <radialGradient> generators
  └── palettes     ← Discrete hex + ANSI terminal palettes
```

## Quick reference

```zig
const color = @import("zigraph").color;

// ── From hex ────────────────────────────────────
const c = color.Color.fromHex("#3b82f6");

// ── Operations (Oklab space, perceptually uniform) ──
const darker = c.darken(0.2);
const lighter = c.lighten(0.15);
const mid = c.lerp(color.Color.fromHex("#e5484d"), 0.5);

// ── Output ──────────────────────────────────────
const hex = c.toHex();                  // comptime [7]u8 "#3b82f6"
const hex_rt = c.toHexAlloc(arena);     // runtime []const u8

// ── Continuous colormap ─────────────────────────
const heat = color.ColorMap.turbo.sample(0.75);   // Color at t=0.75

// ── Discrete palette ────────────────────────────
const edge_color = color.get(&color.radix, edge_index);  // cycling "#rrggbb"
```

## Color spaces

The core `Color` type stores sRGB f32 internally. Four color spaces are supported:

| Space | Constructor | Converter | When to use |
|---|---|---|---|
| **sRGB** (f32 0–1) | `Color.rgb(r,g,b)` / `Color.rgba(r,g,b,a)` | Native storage | Default — what SVG/CSS expects |
| **sRGB** (u8 0–255) | `Color.rgb8(r,g,b)` | — | Integer input convenience |
| **Hex** `#rrggbb` / `#rgb` | `Color.fromHex(str)` | `toHex()` / `toHexAlloc(alloc)` | String I/O for SVG attributes |
| **Oklab** (L, a, b) | `Color.fromOklab(L,a,b)` | `toOklab()` → `Oklab{L,a,b}` | Perceptual operations |
| **HSL** (h°, s, l) | `Color.fromHsl(h,s,l)` | `toHsl()` → `Hsl{h,s,l}` | Saturation adjustments |

### Why Oklab?

All perceptual operations — `lerp()`, `darken()`, `lighten()` — convert to **Oklab** before operating. Oklab is perceptually uniform: a `lerp(a, b, 0.5)` midpoint *looks* like a visual midpoint, unlike sRGB interpolation which skews toward darker values.

We chose Oklab over CIELAB because:
- Simpler math (no D65 illuminant constants)
- Comptime-friendly (all operations are pure arithmetic)
- Better perceptual uniformity for blues (CIELAB's known weakness)

### Why HSL for saturation?

`saturate()` and `desaturate()` convert to **HSL** because saturation is a first-class HSL axis.
Oklab has no dedicated saturation dimension — you'd need to compute chroma from `a,b` which is less intuitive.

## Operations

All operations return a new `Color` (immutable value type):

```zig
const c = Color.fromHex("#3b82f6");

c.darken(0.2)          // Oklab: reduce L by 20%
c.lighten(0.15)        // Oklab: increase L by 15%
c.saturate(0.1)        // HSL: increase S by 10%
c.desaturate(0.2)      // HSL: decrease S by 20%
c.withAlpha(0.5)       // Set alpha to 0.5
c.lerp(other, 0.5)     // Oklab midpoint between c and other
```

## Comptime patterns

A major design goal is **zero runtime cost for static colors**. All operations work at comptime:

```zig
// Baked into .rodata — no runtime computation
const warning_dark = comptime Color.fromHex("#f59e0b").darken(0.15).toHex();
// warning_dark = "#c47f09" — a [7]u8 string literal

// Pre-baked colormap LUT — 64 hex strings, zero runtime cost
const turbo_lut = comptime ColorMap.turbo.quantize(64);
// turbo_lut[0] = "#30123b", turbo_lut[63] = "#7a0403"
```

Use `toHex()` (returns `[7]u8`, no allocator) for comptime and static contexts.
Use `toHexAlloc(arena)` for runtime contexts (style functions, dynamic values).

## Colormaps

Six scientific colormaps, each defined with 16 control stops interpolated in Oklab space:

| Map | Type | Origin | Use case |
|---|---|---|---|
| `viridis` | Sequential | Matplotlib | Default scientific — perceptually uniform, colorblind safe |
| `inferno` | Sequential | Matplotlib | High contrast dark themes |
| `magma` | Sequential | Matplotlib | Similar to inferno, softer |
| `plasma` | Sequential | Matplotlib | Purple → yellow, good for dark backgrounds |
| `turbo` | Multi-hue | Google (Mikhailov) | Rainbow heatmaps — NOT perceptually uniform (see note) |
| `coolwarm` | Diverging | Moreland 2009 | Signed data: blue (neg) → gray (zero) → red (pos) |

### Usage

```zig
const ColorMap = @import("zigraph").color.ColorMap;

// Sample a single color at position t ∈ [0, 1]
const c = ColorMap.viridis.sample(0.75);
const hex = c.toHexAlloc(arena);  // runtime hex string

// Pre-bake N stops at comptime for legends, gradients, etc.
const lut = comptime ColorMap.turbo.quantize(32);
// lut[0..31] are [7]u8 hex strings, baked into binary
```

### Reversed colormaps

There is no `reversed()` method (it would require comptime allocation that Zig can't perform).
Use the workaround:

```zig
// Reversed: sample at (1 - t) instead of t
const cold_to_hot = ColorMap.turbo.sample(t);
const hot_to_cold = ColorMap.turbo.sample(1.0 - t);
```

### A note on turbo

Turbo is included because it's the most recognizable heatmap colormap, but it is **not perceptually uniform** — perceived brightness oscillates across the range. For scientific accuracy, prefer `viridis` or `inferno`. For visual impact (FEA stress diagrams, process mining), turbo works well.

## SVG gradient generators

The `gradient` sub-module generates complete SVG `<linearGradient>` / `<radialGradient>` elements as strings, ready to inject via `NodeStyle.defs` or `EdgeStyle.defs`:

```zig
const gradient = @import("zigraph").color.gradient;

// Linear gradient from a colormap (horizontal, 8 stops)
const lg = try gradient.linearGradient(arena, "my-grad", ColorMap.viridis, 8, .horizontal);
// Returns: <linearGradient id="my-grad" x1="0%" y1="0%" x2="100%" y2="0%">
//            <stop offset="0%" stop-color="#440154"/>
//            ...
//          </linearGradient>

// Radial gradient from a colormap (inner focal at t=0.8)
const rg = try gradient.radialGradient(arena, "heat", ColorMap.turbo, 0.8);

// Glow gradient (center color fading to transparent)
const glow = try gradient.glowGradient(arena, "glow", Color.fromHex("#e5484d"), 0.6);
```

These integrate with the SVG style API:

```zig
fn heatNode(ctx: zigraph.NodeStyleContext) zigraph.NodeStyle {
    const grad = gradient.linearGradient(ctx.arena, "node-grad", ColorMap.turbo, 8, .horizontal) catch null;
    return .{
        .shape_svg = "...",
        .fill = "url(#node-grad)",
        .defs = grad,
    };
}
```

## Discrete palettes

### Hex palettes

| Palette | Count | Best for |
|---|---|---|
| `radix` | 16 | Default — Radix UI shade 9, balanced saturation, dashboards |
| `vibrant` | 12 | High-contrast saturated, presentations |
| `monochrome` | 8 | Blue/gray formal diagrams, publications |
| `pastel` | 10 | Soft, light backgrounds |
| `dark_mode` | 10 | Bright on dark backgrounds |
| `colorblind_safe` | 8 | Okabe-Ito — accessible for all color vision types |
| `categorical` | 10 | D3/Tableau inspired, data visualization |

```zig
const color = @import("zigraph").color;

// Cycle through palette by index (wraps around)
const c = color.get(&color.radix, edge_index);  // "#rrggbb"

// Access specific entry
const first = color.radix[0];                    // "#e5484d"

// Any []const []const u8 works — bring your own palette
const my_palette = [_][]const u8{ "#ff0000", "#00ff00", "#0000ff" };
const c2 = color.get(&my_palette, i);
```

### ANSI palettes (terminal)

For the Unicode renderer's terminal output:

| Palette | Count | Terminal |
|---|---|---|
| `ansi` | 16 | General purpose (256-color codes) |
| `ansi_dark` | 12 | Optimized for dark terminal backgrounds |
| `ansi_light` | 12 | Optimized for light terminal backgrounds |

```zig
const ansi_code = color.getAnsi(&color.ansi_dark, edge_index);
const colored = color.escape.fg256(ansi_code);   // "\x1b[38;5;{code}m"
const reset = color.escape.reset;                 // "\x1b[0m"
```

### Radix 12-step scales (light + dark)

Full [Radix UI](https://www.radix-ui.com/colors) 12-step scales for 16 colors, each with light **and** dark variants via `DualScale`:

| Scale | Light step 9 | Dark step 9 | Use case |
|---|---|---|---|
| `red` | `#e5484d` | `#e5484d` | Errors, destructive actions |
| `tomato` | `#e54d2e` | `#e54d2e` | Warm accent |
| `orange` | `#f76b15` | `#f76b15` | Warnings |
| `amber` | `#ffc53d` | `#ffc53d` | Caution, pending |
| `yellow` | `#ffe629` | `#ffe629` | Highlights |
| `green` | `#30a46c` | `#30a46c` | Success, confirmations |
| `grass` | `#46a758` | `#46a758` | Nature, growth |
| `teal` | `#12a594` | `#12a594` | Data, information |
| `cyan` | `#00a2c7` | `#00a2c7` | Links, interactive |
| `blue` | `#0090ff` | `#0090ff` | Primary actions |
| `indigo` | `#3e63dd` | `#3e63dd` | Brand, navigation |
| `violet` | `#6e56cf` | `#6e56cf` | Creative, premium |
| `purple` | `#8e4ec6` | `#8e4ec6` | Rich accent |
| `pink` | `#d6409f` | `#d6409f` | Fun, playful |
| `plum` | `#ab4aba` | `#ab4aba` | Mystical |
| `gray` | `#8d8d8d` | `#6e6e6e` | Neutral, borders |

Step 9 (the accent) is identical across modes for most colors. Steps 1-4 (backgrounds) and 11-12 (text) are **inverted** — light step 1 is near-white, dark step 1 is near-black.

```zig
const color = @import("zigraph").color;

// Direct access — light mode background
const panel_bg = color.scale.blue.light.step(2);   // "#f4faff"

// Dark mode equivalent
const panel_bg_dark = color.scale.blue.dark.step(2); // "#111927"

// Mode-switched — pass .light or .dark from app config
const mode: color.Mode = if (user_prefers_dark) .dark else .light;
const accent = color.scale.red.forMode(mode).step(9); // "#e5484d" (same both)
const bg = color.scale.red.forMode(mode).step(2);     // "#fff8f8" or "#201314"

// As a cycling palette (light mode)
const red_palette = color.scale.red.light.all();  // [12][]const u8
const c = color.get(&red_palette, edge_index);

// Use in SVG style function
fn nodeStyle(ctx: NodeStyleContext) NodeStyle {
    const s = color.scale.blue.light;  // or .dark
    return .{
        .fill = s.step(3),        // light background
        .stroke = s.step(7),      // medium border
        .label_color = s.step(12), // dark text
    };
}
```

**Step roles** (Radix convention):

| Steps | Purpose | Light example | Dark example |
|---|---|---|---|
| 1-2 | App background | Near-white | Near-black |
| 3-4 | Component background | Subtle tint | Subtle tint |
| 5-6 | Borders, separators | Visible outline | Visible outline |
| 7-8 | Solid backgrounds, hover | Medium tone | Medium tone |
| 9 | Solid accent | The color | The color |
| 10 | Hover accent | Slightly shifted | Slightly shifted |
| 11-12 | Text | Near-black | Near-white |

### Semantic colors

Named constants for common UI meanings:

```zig
color.semantic.success    // "#30a46c" green
color.semantic.warning    // "#f59e0b" amber
color.semantic.error_     // "#e5484d" red
color.semantic.info       // "#3b82f6" blue
color.semantic.neutral    // "#64748b" gray
color.semantic.highlight  // "#8b5cf6" purple
```

### Utilities

```zig
color.isValidHex("#3b82f6")     // true
color.isValidHex("#xyz")        // false
color.hexToAnsi256("#3b82f6")   // nearest 256-color code (approx)
```

## Limitations

| Limitation | Workaround |
|---|---|
| **No CSS named colors** — no `"red"`, `"cornflowerblue"` | Use hex strings directly |
| **`ColorMap.reversed()` is a compileError** | Use `sample(1.0 - t)` |
| **16-stop colormap approximation** | 16 control points per map, Oklab-interpolated — adequate for smooth gradients but not bit-exact vs. canonical 256-stop tables |
| **No alpha in discrete palettes** | All palette entries are opaque `#rrggbb` — set opacity via SVG `opacity` attribute or `Color.withAlpha()` |
| **`hexToAnsi256` is approximate** | Maps to nearest color-cube entry, not delta-E perceptual matching |
| **No CMYK / ICC profiles** | No print color space support — sRGB only |

## Design contract

The color module guarantees:

1. **`Color` is a value type** — 4×f32, no heap allocation, copy-safe
2. **All operations are pure** — no side effects, return new values
3. **Comptime-everywhere** — any operation chain works at `comptime`
4. **`toHex()` needs no allocator** — returns fixed `[7]u8` for zero-cost static colors
5. **`toHex8()` for alpha** — returns fixed `[9]u8` `#rrggbbaa`
6. **`toHexAlloc()` for arena contexts** — auto-picks 6 vs 8 digit based on alpha
7. **Palettes are `[]const []const u8`** — bring your own, `get()` works with any slice
8. **Colormaps produce `Color`** — `sample()` returns a `Color`, compose freely with `darken()`, `lerp()`, etc.
9. **SVG gradients produce `[]const u8`** — ready to inject into `NodeStyle.defs` / `EdgeStyle.defs`
10. **Radial gradients are configurable** — `RadialConfig` exposes cx/cy/r/fx/fy
