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
URL=http://localhost:8096
AUTH='MediaBrowser Client="JukeboxTests", Device="Linux", DeviceId="jukebox-tests", Version="1.0"'

if [[ ${1:-} == --reset ]]; then
  docker rm -f jukebox-jellyfin >/dev/null 2>&1 || true
  rm -rf "$DATA"
fi
mkdir -p "$DATA/media" "$DATA/config" "$DATA/cache"
docker network inspect jukebox >/dev/null 2>&1 || docker network create jukebox >/dev/null

if [[ ! -d $DATA/media/music ]]; then
  python3 dev/make-test-library.py > "$DATA/gen.sh"
  docker run --rm --entrypoint /bin/bash -v "$DATA/media:/media" -v "$DATA/gen.sh:/gen.sh:ro" \
    "$IMAGE" /gen.sh
fi

if ! docker ps --format '{{.Names}}' | grep -qx jukebox-jellyfin; then
  docker rm -f jukebox-jellyfin >/dev/null 2>&1 || true
  docker run -d --name jukebox-jellyfin --network jukebox --network-alias jellyfin \
    -p 8096:8096 -v "$DATA/config:/config" -v "$DATA/cache:/cache" -v "$DATA/media:/media:ro" \
    "$IMAGE" >/dev/null
fi

for _ in $(seq 1 90); do
  curl -sf "$URL/System/Info/Public" >/dev/null 2>&1 && break
  sleep 1
done
curl -sf "$URL/System/Info/Public" >/dev/null

json() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }

done_already=$(curl -sf "$URL/System/Info/Public" | json 'd.get("StartupWizardCompleted")')
if [[ $done_already != True ]]; then
  # The wizard's own order. The first GET of /Startup/User makes the user.
  curl -sf -X POST "$URL/Startup/Configuration" -H 'Content-Type: application/json' \
    -d '{"UICulture":"en-US","MetadataCountryCode":"US","PreferredMetadataLanguage":"en"}'
  curl -sf "$URL/Startup/User" >/dev/null
  curl -sf -X POST "$URL/Startup/User" -H 'Content-Type: application/json' \
    -d '{"Name":"test","Password":"test"}'
  curl -sf -X POST "$URL/Startup/RemoteAccess" -H 'Content-Type: application/json' \
    -d '{"EnableRemoteAccess":true,"EnableAutomaticPortMapping":false}'
  curl -sf -X POST "$URL/Startup/Complete"
fi

TOKEN=$(curl -sf -X POST "$URL/Users/AuthenticateByName" -H 'Content-Type: application/json' \
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
echo "Jellyfin at $URL (Docker: http://jellyfin:8096): $have of $want tracks, user test/test, user id $USER_ID"
