const std = @import("std");
const linebreak = @import("uucode_linebreak");
const Io = std.Io;

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const out = &stdout_file_writer.interface;
    try out.print("uucode-linebreak Unicode 18.0.0\n", .{});
    var iterator = linebreak.lineSegments("hello world");
    while (iterator.nextSegment()) |segment| {
        try out.print("{d}..{d}: {s}\n", .{ segment.start, segment.end, @tagName(segment.@"break") });
    }
    try out.flush();
}
