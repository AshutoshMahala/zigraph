# zigraph Documentation Site Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Zine-based documentation site covering all zigraph features — primitives, DSL, CLI, LSP, editors, syntax highlighting, and Zig API — with three-column layout, input/output split-view examples, and audience callouts for CLI users vs Zig embedders.

**Architecture:** Zine SSG with SuperMD content (`.smd`) and SuperHTML templates (`.shtml`). Config via `zine.ziggy`. Three-column layout: top nav, left sidebar, main content, right TOC. Visual examples use a CSS split-view with JS-powered ASCII/SVG toggle. Audience callouts use CSS-styled `<div>` blocks in SuperMD via `=html` escape hatches.

**Tech Stack:** Zine (v0.11.2+), SuperMD, SuperHTML, vanilla CSS + JS, GitHub Pages deployment

**Important Zine conventions:**
- Content files use `.smd` extension (not `.md`)
- Template files use `.shtml` extension (not `.html`)
- Config is `zine.ziggy` (Ziggy format)
- Frontmatter uses Ziggy syntax: `.title = "Page Title"`, `.layout = "page.shtml"`
- Templates use Scripty: `$page.title`, `$site.asset('style.css').link()`, `:text`, `:html`, `:if`, `:loop`
- `<super>` marks extension points in templates; parent element needs `id` attribute
- `<extend template="base.shtml">` to inherit from base
- Content routing: `content/foo/bar.smd` → `/foo/bar/`
- Sections: every `index.smd` defines a section with `$page.subpages()`

---

## File Map

```
docs/site/
├── zine.ziggy                     # Site configuration
├── content/
│   ├── index.smd                  # Home/landing page
│   ├── getting-started/
│   │   ├── index.smd              # Installation
│   │   ├── quick-start.smd
│   │   └── first-diagram.smd
│   ├── primitives/
│   │   ├── index.smd              # Primitives overview
│   │   ├── graph.smd
│   │   ├── tree.smd
│   │   ├── card.smd
│   │   ├── table.smd
│   │   ├── gantt.smd
│   │   ├── flow.smd
│   │   └── dag.smd
│   ├── dsl/
│   │   ├── index.smd              # DSL overview
│   │   ├── file-format.smd
│   │   ├── nodes-and-blocks.smd
│   │   ├── edges.smd
│   │   ├── properties.smd
│   │   ├── variables.smd
│   │   ├── directives.smd
│   │   └── styling.smd
│   ├── cli/
│   │   ├── index.smd
│   │   ├── commands.smd
│   │   ├── options.smd
│   │   └── output-formats.smd
│   ├── lsp/
│   │   ├── index.smd
│   │   ├── features.smd
│   │   ├── formatter.smd
│   │   └── configuration.smd
│   ├── editors/
│   │   ├── index.smd
│   │   ├── neovim.smd
│   │   ├── vscode.smd
│   │   └── other-editors.smd
│   ├── syntax-highlighting/
│   │   ├── index.smd
│   │   ├── tree-sitter.smd
│   │   ├── textmate.smd
│   │   └── adding-editors.smd
│   └── zig-api/
│       ├── index.smd
│       ├── embedding.smd
│       ├── reference.smd
│       └── examples.smd
├── layouts/
│   ├── templates/
│   │   └── base.shtml             # Base template (three-column layout)
│   ├── page.shtml                 # Standard doc page (extends base)
│   ├── home.shtml                 # Landing page (extends base)
│   └── section.shtml              # Section index page (extends base)
├── assets/
│   ├── style.css                  # All site styles
│   ├── main.js                    # ASCII/SVG toggle, mobile nav, TOC highlight
│   └── examples/
│       └── svg/                   # Pre-rendered SVG example outputs
│           ├── graph-basic.svg
│           ├── tree-basic.svg
│           └── ...
└── static/
    └── favicon.ico
```

---

### Task 1: Zine Project Scaffold

**Files:**
- Create: `docs/site/zine.ziggy`
- Modify: `.gitignore` (allow `docs/site/`, ignore `docs/site/zig-out/` and `docs/site/public/`)

- [ ] **Step 1: Update `.gitignore` to allow docs site**

Replace the blanket `docs/` ignore with specific ignores. In `.gitignore`, replace:

```
# Auto-generated docs (WASM playground)
docs/
```

with:

```
# Auto-generated docs output
docs/site/zig-out/
docs/site/public/
docs/site/.zig-cache/

# Keep superpowers specs/plans ignored on main (they live on feature branches)
# docs/superpowers/
```

- [ ] **Step 2: Create `docs/site/zine.ziggy`**

```ziggy
Site {
    .title = "zigraph",
    .host_url = "https://markussagen.github.io/zigraph",
    .content_dir_path = "content",
    .layouts_dir_path = "layouts",
    .assets_dir_path = "assets",
    .static_assets = [
        "favicon.ico",
    ],
}
```

- [ ] **Step 3: Create directory structure**

```bash
mkdir -p docs/site/{content,layouts/templates,assets/examples/svg,static}
```

- [ ] **Step 4: Create placeholder `docs/site/static/favicon.ico`**

Create an empty file (or copy from project if one exists):

```bash
touch docs/site/static/favicon.ico
```

- [ ] **Step 5: Commit**

```bash
git add docs/site/zine.ziggy docs/site/static/favicon.ico .gitignore
git commit -m "feat(docs): scaffold Zine site with config and directory structure"
```

---

### Task 2: Base Template (Three-Column Layout)

**Files:**
- Create: `docs/site/layouts/templates/base.shtml`
- Create: `docs/site/assets/style.css`

- [ ] **Step 1: Create `docs/site/layouts/templates/base.shtml`**

```html
<!DOCTYPE html>
<html lang="en">
  <head id="head">
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title id="title" :text="$page.title.suffix(' | zigraph')"></title>
    <link rel="stylesheet" href="$site.asset('style.css').link()">
    <super>
  </head>
  <body id="body">
    <nav class="top-nav" id="top-nav">
      <div class="nav-inner">
        <a href="$site.page('').link()" class="nav-logo">zigraph</a>
        <button class="nav-toggle" onclick="document.body.classList.toggle('nav-open')" aria-label="Toggle navigation">
          <span></span><span></span><span></span>
        </button>
        <div class="nav-links">
          <a href="$site.page('getting-started').link()">Guide</a>
          <a href="$site.page('primitives').link()">Primitives</a>
          <a href="$site.page('dsl').link()">DSL</a>
          <a href="$site.page('cli').link()">CLI</a>
          <a href="$site.page('lsp').link()">LSP</a>
          <a href="$site.page('editors').link()">Editors</a>
          <a href="$site.page('zig-api').link()">Zig API</a>
          <a href="https://github.com/markussagen/zigraph" class="nav-github">GitHub</a>
        </div>
      </div>
    </nav>
    <div class="layout">
      <aside class="sidebar" id="sidebar">
        <super>
      </aside>
      <main class="content" id="content">
        <super>
      </main>
      <aside class="toc" id="toc">
        <super>
      </aside>
    </div>
    <script src="$site.asset('main.js').link()"></script>
    <super>
  </body>
</html>
```

- [ ] **Step 2: Create `docs/site/assets/style.css`**

```css
/* === Reset & Base === */
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

:root {
  --c-bg: #0f1117;
  --c-surface: #161922;
  --c-border: #2a2d3a;
  --c-text: #e0e0e8;
  --c-text-muted: #8888a0;
  --c-accent: #818cf8;
  --c-accent-dim: rgba(129, 140, 248, 0.15);
  --c-code-bg: #1a1d2b;
  --c-nav-bg: #0c0e14;
  --sidebar-w: 240px;
  --toc-w: 200px;
  --nav-h: 56px;
  --content-max: 800px;
}

html { font-size: 16px; }
body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
  background: var(--c-bg);
  color: var(--c-text);
  line-height: 1.7;
}

a { color: var(--c-accent); text-decoration: none; }
a:hover { text-decoration: underline; }

/* === Top Nav === */
.top-nav {
  position: sticky;
  top: 0;
  z-index: 100;
  background: var(--c-nav-bg);
  border-bottom: 1px solid var(--c-border);
  height: var(--nav-h);
}
.nav-inner {
  max-width: calc(var(--sidebar-w) + var(--content-max) + var(--toc-w) + 4rem);
  margin: 0 auto;
  display: flex;
  align-items: center;
  height: 100%;
  padding: 0 1rem;
  gap: 1.5rem;
}
.nav-logo {
  font-weight: 700;
  font-size: 1.2rem;
  color: var(--c-text);
}
.nav-logo:hover { text-decoration: none; color: var(--c-accent); }
.nav-links { display: flex; gap: 1.25rem; font-size: 0.9rem; }
.nav-links a { color: var(--c-text-muted); }
.nav-links a:hover { color: var(--c-text); text-decoration: none; }
.nav-github { opacity: 0.6; }
.nav-toggle { display: none; background: none; border: none; cursor: pointer; }
.nav-toggle span {
  display: block;
  width: 20px;
  height: 2px;
  background: var(--c-text);
  margin: 4px 0;
}

/* === Three-Column Layout === */
.layout {
  max-width: calc(var(--sidebar-w) + var(--content-max) + var(--toc-w) + 4rem);
  margin: 0 auto;
  display: grid;
  grid-template-columns: var(--sidebar-w) minmax(0, var(--content-max)) var(--toc-w);
  gap: 2rem;
  padding: 2rem 1rem;
  min-height: calc(100vh - var(--nav-h));
}

/* === Sidebar === */
.sidebar {
  position: sticky;
  top: calc(var(--nav-h) + 1rem);
  align-self: start;
  max-height: calc(100vh - var(--nav-h) - 2rem);
  overflow-y: auto;
  font-size: 0.875rem;
  padding-right: 1rem;
}
.sidebar-group { margin-bottom: 1.25rem; }
.sidebar-heading {
  font-size: 0.75rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--c-text-muted);
  margin-bottom: 0.5rem;
}
.sidebar a {
  display: block;
  padding: 0.2rem 0;
  color: var(--c-text-muted);
}
.sidebar a:hover { color: var(--c-text); text-decoration: none; }
.sidebar a.active { color: var(--c-accent); font-weight: 500; }

/* === TOC (Right Sidebar) === */
.toc {
  position: sticky;
  top: calc(var(--nav-h) + 1rem);
  align-self: start;
  max-height: calc(100vh - var(--nav-h) - 2rem);
  overflow-y: auto;
  font-size: 0.8rem;
  padding-left: 1rem;
  border-left: 1px solid var(--c-border);
}
.toc-title {
  font-size: 0.7rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--c-text-muted);
  margin-bottom: 0.75rem;
}
.toc a {
  display: block;
  padding: 0.2rem 0;
  color: var(--c-text-muted);
}
.toc a:hover { color: var(--c-text); text-decoration: none; }
.toc a.active { color: var(--c-accent); }

/* === Content === */
.content {
  min-width: 0;
}
.content h1 { font-size: 2rem; margin-bottom: 0.5rem; }
.content h2 { font-size: 1.5rem; margin: 2rem 0 0.75rem; border-bottom: 1px solid var(--c-border); padding-bottom: 0.5rem; }
.content h3 { font-size: 1.2rem; margin: 1.5rem 0 0.5rem; }
.content h4 { font-size: 1rem; margin: 1.25rem 0 0.5rem; color: var(--c-text-muted); }
.content p { margin-bottom: 1rem; }
.content ul, .content ol { margin: 0 0 1rem 1.5rem; }
.content li { margin-bottom: 0.25rem; }
.content code {
  background: var(--c-code-bg);
  padding: 0.15em 0.35em;
  border-radius: 3px;
  font-size: 0.9em;
  font-family: "JetBrains Mono", "Fira Code", monospace;
}
.content pre {
  background: var(--c-code-bg);
  border: 1px solid var(--c-border);
  border-radius: 6px;
  padding: 1rem;
  overflow-x: auto;
  margin-bottom: 1rem;
  font-size: 0.85rem;
  line-height: 1.5;
}
.content pre code { background: none; padding: 0; }
.content table {
  width: 100%;
  border-collapse: collapse;
  margin-bottom: 1rem;
  font-size: 0.9rem;
}
.content th, .content td {
  border: 1px solid var(--c-border);
  padding: 0.5rem 0.75rem;
  text-align: left;
}
.content th { background: var(--c-surface); font-weight: 600; }

/* === Split-View (Input/Output Examples) === */
.split-view {
  display: grid;
  grid-template-columns: 1fr 1fr;
  border: 1px solid var(--c-border);
  border-radius: 6px;
  overflow: hidden;
  margin-bottom: 1.5rem;
}
.split-input, .split-output {
  padding: 1rem;
}
.split-input {
  background: var(--c-code-bg);
  border-right: 1px solid var(--c-border);
}
.split-output {
  background: var(--c-surface);
}
.split-label {
  font-size: 0.75rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--c-text-muted);
  margin-bottom: 0.5rem;
}
.split-tabs {
  display: flex;
  gap: 0.5rem;
  margin-bottom: 0.75rem;
}
.split-tabs button {
  background: none;
  border: 1px solid var(--c-border);
  border-radius: 4px;
  padding: 0.25rem 0.75rem;
  font-size: 0.8rem;
  color: var(--c-text-muted);
  cursor: pointer;
}
.split-tabs button.active {
  background: var(--c-accent-dim);
  border-color: var(--c-accent);
  color: var(--c-accent);
}
.split-panel { display: none; }
.split-panel.active { display: block; }
.split-panel pre { margin: 0; border: none; background: none; }
.split-panel svg { max-width: 100%; height: auto; }

/* === Audience Callouts === */
.callout {
  border-radius: 6px;
  padding: 1rem 1.25rem;
  margin-bottom: 1rem;
  border-left: 3px solid;
}
.callout-cli {
  background: rgba(52, 211, 153, 0.08);
  border-color: #34d399;
}
.callout-zig {
  background: rgba(251, 146, 60, 0.08);
  border-color: #fb923c;
}
.callout-label {
  font-size: 0.75rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  margin-bottom: 0.5rem;
}
.callout-cli .callout-label { color: #34d399; }
.callout-zig .callout-label { color: #fb923c; }

/* === Prev/Next Navigation === */
.page-nav {
  display: flex;
  justify-content: space-between;
  margin-top: 3rem;
  padding-top: 1.5rem;
  border-top: 1px solid var(--c-border);
}
.page-nav a {
  font-size: 0.9rem;
  color: var(--c-text-muted);
}
.page-nav a:hover { color: var(--c-accent); }

/* === Home Hero === */
.hero { text-align: center; padding: 3rem 0 2rem; }
.hero h1 { font-size: 2.5rem; margin-bottom: 0.5rem; }
.hero p { font-size: 1.1rem; color: var(--c-text-muted); max-width: 600px; margin: 0 auto 2rem; }
.hero-actions { display: flex; gap: 1rem; justify-content: center; }
.hero-actions a {
  padding: 0.6rem 1.5rem;
  border-radius: 6px;
  font-weight: 500;
}
.btn-primary { background: var(--c-accent); color: #fff; }
.btn-primary:hover { text-decoration: none; opacity: 0.9; }
.btn-secondary { border: 1px solid var(--c-border); color: var(--c-text); }
.btn-secondary:hover { text-decoration: none; border-color: var(--c-accent); }

/* === Responsive === */
@media (max-width: 1024px) {
  .layout {
    grid-template-columns: 1fr;
    padding: 1rem;
  }
  .sidebar, .toc { display: none; }
  .nav-toggle { display: block; }
  .nav-links { display: none; }
  body.nav-open .nav-links {
    display: flex;
    flex-direction: column;
    position: absolute;
    top: var(--nav-h);
    left: 0;
    right: 0;
    background: var(--c-nav-bg);
    border-bottom: 1px solid var(--c-border);
    padding: 1rem;
  }
  .split-view { grid-template-columns: 1fr; }
  .split-input { border-right: none; border-bottom: 1px solid var(--c-border); }
}
```

- [ ] **Step 3: Verify the template renders valid HTML structure**

Open the file and verify:
- Every `<super>` parent has an `id` attribute (head, body, top-nav, sidebar, content, toc)
- The template is well-formed HTML
- All Scripty references use valid API (`$site.page()`, `$site.asset()`)

- [ ] **Step 4: Commit**

```bash
git add docs/site/layouts/templates/base.shtml docs/site/assets/style.css
git commit -m "feat(docs): add base template with three-column layout and styles"
```

---

### Task 3: Page, Home, and Section Templates

**Files:**
- Create: `docs/site/layouts/page.shtml`
- Create: `docs/site/layouts/home.shtml`
- Create: `docs/site/layouts/section.shtml`
- Create: `docs/site/assets/main.js`

- [ ] **Step 1: Create `docs/site/layouts/page.shtml`**

```html
<extend template="base.shtml">
<head id="head">
</head>
<body id="body">
  <nav class="top-nav" id="top-nav">
  </nav>
  <aside class="sidebar" id="sidebar">
    <div :html="$page.parentSection().content()"></div>
  </aside>
  <main class="content" id="content">
    <h1 :text="$page.title"></h1>
    <div :html="$page.content()"></div>
    <div class="page-nav">
      <ctx :if="$page.prevPage?()">
        <a href="$if.link()">
          &larr; <span :text="$if.title"></span>
        </a>
      </ctx>
      <ctx :if="$page.prevPage?().not()">
        <span></span>
      </ctx>
      <ctx :if="$page.nextPage?()">
        <a href="$if.link()">
          <span :text="$if.title"></span> &rarr;
        </a>
      </ctx>
    </div>
  </main>
  <aside class="toc" id="toc">
    <div class="toc-title">On this page</div>
    <div :html="$page.toc()"></div>
  </aside>
</body>
```

- [ ] **Step 2: Create `docs/site/layouts/home.shtml`**

```html
<extend template="base.shtml">
<head id="head">
</head>
<body id="body">
  <nav class="top-nav" id="top-nav">
  </nav>
  <aside class="sidebar" id="sidebar">
  </aside>
  <main class="content" id="content">
    <div :html="$page.content()"></div>
  </main>
  <aside class="toc" id="toc">
  </aside>
</body>
```

- [ ] **Step 3: Create `docs/site/layouts/section.shtml`**

```html
<extend template="base.shtml">
<head id="head">
</head>
<body id="body">
  <nav class="top-nav" id="top-nav">
  </nav>
  <aside class="sidebar" id="sidebar">
    <div class="sidebar-group">
      <div class="sidebar-heading" :text="$page.title"></div>
      <div :loop="$page.subpages()">
        <a href="$loop.it.link()" :text="$loop.it.title"></a>
      </div>
    </div>
  </aside>
  <main class="content" id="content">
    <h1 :text="$page.title"></h1>
    <div :html="$page.content()"></div>
    <div :loop="$page.subpages()">
      <h3>
        <a href="$loop.it.link()" :text="$loop.it.title"></a>
      </h3>
      <ctx :if="$loop.it.description">
        <p :text="$if"></p>
      </ctx>
    </div>
  </main>
  <aside class="toc" id="toc">
  </aside>
</body>
```

- [ ] **Step 4: Create `docs/site/assets/main.js`**

```javascript
// Split-view ASCII/SVG toggle
document.addEventListener("click", function (e) {
  var btn = e.target.closest(".split-tabs button");
  if (!btn) return;
  var view = btn.closest(".split-view");
  var target = btn.getAttribute("data-target");

  view.querySelectorAll(".split-tabs button").forEach(function (b) {
    b.classList.toggle("active", b === btn);
  });
  view.querySelectorAll(".split-panel").forEach(function (p) {
    p.classList.toggle("active", p.getAttribute("data-panel") === target);
  });
});

// TOC scroll highlight
(function () {
  var tocLinks = document.querySelectorAll(".toc a");
  if (!tocLinks.length) return;

  var headings = [];
  tocLinks.forEach(function (link) {
    var id = link.getAttribute("href");
    if (id && id.startsWith("#")) {
      var el = document.getElementById(id.slice(1));
      if (el) headings.push({ el: el, link: link });
    }
  });

  function updateToc() {
    var scrollY = window.scrollY + 80;
    var current = null;
    for (var i = 0; i < headings.length; i++) {
      if (headings[i].el.offsetTop <= scrollY) {
        current = headings[i];
      }
    }
    tocLinks.forEach(function (l) { l.classList.remove("active"); });
    if (current) current.link.classList.add("active");
  }

  window.addEventListener("scroll", updateToc, { passive: true });
  updateToc();
})();
```

- [ ] **Step 5: Commit**

```bash
git add docs/site/layouts/page.shtml docs/site/layouts/home.shtml docs/site/layouts/section.shtml docs/site/assets/main.js
git commit -m "feat(docs): add page, home, and section templates with JS interactivity"
```

---

### Task 4: Home Page and Getting Started Section

**Files:**
- Create: `docs/site/content/index.smd`
- Create: `docs/site/content/getting-started/index.smd`
- Create: `docs/site/content/getting-started/quick-start.smd`
- Create: `docs/site/content/getting-started/first-diagram.smd`

- [ ] **Step 1: Create `docs/site/content/index.smd`**

```
---
.title = "zigraph",
.layout = "home.shtml",
.description = "Zero-dependency graph layout engine for Zig",
---

```=html
<div class="hero">
  <h1>zigraph</h1>
  <p>Zero-dependency graph layout engine for Zig. Visualize DAGs, dependency trees, and flow graphs in terminals, SVG, or JSON.</p>
  <div class="hero-actions">
    <a href="/getting-started/" class="btn-primary">Get Started</a>
    <a href="/primitives/" class="btn-secondary">Browse Primitives</a>
  </div>
</div>
```

## Features

- **Zero dependencies** — Pure Zig, no libc required
- **Two layout engines** — Sugiyama (hierarchical DAGs) and Fruchterman-Reingold (force-directed)
- **Multiple renderers** — Unicode terminal, SVG with splines, JSON for tooling
- **DSL support** — Write `.zgraph` files with a concise graph description language
- **Editor integration** — Syntax highlighting and LSP for Neovim and VS Code

## Quick Example

```zig
const zigraph = @import("zigraph");

var g = zigraph.Graph.init(allocator);
defer g.deinit();

try g.addNode(1, "main.zig");
try g.addNode(2, "http.zig");
try g.addNode(3, "json.zig");

try g.addEdge(1, 2);
try g.addEdge(1, 3);

var ir = try zigraph.layout(&g, allocator, .{});
defer ir.deinit();
const svg = try zigraph.svg.render(ir, allocator, .{});
```
```

- [ ] **Step 2: Create `docs/site/content/getting-started/index.smd`**

```
---
.title = "Getting Started",
.layout = "section.shtml",
.description = "Install zigraph and create your first diagram",
---

Get up and running with zigraph. Whether you're using the CLI to render diagrams or embedding the library in a Zig project, this guide walks you through installation and your first visualization.
```

- [ ] **Step 3: Create `docs/site/content/getting-started/quick-start.smd`**

```
---
.title = "Quick Start",
.layout = "page.shtml",
.date = @date("2026-04-06T00:00:00"),
.description = "Create your first diagram in under a minute",
---

## Install

Add zigraph as a dependency in your `build.zig.zon`:

```bash
zig fetch --save git+https://github.com/markussagen/zigraph
```

Then in your `build.zig`:

```zig
const zigraph_dep = b.dependency("zigraph", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("zigraph", zigraph_dep.module("zigraph"));
```

## Your First Graph

Create a file `main.zig`:

```zig
const std = @import("std");
const zigraph = @import("zigraph");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var g = zigraph.Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "main.zig");
    try g.addNode(2, "http.zig");
    try g.addNode(3, "json.zig");
    try g.addNode(4, "db.zig");

    try g.addEdge(1, 2);
    try g.addEdge(1, 3);
    try g.addEdge(2, 4);
    try g.addEdge(3, 4);

    var ir = try zigraph.layout(&g, allocator, .{});
    defer ir.deinit();

    const svg = try zigraph.svg.render(ir, allocator, .{});
    defer allocator.free(svg);

    const file = try std.fs.cwd().createFile("output.svg", .{});
    defer file.close();
    try file.writeAll(svg);
}
```

Run it:

```bash
zig build run
```

This generates `output.svg` with your dependency graph laid out using the Sugiyama algorithm.

## Terminal Output

For terminal rendering, swap the SVG renderer:

```zig
const terminal = zigraph.terminal;
const text = try terminal.render(ir, allocator, .{});
defer allocator.free(text);
std.debug.print("{s}\n", .{text});
```

```

- [ ] **Step 4: Create `docs/site/content/getting-started/first-diagram.smd`**

```
---
.title = "First Diagram",
.layout = "page.shtml",
.date = @date("2026-04-06T00:00:00"),
.description = "Step-by-step walkthrough with visual output",
---

## What We're Building

A simple dependency graph showing how modules relate to each other. We'll render it to both ASCII (terminal) and SVG.

```=html
<div class="split-view">
  <div class="split-input">
    <div class="split-label">Zig Source</div>
    <pre><code>var g = zigraph.Graph.init(allocator);

try g.addNode(1, "main.zig");
try g.addNode(2, "http.zig");
try g.addNode(3, "json.zig");
try g.addNode(4, "auth.zig");
try g.addNode(5, "db.zig");
try g.addNode(6, "log.zig");

try g.addEdge(1, 2);
try g.addEdge(1, 3);
try g.addEdge(2, 4);
try g.addEdge(2, 5);
try g.addEdge(3, 5);
try g.addEdge(4, 6);
try g.addEdge(5, 6);</code></pre>
  </div>
  <div class="split-output">
    <div class="split-tabs">
      <button class="active" data-target="svg">SVG</button>
      <button data-target="ascii">ASCII</button>
    </div>
    <div class="split-panel active" data-panel="svg">
      <p><em>SVG output renders a layered DAG with nodes arranged by dependency depth.</em></p>
    </div>
    <div class="split-panel" data-panel="ascii">
      <pre>          ┌──────────┐
          │ main.zig │
          └────┬─────┘
         ┌─────┴─────┐
         v            v
    ┌──────────┐ ┌──────────┐
    │ http.zig │ │ json.zig │
    └────┬─────┘ └────┬─────┘
    ┌────┴──┐         │
    v       v         v
┌──────┐ ┌──────┐
│ auth │ │  db  │
└───┬──┘ └───┬──┘
    └────┬────┘
         v
    ┌─────────┐
    │ log.zig │
    └─────────┘</pre>
    </div>
  </div>
</div>
```

## Step by Step

### 1. Create the graph

Every graph starts with `Graph.init` and explicit allocator:

```zig
var g = zigraph.Graph.init(allocator);
defer g.deinit();
```

### 2. Add nodes

Nodes have a numeric ID and a label string:

```zig
try g.addNode(1, "main.zig");
try g.addNode(2, "http.zig");
```

### 3. Add edges

Directed edges point from source to target:

```zig
try g.addEdge(1, 2); // main.zig -> http.zig
```

### 4. Compute layout

The layout engine assigns positions to all nodes:

```zig
var ir = try zigraph.layout(&g, allocator, .{});
defer ir.deinit();
```

### 5. Render

Choose your renderer — SVG for files, terminal for quick previews:

```zig
// SVG
const svg = try zigraph.svg.render(ir, allocator, .{});

// Terminal
const text = try zigraph.terminal.render(ir, allocator, .{});
```

## Next Steps

- Explore [Primitives](/primitives/) for graph, tree, card, table, and more
- Learn the [DSL syntax](/dsl/) for writing `.zgraph` files
- Set up [editor integration](/editors/) for syntax highlighting

```

- [ ] **Step 5: Verify content is valid SuperMD**

Check that:
- All frontmatter uses Ziggy syntax (`.title = "..."`, `.layout = "..."`)
- Every file has `.layout` set
- Section index files use `section.shtml`, content pages use `page.shtml`
- HTML escape hatches use `` ```=html `` fencing

- [ ] **Step 6: Commit**

```bash
git add docs/site/content/index.smd docs/site/content/getting-started/
git commit -m "feat(docs): add home page and getting started section"
```

---

### Task 5: Primitives Section

**Files:**
- Create: `docs/site/content/primitives/index.smd`
- Create: `docs/site/content/primitives/graph.smd`
- Create: `docs/site/content/primitives/tree.smd`
- Create: `docs/site/content/primitives/card.smd`
- Create: `docs/site/content/primitives/table.smd`
- Create: `docs/site/content/primitives/gantt.smd`
- Create: `docs/site/content/primitives/flow.smd`
- Create: `docs/site/content/primitives/dag.smd`

- [ ] **Step 1: Create `docs/site/content/primitives/index.smd`**

```
---
.title = "Primitives",
.layout = "section.shtml",
.description = "Visual building blocks: graph, tree, card, table, gantt, flow, and DAG",
---

zigraph provides several diagramming primitives. Each primitive has its own layout algorithm and rendering options. All primitives can be rendered to terminal (ASCII/Unicode), SVG, or JSON.
```

- [ ] **Step 2: Create `docs/site/content/primitives/graph.smd`**

```
---
.title = "Graph",
.layout = "page.shtml",
.date = @date("2026-04-06T00:00:00"),
.description = "Directed and undirected graphs with the Sugiyama layered layout",
---

The graph primitive is zigraph's core — a general-purpose directed or undirected graph rendered using the Sugiyama hierarchical layout algorithm.

## Overview

Graphs consist of **nodes** (labeled boxes) and **edges** (directed or undirected connections). The Sugiyama algorithm arranges nodes in layers to minimize edge crossings, producing clean, readable layouts.

```=html
<div class="split-view">
  <div class="split-input">
    <div class="split-label">input.zgraph</div>
    <pre><code># A simple dependency graph
server [label="API Server"]
db [label="PostgreSQL"]
cache [label="Redis"]
worker [label="Worker"]

server -> db
server -> cache
server -> worker
worker -> db
cache -.-> db</code></pre>
  </div>
  <div class="split-output">
    <div class="split-tabs">
      <button class="active" data-target="svg">SVG</button>
      <button data-target="ascii">ASCII</button>
    </div>
    <div class="split-panel active" data-panel="svg">
      <p><em>Layered DAG with API Server at top, dependencies below.</em></p>
    </div>
    <div class="split-panel" data-panel="ascii">
      <pre>       ┌────────────┐
       │ API Server │
       └──┬──┬──┬───┘
          │  │  │
          v  │  v
   ┌──────┐  │  ┌────────┐
   │Redis │  │  │ Worker │
   └──┬───┘  │  └───┬────┘
      :      │      │
      v      v      v
      ┌────────────┐
      │ PostgreSQL │
      └────────────┘</pre>
    </div>
  </div>
</div>
```

## Edge Types

| Operator | Meaning | Style |
|----------|---------|-------|
| `->` | Directed edge | Solid arrow |
| `<-` | Reverse directed | Solid arrow (reversed) |
| `--` | Undirected | Solid line, no arrows |
| `<->` | Bidirectional | Arrows on both ends |
| `=>` | Thick directed | Bold arrow |
| `==>` | Double thick | Double bold arrow |
| `-.->` | Dashed directed | Dashed arrow |
| `-..->` | Dotted directed | Dotted arrow |
| `-..-` | Dotted undirected | Dotted line, no arrows |

## CLI Usage

```=html
<div class="callout callout-cli">
  <div class="callout-label">CLI</div>
```

Render a graph from a `.zgraph` file:

```bash
zigraph render graph.zgraph -o output.svg
zigraph render graph.zgraph --format ascii
```

```=html
</div>
```

## Zig API

```=html
<div class="callout callout-zig">
  <div class="callout-label">Zig API</div>
```

Build and render a graph programmatically:

```zig
const zigraph = @import("zigraph");

var g = zigraph.Graph.init(allocator);
defer g.deinit();

try g.addNode(1, "API Server");
try g.addNode(2, "PostgreSQL");
try g.addNode(3, "Redis");

try g.addEdge(1, 2);
try g.addEdge(1, 3);

var ir = try zigraph.layout(&g, allocator, .{});
defer ir.deinit();

// SVG output
const svg = try zigraph.svg.render(ir, allocator, .{});

// Terminal output
const text = try zigraph.terminal.render(ir, allocator, .{});
```

```=html
</div>
```

## Configuration

Pass options to the layout engine:

```zig
var ir = try zigraph.layout(&g, allocator, .{
    .node_spacing = 20,
    .layer_spacing = 40,
    .optimize_crossings = true,
});
```

| Option | Default | Description |
|--------|---------|-------------|
| `node_spacing` | `15` | Horizontal spacing between nodes |
| `layer_spacing` | `30` | Vertical spacing between layers |
| `optimize_crossings` | `true` | Run crossing minimization passes |

```

- [ ] **Step 3: Create `docs/site/content/primitives/tree.smd`**

```
---
.title = "Tree",
.layout = "page.shtml",
.date = @date("2026-04-06T00:00:00"),
.description = "Hierarchical tree diagrams with Unicode box-drawing",
---

The tree primitive renders hierarchical data as indented text diagrams using Unicode box-drawing characters (`├─`, `└─`, `│`).

## Overview

Trees are ideal for visualizing file systems, ASTs, org charts, or any hierarchical structure. The tree renderer is standalone — it doesn't use the graph layout engine.

```=html
<div class="split-view">
  <div class="split-input">
    <div class="split-label">Zig Source</div>
    <pre><code>const TreeNode = zigraph.terminal.tree.TreeNode;
const nodes = [_]TreeNode{.{
    .label = "src",
    .children = &.{
        .{ .label = "main.zig", .description = "entry point" },
        .{ .label = "graph.zig", .description = "core graph types" },
        .{ .label = "layout/", .children = &.{
            .{ .label = "sugiyama.zig" },
            .{ .label = "force.zig" },
        }},
    },
}};</code></pre>
  </div>
  <div class="split-output">
    <div class="split-tabs">
      <button class="active" data-target="ascii">ASCII</button>
    </div>
    <div class="split-panel active" data-panel="ascii">
      <pre>src
├── main.zig — entry point
├── graph.zig — core graph types
└── layout/
    ├── sugiyama.zig
    └── force.zig</pre>
    </div>
  </div>
</div>
```

## Zig API

```=html
<div class="callout callout-zig">
  <div class="callout-label">Zig API</div>
```

```zig
const std = @import("std");
const zigraph = @import("zigraph");
const T = zigraph.terminal;
const TreeNode = T.tree.TreeNode;

const nodes = [_]TreeNode{.{
    .label = "Project",
    .children = &.{
        .{ .label = "src", .children = &.{
            .{ .label = "main.zig" },
            .{ .label = "lib.zig" },
        }},
        .{ .label = "tests", .children = &.{
            .{ .label = "test_graph.zig" },
        }},
    },
}};

const output = try T.tree.render(allocator, &nodes, .{});
defer allocator.free(output);
std.debug.print("{s}\n", .{output});
```

```=html
</div>
```

## Features

- **Descriptions** — Add context next to labels with `.description`
- **Extra lines** — Multi-line content with `.extra_lines`
- **Grouping** — Nested children with visual indentation
- **Colors** — Terminal color support via the color system

```

- [ ] **Step 4: Create `docs/site/content/primitives/card.smd`**

```
---
.title = "Card",
.layout = "page.shtml",
.date = @date("2026-04-06T00:00:00"),
.description = "Multi-line box nodes with header and content lines",
---

Card nodes are multi-line box nodes with a header and content lines, rendered natively in graph layouts. They're useful for displaying structured information within graph nodes — like database schemas, service descriptions, or configuration blocks.

## Overview

```=html
<div class="split-view">
  <div class="split-input">
    <div class="split-label">Zig Source</div>
    <pre><code>var g = zigraph.Graph.init(allocator);
// Add card-style nodes with content lines
try g.addCardNode(1, "UserService", &.{
    "POST /users",
    "GET /users/:id",
    "PUT /users/:id",
});
try g.addCardNode(2, "AuthService", &.{
    "POST /login",
    "POST /refresh",
});
try g.addEdge(1, 2);</code></pre>
  </div>
  <div class="split-output">
    <div class="split-tabs">
      <button class="active" data-target="ascii">ASCII</button>
    </div>
    <div class="split-panel active" data-panel="ascii">
      <pre>┌──────────────────┐
│   UserService    │
├──────────────────┤
│ POST /users      │
│ GET /users/:id   │
│ PUT /users/:id   │
└────────┬─────────┘
         │
         v
┌──────────────────┐
│   AuthService    │
├──────────────────┤
│ POST /login      │
│ POST /refresh    │
└──────────────────┘</pre>
    </div>
  </div>
</div>
```

## Zig API

```=html
<div class="callout callout-zig">
  <div class="callout-label">Zig API</div>
```

```zig
const zigraph = @import("zigraph");

var g = zigraph.Graph.init(allocator);
defer g.deinit();

try g.addCardNode(1, "Service", &.{ "endpoint 1", "endpoint 2" });
try g.addCardNode(2, "Database", &.{ "table_a", "table_b" });
try g.addEdge(1, 2);

var ir = try zigraph.layout(&g, allocator, .{});
defer ir.deinit();
const text = try zigraph.terminal.render(ir, allocator, .{});
```

```=html
</div>
```

```

- [ ] **Step 5: Create `docs/site/content/primitives/table.smd`**

```
---
.title = "Table",
.layout = "page.shtml",
.date = @date("2026-04-06T00:00:00"),
.description = "Tabular data rendering with headers and rows",
---

The table primitive renders structured data as formatted tables with headers, alignment, and borders.

## DSL Syntax

```zgraph
users {
  headers: id | name | email
  row: 1 | Alice | alice@example.com
  row: 2 | Bob | bob@example.com
}
```

## Zig API

```=html
<div class="callout callout-zig">
  <div class="callout-label">Zig API</div>
```

Table rendering uses the terminal table module:

```zig
const zigraph = @import("zigraph");
const T = zigraph.terminal;

const output = try T.table.render(allocator, .{
    .headers = &.{ "id", "name", "email" },
    .rows = &.{
        &.{ "1", "Alice", "alice@example.com" },
        &.{ "2", "Bob", "bob@example.com" },
    },
});
```

```=html
</div>
```

```

- [ ] **Step 6: Create stub pages for gantt, flow, and dag**

Create `docs/site/content/primitives/gantt.smd`:

```
---
.title = "Gantt",
.layout = "page.shtml",
.date = @date("2026-04-06T00:00:00"),
.description = "Timeline and Gantt chart rendering",
---

Gantt charts visualize tasks across a timeline, showing duration, dependencies, and progress.

## Overview

The Gantt primitive renders tasks as horizontal bars on a time axis, with dependency arrows between related tasks.

## Status

Gantt chart support is planned for a future release. The DSL syntax and API are being designed.

```

Create `docs/site/content/primitives/flow.smd`:

```
---
.title = "Flow",
.layout = "page.shtml",
.date = @date("2026-04-06T00:00:00"),
.description = "Flowchart diagrams with decision nodes and paths",
---

Flowcharts extend the graph primitive with specialized node shapes (diamonds for decisions, rounded rectangles for processes) and labeled paths.

## Overview

Flowcharts use the same Sugiyama layout engine as graphs, but with additional node types and edge labels optimized for process visualization.

## Example

```zgraph
start [shape="oval"]
check [shape="diamond" label="Valid?"]
process [label="Process Data"]
error [label="Show Error"]
done [shape="oval" label="End"]

start -> check
check -> process [label="yes"]
check -> error [label="no"]
process -> done
error -> done
```

```

Create `docs/site/content/primitives/dag.smd`:

```
---
.title = "DAG",
.layout = "page.shtml",
.date = @date("2026-04-06T00:00:00"),
.description = "Directed acyclic graph layouts with topological ordering",
---

DAGs (Directed Acyclic Graphs) are a specialization of the graph primitive that guarantees no cycles. The layout engine can exploit the acyclic property for more efficient and cleaner layouts.

## Overview

When your graph is known to be acyclic, you can use DAG-specific options that skip cycle detection and produce tighter layouts:

```zig
var ir = try zigraph.layout(&g, allocator, .{
    .assume_acyclic = true,
});
```

## Use Cases

- **Build systems** — Task dependency graphs
- **Package managers** — Dependency resolution visualization
- **Data pipelines** — ETL flow visualization
- **Git history** — Commit graph rendering

## Example

```zgraph
# Build pipeline DAG
fetch [label="Fetch Deps"]
compile [label="Compile"]
test [label="Run Tests"]
link [label="Link"]
package [label="Package"]

fetch -> compile
compile -> test
compile -> link
test -> package
link -> package
```

```

- [ ] **Step 7: Commit**

```bash
git add docs/site/content/primitives/
git commit -m "feat(docs): add primitives section with graph, tree, card, table, gantt, flow, dag pages"
```

---

### Task 6: DSL Syntax Section

**Files:**
- Create: `docs/site/content/dsl/index.smd`
- Create: `docs/site/content/dsl/file-format.smd`
- Create: `docs/site/content/dsl/nodes-and-blocks.smd`
- Create: `docs/site/content/dsl/edges.smd`
- Create: `docs/site/content/dsl/properties.smd`
- Create: `docs/site/content/dsl/variables.smd`
- Create: `docs/site/content/dsl/directives.smd`
- Create: `docs/site/content/dsl/styling.smd`

- [ ] **Step 1: Create `docs/site/content/dsl/index.smd`**

```
---
.title = "DSL Syntax",
.layout = "section.shtml",
.description = "The .zgraph file format for describing graphs",
---

The zgraph DSL is a concise language for describing graphs, trees, and other visual structures. Files use the `.zgraph` extension and can be rendered via the CLI or parsed programmatically with the Zig API.
```

- [ ] **Step 2: Create `docs/site/content/dsl/file-format.smd`**

```
---
.title = "File Format",
.layout = "page.shtml",
.date = @date("2026-04-06T00:00:00"),
.description = ".zgraph file structure, encoding, and comments",
---

## File Extension

zgraph files use the `.zgraph` extension. The file is UTF-8 encoded plain text.

## Comments

Comments start with `#` and continue to the end of the line:

```zgraph
# This is a comment
server [label="API"]  # Inline comment
```

## Basic Structure

A `.zgraph` file consists of:

1. **Node declarations** — named identifiers with optional attributes
2. **Edge statements** — connections between nodes
3. **Blocks** — grouped content within `{}`
4. **Directives** — `@`-prefixed instructions like `@style` and `@layout`
5. **Variable blocks** — `vars {}` for reusable values

Statements are separated by newlines. Semicolons are treated as whitespace and can be used as separators if preferred.

## Minimal Example

```zgraph
# Two nodes connected by a directed edge
a -> b
```

This declares two nodes (`a` and `b`) and a directed edge from `a` to `b`. Node labels default to the identifier name.

```

- [ ] **Step 3: Create `docs/site/content/dsl/nodes-and-blocks.smd`**

```
---
.title = "Nodes & Blocks",
.layout = "page.shtml",
.date = @date("2026-04-06T00:00:00"),
.description = "Node declarations, labels, and block syntax",
---

## Node Declarations

Nodes are declared by using an identifier. The first use of an identifier creates the node:

```zgraph
server
database
cache
```

## Labels

Add a label with the `label` property in brackets:

```zgraph
server [label="API Server"]
db [label="PostgreSQL Database"]
```

If no label is given, the identifier name is used as the label.

## Blocks

Blocks group related content with curly braces:

```zgraph
backend {
  server [label="API"]
  db [label="Database"]
  server -> db
}

frontend {
  app [label="React App"]
  cdn [label="CDN"]
  app -> cdn
}

frontend.app -> backend.server
```

Blocks create namespaced scopes. Nodes inside blocks are referenced using dot-path notation (`backend.server`).

## Nested Blocks

Blocks can be nested to arbitrary depth:

```zgraph
infrastructure {
  aws {
    ec2 [label="EC2"]
    rds [label="RDS"]
    ec2 -> rds
  }
  monitoring {
    grafana [label="Grafana"]
  }
  aws.ec2 -> monitoring.grafana
}
```

```

- [ ] **Step 4: Create `docs/site/content/dsl/edges.smd`**

```
---
.title = "Edges",
.layout = "page.shtml",
.date = @date("2026-04-06T00:00:00"),
.description = "All 9 edge operators and edge chains",
---

## Edge Operators

zgraph supports 9 edge operators:

| Operator | Name | Style |
|----------|------|-------|
| `->` | Directed | Solid line with arrow |
| `<-` | Reverse directed | Solid line with reversed arrow |
| `--` | Undirected | Solid line, no arrows |
| `<->` | Bidirectional | Arrows on both ends |
| `=>` | Thick directed | Bold arrow |
| `==>` | Double thick | Double bold arrow |
| `-.->` | Dashed directed | Dashed line with arrow |
| `-..->` | Dotted directed | Dotted line with arrow |
| `-..-` | Dotted undirected | Dotted line, no arrows |

## Examples

```zgraph
# Solid connections
a -> b         # directed
a <-> b        # bidirectional
a -- b         # undirected

# Emphasized connections
a => b         # thick
a ==> b        # double thick

# Weak/optional connections
a -.-> b       # dashed
a -..-> b      # dotted
a -..- b       # dotted undirected
```

## Edge Chains

Multiple nodes can be chained in a single statement:

```zgraph
a -> b -> c -> d
```

This creates three edges: `a->b`, `b->c`, `c->d`.

Mixed operators in chains:

```zgraph
client -> server => database -.-> cache
```

## Edge Labels

Add labels to edges with brackets:

```zgraph
server -> db [label="queries"]
server -> cache [label="reads"]
```

```

- [ ] **Step 5: Create `docs/site/content/dsl/properties.smd`**

```
---
.title = "Properties",
.layout = "page.shtml",
.date = @date("2026-04-06T00:00:00"),
.description = "Property lists and annotations",
---

## Property Lists

Properties are key-value pairs in square brackets:

```zgraph
server [label="API Server" color="blue" shape="box"]
```

Multiple properties are space-separated within the brackets.

## Common Properties

| Property | Values | Description |
|----------|--------|-------------|
| `label` | String | Display text for the node |
| `color` | Color name or hex | Node border/text color |
| `shape` | `box`, `oval`, `diamond` | Node shape |
| `style` | `filled`, `dashed`, `dotted` | Visual style |

## Annotations

Annotations appear before nodes or edges and modify their behavior:

```zgraph
[layout="lr"]  # Left-to-right layout for this scope

server [label="API"]
db [label="DB"]
server -> db
```

Annotations use the same bracket syntax as properties but apply to the scope rather than a specific node.

```

- [ ] **Step 6: Create `docs/site/content/dsl/variables.smd`**

```
---
.title = "Variables",
.layout = "page.shtml",
.date = @date("2026-04-06T00:00:00"),
.description = "Variable blocks and string interpolation",
---

## Variable Blocks

Define reusable values in a `vars` block:

```zgraph
vars {
  app_name: "My Application"
  db_host: "db.example.com"
  version: "2.1.0"
}
```

## String Interpolation

Use `${name}` syntax inside strings to reference variables:

```zgraph
vars {
  env: "production"
  region: "us-east-1"
}

server [label="Server (${env})"]
db [label="DB @ ${region}"]
server -> db
```

Variables are resolved at parse time. Undefined variables produce an error.

```

- [ ] **Step 7: Create `docs/site/content/dsl/directives.smd`**

```
---
.title = "Directives",
.layout = "page.shtml",
.date = @date("2026-04-06T00:00:00"),
.description = "@-prefixed directives for style, layout, and more",
---

## Overview

Directives are `@`-prefixed instructions that control rendering behavior. They start with `@` followed by a name.

## @style

Define visual styles for nodes, edges, or classes:

```zgraph
@style node {
  color = "white"
  fill = "#1a1a2e"
  border = "#333"
}

@style edge {
  color = "#666"
}

@style .highlight {
  fill = "#f59e0b"
  color = "#000"
}
```

Apply class styles with dot-prefix notation:

```zgraph
server .highlight [label="Important Server"]
```

## @layout

Control the layout direction:

```zgraph
@layout {
  direction = "lr"    # left-to-right (default is top-to-bottom)
  spacing = 20
}
```

## Custom Directives

Any `@name` is parsed as a directive. Unknown directives are passed through to the rendering engine, allowing extensions.

```

- [ ] **Step 8: Create `docs/site/content/dsl/styling.smd`**

```
---
.title = "Styling & Theming",
.layout = "page.shtml",
.date = @date("2026-04-06T00:00:00"),
.description = "@style blocks, class references, colors, and visual properties",
---

## Style Blocks

Use `@style` to define default styles for all nodes or edges:

```zgraph
@style node {
  fill = "#1e1e2e"
  color = "#cdd6f4"
  border = "#45475a"
  font-size = 14
}

@style edge {
  color = "#585b70"
  width = 1.5
}
```

## Class References

Define named style classes and apply them to nodes:

```zgraph
@style .primary {
  fill = "#89b4fa"
  color = "#1e1e2e"
}

@style .danger {
  fill = "#f38ba8"
  color = "#1e1e2e"
}

server .primary [label="API Server"]
legacy .danger [label="Deprecated Service"]
```

Multiple classes can be applied to a single node:

```zgraph
node .primary .large [label="Important"]
```

## Color Values

Styles accept several color formats:

| Format | Example | Description |
|--------|---------|-------------|
| Hex | `"#ff5733"` | 6-digit hex color |
| Named | `"red"` | CSS color name |
| RGB | `"rgb(255, 87, 51)"` | RGB function |

## Theming

Create complete themes by combining `@style` blocks:

```zgraph
# Dark theme
@style node {
  fill = "#1e1e2e"
  color = "#cdd6f4"
  border = "#45475a"
}

@style edge {
  color = "#585b70"
}

@style .accent {
  fill = "#89b4fa"
  color = "#1e1e2e"
}
```

```

- [ ] **Step 9: Commit**

```bash
git add docs/site/content/dsl/
git commit -m "feat(docs): add DSL syntax section with all 7 pages"
```

---

### Task 7: CLI, LSP, and Editors Sections

**Files:**
- Create: `docs/site/content/cli/index.smd`
- Create: `docs/site/content/cli/commands.smd`
- Create: `docs/site/content/cli/options.smd`
- Create: `docs/site/content/cli/output-formats.smd`
- Create: `docs/site/content/lsp/index.smd`
- Create: `docs/site/content/lsp/features.smd`
- Create: `docs/site/content/lsp/formatter.smd`
- Create: `docs/site/content/lsp/configuration.smd`
- Create: `docs/site/content/editors/index.smd`
- Create: `docs/site/content/editors/neovim.smd`
- Create: `docs/site/content/editors/vscode.smd`
- Create: `docs/site/content/editors/other-editors.smd`

- [ ] **Step 1: Create CLI section**

Create `docs/site/content/cli/index.smd`:

```
---
.title = "CLI",
.layout = "section.shtml",
.description = "Command-line interface for rendering and processing .zgraph files",
---

The zigraph CLI renders `.zgraph` files to SVG, ASCII, or JSON from the command line.
```

Create `docs/site/content/cli/commands.smd`:

```
---
.title = "Commands",
.layout = "page.shtml",
.date = @date("2026-04-06T00:00:00"),
.description = "All CLI commands with usage examples",
---

## render

Render a `.zgraph` file to an output format:

```bash
zigraph render input.zgraph -o output.svg
zigraph render input.zgraph --format ascii
zigraph render input.zgraph --format json -o output.json
```

## fmt

Format a `.zgraph` file in place:

```bash
zigraph fmt input.zgraph
zigraph fmt --check input.zgraph  # Check without modifying
```

## lsp

Start the language server (typically called by editors, not manually):

```bash
zigraph lsp
```

## validate

Check a `.zgraph` file for errors without rendering:

```bash
zigraph validate input.zgraph
```

```

Create `docs/site/content/cli/options.smd`:

```
---
.title = "Options",
.layout = "page.shtml",
.date = @date("2026-04-06T00:00:00"),
.description = "Global and per-command flags",
---

## Global Options

| Flag | Description |
|------|-------------|
| `--help`, `-h` | Show help text |
| `--version` | Print version number |
| `--color` | Force colored terminal output |
| `--no-color` | Disable colored output |

## Render Options

| Flag | Default | Description |
|------|---------|-------------|
| `-o`, `--output` | stdout | Output file path |
| `--format` | `svg` | Output format: `svg`, `ascii`, `json` |
| `--theme` | (none) | Apply a named theme |
| `--layout` | `sugiyama` | Layout algorithm: `sugiyama`, `force` |

## Format Options

| Flag | Description |
|------|-------------|
| `--check` | Check formatting without modifying files |
| `--stdin` | Read from stdin instead of file |

```

Create `docs/site/content/cli/output-formats.smd`:

```
---
.title = "Output Formats",
.layout = "page.shtml",
.date = @date("2026-04-06T00:00:00"),
.description = "SVG, ASCII, and JSON output modes",
---

## SVG

The default output format. Produces a standalone SVG file with:

- Spline-based edge routing
- Embedded node labels
- Viewbox scaling for any display size

```bash
zigraph render graph.zgraph -o graph.svg
```

## ASCII / Unicode

Terminal-friendly output using Unicode box-drawing characters:

```bash
zigraph render graph.zgraph --format ascii
```

Outputs text like:

```
    ┌──────────┐
    │ main.zig │
    └────┬─────┘
    ┌────┴─────┐
    v          v
┌────────┐ ┌────────┐
│http.zig│ │json.zig│
└────────┘ └────────┘
```

## JSON

Machine-readable output with full layout information:

```bash
zigraph render graph.zgraph --format json
```

The JSON output includes node positions, edge paths, and all computed layout data. Useful for building custom renderers or integrating with other tools.

```

- [ ] **Step 2: Create LSP section**

Create `docs/site/content/lsp/index.smd`:

```
---
.title = "LSP & Formatter",
.layout = "section.shtml",
.description = "Language server and auto-formatting for .zgraph files",
---

zigraph includes a Language Server Protocol (LSP) implementation and an auto-formatter for `.zgraph` files.
```

Create `docs/site/content/lsp/features.smd`:

```
---
.title = "LSP Features",
.layout = "page.shtml",
.date = @date("2026-04-06T00:00:00"),
.description = "Diagnostics, completions, hover, and go-to-definition",
---

## Diagnostics

Real-time error reporting as you type:

- Syntax errors (missing brackets, invalid operators)
- Undefined node references
- Duplicate node declarations
- Invalid property values

## Completions

Context-aware autocomplete for:

- Node names (from current file)
- Property names (within `[]` brackets)
- Edge operators
- Directive names (`@style`, `@layout`)
- Variable names (within `${...}`)

## Hover

Hover over identifiers to see:

- Node properties and connections
- Variable values
- Style class definitions

## Go to Definition

Jump to the definition of:

- Node declarations
- Variable definitions in `vars {}` blocks
- Style classes defined in `@style` blocks

```

Create `docs/site/content/lsp/formatter.smd`:

```
---
.title = "Formatter",
.layout = "page.shtml",
.date = @date("2026-04-06T00:00:00"),
.description = "Auto-formatting rules and configuration",
---

## Usage

Format via CLI:

```bash
zigraph fmt file.zgraph
```

Format on save via LSP (configure in your editor settings).

## Formatting Rules

The formatter enforces consistent style:

- **Indentation** — 2 spaces inside blocks
- **Spacing** — Single space around edge operators (`a -> b`, not `a->b`)
- **Blank lines** — One blank line between top-level blocks
- **Trailing newline** — Files end with a single newline
- **Property alignment** — Properties aligned within brackets

## Check Mode

Verify formatting without modifying files:

```bash
zigraph fmt --check file.zgraph
echo $?  # 0 = formatted, 1 = needs formatting
```

Useful in CI pipelines.

```

Create `docs/site/content/lsp/configuration.smd`:

```
---
.title = "Configuration",
.layout = "page.shtml",
.date = @date("2026-04-06T00:00:00"),
.description = "LSP and formatter settings",
---

## LSP Settings

The LSP server accepts configuration via the standard `initialize` request:

| Setting | Default | Description |
|---------|---------|-------------|
| `formatOnSave` | `false` | Auto-format when saving |
| `diagnostics.enabled` | `true` | Show real-time diagnostics |
| `completion.enabled` | `true` | Enable autocomplete |

## Editor-Specific Configuration

See the [Editor Integration](/editors/) section for how to pass these settings in Neovim and VS Code.

```

- [ ] **Step 3: Create Editors section**

Create `docs/site/content/editors/index.smd`:

```
---
.title = "Editor Integration",
.layout = "section.shtml",
.description = "Set up syntax highlighting, LSP, and formatting in your editor",
---

zigraph provides first-class editor support for Neovim and VS Code, with generic LSP support for any editor that implements the protocol.
```

Create `docs/site/content/editors/neovim.smd`:

```
---
.title = "Neovim",
.layout = "page.shtml",
.date = @date("2026-04-06T00:00:00"),
.description = "Tree-sitter highlighting, LSP config, and filetype detection",
---

## Prerequisites

- Neovim >= 0.9
- [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter)
- `zigraph` binary on PATH (for LSP)

## 1. Filetype Detection

Add to your `init.lua`:

```lua
vim.filetype.add({
  extension = {
    zgraph = "zgraph",
  },
})
```

Or copy the ftdetect file:

```bash
cp editors/neovim/ftdetect/zgraph.vim ~/.config/nvim/ftdetect/
```

## 2. Tree-sitter Parser

Add the zgraph parser config:

```lua
local parser_config = require("nvim-treesitter.parsers").get_parser_configs()
parser_config.zgraph = {
  install_info = {
    url = "https://github.com/markussagen/zigraph",
    files = { "src/parser.c" },
    location = "tree-sitter-zgraph",
    branch = "main",
  },
  filetype = "zgraph",
}
```

Then install:

```vim
:TSInstall zgraph
```

## 3. Highlight Queries

Copy query files to your Neovim runtime:

```bash
mkdir -p ~/.config/nvim/queries/zgraph
cp tree-sitter-zgraph/queries/highlights.scm ~/.config/nvim/queries/zgraph/
cp tree-sitter-zgraph/queries/locals.scm ~/.config/nvim/queries/zgraph/
```

## 4. LSP Setup

Using `nvim-lspconfig`:

```lua
local lspconfig = require("lspconfig")
local configs = require("lspconfig.configs")

if not configs.zgraph then
  configs.zgraph = {
    default_config = {
      cmd = { "zigraph", "lsp" },
      filetypes = { "zgraph" },
      root_dir = lspconfig.util.find_git_ancestor,
      single_file_support = true,
    },
  }
end

lspconfig.zgraph.setup({})
```

Or without lspconfig:

```lua
vim.api.nvim_create_autocmd("FileType", {
  pattern = "zgraph",
  callback = function()
    vim.lsp.start({
      name = "zgraph",
      cmd = { "zigraph", "lsp" },
    })
  end,
})
```

## 5. Verify

```vim
:echo &filetype                   " Should show: zgraph
:TSHighlightCapturesUnderCursor   " Should show highlight groups
:LspInfo                          " Should show zgraph LSP attached
```

```

Create `docs/site/content/editors/vscode.smd`:

```
---
.title = "VS Code",
.layout = "page.shtml",
.date = @date("2026-04-06T00:00:00"),
.description = "Extension install, TextMate grammar, and LSP settings",
---

## Installation

Install the zgraph extension from the VS Code marketplace, or build from source:

```bash
cd editors/vscode
bun install
bun run build
```

Then install the `.vsix` file via VS Code's "Install from VSIX" command.

## Features

The extension provides:

- **Syntax highlighting** — TextMate grammar for `.zgraph` files
- **LSP integration** — Diagnostics, completions, hover, formatting
- **Comment toggling** — `Ctrl+/` toggles `#` comments
- **Bracket matching** — Auto-close `{}`, `[]`, `""`

## Settings

| Setting | Default | Description |
|---------|---------|-------------|
| `zgraph.lsp.enabled` | `true` | Enable/disable the LSP client |
| `zgraph.lsp.path` | `"zigraph"` | Path to the zigraph binary |

## Troubleshooting

If the LSP fails to start, check:

1. The `zigraph` binary is on your PATH: `which zigraph`
2. The path is correct in settings: `zgraph.lsp.path`
3. Check the Output panel (select "zgraph" from the dropdown) for error messages

```

Create `docs/site/content/editors/other-editors.smd`:

```
---
.title = "Other Editors",
.layout = "page.shtml",
.date = @date("2026-04-06T00:00:00"),
.description = "Generic LSP and formatter integration for any editor",
---

## Generic LSP Setup

Any editor that supports the Language Server Protocol can use zigraph's LSP. The server command is:

```
zigraph lsp
```

Communication is over **stdio** (stdin/stdout).

### Helix

Add to `~/.config/helix/languages.toml`:

```toml
[[language]]
name = "zgraph"
scope = "source.zgraph"
file-types = ["zgraph"]
comment-token = "#"
language-servers = ["zigraph-lsp"]

[language-server.zigraph-lsp]
command = "zigraph"
args = ["lsp"]
```

### Emacs (lsp-mode)

```elisp
(add-to-list 'auto-mode-alist '("\\.zgraph\\'" . prog-mode))

(with-eval-after-load 'lsp-mode
  (add-to-list 'lsp-language-id-configuration '(prog-mode . "zgraph"))
  (lsp-register-client
   (make-lsp-client
    :new-connection (lsp-stdio-connection '("zigraph" "lsp"))
    :activation-fn (lsp-activate-on "zgraph")
    :server-id 'zigraph)))
```

## Formatter Integration

Use `zigraph fmt` as an external formatter:

```bash
zigraph fmt --stdin < input.zgraph > formatted.zgraph
```

Most editors can pipe the buffer through an external command for formatting.

```

- [ ] **Step 4: Commit**

```bash
git add docs/site/content/cli/ docs/site/content/lsp/ docs/site/content/editors/
git commit -m "feat(docs): add CLI, LSP, and editor integration sections"
```

---

### Task 8: Syntax Highlighting and Zig API Sections

**Files:**
- Create: `docs/site/content/syntax-highlighting/index.smd`
- Create: `docs/site/content/syntax-highlighting/tree-sitter.smd`
- Create: `docs/site/content/syntax-highlighting/textmate.smd`
- Create: `docs/site/content/syntax-highlighting/adding-editors.smd`
- Create: `docs/site/content/zig-api/index.smd`
- Create: `docs/site/content/zig-api/embedding.smd`
- Create: `docs/site/content/zig-api/reference.smd`
- Create: `docs/site/content/zig-api/examples.smd`

- [ ] **Step 1: Create Syntax Highlighting section**

Create `docs/site/content/syntax-highlighting/index.smd`:

```
---
.title = "Syntax Highlighting",
.layout = "section.shtml",
.description = "Tree-sitter and TextMate grammars for .zgraph files",
---

zigraph provides two syntax highlighting grammars: a Tree-sitter grammar for editors with native Tree-sitter support (Neovim, Helix) and a TextMate grammar for VS Code and other TextMate-compatible editors.
```

Create `docs/site/content/syntax-highlighting/tree-sitter.smd`:

```
---
.title = "Tree-sitter Grammar",
.layout = "page.shtml",
.date = @date("2026-04-06T00:00:00"),
.description = "Grammar structure, node types, and query files",
---

## Overview

The Tree-sitter grammar lives in `tree-sitter-zgraph/` and provides full incremental parsing of `.zgraph` files. It powers syntax highlighting, code folding, and structural queries.

## Node Types

The grammar defines these node types:

| Node | Description |
|------|-------------|
| `source_file` | Root node |
| `block` | Named `{ }` group |
| `edge_chain` | Node-operator-node sequence |
| `edge_operator` | One of 9 operators (`->`, `<-`, etc.) |
| `annotation` | `[key=val]` property list |
| `directive` | `@name` directive |
| `style_block` | `@style target { }` |
| `vars_block` | `vars { }` block |
| `var_decl` | Variable declaration inside vars |
| `string` | Double-quoted string with interpolation |
| `string_interpolation` | `${name}` inside strings |
| `comment` | `# ...` line comment |
| `identifier` | Node/variable name (including `dot.paths`) |

## Highlight Queries

The highlight queries map node types to standard highlight groups:

```scheme
(comment) @comment
(string) @string
(edge_operator) @operator
(identifier) @variable
(block (identifier) @function)
(directive (identifier) @attribute)
(annotation (identifier) @type)
```

## Building from Source

```bash
cd tree-sitter-zgraph
bun install
bun run generate
bun run test  # Runs 31 corpus tests
```

## Test Corpus

Tests live in `tree-sitter-zgraph/test/corpus/` with 31 tests across 7 files covering blocks, edges, directives, variables, tables, styles, and comments.

```

Create `docs/site/content/syntax-highlighting/textmate.smd`:

```
---
.title = "TextMate Grammar",
.layout = "page.shtml",
.date = @date("2026-04-06T00:00:00"),
.description = "VS Code .tmLanguage.json scope names and patterns",
---

## Overview

The TextMate grammar at `editors/vscode/syntaxes/zgraph.tmLanguage.json` provides regex-based syntax highlighting for VS Code and other TextMate-compatible editors.

## Scope Names

| Scope | Matches |
|-------|---------|
| `comment.line.number-sign.zgraph` | `# ...` comments |
| `string.quoted.double.zgraph` | `"..."` strings |
| `constant.character.escape.zgraph` | `\"` escapes in strings |
| `variable.other.zgraph` | `${name}` interpolation |
| `keyword.operator.edge.zgraph` | Edge operators (`->`, `<-`, etc.) |
| `entity.name.type.class.zgraph` | `.className` references |
| `entity.other.attribute-name.zgraph` | `@directive` names |
| `keyword.control.zgraph` | `vars`, `headers`, `row` |
| `support.other.property.zgraph` | Property names in `[key=val]` |
| `constant.numeric.zgraph` | Number literals |
| `entity.name.function.zgraph` | Block names before `{` or `[` |

## Limitations

TextMate grammars are regex-based, so they can't handle:

- Context-dependent highlighting (e.g., different colors for nodes in edges vs declarations)
- Cross-line patterns beyond simple begin/end matching
- Semantic understanding of the graph structure

For full-fidelity highlighting, use the Tree-sitter grammar in Neovim or Helix.

```

Create `docs/site/content/syntax-highlighting/adding-editors.smd`:

```
---
.title = "Adding New Editors",
.layout = "page.shtml",
.date = @date("2026-04-06T00:00:00"),
.description = "How to add zgraph highlighting to other editors",
---

## Using the Tree-sitter Grammar

If your editor supports Tree-sitter (Neovim, Helix, Zed, Emacs with tree-sitter), you can use the zgraph grammar directly.

### 1. Build the parser

```bash
cd tree-sitter-zgraph
bun install
bun run generate
```

This produces `src/parser.c` — the compiled parser.

### 2. Register the parser

Each editor has its own mechanism for registering Tree-sitter parsers. You need:

- **Parser binary**: Compile `src/parser.c` (most editors do this automatically)
- **Highlight queries**: Copy `queries/highlights.scm` to the editor's query directory
- **Filetype mapping**: Associate `.zgraph` files with the `zgraph` language

### 3. Write highlight queries

The provided `queries/highlights.scm` uses standard capture names (`@comment`, `@string`, `@operator`, etc.) that work across editors. If your editor uses different names, adapt accordingly.

## Using the TextMate Grammar

For editors that support TextMate grammars (VS Code, Sublime Text, TextMate), use the grammar at `editors/vscode/syntaxes/zgraph.tmLanguage.json`.

### Sublime Text

1. Create `~/.config/sublime-text/Packages/zgraph/`
2. Copy `zgraph.tmLanguage.json` to that directory
3. Create a `.sublime-syntax` file or use the JSON grammar directly

## Creating a New Grammar

If neither Tree-sitter nor TextMate work for your editor, refer to:

- `tree-sitter-zgraph/grammar.js` for the canonical syntax definition
- The [DSL Syntax](/dsl/) documentation for language semantics
- `tree-sitter-zgraph/test/corpus/` for comprehensive syntax examples

```

- [ ] **Step 2: Create Zig API section**

Create `docs/site/content/zig-api/index.smd`:

```
---
.title = "Zig Library API",
.layout = "section.shtml",
.description = "Embed zigraph in your Zig application",
---

zigraph is designed as an embeddable library. Add it as a Zig dependency and use the public API to build, layout, and render graphs programmatically.
```

Create `docs/site/content/zig-api/embedding.smd`:

```
---
.title = "Embedding zigraph",
.layout = "page.shtml",
.date = @date("2026-04-06T00:00:00"),
.description = "Adding zigraph as a Zig dependency and build.zig setup",
---

## Add the Dependency

```bash
zig fetch --save git+https://github.com/markussagen/zigraph
```

This adds zigraph to your `build.zig.zon` dependencies.

## Configure build.zig

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zigraph_dep = b.dependency("zigraph", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "my-app",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("zigraph", zigraph_dep.module("zigraph"));
    b.installArtifact(exe);
}
```

## Verify

Create `src/main.zig`:

```zig
const zigraph = @import("zigraph");
const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var g = zigraph.Graph.init(gpa.allocator());
    defer g.deinit();

    try g.addNode(1, "hello");
    try g.addNode(2, "world");
    try g.addEdge(1, 2);

    std.debug.print("Graph has {d} nodes\n", .{g.nodeCount()});
}
```

```bash
zig build run
# Output: Graph has 2 nodes
```

```

Create `docs/site/content/zig-api/reference.smd`:

```
---
.title = "API Reference",
.layout = "page.shtml",
.date = @date("2026-04-06T00:00:00"),
.description = "Public types, functions, and rendering pipeline",
---

## Core Types

### `Graph`

The main graph data structure.

```zig
const Graph = zigraph.Graph;

var g = Graph.init(allocator);
defer g.deinit();
```

| Method | Description |
|--------|-------------|
| `init(allocator)` | Create a new empty graph |
| `deinit()` | Free all graph memory |
| `addNode(id, label)` | Add a node with numeric ID and label |
| `addEdge(from, to)` | Add a directed edge |
| `addCardNode(id, label, lines)` | Add a card-style node |
| `nodeCount()` | Return the number of nodes |

### `layout`

Compute positions for all nodes and edges:

```zig
var ir = try zigraph.layout(&g, allocator, .{});
defer ir.deinit();
```

Options:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `node_spacing` | `u32` | `15` | Horizontal gap between nodes |
| `layer_spacing` | `u32` | `30` | Vertical gap between layers |
| `optimize_crossings` | `bool` | `true` | Run crossing reduction |
| `assume_acyclic` | `bool` | `false` | Skip cycle detection |

### Renderers

#### SVG

```zig
const svg = try zigraph.svg.render(ir, allocator, .{});
defer allocator.free(svg);
```

#### Terminal

```zig
const text = try zigraph.terminal.render(ir, allocator, .{});
defer allocator.free(text);
```

#### JSON

```zig
const json = try zigraph.json.render(ir, allocator, .{});
defer allocator.free(json);
```

## Tree Module

Standalone tree rendering (no graph layout needed):

```zig
const T = zigraph.terminal;
const TreeNode = T.tree.TreeNode;

const nodes = [_]TreeNode{.{
    .label = "root",
    .children = &.{
        .{ .label = "child1" },
        .{ .label = "child2", .description = "with description" },
    },
}};

const output = try T.tree.render(allocator, &nodes, .{});
```

```

Create `docs/site/content/zig-api/examples.smd`:

```
---
.title = "Examples",
.layout = "page.shtml",
.date = @date("2026-04-06T00:00:00"),
.description = "Zig code examples for common use cases",
---

## Dependency Graph

```zig
const std = @import("std");
const zigraph = @import("zigraph");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var g = zigraph.Graph.init(allocator);
    defer g.deinit();

    try g.addNode(1, "main.zig");
    try g.addNode(2, "http.zig");
    try g.addNode(3, "json.zig");
    try g.addNode(4, "auth.zig");
    try g.addNode(5, "db.zig");
    try g.addNode(6, "log.zig");

    try g.addEdge(1, 2);
    try g.addEdge(1, 3);
    try g.addEdge(2, 4);
    try g.addEdge(2, 5);
    try g.addEdge(3, 5);
    try g.addEdge(4, 6);
    try g.addEdge(5, 6);

    var ir = try zigraph.layout(&g, allocator, .{});
    defer ir.deinit();

    const svg = try zigraph.svg.render(ir, allocator, .{});
    defer allocator.free(svg);

    const file = try std.fs.cwd().createFile("deps.svg", .{});
    defer file.close();
    try file.writeAll(svg);
}
```

## Service Architecture with Card Nodes

```zig
const std = @import("std");
const zigraph = @import("zigraph");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var g = zigraph.Graph.init(allocator);
    defer g.deinit();

    try g.addCardNode(1, "API Gateway", &.{
        "POST /api/v1/*",
        "rate limiting",
        "auth middleware",
    });
    try g.addCardNode(2, "User Service", &.{
        "CRUD operations",
        "profile management",
    });
    try g.addCardNode(3, "Auth Service", &.{
        "JWT tokens",
        "OAuth2 flow",
    });
    try g.addCardNode(4, "PostgreSQL", &.{
        "users table",
        "sessions table",
    });

    try g.addEdge(1, 2);
    try g.addEdge(1, 3);
    try g.addEdge(2, 4);
    try g.addEdge(3, 4);

    var ir = try zigraph.layout(&g, allocator, .{});
    defer ir.deinit();

    const text = try zigraph.terminal.render(ir, allocator, .{});
    defer allocator.free(text);
    std.debug.print("{s}\n", .{text});
}
```

## File System Tree

```zig
const std = @import("std");
const zigraph = @import("zigraph");
const T = zigraph.terminal;
const TreeNode = T.tree.TreeNode;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const tree = [_]TreeNode{.{
        .label = "zigraph/",
        .children = &.{
            .{ .label = "src/", .children = &.{
                .{ .label = "graph.zig", .description = "core graph types" },
                .{ .label = "layout/", .children = &.{
                    .{ .label = "sugiyama.zig", .description = "hierarchical layout" },
                    .{ .label = "force.zig", .description = "force-directed layout" },
                }},
                .{ .label = "render/", .children = &.{
                    .{ .label = "svg.zig" },
                    .{ .label = "terminal.zig" },
                    .{ .label = "json.zig" },
                }},
            }},
            .{ .label = "examples/", .description = "runnable examples" },
            .{ .label = "docs/", .description = "documentation site" },
        },
    }};

    const output = try T.tree.render(allocator, &tree, .{});
    defer allocator.free(output);
    std.debug.print("{s}\n", .{output});
}
```

## Force-Directed Layout

```zig
const zigraph = @import("zigraph");

var g = zigraph.Graph.init(allocator);
defer g.deinit();

// Add nodes and edges...

var ir = try zigraph.layout(&g, allocator, .{
    .algorithm = .force_directed,
    .iterations = 500,
});
defer ir.deinit();

const svg = try zigraph.svg.render(ir, allocator, .{});
```

The force-directed layout (Fruchterman-Reingold) works better for graphs without a clear hierarchy — social networks, similarity graphs, or any undirected graph.

```

- [ ] **Step 3: Commit**

```bash
git add docs/site/content/syntax-highlighting/ docs/site/content/zig-api/
git commit -m "feat(docs): add syntax highlighting and Zig API sections"
```

---

### Task 9: GitHub Actions Deployment

**Files:**
- Create: `.github/workflows/docs.yml`

- [ ] **Step 1: Create `.github/workflows/docs.yml`**

```yaml
name: Deploy Docs

on:
  push:
    branches: [main]
    paths:
      - 'docs/site/**'
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: pages
  cancel-in-progress: true

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install Zig
        uses: mlugg/setup-zig@v2
        with:
          version: "0.15.0"

      - name: Install Zine
        run: |
          cd docs/site
          zig fetch --save git+https://github.com/kristoff-it/zine#v0.11.2

      - name: Build site
        run: |
          cd docs/site
          zine release

      - name: Upload artifact
        uses: actions/upload-pages-artifact@v3
        with:
          path: docs/site/public

  deploy:
    needs: build
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v4
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/docs.yml
git commit -m "ci: add GitHub Actions workflow for docs site deployment"
```

---

### Task 10: Smoke Test — Build and Serve Locally

- [ ] **Step 1: Install Zine if not already available**

```bash
# Check if zine is available
which zine || echo "Zine not installed — install via: zig fetch + build, or download from https://github.com/kristoff-it/zine/releases"
```

If Zine is not installed, install it:

```bash
cd /tmp
git clone https://github.com/kristoff-it/zine.git
cd zine
zig build -Doptimize=ReleaseFast
cp zig-out/bin/zine ~/.local/bin/  # Or wherever your PATH points
```

- [ ] **Step 2: Test the site builds**

```bash
cd docs/site
zine release
```

Expected: Site builds to `docs/site/public/` without errors. All pages generated.

- [ ] **Step 3: Test dev server**

```bash
cd docs/site
zine
```

Expected: Dev server starts at `http://localhost:1990`. Open in browser and verify:

- Home page renders with hero section
- Navigation links work
- Sidebar shows section pages
- TOC generates from headings
- Split-view examples show with ASCII/SVG toggle
- Audience callouts (CLI/Zig API) render with colored borders
- Prev/next navigation works on content pages
- Mobile responsive (resize browser window)

- [ ] **Step 4: Fix any build errors**

If Zine reports template or content errors, fix them and re-run. Common issues:

- Missing `.layout` in frontmatter
- Invalid Scripty expressions in templates
- Unresolved `$site.page()` references (page path doesn't match content directory)

- [ ] **Step 5: Commit any fixes**

```bash
git add -A docs/site/
git commit -m "fix(docs): resolve build errors from smoke test"
```
