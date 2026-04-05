# zgraph DSL Phase 2a — Core Language Extensions + Tier 1 Block Types

## Overview

Phase 2a extends the zgraph DSL with four new block types (`[tree]`, `[card]`, `[table]`, `[flow]`), the `@import` directive for file-level reuse, and D2-style vars + visual multiplicity. It also merges the table renderer from `feat/table-renderer` into the DSL worktree.

All Tier 1 block types leverage existing renderers — no new rendering code is needed, only bridge/resolver logic.

**Depends on:** Phase 1 (complete on `feat/zgraph-dsl-impl`)
**Branch:** `feat/zgraph-dsl-impl` worktree at `/Users/markussagen/code/hobby/zigraph-zgraph-dsl-impl`

---

## 1. Merge Table Renderer

Merge `origin/feat/table-renderer` into the DSL worktree. The table renderer is self-contained under `src/render/terminal/table.zig` (~693 LOC) with supporting test file, demo, and build registration.

**Files from feat/table-renderer:**
- `src/render/terminal/table.zig` — core implementation
- `src/render/terminal/table_tests.zig` — test suite
- `examples/terminal/table_demo.zig` — demo example
- `src/render/terminal/mod.zig` — re-export (`pub const table = @import("table.zig")`)
- `build.zig` — build target for demo

**Strategy:** Cherry-pick or merge the branch, resolve any conflicts with DSL worktree changes (likely only `build.zig` and `mod.zig`).

---

## 2. Block Type: `[tree]`

### Syntax

```zgraph
hierarchy [tree] {
  root -> utils
  root -> core -> parser
  root -> core -> codegen
  core -> tests
}
```

Edges define parent→child relationships. The graph is validated as a forest (no cycles, each node has at most one parent). Nodes with no incoming edges are roots.

### Resolver Changes

Add tree validation in the resolver for blocks with `layout = .tree`:

1. **Cycle detection:** DFS from each root. Error if a back-edge is found.
2. **Multi-parent check:** Each node must have ≤1 incoming edge. Error with location if violated.
3. **Root identification:** Nodes with zero incoming edges are roots. Error if no roots found (implies a cycle).

### Bridge Changes

New function `graphToTreeNodes()` in `bridge.zig` (or a new `tree_bridge.zig`):

```
fn graphToTreeNodes(resolved: ResolvedBlock, allocator: Allocator) ![]const TreeNode
```

1. Extract root nodes (no incoming edges).
2. For each node, collect children (outgoing edges, sorted by target ID for determinism).
3. Recursively build `TreeNode` structs with label and children.
4. Return array of root `TreeNode`s.

### Rendering

Use existing `zigraph.terminal.tree.render(roots, allocator, config)`. The tree renderer already supports multi-root forests, indentation, and box-drawing connectors.

For SVG/JSON output, convert TreeNode back to IR with tree layout positions (use existing tree layout algorithm).

### Error Messages

- `"cycle detected in [tree] block: A -> B -> C -> A"` — include the cycle path
- `"node 'X' has multiple parents in [tree] block: 'A' and 'B'"` — include both parent IDs with locations

---

## 3. Block Type: `[card]`

### Syntax

```zgraph
team [card] {
  alice: [Alice Smith | Engineering | Senior | alice@co.com]
  bob: [Bob Jones | Design | Lead]
  alice -> bob: "reports to"
}
```

Card nodes use the existing `[Title | field1 | field2 | ...]` syntax from Phase 1. The `[card]` block type is a hint that all nodes should default to card rendering (multi-line boxes) even if they don't use the `[...]` syntax.

### Resolver Changes

For blocks with `layout = .card`:
- Nodes without explicit card fields render as single-line cards (title only, but with card border style).
- The default node shape is overridden to `card` for all nodes in the block.

### Bridge Changes

Minimal — the card renderer is already integrated into the terminal renderer's node painting. The bridge just needs to set the default shape to `.card` for all nodes when the block layout is `.card`.

### Rendering

Existing card renderer in `src/render/terminal/card.zig` handles multi-line boxes with field separators. The Sugiyama layout engine computes node dimensions based on card content height/width.

---

## 4. Block Type: `[table]`

### Syntax

```zgraph
metrics [table] {
  headers: ID, Name, Status
  row: 1, Parser, done
  row: 2, Resolver, "in progress"
  row: 3, Bridge, planned
}
```

**Syntax rules:**
- `headers:` is optional. If omitted, table has no header row.
- `row:` lines define data rows. Columns are comma-separated.
- Quoted strings for values containing commas or whitespace.
- Table blocks do NOT support edges — they are pure data.

**Table-level properties (optional):**
```zgraph
metrics [table] {
  @border heavy
  @align right, left, center
  headers: ID, Name, Status
  row: 1, Parser, done
}
```

### Parser Changes

Add table-specific statement parsing when inside a `[table]` block:
- `headers:` → `TableHeaders` AST node with `[][]const u8` fields
- `row:` → `TableRow` AST node with `[][]const u8` fields
- `@border` → directive with value `none|single|heavy|double`
- `@align` → directive with comma-separated alignment values

### AST Changes

Add to `Statement` union:
```zig
table_headers: struct { fields: [][]const u8, loc: Loc },
table_row: struct { fields: [][]const u8, loc: Loc },
```

### Resolver Changes

Collect headers and rows from statements. Validate:
- All rows have the same number of columns as headers (or pad with empty strings).
- No edges in table blocks.
- `@align` column count matches header count.

### Bridge Changes

Table blocks produce a `BuiltTable` instead of a `BuiltGraph`:

```zig
pub const BuiltTable = struct {
    headers: ?[]const []const u8,
    rows: []const []const []const u8,
    config: terminal.table.TableConfig,
};
```

The `parseAndBuild` result gains a `tables` field alongside `graphs`.

### Rendering

Use `zigraph.terminal.table.render(headers, rows, allocator, config)` for string output. Use `paintTable()` for Buffer2D integration when tables are embedded in larger layouts.

---

## 5. Block Type: `[flow]`

### Syntax

```zgraph
pipeline [flow] {
  Input -> Parse -> Transform -> Output
  Transform -> Validate -> Output
}
```

`[flow]` is an alias for `[dag]` with implicit `@direction left-right`. It provides a semantic name for horizontal flowcharts.

### Implementation

In the resolver/bridge, when `layout = .flow`:
1. Set `layout = .dag` (Sugiyama).
2. Set `direction = .left_right` (unless explicitly overridden by a `@direction` directive in the block).

No new renderer, no new AST types.

---

## 6. `@import` Directive

### Syntax

```zgraph
@import "theme.zgraph"
@import "common/styles.zgraph"

server .production    // .production class defined in theme.zgraph
```

### Semantics

- **Resolution:** Relative to the importing file's directory. No search paths, no remote URLs.
- **Scope:** Imported file's `@style` rules and `vars {}` blocks are merged into the importing document. Named blocks and statements are NOT imported (style/config reuse only).
- **Conflict resolution:** Last rule wins. Imported styles are applied before the importing file's own styles, so local styles override imported ones.
- **Cycle detection:** Maintain a visited-file set during resolution. Error if a cycle is detected.
- **Transitive imports:** If A imports B and B imports C, then A gets B's and C's styles.

### Parser Changes

Add `@import` as a recognized directive kind:

```zig
pub const DirectiveKind = enum { layout, theme, direction, spacing, import_ };
```

The parser stores the path string in `Directive.value`.

### Resolver Changes

New `resolveImports()` pass before style cascade:

1. For each `@import` directive in the document:
   a. Resolve the path relative to the source file's directory.
   b. Check the visited set — error if already visited (cycle).
   c. Read the file contents.
   d. Tokenize + parse the imported file.
   e. Recursively resolve imports in the imported file.
   f. Merge the imported file's `@style` rules and `vars` into the current document's style list (prepended, so local styles override).
2. Remove `@import` directives from the final directive list.

### Error Messages

- `"import cycle detected: a.zgraph -> b.zgraph -> a.zgraph"` — include the full cycle path
- `"import file not found: 'missing.zgraph' (resolved to /full/path)"` — include both relative and resolved paths
- `"import read error: permission denied for 'secret.zgraph'"` — surface OS errors

### CLI Integration

The CLI's `render` and `check` commands already accept a file path. The resolver uses that path's directory as the base for import resolution.

---

## 7. Vars (D2-style)

### Syntax

```zgraph
vars {
  env: production
  db_name: PostgreSQL
  replicas: 3
}

server: "${env} server"
db: "${db_name}"
server -> db: "connects"
```

### Semantics

- **Declaration:** `vars { key: value }` block at the top level or within a named block.
- **Substitution:** `${name}` is replaced with the var's value during the resolver pass.
- **Scope:** Vars are scoped to their block. Top-level vars are global. Block vars override global vars.
- **Types:** All values are strings. No arithmetic, no expressions.
- **Substitution context:** Vars can appear in labels, property values, and card field content. NOT in identifiers, edge operators, or structural syntax.
- **Imported vars:** `@import`ed files' vars are merged (local vars override imported vars).

### Parser Changes

Add `vars {}` block parsing. The `vars` keyword is recognized at the top level and inside named blocks. Each line inside is `key: value` (reuses property parsing).

### AST Changes

Add to `Document` and `NamedBlock`:
```zig
vars: []Property,  // key-value pairs from vars {} block
```

### Resolver Changes

1. Collect vars from imports (bottom-up, imports first).
2. Collect vars from the current document/block (overrides imports).
3. Walk all labels, property values, and card fields.
4. Replace `${name}` occurrences with the var's value.
5. Error if `${name}` references an undefined var.

### Error Messages

- `"undefined variable '${missing}' at line 5"` — include the var name and location
- `"variable 'x' redefined at line 10 (first defined at line 3)"` — warning, not error

---

## 8. Visual Multiplicity (D2-style)

### Syntax

```zgraph
server { style.multiple: true }
// or as a property:
server { multiple: true }
```

### Rendering

A node with `multiple: true` is rendered with a stacked/shadow effect — a second box offset by 1 character right and 1 character down behind the main box. This indicates "there are many instances of this."

### Terminal Renderer Changes

In the node painting code (`src/render/terminal/nodes.zig` or equivalent), when a node has `multiple: true`:

1. Paint a shadow box at `(x+1, y+1)` with the same dimensions.
2. Paint the main box at `(x, y)` on top.
3. The shadow uses the same border style but a dimmer color (or the same color — keeps it simple).

Width/height of the node in the IR increases by 1 in each dimension to account for the shadow.

### SVG Renderer Changes

In SVG, render a second `<rect>` behind the main one, offset by a few pixels.

### IR/Layout Changes

The layout engine needs to know the effective node size (including shadow). The bridge adds +1 to width and +1 to height for multiplied nodes before layout.

### Property Resolution

`multiple` is resolved during the style cascade as a boolean node property. It can be set via:
- Inline: `server { multiple: true }`
- Class: `@style .replicated { multiple: true }` then `server .replicated`
- Global: `@style node { multiple: true }` (all nodes — unusual but valid)

---

## 9. Updated AST Summary

New/changed types:

```zig
pub const Layout = enum { dag, tree, force, card, table, flow };

pub const DirectiveKind = enum { layout, theme, direction, spacing, import_, border, align };

pub const Statement = union(enum) {
    edge: EdgeStatement,
    node_decl: NodeDecl,
    subgraph: SubgraphDecl,
    table_headers: struct { fields: [][]const u8, loc: Loc },
    table_row: struct { fields: [][]const u8, loc: Loc },
    vars_block: struct { vars: []Property, loc: Loc },
};

pub const Document = struct {
    directives: []Directive,
    styles: []StyleRule,
    statements: []Statement,
    blocks: []NamedBlock,
    vars: []Property,  // top-level vars
};
```

---

## 10. File Structure

New/modified files:

```
src/dsl/
  ast.zig          — Layout enum, DirectiveKind, Statement union (modified)
  tokenizer.zig    — vars, headers, row keywords (modified)
  parser.zig       — vars block, table statements, @import (modified)
  resolver.zig     — import resolution, var substitution, tree validation (modified)
  bridge.zig       — tree bridge, table bridge, flow alias (modified)
  imports.zig      — @import file resolution and cycle detection (new)
  tree_bridge.zig  — graph-to-TreeNode conversion (new)
  mod.zig          — re-export new modules (modified)

src/render/terminal/
  table.zig        — (merged from feat/table-renderer)
  table_tests.zig  — (merged from feat/table-renderer)
  nodes.zig        — multiplicity shadow rendering (modified)
  mod.zig          — table re-export (modified)

src/render/svg/
  nodes.zig        — multiplicity shadow rect (modified)

examples/
  dsl_demo.zig     — updated with new block types (modified)
  terminal/table_demo.zig — (merged from feat/table-renderer)
```

---

## 11. Testing Strategy

### Unit Tests

- **Tree validation:** Valid trees, cycles, multi-parent, no roots, single node, forest
- **Tree bridge:** Graph→TreeNode conversion, various topologies
- **Table parsing:** Headers + rows, no headers, quoted values, ragged rows
- **Table bridge:** BuiltTable construction, config mapping
- **Flow alias:** Verify direction defaults to left-right
- **@import:** Relative resolution, cycle detection, transitive imports, file not found, merge order
- **Vars:** Simple substitution, scoping (block overrides global), undefined var error, imported vars
- **Multiplicity:** Property resolution via inline, class, and global styles

### Integration Tests

- End-to-end: parse `[tree]` block → resolve → bridge → render terminal output
- End-to-end: parse `[table]` block → resolve → bridge → render terminal output
- End-to-end: parse `[flow]` block → verify left-right direction applied
- Import chain: A imports B imports C → verify merged styles
- Vars + import: imported vars used in importing file

### Example Files

- `examples/tree_demo.zgraph` — file hierarchy visualization
- `examples/table_demo.zgraph` — project status table
- `examples/flow_demo.zgraph` — horizontal pipeline
- `examples/import_demo/` — directory with main.zgraph + styles.zgraph

---

## 12. Phase 2a Non-Goals

- No new rendering engines (all Tier 1 types use existing renderers)
- No preprocessor / loops / conditionals (vars are simple substitution only)
- No remote imports (local files only)
- No `@import` search paths or package management
- No incremental parsing
- No Tier 2/3 block types ([grid], [sequence], [state], [er], [gantt], etc.)
- No formatter, LSP, or TUI (Phase 2d)

---

## 13. Phase 2 Roadmap (for context)

- **Phase 2a** (this spec): Merge table renderer + Tier 1 blocks + @import + vars + multiplicity
- **Phase 2b**: Tier 2 blocks — [grid], [sequence], [state], [er]
- **Phase 2c**: Tier 3 blocks — [gantt], [mindmap], [class], [kanban], [c4]
- **Phase 2d**: Formatter → LSP (using lsp-kit) → TUI editor
