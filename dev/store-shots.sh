#!/usr/bin/env bash
# The App Store's pictures, picked from a round of the screenshot walk
# (ci/screenshots.sh) on the `screenshots` branch into build/appstore/, in
# the order the listing shows them, checked against the sizes App Store
# Connect takes, and without the alpha channel it refuses.
#
#   dev/store-shots.sh [folder on the branch, default branches/store-walk]
#
# A platform the folder lacks comes from the branch's top (main's round).
# The round to pick from is a push of the branch `store-walk` (ci/app.sh):
# the Mac's window, the iPhone 17 Pro, the 13-inch iPad.
# No words over the pictures (docs/RELEASE.md, docs/design/tells.md).
# Needs ImageMagick.
set -euo pipefail
cd "$(dirname "$0")/.."
from=${1:-branches/store-walk}
out=build/appstore
git fetch -q origin screenshots
rm -rf "$out"

# pick <platform> <sizes, a grep -E pattern> <picture>...
pick() {
  local platform=$1 sizes=$2 n=0 name src size
  shift 2
  mkdir -p "$out/$platform"
  for name in "$@"; do
    n=$(( n + 1 ))
    src=$from/$platform/$name.png
    git cat-file -e "origin/screenshots:$src" 2> /dev/null || src=$platform/$name.png
    if ! git cat-file -e "origin/screenshots:$src" 2> /dev/null; then
      echo "MISSING $platform/$name" >&2; bad=1; continue
    fi
    git show "origin/screenshots:$src" | magick png:- -alpha off "$out/$platform/$(printf '%02d' $n)-${name#*-}.png"
    size=$(magick identify -format '%wx%h' "$out/$platform/$(printf '%02d' $n)-${name#*-}.png")
    if ! grep -qxE "$sizes" <<< "$size"; then
      echo "WRONG SIZE $src: $size, the store takes $sizes" >&2; bad=1
    fi
    echo "$platform $(printf '%02d' $n) $size  $src"
  done
}

bad=0
# Home with a station on the air first: the store shows the first three
# before anyone taps.
# The Pro's size is the one App Store Connect requires; a Pro Max round
# (SHOTS_IPHONE, ci/app.sh) gives the optional large set.
pick iphone '1206x2622|1179x2556|1320x2868|1290x2796|1260x2736' \
  18-home-playing 19-now-playing 24-station-on-air 13-album 21-queue 23-radio-on-air 12-albums
pick ipad '2752x2064|2732x2048' \
  09-home-playing 10b-now-playing 14-radio-up-next 10-album-up-next 12-now-playing-lyrics 04-albums 03-station
pick mac '1280x800|1440x900|2560x1600|2880x1800' \
  01-home-playing 02-albums 03-album-up-next 04-now-playing 05-now-playing-lyrics 06-radio-on-air 07-station
exit $bad
