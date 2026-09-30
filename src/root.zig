//! Unicode Line Breaking Algorithm (UAX #14) for UTF-8 text.

/// Detailed UAX #14 implementation module.
pub const line_break = @import("line_break.zig");
/// UAX #14 Line_Break property values.
pub const LineBreakClass = line_break.LineBreakClass;
/// Break decision returned for a segment boundary.
pub const Break = line_break.Break;
/// UTF-8 byte range and break decision for one line segment.
pub const Segment = line_break.Segment;
/// Stateful iterator over line segments.
pub const LineIterator = line_break.LineIterator;
/// Returns the Line_Break class for a Unicode code point.
pub const lineBreakClass = line_break.lineBreakClass;
/// Creates a line-segment iterator for a UTF-8 string.
pub const lineSegments = line_break.lineSegments;

test {
    _ = line_break;
    _ = @import("conformance.zig");
}
