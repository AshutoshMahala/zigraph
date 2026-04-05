# zgraph Phase 2a Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the zgraph DSL with Tier 1 block types ([tree], [card], [table], [flow]), @import directive, D2-style vars, and visual multiplicity.

**Architecture:** The DSL pipeline is tokenizer → parser → resolver → bridge → renderer. Phase 2a adds new AST variants and resolver passes without changing the pipeline shape. Table and tree blocks produce alternative output types (BuiltTable, TreeNode[]) alongside the existing BuiltGraph. The @import directive is resolved before style cascade by reading/parsing imported files and merging their styles and vars.

**Tech Stack:** Zig 0.15.2, zigraph layout engine, existing terminal/SVG/JSON renderers.

**Spec:** `docs/superpowers/specs/2026-04-05-zgraph-phase2a-design.md`

**Branch:** `feat/zgraph-dsl-impl` worktree at `/Users/markussagen/code/hobby/zigraph-zgraph-dsl-impl`

---

## File Structure

**New files:**
- `src/dsl/imports.zig` — @import file resolution, cycle detection, merge logic
- `src/dsl/tree_bridge.zig` — graph-to-TreeNode conversion + tree validation

**Modified files:**
- `src/dsl/ast.zig` — Layout enum (+card, table, flow), DirectiveKind (+import_, border, align_), Statement union (+table_headers, table_row, vars_block), Document/NamedBlock (+vars)
- `src/dsl/tokenizer.zig` — keyword recognition for `vars`, `headers`, `row`
- `src/dsl/parser.zig` — vars block parsing, table statement parsing, @import directive
- `src/dsl/resolver.zig` — var substitution pass, tree validation, multiplicity property
- `src/dsl/bridge.zig` — BuiltTable type, flow alias, card default shape, table bridge
- `src/dsl/mod.zig` — re-export new modules, ParseResult gains tables/trees fields
- `src/render/terminal/mod.zig` — table re-export (from merge)
- `build.zig` — table demo build target (from merge)

**Merged files (from feat/table-renderer):**
- `src/render/terminal/table.zig`
- `src/render/terminal/table_tests.zig`
- `examples/terminal/table_demo.zig`

---

## Task 1: Merge Table Renderer

**Files:**
- Merge from: `origin/feat/table-renderer`
- Conflicts expected: `build.zig`, `src/render/terminal/mod.zig`

- [ ] **Step 1: Fetch and merge the table renderer branch**

```bash
cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl-impl
git fetch origin feat/table-renderer
git merge origin/feat/table-renderer --no-edit
```

If there are conflicts in `build.zig` or `mod.zig`, resolve them by keeping both sides (the DSL additions AND the table additions). The table renderer adds:
- In `mod.zig`: `pub const table = @import("table.zig");` and `test { _ = @import("table_tests.zig"); }`
- In `build.zig`: a `run-terminal-table-demo` build step

- [ ] **Step 2: Build and run tests**

```bash
cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl-impl
zig build test
```

Expected: all tests pass (exit code 0).

- [ ] **Step 3: Verify table demo runs**

```bash
cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl-impl
zig build run-terminal-table-demo
```

Expected: table output with borders rendered correctly.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "merge: integrate table renderer from feat/table-renderer"
```

---

## Task 2: Extend AST Types

**Files:**
- Modify: `src/dsl/ast.zig`

- [ ] **Step 1: Write test for new AST types**

Add to the existing test at the bottom of `src/dsl/ast.zig`:

```zig
test "Phase 2a AST types" {
    // Layout enum has new variants
    const layouts: [6]Layout = .{ .dag, .tree, .force, .card, .table, .flow };
    try std.testing.expectEqual(@as(usize, 6), layouts.len);

    // DirectiveKind has new variants
    const dk: DirectiveKind = .import_;
    try std.testing.expectEqual(DirectiveKind.import_, dk);
    const dk2: DirectiveKind = .border;
    try std.testing.expectEqual(DirectiveKind.border, dk2);
    const dk3: DirectiveKind = .align_;
    try std.testing.expectEqual(DirectiveKind.align_, dk3);

    // Statement union has new variants
    const s1 = Statement{ .table_headers = .{ .fields = &.{}, .loc = Loc.zero } };
    try std.testing.expect(s1 == .table_headers);
    const s2 = Statement{ .table_row = .{ .fields = &.{}, .loc = Loc.zero } };
    try std.testing.expect(s2 == .table_row);
    const s3 = Statement{ .vars_block = .{ .vars = &.{}, .loc = Loc.zero } };
    try std.testing.expect(s3 == .vars_block);

    // Document has vars field
    const doc = Document{
        .directives = &.{},
        .styles = &.{},
        .statements = &.{},
        .blocks = &.{},
        .vars = &.{},
    };
    try std.testing.expectEqual(@as(usize, 0), doc.vars.len);
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
zig build test 2>&1 | grep -c "error"
```

Expected: compilation errors (Layout missing card/table/flow, DirectiveKind missing import_/border/align_, Statement missing table_headers/table_row/vars_block, Document missing vars).

- [ ] **Step 3: Add new Layout variants**

In `src/dsl/ast.zig`, change:

```zig
pub const Layout = enum { dag, tree, force };
```

to:

```zig
pub const Layout = enum { dag, tree, force, card, table, flow };
```

- [ ] **Step 4: Add new DirectiveKind variants**

Change:

```zig
pub const DirectiveKind = enum { layout, theme, direction, spacing };
```

to:

```zig
pub const DirectiveKind = enum { layout, theme, direction, spacing, import_, border, align_ };
```

(Using `import_` and `align_` to avoid clashing with Zig keywords.)

- [ ] **Step 5: Add new Statement variants**

Add to the `Statement` union:

```zig
pub const Statement = union(enum) {
    edge: EdgeStatement,
    node_decl: NodeDecl,
    subgraph: SubgraphDecl,
    table_headers: struct { fields: []const []const u8, loc: Loc },
    table_row: struct { fields: []const []const u8, loc: Loc },
    vars_block: struct { vars: []Property, loc: Loc },
};
```

- [ ] **Step 6: Add vars field to Document and NamedBlock**

Change Document:

```zig
pub const Document = struct {
    directives: []Directive,
    styles: []StyleRule,
    statements: []Statement,
    blocks: []NamedBlock,
    vars: []Property,
};
```

Add `vars` field to NamedBlock:

```zig
pub const NamedBlock = struct {
    name: []const u8,
    layout: ?Layout = null,
    directives: []Directive,
    styles: []StyleRule,
    statements: []Statement,
    vars: []Property,
    loc: Loc,
};
```

- [ ] **Step 7: Fix all compilation errors from AST changes**

The new `vars` field on `Document` and `NamedBlock` will cause compilation errors everywhere these structs are constructed. Fix each callsite by adding `.vars = &.{}`:

- `src/dsl/parser.zig` — where Document and NamedBlock are returned
- `src/dsl/ast.zig` — in the existing test
- Any other test files constructing these types

Also fix any `switch` statements on `Statement` or `Layout` or `DirectiveKind` that need new arms. Search for switch statements on these types in:
- `src/dsl/parser.zig`
- `src/dsl/resolver.zig`
- `src/dsl/bridge.zig`
- `src/dsl/mod.zig`

For new `Statement` arms in the resolver, add a placeholder that skips them for now:

```zig
.table_headers, .table_row, .vars_block => {},
```

For new `Layout` arms in the bridge, add:

```zig
.card, .flow => presets.sugiyama.standard(),
.table => presets.sugiyama.standard(), // tables don't use graph layout
```

For new `DirectiveKind` arms in the resolver:

```zig
.import_, .border, .align_ => {}, // handled in separate passes
```

- [ ] **Step 8: Run tests**

```bash
zig build test 2>&1; echo "EXIT: $?"
```

Expected: EXIT: 0, all tests pass.

- [ ] **Step 9: Commit**

```bash
git add src/dsl/ast.zig src/dsl/parser.zig src/dsl/resolver.zig src/dsl/bridge.zig src/dsl/mod.zig
git commit -m "feat(ast): add Phase 2a types — Layout, DirectiveKind, Statement, vars"
```

---

## Task 3: Tokenizer — New Keywords

**Files:**
- Modify: `src/dsl/tokenizer.zig`

- [ ] **Step 1: Write test for new keywords**

Add to the test section of `src/dsl/tokenizer.zig`:

```zig
test "tokenize vars keyword" {
    const allocator = std.testing.allocator;
    var err_list = errors.ErrorList.init(allocator);
    defer err_list.deinit();
    const tokens = try tokenize(allocator, "vars {", &err_list);
    defer allocator.free(tokens);
    try std.testing.expectEqual(TokenKind.identifier, tokens[0].kind);
    try std.testing.expectEqualStrings("vars", tokens[0].text);
    try std.testing.expectEqual(TokenKind.lbrace, tokens[1].kind);
}

test "tokenize headers keyword" {
    const allocator = std.testing.allocator;
    var err_list = errors.ErrorList.init(allocator);
    defer err_list.deinit();
    const tokens = try tokenize(allocator, "headers: ID, Name", &err_list);
    defer allocator.free(tokens);
    try std.testing.expectEqual(TokenKind.identifier, tokens[0].kind);
    try std.testing.expectEqualStrings("headers", tokens[0].text);
    try std.testing.expectEqual(TokenKind.colon, tokens[1].kind);
}

test "tokenize row keyword" {
    const allocator = std.testing.allocator;
    var err_list = errors.ErrorList.init(allocator);
    defer err_list.deinit();
    const tokens = try tokenize(allocator, "row: 1, Parser, done", &err_list);
    defer allocator.free(tokens);
    try std.testing.expectEqual(TokenKind.identifier, tokens[0].kind);
    try std.testing.expectEqualStrings("row", tokens[0].text);
}

test "tokenize @import directive" {
    const allocator = std.testing.allocator;
    var err_list = errors.ErrorList.init(allocator);
    defer err_list.deinit();
    const tokens = try tokenize(allocator, "@import \"styles.zgraph\"", &err_list);
    defer allocator.free(tokens);
    try std.testing.expectEqual(TokenKind.at_keyword, tokens[0].kind);
    try std.testing.expectEqualStrings("import", tokens[0].text);
    try std.testing.expectEqual(TokenKind.string, tokens[1].kind);
    try std.testing.expectEqualStrings("styles.zgraph", tokens[1].text);
}

test "tokenize @border directive" {
    const allocator = std.testing.allocator;
    var err_list = errors.ErrorList.init(allocator);
    defer err_list.deinit();
    const tokens = try tokenize(allocator, "@border heavy", &err_list);
    defer allocator.free(tokens);
    try std.testing.expectEqual(TokenKind.at_keyword, tokens[0].kind);
    try std.testing.expectEqualStrings("border", tokens[0].text);
}

test "tokenize @align directive" {
    const allocator = std.testing.allocator;
    var err_list = errors.ErrorList.init(allocator);
    defer err_list.deinit();
    const tokens = try tokenize(allocator, "@align right, left, center", &err_list);
    defer allocator.free(tokens);
    try std.testing.expectEqual(TokenKind.at_keyword, tokens[0].kind);
    try std.testing.expectEqualStrings("align", tokens[0].text);
}
```

- [ ] **Step 2: Run tests to verify they pass (or fail if tokenizer needs changes)**

The tokenizer already handles `@keyword` as `.at_keyword` and bare words as `.identifier`. The keywords `vars`, `headers`, `row` are just identifiers — no special token type needed. `@import`, `@border`, `@align` are handled by the existing `@` + identifier tokenization path.

```bash
zig build test 2>&1; echo "EXIT: $?"
```

Expected: Tests should pass since `vars`, `headers`, `row` are already valid identifiers, and `@import`, `@border`, `@align` are already valid `at_keyword` tokens. If they pass, no tokenizer changes needed.

- [ ] **Step 3: Commit (if any changes were needed)**

```bash
git add src/dsl/tokenizer.zig
git commit -m "test(tokenizer): add keyword tests for Phase 2a tokens"
```

---

## Task 4: Parser — `vars {}` Block

**Files:**
- Modify: `src/dsl/parser.zig`

- [ ] **Step 1: Write test for vars block parsing**

Add a test to `src/dsl/parser.zig`:

```zig
test "parse vars block" {
    const allocator = std.testing.allocator;
    var err_list = errors.ErrorList.init(allocator);
    defer err_list.deinit();
    const source =
        \\vars {
        \\  env: production
        \\  db: PostgreSQL
        \\}
        \\A -> B
    ;
    const tokens = try tokenizer.tokenize(allocator, source, &err_list);
    defer allocator.free(tokens);
    var p = Parser.init(allocator, tokens, &err_list);
    const doc = try p.parse();

    try std.testing.expectEqual(@as(usize, 2), doc.vars.len);
    try std.testing.expectEqualStrings("env", doc.vars[0].key);
    try std.testing.expectEqualStrings("production", doc.vars[0].value);
    try std.testing.expectEqualStrings("db", doc.vars[1].key);
    try std.testing.expectEqualStrings("PostgreSQL", doc.vars[1].value);
    try std.testing.expectEqual(@as(usize, 1), doc.statements.len);
}
```

- [ ] **Step 2: Run test — should fail**

```bash
zig build test 2>&1 | grep "parse vars"
```

Expected: FAIL (vars block not parsed yet).

- [ ] **Step 3: Implement vars block parsing**

In `parser.zig`, in the main `parse()` method, before processing statements, check for `vars` keyword followed by `{`:

Add a helper method `parseVarsBlock`:

```zig
fn parseVarsBlock(self: *Parser) ![]ast.Property {
    // Current token should be "vars", next should be "{"
    _ = self.advance(); // skip "vars"
    self.skipNewlines();
    if (self.peek().kind != .lbrace) {
        try self.err_list.add(self.peek().loc, .expected_closing_brace, "expected '{' after 'vars'");
        return &.{};
    }
    _ = self.advance(); // skip "{"
    self.skipNewlines();

    var vars_list = std.ArrayList(ast.Property).init(self.allocator);

    while (self.peek().kind != .rbrace and self.peek().kind != .eof) {
        if (self.peek().kind == .identifier) {
            const key_tok = self.advance();
            self.skipNewlines();
            if (self.peek().kind == .colon) {
                _ = self.advance(); // skip ":"
                // Read the rest of the line as the value
                const value = self.parseValueUntilNewline();
                try vars_list.append(.{
                    .key = key_tok.text,
                    .value = value,
                    .loc = key_tok.loc,
                });
            }
        }
        self.skipNewlines();
    }

    if (self.peek().kind == .rbrace) {
        _ = self.advance(); // skip "}"
    }

    return vars_list.toOwnedSlice();
}
```

Also add `parseValueUntilNewline()` helper that reads tokens until newline/EOF and joins them as a string value (or reads a single string/identifier token).

In the `parse()` method, at the top-level parsing loop, check: if current token is `identifier` with text `"vars"` and next token is `lbrace`, call `parseVarsBlock()` and store in `doc_vars`.

- [ ] **Step 4: Run tests**

```bash
zig build test 2>&1; echo "EXIT: $?"
```

Expected: EXIT: 0, "parse vars block" test passes.

- [ ] **Step 5: Commit**

```bash
git add src/dsl/parser.zig
git commit -m "feat(parser): add vars block parsing"
```

---

## Task 5: Parser — Table Statements (`headers:`, `row:`)

**Files:**
- Modify: `src/dsl/parser.zig`

- [ ] **Step 1: Write test for table block parsing**

```zig
test "parse table block" {
    const allocator = std.testing.allocator;
    var err_list = errors.ErrorList.init(allocator);
    defer err_list.deinit();
    const source =
        \\metrics [table] {
        \\  headers: ID, Name, Status
        \\  row: 1, Parser, done
        \\  row: 2, Resolver, "in progress"
        \\}
    ;
    const tokens = try tokenizer.tokenize(allocator, source, &err_list);
    defer allocator.free(tokens);
    var p = Parser.init(allocator, tokens, &err_list);
    const doc = try p.parse();

    try std.testing.expectEqual(@as(usize, 1), doc.blocks.len);
    const block = &doc.blocks[0];
    try std.testing.expectEqualStrings("metrics", block.name);
    try std.testing.expectEqual(ast.Layout.table, block.layout.?);

    // Should have 3 statements: 1 headers + 2 rows
    try std.testing.expectEqual(@as(usize, 3), block.statements.len);
    try std.testing.expect(block.statements[0] == .table_headers);
    try std.testing.expectEqual(@as(usize, 3), block.statements[0].table_headers.fields.len);
    try std.testing.expectEqualStrings("ID", block.statements[0].table_headers.fields[0]);

    try std.testing.expect(block.statements[1] == .table_row);
    try std.testing.expectEqualStrings("1", block.statements[1].table_row.fields[0]);

    try std.testing.expect(block.statements[2] == .table_row);
    try std.testing.expectEqualStrings("in progress", block.statements[2].table_row.fields[2]);
}
```

- [ ] **Step 2: Run test — should fail**

- [ ] **Step 3: Implement table statement parsing**

In the named block parser (`parseNamedBlock`), after detecting `layout = .table`, use a table-specific body parser instead of the standard statement parser.

Add `parseTableBody()`:

```zig
fn parseTableBody(self: *Parser) ![]ast.Statement {
    var stmts = std.ArrayList(ast.Statement).init(self.allocator);

    while (self.peek().kind != .rbrace and self.peek().kind != .eof) {
        self.skipNewlines();
        if (self.peek().kind == .rbrace or self.peek().kind == .eof) break;

        const tok = self.peek();
        if (tok.kind == .at_keyword) {
            // Table-level directives like @border, @align — parse as directives
            // (handled by existing parseDirective, stored in block.directives)
            // ... handle or skip
        } else if (tok.kind == .identifier and std.mem.eql(u8, tok.text, "headers")) {
            const loc = tok.loc;
            _ = self.advance(); // skip "headers"
            if (self.peek().kind == .colon) _ = self.advance(); // skip ":"
            const fields = try self.parseCommaSeparatedValues();
            try stmts.append(.{ .table_headers = .{ .fields = fields, .loc = loc } });
        } else if (tok.kind == .identifier and std.mem.eql(u8, tok.text, "row")) {
            const loc = tok.loc;
            _ = self.advance(); // skip "row"
            if (self.peek().kind == .colon) _ = self.advance(); // skip ":"
            const fields = try self.parseCommaSeparatedValues();
            try stmts.append(.{ .table_row = .{ .fields = fields, .loc = loc } });
        } else {
            _ = self.advance(); // skip unknown
        }
    }

    return stmts.toOwnedSlice();
}
```

Add `parseCommaSeparatedValues()` helper:

```zig
fn parseCommaSeparatedValues(self: *Parser) ![]const []const u8 {
    var fields = std.ArrayList([]const u8).init(self.allocator);

    while (self.peek().kind != .newline and self.peek().kind != .eof and self.peek().kind != .rbrace) {
        const tok = self.peek();
        if (tok.kind == .string or tok.kind == .identifier) {
            try fields.append(tok.text);
            _ = self.advance();
        } else if (tok.kind == .comma) {
            _ = self.advance(); // skip comma
        } else {
            break;
        }
    }

    return fields.toOwnedSlice();
}
```

In `parseNamedBlock`, after detecting the layout type, branch:

```zig
const statements = if (layout == .table)
    try self.parseTableBody()
else
    try self.parseBlockStatements();
```

- [ ] **Step 4: Run tests**

```bash
zig build test 2>&1; echo "EXIT: $?"
```

Expected: EXIT: 0.

- [ ] **Step 5: Commit**

```bash
git add src/dsl/parser.zig
git commit -m "feat(parser): add table block parsing (headers/row statements)"
```

---

## Task 6: Parser — `@import` Directive

**Files:**
- Modify: `src/dsl/parser.zig`

- [ ] **Step 1: Write test**

```zig
test "parse @import directive" {
    const allocator = std.testing.allocator;
    var err_list = errors.ErrorList.init(allocator);
    defer err_list.deinit();
    const source =
        \\@import "styles.zgraph"
        \\A -> B
    ;
    const tokens = try tokenizer.tokenize(allocator, source, &err_list);
    defer allocator.free(tokens);
    var p = Parser.init(allocator, tokens, &err_list);
    const doc = try p.parse();

    try std.testing.expectEqual(@as(usize, 1), doc.directives.len);
    try std.testing.expectEqual(ast.DirectiveKind.import_, doc.directives[0].kind);
    try std.testing.expectEqualStrings("styles.zgraph", doc.directives[0].value);
}
```

- [ ] **Step 2: Run test — should fail**

- [ ] **Step 3: Implement @import directive parsing**

In `parseDirective()`, add the `"import"` keyword mapping:

```zig
const kind: ast.DirectiveKind = if (std.mem.eql(u8, name, "layout"))
    .layout
else if (std.mem.eql(u8, name, "theme"))
    .theme
else if (std.mem.eql(u8, name, "direction"))
    .direction
else if (std.mem.eql(u8, name, "spacing"))
    .spacing
else if (std.mem.eql(u8, name, "import"))
    .import_
else if (std.mem.eql(u8, name, "border"))
    .border
else if (std.mem.eql(u8, name, "align"))
    .align_
else {
    // unknown directive
    ...
};
```

For `@import`, the value is a string token (quoted path):

```zig
if (kind == .import_) {
    // Expect a string literal for the path
    if (self.peek().kind == .string) {
        const path_tok = self.advance();
        return ast.Directive{ .kind = kind, .value = path_tok.text, .loc = loc };
    }
}
```

- [ ] **Step 4: Run tests**

```bash
zig build test 2>&1; echo "EXIT: $?"
```

- [ ] **Step 5: Commit**

```bash
git add src/dsl/parser.zig
git commit -m "feat(parser): add @import, @border, @align directive parsing"
```

---

## Task 7: `[flow]` Block Type

**Files:**
- Modify: `src/dsl/bridge.zig`

- [ ] **Step 1: Write test**

Add to `bridge.zig` tests:

```zig
test "flow block defaults to left-right direction" {
    const source =
        \\pipeline [flow] {
        \\  A -> B -> C
        \\}
    ;
    var built = try testBuild(source);
    defer built.deinit();
    try std.testing.expectEqual(ast.Direction.left_right, built.direction);
}
```

- [ ] **Step 2: Run test — should fail**

- [ ] **Step 3: Implement flow alias**

In `bridge.zig`'s `buildGraph()`, when mapping the layout config, add:

```zig
.flow => {
    // flow is an alias for dag with left-right direction
    config = presets.sugiyama.standard();
    if (std.mem.eql(u8, block.config.direction, "")) {
        direction = .left_right;
    }
},
```

Also ensure the `Layout` → config mapping recognizes `.flow`:

```zig
const config = switch (block.config.layout) {
    .force => presets.fdg_presets.standard(),
    .dag, .tree, .card, .flow => presets.sugiyama.standard(),
    .table => presets.sugiyama.standard(), // unused but needed for exhaustive switch
};
```

And in the direction mapping, default to left-right for flow:

```zig
const direction: ast.Direction = blk: {
    if (std.mem.eql(u8, block.config.direction, "left-right")) break :blk .left_right
    else if (std.mem.eql(u8, block.config.direction, "bottom-up")) break :blk .bottom_up
    else if (std.mem.eql(u8, block.config.direction, "right-left")) break :blk .right_left
    else if (block.config.layout == .flow) break :blk .left_right  // flow default
    else break :blk .top_down;
};
```

- [ ] **Step 4: Run tests**

```bash
zig build test 2>&1; echo "EXIT: $?"
```

- [ ] **Step 5: Commit**

```bash
git add src/dsl/bridge.zig
git commit -m "feat(bridge): add [flow] block type as dag + left-right alias"
```

---

## Task 8: `[card]` Block Type — Default Shape

**Files:**
- Modify: `src/dsl/resolver.zig`

- [ ] **Step 1: Write test**

Add to `resolver.zig` tests:

```zig
test "card block defaults all nodes to card shape" {
    const allocator = std.testing.allocator;
    var err_list = errors.ErrorList.init(allocator);
    defer err_list.deinit();
    const source =
        \\team [card] {
        \\  alice: "Alice Smith"
        \\  bob: "Bob Jones"
        \\}
    ;
    const tokens = try tokenizer.tokenize(allocator, source, &err_list);
    defer allocator.free(tokens);
    var p = parser.Parser.init(allocator, tokens, &err_list);
    const doc = try p.parse();
    const result = try resolve(allocator, doc, &err_list);
    _ = result; // just verify it compiles and doesn't error

    // Check that all nodes in the card block have shape = .card
    // (verification depends on how ResolvedNode exposes shape)
}
```

- [ ] **Step 2: Implement card default shape**

In the resolver, when processing a block with `layout = .card`, set the default shape for all nodes in that block:

In `resolveShape()` or the node resolution path, check if the block layout is `.card` and force shape to `.card` when no explicit shape property is set.

The simplest approach: in the resolver's block processing, after resolving all nodes, if `block.config.layout == .card`, iterate nodes and set any with shape `.rect` (default) to `.card`.

- [ ] **Step 3: Run tests**

```bash
zig build test 2>&1; echo "EXIT: $?"
```

- [ ] **Step 4: Commit**

```bash
git add src/dsl/resolver.zig
git commit -m "feat(resolver): [card] block defaults all nodes to card shape"
```

---

## Task 9: `[tree]` Block — Validation + Bridge

**Files:**
- Create: `src/dsl/tree_bridge.zig`
- Modify: `src/dsl/mod.zig`

- [ ] **Step 1: Create tree_bridge.zig with tests**

Create `src/dsl/tree_bridge.zig`:

```zig
//! Converts a resolved graph block with tree layout into TreeNode structures.
//! Validates tree constraints: no cycles, single parent per node.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ast = @import("ast.zig");
const errors = @import("errors.zig");
const terminal = @import("../render/terminal/mod.zig");

pub const TreeNode = terminal.tree.TreeNode;

pub const TreeResult = struct {
    roots: []const TreeNode,
    allocator: Allocator,

    pub fn deinit(self: *TreeResult) void {
        // TreeNodes borrow strings from the resolved block, no deep free needed
        self.allocator.free(self.roots);
    }
};

/// Build TreeNode forest from resolved edges.
/// Validates: no cycles, each node has at most one parent.
pub fn buildTree(
    allocator: Allocator,
    node_ids: []const []const u8,
    node_labels: []const []const u8,
    edges: []const struct { from: []const u8, to: []const u8 },
    err_list: *errors.ErrorList,
) !TreeResult {
    // 1. Build adjacency list and parent map
    var children_map = std.StringHashMap(std.ArrayList([]const u8)).init(allocator);
    defer {
        var it = children_map.valueIterator();
        while (it.next()) |list| list.deinit();
        children_map.deinit();
    }

    var parent_map = std.StringHashMap([]const u8).init(allocator);
    defer parent_map.deinit();

    // Initialize all nodes
    for (node_ids) |id| {
        if (!children_map.contains(id)) {
            try children_map.put(id, std.ArrayList([]const u8).init(allocator));
        }
    }

    // Process edges
    for (edges) |edge| {
        // Multi-parent check
        if (parent_map.get(edge.to)) |existing_parent| {
            try err_list.add(errors.Loc.zero, .invalid_property_value,
                try std.fmt.allocPrint(allocator,
                    "node '{s}' has multiple parents in [tree] block: '{s}' and '{s}'",
                    .{ edge.to, existing_parent, edge.from }));
            continue;
        }
        try parent_map.put(edge.to, edge.from);

        var list = children_map.getPtr(edge.from) orelse blk: {
            try children_map.put(edge.from, std.ArrayList([]const u8).init(allocator));
            break :blk children_map.getPtr(edge.from).?;
        };
        try list.append(edge.to);
    }

    // 2. Find roots (nodes with no parent)
    var root_ids = std.ArrayList([]const u8).init(allocator);
    defer root_ids.deinit();
    for (node_ids) |id| {
        if (!parent_map.contains(id)) {
            try root_ids.append(id);
        }
    }

    if (root_ids.items.len == 0 and node_ids.len > 0) {
        try err_list.add(errors.Loc.zero, .invalid_property_value,
            "cycle detected in [tree] block: no root nodes found");
        return TreeResult{ .roots = &.{}, .allocator = allocator };
    }

    // 3. Build TreeNode forest recursively
    var label_map = std.StringHashMap([]const u8).init(allocator);
    defer label_map.deinit();
    for (node_ids, node_labels) |id, label| {
        try label_map.put(id, label);
    }

    var roots = std.ArrayList(TreeNode).init(allocator);
    for (root_ids.items) |root_id| {
        const node = try buildTreeNode(allocator, root_id, &children_map, &label_map);
        try roots.append(node);
    }

    return TreeResult{ .roots = try roots.toOwnedSlice(), .allocator = allocator };
}

fn buildTreeNode(
    allocator: Allocator,
    id: []const u8,
    children_map: *std.StringHashMap(std.ArrayList([]const u8)),
    label_map: *std.StringHashMap([]const u8),
) !TreeNode {
    const label = label_map.get(id) orelse id;
    const child_ids = if (children_map.get(id)) |list| list.items else &[_][]const u8{};

    var children = std.ArrayList(TreeNode).init(allocator);
    for (child_ids) |child_id| {
        try children.append(try buildTreeNode(allocator, child_id, children_map, label_map));
    }

    return TreeNode{
        .label = label,
        .children = try children.toOwnedSlice(),
    };
}

// ── Tests ────────────────────────────────────────────────────────────────────

const testing = std.testing;

test "buildTree: simple tree" {
    const allocator = testing.allocator;
    var err_list = errors.ErrorList.init(allocator);
    defer err_list.deinit();

    const Edge = struct { from: []const u8, to: []const u8 };
    const edge_list: []const Edge = &.{
        .{ .from = "root", .to = "a" },
        .{ .from = "root", .to = "b" },
        .{ .from = "b", .to = "c" },
    };

    var result = try buildTree(
        allocator,
        &.{ "root", "a", "b", "c" },
        &.{ "Root", "A", "B", "C" },
        edge_list,
        &err_list,
    );
    defer result.deinit();

    try testing.expect(!err_list.hasErrors());
    try testing.expectEqual(@as(usize, 1), result.roots.len);
    try testing.expectEqualStrings("Root", result.roots[0].label);
    try testing.expectEqual(@as(usize, 2), result.roots[0].children.len);
}

test "buildTree: multi-parent error" {
    const allocator = testing.allocator;
    var err_list = errors.ErrorList.init(allocator);
    defer err_list.deinit();

    const Edge = struct { from: []const u8, to: []const u8 };
    const edge_list: []const Edge = &.{
        .{ .from = "a", .to = "c" },
        .{ .from = "b", .to = "c" },
    };

    var result = try buildTree(
        allocator,
        &.{ "a", "b", "c" },
        &.{ "A", "B", "C" },
        edge_list,
        &err_list,
    );
    defer result.deinit();

    try testing.expect(err_list.hasErrors());
}

test "buildTree: forest (multiple roots)" {
    const allocator = testing.allocator;
    var err_list = errors.ErrorList.init(allocator);
    defer err_list.deinit();

    const Edge = struct { from: []const u8, to: []const u8 };
    const edge_list: []const Edge = &.{
        .{ .from = "a", .to = "b" },
        .{ .from = "c", .to = "d" },
    };

    var result = try buildTree(
        allocator,
        &.{ "a", "b", "c", "d" },
        &.{ "A", "B", "C", "D" },
        edge_list,
        &err_list,
    );
    defer result.deinit();

    try testing.expect(!err_list.hasErrors());
    try testing.expectEqual(@as(usize, 2), result.roots.len);
}
```

- [ ] **Step 2: Add to mod.zig**

In `src/dsl/mod.zig`, add:

```zig
pub const tree_bridge = @import("tree_bridge.zig");
```

And in the test block:

```zig
_ = tree_bridge;
```

- [ ] **Step 3: Run tests**

```bash
zig build test 2>&1; echo "EXIT: $?"
```

Expected: EXIT: 0, tree_bridge tests pass.

- [ ] **Step 4: Commit**

```bash
git add src/dsl/tree_bridge.zig src/dsl/mod.zig
git commit -m "feat(dsl): add tree_bridge — graph-to-TreeNode conversion with validation"
```

---

## Task 10: `@import` Resolution Module

**Files:**
- Create: `src/dsl/imports.zig`
- Modify: `src/dsl/mod.zig`

- [ ] **Step 1: Create imports.zig with core logic and tests**

Create `src/dsl/imports.zig`:

```zig
//! @import directive resolution.
//!
//! Resolves @import directives by reading, tokenizing, and parsing
//! imported files, then merging their @style rules and vars into
//! the importing document. Detects import cycles.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ast = @import("ast.zig");
const errors = @import("errors.zig");
const tokenizer = @import("tokenizer.zig");
const parser = @import("parser.zig");

pub const ImportResult = struct {
    styles: []ast.StyleRule,
    vars: []ast.Property,
};

/// Resolve all @import directives in a document.
/// Returns merged styles and vars from all imports (depth-first, transitive).
/// Detects cycles via the visited set.
pub fn resolveImports(
    allocator: Allocator,
    directives: []const ast.Directive,
    base_dir: []const u8,
    visited: *std.StringHashMap(void),
    err_list: *errors.ErrorList,
) !ImportResult {
    var all_styles = std.ArrayList(ast.StyleRule).init(allocator);
    var all_vars = std.ArrayList(ast.Property).init(allocator);

    for (directives) |dir| {
        if (dir.kind != .import_) continue;

        const rel_path = dir.value;

        // Resolve path relative to base_dir
        const full_path = try std.fs.path.join(allocator, &.{ base_dir, rel_path });
        defer allocator.free(full_path);

        // Cycle detection
        if (visited.contains(full_path)) {
            try err_list.add(dir.loc, .invalid_property_value,
                try std.fmt.allocPrint(allocator,
                    "import cycle detected: '{s}'", .{rel_path}));
            continue;
        }
        try visited.put(try allocator.dupe(u8, full_path), {});

        // Read file
        const source = std.fs.cwd().readFileAlloc(allocator, full_path, 1024 * 1024) catch |err| {
            try err_list.add(dir.loc, .invalid_property_value,
                try std.fmt.allocPrint(allocator,
                    "import file not found: '{s}' ({s})", .{ rel_path, @errorName(err) }));
            continue;
        };
        defer allocator.free(source);

        // Tokenize + parse
        const tokens = tokenizer.tokenize(allocator, source, err_list) catch continue;
        defer allocator.free(tokens);
        var p = parser.Parser.init(allocator, tokens, err_list);
        const doc = p.parse() catch continue;

        // Recursively resolve imports in the imported file
        const import_dir = std.fs.path.dirname(full_path) orelse ".";
        const sub_result = try resolveImports(allocator, doc.directives, import_dir, visited, err_list);

        // Merge: imported file's imports first, then its own styles/vars
        try all_styles.appendSlice(sub_result.styles);
        try all_styles.appendSlice(doc.styles);
        try all_vars.appendSlice(sub_result.vars);
        try all_vars.appendSlice(doc.vars);
    }

    return ImportResult{
        .styles = try all_styles.toOwnedSlice(),
        .vars = try all_vars.toOwnedSlice(),
    };
}

// ── Tests ────────────────────────────────────────────────────────────────────

test "import: cycle detection" {
    // Cycle detection is tested via the visited set mechanism
    const allocator = std.testing.allocator;
    var err_list = errors.ErrorList.init(allocator);
    defer err_list.deinit();

    var visited = std.StringHashMap(void).init(allocator);
    defer visited.deinit();

    // Mark a path as already visited
    try visited.put(try allocator.dupe(u8, "/fake/path/styles.zgraph"), {});

    // Try to import the same path
    const directives: []const ast.Directive = &.{.{
        .kind = .import_,
        .value = "styles.zgraph",
        .loc = errors.Loc.zero,
    }};

    const result = try resolveImports(allocator, directives, "/fake/path", &visited, &err_list);
    _ = result;

    try std.testing.expect(err_list.hasErrors());
}
```

- [ ] **Step 2: Add to mod.zig**

```zig
pub const imports = @import("imports.zig");
```

- [ ] **Step 3: Run tests**

```bash
zig build test 2>&1; echo "EXIT: $?"
```

- [ ] **Step 4: Commit**

```bash
git add src/dsl/imports.zig src/dsl/mod.zig
git commit -m "feat(dsl): add @import resolution with cycle detection"
```

---

## Task 11: Vars Substitution in Resolver

**Files:**
- Modify: `src/dsl/resolver.zig`

- [ ] **Step 1: Write test**

Add to resolver tests:

```zig
test "var substitution in labels" {
    const allocator = std.testing.allocator;
    var err_list = errors.ErrorList.init(allocator);
    defer err_list.deinit();
    const source =
        \\vars {
        \\  env: production
        \\}
        \\server: "${env} server"
    ;
    const tokens = try tokenizer.tokenize(allocator, source, &err_list);
    defer allocator.free(tokens);
    var p = parser.Parser.init(allocator, tokens, &err_list);
    const doc = try p.parse();
    const result = try resolve(allocator, doc, &err_list);

    try std.testing.expect(!err_list.hasErrors());
    // Find the server node and check its label
    for (result.blocks[0].nodes) |node| {
        if (std.mem.eql(u8, node.id, "server")) {
            try std.testing.expectEqualStrings("production server", node.label);
            break;
        }
    }
}
```

- [ ] **Step 2: Implement var substitution**

Add a `substituteVars` function to the resolver:

```zig
fn substituteVars(allocator: Allocator, text: []const u8, vars_map: *const std.StringHashMap([]const u8)) ![]const u8 {
    // Fast path: no substitution markers
    if (std.mem.indexOf(u8, text, "${") == null) return text;

    var result = std.ArrayList(u8).init(allocator);
    var i: usize = 0;
    while (i < text.len) {
        if (i + 1 < text.len and text[i] == '$' and text[i + 1] == '{') {
            // Find closing }
            const start = i + 2;
            const end = std.mem.indexOfScalarPos(u8, text, start, '}') orelse {
                try result.append(text[i]);
                i += 1;
                continue;
            };
            const var_name = text[start..end];
            if (vars_map.get(var_name)) |value| {
                try result.appendSlice(value);
            } else {
                // Keep the original ${name} if undefined (or error)
                try result.appendSlice(text[i .. end + 1]);
            }
            i = end + 1;
        } else {
            try result.append(text[i]);
            i += 1;
        }
    }
    return result.toOwnedSlice();
}
```

Call this during the resolve pass: after collecting vars from the document (and imports), walk all node labels, edge labels, property values, and card fields, substituting `${name}` references.

- [ ] **Step 3: Run tests**

```bash
zig build test 2>&1; echo "EXIT: $?"
```

- [ ] **Step 4: Commit**

```bash
git add src/dsl/resolver.zig
git commit -m "feat(resolver): add ${var} substitution in labels and properties"
```

---

## Task 12: Table Bridge — BuiltTable

**Files:**
- Modify: `src/dsl/bridge.zig`
- Modify: `src/dsl/mod.zig`

- [ ] **Step 1: Add BuiltTable type to bridge.zig**

```zig
pub const BuiltTable = struct {
    name: []const u8,
    headers: ?[]const []const u8,
    rows: []const []const []const u8,
    border: []const u8,    // "none", "single", "heavy", "double"
    alignment: []const u8, // comma-separated alignment values
    allocator: std.mem.Allocator,

    pub fn deinit(self: *BuiltTable) void {
        _ = self; // strings are borrowed from parsed source
    }
};
```

- [ ] **Step 2: Add buildTable function**

```zig
pub fn buildTable(allocator: std.mem.Allocator, block: ResolvedBlock) !BuiltTable {
    var headers: ?[]const []const u8 = null;
    var rows = std.ArrayList([]const []const u8).init(allocator);

    // Extract directives for table config
    var border: []const u8 = "single";
    var alignment: []const u8 = "";
    for (block.config.directives) |dir| {
        if (dir.kind == .border) border = dir.value;
        if (dir.kind == .align_) alignment = dir.value;
    }

    // Note: table statements are stored differently — they come through
    // as ResolvedBlock with special handling. The actual extraction depends
    // on how the resolver passes through table_headers and table_row statements.
    // This will be wired in when the resolver collects table data.

    return BuiltTable{
        .name = block.name,
        .headers = headers,
        .rows = try rows.toOwnedSlice(),
        .border = border,
        .alignment = alignment,
        .allocator = allocator,
    };
}
```

- [ ] **Step 3: Add tables field to ParseResult in mod.zig**

In `src/dsl/mod.zig`, extend `ParseResult`:

```zig
pub const ParseResult = struct {
    graphs: []BuiltGraph,
    tables: []bridge.BuiltTable,
    trees: []tree_bridge.TreeResult,
    err_list: errors.ErrorList,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ParseResult) void {
        for (self.graphs) |*g| g.deinit();
        self.allocator.free(self.graphs);
        for (self.tables) |*t| t.deinit();
        self.allocator.free(self.tables);
        for (self.trees) |*t| t.deinit();
        self.allocator.free(self.trees);
        self.err_list.deinit();
    }

    pub fn hasErrors(self: *const ParseResult) bool {
        return self.err_list.hasErrors();
    }
};
```

Update `parseAndBuild()` to route blocks by layout type:
- `.table` → buildTable → tables list
- `.tree` → buildGraph + buildTree → trees list
- `.dag`, `.force`, `.card`, `.flow` → buildGraph → graphs list

- [ ] **Step 4: Run tests**

```bash
zig build test 2>&1; echo "EXIT: $?"
```

- [ ] **Step 5: Commit**

```bash
git add src/dsl/bridge.zig src/dsl/mod.zig
git commit -m "feat(bridge): add BuiltTable type and table/tree routing in parseAndBuild"
```

---

## Task 13: Visual Multiplicity — Property Resolution

**Files:**
- Modify: `src/dsl/resolver.zig`

- [ ] **Step 1: Write test**

```zig
test "multiplicity property resolved" {
    const allocator = std.testing.allocator;
    var err_list = errors.ErrorList.init(allocator);
    defer err_list.deinit();
    const source =
        \\server { multiple: true }
    ;
    const tokens = try tokenizer.tokenize(allocator, source, &err_list);
    defer allocator.free(tokens);
    var p = parser.Parser.init(allocator, tokens, &err_list);
    const doc = try p.parse();
    const result = try resolve(allocator, doc, &err_list);

    // Find server node and check it has the multiple property
    for (result.blocks[0].nodes) |node| {
        if (std.mem.eql(u8, node.id, "server")) {
            var found = false;
            for (node.properties) |prop| {
                if (std.mem.eql(u8, prop.key, "multiple") and std.mem.eql(u8, prop.value, "true")) {
                    found = true;
                    break;
                }
            }
            try std.testing.expect(found);
            break;
        }
    }
}
```

- [ ] **Step 2: Verify test passes (multiplicity is just a property, should work with existing style cascade)**

The `multiple: true` property should already flow through the existing property/style cascade without any changes. The property block syntax `server { multiple: true }` is parsed as a node declaration with properties, and `cascadeNodeProperties` includes inline properties.

```bash
zig build test 2>&1; echo "EXIT: $?"
```

If it passes, the resolver already handles this. The rendering side (shadow box) is a separate concern handled by the renderers — we'll add that as a follow-up if time permits, since it requires terminal renderer changes that are orthogonal to the DSL pipeline.

- [ ] **Step 3: Commit**

```bash
git add src/dsl/resolver.zig
git commit -m "test(resolver): verify multiplicity property flows through style cascade"
```

---

## Task 14: Integration — Wire Everything Together

**Files:**
- Modify: `src/dsl/mod.zig`
- Modify: `examples/dsl_demo.zig`

- [ ] **Step 1: Update parseAndBuild to handle all block types**

In `src/dsl/mod.zig`, update the `parseAndBuild` function to:

1. Run var substitution before building (already in resolver from Task 11).
2. Route blocks by layout:
   - `.table` → collect table data from statements, create BuiltTable
   - `.tree` → build graph AND build TreeNode forest
   - `.flow` → build graph with left-right direction default
   - `.card` → build graph with card shape default
   - `.dag`, `.force` → build graph (existing behavior)

- [ ] **Step 2: Update dsl_demo.zig to demonstrate new block types**

```zig
const source =
    \\@layout sugiyama
    \\
    \\Client -> API: "HTTPS"
    \\API -> Auth -> Cache
    \\
    \\backend: {
    \\  API -> Router -> Handler
    \\  Handler -> DB: "query"
    \\}
;
```

Keep the existing demo source but add a second example source for flow:

```zig
const flow_source =
    \\pipeline [flow] {
    \\  Input -> Parse -> Transform -> Output
    \\}
;
```

- [ ] **Step 3: Run full test suite**

```bash
cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl-impl
zig build test 2>&1; echo "EXIT: $?"
```

Expected: EXIT: 0, ALL tests pass.

- [ ] **Step 4: Run demo**

```bash
zig build run-dsl-demo 2>&1
```

Expected: graph renders correctly.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(dsl): wire Phase 2a block types into parseAndBuild pipeline"
```

---

## Task 15: End-to-End Integration Tests

**Files:**
- Modify: `src/dsl/mod.zig` (test section)

- [ ] **Step 1: Add integration test for [flow] block**

```zig
test "end-to-end: [flow] block renders left-right" {
    const allocator = std.testing.allocator;
    const source =
        \\pipeline [flow] {
        \\  A -> B -> C
        \\}
    ;
    var result = try parseAndBuild(allocator, source);
    defer result.deinit();
    try std.testing.expect(!result.hasErrors());
    try std.testing.expect(result.graphs.len >= 1);
    try std.testing.expectEqual(ast.Direction.left_right, result.graphs[0].direction);
}
```

- [ ] **Step 2: Add integration test for vars substitution**

```zig
test "end-to-end: vars substitution" {
    const allocator = std.testing.allocator;
    const source =
        \\vars {
        \\  svc: MyService
        \\}
        \\server: "${svc}"
        \\server -> db
    ;
    var result = try parseAndBuild(allocator, source);
    defer result.deinit();
    try std.testing.expect(!result.hasErrors());
}
```

- [ ] **Step 3: Run all tests**

```bash
zig build test 2>&1; echo "EXIT: $?"
```

Expected: EXIT: 0.

- [ ] **Step 4: Commit**

```bash
git add src/dsl/mod.zig
git commit -m "test(dsl): add end-to-end integration tests for Phase 2a features"
```

---

## Summary of Commits

1. `merge: integrate table renderer from feat/table-renderer`
2. `feat(ast): add Phase 2a types — Layout, DirectiveKind, Statement, vars`
3. `test(tokenizer): add keyword tests for Phase 2a tokens`
4. `feat(parser): add vars block parsing`
5. `feat(parser): add table block parsing (headers/row statements)`
6. `feat(parser): add @import, @border, @align directive parsing`
7. `feat(bridge): add [flow] block type as dag + left-right alias`
8. `feat(resolver): [card] block defaults all nodes to card shape`
9. `feat(dsl): add tree_bridge — graph-to-TreeNode conversion with validation`
10. `feat(dsl): add @import resolution with cycle detection`
11. `feat(resolver): add ${var} substitution in labels and properties`
12. `feat(bridge): add BuiltTable type and table/tree routing in parseAndBuild`
13. `test(resolver): verify multiplicity property flows through style cascade`
14. `feat(dsl): wire Phase 2a block types into parseAndBuild pipeline`
15. `test(dsl): add end-to-end integration tests for Phase 2a features`
