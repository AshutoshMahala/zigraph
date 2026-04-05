# Crossing Styles for Terminal Renderer

## Goal

Add configurable crossing styles to the terminal renderer so that when two independent edges cross, the intersection can visually distinguish them instead of merging into an ambiguous junction character.

## Problem

Currently, when a horizontal edge and a vertical edge cross, `mergeJunctionWeighted()` produces a 4-way junction like `┼`. This looks identical to a real 4-way connection, making it ambiguous whether edges are crossing or connecting.

```
       [C]              [C]              [C]
        │                │                │
[A]────┼────[B]  [A]────⌒────[B]  [A]──── ────[B]
        │                │                │
       [D]              [D]              [D]
     flat (current)      arc               gap
```

## Design

### Crossing Style Enum

Three modes, configured on the terminal renderer:

- **`.flat`** (default) — current behavior, produces `┼`/`╋`/`╬` at crossings
- **`.arc`** — replaces the crossing character with `⌒` (U+2312), visually showing the horizontal line hopping over the vertical
- **`.gap`** — replaces the crossing character with a space, breaking the horizontal line at the crossing point

### Detection

A crossing is detected when `mergeJunctionWeighted()` produces a result with all 4 directions filled (up, down, left, right all non-`.none`). This is the `┼` family of characters.

This simple heuristic works because true 4-way junctions are extremely rare in directed graphs — a 4-way merge almost always means two independent edges crossing.

### Weight Handling

The arc (`⌒`) and gap (` `) characters have no weight variants. When crossing style is `.arc` or `.gap`, the replacement applies regardless of the weight combination that produced the 4-way cross. The vertical line's character in the cell above and below the crossing remains unchanged, preserving visual continuity.

### Config Integration

```zig
// config.zig
pub const CrossingStyle = enum {
    flat,  // ┼ (default, current behavior)
    arc,   // ⌒ (horizontal hops over vertical)
    gap,   // space (horizontal breaks at crossing)
};

// Added to TerminalConfig
crossing_style: CrossingStyle = .flat,
```

### Implementation Approach

1. **`config.zig`** — Add `CrossingStyle` enum and field to `TerminalConfig`
2. **`junctions.zig`** — Modify `mergeJunctionWeighted()` to accept `CrossingStyle` parameter. When the merged result is a 4-way cross and style is not `.flat`, return the style-specific character instead
3. **`edges.zig`** — Thread `CrossingStyle` through `drawLineCell()` and other functions that call `mergeJunctionWeighted()`
4. **`mod.zig`** — Pass the crossing style from render config to edge painting functions
5. **Tests** — Unit tests for each crossing style in junction merging, integration test with a graph that produces crossings

### Files

| File | Change |
|------|--------|
| `src/render/terminal/config.zig` | Add `CrossingStyle` enum, add field to `TerminalConfig` |
| `src/render/terminal/junctions.zig` | Modify `mergeJunctionWeighted` signature + 4-way detection |
| `src/render/terminal/edges.zig` | Thread `CrossingStyle` to junction merge calls |
| `src/render/terminal/mod.zig` | Pass config to edge painting |
| `src/render/terminal/junctions_tests.zig` or inline | Tests for arc/gap crossing behavior |

### API Usage

```zig
const output = try zigraph.terminal.renderWithConfig(&ir, allocator, .{
    .crossing_style = .arc,
});
```

### What This Does NOT Change

- Corner characters (`┌┐└┘`) — unchanged
- T-junctions (`┬┴├┤`) — unchanged (3-way, not 4-way)
- Arrow markers (`↓↑→←`) — already protected from merging
- Default behavior — `.flat` preserves exact current output
