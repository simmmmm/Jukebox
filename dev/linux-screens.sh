#!/usr/bin/env bash
# Pictures of Jukebox for Linux at its true size, without a desktop: the app
# walks its own screens (Linux/App/Shots.swift) under Xvfb, against the demo
# library the iPhone's screenshots use (dev/fake-jellyfin.py, dev/demo), with
# sound to nowhere. Dark and light, wide and narrow.
#
#   dev/linux-screens.sh                 every size  -> build/linux-screens/<size>/*.png
#   dev/linux-screens.sh 1440x900-dark   one of them
#
# The debug build as it is (dev/linux-build.sh first). Needs Xvfb.
set -euo pipefail
cd "$(dirname "$0")/.."
out=build/linux-screens
work=$(mktemp -d)
port=8197
python3 dev/fake-jellyfin.py --port $port --data dev/demo --song-lengths --slow-downloads >"$work/fake.log" 2>&1 &
fake=$!
trap 'kill $fake 2>/dev/null; rm -rf "$work"' EXIT
for _ in $(seq 1 40); do curl -fs "http://localhost:$port/System/Info/Public" >/dev/null && break; sleep 0.25; done

# Signed in already, by the file a desktop without a keyring uses.
mkdir -p "$work/data/Jukebox"
python3 - "$port" "$work/data/Jukebox/credentials.json" <<'PY'
import json, sys, urllib.request
base = f"http://localhost:{sys.argv[1]}"
auth = 'MediaBrowser Client="Jukebox", Device="screens", DeviceId="jukebox-screens", Version="1.0"'
request = urllib.request.Request(base + "/Users/AuthenticateByName", data=b'{"Username":"test","Pw":"test"}',
                                 headers={"Content-Type": "application/json", "Authorization": auth})
answer = json.load(urllib.request.urlopen(request))
info = json.load(urllib.request.urlopen(base + "/System/Info/Public"))
json.dump({"serverURL": base, "serverID": info["Id"], "serverName": info["ServerName"],
           "userID": answer["User"]["Id"], "userName": "test", "accessToken": answer["AccessToken"]},
          open(sys.argv[2], "w"))
PY

for shot in ${@:-1440x900-dark 1440x900-light 1920x1080-dark 760x900-dark 400x800-dark}; do
  size=${shot%-*} scheme=${shot#*-}
  rm -rf "$out/$shot"; mkdir -p "$out/$shot"
  # A session bus of its own and no keyring on it; the history kept from
  # one size to the next, so Home has its "Played lately".
  env -u WAYLAND_DISPLAY GDK_BACKEND=x11 GSK_RENDERER=cairo ADW_DEBUG_COLOR_SCHEME=prefer-$scheme \
    JUKEBOX_AUDIO_SINK=fakesink JUKEBOX_SHOTS="$out/$shot" JUKEBOX_WINDOW="$size" \
    XDG_CONFIG_HOME="$work/config" XDG_DATA_HOME="$work/data" XDG_CACHE_HOME="$work/cache" \
    timeout 200 dbus-run-session -- xvfb-run -a -s "-screen 0 ${size}x24" .build-linux/debug/Jukebox \
    >"$work/app-$shot.log" 2>&1 || { echo "$shot: the walk did not finish"; tail -5 "$work/app-$shot.log"; }
  echo "$shot: $(ls "$out/$shot" | wc -l) pictures"
done
echo "$out"
