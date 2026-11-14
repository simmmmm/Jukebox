#!/usr/bin/env bash
# Jukebox into this user's own ~/.local, so GNOME knows it: the binary, the
# desktop entry and the icon (the dock, the overview and the media controls
# name an app by its desktop entry). A release build first.
#
#   dev/linux-install.sh            build and install
#   dev/linux-install.sh --remove   take it away again
set -euo pipefail
cd "$(dirname "$0")/.."
bin=${XDG_BIN_HOME:-$HOME/.local/bin}
data=${XDG_DATA_HOME:-$HOME/.local/share}
id=com.tijmen.Jukebox
if [[ ${1:-} == --remove ]]; then
  rm -f "$bin/jukebox" "$data/applications/$id.desktop" "$data/icons/hicolor/scalable/apps/$id.svg"
  echo "removed"
  exit 0
fi
dev/linux-build.sh release
install -Dm755 .build-linux/release/Jukebox "$bin/jukebox"
install -Dm644 Linux/data/$id.svg "$data/icons/hicolor/scalable/apps/$id.svg"
# The entry starts the binary by its whole path: ~/.local/bin is not on
# every session's PATH.
install -Dm644 /dev/stdin "$data/applications/$id.desktop" < <(sed "s|^Exec=jukebox|Exec=$bin/jukebox|" Linux/data/$id.desktop)
update-desktop-database "$data/applications" 2>/dev/null || true
gtk4-update-icon-cache -q "$data/icons/hicolor" 2>/dev/null || true
echo "installed: Jukebox is in the overview"
