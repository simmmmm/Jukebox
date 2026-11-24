#!/usr/bin/env bash
# CI's app job (.github/workflows/ci.yml, on GitHub's macOS): the Xcode
# project from project.yml, then either
#   - the app compiled (every push) for the iPhone, signed ad hoc and its
#     signature checked for CarPlay and the widget, then for the Mac, signed
#     ad hoc and checked for the widget, then, when the iPhone's compiled,
#     the pictures of its
#     screens (ci/screenshots.sh), or
#   - with TESTFLIGHT=true: archived, signed by Xcode itself with the App
#     Store Connect API key (role Admin: it makes the certificate and the
#     profile, no Mac of the photographer's needed) and uploaded, the
#     iPhone's and then the Mac's, to the same App Store Connect record.
# The compiler's errors go to the run's summary page, so a failed build
# reads without opening the log.
set -euo pipefail
cd "$(dirname "$0")/.."
# Every log of build/logs (the run's artifact, and the screenshots' logs)
# and the summary without the runner's home, user or machine name, however
# the run ends (ci/redact.sh): in both shells below, so a run cancelled
# while the inner one works is cleaned too.
trap 'bash ci/redact.sh build/logs "${GITHUB_STEP_SUMMARY:-}" || true' EXIT
# The job's console without the runner's home, user or machine name, as the
# logs below (ci/redact.sh): the script runs again with its output through
# the redactor, a line at a time so the log still streams, and ends with
# the script's own status. GitHub's ::group:: and ::error:: lines pass as
# they are.
if [[ -z ${JUKEBOX_REDACTED:-} ]]; then
  set +e
  JUKEBOX_REDACTED=1 bash ci/app.sh "$@" 2>&1 | (unset GH_TOKEN ASC_KEY_P8 ASC_KEY_ID ASC_ISSUER_ID; bash ci/redact.sh -)
  exit "${PIPESTATUS[0]}"
fi
# One app job at a time on the MacBook, whichever of its runners took it: two
# at once kept it at 100% CPU, and the simulators' own apps missed their
# launch watchdog and crashed onto the photographer's screen ("1 want als
# het steeds crashed ga je nog langzamer", 24 November 2026). The lock is a
# directory with the holder's PID: one left by a cancelled job is taken over.
if [[ ${RUNNER_ENVIRONMENT:-} == self-hosted && $(uname) == Darwin ]]; then
  job_lock=/tmp/jukebox-app-job.lock
  until mkdir "$job_lock" 2> /dev/null; do
    holder=$(cat "$job_lock/pid" 2> /dev/null || true)
    if [[ -n $holder ]] && kill -0 "$holder" 2> /dev/null; then
      echo "Waiting for the other app job on this Mac (PID $holder) to finish."
      sleep 20
    else
      sleep 2
      holder=$(cat "$job_lock/pid" 2> /dev/null || true)
      [[ -n $holder ]] && kill -0 "$holder" 2> /dev/null || rm -rf "$job_lock"
    fi
  done
  echo $$ > "$job_lock/pid"
  trap '[[ $(cat "$job_lock/pid" 2> /dev/null) == "$$" ]] && rm -rf "$job_lock"; bash ci/redact.sh build/logs "${GITHUB_STEP_SUMMARY:-}" || true' EXIT
fi
# The App Store Connect key only for a run that uploads, from main or a
# "-testflight" branch: every other run, and everything it starts (the
# tree's scripts, XcodeGen, xcodebuild's phases), never has it. First, so
# nothing below sees it. ponytail: a branch can still change this script;
# a GitHub Environment for main is the lock that holds.
case ${GITHUB_REF_NAME:-} in
  main | *-testflight) [[ ${TESTFLIGHT:-false} == true ]] || unset ASC_KEY_P8 ASC_KEY_ID ASC_ISSUER_ID ;;
  *) unset ASC_KEY_P8 ASC_KEY_ID ASC_ISSUER_ID ;;
esac
# GitHub's token only for the push of the screenshots branch
# (screenshots()): XcodeGen, xcodebuild and the tree's own scripts run
# without it. The copy actions/checkout leaves in .git/config goes too.
gh_token=${GH_TOKEN:-}
unset GH_TOKEN GITHUB_TOKEN
git config --local --unset-all http.https://github.com/.extraheader 2> /dev/null || true
# On the MacBook (a self-hosted runner) the folder outlives a run: a run
# cancelled by the next push may still have an xcodebuild writing in
# build/, and the next run then broke on its build database ("disk I/O
# error", run 44755707683). So first whatever still holds a file in build/
# is stopped, then build/ goes, whole. Only this checkout's processes: the
# Mac's other runners (Numa's) build in folders of their own.
if [[ ${RUNNER_ENVIRONMENT:-} == self-hosted && -d build ]]; then
  pids=$(lsof -t +D build 2>/dev/null | sort -u || true)
  if [[ -n $pids ]]; then
    echo "Stopping what a run before left writing in build/: $pids"
    kill $pids 2>/dev/null || true
    sleep 3
    kill -9 $pids 2>/dev/null || true
  fi
  rm -rf build
fi
mkdir -p build/logs
# The asset catalog's accent as Tokens.swift has it (docs/design/SYSTEM.md).
dev/accent-check.sh

# The Mac compiles (run 43621164893, 14 November 2026): its build is part of
# the job's verdict. False again makes a red Mac build only a warning.
mac_gates=true
# A [testflight] run uploads the Mac too: App Store Connect's Jukebox has
# the macOS platform since 16 November 2026. False again uploads the
# iPhone's build only.
mac_upload=true

# Uploads and screenshots belong to main. On a work branch a commit
# that happens to name the upload's token uploads nothing, and the job is the
# two builds only, quick to iterate on; a branch ending in "walk" keeps the
# screenshots, for working on the walk itself.
case ${GITHUB_REF_NAME:-main} in
  main) ;;
  # The App Store's pictures (docs/RELEASE.md, Screenshots): the Mac's
  # window, the iPhone and the iPad; the iPad last, as main's round has its
  # pictures already should time run short. The iPhone is the walk's own,
  # the 17 Pro: its 1206 x 2622 is the size App Store Connect requires.
  # SHOTS_IPHONE="iPhone 17 Pro Max" here walks the large display instead,
  # for the optional set (1320 x 2868).
  store-walk) TESTFLIGHT=false; export SHOTS_DEVICES="mac iphone ipad" ;;
  # The Mac's walk alone, to work on it: a quarter of the store's round.
  store-mac-walk) TESTFLIGHT=false; export SHOTS_DEVICES=mac ;;
  # A design to hold in the hand before it goes on main: a branch ending
  # in "-testflight" uploads as main does, when its commit says so. "hou de
  # andere ook even ik wil het zelf testen" (the photographer, 20 November
  # 2026), two versions of the iPhone's player side by side in TestFlight.
  *-testflight) ;;
  *walk) TESTFLIGHT=false ;;
  *) TESTFLIGHT=false; SCREENSHOTS=${SCREENSHOTS:-false} ;;
esac

# The newest released Xcode the runner has, 26 or later: from April 2027
# the store takes only builds made with the iOS 27 SDK (ITMS-90725, on
# build 306 of 19 November 2026).
ls -d /Applications/Xcode*.app 2>/dev/null || true
xcode=$(ls -d /Applications/Xcode_2[6-9]*.app 2>/dev/null | grep -iv beta | sort -V | tail -1 || true)
# DEVELOPER_DIR rather than `sudo xcode-select`: the same on GitHub's
# machines, and no password asked on the photographer's MacBook, a runner
# of its own ("kunnen we ook m'n laptop gaan gebruiken als runner", 20
# November 2026), whose one Xcode is plain /Applications/Xcode.app.
if [[ -n $xcode ]]; then export DEVELOPER_DIR="$xcode/Contents/Developer"; fi
xcodebuild -version | tee build/logs/xcode-version.txt

# XcodeGen: the release's own binary on every runner, pinned by version and
# sha256 (the release's own digest), as dev/linux-appimage.sh pins its
# tools; never Homebrew's or one already on the PATH. The zip is kept beside
# the runner's work, but the MacBook keeps its files between runs, any
# branch's: so on every run the zip is copied into this run's own folder,
# its digest checked there, and unpacked there afresh.
xcodegen_version=2.48.0
xcodegen_sha256=620c9f0dc10849f94728ab5df52d225ebab8187439dd6fee1925e59e80dff892
tools="${RUNNER_TOOL_CACHE:-$HOME/.cache}/xcodegen-$xcodegen_version"
xcodegen_run=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/xcodegen.XXXXXX")
xcodegen_zip=$xcodegen_run/xcodegen.zip
pinned() { echo "$xcodegen_sha256  $xcodegen_zip" | shasum -a 256 -c --quiet > /dev/null 2>&1; }
cp "$tools/xcodegen.zip" "$xcodegen_zip" 2> /dev/null || true
if ! pinned; then
  curl -fsSL -o "$xcodegen_zip" \
    "https://github.com/yonaskolb/XcodeGen/releases/download/$xcodegen_version/xcodegen.zip"
  pinned || { echo "::error::xcodegen.zip: not the pinned sha256"; exit 1; }
  # Into the cache whole or not at all: two runners on the MacBook share it.
  mkdir -p "$tools"
  cp "$xcodegen_zip" "$tools/xcodegen.zip.$$" && mv -f "$tools/xcodegen.zip.$$" "$tools/xcodegen.zip"
fi
unzip -oq "$xcodegen_zip" -d "$xcodegen_run"
export PATH="$xcodegen_run/xcodegen/bin:$PATH"
xcodegen generate

# Jukebox's own Last.fm key, so the radio knows who sounds like whom
# without a key typed into each device: "Ik denk dat een eigen last fm
# verstandiger is" (the photographer, 21 November 2026). From the runner's
# file (docs/RELEASE.md, Last.fm's key), never from git: the repository is
# public. Handed to the four builds below in their environment, which
# project.yml's `$(LASTFM_APP_KEY)` reads, and not as an argument:
# xcodebuild repeats its arguments at the top of the log, which is uploaded.
# Not exported, so the screenshots' builds have none. GitHub's own runners
# have no file, and build without a key.
lastfm_file=$HOME/.config/jukebox-ci/lastfm-app-key
lastfm_key=
if [[ -r $lastfm_file ]]; then
  lastfm_key=$(tr -d ' \t\r\n' < "$lastfm_file")
  echo "::add-mask::$lastfm_key"
fi
# The key in a built app's Info.plist, by its length alone; when the runner
# has one, an app without it is an error.
lastfm_in() {
  local plist=$1/Info.plist length
  if [[ -d $1/Contents ]]; then plist=$1/Contents/Info.plist; fi
  length=$(/usr/libexec/PlistBuddy -c "Print :LastFMAppKey" "$plist" 2> /dev/null | tr -d '\n' | wc -c | tr -d ' ')
  echo "Last.fm app key in the $2: $length characters (the runner's: ${#lastfm_key})."
  if [[ $length != "${#lastfm_key}" ]]; then
    echo "::error::The $2 lacks the runner's Last.fm key (docs/RELEASE.md, Last.fm's key)."
    return 1
  fi
}

# The errors, once each, without the runner's path, on the summary page.
report() {
  local log=$1 title=$2
  {
    echo "### $title"
    grep -E '(error|warning: .*(will be an error|is unavailable))' "$log" | grep -v '^warning: ' \
      | sed "s#$PWD/##g" | sort -u | head -120 | sed 's/^/    /'
  } >> "${GITHUB_STEP_SUMMARY:-/dev/null}" || true
}

# Pictures of every main screen (ci/screenshots.sh): walked in the simulator
# against the fake Jellyfin, put on the `screenshots` branch and printed at
# the end of this log. Never this job's verdict. It runs in a process group
# of its own, so that the watchdog (macOS has no `timeout`) can stop all of it
# at once, xcodebuild and the fake server included, if a simulator hangs: the
# job has 75 minutes, and its budget is what the build left of them, less ten
# minutes for the steps around this script, and at most 55. At 45 the
# 11-inch iPad, last, had no time left on main (run 184: the build, the
# iPhone and the 13-inch took them all).
screenshots() {
  local budget=$(( ${JOB_MINUTES:-75} * 60 - 600 - SECONDS )) pid dog
  if (( budget > 3300 )); then budget=3300; fi
  if (( budget < 600 )); then
    echo "::warning::No screenshots: the build left $budget s of the job."
    return 0
  fi
  GH_TOKEN=$gh_token SHOTS_BUDGET=$budget perl -e 'setpgrp(0, 0); exec @ARGV or die "exec: $!\n"' bash ci/screenshots.sh \
    < /dev/null &
  pid=$!
  # One perl process, nothing else: killed, it leaves nothing that holds
  # the log open.
  perl -e '
    my ($limit, $group) = @ARGV;
    sleep $limit;
    kill(0, $group) or exit 0;
    print STDERR "::warning::The screenshots ran past $limit s and were stopped.\n";
    kill("-TERM", $group);
    sleep 20;
    kill("-KILL", $group);
  ' "$(( budget + 120 ))" "$pid" &
  dog=$!
  wait "$pid" || true
  kill "$dog" 2> /dev/null || true
  # Whatever of the round is still running, stopped or finished.
  kill -TERM -- "-$pid" 2> /dev/null || true
  return 0
}

# adhoc_sign, the apps signed ad hoc with their entitlements (ci/sign.sh).
source ci/sign.sh

# Whether the app's signature has CarPlay audio and Siri, true: the archive's, the
# exported ipa's, and on every push the build's, signed as the archive is.
carplay_signed() {
  local app=$1 entitlements=build/logs/entitlements-$2.plist
  codesign -d --entitlements - --xml "$app" > "$entitlements" 2> /dev/null || true
  # Siri too: without it "Play … in Jukebox" never reaches the app, in the
  # car least of all (docs/RELEASE.md, Siri).
  local key missing=0
  for key in com.apple.developer.carplay-audio com.apple.developer.siri; do
    if [[ $(/usr/libexec/PlistBuddy -c "Print :$key" "$entitlements" 2> /dev/null) == true ]]; then
      echo "$key is in the signature ($2)."
    else
      echo "::error::No $key in the signature of the $2 (docs/RELEASE.md, CarPlay and Siri)."
      missing=1
    fi
  done
  if (( missing )); then codesign -d --entitlements - "$app" 2>&1 | head -40 || true; fi
  return $missing
}

# Whether the widget is in the app (PlugIns/JukeboxWidget.appex, on the Mac
# Contents/PlugIns/), and the app and the widget both carry the App Group the
# snapshot is written into (docs/RELEASE.md, The widget): without it in
# either signature the widget shows nothing but "Sign in". The Mac's widget
# must be sandboxed too, or macOS never loads it. The iPhone's own checks
# stay carplay_signed's.
widget_signed() {
  local app=$1 bundle part signed missing=0 plugins=$1/PlugIns mac=false
  if [[ -d $app/Contents ]]; then plugins=$app/Contents/PlugIns mac=true; fi
  for bundle in "$app" "$plugins/JukeboxWidget.appex"; do
    part=widget
    if [[ $bundle == "$app" ]]; then part=app; fi
    if [[ ! -d $bundle ]]; then
      echo "::error::No widget in the $2: $bundle is missing."
      missing=1
      continue
    fi
    # Read whole first: grep -q in a pipe under pipefail can fail a good one.
    signed=$(codesign -d --entitlements - --xml "$bundle" 2> /dev/null || true)
    if [[ $signed == *'<string>group.com.tijmen.Jukebox</string>'* ]]; then
      echo "The App Group is in the $part's signature ($2)."
    else
      echo "::error::No App Group group.com.tijmen.Jukebox in the signature of the $part ($2)."
      missing=1
    fi
    # Squeezed first: codesign's XML may break a line between key and value.
    signed=$(tr -d ' \t\n' <<< "$signed")
    if [[ $mac == true && $signed != *'<key>com.apple.security.app-sandbox</key><true/>'* ]]; then
      echo "::error::The $part is not sandboxed ($2)."
      missing=1
    fi
  done
  return $missing
}

if [[ ${TESTFLIGHT:-false} != true ]]; then
  set +e
  LASTFM_APP_KEY=$lastfm_key xcodebuild build -project Jukebox.xcodeproj -scheme Jukebox -configuration Debug \
    -destination 'generic/platform=iOS' -derivedDataPath build/derived CODE_SIGNING_ALLOWED=NO \
    > build/logs/build.log 2>&1
  status=$?
  if [[ $status == 0 ]]; then
    adhoc_sign build/derived/Build/Products/Debug-iphoneos/Jukebox.app || status=1
  fi
  if [[ $status == 0 ]]; then
    carplay_signed build/derived/Build/Products/Debug-iphoneos/Jukebox.app build
    status=$?
    widget_signed build/derived/Build/Products/Debug-iphoneos/Jukebox.app build || status=1
    lastfm_in build/derived/Build/Products/Debug-iphoneos/Jukebox.app build || status=1
  fi
  set -e
  { grep -E 'error:|BUILD (SUCCEEDED|FAILED)' build/logs/build.log || true; } | sed "s#$PWD/##g" | sort -u > build/logs/errors.txt
  head -200 build/logs/errors.txt
  # The app's own warnings too, in the log: the artifact cannot be read from
  # where the code is written, the log can.
  # Not in one pipe with head: under pipefail no warning at all (grep finds
  # nothing) or many (tee killed by head) would end the job after a good build.
  { grep -E '^/.*\.swift:[0-9]+:[0-9]+: warning:' build/logs/build.log || true; } | sed "s#$PWD/##g" | sort -u \
    > build/logs/warnings.txt
  head -80 build/logs/warnings.txt
  echo "$(wc -l < build/logs/warnings.txt | tr -d ' ') distinct Swift warnings"
  report build/logs/build.log "Compile errors"

  # The Mac: the same target, built for macOS. After the iPhone's, so a
  # Mac-only error never hides the iPhone's. Signed ad hoc, as its archive
  # is, so the signatures carry the entitlements widget_signed reads.
  set +e
  LASTFM_APP_KEY=$lastfm_key xcodebuild build -project Jukebox.xcodeproj -scheme Jukebox -configuration Debug \
    -destination 'generic/platform=macOS' -derivedDataPath build/derived-mac \
    CODE_SIGNING_ALLOWED=NO \
    > build/logs/build-mac.log 2>&1
  mac_status=$?
  if [[ $mac_status == 0 ]]; then
    adhoc_sign build/derived-mac/Build/Products/Debug/Jukebox.app || mac_status=1
  fi
  if [[ $mac_status == 0 ]]; then
    widget_signed build/derived-mac/Build/Products/Debug/Jukebox.app "Mac build" || mac_status=1
    lastfm_in build/derived-mac/Build/Products/Debug/Jukebox.app "Mac build" || mac_status=1
  fi
  set -e
  { grep -E 'error:|BUILD (SUCCEEDED|FAILED)' build/logs/build-mac.log || true; } \
    | sed "s#$PWD/##g" | sort -u > build/logs/errors-mac.txt
  head -200 build/logs/errors-mac.txt
  # The Mac's own warnings too, as the iPhone's: from macOS 15 an API
  # younger than the minimum shows here.
  { grep -E '^/.*\.swift:[0-9]+:[0-9]+: warning:' build/logs/build-mac.log || true; } | sed "s#$PWD/##g" | sort -u \
    > build/logs/warnings-mac.txt
  head -80 build/logs/warnings-mac.txt
  echo "$(wc -l < build/logs/warnings-mac.txt | tr -d ' ') distinct Swift warnings, Mac"
  report build/logs/build-mac.log "Compile errors, Mac"

  # Only of an app that compiled; SCREENSHOTS=false leaves them out.
  if [[ $status == 0 && ${SCREENSHOTS:-true} != false ]]; then
    screenshots
  fi
  # The derived data and the screenshots' work (the clone of the
  # screenshots branch, a few hundred MB), gigabytes, gone once the pictures
  # are in build/logs: the MacBook, a runner of its own, keeps its work
  # folder between runs.
  rm -rf build/derived build/derived-mac build/screenshots
  if [[ $mac_status != 0 ]]; then
    echo "::warning::The Mac build failed (build/logs/errors-mac.txt)."
    if [[ $mac_gates == true && $status == 0 ]]; then status=$mac_status; fi
  fi
  exit $status
fi

for name in APPLE_TEAM_ID ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_P8; do
  if [[ -z ${!name:-} ]]; then
    echo "::error::The secret $name is missing in this repository (see README, TestFlight)"
    exit 1
  fi
done
key_path="$RUNNER_TEMP/AuthKey_$ASC_KEY_ID.p8"
printf '%s' "$ASC_KEY_P8" > "$key_path"
auth=(-allowProvisioningUpdates
      -authenticationKeyPath "$key_path"
      -authenticationKeyID "$ASC_KEY_ID"
      -authenticationKeyIssuerID "$ASC_ISSUER_ID")

# Archived signed ad hoc (adhoc_sign, above), so the entitlements are in the
# archive; signed for the store only at export, by Apple's cloud signing with
# the API key, so the runner needs no certificate of its own. Signing the
# archive with a development identity made a new Apple Development
# certificate on every run (each runner starts with an empty keychain), until
# the account had as many as Apple allows: "Your account has reached the
# maximum number of certificates" (run 28). Ad hoc needs no certificate.
set +e
LASTFM_APP_KEY=$lastfm_key xcodebuild archive -project Jukebox.xcodeproj -scheme Jukebox -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/Jukebox.xcarchive \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" CURRENT_PROJECT_VERSION="${BUILD_NUMBER:-1}" CODE_SIGNING_ALLOWED=NO \
  > build/logs/archive.log 2>&1
status=$?
if [[ $status == 0 ]]; then
  adhoc_sign build/Jukebox.xcarchive/Products/Applications/Jukebox.app || status=1
fi
set -e
{ grep -E 'error:|ARCHIVE (SUCCEEDED|FAILED)' build/logs/archive.log || true; } | sed "s#$PWD/##g" | sort -u > build/logs/archive-errors.txt
head -200 build/logs/archive-errors.txt
report build/logs/archive.log "Archive errors"
[[ $status == 0 ]] || exit $status
carplay_signed build/Jukebox.xcarchive/Products/Applications/Jukebox.app archive
widget_signed build/Jukebox.xcarchive/Products/Applications/Jukebox.app archive
lastfm_in build/Jukebox.xcarchive/Products/Applications/Jukebox.app archive

# destination export leaves the ipa on the runner; upload sends it.
export_options() {
  cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$1</string>
  <key>teamID</key><string>$APPLE_TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
PLIST
}
export_options upload > build/ExportOptions.plist
export_options export > build/ExportOptions-ipa.plist

# First the ipa, signed for the store as the upload will be, and read: an
# export to the store sends what it signs and leaves no ipa to look at
# first, so this export is checked, and only then does the second upload.
# A build whose store signature lacks CarPlay is never uploaded.
set +e
xcodebuild -exportArchive -archivePath build/Jukebox.xcarchive \
  -exportOptionsPlist build/ExportOptions-ipa.plist -exportPath build/export-ipa "${auth[@]}" \
  > build/logs/export-ipa.log 2>&1
status=$?
set -e
if [[ $status != 0 ]]; then
  tail -40 build/logs/export-ipa.log
  report build/logs/export-ipa.log "Export errors"
  exit $status
fi
ipa=$(ls build/export-ipa/*.ipa | head -1)
rm -rf build/ipa && mkdir -p build/ipa && unzip -q "$ipa" -d build/ipa
carplay_signed build/ipa/Payload/Jukebox.app ipa
widget_signed build/ipa/Payload/Jukebox.app ipa

set +e
xcodebuild -exportArchive -archivePath build/Jukebox.xcarchive \
  -exportOptionsPlist build/ExportOptions.plist -exportPath build/export "${auth[@]}" \
  > build/logs/export.log 2>&1
status=$?
set -e
tail -40 build/logs/export.log
report build/logs/export.log "Upload errors"
if [[ $status != 0 ]] && grep -q -i "No suitable application records\|app record" build/logs/export.log; then
  echo "::error::App Store Connect has no app with bundle ID com.tijmen.Jukebox yet: Apps › + › New App (README, TestFlight)."
fi

# Until mac_upload, a [testflight] run uploads the iPhone's build only and
# stays green.
mac_status=0
if [[ $mac_upload != true ]]; then
  echo "::notice::The Mac is not uploaded until mac_upload is true."
else
  # The Mac's build of the same app, to the same App Store Connect record.
  # Signed ad hoc when archived, so its sandbox entitlements are inside the
  # archive; the export signs it for the store with the same API key.
  # As the iPhone's: the archive checked, then a pkg signed for the store
  # and read, and only then the upload. The store's signature is the one
  # that shows the portal's App Group (docs/RELEASE.md, The widget); a Mac
  # build without the widget and the group is never uploaded.
  set +e
  LASTFM_APP_KEY=$lastfm_key xcodebuild archive -project Jukebox.xcodeproj -scheme Jukebox -configuration Release \
    -destination 'generic/platform=macOS' -archivePath build/Jukebox-mac.xcarchive \
    DEVELOPMENT_TEAM="$APPLE_TEAM_ID" CURRENT_PROJECT_VERSION="${BUILD_NUMBER:-1}" \
    CODE_SIGNING_ALLOWED=NO \
    > build/logs/archive-mac.log 2>&1
  mac_status=$?
  if [[ $mac_status == 0 ]]; then
    adhoc_sign build/Jukebox-mac.xcarchive/Products/Applications/Jukebox.app || mac_status=1
  fi
  if [[ $mac_status == 0 ]]; then
    widget_signed build/Jukebox-mac.xcarchive/Products/Applications/Jukebox.app "Mac archive" || mac_status=1
    lastfm_in build/Jukebox-mac.xcarchive/Products/Applications/Jukebox.app "Mac archive" || mac_status=1
  fi
  if [[ $mac_status == 0 ]]; then
    xcodebuild -exportArchive -archivePath build/Jukebox-mac.xcarchive \
      -exportOptionsPlist build/ExportOptions-ipa.plist -exportPath build/export-mac-pkg "${auth[@]}" \
      > build/logs/export-mac-pkg.log 2>&1
    mac_status=$?
    if [[ $mac_status != 0 ]]; then
      tail -40 build/logs/export-mac-pkg.log
      report build/logs/export-mac-pkg.log "Mac export errors"
    fi
  fi
  if [[ $mac_status == 0 ]]; then
    pkg=$(ls build/export-mac-pkg/*.pkg | head -1)
    rm -rf build/pkg && pkgutil --expand-full "$pkg" build/pkg
    mac_app=$(find build/pkg -name Jukebox.app -type d -prune | head -1)
    widget_signed "${mac_app:-build/pkg/Jukebox.app}" "Mac pkg" || mac_status=1
  fi
  if [[ $mac_status == 0 ]]; then
    xcodebuild -exportArchive -archivePath build/Jukebox-mac.xcarchive \
      -exportOptionsPlist build/ExportOptions.plist -exportPath build/export-mac "${auth[@]}" \
      > build/logs/export-mac.log 2>&1
    mac_status=$?
  fi
  set -e
  report build/logs/archive-mac.log "Mac archive errors"
  # No export log when the archive failed.
  if [[ -f build/logs/export-mac.log ]]; then
    tail -40 build/logs/export-mac.log
    report build/logs/export-mac.log "Mac upload errors"
  fi
fi
# The iPhone's upload stands on its own; the job is red if either failed.
exit $(( status != 0 ? status : mac_status ))
