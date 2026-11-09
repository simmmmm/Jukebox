#!/usr/bin/env bash
# A real Navidrome in Docker on the same made-up library as
# dev/jellyfin-test-server.sh (the library is that script's to make), for
# JukeboxKit's Subsonic tests (dev/kit-test.sh passes NAVIDROME_URL when it
# runs) and for measuring the Subsonic API (docs/SERVERS.md). Idempotent: a
# second run keeps what is there.
#
#   dev/navidrome-test-server.sh          start, set up, print the URL
#   dev/navidrome-test-server.sh --reset  throw Navidrome's database away first
#
# User "test", password "test" (the first user Navidrome makes is its admin).
# The server is "navidrome" on the Docker network "jukebox" (port 4533), and
# localhost:4533 from here. Its database is in ~/.cache/jukebox-test-navidrome,
# apart from the library, so Jellyfin's --reset leaves it be (and the play
# counts the tests make live there until this script's --reset).
#
# The photographer, 8 November 2026: "Moet eigenlijk ook voor navidrome en
# die ander" — Jukebox for Navidrome and the other Subsonic servers too.
set -euo pipefail
cd "$(dirname "$0")/.."

IMAGE=deluan/navidrome:latest
LIBRARY=${JUKEBOX_TEST_DATA:-$HOME/.cache/jukebox-test}/media/music
DATA=${JUKEBOX_NAVIDROME_DATA:-$HOME/.cache/jukebox-test-navidrome}
NAME=${JUKEBOX_NAVIDROME_CONTAINER:-jukebox-navidrome}
PORT=${JUKEBOX_NAVIDROME_PORT:-4533}
URL=http://localhost:$PORT

if [[ ${1:-} == --reset ]]; then
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  rm -rf "$DATA"
fi

# One library, two servers.
if [[ ! -d $LIBRARY ]]; then
  echo "No test library at $LIBRARY yet: dev/jellyfin-test-server.sh makes it." >&2
  exit 1
fi
mkdir -p "$DATA"
docker network inspect jukebox >/dev/null 2>&1 || docker network create jukebox >/dev/null

# A container that runs but keeps its database elsewhere (an older version
# of this script put it beside the library) is made again.
if docker ps --format '{{.Names}}' | grep -qx "$NAME"; then
  mounted=$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Source}}{{end}}{{end}}' "$NAME")
  [[ $mounted == "$DATA" ]] || docker rm -f "$NAME" >/dev/null
fi

# What Navidrome said, when something here fails (CI's log has it then).
trap 'echo "--- docker logs $NAME" >&2; docker logs --tail 40 "$NAME" >&2 2>&1 || true' ERR

# The image, pulled again a few times: a fresh runner pulls it, and a pull
# can fail on the way.
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  for i in 1 2 3 4; do docker pull -q "$IMAGE" >/dev/null && break; (( i == 4 )) && exit 1; sleep $((i * 5)); done
fi

alias=navidrome; [[ $NAME == jukebox-navidrome ]] || alias=$NAME
if ! docker ps --format '{{.Names}}' | grep -qx "$NAME"; then
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  # No Last.fm, Spotify, Deezer or ListenBrainz: the made-up artists are not
  # there, and a test must not need the internet. What Navidrome answers
  # without its agents is what docs/SERVERS.md measures as "a server that
  # has nothing to go on". No scheduled scans: the library does not change.
  # -u: the library under ~/.cache is this user's; Navidrome writes only /data.
  docker run -d --name "$NAME" --network jukebox --network-alias "$alias" \
    -u "$(id -u):$(id -g)" -p "$PORT:4533" \
    -e ND_LOGLEVEL=warn -e ND_AGENTS="" -e ND_LASTFM_ENABLED=false -e ND_SPOTIFY_ID="" \
    -e ND_DEEZER_ENABLED=false -e ND_LISTENBRAINZ_ENABLED=false -e ND_ENABLEINSIGHTSCOLLECTOR=false \
    -e ND_SCANNER_SCHEDULE=0 -e ND_SCANNER_SCANONSTARTUP=true \
    -v "$DATA:/data" -v "$LIBRARY:/music:ro" \
    "$IMAGE" >/dev/null
fi

# A call, again each second until it succeeds, for a minute.
again() {
  local _
  for _ in $(seq 1 60); do "$@" 2>/dev/null && return 0; sleep 1; done
  "$@"
}
# A value from an answer, or the default when there is no answer to read
# (the server busy or restarting): one look that fails is one look, not
# the end of the script.
json() {
  python3 -c "import json,sys
try:
    d=json.load(sys.stdin)['subsonic-response']; print($1)
except Exception:
    print('${2:-}')"
}

# Up: the Subsonic ping answers (with error 10, unauthenticated) once the
# server listens.
again curl -sf "$URL/rest/ping.view?f=json" -o /dev/null

# The first user, through Navidrome's own API, not Subsonic's: a fresh
# server has no user, and its web app makes the first one here. It answers
# 403 once there is one, which is fine.
curl -s -X POST "$URL/auth/createAdmin" -H 'Content-Type: application/json' \
  -d '{"username":"test","password":"test"}' -o /dev/null || true

# Token authentication, as Jukebox signs in: t = md5(password + salt).
SALT=jukeboxtests
TOKEN=$(printf '%s' "test$SALT" | md5sum | cut -d' ' -f1)
Q="u=test&t=$TOKEN&s=$SALT&v=1.16.1&c=JukeboxTests&f=json"
rest() { curl -sf "$URL/rest/$1.view?$Q${2:+&$2}"; }

ping_ok() { rest ping | grep -q '"status":"ok"'; }
again ping_ok

# Until the scan has found every file and settled: not scanning, every
# track counted and listed by an empty search3 (what the kit's allTracks
# reads), and the numbers of albums and artists unchanged since the last
# look. Started before there was a user, the first scan can have run with
# nobody to see it: a scan is asked for again while tracks are missing.
want=$(find "$LIBRARY" -type f \( -name '*.mp3' -o -name '*.flac' -o -name '*.m4a' \) | wc -l)
before=""
have=0 listed=0 albums=0 artists=0 settled=no
for i in $(seq 1 120); do
  status=$(rest getScanStatus || true)
  scanning=$(json 'd["scanStatus"]["scanning"]' unknown <<<"$status")
  have=$(json 'd["scanStatus"].get("count", 0)' 0 <<<"$status")
  listed=$(rest search3 "query=&artistCount=0&albumCount=0&songCount=5000" \
    | json 'len(d.get("searchResult3", {}).get("song", []))' 0 || true)
  albums=$(rest getAlbumList2 "type=alphabeticalByName&size=500" | json 'len(d.get("albumList2", {}).get("album", []))' 0 || true)
  artists=$(rest getArtists | json 'sum(len(i.get("artist", [])) for i in d.get("artists", {}).get("index", []))' 0 || true)
  now="$listed/$albums/$artists"
  if [[ $scanning == False && $have -ge $want && $listed -ge $want && $now == "$before" ]]; then
    settled=yes
    break
  fi
  before=$now
  if [[ $scanning == False && $listed -lt $want ]] && (( i % 10 == 1 )); then
    rest startScan >/dev/null || true
  fi
  sleep 2
done

if [[ $settled != yes ]]; then
  echo "Navidrome's scan did not settle in 4 minutes: scanning $scanning, $have counted, $listed of $want listed," \
    "$albums albums, $artists artists" >&2
  docker logs --tail 40 "$NAME" >&2 2>&1 || true
  exit 1
fi

version=$(rest ping | json 'd.get("serverVersion")' unknown)
echo "Navidrome $version at $URL (Docker: http://$alias:4533): $listed of $want tracks listed," \
  "$albums albums, $artists artists, user test/test"
