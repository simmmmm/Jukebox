#!/usr/bin/env bash
# Every distance and size of a screen on the 4-point grid, on the iPhone and
# on Linux: 4, 8, 12, 16, 24, 32 and their multiples ("zorg dat alles past op
# een 4pt grid", the photographer, 14 November 2026). Lists the ones that are
# not, and fails on any.
#
#   dev/grid-check.sh
#
# Looked at: spacing, padding, margins, widths and heights in Jukebox/ (SwiftUI)
# and Linux/App (GTK, and its CSS). Not looked at: what is drawn in its own
# units (the mark, a station's art, the sleeve and its record, Now Playing's
# ground), radii and font sizes. A line that says `grid-ok`, or follows one
# that does, is let be: it says there why (a hairline is a pixel; the system's
# own grabber is 36 by 5). Needs GNU grep (-P), as Linux has.
set -euo pipefail
cd "$(dirname "$0")/.."
drawn='ArchMark|StationArtwork|SleeveRecord|NowPlayingGround|TurntableMeasures|ArtMeasures|Drawings'
# What comes before a measure, then the measure: one number, or CSS's "12px 8px".
measure='(?:spacing: |\.padding\((?:[^)]*, )?|\.frame\((?:min|max|ideal)?[wW]idth: |[hH]eight: |width: '
measure+='|\.offset\([xy]: |min(?:Height|Width): |max(?:Height|Width): |horizontal: |vertical: '
measure+='|margins\(|margin_(?:top|bottom|start|end)\(\w+, |static let \w+: CGFloat = '
measure+='|(?:padding|min-height|margin): )(-?[0-9]+(?:\.[0-9]+)?(?:px(?: [0-9]+px)*)?)'

off=$(
  { find Jukebox -name '*.swift'; ls Linux/App/*.swift; } | LC_ALL=C sort | { grep -Ev "$drawn" || true; } \
    | while IFS= read -r path; do
        # The grid-ok lines and the ones after them blanked, so the numbers stay.
        awk '{ ok = index($0, "grid-ok") > 0; print (ok || was) ? "" : $0; was = ok }' "$path" \
          | { grep -noP "$measure" || true; } | sed "s|^|$path:|"
      done \
    | awk '{
        # path:line:what was found; the measure is its end.
        split($0, part, ":")
        where = part[1] ":" part[2]
        found = substr($0, length(where) + 2)
        match(found, /-?[0-9]+(\.[0-9]+)?(px( [0-9]+px)*)?$/)
        value = substr(found, RSTART, RLENGTH)
        gsub(/px/, "", value)
        n = split(value, numbers, " ")
        for (i = 1; i <= n; i++) if (numbers[i] % 4) { print where ": " found; break }
      }'
)
if [[ -n $off ]]; then
  echo "$off"
  echo "$(wc -l <<< "$off") not on the 4-point grid" >&2
  exit 1
fi
echo "every measure on the 4-point grid"
