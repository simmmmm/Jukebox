#!/usr/bin/env bash
# The asset catalog's AccentColor, which Xcode reads before any code runs,
# against Tokens.swift's accent pair (Copper by day, Glow by night): the one
# copy of a token outside Tokens.swift, kept equal (docs/design/SYSTEM.md).
# ci/app.sh runs it before building. Plain sed and awk: the Mac's grep has
# no -P.
set -euo pipefail
cd "$(dirname "$0")/.."
hex() { sed -n "s/.*static let $1: UInt32 = 0x\([0-9A-F]\{6\}\).*/\1/p" Jukebox/Components/Tokens.swift; }
want="$(hex copper) $(hex glow)"
# Each colour's red, green and blue (0 to 1) as hex, day first.
got=$(awk -F'"' '/"components"/ {
        for (i = 1; i < NF; i++) {
          if ($i == "red") r = $(i + 2); if ($i == "green") g = $(i + 2); if ($i == "blue") b = $(i + 2)
        }
        out = out sprintf("%s%02X%02X%02X", (out == "" ? "" : " "), int(r * 255 + 0.5), int(g * 255 + 0.5), int(b * 255 + 0.5))
      } END { print out }' Jukebox/Resources/Assets.xcassets/AccentColor.colorset/Contents.json)
if [[ $got != "$want" ]]; then
  echo "AccentColor is $got, Tokens.swift's accent $want: make them equal" >&2
  exit 1
fi
echo "AccentColor equals Tokens.accent ($want)"
