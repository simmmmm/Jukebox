# Jukebox for Linux

Jukebox on the desktop: at home on GNOME, at ease everywhere else. The
photographer, 13 and 14 November 2026:

> "Maak hier ook een linux versie van, misschien toch een gedeelde codebase?"

> "ik wil net als met numa dat het vooral super nice werkt op gnome"

> "werkt het dan ook nice in bijv hyprland xfce kde" — "wel zo dat mensen
> nooit 'ge-gnomed' kunnen worden neem ik aan?"

So: one codebase where it is not the screen, GNOME's own way where it is,
and nothing of GNOME's desktop needed to run it.

## One codebase

Swift on both. Swift runs on Linux as on the iPhone (the kit has been tested
there from the first day). Linux lacks Apple's screens and sound, so those
two are written per platform, each its own way.

| | iPhone and iPad | Linux |
|---|---|---|
| Servers, library, radio, mixes, lyrics, play state | `JukeboxKit/`, the same package | the same |
| The app's stores: `LibraryStore`, `RadioController`, `MixStore`, `HistoryStore`, `HandoffStore`, `OfflineStore`, `AppSettings`, `Stats`, `HomeShelves`, `LyricsFinder`, the queue's types; the wide window's `PanelState`, `DesktopMeasures` and `UpNextList` | `Jukebox/` | the same files, named in `Package.swift`'s `shared` |
| Screens | SwiftUI (`Jukebox/`) | GTK 4 and libadwaita (`Linux/App/`) |
| Sound | AVFoundation (`Jukebox/Player/AudioPlayer.swift`) | GStreamer (`Linux/App/AudioPlayer.swift`), the same queue and rules |
| The session's secret | the Keychain | the desktop's keyring, or a file only the user reads |
| Songs kept | Application Support, a background URLSession (`docs/OFFLINE.md`) | `$XDG_DATA_HOME/jukebox/offline`, a URLSession while Jukebox runs |
| System controls | lock screen, remote commands | MPRIS (`Linux/CGlue/mpris.c`) |

The kit and the app's stores compile for both. Linux's own code is Swift,
with a little C as glue only, for what Swift cannot call as it is (C
functions with "…", macros, D-Bus by hand).

A shared file stays shared by importing only Foundation, Observation and
JukeboxKit. Linux compiles them as project.yml does for the iPhone (Swift 5
mode, the main actor by default), so a change to one is checked here before
CI's Mac sees it.

## Building and running

    dev/linux-build.sh            # in Docker: no Swift needed on the machine
    .build-linux/debug/Jukebox
    dev/linux-install.sh          # release build into ~/.local, with icon and desktop entry
    dev/linux-flatpak.sh          # the release build as a Flatpak -> build/flatpak/
    dev/linux-appimage.sh         # and as an AppImage -> build/appimage/

The image (`dev/linux/Dockerfile`) is Swift 6.2 on Ubuntu 24.04 with GTK
4.14, libadwaita 1.5 and GStreamer; those versions are the floor. Swift's
own libraries are linked into the binary. A machine that runs it needs GTK
4, libadwaita, GStreamer (with its good and bad plugins, for MP3, FLAC, AAC
and HLS) and libsecret: libraries, nothing of a desktop.

The Flatpak (`Linux/data/com.tijmen.Jukebox.yml`) is that same binary in
GNOME's runtime, for a distribution below the floor: "zet dan ook maar
flatpak in de releases" (the photographer, 15 November 2026). It is not
built again there: Flathub's Swift is 6.3, and one toolchain means a release
is what was run here. `dev/linux-flatpak.sh install` installs it,
`release` attaches it to GitHub's release (`docs/RELEASE.md`).

The AppImage is the second file on a release, for people without Flatpak
("Ook een AppImage", 16 November 2026). `dev/linux-appimage.sh` puts the
same binary together in Docker with Ubuntu 24.04's own libraries: GTK,
libadwaita, GStreamer with the plugins the player uses (MP3, FLAC, AAC,
ALAC through libav, HLS, PulseAudio, which PipeWire serves too), libsoup
and GLib's TLS, the Adwaita icons, the settings schemas, the MIME
database. `Linux/data/AppRun` points each at its own copy, and every
library finds the others beside it (an rpath, not LD_LIBRARY_PATH). The
few the graphics drivers share (X11, Wayland, libdrm, zlib) are the
computer's own where it has them, so Mesa finds the versions it was built
with; the file lends its copies only to a system without them.
appimagetool 1.9.1 and the type2 runtime 20251108 come from their GitHub
releases, checked by sha256. It is 126 MB, most of it the binary, ICU's
data and libav.

The computer brings glibc 2.38 and GCC 13's libstdc++ or newer (Ubuntu
24.04, Debian 13, Fedora 39 and up, Arch), and what every desktop has:
fonts, the graphics drivers, and a sound server (PulseAudio, or PipeWire's
Pulse; without one Jukebox plays in silence).

What in the AppImage is not MIT ("Met GPL-vermelding", 16 November 2026).
Jukebox's own code is MIT (`LICENSE`). Beside it, the file carries:

- GPL-2.0-or-later: FFmpeg's libraries (libav), Ubuntu's build with x264,
  x265 and libpostproc; the shared-mime-info database.
- LGPL: GTK, GLib, GStreamer and its plugins, libsoup, libadwaita.
- LGPL-3.0 or CC-BY-SA-3.0: the Adwaita icons.
- Apache-2.0 with the Runtime Library Exception: Swift's runtime and
  Foundation, in the binary; with them ICU, under the Unicode licence.
- The other libraries under their own licences, as Ubuntu ships them.

They are Ubuntu 24.04's (noble) packages, unchanged. Each one's name and
version, and its source package, are in the file at
`usr/share/doc/jukebox/PACKAGES` (`--appimage-extract` shows it). The
corresponding source comes from Ubuntu: `apt-get source <source>=<version>`
on noble, or launchpad.net/ubuntu/+source/<source>. Swift's is at
github.com/swiftlang.

Tried, 16 November 2026: on this machine under Xvfb and under mutter,
headless, on Wayland (drawn with OpenGL), and in a bare Fedora
44 container (no GTK, no GStreamer, no X11; this machine's fonts lent to
it), it signs in to the fake Jellyfin, walks every screen and plays song
after song; in the container through a PulseAudio server beside it.
HTTPS verifies on Fedora and Arch with their own certificates (curl and
GStreamer on the file's libraries). Not yet tried: HLS from a real
Jellyfin, a real desktop session with sound.

`JUKEBOX_AUDIO_SINK=fakesink` plays to nowhere, in time, for trying things
without sound.

## How it is made

- **GTK from Swift, directly** (`Linux/App/Gtk.swift`). GTK is C, and Swift
  calls C. A page of helpers makes it read like the rest of the app:
  `on(button, "clicked") { … }`, and `observe(widget) { … }`, which runs
  again whenever something @Observable it read changes, as SwiftUI does for
  a view's body. No binding library in between: C's GTK is the one that is
  looked after.
- **The main actor on GLib's loop** (`main.swift`). Swift's main actor is
  libdispatch's main queue; GTK has the main thread. The queue signals
  through a file descriptor when it has work, and GLib's loop watches it.
  Every `await` comes back between two GTK events.
- **Lists that make only what shows** (`ItemList`): GtkListView and
  GtkGridView, so Songs is as quick with 20 000 songs as with 20.
- **Gapless** (`AudioPlayer`). GStreamer asks for the next address a moment
  before a song ends; the queue follows when the new stream starts, as it
  follows AVQueuePlayer on the iPhone.

## At home on GNOME

GNOME's Human Interface Guidelines, with libadwaita's own widgets:

- a sidebar of places that folds away in a narrow window;
- each page with its header bar and Back, and the search field at the
  header's end, the same on every page: a click in it (or Ctrl+F) shows
  the Search page, which is not in the sidebar;
- the primary menu (F10) with Preferences, Keyboard Shortcuts and About;
- GNOME's own context menus;
- toasts for a moment's news, a dialog before signing out;
- header capitals on buttons and rows;
- a playlist of the listener's own edited in place, as on the Mac (since
  16 November 2026): a song's menu has Move Up, Move Down and, last,
  Remove from Playlist; a song dragged onto another takes its place; the
  same calls as the Mac's (`LibraryStore.remove`, `move`). Moving only
  where the server can reorder, none of it on someone else's playlist.

Keys: Space plays and pauses wherever the focus is, except in a field
typed in (Ctrl+Space everywhere), Ctrl+Right and Ctrl+Left skip, Ctrl+F
goes to the search field, Ctrl+, opens Preferences, Ctrl+? shows them all.
In a list of songs Shift+F10 or the Menu key opens the song's menu, and
in a playlist of one's own Delete removes the song.

GNOME's media controls (the clock's menu, the lock screen, the keyboard's
keys) see Jukebox through MPRIS, with the cover. The Play key with nothing
loaded goes on where this computer, or another device, left off.

Jukebox's soul is in the content, as on the iPhone (`docs/BRAND.md`,
`docs/design/tells.md`): Copper by day and Glow by night as the accent,
Paper and Night as the grounds, titles in a serif, the arch for a station
and light for the one on air. Every measure is on the 4-point grid
(`dev/grid-check.sh` walks both platforms).

## At ease everywhere else

Hyprland, KDE, XFCE and the rest run it as it is: a GTK app with its own
header bar. Their media widgets and `playerctl` read the same MPRIS.

The session's token goes in the keyring where there is one (GNOME Keyring,
KWallet). Where there is none, it goes in
`~/.local/share/Jukebox/credentials.json`, readable by its user alone.
Measured on a session bus without a keyring: the app starts at once and
stays signed in.

It looks like a GNOME app on every desktop: libadwaita does not take another
desktop's theme.

## The 2027 layout (14 November 2026)

The photographer: "nu kunnen we gewoon een 2027 design maken met invloeden van Spotify en feishin, persoonlijk vind ik het heel Nice wat [Feishin] heeft gedaan dat in je een paneel lyrics en de playlist kan bekijken. Als optionele toevoegingen. Wat wij echter niet moeten doen is het een hele drukke app maken".

The design and its spec are in `build/design-round/2027/` (`spec.md`, `sheet.png`).

- **The bar** is 88 tall and spans the whole window. Its centre (previous, play, next, progress) takes 40% of the window, held between 304 and 640, and sits on the window's centre. The song and tools zones are equal (`ThreeZones` in PlayerBar.swift).
- **The panel**, Now playing, at the right is 360 wide. It shows the queue (shuffle, repeat, the radio's reasons) or Lyrics (synced; click a line to seek). The bar's toggles open, switch and close it, and the app remembers it. It sits beside the page from 1280 wide and lies over it below.
- **The places** at the left are 240 wide, the Mac's 1:1: Home, Radio; Albums, Artists, Songs, Playlists, Favorites, Genres, Recently Added, Downloaded; the playlists ("Linux erbij", 15 November 2026). Below 900 they fold and lie over the page; F9 brings them back.
- **Preferences › Pages** takes places out (`AppSettings.hiddenPages`, shared). The place shown switched off goes Home. Every one off, there is no sidebar: Home, the panel and the bar, with the main menu at the end of the page's header.
- **Full Player** (the cover and the title in the bar open it) covers the places and the page. The bar and the panel stay. In the bar, the artist opens the artist and a station's name the panel.
- **Shelves** have no scrollbar over their words. Under the pointer a round
  ‹ and › fade in, 32 wide, while there is more that way; a click moves on
  by what shows, less one tile. The keys go along the tiles.
- **A tile's hover** lights the tile at its own size, 8 past its art on every
  side, corners 14, concentric with the art's 6. A grid's cell shows nothing
  ("hover op linux gaat nog fout, op mac niet", 14 November 2026).

The iPad at regular width and the Mac draw the same window, 1:1
(`Jukebox/App/WideShell.swift`, `docs/ARCHITECTURE.md`).

## What comes next

The iPhone has each of these, and Linux is ready for them:

- Quick Connect at sign-in (the kit has it: `QuickConnectSignIn`).
- The drawings in motion: the label turning, the land under Now Playing
  (once the photographer decides whether it turns), the mark warming up,
  the mark before a station's name in Now Playing and the player's bar.
- The Flatpak's page in GNOME Software (a metainfo file): it names a
  licence, and that is MIT, chosen on 16 November 2026 (`LICENSE`).
  Flathub wants a build from source too.
- CI. The workflow file calls `ci/*.sh`, and the session's token may not
  push workflow files, so Linux is built here, not yet on GitHub.

## Tried so far

On this machine under GTK's Broadway (GTK in a browser tab), against the
test Jellyfin: signing in from the keyring and from the file, Home, Radio,
Albums, an album, Now Playing, the radio playing on from song to song,
MPRIS's Play, Next and metadata, the handoff both ways. Since 15 November
2026 the walk (`dev/linux-screens.sh`) also downloads an album, a playlist
and a mix from the fake Jellyfin by their pages' buttons and plays one from
its file; it starts a station from Radio's +, saves one as a playlist, makes
a playlist, fills it with Add Songs and deletes it, and starts a song's
station from Search. `frames.txt` says what came.

Editing a playlist, 16 November 2026, under Xvfb against the test
Jellyfin, by mouse and keys: Move Down and Move Up from the menu (Up by
Shift+F10 and Enter), a song dragged up and one dragged down, Delete, and
Remove from Playlist; after each, the server's order was the page's. Not
yet tried: a Subsonic server, a playlist someone else shared.

The Flatpak, 16 November 2026: in its sandbox under Broadway it signs in to
the fake Jellyfin from the file, loads the library and its covers. Not yet
tried in it: sound, the keyring, the media controls.

Not yet tried: a real Wayland session with sound, Navidrome in the app (its
calls are tested in the kit), KDE, XFCE and Hyprland themselves; offline on
Linux (the server away, only the files playing, the plays held for it: the
iPhone's rules, ported, never run here), and F10 with Preferences › Pages
all off.
