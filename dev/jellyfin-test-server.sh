#!/usr/bin/env bash
# A real Jellyfin in Docker with a small made-up music library
# (dev/make-test-library.py), set up through the API the way the web wizard
# does it, for JukeboxKit's integration tests (dev/kit-test.sh) and for
# measuring the radio. Idempotent: a second run keeps what is there.
#
#   dev/jellyfin-test-server.sh          start, set up, print the URL
#   dev/jellyfin-test-server.sh --reset  throw the server and library away first
#
# User "test", password "test". The server is "jellyfin" on the Docker network
# "jukebox" (port 8096), and localhost:8096 from here.
set -euo pipefail
cd "$(dirname "$0")/.."

IMAGE=jellyfin/jellyfin:latest
DATA=${JUKEBOX_TEST_DATA:-$HOME/.cache/jukebox-test}
# Another name and port for a second, fresh server beside the usual one.
NAME=${JUKEBOX_TEST_CONTAINER:-jukebox-jellyfin}
PORT=${JUKEBOX_TEST_PORT:-8096}
URL=http://localhost:$PORT
AUTH='MediaBrowser Client="JukeboxTests", Device="Linux", DeviceId="jukebox-tests", Version="1.0"'

if [[ ${1:-} == --reset ]]; then
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  rm -rf "$DATA"
fi
mkdir -p "$DATA/media" "$DATA/config" "$DATA/cache"
docker network inspect jukebox >/dev/null 2>&1 || docker network create jukebox >/dev/null

if [[ ! -d $DATA/media/music ]]; then
  python3 dev/make-test-library.py > "$DATA/gen.sh"
  docker run --rm --entrypoint /bin/bash -v "$DATA/media:/media" -v "$DATA/gen.sh:/gen.sh:ro" \
    "$IMAGE" /gen.sh
fi

if ! docker ps --format '{{.Names}}' | grep -qx "$NAME"; then
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  alias=jellyfin; [[ $NAME == jukebox-jellyfin ]] || alias=$NAME
  docker run -d --name "$NAME" --network jukebox --network-alias "$alias" \
    -p "$PORT:8096" -v "$DATA/config:/config" -v "$DATA/cache:/cache" -v "$DATA/media:/media:ro" \
    "$IMAGE" >/dev/null
fi

# A call, again each second until it succeeds, for a minute. A fresh
# Jellyfin answers /System/Info/Public within a second or two of starting,
# before the wizard's routes take requests (seen on GitHub's Linux: the
# first POST /Startup/Configuration failed three seconds in).
again() {
  local _
  for _ in $(seq 1 60); do "$@" 2>/dev/null && return 0; sleep 1; done
  "$@"
}

# Up, and saying whether its wizard is done (an answer without it is
# from a server still starting).
wizard_known() { curl -sf "$URL/System/Info/Public" | grep -q StartupWizardCompleted; }
again wizard_known

json() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }

done_already=$(curl -sf "$URL/System/Info/Public" | json 'd.get("StartupWizardCompleted")')
if [[ $done_already != True ]]; then
  # The wizard's own order. The first GET of /Startup/User makes the user.
  again curl -sf -X POST "$URL/Startup/Configuration" -H 'Content-Type: application/json' \
    -d '{"UICulture":"en-US","MetadataCountryCode":"US","PreferredMetadataLanguage":"en"}'
  again curl -sf "$URL/Startup/User" -o /dev/null
  again curl -sf -X POST "$URL/Startup/User" -H 'Content-Type: application/json' \
    -d '{"Name":"test","Password":"test"}'
  again curl -sf -X POST "$URL/Startup/RemoteAccess" -H 'Content-Type: application/json' \
    -d '{"EnableRemoteAccess":true,"EnableAutomaticPortMapping":false}'
  again curl -sf -X POST "$URL/Startup/Complete"
fi

TOKEN=$(again curl -sf -X POST "$URL/Users/AuthenticateByName" -H 'Content-Type: application/json' \
  -H "Authorization: $AUTH" -d '{"Username":"test","Pw":"test"}' | json 'd["AccessToken"]')
H=(-H "Authorization: $AUTH, Token=\"$TOKEN\"")

if ! curl -sf "${H[@]}" "$URL/Library/VirtualFolders" | grep -q '"Music"'; then
  curl -sf -X POST "${H[@]}" -H 'Content-Type: application/json' \
    "$URL/Library/VirtualFolders?name=Music&collectionType=music&paths=%2Fmedia%2Fmusic&refreshLibrary=true" \
    -d '{"LibraryOptions":{"EnableRealtimeMonitor":false,"PathInfos":[{"Path":"/media/music"}]}}'
fi

# Wait until the scan has found every file and settled.
want=$(find "$DATA/media/music" -type f \( -name '*.mp3' -o -name '*.flac' -o -name '*.m4a' \) | wc -l)
USER_ID=$(curl -sf "${H[@]}" "$URL/Users/Me" | json 'd["Id"]')
# The first scan, right after the wizard, can finish having found nothing
# (seen with Jellyfin 12.4): a refresh after a while starts it again.
for i in $(seq 1 180); do
  have=$(curl -sf "${H[@]}" "$URL/Items?userId=$USER_ID&IncludeItemTypes=Audio&Recursive=true&Limit=0" | json 'd["TotalRecordCount"]')
  [[ $have -ge $want ]] && break
  (( i % 15 == 0 )) && curl -sf -X POST "${H[@]}" "$URL/Library/Refresh"
  sleep 2
done
# Every track found is not the scan done: on a fresh server (GitHub's
# Linux) the genres, the album artists and the covers came in after the
# count was right, and the tests that started then failed on them. So:
# until the scan task is idle, every track has its genres, and the number
# of album artists has held for one more look.
artists_before=-1
for _ in $(seq 1 120); do
  state=$(curl -sf "${H[@]}" "$URL/ScheduledTasks?isHidden=false" \
    | json '[t["State"] for t in d if t.get("Key") == "RefreshLibrary"][0]' || echo unknown)
  bare=$(curl -sf "${H[@]}" "$URL/Items?userId=$USER_ID&IncludeItemTypes=Audio&Recursive=true&Fields=Genres" \
    | json 'sum(1 for i in d["Items"] if not i.get("Genres"))' || echo -1)
  artists=$(curl -sf "${H[@]}" "$URL/Artists/AlbumArtists?userId=$USER_ID&Limit=0" | json 'd["TotalRecordCount"]' || echo -1)
  [[ $state == Idle && $bare == 0 && $artists -gt 0 && $artists == "$artists_before" ]] && break
  artists_before=$artists
  sleep 3
done
echo "scan: $state, tracks without genres: $bare, album artists: $artists"

echo "Jellyfin at $URL (Docker: http://${alias:-jellyfin}:8096): $have of $want tracks, user test/test, user id $USER_ID"
