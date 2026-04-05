# Crossing Styles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add configurable crossing styles (`.flat`, `.arc`, `.gap`) to the terminal renderer so edge crossings can be visually distinguished from junctions.

**Architecture:** Add a `CrossingStyle` enum to config. Thread it through `paintEdge` → `drawLineCell` → `mergeJunctionWeighted`. When the merged result is a 4-way cross and style is `.arc` or `.gap`, return `⌒` or `' '` instead of `┼`.

**Tech Stack:** Zig 0.15.2, zigraph terminal renderer

---

## File Structure

| File | Responsibility |
|------|---------------|
| `src/render/terminal/config.zig` | Add `CrossingStyle` enum + `crossing_style` field to `Config` |
| `src/render/terminal/junctions.zig` | Modify `mergeJunctionWeighted` to accept and apply `CrossingStyle` |
| `src/render/terminal/edges.zig` | Thread `CrossingStyle` through `drawLineCell` and junction calls |
| `src/render/terminal/mod.zig` | Pass `crossing_style` from config to `paintEdge` |
| `src/render/terminal/render_tests.zig` | Integration test for arc/gap crossings |

---

### Task 1: Add `CrossingStyle` enum and config field

**Files:**
- Modify: `src/render/terminal/config.zig`

- [ ] **Step 1: Add `CrossingStyle` enum after `CharSet` enum (around line 43)**

In `src/render/terminal/config.zig`, add after the `CharSet` enum:

```zig
/// Crossing style for edge intersections.
pub const CrossingStyle = enum {
    flat, // ┼ (default, current behavior)
    arc, // ⌒ (horizontal hops over vertical)
    gap, // space (horizontal breaks at crossing)
};
```

- [ ] **Step 2: Add `crossing_style` field to `Config` struct**

In the `Config` struct (around line 367), add after `char_set`:

```zig
    /// How to render edge crossings (4-way intersections).
    crossing_style: CrossingStyle = .flat,
```

- [ ] **Step 3: Run tests to verify nothing breaks**

Run: `zig build test 2>&1; echo "EXIT: $?"`
Expected: EXIT: 0

- [ ] **Step 4: Commit**

```bash
git add src/render/terminal/config.zig
git commit -m "feat: add CrossingStyle enum and config field"
```

---

### Task 2: Modify `mergeJunctionWeighted` to accept `CrossingStyle`

**Files:**
- Modify: `src/render/terminal/junctions.zig`

- [ ] **Step 1: Write failing test**

Add at the end of `src/render/terminal/junctions.zig` (inside the test block area, or at end of file):

```zig
test "mergeJunctionWeighted: arc crossing style" {
    const CrossingStyle = @import("config.zig").CrossingStyle;
    // Vertical line exists, horizontal crosses it → should produce arc
    const result = mergeJunctionWeighted(CP_V_LINE, .{ .left = .light, .right = .light }, CrossingStyle.arc);
    try std.testing.expectEqual(@as(u21, 0x2312), result); // ⌒
}

test "mergeJunctionWeighted: gap crossing style" {
    const CrossingStyle = @import("config.zig").CrossingStyle;
    // Vertical line exists, horizontal crosses it → should produce space
    const result = mergeJunctionWeighted(CP_V_LINE, .{ .left = .light, .right = .light }, CrossingStyle.gap);
    try std.testing.expectEqual(@as(u21, ' '), result);
}

test "mergeJunctionWeighted: flat crossing style unchanged" {
    const CrossingStyle = @import("config.zig").CrossingStyle;
    // Flat should produce normal cross
    const result = mergeJunctionWeighted(CP_V_LINE, .{ .left = .light, .right = .light }, CrossingStyle.flat);
    try std.testing.expectEqual(CP_CROSS, result);
}

test "mergeJunctionWeighted: arc does not affect T-junctions" {
    const CrossingStyle = @import("config.zig").CrossingStyle;
    // T-junction (3-way) should be unchanged even with arc style
    const result = mergeJunctionWeighted(CP_V_LINE, .{ .right = .light }, CrossingStyle.arc);
    try std.testing.expectEqual(CP_T_RIGHT, result);
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zig build test 2>&1; echo "EXIT: $?"`
Expected: Compilation error — `mergeJunctionWeighted` doesn't accept 3 args yet.

- [ ] **Step 3: Modify `mergeJunctionWeighted` signature and implementation**

Change the function at line 642 from:

```zig
pub fn mergeJunctionWeighted(current: u21, new_dirs: DirWeights) u21 {
    // Protect marker chars: if the cell is a marker, don't merge over it.
    if (isMarkerChar(current)) return current;

    const existing = decomposeChar(current);
    const merged = existing.mergeWith(new_dirs);
    return lookupChar(merged);
}
```

To:

```zig
pub fn mergeJunctionWeighted(current: u21, new_dirs: DirWeights, crossing_style: @import("config.zig").CrossingStyle) u21 {
    if (isMarkerChar(current)) return current;

    const existing = decomposeChar(current);
    const merged = existing.mergeWith(new_dirs);
    const ch = lookupChar(merged);

    if (crossing_style != .flat) {
        const eu = merged.up.effective();
        const ed = merged.down.effective();
        const el = merged.left.effective();
        const er = merged.right.effective();
        if (eu != .none and ed != .none and el != .none and er != .none) {
            return switch (crossing_style) {
                .arc => 0x2312, // ⌒
                .gap => ' ',
                .flat => unreachable,
            };
        }
    }

    return ch;
}
```

- [ ] **Step 4: Update `mergeJunction` legacy wrapper to pass `.flat`**

Change the `mergeJunction` function (line ~653) from:

```zig
pub fn mergeJunction(current: u21, from_above: bool, to_below: bool, to_right: bool, to_left: bool) u21 {
    return mergeJunctionWeighted(current, .{
```

To:

```zig
pub fn mergeJunction(current: u21, from_above: bool, to_below: bool, to_right: bool, to_left: bool) u21 {
    return mergeJunctionWeighted(current, .{
        .up = if (from_above) .light else .none,
        .down = if (to_below) .light else .none,
        .right = if (to_right) .light else .none,
        .left = if (to_left) .light else .none,
    }, .flat);
}
```

- [ ] **Step 5: Update `mergeWithDoubleLine` wrapper similarly**

It calls `mergeJunction` which already passes `.flat`, so no change needed here.

- [ ] **Step 6: Run tests to verify they pass**

Run: `zig build test 2>&1; echo "EXIT: $?"`
Expected: EXIT: 0 (but compilation will fail because `edges.zig` calls `mergeJunctionWeighted` with 2 args still)

Note: This will fail because callers in `edges.zig` haven't been updated yet. That's expected — we'll fix them in Task 3.

- [ ] **Step 7: Commit (even if edges.zig callers are temporarily broken)**

Actually, to keep things compiling, let's do Task 3 before committing.

---

### Task 3: Thread `CrossingStyle` through `edges.zig`

**Files:**
- Modify: `src/render/terminal/edges.zig`
- Modify: `src/render/terminal/mod.zig`

- [ ] **Step 1: Add `CrossingStyle` import and parameter to `drawLineCell`**

In `edges.zig`, add to the imports (around line 14):

```zig
const CrossingStyle = config_mod.CrossingStyle;
```

Change `drawLineCell` (line 572) from:

```zig
fn drawLineCell(buffer: *Buffer2D, x: usize, y: usize, vertical: bool, color: CellColor, arm: ArmWeight) void {
    const new_dirs = DirWeights{
        .up = if (vertical) arm else .none,
        .down = if (vertical) arm else .none,
        .right = if (!vertical) arm else .none,
        .left = if (!vertical) arm else .none,
    };
    const cur = buffer.get(x, y);
    buffer.setWithColor(x, y, mergeJunctionWeighted(cur, new_dirs), color);
}
```

To:

```zig
fn drawLineCell(buffer: *Buffer2D, x: usize, y: usize, vertical: bool, color: CellColor, arm: ArmWeight, crossing_style: CrossingStyle) void {
    const new_dirs = DirWeights{
        .up = if (vertical) arm else .none,
        .down = if (vertical) arm else .none,
        .right = if (!vertical) arm else .none,
        .left = if (!vertical) arm else .none,
    };
    const cur = buffer.get(x, y);
    buffer.setWithColor(x, y, mergeJunctionWeighted(cur, new_dirs, crossing_style), color);
}
```

- [ ] **Step 2: Add `crossing_style` parameter to `paintEdge`**

Change the `paintEdge` signature (line 83) from:

```zig
pub fn paintEdge(buffer: *Buffer2D, edge: *const LayoutEdge, color: Color, weight: LineWeight, marker_end: MarkerShape, marker_start: MarkerShape) void {
```

To:

```zig
pub fn paintEdge(buffer: *Buffer2D, edge: *const LayoutEdge, color: Color, weight: LineWeight, marker_end: MarkerShape, marker_start: MarkerShape, crossing_style: CrossingStyle) void {
```

- [ ] **Step 3: Thread `crossing_style` through all internal functions**

This requires updating every function in `edges.zig` that calls `drawLineCell` or `mergeJunctionWeighted` directly. The changes are mechanical — add `crossing_style: CrossingStyle` as a parameter and pass it through.

Functions to update (add `crossing_style` parameter and pass to callees):

1. `drawDirectVertical` — add param, pass to `drawLineCell` calls
2. `drawDirectHorizontal` — add param, pass to `drawLineCell` calls
3. `drawDirectManhattan` — add param, pass to `drawVerticalSegment`, `drawLineCell`, and `mergeJunctionWeighted` calls
4. `paintCornerEdge` — add param, pass to `drawLineCell` and `mergeJunctionWeighted` calls
5. `paintBusEdge` — add param, pass to `drawLineCell` and `mergeJunctionWeighted` calls
6. `paintSideChannelEdge` — add param, pass to `drawLineCell` calls
7. `paintMultiSegmentEdge` — add param, pass to `drawLineCell` and `mergeJunctionWeighted` calls
8. `paintSplineEdge` — add param, pass to `drawLineCell` calls
9. `drawVerticalSegment` — add param, pass to `drawLineCell` calls
10. `drawManhattanArrow` — no `drawLineCell` calls, no change needed

For each function, the change is:
- Add `crossing_style: CrossingStyle` as the last parameter
- Pass `crossing_style` as the last argument to every `drawLineCell(...)` call
- Pass `crossing_style` as the third argument to every `mergeJunctionWeighted(...)` call
- Pass `crossing_style` to any sub-functions that also need it

In `paintEdge`, pass `crossing_style` to each path handler:

```zig
switch (edge.path) {
    .direct => {
        // ... existing code ...
        if (x0 == x1) {
            drawDirectVertical(buffer, x0, y0, y1, ec, weight, edge.directed, marker_end, crossing_style);
        } else if (y0 == y1) {
            drawDirectHorizontal(buffer, y0, x0, x1, ec, weight, edge.directed, marker_end, crossing_style);
        } else {
            drawDirectManhattan(buffer, x0, y0, x1, y1, ec, weight, edge.directed, edge.reversed, marker_end, marker_start, crossing_style);
        }
    },
    .corner => |corner| {
        paintCornerEdge(buffer, edge, corner.horizontal_y, ec, arm, marker_end, marker_start, crossing_style);
    },
    .side_channel => |sc| {
        paintSideChannelEdge(buffer, edge, sc.channel_x, sc.start_y, sc.end_y, ec, arm, marker_end, marker_start, crossing_style);
    },
    .multi_segment => {
        paintMultiSegmentEdge(buffer, edge, ec, arm, marker_end, marker_start, crossing_style);
    },
    .spline => {
        paintSplineEdge(buffer, edge, ec, arm, marker_end, marker_start, crossing_style);
    },
    .bus => |bus| {
        paintBusEdge(buffer, edge, bus, ec, arm, marker_end, marker_start, crossing_style);
    },
}
```

- [ ] **Step 4: Update `mod.zig` caller**

In `src/render/terminal/mod.zig`, find the `paintEdge` call (around line 337):

```zig
edge_render.paintEdge(&buffer, &ep.edge, ep.style_color, ep.weight, ep.marker_end, ep.marker_start);
```

Change to:

```zig
edge_render.paintEdge(&buffer, &ep.edge, ep.style_color, ep.weight, ep.marker_end, ep.marker_start, config.crossing_style);
```

Also update the re-export if needed. Check if any other file calls `paintEdge` directly (e.g., render_tests.zig) and update those too.

- [ ] **Step 5: Run tests**

Run: `zig build test 2>&1; echo "EXIT: $?"`
Expected: EXIT: 0

- [ ] **Step 6: Commit**

```bash
git add src/render/terminal/config.zig src/render/terminal/junctions.zig src/render/terminal/edges.zig src/render/terminal/mod.zig
git commit -m "feat: add crossing_style config with arc and gap modes"
```

---

### Task 4: Integration test

**Files:**
- Modify: `src/render/terminal/render_tests.zig`

- [ ] **Step 1: Add integration test for arc crossing**

Add a test that creates a LayoutIR where two edges cross, renders with `.arc` style, and verifies the crossing cell contains `⌒`:

```zig
test "terminal render: arc crossing style" {
    const allocator = std.testing.allocator;
    const LayoutIR = ir_mod.LayoutIR(usize);
    const LayoutNode = ir_mod.LayoutNode(usize);
    const LayoutEdge = ir_mod.LayoutEdge(usize);

    // Create a layout where edges cross:
    // Node A at (0, 0), Node B at (8, 0) — connected horizontally
    // Node C at (4, 0), Node D at (4, 4) — connected vertically through the horizontal edge
    // This forces a crossing at (4, 2)
    var nodes = [_]LayoutNode{
        .{ .id = 1, .x = 0, .y = 0, .width = 3, .height = 1, .label = "A", .level = 0 },
        .{ .id = 2, .x = 8, .y = 0, .width = 3, .height = 1, .label = "B", .level = 0 },
        .{ .id = 3, .x = 4, .y = 0, .width = 3, .height = 1, .label = "C", .level = 0 },
        .{ .id = 4, .x = 4, .y = 4, .width = 3, .height = 1, .label = "D", .level = 2 },
    };
    var edges = [_]LayoutEdge{
        // Horizontal edge A→B at y=2
        .{ .from_id = 1, .to_id = 2, .from_x = 1, .from_y = 1, .to_x = 9, .to_y = 1, .path = .direct, .directed = true },
        // Vertical edge C→D crossing the horizontal edge
        .{ .from_id = 3, .to_id = 4, .from_x = 5, .from_y = 1, .to_x = 5, .to_y = 4, .path = .direct, .directed = true },
    };

    var ir = LayoutIR{
        .nodes = &nodes,
        .edges = &edges,
        .width = 12,
        .height = 5,
        .edge_label_ct = 0,
        .subgraphs = &.{},
    };

    // Render with arc style
    const output = try renderWithConfig(&ir, allocator, .{
        .crossing_style = .arc,
        .color_mode = .none,
    });
    defer allocator.free(output);

    // The output should contain ⌒ where edges cross
    try std.testing.expect(std.mem.indexOf(u8, output, "\xe2\x8c\x92") != null); // ⌒ is U+2312 = 0xE2 0x8C 0x92
}
```

Note: The exact node/edge coordinates may need adjustment based on how the renderer lays things out. The key assertion is that `⌒` appears in the output. If this specific layout doesn't produce a crossing, adjust coordinates so that two edges genuinely overlap at a cell.

- [ ] **Step 2: Run tests**

Run: `zig build test 2>&1; echo "EXIT: $?"`
Expected: EXIT: 0

- [ ] **Step 3: Commit**

```bash
git add src/render/terminal/render_tests.zig
git commit -m "test: add integration test for arc crossing style"
```

---

### Task 5: Update `toAscii` for arc character

**Files:**
- Modify: `src/render/terminal/junctions.zig`

- [ ] **Step 1: Add `⌒` to `toAscii` mapping**

In `toAscii` (line 240), add a case for the arc character. In the `switch (cp)` block, add before the `else =>` arm:

```zig
0x2312 => '+', // ⌒ (arc crossing) → '+' in ASCII mode
```

- [ ] **Step 2: Write test**

```zig
test "toAscii: arc crossing character" {
    try std.testing.expectEqual(@as(u21, '+'), toAscii(0x2312));
}
```

- [ ] **Step 3: Run tests**

Run: `zig build test 2>&1; echo "EXIT: $?"`
Expected: EXIT: 0

- [ ] **Step 4: Commit**

```bash
git add src/render/terminal/junctions.zig
git commit -m "feat: add ASCII fallback for arc crossing character"
```
