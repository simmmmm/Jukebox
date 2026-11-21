#!/usr/bin/env bash
# Pictures of Jukebox for Linux at its true size, without a desktop: the app
# walks its own screens (Linux/App/Shots.swift) under Xvfb, against the demo
# library the iPhone's screenshots use (dev/fake-jellyfin.swift, dev/demo),
# with sound to nowhere. Dark and light, wide and narrow.
#
#   dev/linux-screens.sh                 every size  -> build/linux-screens/<size>/*.png
#   dev/linux-screens.sh 1440x900-dark   one of them
#   HANDOFF=Studio dev/linux-screens.sh  with music to go on with on Home
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
# HANDOFF=Studio: music playing on "Studio", offered on Home beside Your Station.
"$fake" --port $port --data dev/demo --song-lengths --slow-downloads ${HANDOFF:+--handoff "$HANDOFF"} >"$work/fake.log" 2>&1 &
fake_pid=$!
watcher=
trap 'kill $fake_pid $watcher 2>/dev/null; rm -rf "$work"' EXIT
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
  # A session bus of its own that starts nothing: without service folders
  # nothing is activatable on it, so no keyring is asked for (a plain
  # dbus-run-session read /usr/share/dbus-1/services and had systemd --user
  # start the desktop's gnome-keyring, which asked to make a keyring, 19
  # November 2026). A home, a runtime folder and settings of its own, and a
  # display from :321 up, clear of the desktop's; the history kept from one
  # size to the next, so Home has its "Played lately".
  mkdir -p "$work/home" "$work/runtime"; chmod 700 "$work/runtime"
  cat > "$work/bus.conf" <<BUS
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:dir=$work/runtime</listen>
  <policy context="default">
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
</busconfig>
BUS
  # A popover is a surface of its own, outside the window's picture: when
  # the walk leaves "<name>-ready" in the folder (Shots.swift, a menu open),
  # the whole screen is taken from outside as <name>.png. The display is
  # open to this machine's own clients (-ac) for it.
  ( while :; do
      for ready in "$out/$shot"/*-ready; do
        [[ -e $ready ]] || continue
        name=$(basename "$ready" -ready)
        [[ -e "$out/$shot/$name.png" ]] && continue
        for display in $(seq 321 330); do
          import -display ":$display" -window root "$out/$shot/$name.png" 2>/dev/null && break
        done
      done
      sleep 0.3
    done ) &
  watcher=$!
  env -u WAYLAND_DISPLAY -u DBUS_SESSION_BUS_ADDRESS -u PULSE_SERVER -u SSH_AUTH_SOCK \
    HOME="$work/home" XDG_RUNTIME_DIR="$work/runtime" GSETTINGS_BACKEND=memory GIO_USE_VFS=local \
    GTK_USE_PORTAL=0 GDK_BACKEND=x11 GSK_RENDERER=cairo ADW_DEBUG_COLOR_SCHEME=prefer-$scheme \
    JUKEBOX_AUDIO_SINK=fakesink JUKEBOX_SHOTS="$out/$shot" JUKEBOX_WINDOW="$size" \
    XDG_CONFIG_HOME="$work/config" XDG_DATA_HOME="$work/data" XDG_CACHE_HOME="$work/cache" \
    timeout 300 dbus-run-session --config-file="$work/bus.conf" -- xvfb-run -a -n 321 -s "-ac -screen 0 ${size}x24" .build-linux/debug/Jukebox \
    >"$work/app-$shot.log" 2>&1 || { echo "$shot: the walk did not finish"; tail -5 "$work/app-$shot.log"; }
  kill $watcher 2>/dev/null || true
  echo "$shot: $(ls "$out/$shot" | wc -l) pictures"
done
echo "$out"
