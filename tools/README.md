# Unicode data generation

`src/line_break_data.zig` is generated from the matching Unicode UCD release.
The generator applies `DerivedLineBreak.txt` over `LineBreak.txt` and fills
unassigned ranges with `XX`.

Generate the pinned Unicode version with:

```sh
python3 tools/generate_line_break.py --version 18.0.0
```

For an offline build, provide local UCD files:

```sh
python3 tools/generate_line_break.py \
  --line-break /path/to/LineBreak.txt \
  --derived-line-break /path/to/DerivedLineBreak.txt \
  --output src/line_break_data.zig
```

Both input files must come from the same Unicode release.
