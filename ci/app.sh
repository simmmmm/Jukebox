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
mkdir -p build/logs

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
  *walk) TESTFLIGHT=false ;;
  *) TESTFLIGHT=false; SCREENSHOTS=${SCREENSHOTS:-false} ;;
esac

# The newest released Xcode the runner has, 26 or later: from April 2027
# the store takes only builds made with the iOS 27 SDK (ITMS-90725, on
# build 306 of 19 November 2026).
ls -d /Applications/Xcode*.app 2>/dev/null || true
xcode=$(ls -d /Applications/Xcode_2[6-9]*.app 2>/dev/null | grep -iv beta | sort -V | tail -1 || true)
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

# The iPhone's app signed ad hoc, as the Mac's archive is: no certificate,
# no profile, but the signature carries the entitlements of
# Jukebox/Jukebox-iOS.entitlements, CarPlay audio. The export reads the
# entitlements from the archived app's signature and asks the store's profile
# for them; an app built with CODE_SIGNING_ALLOWED=NO has no signature, and
# its upload went without CarPlay. iOS allows ad hoc signing only when asked
# (AD_HOC_CODE_SIGNING_ALLOWED; the Mac's default).
ios_adhoc=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" AD_HOC_CODE_SIGNING_ALLOWED=YES
           PROVISIONING_PROFILE_SPECIFIER="")

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
  xcodebuild build -project Jukebox.xcodeproj -scheme Jukebox -configuration Debug \
    -destination 'generic/platform=iOS' -derivedDataPath build/derived "${ios_adhoc[@]}" \
    > build/logs/build.log 2>&1
  status=$?
  if [[ $status == 0 ]]; then
    carplay_signed build/derived/Build/Products/Debug-iphoneos/Jukebox.app build
    status=$?
    widget_signed build/derived/Build/Products/Debug-iphoneos/Jukebox.app build || status=1
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
  xcodebuild build -project Jukebox.xcodeproj -scheme Jukebox -configuration Debug \
    -destination 'generic/platform=macOS' -derivedDataPath build/derived-mac \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= \
    > build/logs/build-mac.log 2>&1
  mac_status=$?
  if [[ $mac_status == 0 ]]; then
    widget_signed build/derived-mac/Build/Products/Debug/Jukebox.app "Mac build" || mac_status=1
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

# Archived signed ad hoc (ios_adhoc, above), so the entitlements are in the
# archive; signed for the store only at export, by Apple's cloud signing with
# the API key, so the runner needs no certificate of its own. Signing the
# archive with a development identity made a new Apple Development
# certificate on every run (each runner starts with an empty keychain), until
# the account had as many as Apple allows: "Your account has reached the
# maximum number of certificates" (run 28). Ad hoc needs no certificate.
set +e
xcodebuild archive -project Jukebox.xcodeproj -scheme Jukebox -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/Jukebox.xcarchive \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" CURRENT_PROJECT_VERSION="${BUILD_NUMBER:-1}" "${ios_adhoc[@]}" \
  > build/logs/archive.log 2>&1
status=$?
set -e
{ grep -E 'error:|ARCHIVE (SUCCEEDED|FAILED)' build/logs/archive.log || true; } | sed "s#$PWD/##g" | sort -u > build/logs/archive-errors.txt
head -200 build/logs/archive-errors.txt
report build/logs/archive.log "Archive errors"
[[ $status == 0 ]] || exit $status
carplay_signed build/Jukebox.xcarchive/Products/Applications/Jukebox.app archive
widget_signed build/Jukebox.xcarchive/Products/Applications/Jukebox.app archive

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
  xcodebuild archive -project Jukebox.xcodeproj -scheme Jukebox -configuration Release \
    -destination 'generic/platform=macOS' -archivePath build/Jukebox-mac.xcarchive \
    DEVELOPMENT_TEAM="$APPLE_TEAM_ID" CURRENT_PROJECT_VERSION="${BUILD_NUMBER:-1}" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" \
    > build/logs/archive-mac.log 2>&1
  mac_status=$?
  if [[ $mac_status == 0 ]]; then
    widget_signed build/Jukebox-mac.xcarchive/Products/Applications/Jukebox.app "Mac archive" || mac_status=1
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
