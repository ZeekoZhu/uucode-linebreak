#!/usr/bin/env python3
"""Generate the Zig Line_Break table from a matching Unicode UCD release.

Examples:

    tools/generate_line_break.py --version 18.0.0
    tools/generate_line_break.py --line-break LineBreak.txt \
        --derived-line-break DerivedLineBreak.txt --output src/line_break_data.zig
"""

from __future__ import annotations

import argparse
import bisect
import urllib.request
from pathlib import Path


UNICODE_BASE_URL = "https://www.unicode.org/Public/{version}/ucd"


def read_source(source: str) -> str:
    if source.startswith(("http://", "https://")):
        with urllib.request.urlopen(source) as response:
            return response.read().decode("utf-8")
    return Path(source).read_text(encoding="utf-8")


def parse_ranges(source: str) -> list[tuple[int, int, str]]:
    ranges = []
    for raw_line in source.splitlines():
        line = raw_line.split("#", 1)[0].strip()
        if not line or ";" not in line:
            continue
        codepoints, property_name = (part.strip() for part in line.split(";", 1))
        if ".." in codepoints:
            first_text, last_text = codepoints.split("..", 1)
            first, last = int(first_text, 16), int(last_text, 16)
        else:
            first = last = int(codepoints, 16)
        ranges.append((first, last, property_name))
    return ranges


def lookup(ranges: list[tuple[int, int, str]], starts: list[int], codepoint: int) -> str | None:
    index = bisect.bisect_right(starts, codepoint) - 1
    if index >= 0:
        first, last, property_name = ranges[index]
        if codepoint <= last:
            return property_name
    return None


def merge_ranges(
    line_break: list[tuple[int, int, str]],
    derived_line_break: list[tuple[int, int, str]],
) -> list[tuple[int, int, str]]:
    line_break_starts = [first for first, _, _ in line_break]
    derived_starts = [first for first, _, _ in derived_line_break]
    boundaries = {0, 0x110000}
    for first, last, _ in line_break + derived_line_break:
        boundaries.add(first)
        if last < 0x10FFFF:
            boundaries.add(last + 1)

    merged = []
    sorted_boundaries = sorted(boundaries)
    for first, next_boundary in zip(sorted_boundaries, sorted_boundaries[1:]):
        property_name = lookup(derived_line_break, derived_starts, first)
        if property_name is None:
            property_name = lookup(line_break, line_break_starts, first)
        if property_name is None:
            property_name = "XX"
        last = next_boundary - 1
        if merged and merged[-1][2] == property_name and merged[-1][1] + 1 == first:
            merged[-1] = (merged[-1][0], last, property_name)
        else:
            merged.append((first, last, property_name))
    return merged


def render(version: str, ranges: list[tuple[int, int, str]]) -> str:
    properties = sorted({property_name for _, _, property_name in ranges})
    lines = [f"// Generated from Unicode {version} LineBreak.txt and DerivedLineBreak.txt."]
    lines.append("/// Unicode Line_Break property values for this UCD release.")
    lines.append("pub const LineBreakClass = enum {")
    for offset in range(0, len(properties), 15):
        lines.append("    " + ", ".join(properties[offset : offset + 15]) + ",")
    lines.extend([
        "};",
        "",
        "/// One inclusive code point range with its Line_Break class.",
        "pub const Range = struct { first: u21, last: u21, class: LineBreakClass };",
        "",
        "/// Sorted, non-overlapping Line_Break ranges covering all Unicode code points.",
        "pub const ranges = [_]Range{",
    ])
    lines.extend(
        f"    .{{ .first = 0x{first:X}, .last = 0x{last:X}, .class = .{property_name} }},"
        for first, last, property_name in ranges
    )
    lines.extend(["};", ""])
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", default="18.0.0")
    parser.add_argument("--line-break")
    parser.add_argument("--derived-line-break")
    parser.add_argument("--output", default="src/line_break_data.zig")
    args = parser.parse_args()

    base_url = UNICODE_BASE_URL.format(version=args.version)
    line_break_source = args.line_break or f"{base_url}/LineBreak.txt"
    derived_source = args.derived_line_break or f"{base_url}/extracted/DerivedLineBreak.txt"
    ranges = merge_ranges(parse_ranges(read_source(line_break_source)), parse_ranges(read_source(derived_source)))
    Path(args.output).write_text(render(args.version, ranges), encoding="utf-8")


if __name__ == "__main__":
    main()
