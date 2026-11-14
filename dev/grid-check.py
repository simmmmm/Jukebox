#!/usr/bin/env python3
"""Every distance and size of a screen on the 4-point grid, on the iPhone and
on Linux: 4, 8, 12, 16, 24, 32 and their multiples ("zorg dat alles past op
een 4pt grid", the photographer, 14 November 2026). Lists the ones that are
not, and fails on any.

    dev/grid-check.py

Looked at: spacing, padding, margins, widths and heights in Jukebox/ (SwiftUI)
and Linux/App (GTK, and its CSS). Not looked at: what is drawn in its own
units (the mark, a station's art, the sleeve and its record, Now Playing's
ground), radii and font sizes. A line that says `grid-ok`, or follows one
that does, is let be: it says there why (a hairline is a pixel; the system's
own grabber is 36 by 5).
"""
import glob, os, re, sys

os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
DRAWN = ("ArchMark", "StationArtwork", "SleeveRecord", "NowPlayingGround", "TurntableMeasures", "ArtMeasures",
         "Drawings")
MEASURE = re.compile(
    r"(?:spacing: |\.padding\((?:[^)]*, )?|\.frame\((?:min|max|ideal)?[wW]idth: |[hH]eight: |width: "
    r"|\.offset\([xy]: |min(?:Height|Width): |max(?:Height|Width): |horizontal: |vertical: "
    r"|margins\(|margin_(?:top|bottom|start|end)\(\w+, |static let \w+: CGFloat = "
    r"|(?:padding|min-height|margin): )(-?[0-9]+(?:\.[0-9]+)?(?:px(?: [0-9]+px)*)?)")

off = []
for path in sorted(glob.glob("Jukebox/**/*.swift", recursive=True) + glob.glob("Linux/App/*.swift")):
    if any(name in path for name in DRAWN):
        continue
    previous = ""
    for number, line in enumerate(open(path), 1):
        allowed = "grid-ok" in line or "grid-ok" in previous
        previous = line
        if allowed:
            continue
        for match in MEASURE.finditer(line):
            values = [float(v) for v in re.findall(r"-?[0-9]+(?:\.[0-9]+)?", match.group(1))]
            if any(v % 4 for v in values):
                off.append(f"{path}:{number}: {match.group(0).strip()}")

if off:
    print("\n".join(off))
    sys.exit(f"{len(off)} not on the 4-point grid")
print("every measure on the 4-point grid")
