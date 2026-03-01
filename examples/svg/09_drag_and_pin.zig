//! # 09 — Drag & Pin with Live Re-layout (HTTP Server)
//!
//! An interactive graph editor backed by a local Zig HTTP server.
//!
//! Features:
//!   1. **Drag** any node to a new position
//!   2. **Click** a node to **pin** it (red border = pinned)
//!   3. **Double-click** a pinned node to **unpin** it
//!   4. **Re-layout** button sends pinned state to the server,
//!      which runs the real zigraph layout algorithm and returns new positions
//!   5. **Algorithm selector**: switch between Sugiyama and FDG
//!
//! Run: `zig build run-svg_09_drag_and_pin`
//! Then open http://localhost:8082 in a browser.

const std = @import("std");
const zigraph = @import("zigraph");

// ─── Graph definition (shared between initial render and re-layout) ─────────

const NodeDef = struct { id: usize, label: []const u8 };
const node_defs = [_]NodeDef{
    .{ .id = 1, .label = "Server" },
    .{ .id = 2, .label = "Auth" },
    .{ .id = 3, .label = "API" },
    .{ .id = 4, .label = "Database" },
    .{ .id = 5, .label = "Cache" },
    .{ .id = 6, .label = "Client" },
};

const edge_defs = [_][2]usize{
    .{ 6, 1 }, .{ 1, 2 }, .{ 1, 3 },
    .{ 2, 4 }, .{ 3, 4 }, .{ 3, 5 },
};

const CW: usize = 10; // char_width
const LH: usize = 24; // line_height
const PAD: usize = 20; // padding

// ─── Shared types ───────────────────────────────────────────────────────────

const PinEntry = struct {
    id: usize,
    pin_x: ?usize = null,
    pin_y: ?usize = null,
};

const NodePos = struct {
    id: usize,
    label: []const u8,
    x: usize,
    y: usize,
    w: usize,
    h: usize,
    cx: usize,
    cy: usize,
};

const Algorithm = enum { sugiyama, fdg };

// ─── Layout helper ──────────────────────────────────────────────────────────

const LayoutResult = struct {
    nodes: []NodePos,
    json: []const u8,
    width: usize,
    height: usize,
    allocator: std.mem.Allocator,
    ir_arena: std.heap.ArenaAllocator,

    fn deinit(self: *LayoutResult) void {
        self.allocator.free(self.json);
        self.allocator.free(self.nodes);
        self.ir_arena.deinit();
    }
};

fn runLayout(allocator: std.mem.Allocator, algo: Algorithm, pins: ?[]const PinEntry) !LayoutResult {
    var ir_arena = std.heap.ArenaAllocator.init(allocator);
    errdefer ir_arena.deinit();
    const aa = ir_arena.allocator();

    var g = zigraph.Graph.init(aa);

    for (node_defs) |nd| {
        var pin_val: ?zigraph.Pin = null;
        if (pins) |plist| {
            for (plist) |pe| {
                if (pe.id == nd.id) {
                    pin_val = .{ .x = pe.pin_x, .y = pe.pin_y };
                    break;
                }
            }
        }
        if (pin_val) |pv| {
            try g.addNode(nd.id, zigraph.NodeOptions{ .label = nd.label, .pin = pv });
        } else {
            try g.addNode(nd.id, nd.label);
        }
    }
    for (edge_defs) |ed| try g.addEdge(ed[0], ed[1]);

    const config: zigraph.LayoutConfig = switch (algo) {
        .sugiyama => .{ .routing = .spline },
        .fdg => .{ .algorithm = .{ .fruchterman_reingold = .{} } },
    };

    var ir = try zigraph.layout(&g, aa, config);

    // Build JSON + node position list
    const ir_nodes = ir.getNodes();
    const ir_edges = ir.getEdges();

    var jbuf: std.ArrayListUnmanaged(u8) = .{};
    errdefer jbuf.deinit(allocator);

    var nlist: std.ArrayListUnmanaged(NodePos) = .{};
    errdefer nlist.deinit(allocator);

    try jbuf.appendSlice(allocator, "{\"nodes\":[");
    var first = true;
    for (ir_nodes) |node| {
        if (node.kind != .explicit and node.kind != .implicit) continue;
        const px = node.x * CW + PAD;
        const py = node.y * LH + PAD;
        const pw = node.width * CW;
        const ph = node.height * LH;
        if (!first) try jbuf.append(allocator, ',');
        first = false;
        try std.fmt.format(jbuf.writer(allocator), "{{\"id\":{d},\"x\":{d},\"y\":{d},\"w\":{d},\"h\":{d},\"cx\":{d},\"cy\":{d}}}", .{
            node.id, px, py, pw, ph, px + pw / 2, py + ph / 2,
        });
        try nlist.append(allocator, .{
            .id = node.id,
            .label = node.label,
            .x = px,
            .y = py,
            .w = pw,
            .h = ph,
            .cx = px + pw / 2,
            .cy = py + ph / 2,
        });
    }

    try jbuf.appendSlice(allocator, "],\"edges\":[");
    first = true;
    for (ir_edges) |edge| {
        if (!first) try jbuf.append(allocator, ',');
        first = false;
        try std.fmt.format(jbuf.writer(allocator), "{{\"from\":{d},\"to\":{d},\"x1\":{d},\"y1\":{d},\"x2\":{d},\"y2\":{d}}}", .{
            edge.from_id,           edge.to_id,
            edge.from_x * CW + PAD, edge.from_y * LH + PAD,
            edge.to_x * CW + PAD,   edge.to_y * LH + PAD,
        });
    }

    const w_px = ir.getWidth() * CW + PAD * 2 + 100;
    const h_px = ir.getHeight() * LH + PAD * 2 + 100;
    try std.fmt.format(jbuf.writer(allocator), "],\"width\":{d},\"height\":{d}}}", .{ w_px, h_px });

    ir.deinit();

    const owned_nodes = try allocator.alloc(NodePos, nlist.items.len);
    @memcpy(owned_nodes, nlist.items);
    nlist.deinit(allocator);

    return .{
        .nodes = owned_nodes,
        .json = try jbuf.toOwnedSlice(allocator),
        .width = w_px,
        .height = h_px,
        .allocator = allocator,
        .ir_arena = ir_arena,
    };
}

// ─── HTML page builder ──────────────────────────────────────────────────────

fn buildHtmlPage(allocator: std.mem.Allocator, initial: *LayoutResult) ![]const u8 {
    var buf: std.ArrayListUnmanaged(u8) = .{};
    errdefer buf.deinit(allocator);
    const w = buf.writer(allocator);

    // ── Head + Styles ──
    try w.writeAll(
        \\<!DOCTYPE html>
        \\<html lang="en"><head><meta charset="UTF-8">
        \\<meta name="viewport" content="width=device-width, initial-scale=1.0">
        \\<title>zigraph — Drag &amp; Pin with Re-layout</title>
        \\<style>
        \\*{margin:0;padding:0;box-sizing:border-box}
        \\body{font-family:system-ui,sans-serif;background:#f8fafc}
        \\header{background:#1e293b;color:#fff;padding:12px 24px;display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:8px}
        \\header h1{font-size:18px;font-weight:600}
        \\.hint{font-size:13px;color:#94a3b8;margin-top:2px}
        \\.controls{display:flex;gap:8px;align-items:center}
        \\.controls select,.controls button{font-size:13px;padding:6px 12px;border-radius:6px;border:1px solid #475569;background:#334155;color:#fff;cursor:pointer}
        \\.controls button{background:#2563eb;border-color:#2563eb;font-weight:600}
        \\.controls button:hover{background:#1d4ed8}
        \\.controls button:disabled{opacity:.5;cursor:wait}
        \\.controls .rst{background:#475569;border-color:#475569}
        \\.controls .rst:hover{background:#64748b}
        \\.legend{display:flex;gap:12px;font-size:12px;color:#94a3b8;align-items:center}
        \\.legend span{display:inline-flex;align-items:center;gap:4px}
        \\.dot{width:10px;height:10px;border-radius:50%;display:inline-block}
        \\.dot.free{background:#22c55e;border:2px solid #16a34a}
        \\.dot.pinned{background:#ef4444;border:2px solid #dc2626}
        \\#canvas{width:100%;height:calc(100vh - 56px);cursor:default}
        \\.ng{cursor:grab;transition:transform .4s ease}
        \\.ng:active{cursor:grabbing}
        \\.ng.pinned rect{stroke:#dc2626!important;stroke-width:2.5}
        \\.ng.pinned .pi{display:block}
        \\.pi{display:none;font-size:10px}
        \\.ep{fill:none;stroke:#94a3b8;stroke-width:1.5;transition:all .4s ease}
        \\.ep.hl{stroke:#3b82f6;stroke-width:2.5}
        \\#status{position:fixed;bottom:12px;left:50%;transform:translateX(-50%);background:#1e293b;color:#e2e8f0;padding:8px 16px;border-radius:8px;font-size:13px;opacity:0;transition:opacity .3s;z-index:10;pointer-events:none}
        \\#status.show{opacity:1}
        \\</style></head><body>
        \\<header>
        \\  <div>
        \\    <h1>zigraph — Drag &amp; Pin with Re-layout</h1>
        \\    <div class="hint">Drag to move · Click to pin · Double-click to unpin · Re-layout sends pins to zigraph</div>
        \\  </div>
        \\  <div class="controls">
        \\    <select id="algo">
        \\      <option value="sugiyama" selected>Sugiyama (hierarchical)</option>
        \\      <option value="fdg">Force-Directed (FDG)</option>
        \\    </select>
        \\    <button id="rbtn" onclick="relayout()">⟳ Re-layout</button>
        \\    <button class="rst" onclick="resetPins()">Reset pins</button>
        \\  </div>
        \\  <div class="legend">
        \\    <span><span class="dot free"></span> Free</span>
        \\    <span><span class="dot pinned"></span> Pinned</span>
        \\  </div>
        \\</header>
        \\<div id="status"></div>
        \\
    );

    // ── SVG ──
    try w.print(
        \\<svg id="canvas" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {d} {d}">
        \\<defs>
        \\  <marker id="arr" markerWidth="8" markerHeight="8" refX="8" refY="4"
        \\          orient="auto" markerUnits="userSpaceOnUse">
        \\    <polygon points="0 0,8 4,0 8" fill="#94a3b8"/>
        \\  </marker>
        \\</defs>
        \\<rect width="100%" height="100%" fill="#f8fafc"/>
        \\<g id="edges"></g>
        \\<g id="nodes">
        \\
    , .{ initial.width, initial.height });

    for (initial.nodes) |n| {
        try w.print(
            \\  <g class="ng" data-id="{d}" transform="translate({d},{d})"
            \\     data-cx="{d}" data-cy="{d}" data-w="{d}" data-h="{d}">
            \\    <rect x="0" y="0" width="{d}" height="{d}" rx="6" ry="6"
            \\          fill="#f0f9ff" stroke="#0284c7" stroke-width="1.5"/>
            \\    <text x="{d}" y="{d}" text-anchor="middle" font-family="monospace"
            \\          font-size="12" fill="#334155" stroke="none">{s}</text>
            \\    <text class="pi" x="{d}" y="14" font-size="12">📌</text>
            \\  </g>
            \\
        , .{
            n.id, n.x, n.y,     n.cx,        n.cy,    n.w,       n.h,
            n.w,  n.h, n.w / 2, n.h / 2 + 4, n.label, n.w -| 16,
        });
    }

    try w.writeAll("</g>\n</svg>\n");

    // ── Initial layout JSON ──
    try w.print("<script>var L={s};</script>\n", .{initial.json});

    // ── JavaScript ──
    try w.writeAll(
        \\<script>
        \\(function(){
        \\const svg=document.getElementById('canvas'),
        \\      nG=document.getElementById('nodes'),
        \\      eG=document.getElementById('edges'),
        \\      stEl=document.getElementById('status');
        \\const pinned=new Map();
        \\
        \\function toast(m,d){stEl.textContent=m;stEl.classList.add('show');setTimeout(()=>stEl.classList.remove('show'),d||2000)}
        \\
        \\function drawEdges(lay){
        \\  eG.innerHTML='';
        \\  for(const e of lay.edges){
        \\    const l=document.createElementNS('http://www.w3.org/2000/svg','line');
        \\    l.setAttribute('class','ep');
        \\    l.setAttribute('data-from',e.from);l.setAttribute('data-to',e.to);
        \\    l.setAttribute('x1',e.x1);l.setAttribute('y1',e.y1);
        \\    l.setAttribute('x2',e.x2);l.setAttribute('y2',e.y2);
        \\    l.setAttribute('marker-end','url(#arr)');
        \\    eG.appendChild(l);
        \\  }
        \\}
        \\drawEdges(L);
        \\
        \\function sp(e){const p=svg.createSVGPoint();p.x=e.clientX;p.y=e.clientY;return p.matrixTransform(svg.getScreenCTM().inverse())}
        \\function gc(el){return{x:+el.getAttribute('data-cx'),y:+el.getAttribute('data-cy')}}
        \\function sc(el,cx,cy){el.setAttribute('data-cx',cx);el.setAttribute('data-cy',cy)}
        \\function ue(id,cx,cy){eG.querySelectorAll('line').forEach(l=>{if(+l.getAttribute('data-from')===id){l.setAttribute('x1',cx);l.setAttribute('y1',cy)}if(+l.getAttribute('data-to')===id){l.setAttribute('x2',cx);l.setAttribute('y2',cy)}})}
        \\
        \\let drag=null,off={x:0,y:0},moved=false;
        \\nG.addEventListener('mousedown',e=>{
        \\  const g=e.target.closest('.ng');if(!g)return;e.preventDefault();
        \\  drag=g;moved=false;g.style.transition='none';
        \\  const pt=sp(e),m=g.getAttribute('transform').match(/translate\(([\d.-]+),([\d.-]+)\)/);
        \\  off.x=pt.x-parseFloat(m[1]);off.y=pt.y-parseFloat(m[2]);
        \\  g.style.opacity='.8';
        \\  const id=+g.getAttribute('data-id');
        \\  eG.querySelectorAll('line').forEach(l=>{if(+l.getAttribute('data-from')===id||+l.getAttribute('data-to')===id)l.classList.add('hl')});
        \\});
        \\svg.addEventListener('mousemove',e=>{
        \\  if(!drag)return;moved=true;const pt=sp(e);
        \\  const nx=Math.round(pt.x-off.x),ny=Math.round(pt.y-off.y);
        \\  drag.setAttribute('transform',`translate(${nx},${ny})`);
        \\  const w=+drag.getAttribute('data-w'),h=+drag.getAttribute('data-h');
        \\  const cx=nx+w/2,cy=ny+h/2;sc(drag,cx,cy);
        \\  ue(+drag.getAttribute('data-id'),cx,cy);
        \\});
        \\svg.addEventListener('mouseup',()=>{
        \\  if(!drag)return;drag.style.opacity='1';drag.style.transition='';
        \\  eG.querySelectorAll('.hl').forEach(l=>l.classList.remove('hl'));drag=null;
        \\});
        \\
        \\nG.addEventListener('click',e=>{
        \\  if(moved)return;const g=e.target.closest('.ng');if(!g)return;
        \\  const id=+g.getAttribute('data-id');
        \\  if(!pinned.has(id)){
        \\    const m=g.getAttribute('transform').match(/translate\(([\d.-]+),([\d.-]+)\)/);
        \\    pinned.set(id,{px:parseFloat(m[1]),py:parseFloat(m[2])});
        \\    g.classList.add('pinned');toast(`Node ${id} pinned`);
        \\  }
        \\});
        \\nG.addEventListener('dblclick',e=>{
        \\  const g=e.target.closest('.ng');if(!g)return;
        \\  const id=+g.getAttribute('data-id');
        \\  if(pinned.has(id)){pinned.delete(id);g.classList.remove('pinned');toast(`Node ${id} unpinned`)}
        \\});
        \\
        \\window.relayout=async function(){
        \\  const btn=document.getElementById('rbtn');
        \\  btn.disabled=true;btn.textContent='⏳ Running...';
        \\  const algo=document.getElementById('algo').value;
        \\  const CW=10,LH=24,PAD=20;
        \\  const pl=[];
        \\  for(const[id]of pinned){
        \\    const el=document.querySelector(`.ng[data-id="${id}"]`);
        \\    const m=el.getAttribute('transform').match(/translate\(([\d.-]+),([\d.-]+)\)/);
        \\    const lx=Math.max(0,Math.round((parseFloat(m[1])-PAD)/CW));
        \\    const ly=Math.max(0,Math.round((parseFloat(m[2])-PAD)/LH));
        \\    pl.push({id,x:lx,y:ly});
        \\  }
        \\  try{
        \\    const r=await fetch('/api/layout',{method:'POST',headers:{'Content-Type':'application/json'},
        \\      body:JSON.stringify({algorithm:algo,pins:pl})});
        \\    if(!r.ok)throw new Error(await r.text());
        \\    const lay=await r.json();
        \\    svg.setAttribute('viewBox',`0 0 ${lay.width} ${lay.height}`);
        \\    for(const n of lay.nodes){
        \\      const el=document.querySelector(`.ng[data-id="${n.id}"]`);
        \\      if(!el)continue;
        \\      el.style.transition='transform .4s ease';
        \\      el.setAttribute('transform',`translate(${n.x},${n.y})`);
        \\      sc(el,n.cx,n.cy);
        \\      if(pinned.has(n.id))pinned.set(n.id,{px:n.x,py:n.y});
        \\    }
        \\    drawEdges(lay);
        \\    toast(`Re-layout complete (${algo})`);
        \\  }catch(err){toast(`Error: ${err.message}`,4000)}
        \\  finally{btn.disabled=false;btn.textContent='⟳ Re-layout'}
        \\};
        \\window.resetPins=function(){
        \\  pinned.clear();
        \\  document.querySelectorAll('.ng.pinned').forEach(el=>el.classList.remove('pinned'));
        \\  toast('All pins cleared');
        \\};
        \\})();
        \\</script></body></html>
        \\
    );

    return buf.toOwnedSlice(allocator);
}

// ─── HTTP Server ────────────────────────────────────────────────────────────

fn handleRequest(
    request: *std.http.Server.Request,
    allocator: std.mem.Allocator,
    html_page: []const u8,
) !void {
    const target = request.head.target;

    // GET / → serve HTML
    if (request.head.method == .GET and
        (std.mem.eql(u8, target, "/") or std.mem.eql(u8, target, "/index.html")))
    {
        try request.respond(html_page, .{
            .extra_headers = &.{
                .{ .name = "content-type", .value = "text/html; charset=utf-8" },
                .{ .name = "cache-control", .value = "no-cache" },
            },
        });
        return;
    }

    // POST /api/layout → run layout and return JSON
    if (request.head.method == .POST and std.mem.eql(u8, target, "/api/layout")) {
        // Read body using the new Zig 0.15.2 body reader API
        var body_read_buf: [4096]u8 = undefined;
        const body_reader = request.readerExpectNone(&body_read_buf);
        const body = body_reader.allocRemaining(allocator, std.Io.Limit.limited(65536)) catch &[_]u8{};
        defer allocator.free(body);

        // Parse algorithm
        const algo: Algorithm = if (std.mem.indexOf(u8, body, "\"fdg\"") != null) .fdg else .sugiyama;

        // Parse pins
        var pins: std.ArrayListUnmanaged(PinEntry) = .{};
        defer pins.deinit(allocator);

        if (std.mem.indexOf(u8, body, "\"pins\":[")) |ps| {
            var pos = ps + 8;
            while (pos < body.len) {
                const os = std.mem.indexOfScalarPos(u8, body, pos, '{') orelse break;
                const oe = std.mem.indexOfScalarPos(u8, body, os, '}') orelse break;
                if (parsePinObject(body[os .. oe + 1])) |pe| try pins.append(allocator, pe);
                pos = oe + 1;
                if (pos < body.len and body[pos] == ']') break;
            }
        }

        const pin_slice: ?[]const PinEntry = if (pins.items.len > 0) pins.items else null;

        var result = runLayout(allocator, algo, pin_slice) catch |err| {
            const msg = std.fmt.allocPrint(allocator, "Layout error: {s}", .{@errorName(err)}) catch "layout error";
            defer allocator.free(msg);
            try request.respond(msg, .{
                .status = .internal_server_error,
                .extra_headers = &.{
                    .{ .name = "content-type", .value = "text/plain" },
                    .{ .name = "access-control-allow-origin", .value = "*" },
                },
            });
            return;
        };
        defer result.deinit();

        try request.respond(result.json, .{
            .extra_headers = &.{
                .{ .name = "content-type", .value = "application/json" },
                .{ .name = "access-control-allow-origin", .value = "*" },
            },
        });
        return;
    }

    // CORS preflight
    if (request.head.method == .OPTIONS) {
        try request.respond("", .{
            .extra_headers = &.{
                .{ .name = "access-control-allow-origin", .value = "*" },
                .{ .name = "access-control-allow-methods", .value = "GET,POST,OPTIONS" },
                .{ .name = "access-control-allow-headers", .value = "content-type" },
            },
        });
        return;
    }

    // 404
    try request.respond("Not Found", .{
        .status = .not_found,
        .extra_headers = &.{.{ .name = "content-type", .value = "text/plain" }},
    });
}

fn parsePinObject(obj: []const u8) ?PinEntry {
    const id_val = extractJsonInt(obj, "\"id\":") orelse return null;
    return .{ .id = id_val, .pin_x = extractJsonInt(obj, "\"x\":"), .pin_y = extractJsonInt(obj, "\"y\":") };
}

fn extractJsonInt(data: []const u8, key: []const u8) ?usize {
    const kp = std.mem.indexOf(u8, data, key) orelse return null;
    var s = kp + key.len;
    while (s < data.len and (data[s] == ' ' or data[s] == '\t')) s += 1;
    if (s >= data.len) return null;
    if (s + 4 <= data.len and std.mem.eql(u8, data[s .. s + 4], "null")) return null;
    var e = s;
    while (e < data.len and data[e] >= '0' and data[e] <= '9') e += 1;
    if (e == s) return null;
    return std.fmt.parseInt(usize, data[s..e], 10) catch null;
}

// ─── Main ───────────────────────────────────────────────────────────────────

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n── 09: Drag & Pin (HTTP Server) ──\n\n", .{});

    // Compute initial Sugiyama layout (no pins)
    var initial = try runLayout(allocator, .sugiyama, null);
    defer initial.deinit();

    // Pre-build the HTML page
    const html_page = try buildHtmlPage(allocator, &initial);
    defer allocator.free(html_page);

    // Start listener
    const port: u16 = 8082;
    const addr = std.net.Address.parseIp4("127.0.0.1", port) catch unreachable;
    var listener = try addr.listen(.{ .reuse_address = true });
    defer listener.deinit();

    std.debug.print("  🌐 Server running at http://localhost:{d}\n", .{port});
    std.debug.print("  Open in your browser to drag, pin, and re-layout.\n", .{});
    std.debug.print("  Press Ctrl+C to stop.\n\n", .{});

    while (true) {
        const conn = listener.accept() catch continue;
        defer conn.stream.close();
        var read_buf: [8192]u8 = undefined;
        var send_buf: [8192]u8 = undefined;
        var connection_reader = conn.stream.reader(&read_buf);
        var connection_writer = conn.stream.writer(&send_buf);
        var server: std.http.Server = .init(connection_reader.interface(), &connection_writer.interface);
        while (true) {
            var req = server.receiveHead() catch break;
            handleRequest(&req, allocator, html_page) catch break;
        }
    }
}
