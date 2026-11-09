#!/usr/bin/env bash
# CI's kit job (.github/workflows/ci.yml, on GitHub's Linux): a real Jellyfin
# with the made-up library and a real Navidrome on the same library, then
# JukeboxKit's build and every test against both — the same scripts as on a
# developer's machine. Jellyfin first: its script makes the library.
set -euo pipefail
cd "$(dirname "$0")/.."
dev/jellyfin-test-server.sh
dev/navidrome-test-server.sh
dev/kit-test.sh
