# Table Renderer Design

## Goal

Add a standalone table renderer to zigraph's terminal output that produces formatted ASCII/Unicode tables with configurable borders, column alignment, and optional headers. Composable into graph layouts via `paintTable` on Buffer2D.

## Architecture

A single self-contained module (`table.zig`) following the `tree.zig` / `card.zig` pattern: no LayoutIR dependency, operates on plain data or paints directly to a Buffer2D.

## API

### Types

```zig
pub const Alignment = enum { left, center, right };

pub const Border = enum { none, single, heavy, double };

pub const TableConfig = struct {
    border: Border = .single,
    char_set: CharSet = .unicode,       // .unicode or .ascii
    header_attrs: TextAttrs = .{ .bold = true },
    alignment: ?[]const Alignment = null, // per-column override; null = all left
};
```

### Functions

```zig
/// Render table to an allocated string.
pub fn render(
    headers: ?[]const []const u8,
    rows: []const []const []const u8,
    allocator: Allocator,
    config: TableConfig,
) ![]u8

/// Render table to any writer (no intermediate allocation).
pub fn renderStreaming(
    headers: ?[]const []const u8,
    rows: []const []const []const u8,
    writer: anytype,
    config: TableConfig,
) !void

/// Paint table into a Buffer2D at (x, y) for graph integration.
pub fn paintTable(
    buffer: *Buffer2D,
    x: usize,
    y: usize,
    headers: ?[]const []const u8,
    rows: []const []const []const u8,
    config: TableConfig,
) void

/// Compute rendered table width in columns.
pub fn tableWidth(
    headers: ?[]const []const u8,
    rows: []const []const []const u8,
    config: TableConfig,
) usize

/// Compute rendered table height in rows.
pub fn tableHeight(
    headers: ?[]const []const u8,
    rows: []const []const []const u8,
) usize
```

## Rendering Logic

1. **Column widths**: Scan headers (if present) and all rows to find max display width per column.
2. **Cell padding**: Apply per-column alignment (left/center/right). Default is left. Pad with spaces to column width.
3. **Border characters**: Look up from a border character set based on `Border` style:
   - `.single`: `┌─┬─┐ │ ├─┼─┤ └─┴─┘`
   - `.heavy`: `┏━┳━┓ ┃ ┣━╋━┫ ┗━┻━┛`
   - `.double`: `╔═╦═╗ ║ ╠═╬═╣ ╚═╩═╝`
   - `.none`: spaces only, columns separated by 2+ spaces
   - ASCII fallback (`char_set = .ascii`): `+-| ` regardless of border style
4. **Row structure** (with headers):
   - Top border row
   - Header row (bold via `header_attrs`)
   - Header separator row
   - For each data row: data row + separator row (except last)
   - Bottom border row
5. **Row structure** (without headers):
   - Top border row
   - For each data row: data row + separator row (except last)
   - Bottom border row
6. **Borderless** (`.none`): No border rows. Column values separated by padding. No separators.

## Border Character Sets

Each border style maps to 11 characters:

| Position         | single | heavy | double |
|------------------|--------|-------|--------|
| top-left         | `┌`    | `┏`   | `╔`    |
| top-right        | `┐`    | `┓`   | `╗`    |
| bottom-left      | `└`    | `┗`   | `╚`    |
| bottom-right     | `┘`    | `┛`   | `╝`    |
| horizontal       | `─`    | `━`   | `═`    |
| vertical         | `│`    | `┃`   | `║`    |
| top-tee          | `┬`    | `┳`   | `╦`    |
| bottom-tee       | `┴`    | `┻`   | `╩`    |
| left-tee         | `├`    | `┣`   | `╠`    |
| right-tee        | `┤`    | `┫`   | `╣`    |
| cross            | `┼`    | `╋`   | `╬`    |

## Graph Integration

`paintTable` writes directly to a `Buffer2D` at given coordinates, same as `card.paintCard`. This lets tables be used as node content in graph layouts. Edges between tables use the existing graph edge system — the table is just a visual body painted at the node's position.

Dimension helpers (`tableWidth`, `tableHeight`) let the layout engine allocate the right amount of space.

## Files

- **Create**: `src/render/terminal/table.zig` — all table logic
- **Create**: `src/render/terminal/table_tests.zig` — unit tests
- **Modify**: `src/render/terminal/mod.zig` — add `pub const table = @import("table.zig");`
- **Create**: `examples/terminal/table_demo.zig` — example showing all border styles and alignments
- **Modify**: `build.zig` — register example

## Testing

- Headerless table renders correctly
- Table with headers renders header row + separator
- Per-column alignment (left, center, right)
- All border styles (single, heavy, double, none)
- ASCII fallback
- Empty rows / single column / single row edge cases
- `tableWidth` and `tableHeight` return correct dimensions
- `paintTable` writes to Buffer2D at correct coordinates
