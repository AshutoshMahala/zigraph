# Phase 3b: TUI Editor (`zigraph edit`)

## Goal

Build a terminal-based split-pane editor for `.zgraph` files with live graph preview, syntax highlighting, autocomplete, go-to-definition, bidirectional source ↔ graph linking, node dragging/pinning, multiple tabs, undo/redo, and a fuzzy-find command palette.

## Scope

**In scope:**
- Split-pane layout (editor + preview) with configurable orientation (left/right or top/bottom)
- Modeless text editor with syntax highlighting from zigraph tokenizer
- Live graph preview via existing terminal renderer + RenderPlan
- Debounced re-parse/re-render on every edit (100ms)
- Error/warning display: gutter markers, underlines, status bar messages
- Bidirectional source ↔ graph linking with highlight + scroll
- Toggleable context panel (off by default, Ctrl+I to toggle)
- Node selection, mouse drag, arrow key nudge, pin/unpin in preview
- Go-to-definition: @import files, ${var} references, .class styles, node declarations
- Autocomplete: directives, values, variables, classes, properties, node names, file paths
- Multiple tabs/buffers with auto-hiding tab bar
- Operation-based undo/redo with grouping
- Fuzzy-find command palette overlay
- Keybinding help screen
- Save to file

**Out of scope (later phases):**
- Vim/modal editing mode
- Neovim/VS Code preview extensions (Phase 4)
- Collaborative editing
- Git integration
- Plugin/extension system

## Dependencies

- **libvaxis** (https://github.com/rockorager/libvaxis) — terminal handling, event loop, widgets (SplitView, TextField, Window, etc.). The dominant Zig TUI library (1,700+ stars), used by the Flow editor. Provides: raw terminal mode, double-buffered diffing renderer, mouse tracking (SGR), keyboard events (Kitty protocol), resize handling, unicode support, synchronized output.
- **zigraph** (self) — DSL tokenizer/parser/resolver/bridge, terminal renderer, RenderPlan + hit-testing, Buffer2D.

No other external dependencies.

## Architecture

```
┌─ TabBar (auto-hides with 1 file) ────────────────────────────┐
│ file1.zgraph ×  │ file2.zgraph ×  │                           │
├─────────────────┬─────────────────────────────────────────────┤
│                 │                                             │
│  EditorPane     │  PreviewPane                                │
│  - text buffer  │  - terminal-rendered graph                  │
│  - syntax hl    │  - click to select                          │
│  - line numbers │  - drag to move                             │
│  - error gutter │  - arrow keys to nudge                      │
│  - cursor       │  - P to pin/unpin                           │
│  - selection    │  - scroll wheel to pan                      │
│  - autocomplete │                                             │
│                 │                                             │
├─────────────────┴─────────────────────────────────────────────┤
│ Status: Node: db [shape=cylinder] — 3 edges    Ln 12 Col 5 * │
└───────────────────────────────────────────────────────────────┘

CommandPalette (overlay, Ctrl+P):
┌─────────────────────────────┐
│ > save                      │
│   Save file         Ctrl+S  │
│   Save and quit     Ctrl+Q  │
│   Save all                  │
└─────────────────────────────┘
```

## Components

### App (`app.zig`)

Top-level orchestrator. Owns the libvaxis event loop (`Loop`), routes events to the focused pane, manages the buffer collection (open tabs), and handles global keybindings.

Responsibilities:
- Initialize libvaxis Vaxis + Tty + Loop
- Create and manage child widgets (TabBar, SplitView containing EditorPane + PreviewPane, StatusBar)
- Dispatch events: global keybindings first, then focused pane
- Manage focus state (editor vs preview, or overlay active)
- Coordinate parse/render pipeline on text changes (debounced)
- Handle quit with unsaved-changes prompt

### EditorPane (`editor_pane.zig`)

Text editing widget. Renders into a libvaxis Window.

Responsibilities:
- Display text buffer content with syntax highlighting
- Line number gutter with error/warning markers (red/yellow dots)
- Cursor rendering and movement (arrow keys, Home/End, PgUp/PgDn, Ctrl+arrows for word jump)
- Selection (Shift+arrow, Shift+click, Ctrl+A)
- Text insertion/deletion routed through UndoManager
- Scroll viewport to keep cursor visible
- Ctrl+Click: detect token under cursor, invoke Definitions for go-to-definition
- Show autocomplete popup when triggered

### PreviewPane (`preview_pane.zig`)

Graph preview widget. Renders the terminal graph into a libvaxis Window.

Responsibilities:
- Accept a RenderPlan from the parse/render pipeline
- Map RenderPlan's Buffer2D cells → libvaxis Cells for display
- Handle mouse click → `RenderPlan.elementAt(col, row)` → HitResult
- Mouse drag: track drag start node, update position on mouse motion, commit on mouse up
- Arrow key nudge: move selected node by 1 cell in layout coordinates
- Pin/unpin: `P` key toggles pin state on selected node
- Scroll/pan: scroll wheel or Ctrl+arrow when preview is focused
- Highlight nodes/edges that are linked from editor cursor position
- Maintain pinned node positions per-buffer, pass to layout engine as constraints

### SourceMap (`source_map.zig`)

Bidirectional mapping between source code positions and graph elements.

Rebuilt on every successful parse. Stores:
- `node_index → Loc` (AST location of each graph node's definition)
- `edge_index → Loc` (AST location of each edge statement)
- `Loc range → node_index/edge_index` (reverse: which graph element does a source position belong to?)

Used by:
- EditorPane click → find graph element → highlight in PreviewPane
- PreviewPane click → find source location → jump cursor in EditorPane
- Both directions include auto-scrolling the target pane

### Definitions (`definitions.zig`)

Go-to-definition index built during the resolve phase.

Handles Ctrl+Click on:
- `@import "file.zgraph"` → resolve path relative to current file's directory, open in new tab
- `${var}` inside strings → jump to `vars { }` block where `var` is defined
- `.classname` on nodes → jump to `@style .classname { }` rule
- Node identifier in edge chain → jump to its first declaration (where it has properties/label)

Data structure: `HashMap([]const u8, Loc)` mapping names → definition locations. Rebuilt from resolved AST on each parse.

### Completion (`completion.zig`)

Autocomplete popup widget.

Triggered by:
- `Ctrl+Space` (manual trigger anywhere)
- Typing `@` (directive names)
- Typing `${` (variable names)
- Typing `.` in class position (class names)
- Typing inside `[` property context (property keys after `[`/`,`, values after `=`)

Completion sources:
| Context | Completions |
|---|---|
| After `@` | `layout`, `import`, `direction`, `spacing`, `border`, `align`, `style`, `theme` |
| After `@layout ` | `sugiyama`, `dagre`, `force`, `tree`, `table`, `card`, `flow` |
| After `@direction ` | `top-down`, `left-right`, `bottom-up`, `right-left` |
| After `@import "` | `.zgraph` files in same directory (fs scan) |
| After `@border ` | `none`, `light`, `heavy`, `double`, `rounded` |
| After `${` | Variable names from `vars { }` blocks in scope |
| After `.` (class) | Class names from `@style .name { }` rules |
| Property key position | `color`, `shape`, `label`, `style`, `weight` |
| After `shape=` | `rect`, `circle`, `diamond`, `cylinder`, `person`, `pill`, `hexagon`, `parallelogram`, `queue`, `cloud`, `card` |
| Identifier in edge | Existing node names in current block |

UI: popup list below cursor, max 10 items visible, arrow keys to navigate, Tab/Enter to accept, Esc to dismiss, continues filtering as you type.

### UndoManager (`undo.zig`)

Operation-based undo/redo with edit grouping.

Data model:
- `EditOperation`: enum of `insert(pos, text)` and `delete(pos, text)`
- `undo_stack: ArrayList(EditGroup)` — groups of related operations
- `redo_stack: ArrayList(EditGroup)` — cleared on new edit after undo

Grouping rules:
- Consecutive character insertions at adjacent positions → single group
- Group breaks on: cursor jump, deletion after insertion, pause >1 second, explicit boundary (paste, cut, delete-line)
- Each non-character operation (paste, cut, delete line, find-replace) is its own group

### CommandPalette (`command_palette.zig`)

Fuzzy-find overlay centered on screen.

Structure:
- Text input at top (with `>` prefix)
- Filtered results list below (max 12 visible, scrollable)
- Each result shows: command name, description, keybinding (if any)

Fuzzy matching: character-order substring matching with scoring. Characters that match at word boundaries or consecutively score higher. No external fuzzy library needed.

Commands registered:
| Command | Keybinding | Description |
|---|---|---|
| Save | Ctrl+S | Save current file |
| Quit | Ctrl+Q | Quit (prompts if unsaved) |
| Open file | Ctrl+T | Open file picker |
| Close tab | Ctrl+W | Close current tab |
| Toggle orientation | Ctrl+\\ | Switch split direction |
| Toggle context panel | Ctrl+I | Show/hide element details |
| Jump to line | Ctrl+G | Go to line number |
| Find | Ctrl+F | Find / find+replace |
| Show keybindings | Ctrl+H | Show all keybindings |
| Switch buffer | — | List open buffers |
| Change direction | — | Set graph direction |
| Increase split | Ctrl+] | Grow editor pane |
| Decrease split | Ctrl+[ | Shrink editor pane |

### TextBuffer (`text_buffer.zig`)

Piece table implementation for efficient text editing.

A piece table stores the original file content in an immutable "original" buffer and all insertions in an append-only "add" buffer. The document is represented as a sequence of pieces, each pointing to a span in either buffer. This gives:
- O(1) insert/delete (add piece, split existing piece)
- Efficient undo (remove/restore pieces)
- Low memory overhead (original file content not duplicated)

API:
- `init(allocator, content)` — load file
- `insert(pos, text)` — insert text at position
- `delete(pos, len)` — delete range
- `lineAt(line_num)` — get line content (for rendering)
- `lineCount()` — total lines
- `positionToLineCol(pos)` / `lineColToPosition(line, col)` — coordinate conversion
- `slice(start, end)` — extract range (for copy/cut)
- `contents(allocator)` — materialize full text (for save)

### Highlighter (`highlighter.zig`)

Maps zigraph `TokenKind` → libvaxis `Style` for syntax highlighting.

Color mapping (adjusts to terminal color capability detected by libvaxis):
| TokenKind | Color |
|---|---|
| `identifier` | default (white/fg) |
| `string` | green |
| `at_keyword` | magenta/bold |
| `comment` | gray/dim |
| `arrow`, `arrow_reverse`, `dash_dash`, `arrow_bidi`, `fat_arrow`, `fat_arrow2`, `dashed_arrow`, `dotted_arrow`, `dotted_line` | cyan |
| `lbrace`, `rbrace`, `lbracket`, `rbracket` | yellow |
| `colon`, `comma`, `semicolon` | default/dim |
| `pipe` | yellow |
| `class` | blue |

Error/warning overlays (applied on top of syntax highlighting):
- Error: red underline on the token range indicated by `ErrorList` entries with `Loc`
- Warning: yellow underline
- Gutter: red dot `●` for lines with errors, yellow dot `●` for warnings

### StatusBar (`status_bar.zig`)

Bottom information line, always visible.

Layout (1 line by default, expandable to 3-4 when context panel is on):

```
Left:  [error/warning message] or [selected element info]
Right: [modified *] [filetype] Ln {line} Col {col}  [orientation icon]
```

When context panel is toggled on (Ctrl+I), expands below status line:
```
  Node: db
  Properties: shape=cylinder, color=blue
  Edges: → cache, → api, ← frontend
  Classes: .database, .large
```

### TabBar (`tab_bar.zig`)

Top file tab strip.

- Auto-hides when only 1 file is open (maximizes editing space)
- Shows when 2+ files open
- Each tab: filename (not full path), modified indicator (`*`), close button (`×`)
- Active tab visually distinct (bold/underline/inverse)
- Click tab to switch, Ctrl+Tab / Ctrl+Shift+Tab to cycle
- Ctrl+T opens file via command palette, Ctrl+W closes current tab
- Closing last tab quits the application (with unsaved prompt)

### Keybindings (`keybindings.zig`)

Registry of all keybindings with help screen.

Ctrl+H shows a centered overlay listing all bindings grouped by category (File, Navigation, Editing, Layout, Preview, Global). Dismissable with Esc or Ctrl+H again.

## Data Flow

```
User keystroke in editor
  → EditorPane: insert/delete via TextBuffer (through UndoManager)
  → Highlighter: re-tokenize immediately (for syntax highlighting)
  → App: reset debounce timer (100ms)
  → On debounce fire:
      → Tokenizer → Parser → parse result
      → If parse success:
          → Resolver → resolved AST
          → Bridge → Graph (with pinned positions as constraints)
          → Layout engine → LayoutIR
          → RenderPlan from LayoutIR
          → SourceMap rebuilt from AST Loc ↔ Graph indices
          → Definitions index rebuilt
          → Completion sources updated (vars, classes, nodes)
          → PreviewPane re-renders with new RenderPlan
          → EditorPane clears error markers
      → If parse error:
          → ErrorList → EditorPane gutter markers + underlines
          → StatusBar shows error summary
          → PreviewPane keeps last successful RenderPlan (never blank)
          → SourceMap/Definitions retain last successful state

User clicks in preview
  → PreviewPane: elementAt(col, row) → HitResult
  → If node/edge:
      → SourceMap lookup → Loc
      → EditorPane: move cursor to Loc, scroll to line, highlight
      → StatusBar: show element info
      → If context panel on: show properties/edges

User clicks identifier in editor
  → EditorPane: cursor line/col
  → SourceMap: find AST node at position → graph node index
  → PreviewPane: highlight node, scroll to show it
  → StatusBar: show element info

User Ctrl+Clicks in editor
  → Definitions: lookup token under cursor
  → If @import string → open file in new tab
  → If ${var} → jump to vars block definition
  → If .class → jump to @style rule
  → If node name → jump to first declaration

User drags node in preview
  → Mouse down: elementAt → start drag, record start position
  → Mouse motion: update visual position (immediate, no re-layout)
  → Mouse up: commit position, pin node, re-run layout with constraint
  → Preview re-renders with new layout

Autocomplete trigger
  → Completion: analyze cursor context (token before cursor, parent construct)
  → Build filtered completion list from appropriate source
  → Show popup below cursor
  → Filter as user types, accept on Tab/Enter
  → Insert completion text into TextBuffer (via UndoManager)
```

## Keybindings (Complete)

### File
| Key | Action |
|---|---|
| `Ctrl+S` | Save |
| `Ctrl+Q` | Quit (prompts if unsaved) |
| `Ctrl+T` | Open file (via palette) |
| `Ctrl+W` | Close current tab |

### Navigation
| Key | Action |
|---|---|
| `Ctrl+Tab` | Next tab |
| `Ctrl+Shift+Tab` | Previous tab |
| `Ctrl+G` | Jump to line |
| `Ctrl+F` | Find / find+replace |
| `Tab` | Switch focus: editor ↔ preview |
| `Ctrl+Click` | Go to definition |

### Editing
| Key | Action |
|---|---|
| `Ctrl+Z` | Undo |
| `Ctrl+Y` | Redo |
| `Ctrl+X` | Cut selection |
| `Ctrl+C` | Copy selection |
| `Ctrl+V` | Paste |
| `Ctrl+A` | Select all |
| `Ctrl+D` | Duplicate line |
| `Ctrl+L` | Delete line |
| `Ctrl+Space` | Trigger autocomplete |

### Layout
| Key | Action |
|---|---|
| `Ctrl+\` | Toggle split orientation |
| `Ctrl+]` | Increase editor pane size |
| `Ctrl+[` | Decrease editor pane size |

### Preview (when focused)
| Key | Action |
|---|---|
| Arrow keys | Nudge selected node |
| `P` | Pin/unpin selected node |
| `Esc` | Deselect |
| Click | Select node/edge |
| Drag | Move node |
| Scroll wheel | Pan viewport |

### Global
| Key | Action |
|---|---|
| `Ctrl+P` | Command palette |
| `Ctrl+I` | Toggle context panel |
| `Ctrl+H` | Show keybindings help |

## CLI Integration

New subcommand added to existing CLI:

```
zigraph edit [file...]       Open file(s) in TUI editor
zigraph edit                 Open empty editor (new file)
zigraph edit *.zgraph        Open multiple files as tabs
```

Build target: `zig build run-tui -- <file>` (existing target, updated to use new implementation).

The `edit` subcommand is added to `src/cli/main.zig` which dispatches to `src/tui/main.zig`.

## Testing Strategy

### Unit tests (in-file Zig tests)
- `text_buffer.zig`: insert, delete, line operations, piece table integrity, coordinate conversion
- `undo.zig`: single operations, grouping, undo/redo sequences, redo-clear-on-edit
- `source_map.zig`: build from AST, lookup both directions, handles missing mappings
- `definitions.zig`: resolve imports, vars, classes, nodes
- `completion.zig`: context detection, each completion source, fuzzy matching/scoring
- `highlighter.zig`: token-to-style mapping, error overlay application

### Integration tests
- Parse → render pipeline: edit text → verify preview updates
- Bidirectional linking: click preview node → verify correct editor line
- Go-to-definition: Ctrl+Click on import → verify file opens
- Undo/redo: sequence of edits → undo all → verify original content

### Manual testing
- Visual verification of syntax highlighting colors
- Mouse drag smoothness
- Resize handling (terminal resize, split resize)
- Large file performance (1000+ line zgraph file)
- Unicode content in strings and identifiers

## Performance Considerations

- **Tokenizing**: <1ms for typical files, safe to run on every keystroke
- **Parsing**: ~1-5ms for typical files, debounced to 100ms to avoid thrashing
- **Layout**: most expensive step, but only runs on successful parse (not on every keystroke)
- **Rendering**: libvaxis's diff-based renderer only updates changed cells — fast for incremental updates
- **Piece table**: O(log n) operations with balanced tree, O(1) amortized for sequential inserts
- **Preview on error**: keeps last good render, so parse errors don't cause expensive re-renders
