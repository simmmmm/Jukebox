#!/usr/bin/env bash
# The screenshot round, after the app has compiled (ci/app.sh, on every push
# without TestFlight). Steps:
#   - the fake Jellyfin with the demo library, on localhost:8096
#     (dev/fake-jellyfin.py, dev/demo);
#   - the app and its UI tests built for the simulator;
#   - every main screen walked on an iPhone in dark, Home and Now Playing
#     again in light, and the main screens on an iPad
#     (JukeboxUITests/ScreenshotTests.swift);
#   - the pictures, named, in build/logs/screenshots/<device>/, which the
#     workflow uploads with build/logs;
#   - one contact sheet per device;
#   - all of it on the `screenshots` branch, one commit that replaces the last.
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

start=$SECONDS
budget=${SHOTS_BUDGET:-2400}
devices=${SHOTS_DEVICES:-iphone ipad}
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

# --- The fake Jellyfin -------------------------------------------------------

group "The fake Jellyfin on localhost:8096"
server=
stop_server() {
  if [[ -n $server ]]; then
    kill "$server" 2>/dev/null
    wait "$server" 2>/dev/null
  fi
  server=
}
trap stop_server EXIT
if [[ -f dev/fake-jellyfin.py ]]; then
  # Unbuffered, so its log is whole when it is stopped. --song-lengths: songs
  # of 2:30 to 5:30, as a real library has, not the test library's few
  # seconds, so the album pages and the scrubber look like what a listener sees.
  PYTHONUNBUFFERED=1 python3 dev/fake-jellyfin.py --port 8096 --data dev/demo --song-lengths \
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
  problem "dev/fake-jellyfin.py is missing, so the walks stop at sign-in"
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

# The simulator for a device kind, on the newest iOS 26 or later, made when
# the runner has none: an iPhone 17 Pro, else the newest numbered iPhone (a
# Pro first); a 13-inch iPad Pro, else a 13-inch iPad, else any iPad.
# Prints "udid<TAB>name<TAB>runtime".
cat > "$work/pick.py" <<'PY'
import json, re, subprocess, sys

kind = sys.argv[1]
data = json.load(sys.stdin)


def version(runtime):
    return [int(n) for n in re.findall(r"\d+", runtime.get("version", "0"))]


runtimes = sorted((r for r in data.get("runtimes", [])
                   if r.get("isAvailable") and "SimRuntime.iOS" in r.get("identifier", "")
                   and version(r)[:1] >= [26]), key=version)
if not runtimes:
    sys.exit("no iOS 26 runtime")
runtime = runtimes[-1]


def rank(name):
    """Higher is better; None when the name is not of this kind."""
    if kind == "iphone":
        if not name.startswith("iPhone"):
            return None
        if name == "iPhone 17 Pro":
            return (3, 0)
        m = re.fullmatch(r"iPhone (\d+)( Pro)?", name)
        if m:
            return (2 if m.group(2) else 1, int(m.group(1)))
        return (0, 0)
    if not name.startswith("iPad"):
        return None
    if "13-inch" in name:
        return (2 if name.startswith("iPad Pro") else 1, 0)
    return (0, 0)


devices = [(rank(d["name"]), d["name"], d["udid"])
           for d in data.get("devices", {}).get(runtime["identifier"], [])
           if d.get("isAvailable") and rank(d["name"]) is not None]
if devices:
    _, name, udid = max(devices)
else:
    types = runtime.get("supportedDeviceTypes") or data.get("devicetypes", [])
    candidates = [(rank(t["name"]), t["name"], t["identifier"])
                  for t in types if rank(t.get("name", "")) is not None]
    if not candidates:
        sys.exit("no %s device type for %s" % (kind, runtime.get("name")))
    _, name, type_id = max(candidates)
    udid = subprocess.run(["xcrun", "simctl", "create", name, type_id, runtime["identifier"]],
                          check=True, capture_output=True, text=True).stdout.strip()
print("\t".join([udid, name, runtime.get("name", "iOS")]))
PY

ready=
bounded 120 xcrun simctl list -j > "$work/simctl.json" 2> "$work/simctl.err" \
  || problem "xcrun simctl list failed: $(tail -1 "$work/simctl.err")"
for kind in $devices; do
  if line=$(bounded 180 python3 "$work/pick.py" "$kind" < "$work/simctl.json" 2> "$work/pick-$kind.err"); then
    IFS=$'\t' read -r udid name runtime <<< "$line"
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
if [[ -n $ready ]]; then
  [[ -d Jukebox.xcodeproj ]] || xcodegen generate
  first="udid_${ready%% *}"
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
endgroup

# --- The walks ---------------------------------------------------------------

cat > "$work/verdict.py" <<'PY'
import json, sys

try:
    summary = json.load(sys.stdin)
except Exception:
    print("no result")
    sys.exit()
line = str(summary.get("result", "no result"))
# A walk whose only failures are XCTest's own complaints inside
# XCTExpectFailure ("not hittable") is reported so; they are the missed list.
if line == "Expected Failure":
    line = "Passed (XCTest's complaints about missed steps were expected)"
failures = [f.get("failureText", "") for f in summary.get("testFailures", [])]
if failures:
    line += ": " + " / ".join(failures)[:400]
print(line)
PY

# The pictures of one walk, named as the test named them, into the device's
# folder; its missed list into the folder's missed.txt. Prints how many.
# Two sources: the files the walk wrote itself (JUKEBOX_SHOTS), there even
# when the runner was stopped, and the result's exported attachments
# (manifest.json), there when the files could not be written. The files win.
cat > "$work/collect.py" <<'PY'
import json, os, re, shutil, sys

export, direct, dst, label = sys.argv[1:5]
os.makedirs(dst, exist_ok=True)
PICTURES = (".png", ".jpg", ".jpeg")
# The walk's own names, "07-albums" or "light-01-home": not XCTest's own
# screenshots and recordings, which a result can hold as well.
WALK = re.compile(r"^(?:[a-z]+-)?\d{2,}-")
pictures = {}  # name -> source file
missed = {}  # "export" or "direct" -> source file
manifest = os.path.join(export, "manifest.json")
try:
    with open(manifest, encoding="utf-8") as f:
        tests = json.load(f)
except (OSError, ValueError):
    tests = []
for test in tests if isinstance(tests, list) else []:
    for attachment in test.get("attachments", []):
        src = os.path.join(export, attachment.get("exportedFileName") or "-")
        if not os.path.isfile(src):
            continue
        # "05-home-scrolled_0_<UUID>.png": the name the test gave.
        given = attachment.get("suggestedHumanReadableName") or ""
        name = os.path.splitext(given)[0].split("_")[0]
        if name.startswith("missed"):
            missed["export"] = src
        elif WALK.match(name) and os.path.splitext(src)[1].lower() in PICTURES:
            pictures[name] = src
if os.path.isdir(direct):
    for file in sorted(os.listdir(direct)):
        name, ext = os.path.splitext(file)
        if name.startswith("missed") and ext == ".txt":
            missed["direct"] = os.path.join(direct, file)
        elif ext.lower() in PICTURES:
            pictures[name] = os.path.join(direct, file)
for name, src in pictures.items():
    shutil.copy(src, os.path.join(dst, name + os.path.splitext(src)[1].lower()))
source = missed.get("direct") or missed.get("export")
if source:
    with open(source, encoding="utf-8", errors="replace") as f:
        # "Nothing missed." is the walk saying so: no line for it.
        lines = [l.strip() for l in f if l.strip() and l.strip() != "Nothing missed."]
    with open(os.path.join(dst, "missed.txt"), "a", encoding="utf-8") as f:
        for line in lines:
            f.write("%s: %s\n" % (label, line))
print(len(pictures))
PY

# One walk: one test on a device's simulator, at most $4 seconds, and its
# pictures exported. xcodebuild's own test timeout ends a stuck test with a
# result bundle intact; the perl alarm is the last resort. The allowance
# leaves 150 s to xcodebuild: XCTest rounds it up to a whole minute, and
# installing and starting the runner comes before it.
walk() {
  local kind=$1 test=$2 label=$3 limit allowance verdict pictures
  local udid_var="udid_$1"
  local udid=${!udid_var} result="$work/$label.xcresult" direct="$PWD/$work/direct/$label"
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
  bounded "$limit" xcodebuild test-without-building -project Jukebox.xcodeproj -scheme Jukebox \
    -destination "id=$udid" -derivedDataPath "$work/derived" \
    -only-testing:"JukeboxUITests/ScreenshotTests/$test" -resultBundlePath "$result" \
    -parallel-testing-enabled NO -test-timeouts-enabled YES \
    -default-test-execution-time-allowance "$allowance" \
    -maximum-test-execution-time-allowance "$allowance" \
    > "$out/$label.log" 2>&1
  grep -E 'PICTURE|MISSED|error:|[Cc]rash|Test Case .*(passed|failed|skipped)|TEST EXECUTE' "$out/$label.log" \
    | head -100
  verdict=$(bounded 120 xcrun xcresulttool get test-results summary --path "$result" 2>/dev/null \
    | python3 "$work/verdict.py")
  echo "$label: $verdict" >> "$out/$kind/verdict.txt"
  mkdir -p "$work/attachments/$label"
  if [[ -d $result ]]; then
    bounded 300 xcrun xcresulttool export attachments --path "$result" \
      --output-path "$work/attachments/$label" > "$work/export-$label.log" 2>&1 \
      || problem "$label: no pictures exported from its result ($(tail -1 "$work/export-$label.log"))"
  else
    problem "$label: no result bundle ($label.log)"
  fi
  pictures=$(python3 "$work/collect.py" "$work/attachments/$label" "$direct" "$out/$kind" "$label")
  echo "$label: $verdict; $pictures pictures"
}

# A device's round: its simulator booted and made to look the same each time,
# a first start of the app, then its walks.
round() {
  local kind=$1
  local udid_var="udid_$1"
  local udid=${!udid_var}
  group "The $kind: $(cat "$out/$kind/device.txt")"
  if ! bounded "$(allow 600)" xcrun simctl bootstatus "$udid" -b > "$work/boot-$kind.log" 2>&1; then
    problem "the $kind simulator did not boot ($(tail -1 "$work/boot-$kind.log"))"
    echo "not walked: the simulator did not boot" >> "$out/$kind/verdict.txt"
    endgroup
    return
  fi
  sim ui "$udid" appearance dark || problem "the $kind simulator did not turn dark"
  # Apple's own 9:41 and full bars, not the runner's time.
  sim status_bar "$udid" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100 \
    || problem "the $kind simulator's status bar kept the runner's time"
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
  if [[ $kind == iphone ]]; then
    walk iphone testPhone iphone-dark 1200
    sim ui "$udid" appearance light || problem "the iPhone simulator did not turn light"
    walk iphone testPhoneLight iphone-light 480
  else
    walk ipad testPad ipad-dark 720
  fi
  bounded 120 xcrun simctl shutdown "$udid" > /dev/null 2>&1 || true
  endgroup
}

if $built; then
  for kind in $ready; do
    round "$kind"
  done
fi
stop_server

# --- Contact sheets ----------------------------------------------------------

group "Contact sheets"
# Pillow: already there, else in a venv of its own (Homebrew's Python refuses
# installs outside one), else for the user. Homebrew's python3 first, then
# Apple's (/usr/bin/python3, Xcode's): Numa-mac's Mac once had a Homebrew
# Python whose venv came without pip.
# At most 150 s of the five minutes kept for the end, however the tries go.
py=
pillow_until=$(( SECONDS + 150 ))
: > "$work/pillow.log"
for base in python3 /usr/bin/python3; do
  if "$base" -c 'import PIL' 2> /dev/null; then
    py=$base
    break
  fi
done
if [[ -z $py ]]; then
  n=0
  for base in python3 /usr/bin/python3; do
    n=$(( n + 1 ))
    if bounded "$(( pillow_until - SECONDS ))" "$base" -m venv "$work/venv$n" >> "$work/pillow.log" 2>&1 \
        && bounded "$(( pillow_until - SECONDS ))" "$work/venv$n/bin/python" -m pip install --quiet pillow >> "$work/pillow.log" 2>&1; then
      py="$work/venv$n/bin/python"
      break
    fi
  done
fi
if [[ -z $py ]]; then
  if bounded "$(( pillow_until - SECONDS ))" python3 -m pip install --quiet --user pillow >> "$work/pillow.log" 2>&1 \
      || bounded "$(( pillow_until - SECONDS ))" python3 -m pip install --quiet --user --break-system-packages pillow >> "$work/pillow.log" 2>&1; then
    py=python3
  else
    problem "no Pillow, so no contact sheets ($(tail -1 "$work/pillow.log"))"
  fi
fi
for kind in $devices; do
  [[ -n $py ]] || break
  ls "$out/$kind"/*.png > /dev/null 2>&1 || continue
  bounded 90 "$py" dev/contact-sheet.py "$out/$kind" "$out/$kind-sheet.png" "$out/$kind-sheet.jpg" \
    "Jukebox · $(cat "$out/$kind/device.txt") · $short" || problem "no contact sheet for the $kind"
done
endgroup

# --- The screenshots branch --------------------------------------------------

title_of() {
  case $1 in
    iphone) echo "iPhone" ;;
    ipad) echo "iPad" ;;
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
  echo "Jellyfin library (\`dev/fake-jellyfin.py\`), by \`ci/screenshots.sh\` after each push. This branch"
  echo "holds the latest round only: each round replaces it."
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

pushed=false
# The push may take what is left before ci/app.sh's watchdog (the budget and
# 120 s), less a little for the summary and the sheets printed after it: a
# slow push must not cost the lead the sheets in the log.
push_limit=$(( budget + 100 - (SECONDS - start) ))
if (( push_limit > 180 )); then push_limit=180; fi
if [[ -n ${GH_TOKEN:-} && -n $repo && ${NO_PUSH:-} != 1 ]] && ls "$out"/*/*.png > /dev/null 2>&1; then
  group "Onto the screenshots branch"
  branch="$work/branch"
  mkdir -p "$branch/logs"
  for kind in $devices; do
    [[ -d $out/$kind ]] && cp -R "$out/$kind" "$branch/"
    for sheet in "$out/$kind-sheet.png" "$out/$kind-sheet.jpg"; do
      [[ -f $sheet ]] && cp "$sheet" "$branch/"
    done
  done
  # The walks' logs and the fake server's; the simulator build's errors only
  # (its whole log is many megabytes, and in the artifact).
  for log in "$out"/*.log; do
    [[ -f $log && $log != */build-for-testing.log ]] && cp "$log" "$branch/logs/"
  done
  grep -E 'error:' "$out/build-for-testing.log" 2> /dev/null | sed "s#$PWD/##g" | sort -u \
    > "$branch/logs/build-for-testing-errors.txt"
  readme > "$branch/README.md"
  if (
    cd "$branch" || exit 1
    git init -q . && git symbolic-ref HEAD refs/heads/screenshots && git add -A \
      && git -c user.name="github-actions[bot]" \
        -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
        commit -q -m "Screenshots of $short ($ref, run ${GITHUB_RUN_NUMBER:-local})" \
      && bounded "$push_limit" git push -q -f "https://x-access-token:${GH_TOKEN}@github.com/$repo.git" HEAD:screenshots
  ) > "$work/push.log" 2>&1; then
    pushed=true
    echo "On https://github.com/$repo/tree/screenshots"
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
      echo "- the sheet: https://github.com/$repo/blob/screenshots/$kind-sheet.png"
      echo "- every picture: https://github.com/$repo/tree/screenshots/$kind"
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
  python3 -c 'import base64, sys; sys.stdout.write(base64.encodebytes(open(sys.argv[1], "rb").read()).decode())' "$jpg"
  echo "=====END SHEET $kind====="
done
exit 0
