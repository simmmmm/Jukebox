#!/usr/bin/env bash
# A real Jellyfin in Docker with a small made-up music library
# (dev/test-library.tsv), set up through the API the way the web wizard
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

# The made-up library, a row a song in dev/test-library.tsv: tagged tones in
# the formats a real library has (MP3, FLAC, AAC in M4A), with album covers,
# so the tests run against a real Jellyfin and the radio can be measured on
# a library with genres, eras and artists that belong together (in clusters
# on purpose: the radio is measured by whether it stays inside one and
# drifts to a neighbour). Made with the image's own ffmpeg. The table was
# drawn once, at random from a fixed seed; the tests and docs/RADIO.md's
# measurements count on it as it is.
make_library=$(cat <<'SH'
set -euo pipefail
FF=/usr/lib/jellyfin-ffmpeg/ffmpeg
mkdir -p /media/music
folder=
while IFS=$'\t' read -r artist album year genres cover format track tracks title performers frequency seconds; do
  [[ $artist == '#'* ]] && continue
  case $format in
    mp3) codec=(-c:a libmp3lame -b:a 128k) ;;
    flac) codec=(-c:a flac) ;;
    m4a) codec=(-c:a aac -b:a 128k) ;;
  esac
  if [[ $folder != "/media/music/$artist/$year - $album" ]]; then
    folder="/media/music/$artist/$year - $album"
    mkdir -p "$folder"
    $FF -loglevel error -y -f lavfi -i "color=c=$cover:s=600x600" -frames:v 1 "$folder/folder.jpg" < /dev/null
  fi
  $FF -loglevel error -y -f lavfi -i "sine=frequency=$frequency:duration=$seconds" "${codec[@]}" \
    -metadata "title=$title" -metadata "artist=$performers" -metadata "album_artist=$artist" \
    -metadata "album=$album" -metadata "track=$track/$tracks" -metadata disc=1 -metadata "date=$year" \
    -metadata "genre=$genres" "$folder/$(printf %02d "$track") $title.$format" < /dev/null
done < /library.tsv
echo made the library
SH
)
if [[ ! -d $DATA/media/music ]]; then
  docker run --rm --entrypoint /bin/bash -v "$DATA/media:/media" -v "$PWD/dev/test-library.tsv:/library.tsv:ro" \
    "$IMAGE" -c "$make_library"
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

# A value from an answer; none, and the script stops (set -e), as it should.
json() { jq -er "$1"; }

done_already=$(curl -sf "$URL/System/Info/Public" | jq -r .StartupWizardCompleted)
if [[ $done_already != true ]]; then
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
  -H "Authorization: $AUTH" -d '{"Username":"test","Pw":"test"}' | json .AccessToken)
H=(-H "Authorization: $AUTH, Token=\"$TOKEN\"")

if ! curl -sf "${H[@]}" "$URL/Library/VirtualFolders" | grep -q '"Music"'; then
  curl -sf -X POST "${H[@]}" -H 'Content-Type: application/json' \
    "$URL/Library/VirtualFolders?name=Music&collectionType=music&paths=%2Fmedia%2Fmusic&refreshLibrary=true" \
    -d '{"LibraryOptions":{"EnableRealtimeMonitor":false,"PathInfos":[{"Path":"/media/music"}]}}'
fi

# Wait until the scan has found every file and settled.
want=$(find "$DATA/media/music" -type f \( -name '*.mp3' -o -name '*.flac' -o -name '*.m4a' \) | wc -l)
USER_ID=$(curl -sf "${H[@]}" "$URL/Users/Me" | json .Id)
# The first scan, right after the wizard, can finish having found nothing
# (seen with Jellyfin 12.4): a refresh after a while starts it again.
for i in $(seq 1 180); do
  have=$(curl -sf "${H[@]}" "$URL/Items?userId=$USER_ID&IncludeItemTypes=Audio&Recursive=true&Limit=0" | json .TotalRecordCount)
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
    | json 'first(.[] | select(.Key == "RefreshLibrary") | .State)' || echo unknown)
  bare=$(curl -sf "${H[@]}" "$URL/Items?userId=$USER_ID&IncludeItemTypes=Audio&Recursive=true&Fields=Genres" \
    | json '[.Items[] | select((.Genres // []) | length == 0)] | length' || echo -1)
  artists=$(curl -sf "${H[@]}" "$URL/Artists/AlbumArtists?userId=$USER_ID&Limit=0" | json .TotalRecordCount || echo -1)
  [[ $state == Idle && $bare == 0 && $artists -gt 0 && $artists == "$artists_before" ]] && break
  artists_before=$artists
  sleep 3
done
echo "scan: $state, tracks without genres: $bare, album artists: $artists"

echo "Jellyfin at $URL (Docker: http://${alias:-jellyfin}:8096): $have of $want tracks, user test/test, user id $USER_ID"
