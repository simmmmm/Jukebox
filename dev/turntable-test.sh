#!/usr/bin/env bash
# Now Playing's arithmetic on Linux, in Swift's own Docker image — the album's
# side, the land under the page (sketch D2), the sleeve's layout, the motion's
# numbers and the clock: Jukebox/NowPlaying/TurntableMeasures.swift
# (Foundation only) compiled as it is, with the app's settings (the main actor
# by default, approachable concurrency), and run against
# dev/turntable-test.swift. The rest of the app is SwiftUI and is built only
# on CI's Mac.
#
#   dev/turntable-test.sh
set -euo pipefail
cd "$(dirname "$0")/.."

# main.swift: swiftc runs top-level code only from a file of that name.
docker run --rm -v "$PWD":/w:ro -w /tmp swift:6.2-noble bash -c '
  cp /w/dev/turntable-test.swift main.swift
  swiftc -default-isolation MainActor \
    -enable-upcoming-feature InferIsolatedConformances \
    -enable-upcoming-feature NonisolatedNonsendingByDefault \
    /w/Jukebox/NowPlaying/TurntableMeasures.swift main.swift -o turntable-test
  ./turntable-test'
