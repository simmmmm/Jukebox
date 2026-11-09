#!/usr/bin/env bash
# CI's kit job (.github/workflows/ci.yml, on GitHub's Linux): a real Jellyfin
# with the made-up library and a real Navidrome on the same library, then
# JukeboxKit's build and every test against both — the same scripts as on a
# developer's machine. Jellyfin first: its script makes the library.
set -euo pipefail
cd "$(dirname "$0")/.."
dev/jellyfin-test-server.sh
dev/navidrome-test-server.sh
# One test at a time: on GitHub's runner, three tests talking to the two
# real servers at once never finished — Linux's URLSession stopped answering
# all of them (run 51, 9 November 2026: the job ran out its 30 minutes after
# 8 of them); here, one at a time, the whole suite takes 2.5 minutes.
dev/kit-test.sh --no-parallel
