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
# Tagged by the Dockerfile itself: a package added there (libsoup, 18
# November 2026) builds a new image rather than using the old one; the
# plain name follows the newest, for dev/linux-screens.sh.
image=jukebox-linux-build:$(cksum < dev/linux/Dockerfile | cut -d" " -f1)
if ! docker image inspect "$image" >/dev/null 2>&1; then
  docker build -t "$image" -t jukebox-linux-build dev/linux
fi
config=${1:-debug}
# .build-linux is on the host (so the binary can be run there), owned by
# whoever runs this, not by the container's root; and outside the package
# in the container (/build): inside it, SwiftPM 6.2 fails every build after
# the first with "unknown build description".
mkdir -p .build-linux
# Jukebox's own Last.fm key, from the environment or .env, built in as
# Linux/App/AppKeys.swift, which .gitignore keeps out: the repository is
# public. The photographer, 21 November 2026: "Ik denk dat een eigen last fm
# verstandiger is". Always written, empty without a key, so the build never
# lacks the file; rewritten only when it changes, so it costs no rebuild.
# Only its length is said.
key=${LASTFM_APP_KEY:-$(sed -n 's/^LASTFM_APP_KEY=//p' .env 2>/dev/null | tail -1)}
[[ $key =~ ^[A-Za-z0-9]*$ ]] || { echo "LASTFM_APP_KEY: letters and digits only" >&2; exit 1; }
keys="// Written by dev/linux-build.sh from .env; not in git.
let lastFMAppKey = \"$key\""
if [[ ! -f Linux/App/AppKeys.swift || $(< Linux/App/AppKeys.swift) != "$keys" ]]; then
  printf '%s\n' "$keys" > Linux/App/AppKeys.swift
fi
echo "Last.fm app key: ${#key} characters"
docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -v "$PWD:/src" -v "$PWD/.build-linux:/build" \
  -w /src "$image" \
  swift build -c "$config" --static-swift-stdlib --scratch-path /build
echo ".build-linux/$config/Jukebox"
