#!/usr/bin/env bash
# CI's app job (.github/workflows/ci.yml, on GitHub's macOS): the Xcode
# project from project.yml, then either
#   - the app compiled for the iPhone without signing (every push), then,
#     when it compiled, the pictures of its screens (ci/screenshots.sh), or
#   - with TESTFLIGHT=true: archived, signed by Xcode itself with the App
#     Store Connect API key (role Admin: it makes the certificate and the
#     profile, no Mac of the photographer's needed) and uploaded.
# The compiler's errors go to the run's summary page, so a failed build
# reads without opening the log.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/logs

# The newest released Xcode 26 the runner has.
xcode=$(ls -d /Applications/Xcode_26*.app 2>/dev/null | grep -iv beta | sort -V | tail -1 || true)
if [[ -n $xcode ]]; then sudo xcode-select -s "$xcode"; fi
xcodebuild -version | tee build/logs/xcode-version.txt

command -v xcodegen >/dev/null || brew install xcodegen
xcodegen generate

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
# minutes for the steps around this script, and at most 45.
screenshots() {
  local budget=$(( ${JOB_MINUTES:-75} * 60 - 600 - SECONDS )) pid dog
  if (( budget > 2700 )); then budget=2700; fi
  if (( budget < 600 )); then
    echo "::warning::No screenshots: the build left $budget s of the job."
    return 0
  fi
  SHOTS_BUDGET=$budget perl -e 'setpgrp(0, 0); exec @ARGV or die "exec: $!\n"' bash ci/screenshots.sh \
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

if [[ ${TESTFLIGHT:-false} != true ]]; then
  set +e
  xcodebuild build -project Jukebox.xcodeproj -scheme Jukebox -configuration Debug \
    -destination 'generic/platform=iOS' \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
    > build/logs/build.log 2>&1
  status=$?
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
  # Only of an app that compiled; SCREENSHOTS=false leaves them out.
  if [[ $status == 0 && ${SCREENSHOTS:-true} != false ]]; then
    screenshots
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

set +e
xcodebuild archive -project Jukebox.xcodeproj -scheme Jukebox -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/Jukebox.xcarchive \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" CURRENT_PROJECT_VERSION="${BUILD_NUMBER:-1}" \
  "${auth[@]}" > build/logs/archive.log 2>&1
status=$?
set -e
{ grep -E 'error:|ARCHIVE (SUCCEEDED|FAILED)' build/logs/archive.log || true; } | sed "s#$PWD/##g" | sort -u > build/logs/archive-errors.txt
head -200 build/logs/archive-errors.txt
report build/logs/archive.log "Archive errors"
[[ $status == 0 ]] || exit $status

cat > build/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>$APPLE_TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
PLIST
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
exit $status
