#!/usr/bin/env bash
# CI's kit job (.github/workflows/ci.yml, on GitHub's Linux): a real Jellyfin
# with the made-up library, then JukeboxKit's build and every test against
# it — the same two scripts as on a developer's machine.
set -euo pipefail
cd "$(dirname "$0")/.."
dev/jellyfin-test-server.sh
dev/kit-test.sh
