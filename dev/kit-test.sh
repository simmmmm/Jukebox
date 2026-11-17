#!/usr/bin/env bash
# JukeboxKit's build and tests on Linux, in Swift's own Docker image, beside
# the Jellyfin of dev/jellyfin-test-server.sh, the Navidrome of
# dev/navidrome-test-server.sh and the Emby of dev/emby-test-server.sh when
# they run (each server's integration tests skip themselves without it).
# The same as CI's kit job, which has no Emby.
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
if [[ -n ${JELLYFIN_URL:-} ]]; then
  # Another server on the Docker network "jukebox", such as the fake the
  # screenshots use: JELLYFIN_URL=http://fake-jellyfin:8096 dev/kit-test.sh
  net=(--network jukebox)
  env=(-e JELLYFIN_URL="$JELLYFIN_URL" -e JELLYFIN_USER="${JELLYFIN_USER:-test}"
       -e JELLYFIN_PASSWORD="${JELLYFIN_PASSWORD:-test}")
elif docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$server"; then
  net=(--network jukebox)
  env=(-e "JELLYFIN_URL=http://$host:8096" -e JELLYFIN_USER=test -e JELLYFIN_PASSWORD=test)
fi

# The Navidrome of dev/navidrome-test-server.sh, or another Subsonic server
# on the network: NAVIDROME_URL=http://gonic:80 dev/kit-test.sh
navidrome=${JUKEBOX_NAVIDROME_CONTAINER:-jukebox-navidrome}
navidrome_host=navidrome; [[ $navidrome == jukebox-navidrome ]] || navidrome_host=$navidrome
if [[ -n ${NAVIDROME_URL:-} ]]; then
  net=(--network jukebox)
  env+=(-e NAVIDROME_URL="$NAVIDROME_URL" -e NAVIDROME_USER="${NAVIDROME_USER:-test}"
        -e NAVIDROME_PASSWORD="${NAVIDROME_PASSWORD:-test}")
elif docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$navidrome"; then
  net=(--network jukebox)
  env+=(-e "NAVIDROME_URL=http://$navidrome_host:4533" -e NAVIDROME_USER=test -e NAVIDROME_PASSWORD=test)
fi

# The Emby of dev/emby-test-server.sh: EMBY_URL=http://other-emby:8096 dev/kit-test.sh
emby=${JUKEBOX_EMBY_CONTAINER:-jukebox-emby}
emby_host=emby; [[ $emby == jukebox-emby ]] || emby_host=$emby
if [[ -n ${EMBY_URL:-} ]]; then
  net=(--network jukebox)
  env+=(-e EMBY_URL="$EMBY_URL" -e EMBY_USER="${EMBY_USER:-test}" -e EMBY_PASSWORD="${EMBY_PASSWORD:-test}")
elif docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$emby"; then
  net=(--network jukebox)
  env+=(-e "EMBY_URL=http://$emby_host:8096" -e EMBY_USER=test -e EMBY_PASSWORD=test)
fi

if [[ ${1:-} == build ]]; then
  cmd=(swift build)
else
  # Each line out as it is written: into a pipe (CI's log) the tests' output
  # went in 4 kB blocks, so after a hang the log's last test started was not
  # the one that hung (14 November 2026).
  cmd=(stdbuf -oL swift test "$@")
fi

# .build in a volume of its own: the host's checkout stays clean, and a
# second run does not compile everything again.
docker run --rm "${net[@]}" "${env[@]}" -v "$PWD:/kit" -v "$volume:/kit/.build" -w /kit \
  "$IMAGE" "${cmd[@]}"

# The Plex of dev/plex-test-server.sh, after the rest, from inside its own
# network namespace (127.0.0.1): unclaimed, it answers without a token from
# itself and from its network's gateway only, and refused another container
# on that network with 401 whatever ALLOWED_NETWORKS said (measured, 17
# November 2026). Only when every test ran, or the filter names Plex.
plex=${JUKEBOX_PLEX_CONTAINER:-jukebox-plex}
if [[ ${1:-} != build ]] && docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$plex" \
  && { [[ " $* " != *" --filter "* ]] || [[ "$*" == *Plex* ]]; }; then
  docker run --rm --network "container:$plex" -e PLEX_URL=http://127.0.0.1:32400 \
    -v "$PWD:/kit" -v "$volume:/kit/.build" -w /kit "$IMAGE" stdbuf -oL swift test --filter PlexIntegration
fi
