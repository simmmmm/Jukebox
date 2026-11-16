#!/usr/bin/env bash
# Jukebox for Linux, built in Docker (dev/linux/Dockerfile: Swift 6.2 on
# Ubuntu 24.04 with GTK 4, libadwaita 1.5 and GStreamer), as the kit is
# tested there (dev/kit-test.sh): no Swift is needed on the machine itself.
#
#   dev/linux-build.sh            debug build  -> .build-linux/debug/Jukebox
#   dev/linux-build.sh release    release build
#
# Swift's own libraries are linked in (--static-swift-stdlib), so the binary
# runs outside the container on any Linux with GTK 4.14 and libadwaita 1.5
# or newer.
set -euo pipefail
cd "$(dirname "$0")/.."
docker image inspect jukebox-linux-build >/dev/null 2>&1 || docker build -t jukebox-linux-build dev/linux
config=${1:-debug}
# .build-linux is on the host (so the binary can be run there), owned by
# whoever runs this, not by the container's root; and outside the package
# in the container (/build): inside it, SwiftPM 6.2 fails every build after
# the first with "unknown build description".
mkdir -p .build-linux
docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -v "$PWD:/src" -v "$PWD/.build-linux:/build" \
  -w /src jukebox-linux-build \
  swift build -c "$config" --static-swift-stdlib --scratch-path /build
echo ".build-linux/$config/Jukebox"
