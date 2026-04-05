const std = @import("std");

pub const ExtractedBlock = struct {
    content: []const u8,
    line_offset: u32,
};

pub fn extractBlocks(allocator: std.mem.Allocator, markdown: []const u8) ![]ExtractedBlock {
    var blocks = std.ArrayListUnmanaged(ExtractedBlock){};

    var lines = std.mem.splitScalar(u8, markdown, '\n');
    var line_number: u32 = 0;
    var in_block = false;
    var block_start_offset: u32 = 0;
    var content_start: usize = 0;
    var current_pos: usize = 0;

    while (lines.next()) |line| {
        const trimmed = std.mem.trimLeft(u8, line, " \t");

        if (!in_block) {
            if (std.mem.startsWith(u8, trimmed, "```zgraph")) {
                // Check that after "```zgraph" there's nothing or only whitespace
                const rest = trimmed["```zgraph".len..];
                const rest_trimmed = std.mem.trim(u8, rest, " \t\r");
                if (rest_trimmed.len == 0) {
                    in_block = true;
                    block_start_offset = line_number + 1;
                    // Content starts after this line (after the newline)
                    content_start = current_pos + line.len + 1;
                }
            }
        } else {
            if (std.mem.startsWith(u8, trimmed, "```")) {
                // Check it's a closing fence (just backticks, no language tag)
                const rest = trimmed["```".len..];
                const rest_trimmed = std.mem.trim(u8, rest, " \t\r");
                if (rest_trimmed.len == 0) {
                    // End of block — slice content from markdown source
                    const content_end = current_pos;
                    const content = if (content_end > content_start)
                        markdown[content_start..content_end]
                    else
                        markdown[content_start..content_start];

                    try blocks.append(allocator, ExtractedBlock{
                        .content = content,
                        .line_offset = block_start_offset,
                    });
                    in_block = false;
                }
            }
        }

        current_pos += line.len + 1; // +1 for the '\n' that splitScalar consumed
        line_number += 1;
    }

    return blocks.toOwnedSlice(allocator);
}

test "single block" {
    const allocator = std.testing.allocator;
    const markdown =
        \\# Title
        \\
        \\```zgraph
        \\A -> B
        \\B -> C
        \\```
        \\
        \\End.
    ;

    const blocks = try extractBlocks(allocator, markdown);
    defer allocator.free(blocks);

    try std.testing.expectEqual(@as(usize, 1), blocks.len);
    try std.testing.expectEqualStrings("A -> B\nB -> C\n", blocks[0].content);
    try std.testing.expectEqual(@as(u32, 3), blocks[0].line_offset);
}

test "multiple blocks" {
    const allocator = std.testing.allocator;
    const markdown =
        \\First block:
        \\
        \\```zgraph
        \\X -> Y
        \\```
        \\
        \\Some text in between.
        \\
        \\```zgraph
        \\P -> Q
        \\Q -> R
        \\```
        \\
        \\Done.
    ;

    const blocks = try extractBlocks(allocator, markdown);
    defer allocator.free(blocks);

    try std.testing.expectEqual(@as(usize, 2), blocks.len);
    try std.testing.expectEqualStrings("X -> Y\n", blocks[0].content);
    try std.testing.expectEqualStrings("P -> Q\nQ -> R\n", blocks[1].content);
}

test "non-zgraph blocks ignored" {
    const allocator = std.testing.allocator;
    const markdown =
        \\```python
        \\print("hello")
        \\```
        \\
        \\```zgraph
        \\A -> B
        \\```
        \\
        \\```javascript
        \\console.log("hi");
        \\```
    ;

    const blocks = try extractBlocks(allocator, markdown);
    defer allocator.free(blocks);

    try std.testing.expectEqual(@as(usize, 1), blocks.len);
    try std.testing.expectEqualStrings("A -> B\n", blocks[0].content);
}

test "no blocks" {
    const allocator = std.testing.allocator;
    const markdown =
        \\# Just a heading
        \\
        \\Some plain text here.
        \\No code blocks at all.
    ;

    const blocks = try extractBlocks(allocator, markdown);
    defer allocator.free(blocks);

    try std.testing.expectEqual(@as(usize, 0), blocks.len);
}
