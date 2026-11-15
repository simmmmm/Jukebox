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
| The app's stores: `LibraryStore`, `RadioController`, `MixStore`, `HistoryStore`, `HandoffStore`, `OfflineStore`, `AppSettings`, `Stats`, `HomeShelves`, `LyricsFinder`, the queue's types | `Jukebox/` | the same files, named in `Package.swift`'s `shared` |
| Screens | SwiftUI (`Jukebox/`) | GTK 4 and libadwaita (`Linux/App/`) |
| Sound | AVFoundation (`Jukebox/Player/AudioPlayer.swift`) | GStreamer (`Linux/App/AudioPlayer.swift`), the same queue and rules |
| The session's secret | the Keychain | the desktop's keyring, or a file only the user reads |
| Songs kept | Application Support, a background URLSession (`docs/OFFLINE.md`) | `$XDG_DATA_HOME/jukebox/offline`, a URLSession while Jukebox runs |
| System controls | lock screen, remote commands | MPRIS (`Linux/CGlue/mpris.c`) |

Measured on 15 November 2026: 13 607 lines of kit and 5 750 of the app's
stores compile for both. Linux's own code is 7 424 lines of Swift and 594 of
C. The C is glue only, for what Swift cannot call as it is (C functions with
"…", macros, D-Bus by hand).

A shared file stays shared by importing only Foundation, Observation and
JukeboxKit. Linux compiles them as project.yml does for the iPhone (Swift 5
mode, the main actor by default), so a change to one is checked here before
CI's Mac sees it.

## Building and running

    dev/linux-build.sh            # in Docker: no Swift needed on the machine
    .build-linux/debug/Jukebox
    dev/linux-install.sh          # release build into ~/.local, with icon and desktop entry

The image (`dev/linux/Dockerfile`) is Swift 6.2 on Ubuntu 24.04 with GTK
4.14, libadwaita 1.5 and GStreamer; those versions are the floor. Swift's
own libraries are linked into the binary. A machine that runs it needs GTK
4, libadwaita, GStreamer (with its good and bad plugins, for MP3, FLAC, AAC
and HLS) and libsecret: libraries, nothing of a desktop.

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
- header capitals on buttons and rows.

Keys: Ctrl+Space plays and pauses, Ctrl+Right and Ctrl+Left skip, Ctrl+F
goes to the search field, Ctrl+, opens Preferences, Ctrl+? shows them all.

GNOME's media controls (the clock's menu, the lock screen, the keyboard's
keys) see Jukebox through MPRIS, with the cover. The Play key with nothing
loaded goes on where this computer, or another device, left off.

Jukebox's soul is in the content, as on the iPhone (`docs/BRAND.md`,
`docs/design/tells.md`): Copper by day and Glow by night as the accent,
Paper and Night as the grounds, titles in a serif, the arch for a station
and light for the one on air. Every measure is on the 4-point grid
(`dev/grid-check.py` walks both platforms).

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
- **The panel** at the right is 360 wide. It shows Up next (shuffle, repeat, the radio's reasons) or Lyrics (synced; click a line to seek). The bar's toggles open, switch and close it, and the app remembers it. It sits beside the page from 1280 wide and lies over it below.
- **The places** at the left are 240 wide, the Mac's 1:1: Home, Radio; Albums, Artists, Songs, Playlists, Favorites, Genres, Recently Added, Downloaded; the playlists ("Linux erbij", 15 November 2026). Below 900 they fold and lie over the page; F9 brings them back.
- **Preferences › Pages** takes places out (`AppSettings.hiddenPages`, shared). The place shown switched off goes Home. Every one off, there is no sidebar: Home, the panel and the bar, with the main menu at the end of the page's header.
- **Now Playing** covers the places and the page. The bar and the panel stay.

## What comes next

The iPhone has each of these, and Linux is ready for them:

- Quick Connect at sign-in (the kit has it: `QuickConnectSignIn`).
- Making and editing playlists (they are listed and played).
- The drawings in motion: the label turning, the land under Now Playing
  (once the photographer decides whether it turns), the mark warming up,
  the mark before a station's name in Now Playing and the player's bar.
- A Flatpak. Until then `dev/linux-install.sh` installs for one user.
- CI. The workflow file calls `ci/*.sh`, and the session's token may not
  push workflow files, so Linux is built here, not yet on GitHub.

## Tried so far

On this machine under GTK's Broadway (GTK in a browser tab), against the
test Jellyfin: signing in from the keyring and from the file, Home, Radio,
Albums, an album, Now Playing, the radio playing on from song to song,
MPRIS's Play, Next and metadata, the handoff both ways. Since 15 November
2026 the walk (`dev/linux-screens.sh`) also downloads an album, a playlist
and a mix from the fake Jellyfin by their pages' buttons and plays one from
its file; `frames.txt` says what came.

Not yet tried: a real Wayland session with sound, Navidrome in the app (its
calls are tested in the kit), KDE, XFCE and Hyprland themselves.
