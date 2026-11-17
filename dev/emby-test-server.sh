#!/usr/bin/env bash
# A real Emby in Docker on the made-up library dev/jellyfin-test-server.sh
# makes (read-only, so run that first), set up through the API, for
# JukeboxKit's Emby tests (dev/kit-test.sh runs them when it is up) and the
# Linux client. Idempotent: a second run keeps what is there.
#
#   dev/emby-test-server.sh          start, set up, print the URL
#   dev/emby-test-server.sh --reset  throw this server away first (its own
#                                    folder only; the library stays)
#
# User "test", password "test". The server is "emby" on the Docker network
# "jukebox" (port 8096), and localhost:8097 from here: Emby's own port is
# Jellyfin's, which the Jellyfin test server has.
set -euo pipefail
cd "$(dirname "$0")/.."

IMAGE=emby/embyserver:latest
DATA=${JUKEBOX_EMBY_DATA:-$HOME/.cache/jukebox-emby-test}
MEDIA=${JUKEBOX_TEST_DATA:-$HOME/.cache/jukebox-test}/media
NAME=${JUKEBOX_EMBY_CONTAINER:-jukebox-emby}
PORT=${JUKEBOX_EMBY_PORT:-8097}
URL=http://localhost:$PORT
AUTH='MediaBrowser Client="JukeboxTests", Device="Linux", DeviceId="jukebox-tests", Version="1.0"'

[[ -d $MEDIA/music ]] || { echo "No library at $MEDIA/music: dev/jellyfin-test-server.sh makes it." >&2; exit 1; }
if [[ ${1:-} == --reset ]]; then
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  rm -rf "$DATA"
fi
mkdir -p "$DATA/config"
docker network inspect jukebox >/dev/null 2>&1 || docker network create jukebox >/dev/null

if ! docker ps --format '{{.Names}}' | grep -qx "$NAME"; then
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  alias=emby; [[ $NAME == jukebox-emby ]] || alias=$NAME
  # As whoever runs this, so --reset can remove what it writes (as root
  # otherwise, measured).
  docker run -d --name "$NAME" --network jukebox --network-alias "$alias" \
    -e UID="$(id -u)" -e GID="$(id -g)" \
    -p "$PORT:8096" -v "$DATA/config:/config" -v "$MEDIA:/media:ro" "$IMAGE" >/dev/null
fi

# A call, again each second until it succeeds, for a minute.
again() {
  local _
  for _ in $(seq 1 60); do "$@" 2>/dev/null && return 0; sleep 1; done
  "$@"
}
json() { jq -er "$1"; }

# Up once it has an id (Emby 4.10 answers with its id before the wizard).
again bash -c "curl -sf '$URL/System/Info/Public' | grep -q '\"Id\"'"

# The wizard's first steps make the user. Its last step only marks the web
# app's wizard as done: Emby 4.10 signs in and serves every route Jukebox
# uses without it (measured), so it is not taken.
if [[ $(curl -sf "$URL/Startup/User" | jq -r '.Name // empty') != test ]]; then
  again curl -sf -X POST "$URL/Startup/Configuration" -H 'Content-Type: application/json' \
    -d '{"UICulture":"en-US","MetadataCountryCode":"US","PreferredMetadataLanguage":"en"}'
  again curl -sf -X POST "$URL/Startup/User" -H 'Content-Type: application/json' \
    -d '{"Name":"test","Password":"test"}' -o /dev/null
fi

signed_in=$(again curl -sf -X POST "$URL/Users/AuthenticateByName" -H 'Content-Type: application/json' \
  -H "Authorization: $AUTH" -d '{"Username":"test","Pw":"test"}')
TOKEN=$(json .AccessToken <<<"$signed_in")
USER_ID=$(json .User.Id <<<"$signed_in")
H=(-H "X-Emby-Token: $TOKEN")

if ! curl -sf "${H[@]}" "$URL/Library/VirtualFolders" | grep -q '"Music"'; then
  curl -sf -X POST "${H[@]}" -H 'Content-Type: application/json' \
    "$URL/Library/VirtualFolders?name=Music&collectionType=music&paths=%2Fmedia%2Fmusic&refreshLibrary=true" \
    -d '{"LibraryOptions":{"EnableRealtimeMonitor":false,"PathInfos":[{"Path":"/media/music"}]}}'
fi

# Every track found, the scan idle, and the album artists unchanged for one
# more look (as the Jellyfin script waits; 358 tracks took 20 s here).
want=$(find "$MEDIA/music" -type f \( -name '*.mp3' -o -name '*.flac' -o -name '*.m4a' \) | wc -l)
artists_before=-1
for _ in $(seq 1 120); do
  have=$(curl -sf "${H[@]}" "$URL/Items?UserId=$USER_ID&IncludeItemTypes=Audio&Recursive=true&Limit=0" | json .TotalRecordCount || echo 0)
  state=$(curl -sf "${H[@]}" "$URL/ScheduledTasks" \
    | json 'first(.[] | select(.Key == "RefreshLibrary") | .State)' || echo unknown)
  artists=$(curl -sf "${H[@]}" "$URL/Artists/AlbumArtists?UserId=$USER_ID&Limit=0" | json .TotalRecordCount || echo -1)
  [[ $have -ge $want && $state == Idle && $artists -gt 0 && $artists == "$artists_before" ]] && break
  artists_before=$artists
  sleep 3
done
echo "scan: $state, $have of $want tracks, album artists: $artists"

# The covers. Emby 4.10 makes its albums from the tags (an album has no
# folder of its own, no Path) and read none of the folder.jpg beside the
# files, also after a full refresh (measured): each album's is uploaded
# through the API, as an owner would set it in the web app.
albums=$(curl -sf "${H[@]}" "$URL/Items?UserId=$USER_ID&IncludeItemTypes=MusicAlbum&Recursive=true" \
  | json '.Items[] | select(.ImageTags.Primary == null) | .Id')
for album in $albums; do
  file=$(curl -sf "${H[@]}" "$URL/Items?UserId=$USER_ID&ParentId=$album&IncludeItemTypes=Audio&Recursive=true&Limit=1&Fields=Path" \
    | json '.Items[0].Path')
  cover="$MEDIA/${file#/media/}"
  cover="$(dirname "$cover")/folder.jpg"
  [[ -f $cover ]] || continue
  base64 -w0 "$cover" | curl -sf -X POST "${H[@]}" -H 'Content-Type: image/jpeg' --data-binary @- \
    "$URL/Items/$album/Images/Primary"
done

echo "Emby at $URL (Docker: http://${alias:-emby}:8096): $have of $want tracks, user test/test, user id $USER_ID"
