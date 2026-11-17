#!/usr/bin/env bash
# A real Plex Media Server in Docker on the same made-up library as
# dev/jellyfin-test-server.sh (that script makes it), for JukeboxKit's Plex
# tests (dev/kit-test.sh passes PLEX_URL when it runs). Idempotent: a second
# run keeps what is there.
#
#   dev/plex-test-server.sh          start, set up, print the URL
#   dev/plex-test-server.sh --reset  throw Plex's database away first
#
# The server is never claimed: claiming takes a plex.tv account, and the
# tests must not need one. Unclaimed, it answers without a token, as its
# owner, what comes from itself and from its network's gateway (this
# machine); another container on its network got 401 (measured), so
# dev/kit-test.sh runs the Plex tests inside its network namespace.
#
# It runs on an internal Docker network of its own, "jukebox-plex", with no
# way out: a Plex server calls plex.tv by itself (an unclaimed one asked
# servers.plex.tv a dozen times in its first minute, 17 November 2026), and
# fetches its converters from there. So here it converts only what needs no
# download (an MP3 copied at a cap above its rate). Its address on that
# network is what this prints, for this machine.
set -euo pipefail
cd "$(dirname "$0")/.."

IMAGE=plexinc/pms-docker:latest
LIBRARY=${JUKEBOX_TEST_DATA:-$HOME/.cache/jukebox-test}/media/music
DATA=${JUKEBOX_PLEX_DATA:-$HOME/.cache/jukebox-test-plex}
NAME=${JUKEBOX_PLEX_CONTAINER:-jukebox-plex}
NETWORK=${JUKEBOX_PLEX_NETWORK:-jukebox-plex}

if [[ ${1:-} == --reset ]]; then
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  # Plex leaves a few folders of root's: removed from inside a container.
  [[ -d $DATA ]] && docker run --rm --entrypoint /bin/rm -v "$DATA:/data" "$IMAGE" -rf /data/config /data/transcode
fi

if [[ ! -d $LIBRARY ]]; then
  echo "No test library at $LIBRARY yet: dev/jellyfin-test-server.sh makes it." >&2
  exit 1
fi
mkdir -p "$DATA/config" "$DATA/transcode"
docker network inspect "$NETWORK" >/dev/null 2>&1 || docker network create --internal "$NETWORK" >/dev/null

trap 'echo "--- docker logs $NAME" >&2; docker logs --tail 40 "$NAME" >&2 2>&1 || true' ERR

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  for i in 1 2 3 4; do docker pull -q "$IMAGE" >/dev/null && break; (( i == 4 )) && exit 1; sleep $((i * 5)); done
fi

if ! docker ps --format '{{.Names}}' | grep -qx "$NAME"; then
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  # --dns at the container's own loopback: a name outside fails at once,
  # where on the internal network alone each lookup waited 5 s and the
  # music agent's scan took minutes an album.
  docker run -d --name "$NAME" --network "$NETWORK" --network-alias plex --dns 127.0.0.1 \
    -e TZ=UTC -e PLEX_UID="$(id -u)" -e PLEX_GID="$(id -g)" \
    -e ALLOWED_NETWORKS=172.16.0.0/12,10.0.0.0/8,192.168.0.0/16 \
    -v "$DATA/config:/config" -v "$DATA/transcode:/transcode" -v "$LIBRARY:/music:ro" \
    "$IMAGE" >/dev/null
fi

IP=$(docker inspect -f "{{(index .NetworkSettings.Networks \"$NETWORK\").IPAddress}}" "$NAME")
URL=http://$IP:32400
J=(-sf -H 'Accept: application/json')

# Up once /identity no longer says it is starting.
for _ in $(seq 1 120); do
  curl -sf "$URL/identity" 2>/dev/null | grep -q machineIdentifier \
    && ! curl -sf "$URL/identity" | grep -q startState && break
  sleep 1
done

# The music library, with the agent that reads only the files ("Personal
# Media Artists"): 358 songs in seconds. Plex's own music agent reads the
# genres too (measured: an album's "Pop", "Electronic"), but offline it
# waited a minute an artist for its fingerprints and converters, 23 minutes
# for this library. So this server has no genres; the tests ask for none.
if ! curl "${J[@]}" "$URL/library/sections" | grep -q '"title":"Music"'; then
  curl "${J[@]}" -X POST -o /dev/null \
    "$URL/library/sections?name=Music&type=artist&agent=com.plexapp.agents.none&scanner=Plex%20Music%20Scanner&language=xn&location=%2Fmusic"
fi
SECTION=$(curl "${J[@]}" "$URL/library/sections" | jq -er '.MediaContainer.Directory[] | select(.title == "Music") | .key')

# Every file found, and the scan over.
want=$(find "$LIBRARY" -type f \( -name '*.mp3' -o -name '*.flac' -o -name '*.m4a' \) | wc -l)
for _ in $(seq 1 600); do
  have=$(curl "${J[@]}" "$URL/library/sections/$SECTION/all?type=10&X-Plex-Container-Start=0&X-Plex-Container-Size=0" \
    | jq -r '.MediaContainer.totalSize // 0')
  busy=$(curl "${J[@]}" "$URL/library/sections" | jq -r '[.MediaContainer.Directory[].refreshing] | any')
  [[ $have == "$want" && $busy == false ]] && break
  sleep 1
done
if [[ $have != "$want" ]]; then
  echo "Plex found $have of $want songs." >&2
  exit 1
fi
echo "$URL (section $SECTION, $have songs)"
