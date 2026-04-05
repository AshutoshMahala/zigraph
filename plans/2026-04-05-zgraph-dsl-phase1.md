# Zgraph DSL Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a text-based graph DSL (`.zgraph`) that parses into zigraph's existing Graph type for layout and rendering, with a CLI tool and markdown extraction.

**Architecture:** A four-stage pipeline: Tokenizer → Parser → Resolver → Bridge. The DSL lives in `src/dsl/`, the CLI in `src/cli/`. No existing zigraph code is modified — the DSL is a new frontend that produces `zigraph.Graph` objects.

**Tech Stack:** Zig (same version as zigraph), zigraph library APIs (`Graph`, `LayoutConfig`, terminal/SVG/JSON renderers)

**Spec:** `specs/2026-04-05-zgraph-dsl-design.md`

---

## File Structure

```
src/
├── dsl/
│   ├── ast.zig           # AST node types, Loc, enums
│   ├── tokenizer.zig     # .zgraph text → Token stream
│   ├── parser.zig        # Token stream → AST Document
│   ├── resolver.zig      # Style cascade, implicit nodes, validation → Resolved blocks
│   ├── bridge.zig        # Resolved blocks → zigraph.Graph (one per block)
│   ├── markdown.zig      # Extract ```zgraph blocks from .md files
│   ├── errors.zig        # DSL error types with line:col reporting
│   └── mod.zig           # Public API: parseAndBuild(), convenience wrappers
│
├── cli/
│   └── main.zig          # CLI entry: render, check subcommands
│
└── root.zig              # ADD: pub const dsl = @import("dsl/mod.zig");
```

**Note on node IDs:** zigraph.Graph uses `usize` node IDs. The bridge assigns sequential `usize` IDs (starting at 1) to string identifiers and maintains a `StringHashMap(usize)` for lookups. This mapping is returned alongside each Graph so the caller can correlate DSL names with graph node IDs.

---

### Task 1: AST Types and Error Types

**Files:**
- Create: `src/dsl/ast.zig`
- Create: `src/dsl/errors.zig`

These are pure data types with no logic to test independently. They form the foundation for all subsequent tasks.

- [ ] **Step 1: Create `src/dsl/errors.zig`**

```zig
const std = @import("std");

pub const Loc = struct {
    line: u32,
    col: u32,
    offset: u32,

    pub const zero = Loc{ .line = 1, .col = 1, .offset = 0 };

    pub fn format(self: Loc, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{}:{}", .{ self.line, self.col });
    }
};

pub const DslError = struct {
    loc: Loc,
    kind: Kind,
    message: []const u8,

    pub const Kind = enum {
        // Tokenizer errors
        unexpected_character,
        unterminated_string,
        unterminated_block,

        // Parser errors
        expected_identifier,
        expected_arrow_or_operator,
        expected_closing_brace,
        expected_closing_bracket,
        unexpected_token,

        // Resolver errors
        unknown_directive,
        invalid_property_value,
        unresolved_reference,
        duplicate_block_name,
        unknown_layout_type,
        unknown_shape,
    };

    pub fn format(self: DslError, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{}: error: {s}", .{ self.loc, self.message });
    }
};

pub const ErrorList = struct {
    errors: std.ArrayListUnmanaged(DslError),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ErrorList {
        return .{
            .errors = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ErrorList) void {
        self.errors.deinit(self.allocator);
    }

    pub fn add(self: *ErrorList, loc: Loc, kind: DslError.Kind, message: []const u8) !void {
        try self.errors.append(self.allocator, .{
            .loc = loc,
            .kind = kind,
            .message = message,
        });
    }

    pub fn hasErrors(self: *const ErrorList) bool {
        return self.errors.items.len > 0;
    }
};
```

- [ ] **Step 2: Create `src/dsl/ast.zig`**

```zig
const std = @import("std");
const errors = @import("errors.zig");
pub const Loc = errors.Loc;

pub const EdgeOp = enum {
    directed,           // ->
    reverse,            // <-
    undirected,         // --
    bidirectional,      // <->
    bold,               // =>
    bold_double,        // ==>
    dashed_directed,    // -.->
    dotted_directed,    // -..->
    dotted_undirected,  // -..-
};

pub const Layout = enum {
    dag,
    tree,
    force,
};

pub const Shape = enum {
    rect,
    circle,
    diamond,
    cylinder,
    person,
    pill,
    hexagon,
    parallelogram,
    queue,
    cloud,
    card,
};

pub const Property = struct {
    key: []const u8,
    value: []const u8,
    loc: Loc,
};

pub const PropertyBlock = struct {
    properties: []Property,
    loc: Loc,
};

pub const NodeRef = struct {
    id: []const u8,
    label: ?[]const u8 = null,
    card_fields: ?[]const []const u8 = null,
    properties: ?PropertyBlock = null,
    classes: []const []const u8 = &.{},
    loc: Loc,
};

pub const EdgeStatement = struct {
    chain: []NodeRef,
    operator: EdgeOp,
    label: ?[]const u8 = null,
    properties: ?PropertyBlock = null,
    classes: []const []const u8 = &.{},
    fan_out: bool = false, // true for A -> B, C, D (source -> multiple targets)
    loc: Loc,
};

pub const NodeDecl = struct {
    ref: NodeRef,
    loc: Loc,
};

pub const SubgraphDecl = struct {
    name: []const u8,
    label: ?[]const u8 = null,
    properties: ?PropertyBlock = null,
    statements: []Statement,
    loc: Loc,
};

pub const Statement = union(enum) {
    edge: EdgeStatement,
    node_decl: NodeDecl,
    subgraph: SubgraphDecl,
};

pub const DirectiveKind = enum {
    layout,
    theme,
    direction,
    spacing,
};

pub const Directive = struct {
    kind: DirectiveKind,
    value: []const u8,
    loc: Loc,
};

pub const StyleSelector = union(enum) {
    element: enum { node, edge },
    class: []const u8,
};

pub const StyleRule = struct {
    selector: StyleSelector,
    properties: PropertyBlock,
    loc: Loc,
};

pub const NamedBlock = struct {
    name: []const u8,
    layout: ?Layout = null,
    directives: []Directive,
    styles: []StyleRule,
    statements: []Statement,
    loc: Loc,
};

pub const Document = struct {
    directives: []Directive,
    styles: []StyleRule,
    statements: []Statement,
    blocks: []NamedBlock,
};
```

- [ ] **Step 3: Verify both files compile**

Run: `cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl && zig build-lib src/dsl/ast.zig --name ast_check 2>&1; echo "exit: $?"`

Expected: Compiles without errors (or use a test import approach — see step 4).

- [ ] **Step 4: Add a compile-smoke test**

Add to the bottom of `src/dsl/ast.zig`:

```zig
test "AST types compile and are usable" {
    const doc = Document{
        .directives = &.{},
        .styles = &.{},
        .statements = &.{},
        .blocks = &.{},
    };
    try std.testing.expectEqual(@as(usize, 0), doc.directives.len);

    const edge = EdgeStatement{
        .chain = &.{},
        .operator = .directed,
        .loc = Loc.zero,
    };
    try std.testing.expectEqual(EdgeOp.directed, edge.operator);
}
```

Run: `cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl && zig test src/dsl/ast.zig`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl
git add src/dsl/ast.zig src/dsl/errors.zig
git commit -m "feat(dsl): add AST types and error types"
```

---

### Task 2: Tokenizer

**Files:**
- Create: `src/dsl/tokenizer.zig`

The tokenizer converts `.zgraph` text into a flat token stream. It handles identifiers, strings, edge operators, `@` directives, `#` comments, braces, brackets, pipes, dots, colons, commas, semicolons, and newlines.

- [ ] **Step 1: Write failing test for basic tokenization**

Create `src/dsl/tokenizer.zig` with the Token type and test, but stub `tokenize()` to return error:

```zig
const std = @import("std");
const errors = @import("errors.zig");
const Loc = errors.Loc;

pub const TokenKind = enum {
    // Literals
    identifier,     // alphanumeric + underscore + hyphen, or dot-separated path
    string,         // "quoted string"

    // Edge operators
    arrow,          // ->
    arrow_reverse,  // <-
    dash_dash,      // --
    arrow_bidi,     // <->
    fat_arrow,      // =>
    fat_arrow2,     // ==>
    dashed_arrow,   // -.->
    dotted_arrow,   // -..->
    dotted_line,    // -..-

    // Delimiters
    lbrace,         // {
    rbrace,         // }
    lbracket,       // [
    rbracket,       // ]
    colon,          // :
    comma,          // ,
    semicolon,      // ;
    pipe,           // |
    dot,            // .

    // Directives
    at_keyword,     // @layout, @theme, @style, @direction, @spacing

    // Structure
    class,          // .classname (when preceded by whitespace or after identifier)
    newline,        // \n (significant for statement separation)
    comment,        // # ...

    // Special
    pipe_separator, // | --- (card separator in multi-line cards)
    eof,
};

pub const Token = struct {
    kind: TokenKind,
    text: []const u8,
    loc: Loc,
};

pub fn tokenize(allocator: std.mem.Allocator, source: []const u8, err_list: *errors.ErrorList) ![]Token {
    var tokens = std.ArrayList(Token).init(allocator);
    defer tokens.deinit();

    var line: u32 = 1;
    var col: u32 = 1;
    var i: usize = 0;

    while (i < source.len) {
        const c = source[i];

        // Skip spaces and tabs (not newlines)
        if (c == ' ' or c == '\t') {
            i += 1;
            col += 1;
            continue;
        }

        // Newline
        if (c == '\n') {
            try tokens.append(.{ .kind = .newline, .text = "\n", .loc = .{ .line = line, .col = col, .offset = @intCast(i) } });
            i += 1;
            line += 1;
            col = 1;
            continue;
        }

        // Carriage return (skip, handled with \n)
        if (c == '\r') {
            i += 1;
            continue;
        }

        const loc = Loc{ .line = line, .col = col, .offset = @intCast(i) };

        // Comment: # to end of line
        if (c == '#') {
            const start = i;
            while (i < source.len and source[i] != '\n') : (i += 1) {}
            try tokens.append(.{ .kind = .comment, .text = source[start..i], .loc = loc });
            col += @intCast(i - start);
            continue;
        }

        // @ directive
        if (c == '@') {
            const start = i;
            i += 1;
            while (i < source.len and (std.ascii.isAlphabetic(source[i]) or source[i] == '_')) : (i += 1) {}
            try tokens.append(.{ .kind = .at_keyword, .text = source[start..i], .loc = loc });
            col += @intCast(i - start);
            continue;
        }

        // String literal
        if (c == '"') {
            const start = i;
            i += 1;
            while (i < source.len and source[i] != '"' and source[i] != '\n') : (i += 1) {}
            if (i >= source.len or source[i] == '\n') {
                try err_list.add(loc, .unterminated_string, "unterminated string literal");
                continue;
            }
            i += 1; // skip closing "
            try tokens.append(.{ .kind = .string, .text = source[start + 1 .. i - 1], .loc = loc });
            col += @intCast(i - start);
            continue;
        }

        // Multi-char operators starting with '-'
        if (c == '-') {
            if (matchStr(source, i, "-..->")) {
                try tokens.append(.{ .kind = .dotted_arrow, .text = "-..->" , .loc = loc });
                i += 5; col += 5; continue;
            }
            if (matchStr(source, i, "-.->")) {
                try tokens.append(.{ .kind = .dashed_arrow, .text = "-.->" , .loc = loc });
                i += 4; col += 4; continue;
            }
            if (matchStr(source, i, "-..-")) {
                try tokens.append(.{ .kind = .dotted_line, .text = "-..-" , .loc = loc });
                i += 4; col += 4; continue;
            }
            if (matchStr(source, i, "->")) {
                try tokens.append(.{ .kind = .arrow, .text = "->" , .loc = loc });
                i += 2; col += 2; continue;
            }
            if (matchStr(source, i, "--")) {
                try tokens.append(.{ .kind = .dash_dash, .text = "--" , .loc = loc });
                i += 2; col += 2; continue;
            }
            // Bare '-' is unexpected in our grammar
            try err_list.add(loc, .unexpected_character, "unexpected '-'");
            i += 1; col += 1;
            continue;
        }

        // Operators starting with '<'
        if (c == '<') {
            if (matchStr(source, i, "<->")) {
                try tokens.append(.{ .kind = .arrow_bidi, .text = "<->" , .loc = loc });
                i += 3; col += 3; continue;
            }
            if (matchStr(source, i, "<-")) {
                try tokens.append(.{ .kind = .arrow_reverse, .text = "<-" , .loc = loc });
                i += 2; col += 2; continue;
            }
            try err_list.add(loc, .unexpected_character, "unexpected '<'");
            i += 1; col += 1;
            continue;
        }

        // Operators starting with '='
        if (c == '=') {
            if (matchStr(source, i, "==>")) {
                try tokens.append(.{ .kind = .fat_arrow2, .text = "==>" , .loc = loc });
                i += 3; col += 3; continue;
            }
            if (matchStr(source, i, "=>")) {
                try tokens.append(.{ .kind = .fat_arrow, .text = "=>" , .loc = loc });
                i += 2; col += 2; continue;
            }
            try err_list.add(loc, .unexpected_character, "unexpected '='");
            i += 1; col += 1;
            continue;
        }

        // Single-char delimiters
        if (c == '{') { try tokens.append(.{ .kind = .lbrace, .text = "{", .loc = loc }); i += 1; col += 1; continue; }
        if (c == '}') { try tokens.append(.{ .kind = .rbrace, .text = "}", .loc = loc }); i += 1; col += 1; continue; }
        if (c == '[') { try tokens.append(.{ .kind = .lbracket, .text = "[", .loc = loc }); i += 1; col += 1; continue; }
        if (c == ']') { try tokens.append(.{ .kind = .rbracket, .text = "]", .loc = loc }); i += 1; col += 1; continue; }
        if (c == ':') { try tokens.append(.{ .kind = .colon, .text = ":", .loc = loc }); i += 1; col += 1; continue; }
        if (c == ',') { try tokens.append(.{ .kind = .comma, .text = ",", .loc = loc }); i += 1; col += 1; continue; }
        if (c == ';') { try tokens.append(.{ .kind = .semicolon, .text = ";", .loc = loc }); i += 1; col += 1; continue; }
        if (c == '|') { try tokens.append(.{ .kind = .pipe, .text = "|", .loc = loc }); i += 1; col += 1; continue; }

        // Dot: could be a class reference (.classname) or standalone dot
        if (c == '.') {
            if (i + 1 < source.len and isIdentStart(source[i + 1])) {
                // Class reference: .classname
                const start = i;
                i += 1; // skip .
                while (i < source.len and isIdentContinue(source[i])) : (i += 1) {}
                try tokens.append(.{ .kind = .class, .text = source[start + 1 .. i], .loc = loc });
                col += @intCast(i - start);
                continue;
            }
            try tokens.append(.{ .kind = .dot, .text = ".", .loc = loc });
            i += 1; col += 1;
            continue;
        }

        // Identifier (alphanumeric, underscore, hyphen; also handles dot-paths like frontend.App)
        if (isIdentStart(c)) {
            const start = i;
            while (i < source.len and (isIdentContinue(source[i]) or source[i] == '.')) : (i += 1) {}
            // Don't include trailing dot
            if (i > start and source[i - 1] == '.') {
                i -= 1;
            }
            try tokens.append(.{ .kind = .identifier, .text = source[start..i], .loc = loc });
            col += @intCast(i - start);
            continue;
        }

        // Unknown character
        try err_list.add(loc, .unexpected_character, "unexpected character");
        i += 1;
        col += 1;
    }

    // Append EOF
    try tokens.append(.{ .kind = .eof, .text = "", .loc = .{ .line = line, .col = col, .offset = @intCast(source.len) } });

    return tokens.toOwnedSlice();
}

fn matchStr(source: []const u8, pos: usize, needle: []const u8) bool {
    if (pos + needle.len > source.len) return false;
    return std.mem.eql(u8, source[pos..][0..needle.len], needle);
}

fn isIdentStart(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_';
}

fn isIdentContinue(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_' or c == '-';
}

test "tokenize simple edge" {
    var err_list = errors.ErrorList.init(std.testing.allocator);
    defer err_list.deinit();

    const tokens = try tokenize(std.testing.allocator, "A -> B", &err_list);
    defer std.testing.allocator.free(tokens);

    try std.testing.expect(!err_list.hasErrors());
    // A, ->, B, eof
    try std.testing.expectEqual(@as(usize, 4), tokens.len);
    try std.testing.expectEqual(TokenKind.identifier, tokens[0].kind);
    try std.testing.expectEqualStrings("A", tokens[0].text);
    try std.testing.expectEqual(TokenKind.arrow, tokens[1].kind);
    try std.testing.expectEqual(TokenKind.identifier, tokens[2].kind);
    try std.testing.expectEqualStrings("B", tokens[2].text);
    try std.testing.expectEqual(TokenKind.eof, tokens[3].kind);
}

test "tokenize all edge operators" {
    var err_list = errors.ErrorList.init(std.testing.allocator);
    defer err_list.deinit();

    const tokens = try tokenize(std.testing.allocator, "-> <- -- <-> => ==> -.-> -..-> -..-", &err_list);
    defer std.testing.allocator.free(tokens);

    try std.testing.expect(!err_list.hasErrors());
    try std.testing.expectEqual(TokenKind.arrow, tokens[0].kind);
    try std.testing.expectEqual(TokenKind.arrow_reverse, tokens[1].kind);
    try std.testing.expectEqual(TokenKind.dash_dash, tokens[2].kind);
    try std.testing.expectEqual(TokenKind.arrow_bidi, tokens[3].kind);
    try std.testing.expectEqual(TokenKind.fat_arrow, tokens[4].kind);
    try std.testing.expectEqual(TokenKind.fat_arrow2, tokens[5].kind);
    try std.testing.expectEqual(TokenKind.dashed_arrow, tokens[6].kind);
    try std.testing.expectEqual(TokenKind.dotted_arrow, tokens[7].kind);
    try std.testing.expectEqual(TokenKind.dotted_line, tokens[8].kind);
}

test "tokenize directive and string" {
    var err_list = errors.ErrorList.init(std.testing.allocator);
    defer err_list.deinit();

    const tokens = try tokenize(std.testing.allocator, "@layout sugiyama\ndb: \"PostgreSQL\"", &err_list);
    defer std.testing.allocator.free(tokens);

    try std.testing.expect(!err_list.hasErrors());
    try std.testing.expectEqual(TokenKind.at_keyword, tokens[0].kind);
    try std.testing.expectEqualStrings("@layout", tokens[0].text);
    try std.testing.expectEqual(TokenKind.identifier, tokens[1].kind);
    try std.testing.expectEqualStrings("sugiyama", tokens[1].text);
    try std.testing.expectEqual(TokenKind.newline, tokens[2].kind);
    try std.testing.expectEqual(TokenKind.identifier, tokens[3].kind);
    try std.testing.expectEqualStrings("db", tokens[3].text);
    try std.testing.expectEqual(TokenKind.colon, tokens[4].kind);
    try std.testing.expectEqual(TokenKind.string, tokens[5].kind);
    try std.testing.expectEqualStrings("PostgreSQL", tokens[5].text);
}

test "tokenize class references" {
    var err_list = errors.ErrorList.init(std.testing.allocator);
    defer err_list.deinit();

    const tokens = try tokenize(std.testing.allocator, "db .database .large", &err_list);
    defer std.testing.allocator.free(tokens);

    try std.testing.expect(!err_list.hasErrors());
    try std.testing.expectEqual(TokenKind.identifier, tokens[0].kind);
    try std.testing.expectEqual(TokenKind.class, tokens[1].kind);
    try std.testing.expectEqualStrings("database", tokens[1].text);
    try std.testing.expectEqual(TokenKind.class, tokens[2].kind);
    try std.testing.expectEqualStrings("large", tokens[2].text);
}

test "tokenize comment" {
    var err_list = errors.ErrorList.init(std.testing.allocator);
    defer err_list.deinit();

    const tokens = try tokenize(std.testing.allocator, "# this is a comment\nA -> B", &err_list);
    defer std.testing.allocator.free(tokens);

    try std.testing.expect(!err_list.hasErrors());
    try std.testing.expectEqual(TokenKind.comment, tokens[0].kind);
    try std.testing.expectEqual(TokenKind.newline, tokens[1].kind);
    try std.testing.expectEqual(TokenKind.identifier, tokens[2].kind);
}

test "tokenize dot-path identifier" {
    var err_list = errors.ErrorList.init(std.testing.allocator);
    defer err_list.deinit();

    const tokens = try tokenize(std.testing.allocator, "frontend.App -> backend.API", &err_list);
    defer std.testing.allocator.free(tokens);

    try std.testing.expect(!err_list.hasErrors());
    try std.testing.expectEqual(TokenKind.identifier, tokens[0].kind);
    try std.testing.expectEqualStrings("frontend.App", tokens[0].text);
    try std.testing.expectEqual(TokenKind.arrow, tokens[1].kind);
    try std.testing.expectEqual(TokenKind.identifier, tokens[2].kind);
    try std.testing.expectEqualStrings("backend.API", tokens[2].text);
}

test "tokenize card bracket syntax" {
    var err_list = errors.ErrorList.init(std.testing.allocator);
    defer err_list.deinit();

    const tokens = try tokenize(std.testing.allocator, "svc: [Auth | Port: 8080]", &err_list);
    defer std.testing.allocator.free(tokens);

    try std.testing.expect(!err_list.hasErrors());
    try std.testing.expectEqual(TokenKind.identifier, tokens[0].kind);
    try std.testing.expectEqual(TokenKind.colon, tokens[1].kind);
    try std.testing.expectEqual(TokenKind.lbracket, tokens[2].kind);
    try std.testing.expectEqual(TokenKind.identifier, tokens[3].kind);
    try std.testing.expectEqual(TokenKind.pipe, tokens[4].kind);
}

test "tokenize braces and named block" {
    var err_list = errors.ErrorList.init(std.testing.allocator);
    defer err_list.deinit();

    const tokens = try tokenize(std.testing.allocator, "pipeline [dag] {\n  A -> B\n}", &err_list);
    defer std.testing.allocator.free(tokens);

    try std.testing.expect(!err_list.hasErrors());
    try std.testing.expectEqual(TokenKind.identifier, tokens[0].kind);
    try std.testing.expectEqualStrings("pipeline", tokens[0].text);
    try std.testing.expectEqual(TokenKind.lbracket, tokens[1].kind);
    try std.testing.expectEqual(TokenKind.identifier, tokens[2].kind);
    try std.testing.expectEqualStrings("dag", tokens[2].text);
    try std.testing.expectEqual(TokenKind.rbracket, tokens[3].kind);
    try std.testing.expectEqual(TokenKind.lbrace, tokens[4].kind);
}
```

- [ ] **Step 2: Run tokenizer tests**

Run: `cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl && zig test src/dsl/tokenizer.zig`

Expected: All 8 tests PASS

- [ ] **Step 3: Commit**

```bash
cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl
git add src/dsl/tokenizer.zig
git commit -m "feat(dsl): add tokenizer with all edge operators and token types"
```

---

### Task 3: Parser — Core Edge and Node Parsing

**Files:**
- Create: `src/dsl/parser.zig`

The parser converts the token stream into an AST `Document`. This task covers the core: edges (with chaining, labels, properties), node declarations, and comments. Subgraphs, named blocks, and directives come in Task 4.

- [ ] **Step 1: Write the parser with tests**

Create `src/dsl/parser.zig`:

```zig
const std = @import("std");
const ast = @import("ast.zig");
const tokenizer = @import("tokenizer.zig");
const errors = @import("errors.zig");
const Token = tokenizer.Token;
const TokenKind = tokenizer.TokenKind;
const Loc = errors.Loc;

pub const Parser = struct {
    tokens: []const Token,
    pos: usize,
    allocator: std.mem.Allocator,
    err_list: *errors.ErrorList,

    pub fn init(allocator: std.mem.Allocator, tokens: []const Token, err_list: *errors.ErrorList) Parser {
        return .{
            .tokens = tokens,
            .pos = 0,
            .allocator = allocator,
            .err_list = err_list,
        };
    }

    pub fn parse(self: *Parser) !ast.Document {
        var directives = std.ArrayList(ast.Directive).init(self.allocator);
        var styles = std.ArrayList(ast.StyleRule).init(self.allocator);
        var statements = std.ArrayList(ast.Statement).init(self.allocator);
        var blocks = std.ArrayList(ast.NamedBlock).init(self.allocator);

        while (self.peek().kind != .eof) {
            self.skipNewlines();
            if (self.peek().kind == .eof) break;

            // Skip comments
            if (self.peek().kind == .comment) {
                self.advance();
                continue;
            }

            // @ directive or @style
            if (self.peek().kind == .at_keyword) {
                const tok = self.peek();
                if (std.mem.eql(u8, tok.text, "@style")) {
                    try styles.append(try self.parseStyleRule());
                } else {
                    try directives.append(try self.parseDirective());
                }
                continue;
            }

            // Must be an identifier — could be edge, node decl, subgraph, or named block
            if (self.peek().kind == .identifier) {
                // Look ahead to determine what this is
                if (self.isNamedBlock()) {
                    try blocks.append(try self.parseNamedBlock());
                } else {
                    try statements.append(try self.parseStatement());
                }
                continue;
            }

            // Unexpected token
            try self.err_list.add(self.peek().loc, .unexpected_token, "unexpected token");
            self.advance();
        }

        return .{
            .directives = try directives.toOwnedSlice(),
            .styles = try styles.toOwnedSlice(),
            .statements = try statements.toOwnedSlice(),
            .blocks = try blocks.toOwnedSlice(),
        };
    }

    fn parseStatement(self: *Parser) !ast.Statement {
        // Identifier at start — could be edge chain, node decl, or subgraph
        const id_tok = self.peek();
        const id = id_tok.text;
        const loc = id_tok.loc;

        // Peek after identifier to decide
        const after_id = self.peekAt(self.pos + 1);

        // Edge: identifier followed by arrow operator
        if (isEdgeOp(after_id.kind)) {
            return .{ .edge = try self.parseEdge() };
        }

        // Node decl or subgraph: identifier followed by colon
        if (after_id.kind == .colon) {
            return try self.parseNodeDeclOrSubgraph();
        }

        // Node with properties: identifier followed by lbrace (all key:value = properties)
        if (after_id.kind == .lbrace) {
            return .{ .node_decl = try self.parseNodeDecl() };
        }

        // Node with class: identifier followed by .class
        if (after_id.kind == .class) {
            return .{ .node_decl = try self.parseNodeDecl() };
        }

        // Fallback: treat as bare node declaration
        self.advance();
        return .{ .node_decl = .{
            .ref = .{ .id = id, .loc = loc },
            .loc = loc,
        } };
    }

    fn parseEdge(self: *Parser) !ast.EdgeStatement {
        const loc = self.peek().loc;
        var chain = std.ArrayList(ast.NodeRef).init(self.allocator);

        // Parse first node
        try chain.append(try self.parseNodeRef());

        // Parse operator
        const op = edgeOpFromToken(self.peek().kind) orelse {
            try self.err_list.add(self.peek().loc, .expected_arrow_or_operator, "expected edge operator");
            return error.ParseError;
        };
        self.advance();

        // Parse chain: node (op node)*
        try chain.append(try self.parseNodeRef());

        // Fan-out: A -> B, C, D
        var fan_out = false;
        if (self.peek().kind == .comma) {
            fan_out = true;
            while (self.peek().kind == .comma) {
                self.advance();
                try chain.append(try self.parseNodeRef());
            }
        } else {
            // Continue chain if same operator follows: A -> B -> C
            while (isEdgeOp(self.peek().kind)) {
                const next_op = edgeOpFromToken(self.peek().kind);
                if (next_op != null and next_op.? == op) {
                    self.advance();
                    try chain.append(try self.parseNodeRef());
                } else break;
            }
        }

        // Optional label
        var label: ?[]const u8 = null;
        if (self.peek().kind == .colon) {
            self.advance();
            if (self.peek().kind == .string) {
                label = self.peek().text;
                self.advance();
            }
        }

        // Optional classes
        var classes = std.ArrayList([]const u8).init(self.allocator);
        while (self.peek().kind == .class) {
            try classes.append(self.peek().text);
            self.advance();
        }

        // Optional property block
        var properties: ?ast.PropertyBlock = null;
        if (self.peek().kind == .lbrace) {
            properties = try self.parsePropertyBlock();
        }

        return .{
            .chain = try chain.toOwnedSlice(),
            .operator = op,
            .label = label,
            .properties = properties,
            .classes = try classes.toOwnedSlice(),
            .fan_out = fan_out,
            .loc = loc,
        };
    }

    fn parseNodeRef(self: *Parser) !ast.NodeRef {
        if (self.peek().kind != .identifier) {
            try self.err_list.add(self.peek().loc, .expected_identifier, "expected node identifier");
            return error.ParseError;
        }
        const tok = self.peek();
        self.advance();
        return .{
            .id = tok.text,
            .loc = tok.loc,
        };
    }

    fn parseNodeDecl(self: *Parser) !ast.NodeDecl {
        const loc = self.peek().loc;
        var ref = try self.parseNodeRef();

        // Optional label after colon
        if (self.peek().kind == .colon) {
            self.advance();
            if (self.peek().kind == .string) {
                ref.label = self.peek().text;
                self.advance();
            } else if (self.peek().kind == .lbracket) {
                ref.card_fields = try self.parseCardFields();
            }
        }

        // Optional classes
        var classes = std.ArrayList([]const u8).init(self.allocator);
        while (self.peek().kind == .class) {
            try classes.append(self.peek().text);
            self.advance();
        }
        if (classes.items.len > 0) {
            ref.classes = try classes.toOwnedSlice();
        } else {
            classes.deinit();
        }

        // Optional property block
        if (self.peek().kind == .lbrace) {
            ref.properties = try self.parsePropertyBlock();
        }

        return .{ .ref = ref, .loc = loc };
    }

    fn parseNodeDeclOrSubgraph(self: *Parser) !ast.Statement {
        // Peek inside the brace block (if any) to disambiguate
        const id_tok = self.peek();
        const loc = id_tok.loc;

        // identifier : ...
        self.advance(); // consume identifier
        self.advance(); // consume colon

        // Could be: string label, bracket card, or lbrace (subgraph or card shape)
        if (self.peek().kind == .lbrace) {
            // Look inside to disambiguate: subgraph vs property block
            if (self.isSubgraphBrace()) {
                return .{ .subgraph = try self.parseSubgraphBody(id_tok.text, loc) };
            } else {
                // Property block on a node
                var ref = ast.NodeRef{ .id = id_tok.text, .loc = loc };
                ref.properties = try self.parsePropertyBlock();
                return .{ .node_decl = .{ .ref = ref, .loc = loc } };
            }
        }

        // String label
        if (self.peek().kind == .string) {
            const label = self.peek().text;
            self.advance();
            var ref = ast.NodeRef{ .id = id_tok.text, .label = label, .loc = loc };

            // Optional classes after label
            var classes = std.ArrayList([]const u8).init(self.allocator);
            while (self.peek().kind == .class) {
                try classes.append(self.peek().text);
                self.advance();
            }
            if (classes.items.len > 0) {
                ref.classes = try classes.toOwnedSlice();
            } else {
                classes.deinit();
            }

            // Optional property block after label
            if (self.peek().kind == .lbrace) {
                ref.properties = try self.parsePropertyBlock();
            }
            return .{ .node_decl = .{ .ref = ref, .loc = loc } };
        }

        // Bracket card fields
        if (self.peek().kind == .lbracket) {
            var ref = ast.NodeRef{ .id = id_tok.text, .loc = loc };
            ref.card_fields = try self.parseCardFields();

            var classes = std.ArrayList([]const u8).init(self.allocator);
            while (self.peek().kind == .class) {
                try classes.append(self.peek().text);
                self.advance();
            }
            if (classes.items.len > 0) {
                ref.classes = try classes.toOwnedSlice();
            } else {
                classes.deinit();
            }

            return .{ .node_decl = .{ .ref = ref, .loc = loc } };
        }

        // Bare identifier label (unquoted) — treat rest of line as implicit identifier
        const ref = ast.NodeRef{ .id = id_tok.text, .loc = loc };
        return .{ .node_decl = .{ .ref = ref, .loc = loc } };
    }

    fn parseSubgraphBody(self: *Parser, name: []const u8, loc: Loc) !ast.SubgraphDecl {
        // Consume opening brace
        std.debug.assert(self.peek().kind == .lbrace);
        self.advance();

        var stmts = std.ArrayList(ast.Statement).init(self.allocator);

        while (self.peek().kind != .rbrace and self.peek().kind != .eof) {
            self.skipNewlines();
            if (self.peek().kind == .rbrace or self.peek().kind == .eof) break;
            if (self.peek().kind == .comment) { self.advance(); continue; }

            if (self.peek().kind == .identifier) {
                try stmts.append(try self.parseStatement());
            } else {
                try self.err_list.add(self.peek().loc, .unexpected_token, "unexpected token in subgraph");
                self.advance();
            }
        }

        if (self.peek().kind == .rbrace) {
            self.advance();
        } else {
            try self.err_list.add(loc, .expected_closing_brace, "unterminated subgraph block");
        }

        return .{
            .name = name,
            .statements = try stmts.toOwnedSlice(),
            .loc = loc,
        };
    }

    fn parsePropertyBlock(self: *Parser) !ast.PropertyBlock {
        const loc = self.peek().loc;
        std.debug.assert(self.peek().kind == .lbrace);
        self.advance();

        var props = std.ArrayList(ast.Property).init(self.allocator);

        while (self.peek().kind != .rbrace and self.peek().kind != .eof) {
            self.skipNewlines();
            if (self.peek().kind == .rbrace or self.peek().kind == .eof) break;
            if (self.peek().kind == .comment) { self.advance(); continue; }

            if (self.peek().kind == .identifier) {
                const key_tok = self.peek();
                self.advance();
                if (self.peek().kind == .colon) {
                    self.advance();
                    // Value: identifier, string, or color (#xxx)
                    if (self.peek().kind == .identifier or self.peek().kind == .string) {
                        const val_tok = self.peek();
                        self.advance();
                        try props.append(.{ .key = key_tok.text, .value = val_tok.text, .loc = key_tok.loc });
                    }
                }
            }

            // Skip semicolons between properties
            if (self.peek().kind == .semicolon) self.advance();
        }

        if (self.peek().kind == .rbrace) {
            self.advance();
        } else {
            try self.err_list.add(loc, .expected_closing_brace, "unterminated property block");
        }

        return .{
            .properties = try props.toOwnedSlice(),
            .loc = loc,
        };
    }

    fn parseCardFields(self: *Parser) ![]const []const u8 {
        std.debug.assert(self.peek().kind == .lbracket);
        self.advance();

        var fields = std.ArrayList([]const u8).init(self.allocator);

        // Parse pipe-separated fields: [field1 | field2 | field3]
        while (self.peek().kind != .rbracket and self.peek().kind != .eof) {
            // Collect text until pipe or rbracket
            var field_parts = std.ArrayList(u8).init(self.allocator);
            while (self.peek().kind != .pipe and self.peek().kind != .rbracket and self.peek().kind != .eof) {
                // Accumulate token text as the field content
                const tok = self.peek();
                if (field_parts.items.len > 0) {
                    try field_parts.append(' ');
                }
                try field_parts.appendSlice(tok.text);
                self.advance();
            }
            if (field_parts.items.len > 0) {
                try fields.append(try field_parts.toOwnedSlice());
            } else {
                field_parts.deinit();
            }

            if (self.peek().kind == .pipe) self.advance();
        }

        if (self.peek().kind == .rbracket) {
            self.advance();
        } else {
            try self.err_list.add(self.peek().loc, .expected_closing_bracket, "unterminated card fields");
        }

        return try fields.toOwnedSlice();
    }

    fn parseDirective(self: *Parser) !ast.Directive {
        const tok = self.peek();
        const loc = tok.loc;
        self.advance();

        const kind: ast.DirectiveKind = if (std.mem.eql(u8, tok.text, "@layout"))
            .layout
        else if (std.mem.eql(u8, tok.text, "@theme"))
            .theme
        else if (std.mem.eql(u8, tok.text, "@direction"))
            .direction
        else if (std.mem.eql(u8, tok.text, "@spacing"))
            .spacing
        else {
            try self.err_list.add(loc, .unknown_directive, "unknown directive");
            return error.ParseError;
        };

        if (self.peek().kind != .identifier) {
            try self.err_list.add(self.peek().loc, .expected_identifier, "expected directive value");
            return error.ParseError;
        }
        const value = self.peek().text;
        self.advance();

        return .{ .kind = kind, .value = value, .loc = loc };
    }

    fn parseStyleRule(self: *Parser) !ast.StyleRule {
        const loc = self.peek().loc;
        self.advance(); // consume @style

        // Selector: "node", "edge", or .classname
        var selector: ast.StyleSelector = undefined;
        if (self.peek().kind == .identifier) {
            const sel_text = self.peek().text;
            if (std.mem.eql(u8, sel_text, "node")) {
                selector = .{ .element = .node };
            } else if (std.mem.eql(u8, sel_text, "edge")) {
                selector = .{ .element = .edge };
            } else {
                try self.err_list.add(self.peek().loc, .unexpected_token, "expected 'node', 'edge', or .class");
                return error.ParseError;
            }
            self.advance();
        } else if (self.peek().kind == .class) {
            selector = .{ .class = self.peek().text };
            self.advance();
        } else {
            try self.err_list.add(self.peek().loc, .unexpected_token, "expected style selector");
            return error.ParseError;
        }

        const properties = try self.parsePropertyBlock();

        return .{ .selector = selector, .properties = properties, .loc = loc };
    }

    fn parseNamedBlock(self: *Parser) !ast.NamedBlock {
        const loc = self.peek().loc;
        const name = self.peek().text;
        self.advance(); // consume name

        // Optional layout type: [dag], [tree], [force]
        var layout_type: ?ast.Layout = null;
        if (self.peek().kind == .lbracket) {
            self.advance();
            if (self.peek().kind == .identifier) {
                const lt = self.peek().text;
                if (std.mem.eql(u8, lt, "dag")) {
                    layout_type = .dag;
                } else if (std.mem.eql(u8, lt, "tree")) {
                    layout_type = .tree;
                } else if (std.mem.eql(u8, lt, "force")) {
                    layout_type = .force;
                } else {
                    try self.err_list.add(self.peek().loc, .unknown_layout_type, "unknown layout type");
                }
                self.advance();
            }
            if (self.peek().kind == .rbracket) self.advance();
        }

        // Opening brace
        if (self.peek().kind != .lbrace) {
            try self.err_list.add(self.peek().loc, .expected_closing_brace, "expected '{' after block name");
            return error.ParseError;
        }
        self.advance();

        var block_directives = std.ArrayList(ast.Directive).init(self.allocator);
        var block_styles = std.ArrayList(ast.StyleRule).init(self.allocator);
        var block_stmts = std.ArrayList(ast.Statement).init(self.allocator);

        while (self.peek().kind != .rbrace and self.peek().kind != .eof) {
            self.skipNewlines();
            if (self.peek().kind == .rbrace or self.peek().kind == .eof) break;
            if (self.peek().kind == .comment) { self.advance(); continue; }

            if (self.peek().kind == .at_keyword) {
                const tok = self.peek();
                if (std.mem.eql(u8, tok.text, "@style")) {
                    try block_styles.append(try self.parseStyleRule());
                } else {
                    try block_directives.append(try self.parseDirective());
                }
                continue;
            }

            if (self.peek().kind == .identifier) {
                try block_stmts.append(try self.parseStatement());
                continue;
            }

            try self.err_list.add(self.peek().loc, .unexpected_token, "unexpected token in block");
            self.advance();
        }

        if (self.peek().kind == .rbrace) {
            self.advance();
        } else {
            try self.err_list.add(loc, .expected_closing_brace, "unterminated named block");
        }

        return .{
            .name = name,
            .layout = layout_type,
            .directives = try block_directives.toOwnedSlice(),
            .styles = try block_styles.toOwnedSlice(),
            .statements = try block_stmts.toOwnedSlice(),
            .loc = loc,
        };
    }

    // --- Helpers ---

    fn peek(self: *const Parser) Token {
        return self.peekAt(self.pos);
    }

    fn peekAt(self: *const Parser, idx: usize) Token {
        if (idx >= self.tokens.len) return self.tokens[self.tokens.len - 1]; // eof
        return self.tokens[idx];
    }

    fn advance(self: *Parser) void {
        if (self.pos < self.tokens.len) self.pos += 1;
    }

    fn skipNewlines(self: *Parser) void {
        while (self.peek().kind == .newline) : (self.pos += 1) {}
    }

    fn isEdgeOp(kind: TokenKind) bool {
        return edgeOpFromToken(kind) != null;
    }

    fn edgeOpFromToken(kind: TokenKind) ?ast.EdgeOp {
        return switch (kind) {
            .arrow => .directed,
            .arrow_reverse => .reverse,
            .dash_dash => .undirected,
            .arrow_bidi => .bidirectional,
            .fat_arrow => .bold,
            .fat_arrow2 => .bold_double,
            .dashed_arrow => .dashed_directed,
            .dotted_arrow => .dotted_directed,
            .dotted_line => .dotted_undirected,
            else => null,
        };
    }

    fn isNamedBlock(self: *const Parser) bool {
        // identifier [layout] { ... } — named block pattern
        var i = self.pos + 1;
        // Skip optional [layout]
        if (i < self.tokens.len and self.tokens[i].kind == .lbracket) {
            i += 1; // skip [
            while (i < self.tokens.len and self.tokens[i].kind != .rbracket) : (i += 1) {}
            i += 1; // skip ]
        }
        // Must be followed by { (without colon before it)
        return i < self.tokens.len and self.tokens[i].kind == .lbrace;
    }

    fn isSubgraphBrace(self: *const Parser) bool {
        // Look inside { ... } to see if it contains edges/statements (subgraph)
        // or only key: value pairs (property block)
        var depth: usize = 1;
        var i = self.pos + 1; // past the {
        while (i < self.tokens.len and depth > 0) : (i += 1) {
            const k = self.tokens[i].kind;
            if (k == .lbrace) { depth += 1; continue; }
            if (k == .rbrace) { depth -= 1; continue; }
            if (k == .newline or k == .comment) continue;
            // If we see an edge operator, it's a subgraph
            if (isEdgeOp(k)) return true;
            // If we see a pipe (card line), it's a property/card block
            if (k == .pipe) return false;
        }
        return false;
    }

    // Public error type
    pub const ParseError = error{ParseError} || std.mem.Allocator.Error;
};

// --- Tests ---

fn testParse(source: []const u8) !struct { doc: ast.Document, err_list: errors.ErrorList } {
    var err_list = errors.ErrorList.init(std.testing.allocator);
    const tokens = try tokenizer.tokenize(std.testing.allocator, source, &err_list);
    // Note: tokens lifetime must outlive parsing since AST borrows from source
    var parser = Parser.init(std.testing.allocator, tokens, &err_list);
    const doc = try parser.parse();
    std.testing.allocator.free(tokens);
    return .{ .doc = doc, .err_list = err_list };
}

test "parse simple edge" {
    var result = try testParse("A -> B");
    defer result.err_list.deinit();

    try std.testing.expect(!result.err_list.hasErrors());
    try std.testing.expectEqual(@as(usize, 1), result.doc.statements.len);

    const edge = result.doc.statements[0].edge;
    try std.testing.expectEqual(@as(usize, 2), edge.chain.len);
    try std.testing.expectEqualStrings("A", edge.chain[0].id);
    try std.testing.expectEqualStrings("B", edge.chain[1].id);
    try std.testing.expectEqual(ast.EdgeOp.directed, edge.operator);
}

test "parse chained edge" {
    var result = try testParse("A -> B -> C -> D");
    defer result.err_list.deinit();

    try std.testing.expect(!result.err_list.hasErrors());
    try std.testing.expectEqual(@as(usize, 1), result.doc.statements.len);

    const edge = result.doc.statements[0].edge;
    try std.testing.expectEqual(@as(usize, 4), edge.chain.len);
    try std.testing.expectEqualStrings("D", edge.chain[3].id);
}

test "parse edge with label" {
    var result = try testParse("A -> B: \"transforms\"");
    defer result.err_list.deinit();

    try std.testing.expect(!result.err_list.hasErrors());
    const edge = result.doc.statements[0].edge;
    try std.testing.expectEqualStrings("transforms", edge.label.?);
}

test "parse node declaration with label" {
    var result = try testParse("db: \"PostgreSQL 15\"");
    defer result.err_list.deinit();

    try std.testing.expect(!result.err_list.hasErrors());
    try std.testing.expectEqual(@as(usize, 1), result.doc.statements.len);
    const decl = result.doc.statements[0].node_decl;
    try std.testing.expectEqualStrings("db", decl.ref.id);
    try std.testing.expectEqualStrings("PostgreSQL 15", decl.ref.label.?);
}

test "parse directive" {
    var result = try testParse("@layout sugiyama");
    defer result.err_list.deinit();

    try std.testing.expect(!result.err_list.hasErrors());
    try std.testing.expectEqual(@as(usize, 1), result.doc.directives.len);
    try std.testing.expectEqual(ast.DirectiveKind.layout, result.doc.directives[0].kind);
    try std.testing.expectEqualStrings("sugiyama", result.doc.directives[0].value);
}

test "parse style rule" {
    var result = try testParse("@style .database { shape: cylinder }");
    defer result.err_list.deinit();

    try std.testing.expect(!result.err_list.hasErrors());
    try std.testing.expectEqual(@as(usize, 1), result.doc.styles.len);
    const rule = result.doc.styles[0];
    try std.testing.expectEqualStrings("database", rule.selector.class);
    try std.testing.expectEqual(@as(usize, 1), rule.properties.properties.len);
    try std.testing.expectEqualStrings("shape", rule.properties.properties[0].key);
    try std.testing.expectEqualStrings("cylinder", rule.properties.properties[0].value);
}

test "parse named block" {
    var result = try testParse("pipeline [dag] {\n  A -> B\n}");
    defer result.err_list.deinit();

    try std.testing.expect(!result.err_list.hasErrors());
    try std.testing.expectEqual(@as(usize, 1), result.doc.blocks.len);
    const block = result.doc.blocks[0];
    try std.testing.expectEqualStrings("pipeline", block.name);
    try std.testing.expectEqual(ast.Layout.dag, block.layout.?);
    try std.testing.expectEqual(@as(usize, 1), block.statements.len);
}

test "parse subgraph" {
    var result = try testParse("backend: {\n  API -> DB\n}");
    defer result.err_list.deinit();

    try std.testing.expect(!result.err_list.hasErrors());
    try std.testing.expectEqual(@as(usize, 1), result.doc.statements.len);
    const sg = result.doc.statements[0].subgraph;
    try std.testing.expectEqualStrings("backend", sg.name);
    try std.testing.expectEqual(@as(usize, 1), sg.statements.len);
}

test "parse card fields" {
    var result = try testParse("svc: [Auth Service | Port: 8080 | Status: healthy]");
    defer result.err_list.deinit();

    try std.testing.expect(!result.err_list.hasErrors());
    const decl = result.doc.statements[0].node_decl;
    try std.testing.expectEqualStrings("svc", decl.ref.id);
    try std.testing.expect(decl.ref.card_fields != null);
    try std.testing.expectEqual(@as(usize, 3), decl.ref.card_fields.?.len);
}

test "parse full example" {
    const source =
        \\@layout sugiyama
        \\@theme dark
        \\
        \\@style .db { shape: cylinder }
        \\
        \\Client -> API: "HTTPS"
        \\API -> Auth
        \\
        \\backend: {
        \\  API -> DB
        \\  DB: "PostgreSQL" .db
        \\}
        \\
        \\modules [tree] {
        \\  app -> handlers
        \\  app -> models
        \\}
    ;
    var result = try testParse(source);
    defer result.err_list.deinit();

    try std.testing.expect(!result.err_list.hasErrors());
    try std.testing.expectEqual(@as(usize, 2), result.doc.directives.len);
    try std.testing.expectEqual(@as(usize, 1), result.doc.styles.len);
    try std.testing.expectEqual(@as(usize, 3), result.doc.statements.len); // 2 edges + 1 subgraph
    try std.testing.expectEqual(@as(usize, 1), result.doc.blocks.len);
}
```

- [ ] **Step 2: Run parser tests**

Run: `cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl && zig test src/dsl/parser.zig`

Expected: All 9 tests PASS

- [ ] **Step 3: Commit**

```bash
cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl
git add src/dsl/parser.zig
git commit -m "feat(dsl): add parser for edges, nodes, subgraphs, directives, blocks"
```

---

### Task 4: Resolver

**Files:**
- Create: `src/dsl/resolver.zig`

The Resolver processes the raw AST into resolved blocks. It handles: style cascade, implicit node creation, directive inheritance, and validation.

- [ ] **Step 1: Create resolver with tests**

Create `src/dsl/resolver.zig`:

```zig
const std = @import("std");
const ast = @import("ast.zig");
const errors = @import("errors.zig");
const Loc = errors.Loc;

pub const ResolvedProperty = struct {
    key: []const u8,
    value: []const u8,
};

pub const ResolvedNode = struct {
    id: []const u8,
    label: []const u8,
    shape: ast.Shape,
    card_fields: ?[]const []const u8,
    properties: []ResolvedProperty,
    loc: Loc,
};

pub const ResolvedEdge = struct {
    from: []const u8,
    to: []const u8,
    op: ast.EdgeOp,
    label: ?[]const u8,
    properties: []ResolvedProperty,
    loc: Loc,
};

pub const ResolvedSubgraph = struct {
    name: []const u8,
    label: ?[]const u8,
    node_ids: []const []const u8,
    properties: []ResolvedProperty,
    children: []ResolvedSubgraph,
};

pub const ResolvedConfig = struct {
    layout: ast.Layout,
    direction: []const u8,
    spacing: []const u8,
    theme: []const u8,
};

pub const ResolvedBlock = struct {
    name: []const u8,
    config: ResolvedConfig,
    nodes: []ResolvedNode,
    edges: []ResolvedEdge,
    subgraphs: []ResolvedSubgraph,
};

pub const ResolveResult = struct {
    blocks: []ResolvedBlock,
};

const StyleMap = std.StringHashMap([]const ast.Property);

pub fn resolve(
    allocator: std.mem.Allocator,
    doc: ast.Document,
    err_list: *errors.ErrorList,
) !ResolveResult {
    // Build global style maps
    var node_defaults = std.StringHashMap([]const u8).init(allocator);
    defer node_defaults.deinit();
    var edge_defaults = std.StringHashMap([]const u8).init(allocator);
    defer edge_defaults.deinit();
    var class_styles = std.StringHashMap([]const ast.Property).init(allocator);
    defer class_styles.deinit();

    for (doc.styles) |rule| {
        switch (rule.selector) {
            .element => |elem| {
                const map = if (elem == .node) &node_defaults else &edge_defaults;
                for (rule.properties.properties) |prop| {
                    try map.put(prop.key, prop.value);
                }
            },
            .class => |class_name| {
                try class_styles.put(class_name, rule.properties.properties);
            },
        }
    }

    // Resolve global config from directives
    var global_config = ResolvedConfig{
        .layout = .dag,
        .direction = "top-down",
        .spacing = "normal",
        .theme = "default",
    };
    for (doc.directives) |dir| {
        switch (dir.kind) {
            .layout => {
                if (std.mem.eql(u8, dir.value, "sugiyama") or std.mem.eql(u8, dir.value, "dag")) {
                    global_config.layout = .dag;
                } else if (std.mem.eql(u8, dir.value, "force")) {
                    global_config.layout = .force;
                } else if (std.mem.eql(u8, dir.value, "tree")) {
                    global_config.layout = .tree;
                } else {
                    try err_list.add(dir.loc, .unknown_layout_type, "unknown layout type");
                }
            },
            .direction => global_config.direction = dir.value,
            .spacing => global_config.spacing = dir.value,
            .theme => global_config.theme = dir.value,
        }
    }

    var blocks = std.ArrayList(ResolvedBlock).init(allocator);

    // Resolve bare statements as the default block
    if (doc.statements.len > 0) {
        try blocks.append(try resolveBlock(
            allocator,
            "__default__",
            global_config,
            doc.statements,
            &node_defaults,
            &edge_defaults,
            &class_styles,
            err_list,
        ));
    }

    // Resolve named blocks
    for (doc.blocks) |block| {
        var block_config = global_config;
        if (block.layout) |lt| {
            block_config.layout = lt;
        }
        for (block.directives) |dir| {
            switch (dir.kind) {
                .layout => {}, // already handled via block.layout
                .direction => block_config.direction = dir.value,
                .spacing => block_config.spacing = dir.value,
                .theme => block_config.theme = dir.value,
            }
        }

        // Merge block-level styles into class map (block styles take priority)
        var block_class_styles = try class_styles.clone();
        defer block_class_styles.deinit();
        for (block.styles) |rule| {
            switch (rule.selector) {
                .class => |class_name| {
                    try block_class_styles.put(class_name, rule.properties.properties);
                },
                .element => |elem| {
                    const map = if (elem == .node) &node_defaults else &edge_defaults;
                    for (rule.properties.properties) |prop| {
                        try map.put(prop.key, prop.value);
                    }
                },
            }
        }

        try blocks.append(try resolveBlock(
            allocator,
            block.name,
            block_config,
            block.statements,
            &node_defaults,
            &edge_defaults,
            &block_class_styles,
            err_list,
        ));
    }

    return .{ .blocks = try blocks.toOwnedSlice() };
}

fn resolveBlock(
    allocator: std.mem.Allocator,
    name: []const u8,
    config: ResolvedConfig,
    statements: []const ast.Statement,
    node_defaults: *std.StringHashMap([]const u8),
    edge_defaults: *std.StringHashMap([]const u8),
    class_styles: *std.StringHashMap([]const ast.Property),
    err_list: *errors.ErrorList,
) !ResolvedBlock {
    _ = edge_defaults;

    var nodes = std.ArrayList(ResolvedNode).init(allocator);
    var edges = std.ArrayList(ResolvedEdge).init(allocator);
    var subgraphs = std.ArrayList(ResolvedSubgraph).init(allocator);
    var seen_nodes = std.StringHashMap(void).init(allocator);
    defer seen_nodes.deinit();

    for (statements) |stmt| {
        switch (stmt) {
            .edge => |edge| {
                // Ensure all nodes in chain exist
                for (edge.chain) |ref| {
                    if (!seen_nodes.contains(ref.id)) {
                        try seen_nodes.put(ref.id, {});
                        try nodes.append(resolveNode(ref, node_defaults, class_styles));
                    }
                }
                // Create edges
                if (edge.fan_out) {
                    // Fan-out: chain[0] is source, chain[1..] are targets
                    const source_id = edge.chain[0].id;
                    for (edge.chain[1..]) |target| {
                        try edges.append(.{
                            .from = source_id,
                            .to = target.id,
                            .op = edge.operator,
                            .label = edge.label,
                            .properties = resolveProperties(allocator, edge.classes, edge.properties, class_styles) catch &.{},
                            .loc = edge.loc,
                        });
                    }
                } else {
                    // Linear chain: A -> B -> C → edges A->B, B->C
                    for (0..edge.chain.len - 1) |idx| {
                        const from = edge.chain[idx].id;
                        const to = edge.chain[idx + 1].id;
                        const label = if (idx == edge.chain.len - 2) edge.label else null;
                        try edges.append(.{
                            .from = from,
                            .to = to,
                            .op = edge.operator,
                            .label = label,
                            .properties = resolveProperties(allocator, edge.classes, edge.properties, class_styles) catch &.{},
                            .loc = edge.loc,
                        });
                    }
                }
            },
            .node_decl => |decl| {
                try seen_nodes.put(decl.ref.id, {});
                try nodes.append(resolveNode(decl.ref, node_defaults, class_styles));
            },
            .subgraph => |sg| {
                var sg_node_ids = std.ArrayList([]const u8).init(allocator);
                var sg_children = std.ArrayList(ResolvedSubgraph).init(allocator);

                for (sg.statements) |sg_stmt| {
                    switch (sg_stmt) {
                        .edge => |edge| {
                            for (edge.chain) |ref| {
                                if (!seen_nodes.contains(ref.id)) {
                                    try seen_nodes.put(ref.id, {});
                                    try nodes.append(resolveNode(ref, node_defaults, class_styles));
                                }
                                try sg_node_ids.append(ref.id);
                            }
                            for (0..edge.chain.len - 1) |idx| {
                                const from = edge.chain[idx].id;
                                const to = edge.chain[idx + 1].id;
                                const label = if (idx == edge.chain.len - 2) edge.label else null;
                                try edges.append(.{
                                    .from = from,
                                    .to = to,
                                    .op = edge.operator,
                                    .label = label,
                                    .properties = &.{},
                                    .loc = edge.loc,
                                });
                            }
                        },
                        .node_decl => |decl| {
                            try seen_nodes.put(decl.ref.id, {});
                            try nodes.append(resolveNode(decl.ref, node_defaults, class_styles));
                            try sg_node_ids.append(decl.ref.id);
                        },
                        .subgraph => |nested_sg| {
                            _ = nested_sg;
                            // Nested subgraphs handled recursively in future
                            try err_list.add(sg.loc, .unexpected_token, "nested subgraphs not yet supported in resolver");
                        },
                    }
                }

                try subgraphs.append(.{
                    .name = sg.name,
                    .label = sg.label,
                    .node_ids = try sg_node_ids.toOwnedSlice(),
                    .properties = &.{},
                    .children = try sg_children.toOwnedSlice(),
                });
            },
        }
    }

    return .{
        .name = name,
        .config = config,
        .nodes = try nodes.toOwnedSlice(),
        .edges = try edges.toOwnedSlice(),
        .subgraphs = try subgraphs.toOwnedSlice(),
    };
}

fn resolveNode(
    ref: ast.NodeRef,
    node_defaults: *std.StringHashMap([]const u8),
    class_styles: *std.StringHashMap([]const ast.Property),
) ResolvedNode {
    var shape: ast.Shape = .rect;

    // Apply default shape from @style node { shape: ... }
    if (node_defaults.get("shape")) |shape_str| {
        shape = parseShape(shape_str);
    }

    // Apply class styles
    for (ref.classes) |class_name| {
        if (class_styles.get(class_name)) |props| {
            for (props) |prop| {
                if (std.mem.eql(u8, prop.key, "shape")) {
                    shape = parseShape(prop.value);
                }
            }
        }
    }

    // Apply inline properties (highest priority)
    if (ref.properties) |pb| {
        for (pb.properties) |prop| {
            if (std.mem.eql(u8, prop.key, "shape")) {
                shape = parseShape(prop.value);
            }
        }
    }

    // Card fields imply card shape
    if (ref.card_fields != null) {
        shape = .card;
    }

    return .{
        .id = ref.id,
        .label = ref.label orelse ref.id,
        .shape = shape,
        .card_fields = ref.card_fields,
        .properties = &.{},
        .loc = ref.loc,
    };
}

fn resolveProperties(
    allocator: std.mem.Allocator,
    classes: []const []const u8,
    inline_props: ?ast.PropertyBlock,
    class_styles: *std.StringHashMap([]const ast.Property),
) ![]ResolvedProperty {
    var result = std.ArrayList(ResolvedProperty).init(allocator);

    // Class properties
    for (classes) |class_name| {
        if (class_styles.get(class_name)) |props| {
            for (props) |prop| {
                try result.append(.{ .key = prop.key, .value = prop.value });
            }
        }
    }

    // Inline properties override
    if (inline_props) |pb| {
        for (pb.properties) |prop| {
            try result.append(.{ .key = prop.key, .value = prop.value });
        }
    }

    return try result.toOwnedSlice();
}

fn parseShape(value: []const u8) ast.Shape {
    if (std.mem.eql(u8, value, "rect")) return .rect;
    if (std.mem.eql(u8, value, "circle")) return .circle;
    if (std.mem.eql(u8, value, "diamond")) return .diamond;
    if (std.mem.eql(u8, value, "cylinder")) return .cylinder;
    if (std.mem.eql(u8, value, "person")) return .person;
    if (std.mem.eql(u8, value, "pill")) return .pill;
    if (std.mem.eql(u8, value, "hexagon")) return .hexagon;
    if (std.mem.eql(u8, value, "parallelogram")) return .parallelogram;
    if (std.mem.eql(u8, value, "queue")) return .queue;
    if (std.mem.eql(u8, value, "cloud")) return .cloud;
    if (std.mem.eql(u8, value, "card")) return .card;
    return .rect;
}

// --- Tests ---

const tokenizer_mod = @import("tokenizer.zig");

fn testResolve(source: []const u8) !struct { result: ResolveResult, err_list: errors.ErrorList } {
    var err_list = errors.ErrorList.init(std.testing.allocator);
    const tokens = try tokenizer_mod.tokenize(std.testing.allocator, source, &err_list);
    defer std.testing.allocator.free(tokens);

    var parser = @import("parser.zig").Parser.init(std.testing.allocator, tokens, &err_list);
    const doc = try parser.parse();

    const result = try resolve(std.testing.allocator, doc, &err_list);
    return .{ .result = result, .err_list = err_list };
}

test "resolve simple edge creates implicit nodes" {
    var r = try testResolve("A -> B -> C");
    defer r.err_list.deinit();

    try std.testing.expect(!r.err_list.hasErrors());
    try std.testing.expectEqual(@as(usize, 1), r.result.blocks.len);

    const block = r.result.blocks[0];
    try std.testing.expectEqual(@as(usize, 3), block.nodes.len);
    try std.testing.expectEqual(@as(usize, 2), block.edges.len);
    try std.testing.expectEqualStrings("A", block.nodes[0].id);
    try std.testing.expectEqualStrings("A", block.nodes[0].label);
}

test "resolve node with label" {
    var r = try testResolve("db: \"PostgreSQL\"");
    defer r.err_list.deinit();

    const block = r.result.blocks[0];
    try std.testing.expectEqual(@as(usize, 1), block.nodes.len);
    try std.testing.expectEqualStrings("db", block.nodes[0].id);
    try std.testing.expectEqualStrings("PostgreSQL", block.nodes[0].label);
}

test "resolve style cascade" {
    var r = try testResolve(
        \\@style .db { shape: cylinder }
        \\db: "PostgreSQL" .db
    );
    defer r.err_list.deinit();

    const block = r.result.blocks[0];
    try std.testing.expectEqual(ast.Shape.cylinder, block.nodes[0].shape);
}

test "resolve named block with layout" {
    var r = try testResolve(
        \\@layout sugiyama
        \\A -> B
        \\modules [force] {
        \\  X -- Y
        \\}
    );
    defer r.err_list.deinit();

    try std.testing.expectEqual(@as(usize, 2), r.result.blocks.len);
    try std.testing.expectEqual(ast.Layout.dag, r.result.blocks[0].config.layout);
    try std.testing.expectEqual(ast.Layout.force, r.result.blocks[1].config.layout);
}

test "resolve subgraph tracks node membership" {
    var r = try testResolve(
        \\backend: {
        \\  API -> DB
        \\}
    );
    defer r.err_list.deinit();

    const block = r.result.blocks[0];
    try std.testing.expectEqual(@as(usize, 1), block.subgraphs.len);
    try std.testing.expectEqualStrings("backend", block.subgraphs[0].name);
    try std.testing.expectEqual(@as(usize, 2), block.subgraphs[0].node_ids.len);
}

test "resolve card fields set card shape" {
    var r = try testResolve("svc: [Auth | Port: 8080]");
    defer r.err_list.deinit();

    const node = r.result.blocks[0].nodes[0];
    try std.testing.expectEqual(ast.Shape.card, node.shape);
    try std.testing.expect(node.card_fields != null);
}
```

- [ ] **Step 2: Run resolver tests**

Run: `cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl && zig test src/dsl/resolver.zig`

Expected: All 6 tests PASS

- [ ] **Step 3: Commit**

```bash
cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl
git add src/dsl/resolver.zig
git commit -m "feat(dsl): add resolver with style cascade, implicit nodes, validation"
```

---

### Task 5: Bridge — Resolved AST to zigraph.Graph

**Files:**
- Create: `src/dsl/bridge.zig`

The Bridge converts each `ResolvedBlock` into a `zigraph.Graph`. It maps string IDs to `usize` IDs, creates nodes/edges/subgraphs via the existing zigraph API, and selects the appropriate layout preset.

- [ ] **Step 1: Create bridge with tests**

Create `src/dsl/bridge.zig`:

```zig
const std = @import("std");
const ast = @import("ast.zig");
const resolver = @import("resolver.zig");
const zigraph = @import("zigraph");

pub const BuiltGraph = struct {
    graph: zigraph.Graph,
    config: zigraph.LayoutConfig,
    id_map: std.StringHashMap(usize),
    allocator: std.mem.Allocator,

    pub fn deinit(self: *BuiltGraph) void {
        self.graph.deinit();
        self.id_map.deinit();
    }
};

pub fn build(allocator: std.mem.Allocator, block: resolver.ResolvedBlock) !BuiltGraph {
    var graph = zigraph.Graph.init(allocator);
    var id_map = std.StringHashMap(usize).init(allocator);
    var next_id: usize = 1;

    // Register all nodes
    for (block.nodes) |node| {
        const node_id = next_id;
        next_id += 1;
        try id_map.put(node.id, node_id);

        if (node.card_fields) |fields| {
            try graph.addNode(node_id, .{
                .label = node.label,
                .lines = fields,
            });
        } else {
            try graph.addNode(node_id, .{
                .label = node.label,
            });
        }
    }

    // Create edges
    for (block.edges) |edge| {
        const from_id = id_map.get(edge.from) orelse continue;
        const to_id = id_map.get(edge.to) orelse continue;

        switch (edge.op) {
            .directed, .bold, .bold_double, .dashed_directed, .dotted_directed => {
                if (edge.label) |label| {
                    try graph.addDiEdgeLabeled(from_id, to_id, label);
                } else {
                    try graph.addDiEdge(from_id, to_id);
                }
            },
            .reverse => {
                if (edge.label) |label| {
                    try graph.addDiEdgeLabeled(to_id, from_id, label);
                } else {
                    try graph.addDiEdge(to_id, from_id);
                }
            },
            .undirected, .dotted_undirected => {
                if (edge.label) |label| {
                    try graph.addUnDiEdgeLabeled(from_id, to_id, label);
                } else {
                    try graph.addUnDiEdge(from_id, to_id);
                }
            },
            .bidirectional => {
                // Two directed edges
                if (edge.label) |label| {
                    try graph.addDiEdgeLabeled(from_id, to_id, label);
                    try graph.addDiEdgeLabeled(to_id, from_id, label);
                } else {
                    try graph.addDiEdge(from_id, to_id);
                    try graph.addDiEdge(to_id, from_id);
                }
            },
        }
    }

    // Create subgraphs
    for (block.subgraphs) |sg| {
        const sg_id = try graph.addSubgraph(sg.label orelse sg.name);
        var node_ids = std.ArrayList(usize).init(allocator);
        defer node_ids.deinit();

        for (sg.node_ids) |str_id| {
            if (id_map.get(str_id)) |nid| {
                try node_ids.append(nid);
            }
        }

        if (node_ids.items.len > 0) {
            try graph.putNodes(node_ids.items).inside(sg_id);
        }
    }

    // Build layout config from resolved config
    const config = buildLayoutConfig(block.config);

    return .{
        .graph = graph,
        .config = config,
        .id_map = id_map,
        .allocator = allocator,
    };
}

fn buildLayoutConfig(config: resolver.ResolvedConfig) zigraph.LayoutConfig {
    var layout_config = switch (config.layout) {
        .dag => zigraph.presets.sugiyama.standard(),
        .force => zigraph.presets.fdg_presets.standard(),
        .tree => zigraph.presets.sugiyama.standard(), // Tree uses sugiyama for now
    };

    // Direction is not yet directly configurable via LayoutConfig,
    // but we can store it for future use. For now, sugiyama is always top-down.
    _ = config.direction;
    _ = config.spacing;

    // Force-directed doesn't use sugiyama settings
    if (config.layout == .force) {
        layout_config = zigraph.presets.fdg_presets.standard();
    }

    return layout_config;
}

// --- Tests ---

const errors_mod = @import("errors.zig");
const tokenizer_mod = @import("tokenizer.zig");
const parser_mod = @import("parser.zig");

fn testBuild(source: []const u8) !struct { built: BuiltGraph, err_list: errors_mod.ErrorList } {
    var err_list = errors_mod.ErrorList.init(std.testing.allocator);
    const tokens = try tokenizer_mod.tokenize(std.testing.allocator, source, &err_list);
    defer std.testing.allocator.free(tokens);

    var parser = parser_mod.Parser.init(std.testing.allocator, tokens, &err_list);
    const doc = try parser.parse();

    const resolved = try resolver.resolve(std.testing.allocator, doc, &err_list);

    if (resolved.blocks.len == 0) {
        return error.NoBlocks;
    }

    const built = try build(std.testing.allocator, resolved.blocks[0]);
    return .{ .built = built, .err_list = err_list };
}

test "bridge: simple edge creates graph" {
    var r = try testBuild("A -> B -> C");
    defer r.err_list.deinit();
    defer r.built.deinit();

    try std.testing.expectEqual(@as(usize, 3), r.built.graph.nodeCount());
    try std.testing.expectEqual(@as(usize, 2), r.built.graph.edgeCount());
}

test "bridge: labeled edge" {
    var r = try testBuild("A -> B: \"depends\"");
    defer r.err_list.deinit();
    defer r.built.deinit();

    try std.testing.expectEqual(@as(usize, 2), r.built.graph.nodeCount());
    try std.testing.expectEqual(@as(usize, 1), r.built.graph.edgeCount());
}

test "bridge: undirected edge" {
    var r = try testBuild("A -- B");
    defer r.err_list.deinit();
    defer r.built.deinit();

    try std.testing.expectEqual(@as(usize, 2), r.built.graph.nodeCount());
    // Undirected edges create 2 directed edges internally in zigraph
    try std.testing.expect(r.built.graph.edgeCount() >= 1);
}

test "bridge: subgraph" {
    var r = try testBuild("backend: {\n  API -> DB\n}");
    defer r.err_list.deinit();
    defer r.built.deinit();

    try std.testing.expectEqual(@as(usize, 2), r.built.graph.nodeCount());
    try std.testing.expect(r.built.graph.hasSubgraphs());
}

test "bridge: card node with fields" {
    var r = try testBuild("svc: [Auth | Port: 8080]");
    defer r.err_list.deinit();
    defer r.built.deinit();

    try std.testing.expectEqual(@as(usize, 1), r.built.graph.nodeCount());
    const node_id = r.built.id_map.get("svc").?;
    const node = r.built.graph.nodeById(node_id).?;
    try std.testing.expect(node.lines.len > 0);
}

test "bridge: force layout config" {
    var err_list = errors_mod.ErrorList.init(std.testing.allocator);
    defer err_list.deinit();
    const tokens = try tokenizer_mod.tokenize(std.testing.allocator, "deps [force] {\n  A -- B\n}", &err_list);
    defer std.testing.allocator.free(tokens);

    var parser = parser_mod.Parser.init(std.testing.allocator, tokens, &err_list);
    const doc = try parser.parse();
    const resolved = try resolver.resolve(std.testing.allocator, doc, &err_list);

    var built = try build(std.testing.allocator, resolved.blocks[0]);
    defer built.deinit();

    // Force layout uses fruchterman_reingold algorithm
    try std.testing.expectEqual(zigraph.Algorithm.fruchterman_reingold, std.meta.activeTag(built.config.algorithm));
}
```

- [ ] **Step 2: Run bridge tests**

Run: `cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl && zig test src/dsl/bridge.zig --mod zigraph::src/root.zig`

Note: The bridge imports `zigraph`, so the test needs the module. If the above doesn't work, we'll need to wire this through `build.zig` first (see Task 7). In that case, skip to Task 7 step 1 to add the DSL test target, then return here.

Expected: All 6 tests PASS

- [ ] **Step 3: Commit**

```bash
cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl
git add src/dsl/bridge.zig
git commit -m "feat(dsl): add bridge converting resolved AST to zigraph.Graph"
```

---

### Task 6: Markdown Extraction

**Files:**
- Create: `src/dsl/markdown.zig`

Extracts ` ```zgraph ``` ` fenced code blocks from markdown files.

- [ ] **Step 1: Create markdown extractor with tests**

Create `src/dsl/markdown.zig`:

```zig
const std = @import("std");

pub const ExtractedBlock = struct {
    content: []const u8,
    line_offset: u32,
};

pub fn extractBlocks(allocator: std.mem.Allocator, markdown: []const u8) ![]ExtractedBlock {
    var blocks = std.ArrayList(ExtractedBlock).init(allocator);
    var line_num: u32 = 1;
    var i: usize = 0;

    while (i < markdown.len) {
        // Find start of line
        const line_start = i;

        // Check for ``` at start of line (after optional whitespace)
        var j = i;
        while (j < markdown.len and (markdown[j] == ' ' or markdown[j] == '\t')) : (j += 1) {}

        if (matchFence(markdown, j, "```zgraph")) {
            // Skip past the opening fence line
            while (j < markdown.len and markdown[j] != '\n') : (j += 1) {}
            if (j < markdown.len) j += 1; // skip \n
            const content_start = j;
            const content_line = line_num + 1;

            // Find closing ```
            while (j < markdown.len) {
                // Check for ``` at start of line
                var k = j;
                while (k < markdown.len and (markdown[k] == ' ' or markdown[k] == '\t')) : (k += 1) {}
                if (k + 3 <= markdown.len and std.mem.eql(u8, markdown[k..][0..3], "```")) {
                    try blocks.append(.{
                        .content = markdown[content_start..j],
                        .line_offset = content_line,
                    });
                    // Skip past closing fence
                    while (k < markdown.len and markdown[k] != '\n') : (k += 1) {}
                    if (k < markdown.len) k += 1;
                    j = k;
                    break;
                }
                // Advance to next line
                while (j < markdown.len and markdown[j] != '\n') : (j += 1) {}
                if (j < markdown.len) {
                    j += 1;
                    line_num += 1;
                }
            }

            i = j;
            line_num += 1;
            continue;
        }

        // Advance to next line
        _ = line_start;
        while (i < markdown.len and markdown[i] != '\n') : (i += 1) {}
        if (i < markdown.len) {
            i += 1;
            line_num += 1;
        }
    }

    return try blocks.toOwnedSlice();
}

fn matchFence(source: []const u8, pos: usize, needle: []const u8) bool {
    if (pos + needle.len > source.len) return false;
    return std.mem.eql(u8, source[pos..][0..needle.len], needle);
}

test "extract single zgraph block" {
    const md =
        \\# Title
        \\
        \\Some text.
        \\
        \\```zgraph
        \\A -> B -> C
        \\```
        \\
        \\More text.
    ;
    const blocks = try extractBlocks(std.testing.allocator, md);
    defer std.testing.allocator.free(blocks);

    try std.testing.expectEqual(@as(usize, 1), blocks.len);
    try std.testing.expectEqualStrings("A -> B -> C\n", blocks[0].content);
}

test "extract multiple zgraph blocks" {
    const md =
        \\```zgraph
        \\A -> B
        \\```
        \\
        \\text
        \\
        \\```zgraph
        \\X -- Y
        \\```
    ;
    const blocks = try extractBlocks(std.testing.allocator, md);
    defer std.testing.allocator.free(blocks);

    try std.testing.expectEqual(@as(usize, 2), blocks.len);
    try std.testing.expectEqualStrings("A -> B\n", blocks[0].content);
    try std.testing.expectEqualStrings("X -- Y\n", blocks[1].content);
}

test "ignore non-zgraph code blocks" {
    const md =
        \\```python
        \\print("hello")
        \\```
        \\
        \\```zgraph
        \\A -> B
        \\```
        \\
        \\```javascript
        \\console.log("hi")
        \\```
    ;
    const blocks = try extractBlocks(std.testing.allocator, md);
    defer std.testing.allocator.free(blocks);

    try std.testing.expectEqual(@as(usize, 1), blocks.len);
}

test "no zgraph blocks returns empty" {
    const md =
        \\# Just markdown
        \\
        \\No code blocks here.
    ;
    const blocks = try extractBlocks(std.testing.allocator, md);
    defer std.testing.allocator.free(blocks);

    try std.testing.expectEqual(@as(usize, 0), blocks.len);
}
```

- [ ] **Step 2: Run markdown tests**

Run: `cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl && zig test src/dsl/markdown.zig`

Expected: All 4 tests PASS

- [ ] **Step 3: Commit**

```bash
cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl
git add src/dsl/markdown.zig
git commit -m "feat(dsl): add markdown zgraph block extraction"
```

---

### Task 7: DSL Module Entry Point and Build System Integration

**Files:**
- Create: `src/dsl/mod.zig`
- Modify: `src/root.zig` — add `pub const dsl = @import("dsl/mod.zig");`
- Modify: `build.zig` — add DSL test target

- [ ] **Step 1: Create `src/dsl/mod.zig`**

```zig
const std = @import("std");
pub const ast = @import("ast.zig");
pub const tokenizer = @import("tokenizer.zig");
pub const parser = @import("parser.zig");
pub const resolver = @import("resolver.zig");
pub const bridge = @import("bridge.zig");
pub const markdown = @import("markdown.zig");
pub const errors = @import("errors.zig");

pub const BuiltGraph = bridge.BuiltGraph;
pub const ResolveResult = resolver.ResolveResult;
pub const DslError = errors.DslError;

pub const ParseResult = struct {
    graphs: []BuiltGraph,
    err_list: errors.ErrorList,

    pub fn deinit(self: *ParseResult) void {
        for (self.graphs) |*g| {
            g.deinit();
        }
        self.err_list.allocator.free(self.graphs);
        self.err_list.deinit();
    }

    pub fn hasErrors(self: *const ParseResult) bool {
        return self.err_list.hasErrors();
    }
};

/// Parse a .zgraph source string and build zigraph.Graph objects for each block.
pub fn parseAndBuild(allocator: std.mem.Allocator, source: []const u8) !ParseResult {
    var err_list = errors.ErrorList.init(allocator);

    // Tokenize
    const tokens = try tokenizer.tokenize(allocator, source, &err_list);
    defer allocator.free(tokens);

    if (err_list.hasErrors()) {
        return .{ .graphs = &.{}, .err_list = err_list };
    }

    // Parse
    var p = parser.Parser.init(allocator, tokens, &err_list);
    const doc = p.parse() catch |err| {
        if (err == error.ParseError) {
            return .{ .graphs = &.{}, .err_list = err_list };
        }
        return err;
    };

    if (err_list.hasErrors()) {
        return .{ .graphs = &.{}, .err_list = err_list };
    }

    // Resolve
    const resolved = try resolver.resolve(allocator, doc, &err_list);

    if (err_list.hasErrors()) {
        return .{ .graphs = &.{}, .err_list = err_list };
    }

    // Build graphs
    var graphs = std.ArrayList(BuiltGraph).init(allocator);
    for (resolved.blocks) |block| {
        try graphs.append(try bridge.build(allocator, block));
    }

    return .{
        .graphs = try graphs.toOwnedSlice(),
        .err_list = err_list,
    };
}

/// Parse a markdown file and build graphs from all ```zgraph blocks.
pub fn parseMarkdown(allocator: std.mem.Allocator, md_source: []const u8) !ParseResult {
    const blocks = try markdown.extractBlocks(allocator, md_source);
    defer allocator.free(blocks);

    var all_graphs = std.ArrayList(BuiltGraph).init(allocator);
    var err_list = errors.ErrorList.init(allocator);

    for (blocks) |block| {
        var block_result = try parseAndBuild(allocator, block.content);
        // Merge errors
        for (block_result.err_list.errors.items) |e| {
            try err_list.add(.{
                .line = e.loc.line + block.line_offset - 1,
                .col = e.loc.col,
                .offset = e.loc.offset,
            }, e.kind, e.message);
        }
        // Transfer graphs
        for (block_result.graphs) |g| {
            try all_graphs.append(g);
        }
        block_result.err_list.deinit();
        allocator.free(block_result.graphs);
    }

    return .{
        .graphs = try all_graphs.toOwnedSlice(),
        .err_list = err_list,
    };
}

test {
    // Pull in all submodule tests
    _ = ast;
    _ = tokenizer;
    _ = parser;
    _ = resolver;
    _ = markdown;
    _ = errors;
}
```

- [ ] **Step 2: Add `dsl` to `src/root.zig`**

Add this line near the other public re-exports in `src/root.zig`:

```zig
pub const dsl = @import("dsl/mod.zig");
```

- [ ] **Step 3: Add DSL test target in `build.zig`**

Add after the existing test section in `build.zig`:

```zig
    // DSL module tests (needs zigraph as dependency)
    const dsl_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/dsl/mod.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigraph", .module = zigraph_mod },
            },
        }),
    });
    const run_dsl_tests = b.addRunArtifact(dsl_tests);
    const dsl_test_step = b.step("test-dsl", "Run DSL unit tests");
    dsl_test_step.dependOn(&run_dsl_tests.step);
    test_step.dependOn(&run_dsl_tests.step); // also run with `zig build test`
```

- [ ] **Step 4: Run all DSL tests through build system**

Run: `cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl && zig build test-dsl`

Expected: All tests from tokenizer, parser, resolver, markdown, and bridge PASS

- [ ] **Step 5: Run full test suite to verify no regressions**

Run: `cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl && zig build test`

Expected: All existing tests + all DSL tests PASS

- [ ] **Step 6: Commit**

```bash
cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl
git add src/dsl/mod.zig src/root.zig build.zig
git commit -m "feat(dsl): add module entry point and build system integration"
```

---

### Task 8: CLI Entry Point

**Files:**
- Create: `src/cli/main.zig`
- Modify: `build.zig` — add CLI executable target

- [ ] **Step 1: Create `src/cli/main.zig`**

```zig
const std = @import("std");
const zigraph = @import("zigraph");

const usage =
    \\Usage: zigraph <command> [options] [file]
    \\
    \\Commands:
    \\  render    Render a .zgraph file or markdown file
    \\  check     Validate .zgraph syntax
    \\
    \\Options:
    \\  -f <format>   Output format: terminal (default), svg, json
    \\  -o <file>     Output file (default: stdout)
    \\  -h, --help    Show this help
    \\
    \\Examples:
    \\  zigraph render diagram.zgraph
    \\  zigraph render diagram.zgraph -f svg -o output.svg
    \\  echo "A -> B" | zigraph render
    \\  zigraph check diagram.zgraph
    \\  zigraph render README.md
    \\
;

const Format = enum { terminal, svg, json };

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try std.io.getStdErr().writeAll(usage);
        std.process.exit(1);
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "-h") or std.mem.eql(u8, command, "--help")) {
        try std.io.getStdOut().writeAll(usage);
        return;
    }

    if (std.mem.eql(u8, command, "render")) {
        try runRender(allocator, args[2..]);
    } else if (std.mem.eql(u8, command, "check")) {
        try runCheck(allocator, args[2..]);
    } else {
        try std.io.getStdErr().writer().print("Unknown command: {s}\n\n", .{command});
        try std.io.getStdErr().writeAll(usage);
        std.process.exit(1);
    }
}

fn runRender(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var format: Format = .terminal;
    var output_path: ?[]const u8 = null;
    var input_path: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-f") and i + 1 < args.len) {
            i += 1;
            const fmt_str = args[i];
            if (std.mem.eql(u8, fmt_str, "terminal")) {
                format = .terminal;
            } else if (std.mem.eql(u8, fmt_str, "svg")) {
                format = .svg;
            } else if (std.mem.eql(u8, fmt_str, "json")) {
                format = .json;
            } else {
                try std.io.getStdErr().writer().print("Unknown format: {s}\n", .{fmt_str});
                std.process.exit(1);
            }
        } else if (std.mem.eql(u8, arg, "-o") and i + 1 < args.len) {
            i += 1;
            output_path = args[i];
        } else {
            input_path = arg;
        }
    }

    // Read input
    const source = if (input_path) |path|
        try std.fs.cwd().readFileAlloc(allocator, path, 10 * 1024 * 1024)
    else
        try std.io.getStdIn().readToEndAlloc(allocator, 10 * 1024 * 1024);
    defer allocator.free(source);

    // Detect markdown by extension
    const is_markdown = if (input_path) |path|
        std.mem.endsWith(u8, path, ".md") or std.mem.endsWith(u8, path, ".markdown")
    else
        false;

    // Parse
    var result = if (is_markdown)
        try zigraph.dsl.parseMarkdown(allocator, source)
    else
        try zigraph.dsl.parseAndBuild(allocator, source);
    defer result.deinit();

    if (result.hasErrors()) {
        const stderr = std.io.getStdErr().writer();
        for (result.err_list.errors.items) |e| {
            try stderr.print("{}\n", .{e});
        }
        std.process.exit(1);
    }

    if (result.graphs.len == 0) {
        try std.io.getStdErr().writeAll("No graphs found in input.\n");
        std.process.exit(1);
    }

    // Get output writer
    var output_file: ?std.fs.File = null;
    defer if (output_file) |f| f.close();

    const writer = if (output_path) |path| blk: {
        output_file = try std.fs.cwd().createFile(path, .{});
        break :blk output_file.?.writer();
    } else std.io.getStdOut().writer();

    // Render each graph
    for (result.graphs) |*built| {
        const ir = try zigraph.layout(&built.graph, allocator, built.config);
        var ir_mut = ir;
        defer ir_mut.deinit();

        switch (format) {
            .terminal => {
                const output = try zigraph.terminal.render(&ir, allocator);
                defer allocator.free(output);
                try writer.writeAll(output);
                try writer.writeAll("\n");
            },
            .svg => {
                const output = try zigraph.svg.render(&ir, allocator, .{});
                defer allocator.free(output);
                try writer.writeAll(output);
            },
            .json => {
                const output = try zigraph.json.serialize(&ir, allocator);
                defer allocator.free(output);
                try writer.writeAll(output);
            },
        }
    }
}

fn runCheck(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        try std.io.getStdErr().writeAll("Usage: zigraph check <file>\n");
        std.process.exit(1);
    }

    const path = args[0];
    const source = try std.fs.cwd().readFileAlloc(allocator, path, 10 * 1024 * 1024);
    defer allocator.free(source);

    const is_markdown = std.mem.endsWith(u8, path, ".md") or std.mem.endsWith(u8, path, ".markdown");

    var result = if (is_markdown)
        try zigraph.dsl.parseMarkdown(allocator, source)
    else
        try zigraph.dsl.parseAndBuild(allocator, source);
    defer result.deinit();

    if (result.hasErrors()) {
        const stderr = std.io.getStdErr().writer();
        for (result.err_list.errors.items) |e| {
            try stderr.print("{s}: {}\n", .{ path, e });
        }
        std.process.exit(1);
    }

    const stdout = std.io.getStdOut().writer();
    try stdout.print("{s}: OK ({d} graph(s))\n", .{ path, result.graphs.len });
}
```

- [ ] **Step 2: Add CLI executable target in `build.zig`**

Add to `build.zig`:

```zig
    // CLI executable
    const cli_exe = b.addExecutable(.{
        .name = "zigraph",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/cli/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigraph", .module = zigraph_mod },
            },
        }),
    });
    b.installArtifact(cli_exe);

    const run_cli = b.addRunArtifact(cli_exe);
    if (b.args) |a| run_cli.addArgs(a);
    const run_cli_step = b.step("run-cli", "Run the zigraph CLI");
    run_cli_step.dependOn(&run_cli.step);
```

- [ ] **Step 3: Build the CLI**

Run: `cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl && zig build`

Expected: Builds successfully, produces `zig-out/bin/zigraph`

- [ ] **Step 4: Test CLI with a sample file**

```bash
cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl
echo 'A -> B -> C' > /tmp/test.zgraph
zig-out/bin/zigraph render /tmp/test.zgraph
```

Expected: Terminal rendering of a simple A → B → C graph

- [ ] **Step 5: Test CLI check command**

```bash
zig-out/bin/zigraph check /tmp/test.zgraph
```

Expected: `/tmp/test.zgraph: OK (1 graph(s))`

- [ ] **Step 6: Test stdin pipe**

```bash
echo "X -> Y -> Z" | zig-out/bin/zigraph render
```

Expected: Terminal rendering of X → Y → Z

- [ ] **Step 7: Commit**

```bash
cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl
git add src/cli/main.zig build.zig
git commit -m "feat(cli): add zigraph render and check commands"
```

---

### Task 9: Integration Test — Full Example

**Files:**
- Create: `examples/dsl_demo.zig`

An integration test that uses the full pipeline: parse `.zgraph` source → resolve → build → layout → render to all three formats.

- [ ] **Step 1: Create integration example**

Create `examples/dsl_demo.zig`:

```zig
const std = @import("std");
const zigraph = @import("zigraph");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source =
        \\@layout sugiyama
        \\
        \\@style .db { shape: cylinder }
        \\
        \\Client -> API: "HTTPS"
        \\API -> Auth: "validate"
        \\Auth -> API: "token"
        \\
        \\backend: {
        \\  API -> Router -> Handler
        \\  Handler -> DB: "query"
        \\  DB: "PostgreSQL" .db
        \\}
    ;

    var result = try zigraph.dsl.parseAndBuild(allocator, source);
    defer result.deinit();

    if (result.hasErrors()) {
        const stderr = std.io.getStdErr().writer();
        for (result.err_list.errors.items) |e| {
            try stderr.print("Error: {}\n", .{e});
        }
        return;
    }

    const stdout = std.io.getStdOut().writer();

    for (result.graphs, 0..) |*built, i| {
        try stdout.print("--- Graph {} ({d} nodes, {d} edges) ---\n", .{ i + 1, built.graph.nodeCount(), built.graph.edgeCount() });

        // Layout
        const ir = try zigraph.layout(&built.graph, allocator, built.config);
        var ir_mut = ir;
        defer ir_mut.deinit();

        // Terminal render
        const terminal_output = try zigraph.terminal.render(&ir, allocator);
        defer allocator.free(terminal_output);
        try stdout.writeAll(terminal_output);
        try stdout.writeAll("\n");

        // JSON render
        const json_output = try zigraph.json.serialize(&ir, allocator);
        defer allocator.free(json_output);
        try stdout.print("JSON output length: {d} bytes\n\n", .{json_output.len});
    }
}
```

- [ ] **Step 2: Add example build target in `build.zig`**

```zig
    // DSL demo example
    const dsl_demo = b.addExecutable(.{
        .name = "dsl_demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/dsl_demo.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigraph", .module = zigraph_mod },
            },
        }),
    });
    b.installArtifact(dsl_demo);

    const run_dsl_demo = b.addRunArtifact(dsl_demo);
    const run_dsl_demo_step = b.step("run-dsl-demo", "Run the DSL demo example");
    run_dsl_demo_step.dependOn(&run_dsl_demo.step);
```

- [ ] **Step 3: Run the integration demo**

Run: `cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl && zig build run-dsl-demo`

Expected: Terminal rendering of the multi-node graph with subgraph, labeled edges, and JSON byte count output.

- [ ] **Step 4: Test with markdown extraction**

Create a test markdown file and render it:

```bash
cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl
cat > /tmp/test-doc.md << 'MDEOF'
# Architecture

```zgraph
Client -> API -> Backend
```

## Modules

```zgraph
@layout sugiyama
app -> models
app -> views
app -> controllers
```
MDEOF
zig-out/bin/zigraph render /tmp/test-doc.md
```

Expected: Two terminal-rendered graphs output sequentially.

- [ ] **Step 5: Run the full test suite**

Run: `cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl && zig build test`

Expected: All tests PASS (existing zigraph tests + all DSL tests)

- [ ] **Step 6: Commit**

```bash
cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl
git add examples/dsl_demo.zig build.zig
git commit -m "feat(dsl): add integration demo and markdown rendering"
```

---

### Task 10: Final Cleanup and Documentation

**Files:**
- Modify: `build.zig` — ensure clean build with no warnings

- [ ] **Step 1: Run full build and tests one final time**

```bash
cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl && zig build test 2>&1
```

Expected: All tests PASS, no warnings

- [ ] **Step 2: Test all CLI commands end-to-end**

```bash
cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl

# Simple render
echo "A -> B -> C" | zig-out/bin/zigraph render

# SVG output
echo "A -> B -> C" | zig-out/bin/zigraph render -f svg > /tmp/test.svg
head -5 /tmp/test.svg

# JSON output
echo "A -> B -> C" | zig-out/bin/zigraph render -f json | head -20

# File render
echo '@layout sugiyama
A -> B -> C -> D
B -> D' > /tmp/complex.zgraph
zig-out/bin/zigraph render /tmp/complex.zgraph

# Check command
zig-out/bin/zigraph check /tmp/complex.zgraph

# Help
zig-out/bin/zigraph --help
```

Expected: All commands produce correct output

- [ ] **Step 3: Commit final state**

```bash
cd /Users/markussagen/code/hobby/zigraph-zgraph-dsl
git add -A
git status
# Only commit if there are changes
git diff --cached --quiet || git commit -m "chore: final cleanup for zgraph DSL phase 1"
```
