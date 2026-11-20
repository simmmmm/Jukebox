# Sourced by ci/app.sh and ci/screenshots.sh, from the repository's root.
#
# The apps signed ad hoc: no certificate, no profile, but the signature
# carries the entitlements of the entitlements files, CarPlay audio, Siri,
# the App Group, the Mac's sandbox. The export reads the entitlements from
# the archived app's signature and asks the store's profile for them; an app
# built with CODE_SIGNING_ALLOWED=NO and left so has no signature, and its
# upload went without CarPlay. So the builds and the archives compile
# unsigned (CODE_SIGNING_ALLOWED=NO) and are signed ad hoc here, with the
# same entitlements files. Xcode's own ad hoc signing, as before, works on
# GitHub's macOS 26 only: on the photographer's MacBook (macOS 27) Xcode
# stops a build or an archive whose entitlements need a profile, App
# Groups, CarPlay, Siri, before it compiles, "requires a provisioning
# profile", on Xcode 26.3 and 27.2 alike. Signed by codesign the app carries its
# entitlements as Xcode's own ad hoc signature did, so carplay_signed and
# widget_signed read the same thing on both runners. Inside out, without
# --deep, so the widget keeps its own entitlements.
adhoc_sign() {
  local app=$1 code plugins=$1/PlugIns app_entitlements=Jukebox/Jukebox-iOS.entitlements
  local widget_entitlements=JukeboxWidget/JukeboxWidget.entitlements
  if [[ -d $app/Contents ]]; then
    plugins=$app/Contents/PlugIns
    app_entitlements=Jukebox/Jukebox-macOS.entitlements
    widget_entitlements=JukeboxWidget/JukeboxWidget-macOS.entitlements
  fi
  while IFS= read -r code; do
    codesign --force --sign - --timestamp=none "$code" || return 1
  done < <(find "$app" -name '*.framework' -prune -print -o -name '*.dylib' -print)
  if [[ -d $plugins/JukeboxWidget.appex ]]; then
    codesign --force --sign - --timestamp=none --entitlements "$widget_entitlements" \
      "$plugins/JukeboxWidget.appex" || return 1
  fi
  codesign --force --sign - --timestamp=none --entitlements "$app_entitlements" "$app"
}

# The Mac's UI tests, signed ad hoc as Xcode's "Sign to Run Locally" signs
# them: the runner app and the walk's .xctest inside it, nested code first,
# no entitlements. macOS starts a UI test's runner only when it is signed.
adhoc_sign_tests() {
  local runner=$1 code
  while IFS= read -r code; do
    codesign --force --sign - --timestamp=none "$code" || return 1
  done < <(find "$runner" -name '*.framework' -prune -print -o -name '*.dylib' -print)
  for code in "$runner"/Contents/PlugIns/*.xctest; do
    [[ -d $code ]] || continue
    codesign --force --sign - --timestamp=none "$code" || return 1
  done
  codesign --force --sign - --timestamp=none "$runner"
}
