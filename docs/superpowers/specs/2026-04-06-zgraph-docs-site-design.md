# zigraph Documentation Site — Design Spec

## Overview

A documentation site for zigraph built with Zine (static site generator), using SuperMD for content and SuperHTML for templating. The site covers all aspects of the project: diagramming primitives, DSL syntax, CLI, LSP, formatter, editor integration, syntax highlighting, and Zig library API.

**Target audience:** Both CLI users and Zig library embedders.

**GitHub strategy:** README.md serves as a landing page with badges, hero example, and prominent link to the deployed docs site. Full documentation lives exclusively in SuperMD — no duplication as plain markdown.

## Tech Stack

- **Zine** — Zig-based static site generator by kristoff-it
- **SuperMD** — Extended markdown for content pages
- **SuperHTML** — HTML templating with `:if`, `:loop`, `<super>` block inheritance
- **Deployment** — GitHub Pages (or similar static host)

## Site Layout

Three-column layout:

1. **Top navigation bar** — site logo ("zigraph"), major section links (Guide, Primitives, Tools, API), GitHub link
2. **Left sidebar** — page tree for current section, collapsible groups
3. **Main content** — page body with topic-first content and audience callouts (CLI vs Zig API)
4. **Right sidebar** — on-page table of contents, auto-generated from headings

Responsive: collapses to single column on mobile (hamburger menu for nav, TOC hidden).

Previous/next navigation links at the bottom of each page.

## Visual Examples

Input/output split view on every primitive and DSL page:

- **Left panel:** DSL source code (`.zgraph` input) with syntax highlighting
- **Right panel:** Rendered output with toggle between ASCII and SVG
- Split view uses a horizontal divider on mobile (stacked vertically)

SVG outputs are pre-rendered and embedded as inline SVG or `<img>` references. ASCII outputs shown in `<pre>` blocks.

## Content Structure

Topic-first organization. Where CLI and Zig API usage diverge, pages use callout blocks or labeled sections (e.g., "CLI Usage" / "Zig API") to show both perspectives.

### Section: Getting Started

| Page | Content |
|------|---------|
| Installation | Install via Zig package manager, build from source, pre-built binaries |
| Quick Start | First diagram end-to-end: write .zgraph file, render to SVG/ASCII via CLI |
| First Diagram | Step-by-step walkthrough with split-view example |

### Section: Primitives

One page per primitive, each with:
- Overview and use cases
- Split-view examples (DSL input → ASCII/SVG output)
- Configuration options (properties, styling)
- CLI usage and Zig API usage callouts

| Page | Primitive |
|------|-----------|
| Graph | Directed/undirected graphs, edge types, layouts |
| Tree | Hierarchical tree rendering |
| Card | Card-based node layouts |
| Table | Tabular data with headers/rows |
| Gantt | Gantt chart timelines |
| Flow | Flowchart diagrams |
| DAG | Directed acyclic graph layouts |

### Section: DSL Syntax

| Page | Content |
|------|---------|
| File Format | `.zgraph` file structure, encoding, comments (`#`) |
| Nodes & Blocks | Node declarations, block syntax `{}`, labels |
| Edges | All 9 edge operators (`->`, `<-`, `--`, `<->`, `=>`, `==>`, `-.->`, `-..->`, `-..-`), edge chains |
| Properties | Property lists `[key=val]`, annotations |
| Variables | `vars {}` blocks, `${name}` interpolation in strings |
| Directives | `@style`, `@layout`, and other `@`-prefixed directives |
| Styling & Theming | `@style` blocks, class references (`.classname`), colors, visual properties |

### Section: CLI

| Page | Content |
|------|---------|
| Commands | All CLI commands with usage examples |
| Options | Global and per-command flags |
| Output Formats | SVG, ASCII, and other output modes |

### Section: LSP & Formatter

| Page | Content |
|------|---------|
| LSP Features | Diagnostics, completions, hover, go-to-definition |
| Formatter | Auto-formatting rules, configuration |
| Configuration | LSP settings, formatter settings |

### Section: Editor Integration

| Page | Content |
|------|---------|
| Neovim | Tree-sitter parser install, highlight queries, LSP config, filetype detection |
| VS Code | Extension install, TextMate grammar, LSP client, settings |
| Other Editors | How to integrate LSP and formatter into any editor |

### Section: Syntax Highlighting

| Page | Content |
|------|---------|
| Tree-sitter Grammar | Grammar structure, node types, how it works |
| TextMate Grammar | VS Code `.tmLanguage.json`, scope names |
| Adding New Editors | How to write highlighting for other editors using the grammars |

### Section: Zig Library API

| Page | Content |
|------|---------|
| Embedding zigraph | Adding as a Zig dependency, `build.zig` setup |
| API Reference | Public types, functions, rendering pipeline |
| Examples | Zig code examples for common use cases |

## File Structure

```
docs/site/
├── build.zig              # Zine build configuration
├── build.zig.zon          # Zine dependency
├── content/
│   ├── index.md           # Landing/home page
│   ├── getting-started/
│   │   ├── index.md       # Installation
│   │   ├── quick-start.md
│   │   └── first-diagram.md
│   ├── primitives/
│   │   ├── index.md       # Primitives overview
│   │   ├── graph.md
│   │   ├── tree.md
│   │   ├── card.md
│   │   ├── table.md
│   │   ├── gantt.md
│   │   ├── flow.md
│   │   └── dag.md
│   ├── dsl/
│   │   ├── index.md       # DSL overview
│   │   ├── file-format.md
│   │   ├── nodes-and-blocks.md
│   │   ├── edges.md
│   │   ├── properties.md
│   │   ├── variables.md
│   │   ├── directives.md
│   │   └── styling.md
│   ├── cli/
│   │   ├── index.md
│   │   ├── commands.md
│   │   ├── options.md
│   │   └── output-formats.md
│   ├── lsp/
│   │   ├── index.md
│   │   ├── features.md
│   │   ├── formatter.md
│   │   └── configuration.md
│   ├── editors/
│   │   ├── index.md
│   │   ├── neovim.md
│   │   ├── vscode.md
│   │   └── other-editors.md
│   ├── syntax-highlighting/
│   │   ├── index.md
│   │   ├── tree-sitter.md
│   │   ├── textmate.md
│   │   └── adding-editors.md
│   └── zig-api/
│       ├── index.md
│       ├── embedding.md
│       ├── reference.md
│       └── examples.md
├── layouts/
│   ├── base.html          # Base template with three-column layout
│   ├── page.html          # Standard doc page (extends base)
│   ├── home.html          # Landing page (extends base)
│   └── partials/
│       ├── nav.html        # Top navigation bar
│       ├── sidebar.html    # Left sidebar page tree
│       ├── toc.html        # Right sidebar table of contents
│       ├── split-view.html # Input/output split-view component
│       └── footer.html     # Page footer with prev/next links
├── assets/
│   ├── css/
│   │   └── style.css      # Site styles
│   ├── js/
│   │   └── main.js        # ASCII/SVG toggle, mobile nav, TOC highlight
│   └── examples/
│       ├── svg/            # Pre-rendered SVG outputs
│       └── ascii/          # Pre-rendered ASCII outputs
└── static/
    └── favicon.ico
```

## SuperHTML Template Approach

Templates use SuperHTML's `<super>` block inheritance:

- `base.html` — defines `<super:head>`, `<super:content>`, `<super:sidebar>` blocks, includes nav/footer partials
- `page.html` — extends `base.html`, fills content block, generates TOC from headings
- `home.html` — extends `base.html`, custom hero layout

Audience callouts implemented as a SuperHTML partial or CSS-styled `<div>` blocks in SuperMD content:

```markdown
::: cli
Run the graph renderer:
\`\`\`bash
zigraph render graph.zgraph -o output.svg
\`\`\`
:::

::: zig
Use the Zig API:
\`\`\`zig
const graph = try zigraph.parse(allocator, source);
const svg = try graph.renderSvg(allocator);
\`\`\`
:::
```

## Split-View Component

The split-view partial (`split-view.html`) renders:

```html
<div class="split-view">
  <div class="split-input">
    <div class="split-label">input.zgraph</div>
    <pre><code class="language-zgraph">{{ input }}</code></pre>
  </div>
  <div class="split-output">
    <div class="split-tabs">
      <button class="active" data-target="svg">SVG</button>
      <button data-target="ascii">ASCII</button>
    </div>
    <div class="split-panel" data-panel="svg">{{ svg_output }}</div>
    <div class="split-panel" data-panel="ascii"><pre>{{ ascii_output }}</pre></div>
  </div>
</div>
```

Toggle logic in `main.js` — simple class toggle, no framework needed.

## Deployment

- Build: `zine release` outputs to `zig-out/` (static files)
- Deploy: GitHub Actions workflow builds on push to main, deploys to GitHub Pages
- Custom domain optional

## Out of Scope

- Interactive playground (future work — could use WASM-compiled zigraph)
- Search (Zine may add built-in search; defer until available)
- i18n / translations
- Blog section
