# Terminal Customization Guide

This guide covers every knob the terminal renderer exposes, from simple border changes to gradient colors and custom pipeline rendering.

> **Runnable examples** — All code shown here has a matching example in `examples/terminal/`.
> Each can be run individually or explore them grouped by topic:
>
> | # | Command | Topic |
> |---|---------|-------|
> | 1 | `zig build run-terminal-node-control` | Node borders, implicit/explicit styling |
> | 2 | `zig build run-terminal-edge-styles` | Edge line weights + marker shapes |
> | 3 | `zig build run-terminal-color-system` | Color modes, palettes, gradients |
> | 4 | `zig build run-terminal-edge-labels` | Edge label placement |
> | 5 | `zig build run-terminal-subgraph-styles` | Subgraph borders + nesting |
> | 6 | `zig build run-output-formats` | ASCII charset, HTML output |
| 7 | `zig build run-terminal-record-nodes` | Custom record-style nodes (paint_fn) |
| 8 | `zig build run-terminal-db-diagram` | Full ER diagram with FK edges (paint_fn) |
> | 9 | `zig build run-streaming` | Streaming render to stdout (zero-copy) |
> | 10 | `zig build run-tui` | Interactive click-to-select with hit-testing |
> | 11 | `zig build run-terminal-text-attrs` | Bold, dim, italic, underline on labels |

---

## Overview

The terminal renderer is driven by **4 style function pointers** on `terminal.Config`. Each receives a context struct and returns a style struct.

| Function pointer | Called for | Returns | Controls |
|---|---|---|---|
| `node_style_fn` | Every node | `TerminalNodeStyle` | Border shape, border/text/bg colors, text attributes |
| `edge_style_fn` | Every edge | `TerminalEdgeStyle` | Line weight, color, markers at start/end |
| `edge_label_style_fn` | Every labeled edge | `TerminalEdgeLabelStyle` | Label color, placement, text attributes |
| `subgraph_style_fn` | Every subgraph box | `TerminalSubgraphStyle` | Border style, color, label position, text attributes |

Plus five global options:

| Field | Default | Controls |
|---|---|---|
| `color_mode` | `.ansi256` | Output encoding: `none` / `ansi256` / `truecolor` |
| `char_set` | `.unicode` | `unicode` (box-drawing) or `ascii` (`+`/`-`/`\|`) |
| `output_format` | `.raw` | `raw` (ANSI escapes) or `html_pre` (`<span>` colors) |
| `show_subgraphs` | `true` | Toggle subgraph box rendering |
| `show_dummy_nodes` | `false` | Show internal dummy layout nodes (for debugging) |

---

## Quick start

```zig
const zigraph = @import("zigraph");

// Allocate + layout
var g = zigraph.Graph.init(alloc);
defer g.deinit();
try g.addNode(1, "Start");
try g.addNode(2, "End");
try g.addEdge(1, 2);

var ir = try zigraph.layout(&g, alloc, .{});
defer ir.deinit();

// Zero-config render (ANSI-256, Unicode, bracket nodes)
const output = try zigraph.terminal.render(&ir, alloc);
defer alloc.free(output);
std.debug.print("{s}\n", .{output});

// Custom config
const output2 = try zigraph.terminal.renderWithConfig(&ir, alloc, .{
    .node_style_fn = &zigraph.terminal_node_presets.roundedBox,
    .color_mode    = .truecolor,
});
defer alloc.free(output2);
std.debug.print("{s}\n", .{output2});
```

**Streaming** (write directly to any `std.io.Writer` — avoids allocating the full output string):

```zig
const stdout = std.io.getStdOut().writer();
try zigraph.terminal.renderStreamingWithConfig(&ir, stdout, alloc, .{
    .color_mode = .truecolor,
});
```

---

## Node styling

> **See it:** [`examples/terminal/node_control.zig`](../examples/terminal/node_control.zig)

### NodeStyleContext fields

```zig
pub const NodeStyleContext = struct {
    node_id:     usize,       // original graph ID
    label:       []const u8,  // node label text
    total_nodes: usize,       // total non-dummy nodes in graph
    width:       usize,       // layout-computed column width
    height:      usize,       // layout-computed height from NodeOptions (default 1)
    is_implicit: bool,        // true = auto-created via addEdgeAutoCreate
    arena:       Allocator,   // allocator freed after the render pass
};
```

### TerminalNodeStyle fields

```zig
pub const TerminalNodeStyle = struct {
    border:       NodeBorder = .bracket,  // shape of the node box
    border_color: Color      = .default,  // box-drawing char color
    text_color:   Color      = .default,  // label text color
    bg_color:     Color      = .default,  // cell background color
    attrs:        TextAttrs  = .{},       // bold / dim / italic / underline
    paint_fn:     ?*const fn (*Buffer2D, NodePaintContext) void = null,
    // When non-null, paintNode delegates entirely to this function.
    // The layout engine uses NodeOptions.height for level spacing,
    // so edges route correctly around custom-height nodes.
};
```

### NodePaintContext fields

Passed to `paint_fn` with the node's bounding box coordinates:

```zig
pub const NodePaintContext = struct {
    x:       usize,       // bounding box left (column)
    y:       usize,       // bounding box top (row)
    width:   usize,       // bounding box width
    height:  usize,       // bounding box height (from NodeOptions)
    label:   []const u8,  // node label text
    node_id: usize,       // original graph ID
};
```

### NodeBorder shapes

| Variant | Appearance | Height |
|---|---|---|
| `.bracket` | `[label]` | 1 row |
| `.angle` | `<label>` | 1 row |
| `.none` | `label` (no border) | 1 row |
| `.single_box` | `┌─────┐` / `│label│` / `└─────┘` | 3 rows |
| `.heavy_box` | `┏━━━━━┓` / `┃label┃` / `┗━━━━━┛` | 3 rows |
| `.double_box` | `╔═════╗` / `║label║` / `╚═════╝` | 3 rows |
| `.rounded_box` | `╭─────╮` / `│label│` / `╰─────╯` | 3 rows |
| `.open_single` | `┌──  ` / `│label│` / `  ──┘` | 3 rows |
| `.open_heavy` | `┏━━  ` / `┃label┃` / `  ━━┛` | 3 rows |
| `.open_double` | `╔══  ` / `║label║` / `  ══╝` | 3 rows |
| `.open_rounded` | `╭──  ` / `│label│` / `  ──╯` | 3 rows |

The "open" variants (only TL + BR corners) visually suggest implicit or secondary nodes.

### Built-in node presets

```zig
// One-liner wiring — built-in presets do the explicit/implicit split automatically:
.node_style_fn = &zigraph.terminal_node_presets.singleBox,   // ┌─┐ / ┌──╯ open
.node_style_fn = &zigraph.terminal_node_presets.heavyBox,    // ┏━┓ / ┏━━╯ open
.node_style_fn = &zigraph.terminal_node_presets.doubleBox,   // ╔═╗ / ╔══╯ open
.node_style_fn = &zigraph.terminal_node_presets.roundedBox,  // ╭─╮ / ╭──╯ open
```

### Custom node style function

```zig
fn myNodeStyle(ctx: zigraph.NodeStyleContext) zigraph.TerminalNodeStyle {
    // Different border style per node label
    if (std.mem.eql(u8, ctx.label, "Error")) {
        return .{
            .border       = .heavy_box,
            .border_color = .{ .rgb = .{ .r = 220, .g = 50, .b = 50 } },
            .text_color   = .{ .rgb = .{ .r = 255, .g = 255, .b = 255 } },
        };
    }
    // Implicit nodes get open style
    if (ctx.is_implicit) return .{ .border = .open_single };
    return .{ .border = .single_box };
}

const output = try zigraph.terminal.renderWithConfig(&ir, alloc, .{
    .node_style_fn = &myNodeStyle,
});
```

### Text attributes

> **See it:** [`examples/terminal/text_attrs.zig`](../examples/terminal/text_attrs.zig)

> **Note:** Text attributes require `color_mode != .none`. In `.none` mode, no ANSI escapes are emitted and attrs are silently ignored.

Text attributes apply to **label text only** — border/box-drawing characters are not affected.
Attrs are supported on nodes (`TerminalNodeStyle`), edge labels (`TerminalEdgeLabelStyle`), and subgraph labels (`TerminalSubgraphStyle`).

```zig
fn boldNode(_: zigraph.NodeStyleContext) zigraph.TerminalNodeStyle {
    return .{
        .border = .single_box,
        .attrs  = .{ .bold = true, .italic = false },
    };
}
```

`TextAttrs` fields: `bold`, `dim`, `italic`, `underline` — all `bool`, default `false`.

---

## Edge styling

> **See it:** [`examples/terminal/edge_styles.zig`](../examples/terminal/edge_styles.zig)

### EdgeStyleContext fields

```zig
pub const EdgeStyleContext = struct {
    edge_index:  usize,           // unique index per original edge
    total_edges: usize,
    from_id:     usize,           // source node ID (IR direction)
    to_id:       usize,           // target node ID (IR direction)
    from_label:  []const u8,
    to_label:    []const u8,
    label:       ?[]const u8,     // edge label text, if any
    directed:    bool,
    reversed:    bool,            // true = back-edge (cycle broken)
    arena:       Allocator,
};
```

### TerminalEdgeStyle fields

```zig
pub const TerminalEdgeStyle = struct {
    color:        Color      = .default,  // line color
    weight:       LineWeight = .light,    // which box-drawing chars to use
    marker_end:   MarkerShape = .arrow,   // arrowhead at target
    marker_start: MarkerShape = .none,    // tail marker at source
};
```

### Line weights

| Variant | Characters | Use case |
|---|---|---|
| `.light` | `─ │` (default) | Normal edges |
| `.heavy` | `━ ┃` | Critical paths, emphasis |
| `.double` | `═ ║` | Strong boundaries, important links |
| `.dashed` | `┈ ┊` | Back-edges (applied automatically for reversed edges) |

```zig
fn heavyEdge(_: zigraph.EdgeStyleContext) zigraph.TerminalEdgeStyle {
    return .{ .weight = .heavy };
}

// Critical path: first edge is heavy, rest are light
fn criticalPath(ctx: zigraph.EdgeStyleContext) zigraph.TerminalEdgeStyle {
    return .{ .weight = if (ctx.edge_index == 0) .heavy else .light };
}
```

### Marker shapes

| Shape | Terminal char | Semantic |
|---|---|---|
| `.arrow` | `↓ ↑ → ←` | Default directed edges |
| `.filled_arrow` | `▼ ▲ ▶ ◀` | Heavy directed edges |
| `.open_arrow` | `▽ △ ▷ ◁` | UML inheritance |
| `.diamond` | `◆` | UML composition |
| `.open_diamond` | `◇` | UML aggregation |
| `.circle` | `●` | Association |
| `.open_circle` | `○` | Weak association |
| `.none` | (nothing) | Plain lines |

```zig
// Bidirectional with different end markers
fn biDi(_: zigraph.EdgeStyleContext) zigraph.TerminalEdgeStyle {
    return .{ .marker_start = .open_circle, .marker_end = .arrow };
}

// Rotate through all shapes by edge index
fn allMarkers(ctx: zigraph.EdgeStyleContext) zigraph.TerminalEdgeStyle {
    const shapes = [_]zigraph.MarkerShape{
        .arrow, .filled_arrow, .open_arrow, .diamond, .open_diamond, .circle, .open_circle,
    };
    return .{ .marker_end = shapes[ctx.edge_index % shapes.len] };
}
```

---

## Edge label styling

> **See it:** [`examples/terminal/edge_labels.zig`](../examples/terminal/edge_labels.zig)

Add a label to an edge at graph-build time:

```zig
try g.addEdgeLabeled(1, 2, "depends on");
```

Then control placement and color via `edge_label_style_fn`:

```zig
pub const TerminalEdgeLabelStyle = struct {
    color:     Color          = .default,  // .default follows edge color
    placement: LabelPlacement = .auto,
    attrs:     TextAttrs      = .{},
};
```

### Label placement options

| Variant | Effect |
|---|---|
| `.auto` | Layout-computed — tries to find a free cell near the edge |
| `.near_source` | Hugs the start (source) of the edge |
| `.near_target` | Hugs the end (target) of the edge |
| `.center` | Sits at the midpoint of the horizontal segment |

```zig
fn nearSource(_: zigraph.EdgeStyleContext) zigraph.TerminalEdgeLabelStyle {
    return .{ .placement = .near_source };
}

fn coloredLabels(ctx: zigraph.EdgeStyleContext) zigraph.TerminalEdgeLabelStyle {
    const palette = [_]zigraph.TerminalColor{
        .{ .ansi256 = 196 }, .{ .ansi256 = 46 }, .{ .ansi256 = 33 },
    };
    return .{
        .color     = palette[ctx.edge_index % palette.len],
        .placement = .center,
    };
}
```

When a label cannot be placed inline (e.g., dense graphs), it is automatically moved to a **legend** below the diagram.

---

## Color system

> **See it:** [`examples/terminal/color_system.zig`](../examples/terminal/color_system.zig)

### ColorMode — output encoding

Set once on `Config`; applies to all colors in the render pass.

```zig
const output = try zigraph.terminal.renderWithConfig(&ir, alloc, .{
    .color_mode = .none,       // no ANSI escapes (CI logs, pipe output)
    // .color_mode = .ansi256,  // \e[38;5;Nm (default — broad compat)
    // .color_mode = .truecolor,// \e[38;2;R;G;Bm (modern terminals)
});
```

### The Color union

Node/edge/subgraph color fields are typed `zigraph.TerminalColor` (alias for `terminal.Color`):

> **Color mode interaction:** When `color_mode = .ansi256` (the default), RGB and gradient colors are automatically quantized to the nearest ANSI 256-color index. For full-fidelity RGB output, set `.color_mode = .truecolor`. Conversely, ANSI 256 values are expanded to RGB when using `.truecolor` mode.

```zig
pub const Color = union(enum) {
    default,           // terminal default — no escape emitted
    ansi256: u8,       // ANSI 256 palette index (0–255)
    rgb: Rgb,          // 24-bit truecolor { r, g, b: u8 }
    gradient: GradientSpec, // per-cell color sampled from a ColorMap
};
```

```zig
// ANSI 256 — works everywhere
.color = .{ .ansi256 = 196 }   // red
.color = .{ .ansi256 = 46  }   // green
.color = .{ .ansi256 = 33  }   // blue

// Truecolor RGB — modern terminals
.color = .{ .rgb = .{ .r = 255, .g = 80, .b = 80 } }  // coral

// Gradient — per-cell color swept across the node/edge span
.color = .{ .gradient = .{
    .map  = &zigraph.color.ColorMap.viridis,
    .from = 0.2,
    .to   = 0.8,
} }
```

### Gradient colors

Gradients are sampled along the edge (left → right for horizontal segments, top → bottom for vertical). Available colormaps:

```zig
zigraph.color.ColorMap.viridis    // blue–green–yellow
zigraph.color.ColorMap.inferno    // black–red–yellow
zigraph.color.ColorMap.turbo      // full rainbow
zigraph.color.ColorMap.coolwarm   // blue–white–red
zigraph.color.ColorMap.plasma     // purple–orange–yellow
zigraph.color.ColorMap.magma      // black–purple–white
```

```zig
// Each edge gets a different slice of viridis
fn gradientEdges(ctx: zigraph.EdgeStyleContext) zigraph.TerminalEdgeStyle {
    const n = @as(f32, @floatFromInt(ctx.total_edges));
    const i = @as(f32, @floatFromInt(ctx.edge_index));
    return .{
        .color = .{ .gradient = .{
            .map  = &zigraph.color.ColorMap.viridis,
            .from = i / n,
            .to   = (i + 1.0) / n,
        } },
    };
}
```

### Discrete ANSI palette helper

```zig
fn paletteEdge(ctx: zigraph.EdgeStyleContext) zigraph.TerminalEdgeStyle {
    return .{ .color = .{
        .ansi256 = zigraph.color.getAnsi(&zigraph.color.ansi_dark, ctx.edge_index),
    } };
}
```

Available ANSI terminal palettes (for `getAnsi`): `ansi`, `ansi_dark`, `ansi_light`.

> **Note:** The hex-string palettes (`radix`, `vibrant`, `pastel`, `dark_mode`, etc.) are `[]const []const u8` and cannot be passed to `getAnsi()`. To use hex palettes in the terminal, convert with `zigraph.color.hexToAnsi256()` or use `.rgb` colors with `.color_mode = .truecolor`. See the [Color System guide](color-system.md) for the full palette reference.

### Colored nodes

Node `border_color`, `text_color`, and `bg_color` all accept the same `Color` union:

```zig
fn coloredNode(ctx: zigraph.NodeStyleContext) zigraph.TerminalNodeStyle {
    return .{
        .border       = .single_box,
        .border_color = .{ .rgb = .{ .r = 70, .g = 130, .b = 180 } }, // steel-blue
        .text_color   = .{ .rgb = .{ .r = 255, .g = 255, .b = 255 } }, // white
        .bg_color     = .default,
    };
}
```

`bg_color` fills the cell background behind the node (requires `color_mode != .none`).

---

## Subgraph styling

> **See it:** [`examples/terminal/subgraph_styles.zig`](../examples/terminal/subgraph_styles.zig)

Add a subgraph at graph-build time:

```zig
const sg = try g.addSubgraph("Backend");
try g.putNodes(&.{ node1_id, node2_id }).inside(sg);
```

### SubgraphStyleContext fields

```zig
pub const SubgraphStyleContext = struct {
    subgraph_id:      usize,
    parent_id:        ?usize,      // null = root-level
    label:            []const u8,
    depth:            usize,       // nesting depth: 0 = root
    total_subgraphs:  usize,
    width:            usize,
    height:           usize,
    arena:            Allocator,
};
```

### TerminalSubgraphStyle fields

```zig
pub const TerminalSubgraphStyle = struct {
    border:    SubgraphBorder = .double,      // box-drawing style
    color:     Color          = .default,     // border + label color (gradient not supported — falls back to no color)
    label_pos: LabelPosition  = .top_left,    // where to draw the label
    attrs:     TextAttrs      = .{},          // bold / dim / italic / underline (label text only)
};
```

### SubgraphBorder options

| Variant | Appearance |
|---|---|
| `.single` | `┌─┐ │ │ └─┘` |
| `.double` | `╔═╗ ║ ║ ╚═╝` (default) |
| `.heavy` | `┏━┓ ┃ ┃ ┗━┛` |
| `.dashed` | `┄ ┆` corners `┌┐└┘` |
| `.none` | No border (label only) |

### LabelPosition options

| Variant | Effect |
|---|---|
| `.top_left` | Label on top border, left-aligned (default) |
| `.top_center` | Label on top border, centered |
| `.inside` | One row below the top border |

### Built-in subgraph preset

```zig
// Cycles border style and ANSI color by nesting depth:
.subgraph_style_fn = &zigraph.terminal_subgraph_presets.depthCycled,
```

### Custom subgraph style function

```zig
fn mySubgraph(ctx: zigraph.SubgraphStyleContext) zigraph.TerminalSubgraphStyle {
    const borders = [_]zigraph.terminal.SubgraphBorder{ .double, .single, .dashed };
    const colors  = [_]u8{ 33, 34, 35 }; // blue, blue-green, magenta
    return .{
        .border    = borders[ctx.depth % borders.len],
        .color     = .{ .ansi256 = colors[ctx.depth % colors.len] },
        .label_pos = .top_center,
    };
}
```

---

## Output formats

> **See it:** [`examples/terminal/output_formats.zig`](../examples/terminal/output_formats.zig)

### ASCII charset

Replace all Unicode box-drawing characters with ASCII equivalents (`+`, `-`, `|`, `v`, `^`):

```zig
const output = try zigraph.terminal.renderWithConfig(&ir, alloc, .{
    .char_set = .ascii,
    .color_mode = .none,  // typically paired with no color
});
```

### HTML `<pre>` output

Produces `<pre>` with `<span style="color:...">` instead of ANSI escapes — embed directly in web pages:

```zig
const html = try zigraph.terminal.renderWithConfig(&ir, alloc, .{
    .output_format   = .html_pre,
    .color_mode      = .truecolor,
    .html_pre_style  = "font-family: 'JetBrains Mono', monospace; line-height: 1.4",
});
```

The default `html_pre_style` is `"font-family:monospace;line-height:1.2"`.

---

## Advanced: custom node content via paint_fn

> **See it:** [`examples/terminal/record_nodes.zig`](../examples/terminal/record_nodes.zig) and [`examples/terminal/db_diagram.zig`](../examples/terminal/db_diagram.zig)

For custom node shapes (e.g., ER-diagram record boxes with multiple field rows), use `paint_fn` on `TerminalNodeStyle`. This is the terminal equivalent of SVG's `shape_svg`.

The key idea: declare the node's full height via `NodeOptions`, then provide a `paint_fn` that draws whatever you want inside that bounding box. The layout engine respects the declared height, so edges route correctly around the full node.

### Pattern

1. Define your content struct with auto-computed dimensions:

```zig
const Entity = struct {
    name: []const u8,
    fields: []const Field,

    fn boxWidth(self: Entity) usize {
        var max_len: usize = self.name.len;
        for (self.fields) |f| {
            if (f.text.len > max_len) max_len = f.text.len;
        }
        return max_len + 2; // +2 for border columns
    }

    fn boxHeight(self: Entity) usize {
        return 4 + self.fields.len; // top + header + separator + fields + bottom
    }

    fn nodeOptions(self: Entity) zigraph.NodeOptions {
        return .{ .label = self.name, .width = self.boxWidth(), .height = self.boxHeight() };
    }

    fn paint(self: Entity, buf: *T.Buffer2D, ctx: T.NodePaintContext) void {
        // draw top border, header, separator, field rows, bottom border
        // within ctx.x, ctx.y, ctx.width, ctx.height
    }
};
```

2. Create file-scope instances and thin paint wrappers:

```zig
const server = Entity{ .name = "Server", .fields = &.{ ... } };

fn paintServer(buf: *T.Buffer2D, ctx: T.NodePaintContext) void {
    server.paint(buf, ctx);
}
```

3. Wire it up via `node_style_fn`:

```zig
fn nodeStyle(ctx: T.NodeStyleContext) T.TerminalNodeStyle {
    if (std.mem.eql(u8, ctx.label, "Server"))
        return .{ .border = .none, .paint_fn = &paintServer };
    return .{ .border = .single_box };
}
```

4. Build the graph with auto-computed dimensions and render normally:

```zig
try g.addNode(1, server.nodeOptions());  // width and height from content
var ir = try zigraph.layout(&g, alloc, .{});
const output = try T.renderWithConfig(&ir, alloc, .{ .node_style_fn = &nodeStyle });
```

No manual `RenderPlan`, `Buffer2D`, or `serializeBuffer` needed. The content struct is the single source of truth for dimensions and painting, so they can never go out of sync.

### Why paint_fn needs a wrapper

Zig function pointers cannot capture runtime state. The `paint_fn` signature is `*const fn (*Buffer2D, NodePaintContext) void`, so it cannot close over an `Entity` instance. The pattern is to use file-scope (comptime-known) content structs and a thin wrapper function per entity that calls `entity.paint(buf, ctx)`.

---

## Escape hatch: manual Buffer2D pipeline

For cases where `paint_fn` is not sufficient (e.g., painting outside the node bounding box, custom edge rendering, overlays), the low-level pipeline is still available.

`RenderPlan` also exposes **hit-testing** via `plan.elementAt(x, y)`, which returns which node, edge, or subgraph occupies a given cell. See [`examples/terminal/interactive_tui.zig`](../examples/terminal/interactive_tui.zig) for a complete mouse-interactive terminal demo using this API.

### API surface

```zig
// Build the render plan (resolves styles, Y-expansion, label placement)
var plan = try zigraph.terminal.RenderPlan.build(alloc, &ir, config);
defer plan.deinit();

// Allocate a 2D character + color buffer
var buf = try zigraph.terminal.Buffer2D.init(alloc, plan.width, plan.height);
defer buf.deinit(alloc);

// Paint in Z-order using the public paint functions:
for (plan.edge_plans) |ep| {
    zigraph.terminal.paintEdge(&buf, &ep.edge, ep.color, ep.weight, ep.marker_end, ep.marker_start);
}
const nodes = ir.getNodes();
for (plan.node_plans) |np| {
    zigraph.terminal.paintNode(&buf, &nodes[np.node_index], false, np.style, np.rendered_y, np.level_height);
}

// Serialize to any writer
const stdout = std.io.getStdOut().writer();
try zigraph.terminal.serializeBuffer(&buf, stdout, config, buf.height);
```

### Buffer2D API

```zig
buf.set(x, y, codepoint: u21)                        // write glyph only
buf.setWithColor(x, y, codepoint, color: CellColor)  // write glyph + fg color
buf.setBgColor(x, y, color: CellColor)               // write bg color only
buf.get(x, y) -> u21                                  // read glyph
buf.getColor(x, y) -> CellColor                      // read fg color
```

`CellColor` is a packed `u32`. Construct via:

```zig
const cc = zigraph.terminal.CellColor.rgb(70, 130, 180);   // 24-bit
const cc = zigraph.terminal.CellColor.ansi256(33);          // ANSI 256 index
const cc = zigraph.terminal.CellColor.none;                  // terminal default
```

To convert a `Color` (from a style function) to a `CellColor` for manual buffer writes:

```zig
const cc = zigraph.terminal.resolveColorAt(my_color, 0.0);  // t=0.0 for flat colors
```

---

## Config reference

```zig
pub const Config = struct {
    show_dummy_nodes:    bool        = false,  // debug: show dummy layout nodes
    show_subgraphs:      bool        = true,
    edge_palette:        ?[]const u8 = null,   // ANSI palette fallback; priority: edge_style_fn color > edge_palette > no color
    color_mode:          ColorMode   = .ansi256,
    char_set:            CharSet     = .unicode,
    output_format:       OutputFormat = .raw,
    html_pre_style:      []const u8  = "font-family:monospace;line-height:1.2",

    edge_style_fn:       *const fn (EdgeStyleContext) TerminalEdgeStyle       = &defaultEdgeStyle,
    node_style_fn:       *const fn (NodeStyleContext) TerminalNodeStyle       = &defaultNodeStyle,
    edge_label_style_fn: *const fn (EdgeStyleContext) TerminalEdgeLabelStyle  = &defaultEdgeLabelStyle,
    subgraph_style_fn:   *const fn (SubgraphStyleContext) TerminalSubgraphStyle = &defaultSubgraphStyle,
};
```

## Render API reference

```zig
// High-level (buffers output into []u8)
zigraph.terminal.render(&ir, alloc)                            -> ![]u8
zigraph.terminal.renderWithConfig(&ir, alloc, config)         -> ![]u8

// Streaming (writes directly to writer — zero allocation for output)
zigraph.terminal.renderStreaming(&ir, writer, alloc)           -> !void
zigraph.terminal.renderStreamingWithConfig(&ir, writer, alloc, config) -> !void

// Generic (accepts any coordinate type — converts to usize internally)
zigraph.terminal.renderGenericWithConfig(Coord, &ir, alloc, config) -> ![]u8
zigraph.terminal.renderGenericStreamingWithConfig(Coord, &ir, writer, alloc, config) -> !void

// Low-level pipeline
zigraph.terminal.RenderPlan.build(alloc, &ir, config)          -> !RenderPlan
zigraph.terminal.Buffer2D.init(alloc, width, height)           -> !Buffer2D
zigraph.terminal.paintNode(&buf, node, show_dummies, style, y, level_h) -> void
zigraph.terminal.paintEdge(&buf, edge, color, weight, end, start) -> void
zigraph.terminal.serializeBuffer(&buf, writer, config, height)  -> !void
```
