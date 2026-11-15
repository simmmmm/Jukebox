#!/usr/bin/env bash
# Jukebox as a Flatpak: the release binary dev/linux-build.sh makes, in
# GNOME's runtime (Linux/data/com.tijmen.Jukebox.yml), so it also runs on a
# distribution older than the build's floor. The photographer, 15 November
# 2026: "zet dan ook maar flatpak in de releases".
#
#   dev/linux-flatpak.sh            build  -> build/flatpak/Jukebox-<version>-x86_64.flatpak
#   dev/linux-flatpak.sh install    and install it for this user
#   dev/linux-flatpak.sh release    and attach it to GitHub's release v<version>
#
# Needs Flathub's org.flatpak.Builder, org.gnome.Sdk//50 and
# org.gnome.Platform//50; `release` needs gh, signed in.
set -euo pipefail
cd "$(dirname "$0")/.."
id=com.tijmen.Jukebox
step=${1:-build}
[[ $step == build || $step == install || $step == release ]] || { echo "usage: $0 [install|release]" >&2; exit 2; }
# One number for every platform: the App Store's.
version=$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"$/\1/p' project.yml)
work=.build-linux/flatpak
bundle=build/flatpak/Jukebox-$version-x86_64.flatpak

if [[ $step == release ]]; then
  # The release's tag names a commit, and the file is built from the tree:
  # the two are the same only when nothing is uncommitted or unpushed.
  [[ -z $(git status --porcelain --untracked-files=no) ]] || { echo "Uncommitted changes: commit first." >&2; exit 1; }
  git fetch -q origin
  [[ -n $(git branch -r --contains HEAD) ]] || { echo "HEAD is not on GitHub: push first." >&2; exit 1; }
  # A version is released once: a second file under its name would replace
  # the one people already have.
  if gh release view "v$version" --json assets -q '.assets[].name' 2>/dev/null | grep -qxF "${bundle##*/}"; then
    echo "Jukebox $version already has its Flatpak: raise MARKETING_VERSION in project.yml first." >&2
    exit 1
  fi
fi

dev/linux-build.sh release
mkdir -p build/flatpak
flatpak run org.flatpak.Builder --force-clean --disable-rofiles-fuse \
  --state-dir=$work/state --repo=$work/repo $work/build Linux/data/$id.yml
# The bundle says where its runtime is, so installing it fetches GNOME's too.
flatpak build-bundle --runtime-repo=https://flathub.org/repo/flathub.flatpakrepo \
  $work/repo "$bundle" $id master
echo "$bundle"

if [[ $step == install ]]; then
  flatpak install --user --noninteractive --reinstall "$bundle"
elif [[ $step == release ]]; then
  # A new release is a draft: the photographer publishes it, and so
  # chooses the day, as with the App Store's (docs/RELEASE.md).
  gh release view "v$version" >/dev/null 2>&1 || gh release create "v$version" --draft \
    --target "$(git rev-parse HEAD)" --title "Jukebox $version" \
    --notes "Linux: \`flatpak install --user ${bundle##*/}\`"
  gh release upload "v$version" "$bundle"
fi
