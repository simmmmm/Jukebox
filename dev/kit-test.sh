#!/usr/bin/env bash
# JukeboxKit's build and tests on Linux, in Swift's own Docker image, beside
# the Jellyfin of dev/jellyfin-test-server.sh when it runs (the integration
# tests skip themselves without it). The same as CI's kit job.
#
#   dev/kit-test.sh                 build and every test
#   dev/kit-test.sh build           build only
#   dev/kit-test.sh --filter Radio  the tests whose name has "Radio"
#
# KIT_DIR=/some/copy/JukeboxKit dev/kit-test.sh  tests a copy of the package
# (each agent of a parallel round has its own), with a .build of its own.
set -euo pipefail
cd "${KIT_DIR:-$(dirname "$0")/../JukeboxKit}"
volume=jukebox-kit-build-$(printf '%s' "$PWD" | cksum | cut -d' ' -f1)

IMAGE=swift:6.2-noble
net=()
env=()
# JUKEBOX_TEST_CONTAINER: the second server of dev/jellyfin-test-server.sh.
server=${JUKEBOX_TEST_CONTAINER:-jukebox-jellyfin}
host=jellyfin; [[ $server == jukebox-jellyfin ]] || host=$server
if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$server"; then
  net=(--network jukebox)
  env=(-e JELLYFIN_URL=http://$host:8096 -e JELLYFIN_USER=test -e JELLYFIN_PASSWORD=test)
fi

if [[ ${1:-} == build ]]; then
  cmd=(swift build)
else
  cmd=(swift test "$@")
fi

# .build in a volume of its own: the host's checkout stays clean, and a
# second run does not compile everything again.
docker run --rm "${net[@]}" "${env[@]}" -v "$PWD:/kit" -v "$volume:/kit/.build" -w /kit \
  "$IMAGE" "${cmd[@]}"
