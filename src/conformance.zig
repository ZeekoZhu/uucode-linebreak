const std = @import("std");
const linebreak = @import("line_break.zig");

const fixture = @embedFile("LineBreakTest.txt");

test "Unicode 18 LineBreakTest.txt" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var line_number: usize = 0;
    var lines = std.mem.splitScalar(u8, fixture, '\n');
    while (lines.next()) |raw_line| {
        line_number += 1;
        const comment_start = std.mem.indexOfScalar(u8, raw_line, '#') orelse raw_line.len;
        const line = std.mem.trim(u8, raw_line[0..comment_start], " \t\r");
        if (line.len == 0) continue;

        var codepoints: std.ArrayList(u21) = .empty;
        var expected: std.ArrayList(bool) = .empty;
        var tokens = std.mem.tokenizeAny(u8, line, " \t");
        while (tokens.next()) |marker| {
            const should_break = if (std.mem.eql(u8, marker, "÷")) true else if (std.mem.eql(u8, marker, "×")) false else return error.InvalidFixture;
            try expected.append(allocator, should_break);
            const codepoint_token = tokens.next() orelse break;
            try codepoints.append(allocator, try std.fmt.parseInt(u21, codepoint_token, 16));
        }
        if (expected.items.len != codepoints.items.len + 1) return error.InvalidFixture;

        var input: std.ArrayList(u8) = .empty;
        var ends: std.ArrayList(usize) = .empty;
        for (codepoints.items) |cp| {
            appendUtf8(&input, allocator, cp) catch return error.InvalidFixture;
            try ends.append(allocator, input.items.len);
        }

        var actual: std.ArrayList(bool) = .empty;
        try actual.appendNTimes(allocator, false, expected.items.len);
        var iterator = linebreak.lineSegments(input.items);
        while (iterator.nextSegment()) |segment| {
            var boundary: usize = 0;
            while (boundary < ends.items.len and ends.items[boundary] != segment.end) : (boundary += 1) {}
            if (boundary < ends.items.len) boundary += 1;
            actual.items[boundary] = true;
        }

        for (expected.items, actual.items, 0..) |want, got, boundary| {
            if (want != got) {
                std.debug.print("LineBreakTest.txt:{d}: boundary {d} expected {s}, got {s}\n", .{
                    line_number,
                    boundary,
                    if (want) "÷" else "×",
                    if (got) "÷" else "×",
                });
                return error.ConformanceFailure;
            }
        }
    }
}

fn appendUtf8(input: *std.ArrayList(u8), allocator: std.mem.Allocator, cp: u21) !void {
    if (cp <= 0x7F) {
        try input.append(allocator, @intCast(cp));
    } else if (cp <= 0x7FF) {
        try input.appendSlice(allocator, &.{ @intCast(0xC0 | (cp >> 6)), @intCast(0x80 | (cp & 0x3F)) });
    } else if (cp <= 0xFFFF) {
        try input.appendSlice(allocator, &.{ @intCast(0xE0 | (cp >> 12)), @intCast(0x80 | ((cp >> 6) & 0x3F)), @intCast(0x80 | (cp & 0x3F)) });
    } else {
        try input.appendSlice(allocator, &.{ @intCast(0xF0 | (cp >> 18)), @intCast(0x80 | ((cp >> 12) & 0x3F)), @intCast(0x80 | ((cp >> 6) & 0x3F)), @intCast(0x80 | (cp & 0x3F)) });
    }
}
