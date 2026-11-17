#!/usr/bin/env bash
# Google's Cast SDK for iOS into Vendor/GoogleCast (gitignored), which
# project.yml links for the iPhone and the iPad (Player/GoogleCast.swift).
# Google's own build from Google's own server, the version pinned and its
# sha256 checked; never a mirror. The dynamic xcframework: GTMSessionFetcher
# and the rest it needs are inside it, where the static one asks for them as
# CocoaPods dependencies. Run before `xcodegen generate` (ci/app.sh does;
# docs/RELEASE.md for the photographer's Mac).
#
# The SDK is not MIT: Google APIs Terms of Service and the Google Cast SDK
# Additional Developer Terms (README, Licence).
set -euo pipefail
cd "$(dirname "$0")/.."
version=4.8.6
sha256=55f6c21291a1315c68063f07e7d76225564bff70f2fd38caad135c71d66eb310
target=Vendor/GoogleCast
if [[ -f $target/VERSION && $(cat "$target/VERSION") == "$version" ]]; then exit 0; fi
zip=$(mktemp -d)/cast.zip
curl -fsSL "https://dl.google.com/dl/chromecast/sdk/ios/GoogleCastSDK-ios-${version}_dynamic.zip" -o "$zip"
got=$( (command -v sha256sum >/dev/null && sha256sum "$zip" || shasum -a 256 "$zip") | cut -d' ' -f1)
if [[ $got != "$sha256" ]]; then
  echo "::error::Google Cast SDK $version: sha256 $got, expected $sha256"
  exit 1
fi
rm -rf "$target"
mkdir -p "$target"
unzip -q "$zip" -d "$target/unpacked"
mv "$target/unpacked/GoogleCastSDK-ios-${version}_dynamic_xcframework/GoogleCast.xcframework" "$target/"
rm -rf "$target/unpacked" "$(dirname "$zip")"
echo "$version" > "$target/VERSION"
echo "Google Cast SDK $version in $target"
