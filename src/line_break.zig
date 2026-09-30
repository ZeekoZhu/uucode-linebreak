const std = @import("std");
const uucode = @import("uucode");
const data = @import("line_break_data.zig");

/// Unicode Line_Break property values used by UAX #14.
pub const LineBreakClass = data.LineBreakClass;

/// Result of evaluating the boundary at the end of a segment.
pub const Break = enum { dont_break, can_break, must_break };

/// A contiguous UTF-8 byte range and the break decision at its end.
pub const Segment = struct {
    start: usize,
    end: usize,
    @"break": Break,

    /// Returns the bytes covered by this segment.
    ///
    /// `str` must be the input passed to `lineSegments`; `end` is exclusive.
    pub fn bytes(self: Segment, str: []const u8) []const u8 {
        return str[self.start..self.end];
    }
};

/// Returns the Unicode 18.0.0 Line_Break class for a code point.
pub fn lineBreakClass(cp: u21) LineBreakClass {
    var lo: usize = 0;
    var hi: usize = data.ranges.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const range = data.ranges[mid];
        if (cp < range.first) hi = mid else if (cp > range.last) lo = mid + 1 else return range.class;
    }
    return .XX;
}

const Item = struct {
    start: usize,
    end: usize,
    cp: u21,
    lb: LineBreakClass,
    gc: uucode.types.GeneralCategory,
    eaw: uucode.types.EastAsianWidth,
    zwj: bool,
    cm: bool,
    dotted: bool,
    ext_pic_cn: bool,
};

const NumericState = enum { none, sequence, close };

const State = struct {
    have_prev: bool = false,
    prev: Item = emptyItem(),
    prev2: Item = emptyItem(),
    have_prev2: bool = false,
    have_before_spaces: bool = false,
    before_spaces: Item = emptyItem(),
    prev_initial_quote: bool = false,
    before_spaces_initial_quote: bool = false,
    after_zwj: bool = false,
    ri_run: usize = 0,
    numeric_state: NumericState = .none,

    fn boundaryBefore(self: *State, current: Item, input: []const u8) Break {
        if (!self.have_prev) return .dont_break;
        const prev = self.prev;
        if (prev.lb == .BK) return .must_break;
        if (prev.lb == .CR) return if (current.lb == .LF) .dont_break else .must_break;
        if (prev.lb == .LF or prev.lb == .NL) return .must_break;
        if (isHardBreak(current.lb)) return .dont_break;
        if (current.lb == .SP or current.lb == .ZW) return .dont_break;
        if (prev.lb == .ZW or (prev.lb == .SP and self.have_before_spaces and self.before_spaces.lb == .ZW)) return .can_break;
        if (self.after_zwj) return .dont_break;
        var cur = current;
        if ((cur.cm or cur.zwj) and canAttachLineMark(prev.lb)) return .dont_break;
        if (cur.cm or cur.zwj) cur = asAL(cur);
        if (cur.lb == .WJ or prev.lb == .WJ) return .dont_break;
        if (prev.lb == .GL) return .dont_break;
        if (cur.lb == .GL and prev.lb != .SP and prev.lb != .HY and prev.lb != .HH) return .dont_break;
        if (cur.lb == .CL or cur.lb == .CP or cur.lb == .EX or cur.lb == .SY) return .dont_break;
        if (prev.lb == .OP or (prev.lb == .SP and self.have_before_spaces and self.before_spaces.lb == .OP)) return .dont_break;
        if (self.prev_initial_quote or (prev.lb == .SP and self.before_spaces_initial_quote)) return .dont_break;
        if (isFinalQuote(cur)) {
            const next = firstItem(input, cur.end);
            if (next == null or isAfterFinalQuote(next.?.lb)) return .dont_break;
        }
        if (prev.lb == .SP and cur.lb == .IS) {
            const next = firstItem(input, cur.end);
            if (next != null and next.?.lb == .NU) return .can_break;
        }
        if (cur.lb == .IS) return .dont_break;
        if (cur.lb == .NS and (prev.lb == .CL or prev.lb == .CP or (prev.lb == .SP and self.have_before_spaces and (self.before_spaces.lb == .CL or self.before_spaces.lb == .CP)))) return .dont_break;
        if (cur.lb == .B2 and (prev.lb == .B2 or (prev.lb == .SP and self.have_before_spaces and self.before_spaces.lb == .B2))) return .dont_break;
        if (prev.lb == .SP) return .can_break;
        if (cur.lb == .QU and !isInitialQuote(cur)) return .dont_break;
        if (prev.lb == .QU and !isFinalQuote(prev)) return .dont_break;
        if (cur.lb == .QU and !isEastAsian(prev)) return .dont_break;
        if (cur.lb == .QU) {
            const next = firstItem(input, cur.end);
            if (next == null or !isEastAsian(next.?)) return .dont_break;
        }
        if (prev.lb == .QU and !isEastAsian(cur)) return .dont_break;
        if (prev.lb == .QU and (!self.have_prev2 or !isEastAsian(self.prev2))) return .dont_break;
        if (cur.lb == .CB or prev.lb == .CB) return .can_break;
        if ((cur.lb == .AL or cur.lb == .HL) and (prev.lb == .HY or prev.lb == .HH) and (!self.have_prev2 or isWordInitialHyphenBefore(self.prev2.lb))) return .dont_break;
        if (cur.lb == .BA or cur.lb == .HH or cur.lb == .HY or cur.lb == .NS or prev.lb == .BB) return .dont_break;
        if (cur.lb != .HL and (prev.lb == .HY or prev.lb == .HH) and self.have_prev2 and self.prev2.lb == .HL) return .dont_break;
        if (prev.lb == .SY and cur.lb == .HL) return .dont_break;
        if (cur.lb == .IN) return .dont_break;
        if ((prev.lb == .AL or prev.lb == .HL) and cur.lb == .NU) return .dont_break;
        if (prev.lb == .NU and (cur.lb == .AL or cur.lb == .HL)) return .dont_break;
        if (prev.lb == .PR and (cur.lb == .ID or cur.lb == .EB or cur.lb == .EM)) return .dont_break;
        if ((prev.lb == .ID or prev.lb == .EB or prev.lb == .EM) and cur.lb == .PO) return .dont_break;
        if ((prev.lb == .PR or prev.lb == .PO) and (cur.lb == .AL or cur.lb == .HL)) return .dont_break;
        if ((prev.lb == .AL or prev.lb == .HL) and (cur.lb == .PR or cur.lb == .PO)) return .dont_break;
        if (self.matchesNumericNoBreakBefore(cur, input)) return .dont_break;
        if (prev.lb == .JL and (cur.lb == .JL or cur.lb == .JV or cur.lb == .H2 or cur.lb == .H3)) return .dont_break;
        if ((prev.lb == .JV or prev.lb == .H2) and (cur.lb == .JV or cur.lb == .JT)) return .dont_break;
        if ((prev.lb == .JT or prev.lb == .H3) and cur.lb == .JT) return .dont_break;
        if (isHangul(prev.lb) and cur.lb == .PO) return .dont_break;
        if (prev.lb == .PR and isHangul(cur.lb)) return .dont_break;
        if ((prev.lb == .AL or prev.lb == .HL) and (cur.lb == .AL or cur.lb == .HL)) return .dont_break;
        if (prev.lb == .AP and isAksaraStart(cur)) return .dont_break;
        if (isAksaraStart(prev) and (cur.lb == .VF or cur.lb == .VI)) return .dont_break;
        if (prev.lb == .VI and self.have_prev2 and isAksaraStart(self.prev2) and isAksaraCore(cur)) return .dont_break;
        if (isAksaraStart(prev) and isAksaraStart(cur)) {
            const next = firstItem(input, cur.end);
            if (next != null and next.?.lb == .VF) return .dont_break;
        }
        if (prev.lb == .IS and (cur.lb == .AL or cur.lb == .HL)) return .dont_break;
        if ((prev.lb == .AL or prev.lb == .HL or prev.lb == .NU) and cur.lb == .OP and !isEastAsian(cur)) return .dont_break;
        if (prev.lb == .CP and !isEastAsian(prev) and (cur.lb == .AL or cur.lb == .HL or cur.lb == .NU)) return .dont_break;
        if (prev.lb == .RI and cur.lb == .RI and self.ri_run % 2 == 1) return .dont_break;
        if ((prev.lb == .EB or prev.ext_pic_cn) and cur.lb == .EM) return .dont_break;
        return .can_break;
    }

    fn consume(self: *State, original: Item, no_break: bool) void {
        var item = original;
        var ignore = false;
        if (self.have_prev and (item.cm or item.zwj) and canAttachLineMark(self.prev.lb)) ignore = no_break;
        if (item.cm or item.zwj) {
            if (!ignore) item = asAL(item);
        }
        self.after_zwj = item.zwj;
        if (ignore) return;
        const initial_quote = isInitialQuote(item) and self.initialQuoteContext();
        if (self.have_prev) {
            self.prev2 = self.prev;
            self.have_prev2 = true;
        }
        self.prev = item;
        self.have_prev = true;
        if (item.lb == .SP) {
            if (self.prev2.lb != .SP) {
                self.before_spaces = self.prev2;
                self.have_before_spaces = self.have_prev2;
                self.before_spaces_initial_quote = self.prev_initial_quote;
            }
        } else {
            self.have_before_spaces = false;
            self.before_spaces_initial_quote = false;
        }
        self.prev_initial_quote = initial_quote;
        self.updateNumericState(item.lb);
        if (item.lb == .RI) self.ri_run += 1 else self.ri_run = 0;
    }

    fn initialQuoteContext(self: *const State) bool {
        if (!self.have_prev) return true;
        return switch (self.prev.lb) {
            .BK, .CR, .LF, .NL, .OP, .QU, .GL, .SP, .ZW => true,
            else => false,
        };
    }

    fn updateNumericState(self: *State, lb: LineBreakClass) void {
        switch (lb) {
            .NU => self.numeric_state = .sequence,
            .SY, .IS => {
                if (self.numeric_state != .sequence) self.numeric_state = .none;
            },
            .CL, .CP => self.numeric_state = if (self.numeric_state == .sequence) .close else .none,
            else => self.numeric_state = .none,
        }
    }

    fn matchesNumericNoBreakBefore(self: *const State, cur: Item, input: []const u8) bool {
        const prev = self.prev;
        if ((cur.lb == .PO or cur.lb == .PR) and (self.numeric_state == .sequence or self.numeric_state == .close)) return true;
        if ((prev.lb == .PO or prev.lb == .PR) and cur.lb == .OP) return restStartsNumber(input, cur.end);
        if ((prev.lb == .PO or prev.lb == .PR) and cur.lb == .NU) return true;
        if (prev.lb == .HY and cur.lb == .NU) return true;
        if (prev.lb == .IS and cur.lb == .NU) return true;
        return self.numeric_state == .sequence and cur.lb == .NU;
    }
};

/// Stateful, allocation-free iterator over UTF-8 line segments.
pub const LineIterator = struct {
    input: []const u8,
    segment_start: usize = 0,
    next_index: usize = 0,
    last_end: usize = 0,
    done: bool = false,
    state: State = .{},

    /// Creates a zero-allocation iterator over line segments in `input`.
    pub fn init(input: []const u8) LineIterator {
        var iterator = LineIterator{ .input = input };
        const item = firstItem(input, 0) orelse {
            iterator.done = true;
            return iterator;
        };
        iterator.state.consume(item, true);
        iterator.next_index = item.end;
        iterator.last_end = item.end;
        return iterator;
    }

    /// Returns the next segment, or `null` after the input is exhausted.
    pub fn nextSegment(self: *LineIterator) ?Segment {
        if (self.done or !self.state.have_prev) return null;
        while (true) {
            if (self.next_index >= self.input.len) {
                self.done = true;
                return .{ .start = self.segment_start, .end = self.last_end, .@"break" = .must_break };
            }
            const item = firstItem(self.input, self.next_index) orelse {
                self.done = true;
                return .{ .start = self.segment_start, .end = self.last_end, .@"break" = .must_break };
            };
            const kind = self.state.boundaryBefore(item, self.input);
            self.state.consume(item, kind == .dont_break);
            self.next_index = item.end;
            self.last_end = item.end;
            if (kind != .dont_break) {
                const segment = Segment{ .start = self.segment_start, .end = item.start, .@"break" = kind };
                self.segment_start = item.start;
                return segment;
            }
        }
    }

    /// Returns the next segment without advancing the iterator.
    pub fn peekSegment(self: *const LineIterator) ?Segment {
        var copy = self.*;
        return copy.nextSegment();
    }
};

/// Creates an iterator over UAX #14 line segments in a UTF-8 string.
pub fn lineSegments(input: []const u8) LineIterator {
    return LineIterator.init(input);
}

fn firstItem(input: []const u8, index: usize) ?Item {
    if (index >= input.len) return null;
    const decoded = decode(input, index) orelse return null;
    const cp = decoded.cp;
    const gc = uucode.get(.general_category, cp);
    var lb = lineBreakClass(cp);
    switch (lb) {
        .AI, .SG, .XX => lb = .AL,
        .SA => lb = if (gc == .mark_nonspacing or gc == .mark_spacing_combining) .CM else .AL,
        .CJ => lb = .NS,
        else => {},
    }
    return .{
        .start = index,
        .end = decoded.end,
        .cp = cp,
        .lb = lb,
        .gc = gc,
        .eaw = uucode.get(.east_asian_width, cp),
        .zwj = lb == .ZWJ,
        .cm = lb == .CM,
        .dotted = cp == 0x25CC,
        .ext_pic_cn = uucode.get(.is_extended_pictographic, cp) and gc == .other_not_assigned,
    };
}

const Decoded = struct { cp: u21, end: usize };

fn decode(input: []const u8, index: usize) ?Decoded {
    const first = input[index];
    if (first < 0x80) return .{ .cp = first, .end = index + 1 };
    var cp: u21 = undefined;
    var count: usize = undefined;
    if (first & 0xE0 == 0xC0) { cp = first & 0x1F; count = 2; }
    else if (first & 0xF0 == 0xE0) { cp = first & 0x0F; count = 3; }
    else if (first & 0xF8 == 0xF0) { cp = first & 0x07; count = 4; }
    else return null;
    if (index + count > input.len) return null;
    for (1..count) |i| {
        const byte = input[index + i];
        if (byte & 0xC0 != 0x80) return null;
        cp = (cp << 6) | (byte & 0x3F);
    }
    if ((count == 2 and cp < 0x80) or
        (count == 3 and cp < 0x800) or
        (count == 4 and cp < 0x10000) or
        cp > 0x10FFFF or
        (cp >= 0xD800 and cp <= 0xDFFF)) return null;
    return .{ .cp = cp, .end = index + count };
}

fn emptyItem() Item {
    return .{ .start = 0, .end = 0, .cp = 0, .lb = .AL, .gc = .letter_uppercase, .eaw = .narrow, .zwj = false, .cm = false, .dotted = false, .ext_pic_cn = false };
}

fn asAL(item: Item) Item {
    var result = item;
    result.lb = .AL;
    result.gc = .letter_uppercase;
    result.eaw = .narrow;
    result.cm = false;
    result.ext_pic_cn = false;
    return result;
}

fn restStartsNumber(input: []const u8, index: usize) bool {
    const item = firstItem(input, index) orelse return false;
    if (item.lb == .NU) return true;
    if (item.lb == .IS) {
        const next = firstItem(input, item.end) orelse return false;
        return next.lb == .NU;
    }
    return false;
}

fn isHardBreak(lb: LineBreakClass) bool { return lb == .BK or lb == .CR or lb == .LF or lb == .NL; }
fn canAttachLineMark(lb: LineBreakClass) bool { return !isHardBreak(lb) and lb != .SP and lb != .ZW; }
fn isInitialQuote(item: Item) bool { return item.lb == .QU and item.gc == .punctuation_initial_quote; }
fn isFinalQuote(item: Item) bool { return item.lb == .QU and item.gc == .punctuation_final_quote; }

fn isAfterFinalQuote(lb: LineBreakClass) bool {
    return switch (lb) { .SP, .GL, .WJ, .CL, .QU, .CP, .EX, .IS, .SY, .BK, .CR, .LF, .NL, .ZW => true, else => false };
}

fn isEastAsian(item: Item) bool { return item.eaw == .fullwidth or item.eaw == .wide or item.eaw == .halfwidth; }

fn isWordInitialHyphenBefore(lb: LineBreakClass) bool {
    return switch (lb) { .BK, .CR, .LF, .NL, .SP, .ZW, .CB, .GL => true, else => false };
}

fn isHangul(lb: LineBreakClass) bool { return lb == .JL or lb == .JV or lb == .JT or lb == .H2 or lb == .H3; }
fn isAksaraStart(item: Item) bool { return item.lb == .AK or item.lb == .AS or item.dotted; }
fn isAksaraCore(item: Item) bool { return item.lb == .AK or item.dotted; }

test "line break class" {
    try std.testing.expectEqual(LineBreakClass.LF, lineBreakClass('\n'));
    try std.testing.expectEqual(LineBreakClass.SP, lineBreakClass(' '));
    try std.testing.expectEqual(LineBreakClass.ID, lineBreakClass(0x4E00));
}

test "line segments" {
    var iterator = lineSegments("hello world");
    const first = iterator.nextSegment().?;
    try std.testing.expectEqualStrings("hello ", first.bytes("hello world"));
    try std.testing.expectEqual(Break.can_break, first.@"break");
    const second = iterator.nextSegment().?;
    try std.testing.expectEqualStrings("world", "hello world"[second.start..second.end]);
    try std.testing.expectEqual(Break.must_break, second.@"break");
    try std.testing.expect(iterator.nextSegment() == null);
}

test "rejects overlong UTF-8" {
    var iterator = lineSegments("\xC0\x80");
    try std.testing.expect(iterator.nextSegment() == null);
}
