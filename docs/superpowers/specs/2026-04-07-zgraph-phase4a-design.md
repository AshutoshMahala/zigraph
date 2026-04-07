# Phase 4a: WASM-Bundled VSCode Extension, Neovim Plugin & Editor Docs

## Overview

Bundle the zgraph LSP as a WASM binary inside the VSCode extension so users get diagnostics and formatting without installing the CLI. Create a standalone `zgraph.nvim` Neovim plugin. Consolidate all editor setup documentation in the docs site.

## In Scope

1. WASM build target (`src/wasm.zig`, `build.zig` wasm step)
2. LSP verification and WASI-safety hardening
3. VSCode extension rewrite (dual-mode: WASM default + native fallback)
4. `zgraph.nvim` — separate GitHub repo, lazy.nvim installable
5. Editor documentation consolidation in docs site

## Out of Scope

- New LSP features (hover, completion, go-to-definition)
- TUI editor stubs (Ctrl+T/F/G, Ctrl+Click)
- Build-time tree-sitter query embedding (Phase 4b)

---

## 1. WASM Build Target

### Entry point: `src/wasm.zig`

Minimal WASM entry point following superhtml's pattern:

- Uses `std.heap.wasm_allocator` (WASM linear memory, not GPA)
- Parses args via `std.process.argsAlloc()`
- Delegates to the LSP server logic from `src/lsp/main.zig`
- Error handling: `oom()` and `fatal()` helpers that write to stderr and exit

### Build step

Add a `wasm` step to `build.zig`:

- Target: `wasm32-wasi`, single-threaded, no libc
- Optimization: `ReleaseSmall` for release builds (minimize binary size)
- Output: `zgraph.wasm`
- Install prefix: `editors/vscode/wasm/` (via `zig build wasm -p editors/vscode/wasm`)
- Imports: `zigraph` module + `dsl` module (same as LSP target)
- Step name: `zig build wasm`

### WASI constraints

- No `std.fs` calls in the WASM code path — documents arrive via LSP protocol
- DSL `@import` resolution gracefully returns an error diagnostic (no filesystem in WASI)
- Formatter receives content via LSP `textDocument/formatting`, not file reads

---

## 2. LSP Verification & Hardening

Before bundling as WASM, verify the existing LSP works correctly.

### Current capabilities

| Feature | Protocol Method | Status |
|---------|----------------|--------|
| Document sync | `didOpen`, `didChange`, `didClose`, `didSave` | Implemented |
| Diagnostics | `publishDiagnostics` | Implemented |
| Formatting | `textDocument/formatting` | Implemented |

### Verification checklist

- Test with native VSCode extension: open `.zgraph` file, verify diagnostics appear on syntax errors, verify formatting reformats the document
- Validate JSON-RPC protocol compliance (Content-Length framing, proper response IDs)
- Confirm no panics on malformed input (empty files, binary content, very large files)

### WASI-safety audit

- Audit `src/lsp/main.zig` for `std.fs` usage — replace or guard any filesystem calls
- Ensure `@import` in the DSL resolver returns a diagnostic error when filesystem is unavailable rather than panicking
- Verify `std.io.getStdIn()` / `std.io.getStdErr()` work under WASI (they do — WASI provides stdio)

---

## 3. VSCode Extension Rewrite

### Architecture: dual-mode LSP

The extension supports two modes, configurable via settings:

1. **WASM mode** (default): Loads `wasm/zgraph.wasm` from the extension directory, runs via `@vscode/wasm-wasi` runtime
2. **Native mode**: Spawns `zgraph lsp` as a child process over stdio (current behavior)

### New dependencies

| Package | Purpose |
|---------|---------|
| `@vscode/wasm-wasi` (v1) | WASI runtime for running WASM in VSCode |
| `@vscode/wasm-wasi-lsp` | LSP client adapter for WASM-WASI processes |

### Configuration

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `zgraph.lsp.enabled` | boolean | `true` | Toggle LSP on/off |
| `zgraph.lsp.mode` | `"wasm"` \| `"native"` | `"wasm"` | LSP execution mode |
| `zgraph.lsp.path` | string | `"zgraph"` | Path to native binary (native mode only) |

### Activation flow

```
activate()
├─ read config (mode, enabled, path)
├─ if !enabled → return
├─ if mode == "wasm"
│  ├─ resolve wasm/zgraph.wasm from extension dir
│  ├─ read file via workspace.fs.readFile()
│  ├─ compile via WebAssembly.compile()
│  ├─ create WASI process (memory: initial 160, max 160 pages)
│  ├─ start LSP server via startServer()
│  └─ on error → show message suggesting native mode
└─ if mode == "native"
   ├─ spawn `{path} lsp` via stdio
   └─ on error → show message about path setting
```

### Package changes

- Bundle `wasm/zgraph.wasm` in the VSIX package
- `.vscodeignore`: ensure `wasm/` is NOT excluded
- Bump `engines.vscode` if WASI APIs require a newer version
- Build script: `zig build wasm -p editors/vscode/wasm && cd editors/vscode && bun run build`

---

## 4. Neovim Plugin: `zgraph.nvim`

### Separate repository

Create `zgraph.nvim` as a standalone GitHub repo. Users install with lazy.nvim:

```lua
{ "markussagen/zgraph.nvim", ft = "zgraph" }
```

### Repository structure

```
zgraph.nvim/
├── lua/
│   └── zgraph/
│       └── init.lua          -- setup() entry point
├── ftdetect/
│   └── zgraph.lua            -- vim.filetype.add({ extension = { zgraph = "zgraph" } })
├── queries/
│   └── zgraph/
│       ├── highlights.scm    -- copied from tree-sitter-zgraph/queries/
│       ├── locals.scm
│       └── injections.scm
├── README.md
└── LICENSE
```

### `setup()` function

The `lua/zgraph/init.lua` `setup()` function auto-configures:

1. **Tree-sitter parser registration**: Registers the zgraph parser with install URL pointing at the main zigraph repo's `tree-sitter-zgraph` directory

2. **LSP via lspconfig** (if nvim-lspconfig is installed): Registers `zgraph` LSP — command `{ "zgraph", "lsp" }`, filetypes `{ "zgraph" }`, root pattern `{ "*.zgraph" }`

3. **Formatting via conform.nvim** (if conform is installed): Registers formatter — command `"zgraph"`, args `{ "fmt", "--stdin" }`, stdin `true`

Each integration is conditional — only configures if the corresponding plugin is available. No hard dependencies beyond Neovim >= 0.9.

### User requirement

The `zgraph` binary must be on PATH for LSP and formatting. The README explains how to get it (GitHub releases or build from source) and links to the docs site.

---

## 5. Editor Documentation Consolidation

Single source of truth: `docs/site/content/editors/`.

### `vscode.smd` — Full rewrite

- Installation from VS Code marketplace (one click)
- What's included: syntax highlighting, diagnostics, formatting (all via bundled WASM LSP)
- Configuration reference (mode, path, enabled)
- Switching to native mode
- Troubleshooting (WASM fails to load, native binary not found)

### `neovim.smd` — Full rewrite

- Quick start: lazy.nvim one-liner for `zgraph.nvim`
- What the plugin auto-configures (filetype, tree-sitter, LSP, formatting)
- Manual setup alternative for users not using lazy.nvim:
  - Filetype detection (vim.filetype.add)
  - Tree-sitter parser registration (nvim-treesitter config)
  - LSP setup (lspconfig)
  - Formatting (conform.nvim with `zgraph fmt --stdin`)
  - Query file symlinks
- Getting the zgraph binary
- Troubleshooting

### `other-editors.smd` — Light update

- Generic LSP setup: `zgraph lsp` over stdio, JSON-RPC 2.0
- TextMate grammar available at `editors/vscode/syntaxes/zgraph.tmLanguage.json`
- Tree-sitter grammar available at `tree-sitter-zgraph/`

### READMEs become pointers

- `editors/vscode/README.md` → short description + link to docs site
- `zgraph.nvim/README.md` → install instructions + link to docs site for full guide

---

## Testing

- **WASM build**: `zig build wasm` succeeds, produces valid `.wasm` file
- **LSP protocol**: Send sample JSON-RPC requests via stdin, verify correct responses
- **VSCode WASM mode**: Extension loads, diagnostics appear, formatting works
- **VSCode native mode**: Same as above with `zgraph.lsp.mode: "native"`
- **Neovim plugin**: `zgraph.nvim` installs via lazy.nvim, filetype detected, highlights work, LSP connects, formatting runs
- **Docs site**: Pages render correctly with complete setup instructions
