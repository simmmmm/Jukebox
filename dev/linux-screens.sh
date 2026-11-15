#!/usr/bin/env bash
# Pictures of Jukebox for Linux at its true size, without a desktop: the app
# walks its own screens (Linux/App/Shots.swift) under Xvfb, against the demo
# library the iPhone's screenshots use (dev/fake-jellyfin.swift, dev/demo),
# with sound to nowhere. Dark and light, wide and narrow.
#
#   dev/linux-screens.sh                 every size  -> build/linux-screens/<size>/*.png
#   dev/linux-screens.sh 1440x900-dark   one of them
#
# The debug build as it is (dev/linux-build.sh first). Needs Xvfb and jq.
set -euo pipefail
cd "$(dirname "$0")/.."
out=build/linux-screens
work=$(mktemp -d)
port=8197

# The fake Jellyfin, built in the image dev/linux-build.sh builds the app in,
# again only when its source is newer than it.
fake=.build-linux/fake-jellyfin
sources=(dev/fake-jellyfin.swift JukeboxKit/Sources/JukeboxKit/Subsonic/MD5.swift)
if [[ ! -x $fake || ${sources[0]} -nt $fake || ${sources[1]} -nt $fake ]]; then
  docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -v "$PWD:/src" -w /src jukebox-linux-build \
    swiftc -O -static-stdlib -parse-as-library "${sources[@]}" -o "$fake" 2>&1 | { grep -v mktemp || true; }
fi
"$fake" --port $port --data dev/demo --song-lengths --slow-downloads >"$work/fake.log" 2>&1 &
fake_pid=$!
trap 'kill $fake_pid 2>/dev/null; rm -rf "$work"' EXIT
for _ in $(seq 1 40); do curl -fs "http://localhost:$port/System/Info/Public" >/dev/null && break; sleep 0.25; done

# Signed in already, by the file a desktop without a keyring uses.
mkdir -p "$work/data/Jukebox"
base=http://localhost:$port
answer=$(curl -fs -X POST "$base/Users/AuthenticateByName" -H 'Content-Type: application/json' \
  -H 'Authorization: MediaBrowser Client="Jukebox", Device="screens", DeviceId="jukebox-screens", Version="1.0"' \
  -d '{"Username":"test","Pw":"test"}')
info=$(curl -fs "$base/System/Info/Public")
jq -n --arg url "$base" --argjson answer "$answer" --argjson info "$info" \
  '{serverURL: $url, serverID: $info.Id, serverName: $info.ServerName, userID: $answer.User.Id,
    userName: "test", accessToken: $answer.AccessToken}' > "$work/data/Jukebox/credentials.json"

for shot in ${@:-1440x900-dark 1440x900-light 1920x1080-dark 760x900-dark 400x800-dark}; do
  size=${shot%-*} scheme=${shot#*-}
  rm -rf "$out/$shot"; mkdir -p "$out/$shot"
  # A session bus of its own and no keyring on it; the history kept from
  # one size to the next, so Home has its "Played lately".
  env -u WAYLAND_DISPLAY GDK_BACKEND=x11 GSK_RENDERER=cairo ADW_DEBUG_COLOR_SCHEME=prefer-$scheme \
    JUKEBOX_AUDIO_SINK=fakesink JUKEBOX_SHOTS="$out/$shot" JUKEBOX_WINDOW="$size" \
    XDG_CONFIG_HOME="$work/config" XDG_DATA_HOME="$work/data" XDG_CACHE_HOME="$work/cache" \
    timeout 300 dbus-run-session -- xvfb-run -a -s "-screen 0 ${size}x24" .build-linux/debug/Jukebox \
    >"$work/app-$shot.log" 2>&1 || { echo "$shot: the walk did not finish"; tail -5 "$work/app-$shot.log"; }
  echo "$shot: $(ls "$out/$shot" | wc -l) pictures"
done
echo "$out"
