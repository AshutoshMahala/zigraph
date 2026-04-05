# Zigraph DSL Design Spec

**Date:** 2026-04-05
**Status:** Approved
**Scope:** Phase 1 — Parser, Resolver, Bridge, CLI, Markdown extraction

## 1. Overview

Zigraph DSL (`.zgraph`) is a text-based graph description language that provides a fast, intuitive, opinionated way to define and render graphs, trees, flowcharts, and other diagrams. It integrates with zigraph's existing layout engine and renderers.

### Design Principles

- **Zero friction for simple cases** — `A -> B -> C` is a complete diagram
- **Opinionated defaults** — great-looking output without configuration
- **Progressive complexity** — bare syntax for quick graphs, named blocks and `@` directives for power users
- **Portable embedding** — identical syntax in standalone files, markdown, and Typst
- **User is always in control** — every default is configurable and overridable

### Long-term Vision

Phase 1 delivers the graph DSL. Future phases extend toward a general visualization language (plots, charts, canvas primitives) inspired by Bluefish and Typst's ecosystem, with interactive TUI/web interfaces.

## 2. File Format

- **Extension:** `.zgraph` (standalone files)
- **Embedding:** ` ```zgraph ``` ` fenced code blocks (markdown, Typst, etc.)
- **Encoding:** UTF-8
- **Comments:** `#` line comments

## 3. Syntax Specification

### 3.1 Nodes

Nodes are created implicitly when mentioned in edges. Optional explicit declaration for labels, shapes, and properties.

```
# Implicit creation (mention = create, identifier = label)
Parse -> Compile

# Custom label
db: "PostgreSQL 15"

# Shape via keyword
db { shape: cylinder }
user { shape: person }
decision { shape: diamond }

# Inline combined
db: "PostgreSQL 15" { shape: cylinder; fill: "#336699" }

# Card/record nodes (pipe-bracket syntax)
service: [Auth Service | Port: 8080 | Status: healthy]

# Multi-line card
service: {
  shape: card
  | Auth Service
  | ---
  | Port: 8080
  | Status: healthy
  | Version: 2.1.0
}

# CSS-like class shorthand
db .database
api .primary .large
```

**Supported shapes:** `rect` (default), `circle`, `diamond`, `cylinder`, `person`, `pill`, `hexagon`, `parallelogram`, `queue`, `cloud`, `card`

### 3.2 Edges

Core operators plus extended visual operators. Chaining, fan-out, labels, and property blocks.

```
# Core operators
A -> B                  # directed
A <- B                  # reverse directed
A -- B                  # undirected
A <-> B                 # bidirectional

# Extended visual operators
A => B                  # bold/heavy
A ==> B                 # extra thick
A -.-> B                # dashed directed
A -..-> B               # dotted directed
A -..- B                # dotted undirected

# Chaining
A -> B -> C -> D

# Fan-out
A -> B, C, D
A -> { B; C; D }

# Labels
A -> B: "transforms"
A -.-> B: "optional"

# Edge properties
A -> B: "2ms" { stroke: green; style: dashed }
```

### 3.3 Subgraphs

D2-style brace nesting with dot-path cross-references.

**Disambiguation rule:** A brace block after `name:` is a **subgraph** if it contains statements (edges, node declarations). It's a **property block** if it contains only `key: value` pairs. The parser looks at the first non-whitespace content inside braces to decide.

```
# Container = identifier + braces
backend: {
  API -> Auth -> DB
}

frontend: {
  App -> Router -> Views
}

# Deep nesting
cloud: {
  backend: {
    API -> DB
  }
}

# Cross-container edges (dot-path)
frontend.App -> backend.API

# Container styling
backend {
  label: "Backend Services"
  fill: "#1a2a3a"
  border: dashed
}
```

### 3.4 Directives & Configuration

All configuration uses the unified `@` prefix. Works identically in standalone files and embedded blocks.

```
# Layout and display
@layout sugiyama          # or: force, tree
@theme dark               # built-in themes
@direction top-down       # or: left-right, bottom-up, right-left
@spacing compact          # or: normal, wide

# Style rules (CSS-like cascade)
@style node {
  fill: "#2a2a4a"
  shape: rect
}

@style edge {
  stroke: "#666"
}

@style .database {
  shape: cylinder
  fill: "#336699"
}

@style .critical {
  stroke: red
  stroke-width: 2
}
```

**Cascade order (lowest → highest priority):**
1. `@style node/edge` defaults
2. `@style .class` rules
3. Inline `{ property: value }` on elements

### 3.5 Named Blocks

Multi-diagram files use named blocks with explicit layout types. Bare syntax (no block) defaults to a DAG graph.

```
# Bare syntax = default graph
A -> B -> C

# Named blocks with layout type
pipeline [dag] {
  Parse -> Compile -> Link
}

modules [tree] {
  root -> utils
  root -> core -> parser
  root -> core -> codegen
}

deps [force] {
  react -- react-dom
  react -- scheduler
}

# Block-level directives override file-level
sidebar [dag] {
  @direction left-right
  @spacing wide
  X -> Y -> Z
}
```

**Block layout types:** `[dag]` (Sugiyama), `[tree]` (tree renderer), `[force]` (Fruchterman-Reingold)

### 3.6 Full Example

```
@layout sugiyama
@theme dark
@direction top-down

@style node { fill: "#2a2a4a" }
@style edge { stroke: "#555" }
@style .db { shape: cylinder; fill: "#336699" }
@style .critical { stroke: "#ff4444"; stroke-width: 2 }

# Main pipeline
Client -> API: "HTTPS"
API -> Auth: "validate"
Auth -.-> Cache: "check"
Auth -> API: "token"

backend: {
  API -> Router -> Handler
  Handler -> DB: "query" .critical
  DB: "PostgreSQL" .db
  Handler -> Queue: "async"
  Queue: [Message Queue | Type: Redis | Port: 6379]
}

# Separate view of module dependencies
modules [tree] {
  app -> handlers
  app -> middleware -> auth
  app -> middleware -> logging
  app -> models -> user
  app -> models -> session
}
```

### 3.7 Markdown Embedding

```markdown
# Architecture Overview

Here's the pipeline:

` ``zgraph
@layout sugiyama
Parse -> Compile -> Link -> Run
` ``

And the module tree:

` ``zgraph
@layout tree
root -> utils
root -> core -> parser
` ``
```

Each ` ```zgraph ``` ` block is an independent diagram with its own scope and directives.

## 4. Architecture

### 4.1 Pipeline

```
.zgraph file  or  ```zgraph``` block  or  stdin
                         │
                         ▼
                    ┌──────────┐
                    │ Tokenizer│  src/dsl/tokenizer.zig
                    └────┬─────┘
                         │
                         ▼
                    ┌──────────┐
                    │  Parser  │  src/dsl/parser.zig
                    └────┬─────┘
                         │
                         ▼
                    ┌──────────┐
                    │ Resolver │  src/dsl/resolver.zig
                    └────┬─────┘
                         │
                    Resolved AST
                         │
                         ▼
                    ┌──────────┐
                    │  Bridge  │  src/dsl/bridge.zig
                    └────┬─────┘
                         │
                    zigraph.Graph (one per block)
                         │
                    ┌────┼────┐
                    ▼    ▼    ▼
                 Terminal SVG JSON
```

### 4.2 Module Layout

```
src/
├── dsl/                        # NEW — all DSL code
│   ├── tokenizer.zig           # .zgraph text → Token stream
│   ├── parser.zig              # Token stream → AST
│   ├── ast.zig                 # AST node types
│   ├── resolver.zig            # Style cascade, implicit nodes, validation
│   ├── bridge.zig              # Resolved AST → zigraph.Graph
│   ├── markdown.zig            # Extract ```zgraph blocks from .md
│   └── errors.zig              # DSL-specific error types w/ line:col
│
├── cli/                        # NEW — CLI entry point
│   └── main.zig                # zigraph render/check commands
│
├── core/                       # EXISTING — untouched
├── algorithms/                 # EXISTING — untouched
└── render/                     # EXISTING — untouched
```

**Key principle:** The DSL is a new *frontend* to zigraph. It adds `src/dsl/` and `src/cli/` without modifying any existing code.

### 4.3 AST Node Types

```
Document
├── directives: []Directive        # @layout, @theme, @direction, @spacing
├── styles: []StyleRule            # @style node {}, @style .class {}
├── statements: []Statement        # bare graph content
└── blocks: []NamedBlock           # name [layout] { ... }

Statement = union {
    edge: EdgeStatement            # A -> B: "label" { props }
    node_decl: NodeDecl            # db: "PostgreSQL" { shape: cylinder }
    subgraph: Subgraph             # name: { ... }
    comment: Comment               # # text
}

EdgeStatement
├── chain: []NodeRef               # A -> B -> C (chain of nodes)
├── operator: EdgeOp               # ->, <-, --, <->, =>, -.-> etc.
├── label: ?[]const u8             # optional "label text"
├── properties: ?PropertyBlock     # { stroke: red }
└── classes: [][]const u8          # .critical .dashed

NodeRef
├── id: []const u8                 # identifier or dot-path
├── label: ?[]const u8             # "custom label"
├── card_fields: ?[][]const u8     # [Title | field | field]
├── properties: ?PropertyBlock
└── classes: [][]const u8

NamedBlock
├── name: []const u8               # block identifier
├── layout: ?Layout                # [dag], [tree], [force]
├── directives: []Directive        # block-level @directives
└── statements: []Statement
```

Every AST node carries a `Loc` (line, column, byte offset) for error reporting.

### 4.4 Resolver

The Resolver transforms the raw AST into a Resolved AST:

1. **Style cascade resolution** — `@style` defaults → `.class` rules → inline properties (highest priority)
2. **Implicit node creation** — nodes referenced in edges are created automatically
3. **Block scoping** — bare statements go to the default block; named blocks get their own scope
4. **Directive inheritance** — block-level directives override file-level directives
5. **Validation** — unknown directives, invalid property values, unresolved cross-block references, duplicate declarations → errors with line:col

### 4.5 Bridge

The Bridge converts each resolved block into a `zigraph.Graph`:

| Resolved AST | zigraph API |
|---|---|
| NodeRef | `graph.addNode(id, .{ .label, .width, .height, .lines })` |
| EdgeStatement (directed) | `graph.addDiEdge(from, to)` / `addDiEdgeLabeled` |
| EdgeStatement (undirected) | `graph.addUnDiEdge(from, to)` |
| Subgraph | `graph.addSubgraph()` + `graph.putNodes().inside()` |
| EdgeOp visual type | Stored as edge metadata for renderer styling |
| `@layout` directive | Selects preset (sugiyama / fruchterman_reingold) |
| `@direction` directive | Configures layout options |
| Card fields | `node.lines` (existing card node support) |

The Bridge does **not** modify existing Graph/Node/Edge types. Unknown style properties are stored as metadata for future renderers.

## 5. CLI Interface

### Phase 1 Commands

```bash
# Render .zgraph file to terminal (default)
zigraph render diagram.zgraph

# Render to specific format
zigraph render diagram.zgraph -f svg
zigraph render diagram.zgraph -f json
zigraph render diagram.zgraph -f svg -o output.svg

# Pipe from stdin
echo "A -> B -> C" | zigraph render
echo "A -> B -> C" | zigraph render -f svg

# Validate syntax
zigraph check diagram.zgraph

# Render ```zgraph blocks from markdown
zigraph render README.md
zigraph render README.md -f svg-inline    # inline SVGs in markdown output
```

## 6. Phasing

### Phase 1 (this spec)

- Tokenizer + Parser + AST
- Resolver (style cascade, implicit nodes, validation)
- Bridge (Resolved AST → zigraph.Graph)
- CLI: `zigraph render`, `zigraph check`
- Markdown: extract ` ```zgraph ``` ` blocks

### Phase 2 (future)

- **LSP** (language server protocol) — powered by AST + Resolver for editor integration
- Formatter (`zigraph fmt`) — AST round-trip preserving comments
- TUI editor (`zigraph edit`) — split-pane editor + live terminal preview
- `@import` directive — reusable style/block libraries
- Tree bridge — `[tree]` blocks → TreeNode[] renderer

### Phase 3 (future)

- Web viewer (`zigraph serve` / `zigraph watch`) — WASM-powered browser preview
- Playground (`zigraph playground`) — blank canvas in browser
- Document IR — formal multi-type intermediate representation
- Plot/chart blocks — `[plot]`, `[bar]`, `[timeline]`
- General visualization primitives (Bluefish-inspired compositional system)

## 7. Design Decisions Log

| Decision | Choice | Rationale |
|---|---|---|
| Syntax identity | Hybrid (bare + blocks) | Zero friction for simple cases, scales to multi-layout files |
| Edge syntax | A+B (core + extended) | `->`, `<-`, `--`, `<->` + visual `=>`, `-.->`, `-..->` |
| Node syntax | Implicit + keywords + bracket cards | Readable, no bracket-shape memorization |
| Subgraphs | D2-style braces | Consistent with block syntax |
| Configuration | Unified `@` directives | Portable across all host documents |
| Embedding | ` ```zgraph ``` ` | Short, clean, no conflict with host syntax |
| File extension | `.zgraph` | Clear branding |
| Architecture | Rich AST → Resolver → Bridge | Clean separation, AST reusable for tooling, evolves to Document IR |
| Interaction model | Layered (CLI → TUI → Web) | Build incrementally, all tiers share same engine |
