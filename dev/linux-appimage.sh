#!/usr/bin/env bash
# Jukebox as an AppImage: the release binary dev/linux-build.sh makes, with
# every library it needs beside it (GTK 4, libadwaita, GStreamer and the
# plugins the player uses, the icons), in one file that runs without
# installing anything. The second file on a release, for people without
# Flatpak; the Flatpak stays the first. The photographer, 16 November 2026:
# "Ook een AppImage".
#
#   dev/linux-appimage.sh           build  -> build/appimage/Jukebox-<version>-x86_64.AppImage
#
# Put together in Docker from Ubuntu 24.04's own packages, the system the
# binary is built on; it asks for glibc 2.38 and GCC 13's libstdc++, the
# floor (docs/LINUX.md). Tools from their
# projects' GitHub releases, pinned by sha256, kept in .build-linux.
set -euo pipefail
cd "$(dirname "$0")/.."
# One number for every platform: the App Store's.
version=$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"$/\1/p' project.yml)
work=.build-linux/appimage
out=build/appimage/Jukebox-$version-x86_64.AppImage

# appimagetool, and the runtime it puts in front of the image (without
# --runtime-file it would fetch the newest one, unpinned).
tools=$work/tools
mkdir -p "$tools"
fetch() {  # url sha256 file
  [[ -f $tools/$3 ]] || curl -fsSL -o "$tools/$3.part" "$1"
  [[ -f $tools/$3.part ]] && mv "$tools/$3.part" "$tools/$3"
  echo "$2  $tools/$3" | sha256sum -c --quiet || { rm -f "$tools/$3"; echo "$3: wrong sha256" >&2; exit 1; }
  chmod +x "$tools/$3"
}
fetch https://github.com/AppImage/appimagetool/releases/download/1.9.1/appimagetool-x86_64.AppImage \
  ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0 appimagetool
fetch https://github.com/AppImage/type2-runtime/releases/download/20251108/runtime-x86_64 \
  2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d runtime

dev/linux-build.sh release

# The libraries as Ubuntu 24.04 has them, the system the binary is linked
# on: the same versions it was built and tried against.
image=jukebox-appimage
docker image inspect $image >/dev/null 2>&1 || docker build -t $image - <<'DOCKERFILE'
FROM ubuntu:24.04
RUN apt-get update && apt-get install -y --no-install-recommends \
      libgtk-4-1 libadwaita-1-0 libsecret-1-0 libcurl4t64 \
      gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad \
      gstreamer1.0-libav gstreamer1.0-pulseaudio \
      glib-networking librsvg2-common libgdk-pixbuf2.0-bin libglib2.0-bin \
      gsettings-desktop-schemas adwaita-icon-theme \
      patchelf binutils file desktop-file-utils \
    && rm -rf /var/lib/apt/lists/*
DOCKERFILE

rm -rf "$work/AppDir"
mkdir -p "$work/AppDir" build/appimage
docker run --rm -u "$(id -u):$(id -g)" -e HOME=/tmp -e VERSION="$version" \
  -v "$PWD:/src:ro" -v "$PWD/$work:/work" -v "$PWD/build/appimage:/out" -w /work $image bash -euo pipefail -c '
sys=/usr/lib/x86_64-linux-gnu
A=/work/AppDir L=/work/AppDir/usr/lib
mkdir -p $A/usr/bin $L/gstreamer-1.0 $L/gio/modules $A/usr/libexec $A/usr/share/glib-2.0/schemas $A/usr/share/icons
install -m755 /src/.build-linux/release/Jukebox $A/usr/bin/jukebox

# What the player asks of GStreamer (Linux/App/AudioPlayer.swift): playbin3
# over http(s) and files; MP3, FLAC, AAC and ALAC in M4A, WAV and AIFF as
# the servers send them as they are (JellyfinRequests.directContainers),
# HLS with AAC in MPEG-TS when Jellyfin transcodes; out through PulseAudio,
# which PipeWire serves too. ALAC has no decoder but libav.
for p in coreelements playback typefindfunctions audioconvert audioresample volume ogg opus vorbis \
         soup isomp4 audioparsers flac mpg123 id3demux apetag icydemux wavparse pulseaudio autodetect \
         adaptivedemux2 hls mpegtsdemux aiff libav; do
  cp $sys/gstreamer-1.0/libgst$p.so $L/gstreamer-1.0/
done
cp $sys/gstreamer1.0/gstreamer-1.0/gst-plugin-scanner $A/usr/libexec/
# HTTPS for GLib (souphttpsrc), and libsoup itself, which GStreamer opens
# by name, unseen by ldd.
cp $sys/gio/modules/libgiognutls.so $L/gio/modules/
cp -L $sys/libsoup-3.0.so.0 $L/
# Pictures: SVG icons go through librsvg; the cache names its loaders by
# whole path, so AppRun writes it again for where the image is mounted.
cp -r $sys/gdk-pixbuf-2.0 $L/
GDK_PIXBUF_MODULEDIR=$L/gdk-pixbuf-2.0/2.10.0/loaders $sys/gdk-pixbuf-2.0/gdk-pixbuf-query-loaders \
  | sed "s|$A|@APPDIR@|g" > $L/gdk-pixbuf-2.0/2.10.0/loaders.cache.in
rm -f $L/gdk-pixbuf-2.0/2.10.0/loaders.cache
# GTK'"'"'s and the desktop'"'"'s settings, and the icons libadwaita draws with.
cp /usr/share/glib-2.0/schemas/*.xml $A/usr/share/glib-2.0/schemas/
glib-compile-schemas $A/usr/share/glib-2.0/schemas
cp -r /usr/share/icons/Adwaita /usr/share/icons/hicolor $A/usr/share/icons/
# What a file is, by its first bytes: without it no SVG is recognised.
mkdir -p $A/usr/share/mime
find /usr/share/mime -maxdepth 1 -type f -exec cp {} $A/usr/share/mime/ \;
find $A/usr/share/icons/hicolor -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} +
install -Dm644 /src/Linux/data/com.tijmen.Jukebox.svg $A/usr/share/icons/hicolor/scalable/apps/com.tijmen.Jukebox.svg
install -Dm644 /src/Linux/data/com.tijmen.Jukebox.desktop $A/usr/share/applications/com.tijmen.Jukebox.desktop
cp /src/Linux/data/com.tijmen.Jukebox.desktop /src/Linux/data/com.tijmen.Jukebox.svg $A/
ln -s com.tijmen.Jukebox.svg $A/.DirIcon

# Every library those need, but the ones the computer must bring itself:
# glibc, and the graphics drivers'"'"' (they belong to the machine'"'"'s GPU).
# libstdc++ and libgcc_s too: a newer one is on every system above the
# floor, and the drivers load theirs.
skip="^(ld-linux|libc|libm|libdl|libpthread|librt|libresolv|libutil|libanl|libmvec|libnss_|libBrokenLocale|libthread_db|libGL|libGLX|libEGL|libOpenGL|libGLdispatch|libgbm|libstdc\+\+|libgcc_s)\."
elves() { find $A -type f \( -name "*.so*" -o -perm -u+x \) -exec sh -c "file -b \"\$1\" | grep -q ^ELF && echo \"\$1\"" _ {} \;; }
for f in $(elves); do ldd $f 2>/dev/null; done | awk "/=> \// {print \$3}" | sort -u | while read -r lib; do
  name=${lib##*/}
  [[ $name =~ $skip || -e $L/$name ]] || cp -L $lib $L/$name
done
# The ones the graphics drivers share with GTK: the computer'"'"'s own where
# it has them, as its drivers were built against its versions (with ours,
# Mesa'"'"'s Vulkan and EGL fail on a symbol and GTK draws without the GPU).
# AppRun lends these only to a computer without them.
shared="^(libdrm[_a-z]*|libelf|libexpat|libffi|libwayland-[a-z]+|libX11(-xcb)?|libXau|libXdmcp|libXext|libXfixes|libXxf86vm|libxshmfence|libxcb(-[a-z0-9]+)?|libz|libzstd|libudev)\.so"
mkdir -p $L/fallback
for f in $L/*.so*; do if [[ ${f##*/} =~ $shared ]]; then mv $f $L/fallback/; fi; done
# Each finds its own beside it, not the host'"'"'s (LD_LIBRARY_PATH would
# hand them to the drivers and to every program Jukebox opens too).
for f in $(elves); do
  patchelf --set-rpath "\$ORIGIN/$(realpath --relative-to=${f%/*} $L)" $f
done
missing=$(for f in $(elves); do ldd $f 2>/dev/null | grep "not found" || true; done | sort -u)
[[ -z $missing ]] || { echo "not found: $missing" >&2; exit 1; }
cp /src/Linux/data/AppRun $A/AppRun

# The oldest glibc and libstdc++ it runs on: the newest any part asks for.
floor() { elves | xargs objdump -T 2>/dev/null | grep -o "$1_[0-9.]*" | sort -uV | tail -1; }
echo "floor: $(floor GLIBC) $(floor GLIBCXX)"

ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 /work/tools/appimagetool --no-appstream \
  --runtime-file /work/tools/runtime $A /out/Jukebox-$VERSION-x86_64.AppImage >/work/appimagetool.log 2>&1 \
  || { cat /work/appimagetool.log; exit 1; }
'
ls -lh "$out" | awk '{print $5}'
echo "$out"
