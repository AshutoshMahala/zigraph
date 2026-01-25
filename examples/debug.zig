//! Debug example - inspect edge coordinates

const std = @import("std");
const zigraph = @import("zigraph");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // README Hero graph
    var dag = zigraph.Graph.init(allocator);
    defer dag.deinit();

    try dag.addNode(1, "Root");
    try dag.addNode(2, "Task A");
    try dag.addNode(3, "Task B");
    try dag.addNode(4, "Task C");
    try dag.addNode(5, "Task D");
    try dag.addNode(6, "Task E");
    try dag.addNode(7, "Task F");
    try dag.addNode(8, "Output");

    try dag.addEdge(1, 2);
    try dag.addEdge(1, 3);
    try dag.addEdge(1, 4);
    try dag.addEdge(1, 5);
    try dag.addEdge(1, 6);
    try dag.addEdge(2, 7);
    try dag.addEdge(3, 7);
    try dag.addEdge(4, 7);
    try dag.addEdge(5, 7);
    try dag.addEdge(7, 8);
    try dag.addEdge(6, 8);

    var layout_ir = try zigraph.layout(&dag, allocator, .{});
    defer layout_ir.deinit();

    std.debug.print("Nodes:\n", .{});
    for (layout_ir.getNodes()) |node| {
        std.debug.print("  id={d} label={s} x={d} y={d} center_x={d} level={d}\n", .{ node.id, node.label, node.x, node.y, node.center_x, node.level });
    }

    std.debug.print("\nEdges:\n", .{});
    for (layout_ir.getEdges()) |edge| {
        std.debug.print("  {d}->{d}: from_x={d} from_y={d} to_x={d} to_y={d}\n", .{ edge.from_id, edge.to_id, edge.from_x, edge.from_y, edge.to_x, edge.to_y });
        switch (edge.path) {
            .direct => std.debug.print("         path=direct\n", .{}),
            .corner => |c| std.debug.print("         path=corner h_y={d}\n", .{c.horizontal_y}),
            else => std.debug.print("         path=other\n", .{}),
        }
    }

    std.debug.print("\nDimensions: width={d} height={d}\n", .{ layout_ir.getWidth(), layout_ir.getHeight() });

    std.debug.print("\nRendered:\n", .{});
    const output = try zigraph.unicode.render(&layout_ir, allocator);
    defer allocator.free(output);
    std.debug.print("{s}\n", .{output});
}
