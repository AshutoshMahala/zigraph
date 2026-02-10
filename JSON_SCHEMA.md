# JSON IR Schema

Version: **1.1**

The JSON IR (Intermediate Representation) is zigraph's output format for external tool integration. Use it to build SVG renderers, web visualizations, React/Vue components, or any custom output.

## Quick Example

```json
{
  "version": "1.1",
  "width": 25,
  "height": 10,
  "level_count": 3,
  "nodes": [
    {"id": 1, "label": "Start", "x": 5, "y": 0, "width": 7, "center_x": 8, "level": 0, "level_position": 0, "kind": "explicit", "edge_index": null},
    {"id": 2, "label": "Process", "x": 3, "y": 3, "width": 9, "center_x": 7, "level": 1, "level_position": 0, "kind": "explicit", "edge_index": null},
    {"id": 3, "label": "End", "x": 7, "y": 6, "width": 5, "center_x": 9, "level": 2, "level_position": 0, "kind": "explicit", "edge_index": null}
  ],
  "edges": [
    {"from": 1, "to": 2, "from_x": 8, "from_y": 1, "to_x": 7, "to_y": 3, "path": {"type": "direct"}, "edge_index": 0, "directed": true},
    {"from": 2, "to": 3, "from_x": 7, "from_y": 4, "to_x": 9, "to_y": 6, "path": {"type": "direct"}, "edge_index": 1, "directed": true}
  ]
}
```

---

## Root Object

| Field | Type | Description |
|-------|------|-------------|
| `version` | string | Schema version (currently `"1.1"`) |
| `width` | integer | Total width of layout in character cells |
| `height` | integer | Total height of layout in character cells |
| `level_count` | integer | Number of horizontal levels (layers) |
| `nodes` | array | Array of node objects |
| `edges` | array | Array of edge objects |

---

## Node Object

Each node represents a positioned vertex in the layout.

| Field | Type | Description |
|-------|------|-------------|
| `id` | integer | Unique node identifier (from input graph) |
| `label` | string | Node label text |
| `x` | integer | Left edge x-coordinate (0-indexed) |
| `y` | integer | Top edge y-coordinate (0-indexed) |
| `width` | integer | Width of node box (includes brackets: `[label]`) |
| `center_x` | integer | Center x-coordinate (for edge connections) |
| `level` | integer | Hierarchical level (0 = top) |
| `level_position` | integer | Position within level (0 = leftmost) |
| `kind` | string | `explicit`, `implicit`, or `dummy` |
| `edge_index` | integer&#124;null | For dummy nodes: which edge they belong to |

### Coordinate System

```
(0,0) ────────────────────────▶ x
  │
  │    [Node A]       ← y=0, node box
  │       │
  │       ↓
  │    [Node B]       ← y=3 (after spacing)
  │
  ▼
  y
```

- Origin `(0,0)` is top-left
- `x` increases rightward
- `y` increases downward
- Node `y` is the row containing the node text
- Edge endpoints use `center_x` for horizontal alignment

### Node Box Structure

```
[Label]
 ↑   ↑
 │   └── x + width - 1
 └────── x

center_x = x + (width / 2)
```

For a node at `x=5` with `width=7`:
- Left bracket at column 5
- Right bracket at column 11
- Center at column 8

---

## Edge Object

Each edge represents a connection between two nodes.

| Field | Type | Description |
|-------|------|-------------|
| `from` | integer | Source node ID |
| `to` | integer | Target node ID |
| `from_x` | integer | Start x-coordinate (source node center) |
| `from_y` | integer | Start y-coordinate (row below source) |
| `to_x` | integer | End x-coordinate (target node center) |
| `to_y` | integer | End y-coordinate (row of target) |
| `path` | object | Path routing information |
| `edge_index` | integer | Edge index for consistent coloring |
| `directed` | boolean | Whether an arrow is drawn at the target |
| `label` | string (optional) | Edge label text |
| `label_x` | integer (optional) | Label x-position (grid coords) |
| `label_y` | integer (optional) | Label y-position (grid coords) |

### Edge Direction

Edges always flow **downward** (from lower level to higher level number):
- `from_y` < `to_y` always
- `from` node is in an earlier level than `to` node

---

## Path Types

The `path` object describes how to route the edge between endpoints.

### Direct Path

Straight vertical or single-bend connection.

```json
{"type": "direct"}
```

**Rendering:**
- If `from_x == to_x`: vertical line with `│` and `↓`
- If different: vertical from source, then arrow to target

```
   [A]
    │
    ↓
   [B]
```

### Corner Path

Two-segment path with horizontal routing at a specific y-level.

```json
{"type": "corner", "horizontal_y": 2}
```

| Field | Type | Description |
|-------|------|-------------|
| `horizontal_y` | integer | Y-coordinate of horizontal segment |

**Rendering:**
```
   [A]
    │
    └───┐     ← horizontal_y
        ↓
       [B]
```

### Side Channel Path

Edges that route around other nodes via a vertical channel.

```json
{"type": "side_channel", "channel_x": 0, "start_y": 1, "end_y": 5}
```

| Field | Type | Description |
|-------|------|-------------|
| `channel_x` | integer | X-coordinate of vertical channel |
| `start_y` | integer | Y where edge enters channel |
| `end_y` | integer | Y where edge exits channel |

**Rendering:**
```
     [A]
 ┌────┘         ← enter at start_y
 │
 │   [B]        ← skip over intermediate nodes
 │
 └────┐         ← exit at end_y
     [C]
```

### Multi-Segment Path

Complex paths with multiple waypoints (for edge crossing avoidance).

```json
{
  "type": "multi_segment",
  "waypoints": [[5, 2], [5, 4], [10, 4], [10, 6]]
}
```

| Field | Type | Description |
|-------|------|-------------|
| `waypoints` | array | Array of `[x, y]` coordinate pairs |

**Rendering:** Connect waypoints in order with line segments.

### Spline Path

Cubic Bezier curve definition for smooth edges.

```json
{
  "type": "spline",
  "cp1_x": 10, "cp1_y": 5,
  "cp2_x": 15, "cp2_y": 8
}
```

| Field | Type | Description |
|-------|------|-------------|
| `cp1_x`, `cp1_y` | integer | First control point coordinates (based on `from` point) |
| `cp2_x`, `cp2_y` | integer | Second control point coordinates (based on `to` point) |

**Rendering:** Draw a cubic bezier curve using `from` point, `cp1`, `cp2`, and `to` point.

---

## Usage Examples

### JavaScript/TypeScript

```typescript
interface ZigraphLayout {
  version: string;
  width: number;
  height: number;
  level_count: number;
  nodes: ZigraphNode[];
  edges: ZigraphEdge[];
}

interface ZigraphNode {
  id: number;
  label: string;
  x: number;
  y: number;
  width: number;
  center_x: number;
  level: number;
  level_position: number;
  kind: "explicit" | "implicit" | "dummy";
  edge_index: number | null;
}

interface ZigraphEdge {
  from: number;
  to: number;
  from_x: number;
  from_y: number;
  to_x: number;
  to_y: number;
  path: PathDirect | PathCorner | PathSideChannel | PathMultiSegment | PathSpline;
  edge_index: number;
  directed: boolean;
  label?: string;
  label_x?: number;
  label_y?: number;
}

type PathDirect = { type: "direct" };
type PathCorner = { type: "corner"; horizontal_y: number };
type PathSideChannel = { type: "side_channel"; channel_x: number; start_y: number; end_y: number };
type PathMultiSegment = { type: "multi_segment"; waypoints: [number, number][] };
type PathSpline = { type: "spline"; cp1_x: number; cp1_y: number; cp2_x: number; cp2_y: number };
```

### SVG Rendering (Pseudocode)

```javascript
function renderToSVG(layout) {
  const cellWidth = 10;  // pixels per character cell
  const cellHeight = 20;
  
  let svg = `<svg width="${layout.width * cellWidth}" height="${layout.height * cellHeight}">`;
  
  // Render nodes as rectangles
  for (const node of layout.nodes) {
    svg += `<rect x="${node.x * cellWidth}" y="${node.y * cellHeight}" 
                  width="${node.width * cellWidth}" height="${cellHeight}" 
                  fill="white" stroke="black"/>`;
    svg += `<text x="${node.center_x * cellWidth}" y="${(node.y + 0.7) * cellHeight}"
                  text-anchor="middle">${node.label}</text>`;
  }
  
  // Render edges as paths
  for (const edge of layout.edges) {
    if (edge.path.type === "direct") {
      svg += `<line x1="${edge.from_x * cellWidth}" y1="${edge.from_y * cellHeight}"
                    x2="${edge.to_x * cellWidth}" y2="${edge.to_y * cellHeight}"
                    stroke="black" marker-end="url(#arrow)"/>`;
    }
    // Handle other path types...
  }
  
  svg += '</svg>';
  return svg;
}
```

### Python

```python
import json

def load_layout(json_str: str) -> dict:
    layout = json.loads(json_str)
    assert layout["version"] in ("1.0", "1.1")
    return layout

def node_bounds(node: dict) -> tuple:
    """Return (left, top, right, bottom) bounds."""
    return (
        node["x"],
        node["y"],
        node["x"] + node["width"],
        node["y"] + 1
    )
```

---

## Version History

| Version | Changes |
|---------|---------|
| 1.0 | Initial schema |
| 1.1 | Added `directed`, `edge_index`, `label`, `label_x`, `label_y` on edges; `kind` and `edge_index` on nodes; added deserialization support |

---

## Design Decisions

### Why character cells?

The coordinate system uses character cells (not pixels) because:
1. Matches the Unicode renderer output exactly
2. Resolution-independent
3. Easy to scale: multiply by desired cell size

### Why center_x?

Edge routing needs the center of node boxes. Including `center_x` saves consumers from computing `x + width/2` repeatedly.

### Why level and level_position?

These expose the Sugiyama layer structure for consumers that want semantic information (e.g., "show all nodes at the same level with the same color").
