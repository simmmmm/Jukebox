#!/usr/bin/env bash
# The screenshot round, after the app has compiled (ci/app.sh, on every push
# without TestFlight). Steps:
#   - the fake Jellyfin with the demo library, on localhost:8096
#     (dev/fake-jellyfin.swift, dev/demo), and the contact sheet's tool
#     (dev/contact-sheet.swift), both built here with Xcode's swiftc;
#   - the app and its UI tests built for the simulator;
#   - every main screen walked on an iPhone in dark, Home and Now Playing
#     again in light, Linux's walk on a 13-inch iPad held sideways (each
#     picture named as its Linux twin), and the narrowest wide window on an
#     11-inch iPad held upright (JukeboxUITests/ScreenshotTests.swift);
#   - the pictures, named, in build/logs/screenshots/<device>/, which the
#     workflow uploads with build/logs;
#   - one contact sheet per device;
#   - all of it on the `screenshots` branch, one commit that replaces the last:
#     main's round at its top, a work branch's (one whose name ends in
#     "walk", ci/app.sh) in branches/<name>/, so it never replaces main's.
# The Mac's own window is walked when asked for (SHOTS_DEVICES has "mac":
# the store's round, a push of `store-walk`, ci/app.sh), on the runner
# itself, for the Mac App Store's pictures (MacScreenshotTests.swift).
# On the photographer's MacBook, a runner of our own, the walk is left out
# and the Mac's snapshots ("mac-snap", JukeboxSnapshots/Snapshots.swift) are
# made instead, on every push: the main screens drawn offscreen, nothing on
# the laptop's screen.
#
# Why: there is no Mac here, so nobody has seen the app. The photographer
# asked for pictures ("Als je plaatjes hebt om te delen zie ik ze graag") and
# opens the branch on GitHub on the phone. The lead can read the run's log
# but not its artifact, so each sheet is printed last, as a 900-pixel JPEG in
# base64 between "=====BEGIN SHEET <device>=====" and "=====END SHEET
# <device>=====".
#
# It never fails the job. Every failure is written down (warnings, the run's
# summary, the README of the branch) and the round goes on; it exits 0.
# SHOTS_BUDGET (seconds, set by ci/app.sh) is how long it may take. Each step
# is cut short so that the last five minutes are left for the sheets and the
# push; ci/app.sh's watchdog stops whatever is still running after that.
#
# On a Mac, by hand: SHOTS_DEVICES=iphone NO_PUSH=1 ci/screenshots.sh.
# SEARCH_TERM sets what the search types (else a word of the first artist).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 0
# adhoc_sign and adhoc_sign_tests, for the Mac's walk (ci/sign.sh).
source ci/sign.sh

start=$SECONDS
budget=${SHOTS_BUDGET:-2400}
# Walked in this order; the last is the first left out when time runs short.
devices=${SHOTS_DEVICES:-iphone ipad ipad11}
# The Mac's walk takes over the screen, the mouse and the keyboard; on a
# runner of our own, the photographer's MacBook, it is left out: "Doe dan
# maar via GitHub" (20 November 2026). The simulators' walks stay.
# In its place, on every push, the snapshots: first, as they take a minute
# and the walks after them many.
if [[ ${RUNNER_ENVIRONMENT:-} == self-hosted ]]; then
  kept=
  for kind in $devices; do [[ $kind == mac || $kind == mac-snap ]] || kept="${kept:+$kept }$kind"; done
  if [[ " $devices " == *" mac "* ]]; then
    echo "::notice::No Mac walk on a self-hosted runner: the store's Mac pictures come from GitHub's runner."
  fi
  devices="mac-snap${kept:+ $kept}"
fi
# The iPhone walked. The Pro's 1206 x 2622 is what App Store Connect
# requires; "iPhone 17 Pro Max" gives the optional large set, 1320 x 2868
# (docs/RELEASE.md, Screenshots).
iphone=${SHOTS_IPHONE:-iPhone 17 Pro}
out=build/logs/screenshots
# Result bundles, exports, the derived data and the branch: not uploaded.
work=build/screenshots
summary=${GITHUB_STEP_SUMMARY:-/dev/null}
repo=${GITHUB_REPOSITORY:-}
sha=$(git rev-parse HEAD 2>/dev/null || echo unknown)
short=${sha:0:7}
ref=${GITHUB_REF_NAME:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)}
rm -rf "$out" "$work"
mkdir -p "$out" "$work"
: > "$work/problems.txt"
if [[ -n ${SEARCH_TERM:-} ]]; then
  # xcodebuild hands TEST_RUNNER_ variables to the tests, without the prefix.
  export TEST_RUNNER_JUKEBOX_SEARCH=$SEARCH_TERM
fi

group() { echo "::group::$*"; }
endgroup() { echo "::endgroup::"; }
problem() {
  echo "::warning::Screenshots: $*"
  echo "$*" >> "$work/problems.txt"
}

# The seconds a step may take: what it asks for, or what is left before the
# last five minutes, which are kept for the sheets and the push.
allow() {
  local left=$(( budget - (SECONDS - start) - 300 ))
  if (( left < $1 )); then echo "$left"; else echo "$1"; fi
}

# A command, stopped after $1 seconds. macOS has no `timeout`; perl's alarm
# outlives its exec. The exit status is 142 when the command was stopped.
bounded() {
  local limit=$1
  shift
  if (( limit < 20 )); then
    problem "no time left for: $*"
    return 124
  fi
  perl -e 'alarm shift @ARGV; exec @ARGV or die "exec $ARGV[0]: $!\n"' "$limit" "$@"
}

sim() { bounded 60 xcrun simctl "$@"; }

# A simulator turned dark or light, and asked afterwards what it is. Just
# after a boot `simctl ui … appearance dark` can hang until its minute is up
# and leave the simulator light (run 43718236975: the iPhone's "dark"
# pictures came out light). So: tried again, and once more after the
# simulator is booted afresh. False when it never says $2: its walk is then
# not walked, rather than light pictures saved as dark ones.
appearance() {
  local udid=$1 mode=$2 try now=
  for try in 1 2 3 4 5; do
    if (( try == 4 )); then
      bounded 120 xcrun simctl shutdown "$udid" > /dev/null 2>&1
      bounded "$(allow 300)" xcrun simctl bootstatus "$udid" -b > /dev/null 2>&1
    fi
    bounded 45 xcrun simctl ui "$udid" appearance "$mode" > /dev/null 2>&1
    now=$(bounded 30 xcrun simctl ui "$udid" appearance 2> /dev/null)
    if [[ $now == "$mode" ]]; then
      (( try == 1 )) || echo "The simulator turned $mode at try $try."
      return 0
    fi
    echo "The simulator is ${now:-silent}, not $mode (try $try)."
    sleep 5
  done
  return 1
}

# Apple's own 9:41 and full bars, not the runner's time. Again after each
# turn of the appearance: a boot afresh (appearance) forgets it.
status_bar() {
  sim status_bar "$1" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100 \
    || problem "the $2 simulator's status bar kept the runner's time"
}

# --- The fake Jellyfin -------------------------------------------------------

group "The fake Jellyfin on localhost:8096, and the contact sheet's tool"
server=
stop_server() {
  if [[ -n $server ]]; then
    kill "$server" 2>/dev/null
    wait "$server" 2>/dev/null
  fi
  server=
}
# What the Mac's round changes on the runner, put back as it was: on
# GitHub's machines it goes with the machine, but the MacBook is the
# photographer's own laptop ("doe alles via m'n macbook joh, zeker
# screenshots", 20 November 2026). Saved in mac_settings before the round.
mac_saved=false
wallpaper_store="$HOME/Library/Application Support/com.apple.wallpaper/Store/Index.plist"
restore_mac() {
  $mac_saved || return 0
  mac_saved=false
  echo "The Mac's own settings put back."
  osascript -e "tell application \"System Events\" to tell appearance preferences to set dark mode to $saved_dark" \
    > /dev/null 2>&1 || problem "the Mac's dark mode was not put back ($saved_dark)"
  if [[ -f $work/wallpaper-Index.plist ]]; then
    cp "$work/wallpaper-Index.plist" "$wallpaper_store" && killall WallpaperAgent 2> /dev/null
  fi
  if [[ -n $saved_scrollbars ]]; then
    defaults write -g AppleShowScrollBars -string "$saved_scrollbars"
  else
    defaults delete -g AppleShowScrollBars 2> /dev/null
  fi
  if [[ $saved_autohide != 1 ]]; then
    if [[ -n $saved_autohide ]]; then
      defaults write com.apple.dock autohide -bool "$saved_autohide"
    else
      defaults delete com.apple.dock autohide 2> /dev/null
    fi
    killall Dock 2> /dev/null
  fi
  if [[ -x $work/mac-display && -s $work/display-mode.txt ]]; then
    "$work/mac-display" --restore "$work/display-mode.txt" | grep '^display:' \
      || problem "the Mac's display mode was not put back"
  fi
  return 0
}
mac_settings() {
  saved_dark=$(osascript -e 'tell application "System Events" to tell appearance preferences to get dark mode' 2> /dev/null)
  [[ $saved_dark == true ]] || saved_dark=false
  saved_scrollbars=$(defaults read -g AppleShowScrollBars 2> /dev/null)
  saved_autohide=$(defaults read com.apple.dock autohide 2> /dev/null)
  if [[ -f $wallpaper_store ]]; then cp "$wallpaper_store" "$work/wallpaper-Index.plist"; fi
  mac_saved=true
}
trap 'stop_server; restore_mac' EXIT
# The watchdog's TERM (ci/app.sh) ends the round through the EXIT trap too.
trap 'exit 143' TERM INT
# jq reads simctl's and the results' JSON below; the runner has it.
command -v jq > /dev/null || problem "no jq on this runner: no simulators, verdicts or pictures"
# Built first, so a tool that does not compile shows at the top of the log,
# before the walks. The contact sheet's tool checks itself on made-up pictures.
if bounded "$(allow 300)" xcrun swiftc -O dev/contact-sheet.swift -o "$work/contact-sheet" \
    > "$work/contact-sheet-build.log" 2>&1 && bounded 60 "$work/contact-sheet" >> "$work/contact-sheet-build.log" 2>&1; then
  sheet_tool=$work/contact-sheet
else
  sheet_tool=
  problem "dev/contact-sheet.swift did not build or check itself, so no contact sheets"
  tail -20 "$work/contact-sheet-build.log"
fi
if bounded "$(allow 300)" xcrun swiftc -O -parse-as-library dev/fake-jellyfin.swift \
    JukeboxKit/Sources/JukeboxKit/Subsonic/MD5.swift -o "$work/fake-jellyfin" > "$out/fake-jellyfin-build.log" 2>&1; then
  # Its log is written a line at a time, so it is whole when it is stopped.
  # --song-lengths: songs of 2:30 to 5:30, as a real library has, not the
  # test library's few seconds, so the album pages and the scrubber look
  # like what a listener sees.
  # A work round (a branch ending in "walk", not the store's) has music
  # playing on another device, so Home shows its card beside Your Station;
  # main's and the store's pictures stay as they were.
  handoff=
  case $ref in
    store-*) ;;
    *walk) handoff="--handoff Studio" ;;
  esac
  # shellcheck disable=SC2086 # two words, or none
  "$work/fake-jellyfin" --port 8096 --data dev/demo --song-lengths $handoff \
    > "$out/fake-jellyfin.log" 2>&1 < /dev/null &
  server=$!
  answered=false
  for _ in $(seq 1 60); do
    if curl -fsS -m 2 http://localhost:8096/System/Info/Public > "$work/public-info.json" 2>/dev/null; then
      answered=true
      break
    fi
    kill -0 "$server" 2>/dev/null || break
    sleep 0.5
  done
  # A moment for a server that could not have the port to have stopped.
  sleep 1
  if $answered && ! kill -0 "$server" 2>/dev/null; then
    # Something else holds the port (on a developer's machine, the real
    # Jellyfin of dev/jellyfin-test-server.sh), and the fake one has stopped.
    problem "the fake Jellyfin stopped at once and something else answers on localhost:8096 (fake-jellyfin.log)"
    tail -20 "$out/fake-jellyfin.log"
    server=
  elif $answered; then
    echo "It answers: $(head -c 300 "$work/public-info.json")"
  else
    problem "the fake Jellyfin did not answer on localhost:8096, so the walks stop at sign-in (fake-jellyfin.log)"
    tail -40 "$out/fake-jellyfin.log"
  fi
else
  problem "dev/fake-jellyfin.swift did not build, so the walks stop at sign-in (fake-jellyfin-build.log)"
  tail -20 "$out/fake-jellyfin-build.log"
fi
endgroup

# --- The simulators ----------------------------------------------------------

group "The simulators"
# Read once into a variable, then searched: `simctl … | grep -q` under
# pipefail fails when grep stops reading first, and would read as "no
# runtime" and download one for twenty minutes. Bounded: a wedged
# CoreSimulatorService does not answer at all.
runtimes=$(bounded 120 xcrun simctl list runtimes available 2> /dev/null)
if ! grep -qE '^iOS (2[6-9]|[3-9][0-9])' <<< "$runtimes"; then
  echo "No iOS 26 simulator runtime: downloading one."
  bounded "$(allow 1200)" xcodebuild -downloadPlatform iOS > "$work/download-platform.log" 2>&1 \
    || problem "xcodebuild -downloadPlatform iOS failed"
  runtimes=$(bounded 120 xcrun simctl list runtimes available 2> /dev/null)
fi
grep '^iOS' <<< "$runtimes"

# The simulator for a device kind, from `xcrun simctl list -j` on stdin:
# "udid<TAB>name<TAB>runtime", or, when the runner has none of that kind,
# "create<TAB>name<TAB>device type<TAB>runtime id<TAB>runtime" for simctl to
# make. The newest iOS 26 or later; an iPhone 17 Pro, else the newest
# numbered iPhone (a Pro first); a 13-inch iPad Pro, else a 13-inch iPad,
# else any iPad; an 11-inch iPad Pro (834 points upright), else another
# 11-inch iPad.
pick() {
  jq -r --arg kind "$1" --arg iphone "$iphone" '
    def version: [(.version // "0") | scan("[0-9]+") | tonumber];
    # Higher is better; null when the name is not of this kind.
    def rank: . as $name
      | if $kind == "iphone" then
          if ($name | startswith("iPhone") | not) then null
          elif $name == $iphone then [3, 0]
          elif ($name | test("^iPhone [0-9]+( Pro)?$")) then
            $name | capture("^iPhone (?<number>[0-9]+)(?<pro> Pro)?$")
            | [(if .pro then 2 else 1 end), (.number | tonumber)]
          else [0, 0] end
        elif $kind == "ipad11" then
          if ($name | startswith("iPad")) and ($name | contains("11-inch"))
          then [(if $name | startswith("iPad Pro") then 1 else 0 end), 0] else null end
        elif ($name | startswith("iPad") | not) then null
        elif ($name | contains("13-inch")) then [(if $name | startswith("iPad Pro") then 2 else 1 end), 0]
        else [0, 0] end;
    . as $data
    | [.runtimes[]? | select(.isAvailable and ((.identifier // "") | contains("SimRuntime.iOS"))
        and (version[:1] >= [26]))]
    # Of one version, the runtime for every device: Xcode 27.2 has a second
    # iOS 27.2 for one iPhone alone ("iPhone Duo", on the MacBook).
    | if length == 0 then error("no iOS 26 runtime")
      else sort_by([version, ((.supportedDeviceTypes // []) | length)]) | last end
    | . as $runtime
    | [$data.devices[$runtime.identifier][]? | select(.isAvailable)
        | {rank: (.name | rank), name, udid} | select(.rank != null)]
    | if length > 0 then
        max_by([.rank, .name, .udid]) | [.udid, .name, ($runtime.name // "iOS")] | @tsv
      else
        [(if ($runtime.supportedDeviceTypes // []) | length > 0 then $runtime.supportedDeviceTypes
          else $data.devicetypes // [] end)[]
          | {rank: ((.name // "") | rank), name, identifier} | select(.rank != null)]
        | if length == 0 then error("no \($kind) device type for \($runtime.name)") else . end
        | max_by([.rank, .name, .identifier])
        | ["create", .name, .identifier, $runtime.identifier, ($runtime.name // "iOS")] | @tsv
      end'
}

ready=
bounded 120 xcrun simctl list -j > "$work/simctl.json" 2> "$work/simctl.err" \
  || problem "xcrun simctl list failed: $(tail -1 "$work/simctl.err")"
for kind in $devices; do
  if [[ $kind == mac-snap ]]; then
    mkdir -p "$out/mac-snap"
    echo "$(sw_vers -productName) $(sw_vers -productVersion), offscreen" > "$out/mac-snap/device.txt"
    echo "mac-snap: $(cat "$out/mac-snap/device.txt")"
    ready="${ready:+$ready }mac-snap"
    continue
  fi
  if [[ $kind == mac ]]; then
    # The Mac's walk needs no simulator: the runner is the Mac. (The walk
    # itself says how large its screen is, with its first PICTURE line.)
    mkdir -p "$out/mac"
    echo "$(sw_vers -productName) $(sw_vers -productVersion)" > "$out/mac/device.txt"
    echo "mac: $(cat "$out/mac/device.txt")"
    # Set, though no simulator: macOS's bash 3.2 stops at ${!udid_var} of a
    # variable that is not.
    udid_mac=none
    ready="${ready:+$ready }mac"
    continue
  fi
  udid=
  if line=$(pick "$kind" < "$work/simctl.json" 2> "$work/pick-$kind.err"); then
    if [[ $line == create$'\t'* ]]; then
      IFS=$'\t' read -r _ name type runtime_id runtime <<< "$line"
      udid=$(sim create "$name" "$type" "$runtime_id" 2>> "$work/pick-$kind.err") || udid=
    else
      IFS=$'\t' read -r udid name runtime <<< "$line"
    fi
  fi
  if [[ -n $udid ]]; then
    printf -v "udid_$kind" '%s' "$udid"
    mkdir -p "$out/$kind"
    echo "$name, $runtime" > "$out/$kind/device.txt"
    echo "$kind: $name, $runtime ($udid)"
    ready="${ready:+$ready }$kind"
  else
    problem "no $kind simulator: $(tail -1 "$work/pick-$kind.err")"
  fi
done
endgroup

# --- The build ---------------------------------------------------------------

group "The app and its UI tests, built for the simulator"
built=false
[[ -d Jukebox.xcodeproj ]] || xcodegen generate
sims=
for kind in $ready; do [[ $kind == mac* ]] || sims="${sims:+$sims }$kind"; done
if [[ -n $sims ]]; then
  first="udid_${sims%% *}"
  # For the first simulator's architecture only; the products serve the
  # other simulator as well (the same SDK, the same Mac).
  if bounded "$(allow 1500)" xcodebuild build-for-testing -project Jukebox.xcodeproj -scheme Jukebox \
      -configuration Debug -destination "id=${!first}" -derivedDataPath "$work/derived" \
      CODE_SIGNING_ALLOWED=NO > "$out/build-for-testing.log" 2>&1; then
    built=true
  else
    problem "the build for the simulator failed (build-for-testing.log)"
  fi
  grep -E 'error:|\*\* TEST BUILD' "$out/build-for-testing.log" | sed "s#$PWD/##g" | sort -u | head -60
fi
# The Mac's, in derived data of its own. Built unsigned and signed ad hoc
# after (ci/sign.sh), as ci/app.sh's builds are: macOS starts a UI test's
# runner only when it is signed, and the app is then in its sandbox, as the
# store's build is. Xcode's own ad hoc signing stops on the MacBook.
built_mac=false
if [[ " $ready " == *" mac "* ]]; then
  products=$work/derived-mac/Build/Products/Debug
  if bounded "$(allow 1200)" xcodebuild build-for-testing -project Jukebox.xcodeproj -scheme Jukebox \
      -configuration Debug -destination 'platform=macOS' -derivedDataPath "$work/derived-mac" \
      CODE_SIGNING_ALLOWED=NO > "$out/build-for-testing-mac.log" 2>&1 \
      && adhoc_sign "$products/Jukebox.app" >> "$out/build-for-testing-mac.log" 2>&1 \
      && adhoc_sign_tests "$products/JukeboxUITests-Runner.app" >> "$out/build-for-testing-mac.log" 2>&1; then
    built_mac=true
  else
    problem "the build for the Mac's walk failed (build-for-testing-mac.log)"
  fi
  grep -E 'error:|\*\* TEST BUILD' "$out/build-for-testing-mac.log" | sed "s#$PWD/##g" | sort -u | head -60
fi
# The snapshots' own Mac app, in derived data of its own. Signed by the
# linker alone: it runs from the command line, not sandboxed.
built_snap=false
if [[ " $ready " == *" mac-snap "* ]]; then
  if bounded "$(allow 600)" xcodebuild build -project Jukebox.xcodeproj -scheme JukeboxSnapshots \
      -configuration Debug -destination 'platform=macOS' -derivedDataPath "$work/derived-snap" \
      CODE_SIGNING_ALLOWED=NO > "$out/build-snapshots.log" 2>&1; then
    built_snap=true
  else
    problem "the build of the Mac's snapshots failed (build-snapshots.log)"
  fi
  grep -E 'error:|\*\* BUILD' "$out/build-snapshots.log" | sed "s#$PWD/##g" | sort -u | head -60
fi
endgroup

# --- The walks ---------------------------------------------------------------

# A walk's result in a line, from xcresulttool's summary on stdin. A walk
# whose only failures are XCTest's own complaints inside XCTExpectFailure
# ("not hittable") is reported so; they are the missed list.
verdict() {
  local line
  line=$(jq -r '((.result // "no result") | tostring) as $result
    | (if $result == "Expected Failure"
       then "Passed (XCTest\u0027s complaints about missed steps were expected)" else $result end)
      + ([.testFailures[]? | .failureText // ""]
         | if length > 0 then ": " + (join(" / ") | .[:400]) else "" end)' 2> /dev/null)
  echo "${line:-no result}"
}

is_picture() {
  case $1 in
    *.[pP][nN][gG] | *.[jJ][pP][gG] | *.[jJ][pP][eE][gG]) return 0 ;;
  esac
  return 1
}

# The pictures of one walk, named as the test named them, into the device's
# folder; its missed list into the folder's missed.txt. Prints how many.
# Two sources: the files the walk wrote itself (JUKEBOX_SHOTS), there even
# when the runner was stopped, and the result's exported attachments
# (manifest.json), there when the files could not be written. The files win.
collect() {
  local export=$1 direct=$2 dst=$3 label=$4 found=$work/found-$4.txt
  local file name base src missed_export= missed_direct= walk='^([a-z]+-)?[0-9]{2,}[a-z]?-'
  mkdir -p "$dst"
  : > "$found"
  # "05-home-scrolled_0_<UUID>.png": the name the test gave, before the
  # first "_". Only the walk's own names, "07-albums", "light-01-home" or
  # the iPad's Linux twins' "10b-now-playing": not XCTest's own screenshots
  # and recordings, which a result can hold as well.
  if [[ -f $export/manifest.json ]]; then
    while IFS=$'\t' read -r file name; do
      src=$export/$file
      [[ -f $src ]] || continue
      name=${name%.*}
      name=${name%%_*}
      if [[ $name == missed* ]]; then
        missed_export=$src
      elif [[ $name =~ $walk ]] && is_picture "$src"; then
        printf '%s\t%s\n' "$name" "$src" >> "$found"
      fi
    done < <(jq -r 'if type == "array" then .[] else empty end | .attachments[]?
      | [(.exportedFileName // "-"), (.suggestedHumanReadableName // "")] | @tsv' \
      "$export/manifest.json" 2> /dev/null)
  fi
  if [[ -d $direct ]]; then
    for src in "$direct"/*; do
      [[ -f $src ]] || continue
      base=${src##*/}
      name=${base%.*}
      if [[ $name == missed* && $base == *.txt ]]; then
        missed_direct=$src
      elif is_picture "$src"; then
        printf '%s\t%s\n' "$name" "$src" >> "$found"
      fi
    done
  fi
  # One picture a name: the last found, so the walk's own file.
  awk -F'\t' '{ last[$1] = $2 } END { for (name in last) print name "\t" last[name] }' "$found" \
    | while IFS=$'\t' read -r name src; do
        cp "$src" "$dst/$name.$(printf '%s' "${src##*.}" | tr '[:upper:]' '[:lower:]')"
      done
  src=${missed_direct:-$missed_export}
  if [[ -n $src ]]; then
    # "Nothing missed." is the walk saying so: no line for it.
    sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$src" | grep -v -e '^$' -e '^Nothing missed\.$' \
      | sed "s/^/$label: /" >> "$dst/missed.txt"
  fi
  cut -f1 "$found" | sort -u | wc -l | tr -d ' '
}

# What the app said and how it ended, beside the walk's log: the crash
# reports macOS wrote for it during the walk (the simulator's apps write
# theirs on the runner, ~/Library/Logs/DiagnosticReports) as
# <label>-crash-<n>.ips, and the simulator's own log of the app's last
# five minutes as <label>-device.log. Why: a walk that ends "Lost connection
# to the application" or "stopped running" says nothing of where (589adbe
# crashed right after sign-in, and nobody here has a Mac to look).
crashes() {
  local kind=$1 udid=$2 label=$3 report n=0
  while IFS= read -r report; do
    n=$(( n + 1 ))
    cp "$report" "$out/$label-crash-$n.ips"
    echo "$label: the app crashed: ${report##*/} (logs/$label-crash-$n.ips)"
    # The decisive lines in the run's log too: the exception and the
    # crashed thread's first frames of the report's readable half.
    grep -E '"(type|signal|subtype|codes|indicator|message)"|"symbol"' "$report" | head -40
  done < <(find "$HOME/Library/Logs/DiagnosticReports" -maxdepth 2 -name 'Jukebox*.ips' \
    -newer "$work/started-$label" 2> /dev/null)
  if [[ $kind != mac ]]; then
    bounded 120 xcrun simctl spawn "$udid" log show --predicate 'process == "Jukebox"' \
      --last 5m --style compact 2> /dev/null | tail -600 > "$out/$label-device.log"
  fi
}

# One walk: one test on a device's simulator, at most $4 seconds, and its
# pictures exported. xcodebuild's own test timeout ends a stuck test with a
# result bundle intact; the perl alarm is the last resort. The allowance
# leaves 150 s to xcodebuild: XCTest rounds it up to a whole minute, and
# installing and starting the runner comes before it.
walk() {
  local kind=$1 test=$2 label=$3 limit allowance verdict pictures
  local udid_var="udid_$1"
  local udid=${!udid_var} result="$work/$label.xcresult" direct="$PWD/$work/direct/$label"
  local destination="id=$udid" derived="$work/derived" class=ScreenshotTests
  if [[ $kind == mac ]]; then
    destination='platform=macOS' derived="$work/derived-mac" class=MacScreenshotTests
  fi
  limit=$(allow "$4")
  if (( limit < 240 )); then
    problem "$label: not walked, no time left"
    echo "$label: not walked (no time left)" >> "$out/$kind/verdict.txt"
    return
  fi
  allowance=$(( limit - 150 ))
  mkdir -p "$direct"
  # The walk writes each picture here as it takes it (JUKEBOX_SHOTS in the
  # test: xcodebuild hands TEST_RUNNER_ variables over without the prefix).
  export TEST_RUNNER_JUKEBOX_SHOTS=$direct
  echo "$label: $test on the $kind, at most $limit s"
  # Crash reports written after this moment are this walk's (crashes, below).
  touch "$work/started-$label"
  bounded "$limit" xcodebuild test-without-building -project Jukebox.xcodeproj -scheme Jukebox \
    -destination "$destination" -derivedDataPath "$derived" \
    -only-testing:"JukeboxUITests/$class/$test" -resultBundlePath "$result" \
    -parallel-testing-enabled NO -test-timeouts-enabled YES \
    -default-test-execution-time-allowance "$allowance" \
    -maximum-test-execution-time-allowance "$allowance" \
    > "$out/$label.log" 2>&1
  grep -E 'PICTURE|MISSED|error:|[Cc]rash|Test Case .*(passed|failed|skipped)|TEST EXECUTE' "$out/$label.log" \
    | head -100
  verdict=$(bounded 120 xcrun xcresulttool get test-results summary --path "$result" 2>/dev/null \
    | verdict)
  echo "$label: $verdict" >> "$out/$kind/verdict.txt"
  crashes "$kind" "$udid" "$label"
  mkdir -p "$work/attachments/$label"
  if [[ -d $result ]]; then
    bounded 300 xcrun xcresulttool export attachments --path "$result" \
      --output-path "$work/attachments/$label" > "$work/export-$label.log" 2>&1 \
      || problem "$label: no pictures exported from its result ($(tail -1 "$work/export-$label.log"))"
  else
    problem "$label: no result bundle ($label.log)"
  fi
  pictures=$(collect "$work/attachments/$label" "$direct" "$out/$kind" "$label")
  echo "$label: $verdict; $pictures pictures"
}

# XCTest ends a walk whose app stops answering its questions for a while
# ("Timed out while evaluating UI query": the 13-inch's walk after its first
# picture, on the run of c617121). An iPad's walk goes once more then, while
# there is time: signed in already, its pictures, named as Linux names its
# own, replace the first try's. Not the iPhone's: numbered as they are taken,
# a second try's pictures would not line up with the first's.
walk_again() {
  if grep -q 'Timed out while evaluating UI query' "$out/$3.log" 2> /dev/null; then
    walk "$1" "$2" "$3-again" "$4"
  fi
}

# The Mac's snapshots: the app's screens drawn offscreen against the fake
# Jellyfin, dark and light, into mac-snap/. Its files go to a home of its
# own (CFFIXED_USER_HOME), not the laptop's Application Support; what
# UserDefaults keeps of it (an id) goes after.
snapshots_round() {
  local started=$SECONDS limit pictures
  group "The Mac's snapshots: $(cat "$out/mac-snap/device.txt")"
  limit=$(allow 240)
  if (( limit < 60 )); then
    problem "mac-snap: not made, no time left"
    echo "mac-snap: not made (no time left)" >> "$out/mac-snap/verdict.txt"
    endgroup
    return
  fi
  mkdir -p "$work/snap-home"
  # A fake Jellyfin of their own, on 8097: what the snapshots make ready
  # (a queue, this Mac as a device) never shows in the walks' pictures, a
  # "Playing on" card for the laptop on the iPhone's Home.
  local snap_server
  # shellcheck disable=SC2086 # two words, or none
  "$work/fake-jellyfin" --port 8097 --data dev/demo --song-lengths $handoff \
    > "$out/fake-jellyfin-snap.log" 2>&1 < /dev/null &
  snap_server=$!
  for _ in $(seq 1 40); do
    curl -fsS -m 2 http://localhost:8097/System/Info/Public > /dev/null 2>&1 && break
    sleep 0.5
  done
  CFFIXED_USER_HOME="$PWD/$work/snap-home" bounded "$limit" \
    "$work/derived-snap/Build/Products/Debug/JukeboxSnapshots.app/Contents/MacOS/JukeboxSnapshots" \
    "$PWD/$out/mac-snap" localhost:8097 -deviceID snapshots > "$out/mac-snap.log" 2>&1
  kill "$snap_server" 2> /dev/null
  wait "$snap_server" 2> /dev/null
  # Preferences ignore CFFIXED_USER_HOME: whatever a store wrote there goes.
  defaults delete com.tijmen.Jukebox.Snapshots > /dev/null 2>&1
  rm -f "$HOME/Library/Preferences/com.tijmen.Jukebox.Snapshots.plist"
  grep -E 'PICTURE|SNAPSHOT' "$out/mac-snap.log"
  pictures=$(ls "$out/mac-snap"/*.png 2> /dev/null | wc -l | tr -d " ")
  echo "mac-snap: $pictures pictures in $(( SECONDS - started )) s" | tee -a "$out/mac-snap/verdict.txt"
  if [[ -s $out/mac-snap/missed.txt ]]; then sed -i '' 's/^/mac-snap: /' "$out/mac-snap/missed.txt"; fi
  (( pictures > 0 )) || problem "mac-snap: no pictures (mac-snap.log)"
  endgroup
}

# A device's round: its simulator booted and made to look the same each time,
# a first start of the app, then its walks.
round() {
  local kind=$1
  local udid_var="udid_$1"
  local udid=${!udid_var}
  group "The $kind: $(cat "$out/$kind/device.txt")"
  if [[ $kind == mac ]]; then
    mac_settings
    # The runner's desktop dark, and black behind the window: a window's
    # picture is its rectangle, and what lies behind its round corners
    # shows in them.
    osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true' \
      -e 'tell application "System Events" to set picture of every desktop to "/System/Library/Desktop Pictures/Solid Colors/Black.png"' \
      > /dev/null 2>&1 || problem "the Mac's desktop did not turn dark and black"
    # A screen that holds the store's window, 1440 x 900 under the menu bar
    # (the runner's is 1024 x 768), and no Dock taking its foot.
    if bounded "$(allow 300)" xcrun swiftc -O dev/mac-display.swift -o "$work/mac-display" \
        > "$work/mac-display-build.log" 2>&1; then
      "$work/mac-display" "$work/display-mode.txt" \
        || problem "the Mac's display stayed too small for a window of 1440 x 900"
    else
      problem "dev/mac-display.swift did not build"
      tail -20 "$work/mac-display-build.log"
    fi
    if [[ $saved_autohide != 1 ]]; then defaults write com.apple.dock autohide -bool true && killall Dock; fi
    # Scroll bars only while scrolling, as with a trackpad: a Mac with a
    # mouse, the runner, shows them always, under every shelf.
    defaults write -g AppleShowScrollBars -string WhenScrolling
    sleep 3
    walk mac testMac mac-dark 720
    restore_mac
    endgroup
    return
  fi
  if ! bounded "$(allow 600)" xcrun simctl bootstatus "$udid" -b > "$work/boot-$kind.log" 2>&1; then
    problem "the $kind simulator did not boot ($(tail -1 "$work/boot-$kind.log"))"
    echo "not walked: the simulator did not boot" >> "$out/$kind/verdict.txt"
    endgroup
    return
  fi
  local dark=true
  if ! appearance "$udid" dark; then
    dark=false
    problem "the $kind simulator did not turn dark, so its dark walks are not walked"
  fi
  status_bar "$udid" "$kind"
  # A fresh simulator explains slide-to-type over the keyboard the first time
  # it shows; that would lie over the sign-in.
  sim spawn "$udid" defaults write com.apple.keyboard.preferences DidShowContinuousPathIntroduction -bool true \
    || true
  # Reduce Motion: the station badge's waveform then stands still. XCTest
  # waits for an app's animations to end before each step, and an endless
  # one would make each step wait for its timeout. The screens look the same.
  sim spawn "$udid" defaults write com.apple.Accessibility ReduceMotionEnabled -bool true || true
  # A first start: no app, no session in the keychain, so the walk begins
  # at the welcome.
  sim uninstall "$udid" com.tijmen.Jukebox > /dev/null 2>&1 || true
  sim keychain "$udid" reset || problem "the $kind simulator's keychain was not reset"
  if ! $dark && [[ $kind != iphone ]]; then
    echo "$kind-dark: not walked: the simulator stayed light" >> "$out/$kind/verdict.txt"
    bounded 120 xcrun simctl shutdown "$udid" > /dev/null 2>&1 || true
    endgroup
    return
  fi
  case $kind in
    iphone)
      if $dark; then
        walk iphone testPhone iphone-dark 1200
      else
        echo "iphone-dark: not walked: the simulator stayed light" >> "$out/$kind/verdict.txt"
      fi
      if appearance "$udid" light; then
        status_bar "$udid" "$kind"
        walk iphone testPhoneLight iphone-light 480
      else
        problem "the iPhone simulator did not turn light, so its light walk is not walked"
        echo "iphone-light: not walked: the simulator did not turn light" >> "$out/$kind/verdict.txt"
      fi
      ;;
    # Linux's walk, some twenty pictures: 450 s with every wide step a skip
    # (run of da76341), and once music plays each step waits 10 to 40 s for
    # the app to be idle, so the merged walk, all its steps real, needs more.
    ipad)
      walk ipad testPad ipad-dark 1080
      walk_again ipad testPad ipad-dark 1080
      ;;
    ipad11)
      walk ipad11 testPadUpright ipad11-dark 480
      walk_again ipad11 testPadUpright ipad11-dark 480
      ;;
  esac
  bounded 120 xcrun simctl shutdown "$udid" > /dev/null 2>&1 || true
  endgroup
}

for kind in $ready; do
  if [[ $kind == mac-snap ]]; then
    if $built_snap && [[ -n $server ]]; then
      snapshots_round
    elif $built_snap; then
      problem "mac-snap: not made, the fake Jellyfin is not running"
    fi
  elif [[ $kind == mac ]]; then
    if $built_mac; then round mac; fi
  elif $built; then
    round "$kind"
  fi
done
stop_server

# --- Contact sheets ----------------------------------------------------------

group "Contact sheets"
for kind in $devices; do
  [[ -n $sheet_tool ]] || break
  ls "$out/$kind"/*.png > /dev/null 2>&1 || continue
  bounded 90 "$sheet_tool" "$out/$kind" "$out/$kind-sheet.png" "$out/$kind-sheet.jpg" \
    "Jukebox · $(cat "$out/$kind/device.txt") · $short" || problem "no contact sheet for the $kind"
done
endgroup

# --- The screenshots branch --------------------------------------------------

title_of() {
  case $1 in
    iphone) echo "iPhone" ;;
    ipad) echo "iPad" ;;
    ipad11) echo "iPad, upright" ;;
    mac) echo "Mac" ;;
    mac-snap) echo "Mac, drawn offscreen" ;;
    *) echo "$1" ;;
  esac
}

count_of() {
  local n=0 file
  for file in "$out/$1"/*.png; do
    if [[ -f $file ]]; then n=$(( n + 1 )); fi
  done
  echo "$n"
}

readme() {
  echo "# Jukebox, as it looks"
  echo
  echo "Every main screen of the app, walked in the iOS Simulator on GitHub's Mac against a made-up"
  echo "Jellyfin library (\`dev/fake-jellyfin.swift\`), by \`ci/screenshots.sh\` after each push. This branch"
  echo "holds the latest round of main at its top, and the latest of each work branch in"
  echo "\`branches/<name>/\`: each round replaces its own. The iPad's pictures are named as their twins"
  echo "in Linux's walk (\`Linux/App/Shots.swift\`, 1440x900; upright, 760x900)."
  echo
  echo "From \`$short\` on \`$ref\`, run ${GITHUB_RUN_NUMBER:-local}, $(date -u '+%Y-%m-%d %H:%M UTC')."
  for kind in $devices; do
    [[ -d $out/$kind ]] || continue
    echo
    echo "## $(title_of "$kind")"
    echo
    echo "$(cat "$out/$kind/device.txt" 2> /dev/null), $(count_of "$kind") pictures."
    echo "[Every picture]($kind/) · [the sheet at full size]($kind-sheet.png)"
    echo
    if [[ -f $out/$kind/verdict.txt ]]; then
      sed 's/^/- /' "$out/$kind/verdict.txt"
      echo
    fi
    if [[ -f $out/$kind-sheet.jpg ]]; then
      echo "[![The $(title_of "$kind")'s screens]($kind-sheet.jpg)]($kind-sheet.png)"
      echo
    fi
    if [[ -s $out/$kind/missed.txt ]]; then
      echo "Steps that found nothing to tap:"
      echo
      echo '```'
      cat "$out/$kind/missed.txt"
      echo '```'
    fi
  done
  if [[ -s $work/problems.txt ]]; then
    echo
    echo "## Problems in this round"
    echo
    sed 's/^/- /' "$work/problems.txt"
  fi
}

# Where on the screenshots branch: main's round at its top, where
# the README's links and the photographer's bookmarks point; a work branch's
# in a folder of its own, so that its round never replaces main's pictures.
case $ref in
  main) place= ;;
  *) place="branches/${ref//\//-}/" ;;
esac
pushed=false
# The push may take what is left before ci/app.sh's watchdog (the budget and
# 120 s), less a little for the summary and the sheets printed after it: a
# slow push must not cost the lead the sheets in the log.
push_limit=$(( budget + 100 - (SECONDS - start) ))
if (( push_limit > 180 )); then push_limit=180; fi
push_until=$(( SECONDS + push_limit ))
if [[ -n ${GH_TOKEN:-} && -n $repo && ${NO_PUSH:-} != 1 ]] && ls "$out"/*/*.png > /dev/null 2>&1; then
  group "Onto the screenshots branch, ${place:-its top}"
  # This round's part of the branch, as it goes there.
  part="$PWD/$work/part"
  mkdir -p "$part/logs"
  for kind in $devices; do
    [[ -d $out/$kind ]] && cp -R "$out/$kind" "$part/"
    for sheet in "$out/$kind-sheet.png" "$out/$kind-sheet.jpg"; do
      [[ -f $sheet ]] && cp "$sheet" "$part/"
    done
  done
  # The walks' logs and the fake server's; the simulator build's errors only
  # (its whole log is many megabytes, and in the artifact).
  for log in "$out"/*.log "$out"/*.ips; do
    [[ -f $log && $log != */build-for-testing*.log ]] && cp "$log" "$part/logs/"
  done
  grep -E 'error:' "$out/build-for-testing.log" 2> /dev/null | sed "s#$PWD/##g" | sort -u \
    > "$part/logs/build-for-testing-errors.txt"
  grep -E 'error:' "$out/build-for-testing-mac.log" 2> /dev/null | sed "s#$PWD/##g" | sort -u \
    > "$part/logs/build-for-testing-mac-errors.txt"
  readme > "$part/README.md"
  remote="https://x-access-token:${GH_TOKEN}@github.com/$repo.git"
  # The branch as it is, with this round's place emptied and filled again,
  # as one new commit without a parent, so the branch stays one commit. The
  # lease refuses the push when another round pushed since the clone (main's
  # and a work branch's runs can end together): then once more, from the
  # newer branch. No branch at all yet: the lease expects none.
  for try in 1 2; do
    if (
      branch="$PWD/$work/branch"
      rm -rf "$branch"
      old=
      if bounded "$(( push_until - SECONDS ))" git clone -q --depth 1 --branch screenshots "$remote" "$branch"; then
        old=$(git -C "$branch" rev-parse HEAD) || exit 1
      else
        rm -rf "$branch"
        git init -q "$branch" || exit 1
      fi
      cd "$branch" || exit 1
      if [[ -z $place ]]; then
        # main's: all but the work branches' folders.
        find . -mindepth 1 -maxdepth 1 ! -name .git ! -name branches -exec rm -rf {} +
      else
        rm -rf "./$place"
      fi
      mkdir -p "./$place" && cp -R "$part"/. "./$place" \
        && git symbolic-ref HEAD refs/heads/round && git add -A \
        && git -c user.name="github-actions[bot]" \
          -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
          commit -q -m "Screenshots of $short ($ref, run ${GITHUB_RUN_NUMBER:-local})" \
        && bounded "$(( push_until - SECONDS ))" git push -q --force-with-lease="screenshots:$old" \
          "$remote" HEAD:screenshots
    ) > "$work/push.log" 2>&1; then
      pushed=true
      break
    fi
  done
  if $pushed; then
    echo "On https://github.com/$repo/tree/screenshots/$place"
  else
    problem "the push to the screenshots branch failed"
    sed "s/${GH_TOKEN}/***/g" "$work/push.log" | tail -20
  fi
  endgroup
fi

# --- What happened -----------------------------------------------------------

{
  echo "## Screenshots of $short"
  for kind in $devices; do
    echo
    if [[ ! -d $out/$kind ]]; then
      echo "**$(title_of "$kind")**: not walked"
      continue
    fi
    echo "**$(title_of "$kind")** ($(cat "$out/$kind/device.txt" 2> /dev/null)): $(count_of "$kind") pictures"
    [[ -f $out/$kind/verdict.txt ]] && sed 's/^/- /' "$out/$kind/verdict.txt"
    if $pushed; then
      echo "- the sheet: https://github.com/$repo/blob/screenshots/$place$kind-sheet.png"
      echo "- every picture: https://github.com/$repo/tree/screenshots/$place$kind"
    else
      echo "- not on the screenshots branch: in this run's artifact (logs-${GITHUB_RUN_NUMBER:-local}), screenshots/$kind"
    fi
    if [[ -s $out/$kind/missed.txt ]]; then
      echo "- steps that found nothing to tap:"
      grep -v '^$' "$out/$kind/missed.txt" | sed 's/^/  - /'
    fi
  done
  if [[ -s $work/problems.txt ]]; then
    echo
    echo "Problems:"
    sed 's/^/- /' "$work/problems.txt"
  fi
} | tee -a "$summary"

if [[ -f $out/fake-jellyfin.log ]]; then
  group "The fake Jellyfin's log, its last 80 lines"
  tail -80 "$out/fake-jellyfin.log"
  endgroup
fi

for kind in $devices; do
  if [[ -s $out/$kind/missed.txt ]]; then
    echo "Missed on the $kind:"
    cat "$out/$kind/missed.txt"
  fi
done

# Last in the log, for the lead: each sheet as a JPEG, 900 pixels wide, in
# base64 lines of 76 characters.
for kind in $devices; do
  jpg="$out/$kind-sheet.jpg"
  [[ -f $jpg ]] || continue
  echo "=====BEGIN SHEET $kind====="
  base64 < "$jpg" | fold -w 76
  echo "=====END SHEET $kind====="
done
exit 0
