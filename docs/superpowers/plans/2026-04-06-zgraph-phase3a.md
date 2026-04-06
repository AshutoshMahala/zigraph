# Phase 3a: Tree-sitter Grammar + Editor Syntax Highlighting — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a Tree-sitter grammar for `.zgraph` files with full syntax highlighting in Neovim and VS Code, publishable to npm via bun.

**Architecture:** Standalone `tree-sitter-zgraph/` package with `grammar.js` → Tree-sitter generate → C parser. Dual highlighting: Tree-sitter queries for Neovim/Helix, TextMate `.tmLanguage.json` for VS Code. VS Code extension wraps TextMate grammar + LSP client. Neovim gets ftdetect + query files + LSP setup docs.

**Tech Stack:** Tree-sitter (grammar.js, tree-sitter-cli), bun (package manager), TypeScript (VS Code extension), esbuild (extension bundling), vscode-languageclient (LSP client)

---

## Important: Actual zgraph Syntax Reference

The grammar MUST match the real tokenizer/parser in `src/dsl/`. Key syntax facts discovered from source:

- **Comments**: `#` (hash), NOT `//`
- **Variables**: `${name}` inside strings (e.g., `"${env} server"`), NOT `$name`
- **Variable definitions**: `vars { key: value }` blocks
- **Edge operators** (9 total): `->`, `<-`, `--`, `<->`, `=>`, `==>`, `-.->`, `-..->`, `-..-`
- **Directives**: `@layout`, `@theme`, `@direction`, `@spacing`, `@import`, `@border`, `@align`, `@style`
- **Block types**: identifier-based (e.g., `pipeline`, `network`), NOT keywords. Layout is set via `[dag]`, `[tree]`, etc.
- **Style rules**: `@style node { ... }`, `@style edge { ... }`, `@style .classname { ... }`
- **Class references**: `.classname` on nodes
- **Dot-path identifiers**: `frontend.App`
- **Table syntax**: `headers: Col1, Col2` and `row: val1, val2` (colon-based)
- **Property blocks**: `[key=value, key=value]` on nodes/edges
- **Card bracket syntax**: `svc: [Auth | Port: 8080]`
- **Strings**: double-quoted `"text"`, support `${var}` interpolation inside
- **Numbers**: digits, consumed as identifiers by tokenizer (e.g., `8080`)
- **Semicolons**: optional statement separators

## File Structure

### New Files (create)

| File | Purpose |
|---|---|
| `tree-sitter-zgraph/grammar.js` | Tree-sitter grammar definition |
| `tree-sitter-zgraph/package.json` | bun-managed npm package |
| `tree-sitter-zgraph/queries/highlights.scm` | Syntax highlighting queries |
| `tree-sitter-zgraph/queries/locals.scm` | Scope/variable tracking |
| `tree-sitter-zgraph/queries/injections.scm` | Language injections (empty placeholder) |
| `tree-sitter-zgraph/test/corpus/blocks.txt` | Tree-sitter tests: blocks |
| `tree-sitter-zgraph/test/corpus/edges.txt` | Tree-sitter tests: edge chains |
| `tree-sitter-zgraph/test/corpus/directives.txt` | Tree-sitter tests: directives |
| `tree-sitter-zgraph/test/corpus/tables.txt` | Tree-sitter tests: table syntax |
| `tree-sitter-zgraph/test/corpus/comments.txt` | Tree-sitter tests: comments |
| `tree-sitter-zgraph/test/corpus/variables.txt` | Tree-sitter tests: vars blocks, interpolation |
| `tree-sitter-zgraph/test/corpus/styles.txt` | Tree-sitter tests: @style rules |
| `editors/neovim/ftdetect/zgraph.vim` | Neovim filetype detection |
| `editors/neovim/queries/zgraph/highlights.scm` | Neovim highlight queries (copy) |
| `editors/neovim/queries/zgraph/locals.scm` | Neovim locals queries (copy) |
| `editors/neovim/README.md` | Neovim setup instructions |
| `editors/vscode/package.json` | VS Code extension manifest |
| `editors/vscode/syntaxes/zgraph.tmLanguage.json` | TextMate grammar |
| `editors/vscode/language-configuration.json` | Language configuration |
| `editors/vscode/src/extension.ts` | LSP client |
| `editors/vscode/tsconfig.json` | TypeScript config |
| `CREDITS.md` | Inspiration credits |

### Existing Files (no modifications needed)

The Tree-sitter grammar is a standalone package; no changes to existing Zig source files.

---

### Task 1: Tree-sitter Package Scaffold

**Files:**
- Create: `tree-sitter-zgraph/package.json`
- Create: `tree-sitter-zgraph/grammar.js` (minimal skeleton)

- [ ] **Step 1: Create package.json**

```bash
cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl-impl
mkdir -p tree-sitter-zgraph
```

Create `tree-sitter-zgraph/package.json`:

```json
{
  "name": "tree-sitter-zgraph",
  "version": "0.1.0",
  "description": "Tree-sitter grammar for the zgraph graph description language",
  "main": "bindings/node",
  "types": "bindings/node",
  "keywords": [
    "tree-sitter",
    "parser",
    "zgraph",
    "graph",
    "syntax-highlighting"
  ],
  "repository": {
    "type": "git",
    "url": "https://github.com/markussagen/zigraph"
  },
  "license": "MIT",
  "files": [
    "grammar.js",
    "binding.gyp",
    "prebuilds/**",
    "bindings/node/*",
    "queries/*",
    "src/**"
  ],
  "dependencies": {
    "node-addon-api": "^8.0.0",
    "node-gyp-build": "^4.8.0"
  },
  "devDependencies": {
    "tree-sitter-cli": "^0.24.0"
  },
  "scripts": {
    "generate": "tree-sitter generate",
    "test": "tree-sitter test",
    "parse": "tree-sitter parse",
    "build": "tree-sitter generate && tree-sitter test"
  },
  "tree-sitter": [
    {
      "scope": "source.zgraph",
      "file-types": ["zgraph"],
      "highlights": "queries/highlights.scm",
      "locals": "queries/locals.scm",
      "injections": "queries/injections.scm"
    }
  ]
}
```

- [ ] **Step 2: Create minimal grammar.js skeleton**

Create `tree-sitter-zgraph/grammar.js`:

```javascript
/// <reference types="tree-sitter-cli/dsl" />
// @ts-check

module.exports = grammar({
  name: 'zgraph',

  extras: $ => [/\s/],

  rules: {
    source_file: $ => repeat($._statement),

    _statement: $ => choice(
      $.comment,
    ),

    comment: _ => token(seq('#', /.*/)),
  },
});
```

- [ ] **Step 3: Install dependencies and verify generation**

```bash
cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl-impl/tree-sitter-zgraph
bun install
bunx tree-sitter generate
```

Expected: `src/` directory created with `parser.c`, `tree_sitter/parser.h`, etc.

- [ ] **Step 4: Create a minimal test to verify setup**

Create `tree-sitter-zgraph/test/corpus/comments.txt`:

```
================
Single line comment
================

# this is a comment

---

(source_file
  (comment))
```

```bash
cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl-impl/tree-sitter-zgraph
bunx tree-sitter test
```

Expected: 1 test, 1 passed.

- [ ] **Step 5: Add tree-sitter-zgraph/src/ to .gitignore**

The `src/` directory inside `tree-sitter-zgraph/` is auto-generated by `tree-sitter generate`. Add to `.gitignore`:

```
# Tree-sitter generated files
tree-sitter-zgraph/src/
tree-sitter-zgraph/node_modules/
tree-sitter-zgraph/build/
```

**Note:** Tree-sitter convention is to commit `src/` for consumers who don't want to run generate. However, since this is early development, it's cleaner to gitignore and generate on demand. This can be revisited before npm publish.

- [ ] **Step 6: Commit**

```bash
cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl-impl
git add tree-sitter-zgraph/package.json tree-sitter-zgraph/grammar.js tree-sitter-zgraph/test/corpus/comments.txt .gitignore
git commit -m "feat(tree-sitter): scaffold tree-sitter-zgraph package with minimal grammar"
```

---

### Task 2: Core Grammar — Blocks and Identifiers

**Files:**
- Modify: `tree-sitter-zgraph/grammar.js`
- Create: `tree-sitter-zgraph/test/corpus/blocks.txt`

- [ ] **Step 1: Write block tests**

Create `tree-sitter-zgraph/test/corpus/blocks.txt`:

```
================
Empty named block
================

pipeline {
}

---

(source_file
  (block
    (block_name
      (identifier))
    (block_body)))

================
Block with layout annotation
================

network [dag] {
}

---

(source_file
  (block
    (block_name
      (identifier))
    (layout_annotation
      (identifier))
    (block_body)))

================
Block with string name
================

"My Graph" {
}

---

(source_file
  (block
    (block_name
      (string))
    (block_body)))

================
Nested blocks
================

system {
  frontend {
  }
}

---

(source_file
  (block
    (block_name
      (identifier))
    (block_body
      (block
        (block_name
          (identifier))
        (block_body)))))

================
Block without name
================

{
  A
}

---

(source_file
  (block
    (block_body
      (node_decl
        (identifier)))))
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl-impl/tree-sitter-zgraph
bunx tree-sitter test
```

Expected: Failures for block tests (only comment rule exists).

- [ ] **Step 3: Implement block and identifier rules**

Update `tree-sitter-zgraph/grammar.js`:

```javascript
/// <reference types="tree-sitter-cli/dsl" />
// @ts-check

module.exports = grammar({
  name: 'zgraph',

  extras: $ => [/\s/, $.comment],

  conflicts: $ => [
    [$.block, $.node_decl],
  ],

  rules: {
    source_file: $ => repeat($._statement),

    _statement: $ => choice(
      $.block,
      $.node_decl,
    ),

    block: $ => seq(
      optional(field('name', $.block_name)),
      optional(field('layout', $.layout_annotation)),
      '{',
      optional(field('body', $.block_body)),
      '}',
    ),

    block_name: $ => choice($.identifier, $.string),

    layout_annotation: $ => seq('[', $.identifier, ']'),

    block_body: $ => repeat1($._block_statement),

    _block_statement: $ => choice(
      $.block,
      $.node_decl,
    ),

    node_decl: $ => $.identifier,

    identifier: _ => /[a-zA-Z_][a-zA-Z0-9_\-]*/,

    string: _ => seq('"', /[^"]*/, '"'),

    comment: _ => token(seq('#', /.*/)),
  },
});
```

- [ ] **Step 4: Generate and run tests**

```bash
cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl-impl/tree-sitter-zgraph
bunx tree-sitter generate
bunx tree-sitter test
```

Expected: All block and comment tests pass. If there are conflicts or unexpected tree shapes, adjust `grammar.js` rules and `conflicts` array, then re-run. The exact tree shape may differ slightly from the test expectations — update tests to match the actual generated tree if the structure is semantically correct.

- [ ] **Step 5: Commit**

```bash
cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl-impl
git add tree-sitter-zgraph/grammar.js tree-sitter-zgraph/test/corpus/blocks.txt
git commit -m "feat(tree-sitter): add block and identifier grammar rules"
```

---

### Task 3: Core Grammar — Edge Chains and Operators

**Files:**
- Modify: `tree-sitter-zgraph/grammar.js`
- Create: `tree-sitter-zgraph/test/corpus/edges.txt`

- [ ] **Step 1: Write edge chain tests**

Create `tree-sitter-zgraph/test/corpus/edges.txt`:

```
================
Simple directed edge
================

A -> B

---

(source_file
  (edge_chain
    (identifier)
    (edge_operator)
    (identifier)))

================
Bidirectional edge
================

A <-> B

---

(source_file
  (edge_chain
    (identifier)
    (edge_operator)
    (identifier)))

================
Chain of three nodes
================

A -> B -> C

---

(source_file
  (edge_chain
    (identifier)
    (edge_operator)
    (identifier)
    (edge_operator)
    (identifier)))

================
All edge operators
================

A -> B
C <- D
E -- F
G <-> H
I => J
K ==> L
M -.-> N
O -..-> P
Q -..- R

---

(source_file
  (edge_chain (identifier) (edge_operator) (identifier))
  (edge_chain (identifier) (edge_operator) (identifier))
  (edge_chain (identifier) (edge_operator) (identifier))
  (edge_chain (identifier) (edge_operator) (identifier))
  (edge_chain (identifier) (edge_operator) (identifier))
  (edge_chain (identifier) (edge_operator) (identifier))
  (edge_chain (identifier) (edge_operator) (identifier))
  (edge_chain (identifier) (edge_operator) (identifier))
  (edge_chain (identifier) (edge_operator) (identifier)))

================
Edge with string labels
================

"Web Server" -> "Database"

---

(source_file
  (edge_chain
    (string)
    (edge_operator)
    (string)))

================
Edge with property list
================

A [color=red] -> B [shape=circle]

---

(source_file
  (edge_chain
    (identifier)
    (property_list
      (property
        (property_key)
        (property_value
          (identifier))))
    (edge_operator)
    (identifier)
    (property_list
      (property
        (property_key)
        (property_value
          (identifier))))))

================
Edge with class reference
================

db .database -> cache .cache

---

(source_file
  (edge_chain
    (identifier)
    (class_ref)
    (edge_operator)
    (identifier)
    (class_ref)))

================
Dot path identifiers
================

frontend.App -> backend.API

---

(source_file
  (edge_chain
    (identifier)
    (edge_operator)
    (identifier)))
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl-impl/tree-sitter-zgraph
bunx tree-sitter test
```

Expected: Edge tests fail.

- [ ] **Step 3: Add edge chain, operator, property, and class rules**

Update `tree-sitter-zgraph/grammar.js` — replace the full content:

```javascript
/// <reference types="tree-sitter-cli/dsl" />
// @ts-check

module.exports = grammar({
  name: 'zgraph',

  extras: $ => [/\s/, $.comment],

  conflicts: $ => [
    [$.block, $.edge_chain],
    [$.block, $.node_decl],
    [$.edge_chain, $.node_decl],
  ],

  rules: {
    source_file: $ => repeat($._statement),

    _statement: $ => choice(
      $.block,
      $.edge_chain,
      $.node_decl,
    ),

    // ── Blocks ──────────────────────────────────────────

    block: $ => seq(
      optional(field('name', $.block_name)),
      optional(field('layout', $.layout_annotation)),
      '{',
      optional(field('body', $.block_body)),
      '}',
    ),

    block_name: $ => choice($.identifier, $.string),

    layout_annotation: $ => seq('[', $.identifier, ']'),

    block_body: $ => repeat1($._block_statement),

    _block_statement: $ => choice(
      $.block,
      $.edge_chain,
      $.node_decl,
      $.directive,
      $.style_rule,
      $.table_headers,
      $.table_row_decl,
      $.vars_block,
      $.card_field,
    ),

    // ── Edges ───────────────────────────────────────────

    edge_chain: $ => seq(
      $._node_ref,
      repeat1(seq($.edge_operator, $._node_ref)),
    ),

    _node_ref: $ => seq(
      choice($.identifier, $.string),
      repeat($.class_ref),
      optional($.property_list),
    ),

    edge_operator: _ => choice(
      '->',   // directed
      '<-',   // reverse
      '--',   // undirected
      '<->',  // bidirectional
      '=>',   // bold
      '==>',  // bold double
      '-.->',  // dashed
      '-..->',  // dotted directed
      '-..-',   // dotted undirected
    ),

    // ── Node declarations ───────────────────────────────

    node_decl: $ => seq(
      choice($.identifier, $.string),
      optional(choice(
        seq(':', choice($.string, $.identifier)),  // label syntax: node: "Label"
        $.property_list,
      )),
      repeat($.class_ref),
    ),

    // ── Properties ──────────────────────────────────────

    property_list: $ => seq(
      '[',
      $.property,
      repeat(seq(',', $.property)),
      ']',
    ),

    property: $ => seq(
      field('key', $.property_key),
      '=',
      field('value', $.property_value),
    ),

    property_key: _ => /[a-zA-Z_][a-zA-Z0-9_\-]*/,

    property_value: $ => choice($.string, $.identifier, $.number),

    // ── Directives ──────────────────────────────────────

    directive: $ => seq(
      '@',
      field('name', $.directive_name),
      optional(field('value', $._directive_value)),
    ),

    directive_name: _ => /[a-zA-Z_][a-zA-Z0-9_]*/,

    _directive_value: $ => choice(
      $.string,
      $.identifier,
      $.number,
      // Comma-separated values for @align
      seq($.identifier, repeat1(seq(',', $.identifier))),
    ),

    // ── Style rules ─────────────────────────────────────

    style_rule: $ => seq(
      '@', 'style',
      field('selector', $.style_selector),
      '{',
      optional(repeat1($.property)),
      '}',
    ),

    style_selector: $ => choice(
      'node',
      'edge',
      $.class_ref,
    ),

    // ── Class references ────────────────────────────────

    class_ref: _ => /\.[a-zA-Z_][a-zA-Z0-9_\-]*/,

    // ── Variables ───────────────────────────────────────

    vars_block: $ => seq(
      'vars',
      '{',
      repeat($.var_decl),
      '}',
    ),

    var_decl: $ => seq(
      field('key', $.identifier),
      ':',
      field('value', choice($.string, $.identifier, $.number)),
    ),

    // ── Tables ──────────────────────────────────────────

    table_headers: $ => seq(
      'headers',
      ':',
      $.identifier,
      repeat(seq(',', $.identifier)),
    ),

    table_row_decl: $ => seq(
      'row',
      ':',
      $._table_value,
      repeat(seq(',', $._table_value)),
    ),

    _table_value: $ => choice($.string, $.identifier, $.number),

    // ── Card fields ─────────────────────────────────────

    card_field: $ => seq(
      field('key', $.identifier),
      ':',
      field('value', choice($.string, $.identifier, $.number)),
    ),

    // ── Literals ────────────────────────────────────────

    identifier: _ => /[a-zA-Z_][a-zA-Z0-9_\-]*(\.[a-zA-Z_][a-zA-Z0-9_\-]*)*/,

    string: $ => seq(
      '"',
      repeat(choice(
        $.string_content,
        $.string_interpolation,
      )),
      '"',
    ),

    string_content: _ => token.immediate(prec(1, /[^"$]+/)),

    string_interpolation: $ => seq(
      token.immediate('${'),
      $.identifier,
      '}',
    ),

    number: _ => /\d+(\.\d+)?/,

    comment: _ => token(seq('#', /.*/)),
  },
});
```

- [ ] **Step 4: Generate and run tests**

```bash
cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl-impl/tree-sitter-zgraph
bunx tree-sitter generate
bunx tree-sitter test
```

Expected: All tests pass. If grammar conflicts arise, add entries to the `conflicts` array and adjust. If tree shapes differ from test expectations, update test expectations to match the actual tree (verifying they're semantically correct).

**Debugging tip:** If a specific test fails, run `bunx tree-sitter parse` on the input to see what tree is actually produced, then update the test expectation.

- [ ] **Step 5: Commit**

```bash
cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl-impl
git add tree-sitter-zgraph/grammar.js tree-sitter-zgraph/test/corpus/edges.txt
git commit -m "feat(tree-sitter): add edge chains, operators, properties, and class references"
```

---

### Task 4: Grammar — Directives, Styles, Variables, Tables

**Files:**
- Modify: `tree-sitter-zgraph/grammar.js` (only if adjustments needed from Task 3)
- Create: `tree-sitter-zgraph/test/corpus/directives.txt`
- Create: `tree-sitter-zgraph/test/corpus/variables.txt`
- Create: `tree-sitter-zgraph/test/corpus/tables.txt`
- Create: `tree-sitter-zgraph/test/corpus/styles.txt`

- [ ] **Step 1: Write directive tests**

Create `tree-sitter-zgraph/test/corpus/directives.txt`:

```
================
Layout directive with identifier
================

@layout sugiyama

---

(source_file
  (directive
    (directive_name)
    (identifier)))

================
Layout directive with string
================

@layout "dagre"

---

(source_file
  (directive
    (directive_name)
    (string
      (string_content))))

================
Import directive
================

@import "styles.zgraph"

---

(source_file
  (directive
    (directive_name)
    (string
      (string_content))))

================
Direction directive
================

@direction left-right

---

(source_file
  (directive
    (directive_name)
    (identifier)))

================
Border directive
================

@border heavy

---

(source_file
  (directive
    (directive_name)
    (identifier)))

================
Align directive with multiple values
================

@align right, left, center

---

(source_file
  (directive
    (directive_name)
    (identifier)
    (identifier)
    (identifier)))

================
Directive without value
================

@theme

---

(source_file
  (directive
    (directive_name)))
```

- [ ] **Step 2: Write variable tests**

Create `tree-sitter-zgraph/test/corpus/variables.txt`:

```
================
Vars block
================

vars {
  env: production
  port: 8080
}

---

(source_file
  (vars_block
    (var_decl
      (identifier)
      (identifier))
    (var_decl
      (identifier)
      (number))))

================
String interpolation
================

server: "${env} server"

---

(source_file
  (card_field
    (identifier)
    (string
      (string_interpolation
        (identifier))
      (string_content))))

================
Vars block with string values
================

vars {
  title: "My App"
}

---

(source_file
  (vars_block
    (var_decl
      (identifier)
      (string
        (string_content)))))
```

- [ ] **Step 3: Write table tests**

Create `tree-sitter-zgraph/test/corpus/tables.txt`:

```
================
Table headers and rows
================

pipeline [table] {
  headers: ID, Name, Status
  row: 1, Parser, done
  row: 2, Lexer, wip
}

---

(source_file
  (block
    (block_name
      (identifier))
    (layout_annotation
      (identifier))
    (block_body
      (table_headers
        (identifier)
        (identifier)
        (identifier))
      (table_row_decl
        (number)
        (identifier)
        (identifier))
      (table_row_decl
        (number)
        (identifier)
        (identifier)))))
```

- [ ] **Step 4: Write style tests**

Create `tree-sitter-zgraph/test/corpus/styles.txt`:

```
================
Style rule for nodes
================

@style node {
  color = blue
  shape = circle
}

---

(source_file
  (style_rule
    (style_selector)
    (property
      (property_key)
      (property_value
        (identifier)))
    (property
      (property_key)
      (property_value
        (identifier)))))

================
Style rule for class
================

@style .database {
  shape = cylinder
}

---

(source_file
  (style_rule
    (style_selector
      (class_ref))
    (property
      (property_key)
      (property_value
        (identifier)))))
```

- [ ] **Step 5: Run all tests**

```bash
cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl-impl/tree-sitter-zgraph
bunx tree-sitter generate
bunx tree-sitter test
```

Expected: All tests pass. If tree shapes differ from expectations, use `bunx tree-sitter parse <file>` to debug, then update test expectations to match actual output. If grammar conflicts arise, adjust `conflicts` array or add `prec()` calls.

- [ ] **Step 6: Commit**

```bash
cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl-impl
git add tree-sitter-zgraph/test/corpus/directives.txt tree-sitter-zgraph/test/corpus/variables.txt tree-sitter-zgraph/test/corpus/tables.txt tree-sitter-zgraph/test/corpus/styles.txt tree-sitter-zgraph/grammar.js
git commit -m "feat(tree-sitter): add tests for directives, variables, tables, and styles"
```

---

### Task 5: Highlight Queries

**Files:**
- Create: `tree-sitter-zgraph/queries/highlights.scm`
- Create: `tree-sitter-zgraph/queries/locals.scm`
- Create: `tree-sitter-zgraph/queries/injections.scm`

- [ ] **Step 1: Create highlights.scm**

Create `tree-sitter-zgraph/queries/highlights.scm`:

```scheme
; ── Keywords ──────────────────────────────────────────────
; Block-related keywords that appear as literal tokens
["vars" "headers" "row" "node" "edge"] @keyword

; Style keyword
("@" "style" @keyword)

; ── Block names ───────────────────────────────────────────
(block (block_name (identifier) @function))
(block (block_name (string) @function))

; Layout annotation
(layout_annotation (identifier) @type)

; ── Directives ────────────────────────────────────────────
(directive "@" @attribute)
(directive_name) @attribute

; ── Edge operators ────────────────────────────────────────
(edge_operator) @operator

; ── Strings ───────────────────────────────────────────────
(string "\"" @string)
(string_content) @string
(string_interpolation "${" @punctuation.special)
(string_interpolation "}" @punctuation.special)
(string_interpolation (identifier) @variable)

; ── Numbers ───────────────────────────────────────────────
(number) @number

; ── Comments ──────────────────────────────────────────────
(comment) @comment

; ── Properties ────────────────────────────────────────────
(property_key) @property
(property_value (identifier) @string.special)

; ── Variables ─────────────────────────────────────────────
(var_decl (identifier) @variable.parameter)
(vars_block "vars" @keyword)

; ── Tables ────────────────────────────────────────────────
(table_headers "headers" @keyword)
(table_row_decl "row" @keyword)

; ── Card fields ───────────────────────────────────────────
(card_field (identifier) @property)

; ── Class references ──────────────────────────────────────
(class_ref) @type

; ── Style rules ───────────────────────────────────────────
(style_rule "@" @attribute)
(style_selector) @type

; ── Identifiers in edges ──────────────────────────────────
(edge_chain (identifier) @variable)

; ── Node declarations ─────────────────────────────────────
(node_decl (identifier) @variable)

; ── Punctuation ───────────────────────────────────────────
["{" "}"] @punctuation.bracket
["[" "]"] @punctuation.bracket
["," ":" ";"] @punctuation.delimiter
["="] @operator
```

- [ ] **Step 2: Create locals.scm**

Create `tree-sitter-zgraph/queries/locals.scm`:

```scheme
; Blocks create scopes
(block) @local.scope

; Variable definitions in vars blocks
(var_decl
  (identifier) @local.definition)

; Variable references in string interpolation
(string_interpolation
  (identifier) @local.reference)
```

- [ ] **Step 3: Create injections.scm (empty placeholder)**

Create `tree-sitter-zgraph/queries/injections.scm`:

```scheme
; No language injections needed for zgraph
; This file exists for completeness and future use
```

- [ ] **Step 4: Verify highlights work**

Create a test file `tree-sitter-zgraph/examples/demo.zgraph`:

```
# Network topology diagram

vars {
  env: production
}

network [dag] {
  @direction left-right
  @layout sugiyama

  frontend.App -> backend.API [color=blue]
  backend.API -> db .database
  db -> cache .cache

  @style node {
    shape = rect
  }

  @style .database {
    shape = cylinder
  }
}

metrics [table] {
  headers: Service, Latency, Status
  row: API, 120ms, healthy
  row: DB, 45ms, healthy
}
```

```bash
cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl-impl/tree-sitter-zgraph
bunx tree-sitter highlight examples/demo.zgraph
```

Expected: Colored output with different colors for keywords, strings, comments, operators, etc. If the command errors with "Unknown language", ensure the `tree-sitter` section in `package.json` is correct and regenerate.

- [ ] **Step 5: Commit**

```bash
cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl-impl
git add tree-sitter-zgraph/queries/ tree-sitter-zgraph/examples/demo.zgraph
git commit -m "feat(tree-sitter): add highlight, locals, and injection queries"
```

---

### Task 6: TextMate Grammar for VS Code

**Files:**
- Create: `editors/vscode/syntaxes/zgraph.tmLanguage.json`

- [ ] **Step 1: Create the TextMate grammar**

```bash
mkdir -p /Users/markussagen/code/hobby/zigraph-zgraph-dsl-impl/editors/vscode/syntaxes
```

Create `editors/vscode/syntaxes/zgraph.tmLanguage.json`:

```json
{
  "$schema": "https://raw.githubusercontent.com/martinring/tmlanguage/master/tmlanguage.json",
  "name": "zgraph",
  "scopeName": "source.zgraph",
  "patterns": [
    { "include": "#comment" },
    { "include": "#string" },
    { "include": "#directive" },
    { "include": "#style-block" },
    { "include": "#vars-block" },
    { "include": "#edge-operator" },
    { "include": "#class-ref" },
    { "include": "#property-list" },
    { "include": "#table-keyword" },
    { "include": "#number" },
    { "include": "#block-start" },
    { "include": "#identifier" }
  ],
  "repository": {
    "comment": {
      "match": "#.*$",
      "name": "comment.line.number-sign.zgraph"
    },
    "string": {
      "begin": "\"",
      "end": "\"",
      "name": "string.quoted.double.zgraph",
      "patterns": [
        {
          "match": "\\$\\{([a-zA-Z_][a-zA-Z0-9_]*)\\}",
          "captures": {
            "0": { "name": "meta.interpolation.zgraph" },
            "1": { "name": "variable.other.zgraph" }
          }
        }
      ]
    },
    "directive": {
      "match": "(@)(import|layout|theme|direction|spacing|border|align)\\b",
      "captures": {
        "1": { "name": "punctuation.definition.directive.zgraph" },
        "2": { "name": "entity.other.attribute-name.zgraph" }
      }
    },
    "style-block": {
      "begin": "(@)(style)\\s+(node|edge|\\.[a-zA-Z_][a-zA-Z0-9_\\-]*)\\s*\\{",
      "end": "\\}",
      "beginCaptures": {
        "1": { "name": "punctuation.definition.directive.zgraph" },
        "2": { "name": "keyword.control.zgraph" },
        "3": { "name": "entity.name.type.zgraph" }
      },
      "endCaptures": {
        "0": { "name": "punctuation.section.block.end.zgraph" }
      },
      "patterns": [
        { "include": "#comment" },
        { "include": "#property-assignment" }
      ]
    },
    "vars-block": {
      "begin": "\\b(vars)\\s*\\{",
      "end": "\\}",
      "beginCaptures": {
        "1": { "name": "keyword.control.zgraph" }
      },
      "endCaptures": {
        "0": { "name": "punctuation.section.block.end.zgraph" }
      },
      "patterns": [
        { "include": "#comment" },
        { "include": "#string" },
        { "include": "#number" },
        {
          "match": "([a-zA-Z_][a-zA-Z0-9_\\-]*)\\s*(:)",
          "captures": {
            "1": { "name": "variable.parameter.zgraph" },
            "2": { "name": "punctuation.separator.zgraph" }
          }
        }
      ]
    },
    "edge-operator": {
      "match": "(<==?>|<->|<-|-\\.\\.->\\.\\.|->|--|-\\.->|-\\.\\.-|=>|==>)",
      "name": "keyword.operator.edge.zgraph"
    },
    "class-ref": {
      "match": "\\.[a-zA-Z_][a-zA-Z0-9_\\-]*",
      "name": "entity.name.type.class.zgraph"
    },
    "property-list": {
      "begin": "\\[",
      "end": "\\]",
      "beginCaptures": {
        "0": { "name": "punctuation.section.brackets.begin.zgraph" }
      },
      "endCaptures": {
        "0": { "name": "punctuation.section.brackets.end.zgraph" }
      },
      "patterns": [
        { "include": "#comment" },
        { "include": "#string" },
        { "include": "#number" },
        { "include": "#property-assignment" },
        {
          "match": "[a-zA-Z_][a-zA-Z0-9_\\-]*",
          "name": "string.unquoted.zgraph"
        }
      ]
    },
    "property-assignment": {
      "match": "([a-zA-Z_][a-zA-Z0-9_\\-]*)\\s*(=)\\s*",
      "captures": {
        "1": { "name": "support.other.property.zgraph" },
        "2": { "name": "keyword.operator.assignment.zgraph" }
      }
    },
    "table-keyword": {
      "match": "\\b(headers|row)\\s*(:)",
      "captures": {
        "1": { "name": "keyword.control.zgraph" },
        "2": { "name": "punctuation.separator.zgraph" }
      }
    },
    "number": {
      "match": "\\b\\d+(\\.\\d+)?\\b",
      "name": "constant.numeric.zgraph"
    },
    "block-start": {
      "match": "([a-zA-Z_][a-zA-Z0-9_\\-]*)\\s*(\\[)([a-zA-Z_][a-zA-Z0-9_\\-]*)(\\])\\s*(?=\\{)",
      "captures": {
        "1": { "name": "entity.name.function.zgraph" },
        "2": { "name": "punctuation.section.brackets.begin.zgraph" },
        "3": { "name": "entity.name.type.layout.zgraph" },
        "4": { "name": "punctuation.section.brackets.end.zgraph" }
      }
    },
    "identifier": {
      "match": "\\b[a-zA-Z_][a-zA-Z0-9_\\-]*(\\.[a-zA-Z_][a-zA-Z0-9_\\-]*)*\\b",
      "name": "variable.other.zgraph"
    }
  }
}
```

- [ ] **Step 2: Verify JSON is valid**

```bash
cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl-impl
cat editors/vscode/syntaxes/zgraph.tmLanguage.json | python3 -m json.tool > /dev/null && echo "Valid JSON"
```

Expected: "Valid JSON"

- [ ] **Step 3: Commit**

```bash
cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl-impl
git add editors/vscode/syntaxes/zgraph.tmLanguage.json
git commit -m "feat(vscode): add TextMate grammar for zgraph syntax highlighting"
```

---

### Task 7: VS Code Extension Scaffold

**Files:**
- Create: `editors/vscode/package.json`
- Create: `editors/vscode/language-configuration.json`
- Create: `editors/vscode/tsconfig.json`
- Create: `editors/vscode/src/extension.ts`

- [ ] **Step 1: Create package.json (extension manifest)**

Create `editors/vscode/package.json`:

```json
{
  "name": "zgraph",
  "displayName": "zgraph",
  "description": "Syntax highlighting and LSP support for the zgraph graph description language",
  "version": "0.1.0",
  "publisher": "markussagen",
  "license": "MIT",
  "engines": {
    "vscode": "^1.85.0"
  },
  "categories": ["Programming Languages"],
  "activationEvents": ["onLanguage:zgraph"],
  "main": "./out/extension.js",
  "contributes": {
    "languages": [
      {
        "id": "zgraph",
        "aliases": ["zgraph", "ZGraph"],
        "extensions": [".zgraph"],
        "configuration": "./language-configuration.json",
        "icon": {
          "light": "./icons/zgraph-light.png",
          "dark": "./icons/zgraph-dark.png"
        }
      }
    ],
    "grammars": [
      {
        "language": "zgraph",
        "scopeName": "source.zgraph",
        "path": "./syntaxes/zgraph.tmLanguage.json"
      }
    ],
    "configuration": {
      "title": "zgraph",
      "properties": {
        "zgraph.lsp.path": {
          "type": "string",
          "default": "zgraph",
          "description": "Path to the zgraph binary (must support 'zgraph lsp' subcommand)"
        },
        "zgraph.lsp.enabled": {
          "type": "boolean",
          "default": true,
          "description": "Enable the zgraph language server"
        }
      }
    }
  },
  "scripts": {
    "compile": "esbuild src/extension.ts --bundle --outfile=out/extension.js --external:vscode --format=cjs --platform=node",
    "watch": "esbuild src/extension.ts --bundle --outfile=out/extension.js --external:vscode --format=cjs --platform=node --watch",
    "package": "vsce package",
    "lint": "tsc --noEmit"
  },
  "devDependencies": {
    "@types/vscode": "^1.85.0",
    "@vscode/vsce": "^3.0.0",
    "esbuild": "^0.24.0",
    "typescript": "^5.5.0"
  },
  "dependencies": {
    "vscode-languageclient": "^9.0.0"
  }
}
```

- [ ] **Step 2: Create language-configuration.json**

Create `editors/vscode/language-configuration.json`:

```json
{
  "comments": {
    "lineComment": "#"
  },
  "brackets": [
    ["{", "}"],
    ["[", "]"]
  ],
  "autoClosingPairs": [
    { "open": "{", "close": "}" },
    { "open": "[", "close": "]" },
    { "open": "\"", "close": "\"", "notIn": ["string"] }
  ],
  "surroundingPairs": [
    { "open": "{", "close": "}" },
    { "open": "[", "close": "]" },
    { "open": "\"", "close": "\"" }
  ],
  "folding": {
    "markers": {
      "start": "\\{",
      "end": "\\}"
    }
  },
  "indentationRules": {
    "increaseIndentPattern": "\\{\\s*$",
    "decreaseIndentPattern": "^\\s*\\}"
  }
}
```

- [ ] **Step 3: Create tsconfig.json**

Create `editors/vscode/tsconfig.json`:

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "lib": ["ES2020"],
    "outDir": "out",
    "rootDir": "src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true
  },
  "include": ["src"],
  "exclude": ["node_modules", "out"]
}
```

- [ ] **Step 4: Create extension.ts (LSP client)**

Create `editors/vscode/src/extension.ts`:

```typescript
import * as vscode from "vscode";
import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions,
  TransportKind,
} from "vscode-languageclient/node";

let client: LanguageClient | undefined;

export function activate(context: vscode.ExtensionContext): void {
  const config = vscode.workspace.getConfiguration("zgraph");
  const lspEnabled = config.get<boolean>("lsp.enabled", true);

  if (!lspEnabled) {
    return;
  }

  const zgraphPath = config.get<string>("lsp.path", "zgraph");

  const serverOptions: ServerOptions = {
    command: zgraphPath,
    args: ["lsp"],
    transport: TransportKind.stdio,
  };

  const clientOptions: LanguageClientOptions = {
    documentSelector: [{ scheme: "file", language: "zgraph" }],
  };

  client = new LanguageClient(
    "zgraph",
    "zgraph Language Server",
    serverOptions,
    clientOptions,
  );

  client.start();
  context.subscriptions.push({
    dispose: () => {
      if (client) {
        client.stop();
      }
    },
  });
}

export function deactivate(): Thenable<void> | undefined {
  if (client) {
    return client.stop();
  }
  return undefined;
}
```

- [ ] **Step 5: Install dependencies and verify compilation**

```bash
cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl-impl/editors/vscode
bun install
bun run compile
```

Expected: `out/extension.js` is created without errors.

- [ ] **Step 6: Add vscode build artifacts to .gitignore**

Append to `.gitignore`:

```
# VS Code extension build artifacts
editors/vscode/out/
editors/vscode/node_modules/
editors/vscode/*.vsix
```

- [ ] **Step 7: Commit**

```bash
cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl-impl
git add editors/vscode/package.json editors/vscode/language-configuration.json editors/vscode/tsconfig.json editors/vscode/src/extension.ts .gitignore
git commit -m "feat(vscode): scaffold VS Code extension with LSP client"
```

---

### Task 8: Neovim Integration

**Files:**
- Create: `editors/neovim/ftdetect/zgraph.vim`
- Create: `editors/neovim/queries/zgraph/highlights.scm`
- Create: `editors/neovim/queries/zgraph/locals.scm`
- Create: `editors/neovim/README.md`

- [ ] **Step 1: Create ftdetect**

```bash
mkdir -p /Users/markussagen/code/hobby/zigraph-zgraph-dsl-impl/editors/neovim/ftdetect
mkdir -p /Users/markussagen/code/hobby/zigraph-zgraph-dsl-impl/editors/neovim/queries/zgraph
```

Create `editors/neovim/ftdetect/zgraph.vim`:

```vim
au BufRead,BufNewFile *.zgraph set filetype=zgraph
```

- [ ] **Step 2: Copy query files from tree-sitter-zgraph**

Create `editors/neovim/queries/zgraph/highlights.scm` — identical content to `tree-sitter-zgraph/queries/highlights.scm` (copy the file from Task 5, Step 1).

Create `editors/neovim/queries/zgraph/locals.scm` — identical content to `tree-sitter-zgraph/queries/locals.scm` (copy the file from Task 5, Step 2).

```bash
cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl-impl
cp tree-sitter-zgraph/queries/highlights.scm editors/neovim/queries/zgraph/highlights.scm
cp tree-sitter-zgraph/queries/locals.scm editors/neovim/queries/zgraph/locals.scm
```

- [ ] **Step 3: Create README with setup instructions**

Create `editors/neovim/README.md`:

```markdown
# zgraph Neovim Support

Tree-sitter syntax highlighting and LSP integration for `.zgraph` files in Neovim.

## Prerequisites

- Neovim >= 0.9
- [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter)
- zgraph CLI binary on PATH (for LSP support)

## Setup

### 1. Filetype Detection

Copy `ftdetect/zgraph.vim` to your Neovim config:

```bash
cp ftdetect/zgraph.vim ~/.config/nvim/ftdetect/zgraph.vim
```

Or add this to your `init.lua`:

```lua
vim.filetype.add({
  extension = {
    zgraph = "zgraph",
  },
})
```

### 2. Tree-sitter Parser

Add the zgraph parser to your `nvim-treesitter` config:

```lua
local parser_config = require("nvim-treesitter.parsers").get_parser_configs()
parser_config.zgraph = {
  install_info = {
    url = "https://github.com/markussagen/zigraph",
    files = { "tree-sitter-zgraph/src/parser.c" },
    branch = "main",
  },
  filetype = "zgraph",
}
```

Then install the parser:

```vim
:TSInstall zgraph
```

### 3. Highlight Queries

Copy the query files to your Neovim runtime:

```bash
mkdir -p ~/.config/nvim/queries/zgraph
cp queries/zgraph/highlights.scm ~/.config/nvim/queries/zgraph/highlights.scm
cp queries/zgraph/locals.scm ~/.config/nvim/queries/zgraph/locals.scm
```

### 4. LSP Configuration

Using `nvim-lspconfig` (add to your Lua config):

```lua
local lspconfig = require("lspconfig")
local configs = require("lspconfig.configs")

if not configs.zgraph then
  configs.zgraph = {
    default_config = {
      cmd = { "zgraph", "lsp" },
      filetypes = { "zgraph" },
      root_dir = lspconfig.util.find_git_ancestor,
      single_file_support = true,
    },
  }
end

lspconfig.zgraph.setup({})
```

Or using manual LSP start (without lspconfig):

```lua
vim.api.nvim_create_autocmd("FileType", {
  pattern = "zgraph",
  callback = function()
    vim.lsp.start({
      name = "zgraph",
      cmd = { "zgraph", "lsp" },
    })
  end,
})
```

### 5. Verify

Open a `.zgraph` file and check:

```vim
:echo &filetype        " Should show: zgraph
:TSHighlightCapturesUnderCursor  " Should show highlight groups
:LspInfo               " Should show zgraph LSP attached
```
```

- [ ] **Step 4: Commit**

```bash
cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl-impl
git add editors/neovim/
git commit -m "feat(neovim): add filetype detection, query files, and setup docs"
```

---

### Task 9: Credits and Final Polish

**Files:**
- Create: `CREDITS.md`
- Modify: `tree-sitter-zgraph/test/corpus/comments.txt` (add more tests)

- [ ] **Step 1: Create CREDITS.md**

Create `CREDITS.md` at repo root:

```markdown
# Credits & Inspiration

This project draws inspiration from and builds upon ideas from the following projects:

- **[superhtml](https://github.com/nickel-org/superhtml)** — Dual highlighting approach: Tree-sitter grammar for Neovim/Helix + TextMate grammar for VS Code
- **[zigtools/playground](https://github.com/zigtools/playground)** — WASM compilation of Zig tooling, browser-based playground with LSP integration, and CodeMirror editor setup
- **[zig-tree-sitter](https://github.com/tree-sitter/zig-tree-sitter)** — Zig bindings for Tree-sitter, referenced for potential future Zig-native Tree-sitter integration
```

- [ ] **Step 2: Add more comment tests**

Update `tree-sitter-zgraph/test/corpus/comments.txt` to include additional cases:

```
================
Single line comment
================

# this is a comment

---

(source_file
  (comment))

================
Comment after edge
================

A -> B # inline comment

---

(source_file
  (edge_chain
    (identifier)
    (edge_operator)
    (identifier))
  (comment))

================
Multiple comments
================

# first comment
# second comment

---

(source_file
  (comment)
  (comment))

================
Comment inside block
================

network {
  # internal comment
  A -> B
}

---

(source_file
  (block
    (block_name
      (identifier))
    (block_body
      (edge_chain
        (identifier)
        (edge_operator)
        (identifier)))))
```

**Note:** The "Comment inside block" test expects the comment to be consumed by `extras` and not appear in the tree. If Tree-sitter's behavior differs (some grammars include comments as named nodes), adjust accordingly.

- [ ] **Step 3: Run full test suite**

```bash
cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl-impl/tree-sitter-zgraph
bunx tree-sitter generate
bunx tree-sitter test
```

Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl-impl
git add -f CREDITS.md tree-sitter-zgraph/test/corpus/comments.txt
git commit -m "docs: add CREDITS.md and expand comment test corpus"
```

---

## Self-Review

### Spec Coverage Check

| Spec requirement | Task |
|---|---|
| Tree-sitter grammar definition (grammar.js) | Tasks 1-4 |
| Highlight queries (highlights.scm, locals.scm) | Task 5 |
| Tree-sitter test corpus | Tasks 1-4, 9 |
| TextMate grammar (.tmLanguage.json) | Task 6 |
| VS Code extension (package.json, language-config, LSP client) | Task 7 |
| Neovim integration (ftdetect, queries, setup docs) | Task 8 |
| Credits section | Task 9 |
| injections.scm placeholder | Task 5 |
| Publishable to npm via bun | Task 1 (package.json) |

### Placeholder Scan

No TBD/TODO items. All code blocks are complete. All file paths are exact.

### Type Consistency

- `identifier` regex consistent across grammar.js: `/[a-zA-Z_][a-zA-Z0-9_\-]*(\.[a-zA-Z_][a-zA-Z0-9_\-]*)*/`
- `string` rule uses `string_content` and `string_interpolation` consistently
- `comment` rule uses `#` consistently (matches actual tokenizer)
- Node type names match between grammar.js and query files
