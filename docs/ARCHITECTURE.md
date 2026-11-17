# Jukebox: how it is built

The photographer's own music app for their server's music: artists, albums,
songs, playlists, playlists the app makes up itself on Home, and a radio
that plays on from anything. iPhone, iPad and the Mac (one SwiftUI target);
Linux since 14 November 2026 (the same Swift under GTK and libadwaita,
`docs/LINUX.md`). Jellyfin; since 9 November 2026 also Navidrome and other
Subsonic servers.

Asked for on 8 November 2026: "op de homepage wil ik dat de app zelf leuke
playlists verzint en of een goede radio functie heeft — ik vind vooral de
radiofunctie echt belangrijk".

Design: Apple's HIG and native controls, with a brand of its own, the Arch
(`docs/BRAND.md`): two bands and a core, Copper and Glow, Cabinet. A sibling
of Numa in restraint, no longer in its shapes. Drawn by the rules of
`docs/design/tells.md` ("more soul": light means on air, flat grounds,
titles in New York, facts not slogans). A wide window, the iPad's and the
Mac's, is Linux's window, 1:1 (below).

## Layout

| Path | What |
|---|---|
| `JukeboxKit/` | Swift package, Foundation only, Swift 6 strict. Jellyfin, Subsonic, Last.fm and LRCLIB clients, the library index, the radio, the mixes, the LRC parser. Built and tested on Linux (`dev/kit-test.sh`) against a real Jellyfin (`dev/jellyfin-test-server.sh`). |
| `Jukebox/` | The SwiftUI app for the iPhone, the iPad and the Mac: iOS 26 and macOS 26, Swift 5 mode, MainActor default isolation (project.yml). The Mac is a native macOS destination of the same target, not Catalyst; `Components/Platform.swift` holds the few things the two spell differently (the image type, the device's name, the bar's placements, `\.isWide`). Compiled on GitHub's macOS (`ci/app.sh`) and, for a quick try, on the photographer's Mac (`docs/RELEASE.md`); not on the Linux machine, so read its Swift twice before pushing. |
| `Linux/` | The Linux client: `App/` (Swift on GTK 4, libadwaita, GStreamer), `CGlue/` (the C Swift cannot call as it is, and MPRIS), `data/` (icon, desktop entry). Built and run here: `dev/linux-build.sh`. `docs/LINUX.md`. |
| `Package.swift` | The Linux client's package. Its `shared` list names the files of `Jukebox/` Linux compiles too (the stores, not the screens). A file that gains `import SwiftUI` leaves the list, or loses the import. |
| `project.yml` | XcodeGen. One target for the iPhone, the iPad and the Mac: one bundle ID, so one App Store record and one purchase. Every file under `Jukebox/` is in the app; no .xcodeproj in git. |
| `ci/` | What `.github/workflows/ci.yml` runs: the iPhone's build and the Mac's, the screenshot walk, the upload (`docs/RELEASE.md`). The workflow stays generic: the Claude session may not push workflow files. |
| `dev/` | The test servers and their made-up library, the kit tests, the Linux build and its screenshot walk, the fake Jellyfin and its demo library (`demo/`, recorded once from the test server), the 4-point grid check. |
| `docs/` | This; `RADIO.md` (how the radio chooses); `BRAND.md` (the Arch, its rules and colours); `SERVERS.md` (Jellyfin and Subsonic, call by call); `OFFLINE.md` (songs kept on the phone); `LINUX.md` (the Linux client); `STATS.md` (anonymous usage counts); `RELEASE.md` (the App Store, the builds, the Mac); `brand/` (the mark and the boards); `design/tells.md` (sketch D's rules, the reference for every screen). |

## Rules for every part

- **Contracts.** A file marked `CONTRACT` declares a public surface; its
  bodies are `fatalError("not built yet")` until the owner writes them.
  Keep its signatures: other parts are written against them at the same
  time. Add to a type in your own files (extensions, private helpers). If a
  contract is truly wrong, change it minimally and say so in your report.
- **Ownership.** Each part writes only its own files (below). Shared
  components (`Jukebox/Components/*`, `Jukebox/App/*`) are the lead's: use
  them as they are, report what you would change.
- **Native first.** NavigationStack, List, ScrollView with
  LazyVGrid/LazyHStack, `.searchable`, `ContentUnavailableView`, `Menu`,
  `.contextMenu`, `.swipeActions`, `.refreshable`, `.toolbar`, sheets, SF
  Symbols. iOS 26 is the minimum; use its APIs plainly (Tab,
  `tabViewBottomAccessory`, `glassEffect` only where Apple's own apps use
  glass). UIKit only where SwiftUI has nothing (MPVolumeView,
  AVRoutePickerView). The wide window is the one thing drawn by hand,
  1:1 with Linux's (below).
- **The Arch** (`Theme.swift`, `docs/BRAND.md`, `docs/design/tells.md`).
  `Theme.accent` is the one accent (Copper #A84A17 by day, Glow #FFB54D by
  night), `Theme.onAccent` on it. One filled button per screen
  (`.buttonStyle(.prominent)`, a plain rectangle); every other action a
  word in the accent (`.secondary`) or a plain SF Symbol. Titles in New
  York (`Font.serif(_:)`; the bars' through `Theme.styleNavigationBars`).
  `SectionHeader` (serif heading, a fact, See All) for a page's sections,
  `ListHeading` in a list, `Eyebrow` only for a screen's one small label
  ("On air"). `Hairline` between things, not cards. `Theme.ground` under the
  main screens. One radius, `Theme.Radius.artwork` (6 pt). `ArchMark` for
  the mark, `StationArtwork` for a station: the arch only ever means a
  station, and only the one on air is lit ("light means on air"); mixes,
  albums and playlists stay square. `RelativeDay` writes the facts ("Played
  Thursday", "Made at 06:00").
- **The 4-point grid.** Every distance and size is a multiple of 4:
  `Theme.Space` (4, 8, 12, 16, 24, 32) on the iPhone, the same numbers on
  Linux. "zorg dat alles past op een 4pt grid" (14 November 2026).
  `dev/grid-check.sh` walks both and names what is off. A line that must
  differ says `grid-ok` and why (a hairline is a pixel; the system's own
  grabber is 36 by 5).
- **Each platform's own guidelines.** Apple's HIG on the iPhone, GNOME's on
  Linux ("iphone heeft apple's eigen HIG"); Jukebox's own in the content.
- **Comments say why**, in plain words, quoting the photographer where they
  decided. Measurements rather than claims.
- **English UI**, as Numa's. Strings as literals (`Text("Albums")`); the
  String Catalog picks them up.
- **Swift you cannot compile.** Plain, well-known API. Unsure a modifier
  exists on iOS 26? Use the older one you are sure of. Mark nothing
  `@MainActor` by hand in the app (it is the default); mark `nonisolated`
  what must run elsewhere. `Sendable` value types from JukeboxKit cross
  freely.

## Ownership

| Part | Files |
|---|---|
| Lead | `project.yml`, `ci/`, `dev/`, `Jukebox/App/*` (with WideShell, PanelState, Commands: the Mac's menus and ⌘F), `Jukebox/Components/*` (with Platform, WidePage, DesktopMeasures), kit `Models.swift`, `NameKey.swift`, `HTTPTransport.swift`, `LibraryCache.swift` |
| Kit: Jellyfin | `JukeboxKit/Sources/JukeboxKit/Jellyfin/*` (client, DTOs), its tests |
| Kit: radio | `Library/LibrarySnapshot.swift`, `Radio/*`, tests, `docs/RADIO.md` |
| Kit: mixes and Last.fm | `Mixes/*`, `LastFM/*`, tests |
| Kit: lyrics | `Lyrics/*` (LRCParser, LyricsQuery, LRCLIBClient, LyricsCache), tests |
| Kit: artwork | `Artwork/CoverAccent.swift` (Now Playing's accent from its cover, BRAND.md), `Artwork/CoverWall.swift` (the still page's wall and floor from it), tests |
| Kit: servers | `Server/*` (MusicServer, the CONTRACT; JellyfinServer; ServerAddress), `Subsonic/*` (SubsonicClient, its requests, answers, sign-in, MD5), their tests (Subsonic*, JellyfinServer, ServerAddress, Navidrome's integration, the contract on both servers), `dev/navidrome-test-server.sh`, `docs/SERVERS.md` |
| Kit: offline | `Offline/*` (OfflineManifest, KeepPolicy: the automatic keep, JellyfinClient.downloadURL), tests, `docs/OFFLINE.md` except "In the app" |
| App: library | `Jukebox/Library/*`: LibraryStore, every library screen, AddToPlaylistSheet |
| App: player | `Jukebox/Player/*`, `Jukebox/Radio/RadioController.swift`: AudioPlayer, HistoryStore, Now Playing info, remote commands, audio session, the radio's feeding. `PlayQueue` is the queue and its rules on both platforms (play, next and previous, shuffle, repeat, Up Next's edits and "Then", the radio's feed and trim, the playback reports); each AudioPlayer is that class with its engine (AVQueuePlayer; `Linux/App/AudioPlayer.swift`'s GStreamer), and `Linux/App/QueueCheck.swift` checks the rules after every Linux build |
| App: now playing | `Jukebox/NowPlaying/*`: MiniPlayer, NowPlayingView, SleeveRecord (the sleeve and its record in the cover's place), NowPlayingGround (the land, the wall), QueueView, LyricsView, AirPlay and volume; the wide window's PlayerBar and PanelView; UpNextList (Up Next's rows, shared with Linux) |
| App: home and radio | `Jukebox/Home/*`, `Jukebox/Radio/*` except RadioController: MixStore, HomeView, MixDetailView, RadioView |
| App: shell | `Jukebox/Settings/*`, `Jukebox/Search/*`: OnboardingView (sign in to any server: the address, then a password, Quick Connect or an API key), SettingsView, SearchView |
| App: offline | `Jukebox/Offline/*`: OfflineStore (songs on the phone per account, the queue, the keep's runs, offline or not, plays heard offline), OfflineStore+Apple (the network, Low Power Mode, the folder), OfflineDownloader (the background URLSession, JukeboxAppDelegate), OfflineDisk (folders and files), OfflineText, OfflineDownloadButton, DownloadedView; `docs/OFFLINE.md`'s "In the app". The store, the disk and the words are Linux's too (`shared`). |

## The views each part provides

`Navigator.swift`'s `routeDestinations()` and `JukeboxApp.swift` name these;
each must exist with exactly this initializer.

- Library: `LibraryView()`, `ArtistsView()`, `ArtistDetailView(artist: Artist)`,
  `AlbumsView()`, `AlbumDetailView(album: Album)`, `SongsView()`,
  `PlaylistsView()`, `PlaylistDetailView(playlist: Playlist)`, `GenresView()`,
  `GenreDetailView(genre: Genre)`, `FavoritesView()`, `RecentlyAddedView()`,
  `AddToPlaylistSheet(tracks: [Track])`.
- Offline: `DownloadedView()` (`Route.downloaded`, Library › Downloaded).
- Now playing: on the iPhone `MiniPlayer()`, inside
  `tabViewBottomAccessory`, reading
  `@Environment(\.tabViewBottomAccessoryPlacement)` to draw inline or
  expanded, and `NowPlayingView()` in a fullScreenCover. In the wide window
  `PlayerBar()`, `PanelView()`, and `NowPlayingView()` as the room.
- Home and radio: `HomeView()`, `MixDetailView(mix: Mix)`, `RadioView()`,
  `StationDetailView(station: Station)` (`Route.station(station)`).
- Shell: `OnboardingView()`, `SearchView()` (a tab on the iPhone, the bar's
  field in the wide window), `SettingsView()` (a sheet from Home's toolbar
  on the iPhone and from the places' ≡ menu on the iPad;
  `SettingsView(asWindow: true)` is the Mac's Settings window, ⌘,).

### Now Playing

Sketch E's D2 and D1, as the photographer chose them: "D1 is reduced
motion/batterij besparing d2 normaal" (8 November 2026).

In the cover's place sits the album's sleeve as a printed card, its black
record half out, the label turning (`NowPlaying/SleeveRecord.swift`). Under
the whole page lies `NowPlayingGround` (`NowPlaying/NowPlayingGround.swift`),
put behind it through `backgroundPreferenceValue` and told by
`NowPlayingAnchorsKey` where the page put the sleeve's room and the title.

- D2, normally: the album's side as a giant record whose grooves cross the
  page, one band per song (`TurntableSide`, from
  `LibraryStore.tracks(inAlbum:)`). The playing song's band starts above
  its title, is lighter where it has played, and moves on one band when the
  song changes. One bitmap, drawn once per album and screen, off the main
  thread.
- D1, with Reduce Motion, Low Power Mode or Settings' Spin the Record off
  (`AppSettings.spinRecord`): a wall and a floor in the cover's colours
  (JukeboxKit's `CoverWall`). Nothing moves.

The arithmetic is `TurntableMeasures.swift` (the land, the sleeve's layout,
`RecordMotion`'s numbers, the clock), Foundation only and built on Linux
too. One timeline turns what turns, at most 20 frames a
second (30 once the land itself turns, sketch H), and only while the sleeve
shows, the music plays, the app is active and the page is D2. At rest it is
paused. `docs/BRAND.md` says why each.

### A station's page

`StationDetailView` shows what a station would play before it plays. Every
tile and card of a station opens it, because the photographer asked to see
what the radio made first: "Als je nu klikt op een tegel van radio begint er
meteen van alles te spelen ipv dat je kan zien wat je van de playlist gemaakt
hebt" (8 November 2026). A long press's Play Station, Your Station's Play on
Home and Radio, and every "Start Radio" still play at once.

## The wide window

The iPad at regular width and the Mac always (`\.isWide`) get Linux's window
in place of the tabs: `App/WideShell.swift`, drawn by hand 1:1 with Linux's
`MainWindow.swift`. NavigationSplitView and the inspector would fold and look
their own way. The photographer, 14 November 2026: "ik wil dat de linux app
en de apple app 1:1 op elkaar lijken". The iPhone, and an iPad window made
narrow, keep their tabs (`MainTabView`).

- **The places**, 240 at the left: Home and Radio, a hair, the library's
  kinds, a hair, the playlists with their covers. Below 900 wide they fold
  away and come over the page when asked for.
- **The page**: a NavigationStack on `navigator.widePath`, with the window's
  bar on every page. At its trailing end sits the one search field (⌘F); a
  click in it shows the Search page. Search has no row of its own.
- **The panel**, 360 at the right (`NowPlaying/PanelView.swift`), Now Playing: the queue or
  the lyrics, opened from the bar. `PanelState`, shared with Linux, keeps it
  across launches. Below 1280 it lies over the page.
- **The bar**, 88 across the window's foot (`NowPlaying/PlayerBar.swift`),
  its three zones from `DesktopMeasures`, shared with Linux.
- **Full Player** is a room over the places and the page (`\.inRoom`); the
  bar and the panel stay.

Every wide page is built from `Components/WidePage.swift`: `desktopFont`
(Linux's pixel sizes as points, the same on the Mac and the iPad),
`WidePage`, `PageTitle`, `PageHead`, `TileGrid`. A `Shelf`
(`Components/Tiles.swift`) shows ‹ and › under a pointer, as Linux's.

The rule: 1:1 with Linux. Native wins only where the OS has its own place
for a thing: the Mac's menu bar in place of the ≡ menu, the toolbar's search
field, the logo beside the traffic lights. "hier trumpt native de 1:1
requirement" (14 November 2026).

## The environment

`JukeboxApp` puts these in the environment, read with `@Environment(X.self)`:
`AppModel`, `Navigator`, `AppSettings`, `LibraryStore`, `HistoryStore`,
`AudioPlayer`, `RadioController`, `MixStore`, `OfflineStore`, `HandoffStore`,
`PanelState`.

- `AppModel.server` is the signed-in server, `any MusicServer` (Jellyfin or
  Subsonic); `AppModel.credentials` its `ServerCredentials`;
  `LibraryStore.server` the same one. `AppModel.accounts` every account
  kept (below, Accounts).
- What a server lacks is not offered: `app.can(.lyrics)`,
  `library.can(.playlistReorder)` (`ServerCapability`).
- Words name the server by its kind: `library.serverKind` ("your Navidrome
  server").
- Offline (`OfflineStore.isOffline`) only songs on the phone play: a row
  asks `player.refusesOffline(track)` before it plays, and `TrackRow` dims
  what cannot.

Starting things, from any screen:

| To start | Call |
|---|---|
| an album | `player.play(tracks, startingAt: i, context: QueueContext(.album(album.id), title: album.name))` |
| shuffle | the same with `shuffled: true` |
| a station | `radio.start(.artist(key: artist.key, name: artist.name, id: artist.id))`, `radio.start(.track(id))`, `radio.start(station)` |
| a station's page | `navigator.open(.station(station))` |
| going somewhere | `navigator.open(.album(album))` |
| Now Playing | `navigator.isNowPlayingPresented = true` |

A station's page plays the list it shows. It asks
`radio.preview(station, randomSeed:)` for its first 25 songs (chosen as
`begin` chooses, the session kept); Play is
`radio.start(station, preview: picks, from: i)`.

- The seed is the station's draw, `radio.pageSeed(for:)`: the same each
  time the page opens while the app runs, so going back shows the list seen
  before. New Picks draws another (`radio.drawPageSeed(for:)`).
- Lists are kept by station and draw, so one station's page on two tabs
  each plays its own.
- A newer library, graph or dial makes the kept list stale
  (`radio.previewInputs` moves; the page chooses again, same seed). It also
  chooses again when another song plays, as the list leaves out the one
  playing.
- A stale or unknown list starts the station afresh.

## Jellyfin

The test server (`dev/jellyfin-test-server.sh`) runs Jellyfin 12.4 (the
`latest` image, November 2026): user `test`/`test`, 23 made-up artists, 358
tracks in MP3, FLAC and M4A, genres in clusters. Requests carry
`Authorization: MediaBrowser Client="Jukebox", Device="…", DeviceId="…", Version="…", Token="…"`.
Times are ticks (10 000 000 a second); dates have seven fractional digits.

## From one device to another

The photographer, 13 November 2026: "ik wil ook dat de ios app en de linux
app van elkaar kunnen zien wat ze afspelen net als bij spotify zodat ik
verder kan waar ik gebleven was als ik wegga van mijn pc".

What a device plays is kept on the listener's own server, with no service of
Jukebox's in between, as JukeboxKit's `PlayState` (`Server/PlayState.swift`):
the queue around the current song, where it is, the device, the station if
one played. `MusicServer.savePlayState` and `playState` keep and read it: on
Jellyfin in the user's DisplayPreferences for the client "Jukebox", on a
Subsonic server as its API's play queue. Measured on Jellyfin 12.4 and
Navidrome 0.64.2; `PlayStateTests` saves and reads on both.

`HandoffStore` (`Jukebox/Player/HandoffStore.swift`, one file for both
platforms) saves when the song changes, on pause and resume, and every half
minute while music plays. It reads every 15 s and before every save.

- Another device's session is offered as "Playing on tijmen-pc" or "Left
  off on iPhone", with Continue Here: a notice on Home on both, never at
  the player's controls ("ik wil die melding echt niet over de controls
  hebben", 14 November 2026).
- A device's own last session is offered at its next launch ("Where you
  left off"). On Linux the keyboard's Play key takes it.
- With Continue Where You Left Off on (Settings, Preferences; on by
  default), that first offer is not a notice: its queue waits in the
  player, paused at its song and place, and Play is Continue Here ("ik denk
  dat het nummer gewoon onderin de player al klaar moet staan", 14 November
  2026). It is this device's last session or another's left off; one
  playing elsewhere is still said, "Playing on …". Nothing is saved until
  Play.
- Continue Here plays the queue from its song, at its place (or where it is
  by now, while the other still plays). A station plays on as a station
  (`RadioController.continueStation`).
- On Jellyfin the device the music was taken from stops when it next looks,
  once for each taking (`PlayState.takenAt`): Play there again later is its
  own music. A Subsonic server keeps no word of who took it, so there it plays on until
  it is paused.

## Accounts

More than one account kept, one signed in: a home server and a shared one,
or two people on one server. Asked for with the other players' features
Jukebox lacked, "maak ze allemaal maar" (17 November 2026).

- **Who owns the list**: `Accounts` (`Jukebox/App/Accounts.swift`, shared
  with Linux), on JukeboxKit's `SavedAccounts` (tested in the kit). The
  keychain keeps two items: `credentials`, the session signed in, as it
  always did (a build from before the list reads it alone), and `accounts`,
  the list. Linux's keyring the same, or two files.
- **The migration**: an install with a session and no list makes the
  session the list's only entry; its `history.json`, `recentStations` and
  Last.fm answers are renamed to that account's (`AccountFiles.adoptLegacy`,
  only what is not there yet, so a second run moves nothing). Nobody signs in
  again. A list that could not be read (a locked keychain, a keyring that did
  not answer) is never written over.
- **Per account**, named by its server's id and its user's
  (`OfflinePaths.account`): the session, the library cache, the songs on the
  device (a folder each; no folder is swept any more), the listening history
  (the radio's learning, what the mixes are made from), the recent stations,
  the Last.fm answers about its library (they name its songs by id). Home's
  mixes are made again from those.
- **Shared**: `AppSettings` (qualities, pages, downloads' limit, the
  switches) and the Last.fm API key, a key to Last.fm's catalogue rather
  than anyone's Last.fm account (the servers scrobble).
- **A switch** (`AppModel.switchAccount`): the new account's server is asked
  first, with its own session (`AccountStores.reach`, 10 s at most); silent,
  the account signed in stays and the words say so, unless the new one has
  songs on the device (offline, they play). Then `AccountStores.close`: the
  handoff lets go, the player stops (clearing the queue and the sleep timer,
  its last song told to its own server and history), every store writes its
  account's files; `open` reads the next one's, and the window goes Home.
  CarPlay's lists follow and pop to their root; Siri waits for the switch.
- **Signing out** of an account forgets its library cache, songs, recent
  stations and Last.fm answers; its history stays, for a sign-in again. Of
  the one signed in: the next account opens, or the sign-in screen when none
  is left. Add Account is the sign-in screen, in a sheet (Linux: over the
  window, with Cancel).
- **Where**: Settings' account section (rows, the one signed in checked, a
  tap switches, a swipe or a long press signs out of another; Add Account;
  Sign Out); the iPad's ≡ menu and the Mac's Account menu
  (`Settings/AccountMenu.swift`); Linux's primary menu and Preferences ›
  Accounts.
- **Checked**: JukeboxKit's `SavedAccountsTests` (the migration, and the
  test Jellyfin's two users, test and second); Linux's `AccountCheck`
  after every build (`dev/linux-errors.sh`).

## Scrobbling

The server scrobbles, not Jukebox: Jellyfin with its Last.fm plugin,
Navidrome with its own Last.fm link, from the playback reports the app
already sends (Jellyfin's start/progress/stopped; Subsonic's scrobble). The
photographer, 8 November 2026: "Laat scrobblen lekker via de server lopen."
One place for every client, and no song twice on Last.fm. The Last.fm key in
Settings is only for the radio's similar artists and songs.

## Lyrics

The photographer, 8 November 2026, from the TestFlight build: "Kun je ook
lyrics toevoegen". Now Playing's Lyrics panel (`LyricsView`, through
`LyricsFinder`) looks in two places.

1. The server first: Jellyfin's `/Audio/{id}/Lyrics`, a Subsonic server's
   `getLyricsBySongId` or `getLyrics`. Not a server without `.lyrics`;
   with neither `.lyrics` nor LRCLIB there is no Lyrics button.
2. Most libraries have none, so then LRCLIB (lrclib.net), while Settings'
   Find Lyrics Online is on (the default): a free, open lyrics database
   without a key, which Feishin uses too. `/api/get` with title, artist,
   album and length. On a 404, or no answer in 8 s (it may look beyond
   LRCLIB's own database), `/api/search`: the record of the same title and
   artist nearest in length, synced first, never one more than 3 s off
   (another recording, whose timed lines would drift) or without a length.

An artist matches as a whole name or one of the record's credits ("Daft
Punk, Pharrell Williams"), never a name that only begins with ours ("Queen"
is not "Queensrÿche"). Only the title (without "feat."), the main artist,
the album and the length are sent.

Answers are kept on disk (`LyricsCache`, about 1.2 kB a song): found for 90
days, not found for 3. Nothing is asked while the panel is closed. The
song's lookup is cancelled when the song changes or the panel closes; while
it is open, the next song is looked up too, once the playing song's answer
is in.

`LRCLIBLiveTests` asks the real LRCLIB where it answers within 3 s (GitHub's
runners) or with `LRCLIB_LIVE=1`, and skips itself elsewhere.

## The sleep timer

Asked for with what other players have ("maak ze allemaal maar").
One timer in `PlayQueue`, so every client keeps the same:
15, 30 or 45 minutes, an hour, End of Song, End of Album (or Playlist, or
Queue; not on a station). A timer of minutes is a deadline the player's own
ticks look at, not a Timer iOS may suspend in the background; its last 8 s
fade the music through `level(for:)`, then it pauses and the volume is the
listener's again. End of Song holds nothing after the song, so it ends by
itself and the next waits, paused; End of Album goes round no Repeat All and
starts no Autoplay. In Now Playing's ⋮ (`SleepTimerMenu.swift`), saying
when it stops, a small moon before ⋮ while set; on the Mac also Controls ›
Sleep Timer. Not in the car.

## CarPlay

The car's screen, Apple's templates (`Jukebox/CarPlay/CarPlayScene.swift`,
the lead's). Asked for on 16 November 2026: "we missen iets echt extreem
belangrijks in de ios app, carplay!"

- Tabs Home (Your Station, mixes, played lately, recently added), Radio
  (the Radio tab's stations, the one on air marked) and Library (playlists,
  albums, artists, favourites, downloaded), as Settings › Pages shows them.
  An album, a playlist or an artist pushes its songs, Play and Shuffle on
  top. Five deep at most with Now Playing and Up Next.
- Now Playing is `CPNowPlayingTemplate`, fed by NowPlayingInfo and
  RemoteCommands. Its buttons: a station's thumbs, otherwise shuffle and
  repeat. Up Next lists the queue.
- Every tap plays through the phone's own calls (`player.play`, `playMix`,
  `radio.start`): the same queue, offline rules and counts.
- `AppModel.shared` is the one model: CarPlay can launch the app without
  its window, so the scene calls `restore()` too. Lists follow the stores
  through `withObservationTracking`.
- The scene manifest in project.yml names only the car's role; SwiftUI's
  App keeps the phone's window. Multiple scenes on, so the window and the
  car run at once; the iPad's own manifest (`~ipad`) keeps it one window.
  No lyrics and no other phone-only notice
  in the car (Apple's CarPlay addendum). Entitlement: `docs/RELEASE.md`.

## Siri and Shortcuts

`Jukebox/Intents/`. Asked for with the other players' features ("maak ze
allemaal maar", 17 November 2026); in the car, without a voice, every song
is a tap while driving.

- **"Play … in Jukebox"**, any name in the library, on the iPhone, the iPad and in the car:
  SiriKit's `INPlayMediaIntent`, handled in the app (`SiriMedia.swift`,
  through `JukeboxAppDelegate`), no extension. Siri hears the name and what
  it is; `Voice.find` looks in the library. No name: Your Station. A
  station's name ("Radiohead radio"): its station.
- **Why not App Intents alone**: an App Shortcut's phrase matches only the
  names suggested beforehand, and App Intents' audio schema (MediaIntents'
  `AudioSearch`) is iOS 27.
- **App Intents** (`MusicIntents.swift`), on the iPhone, the iPad and the
  Mac, in Siri and the Shortcuts app with nothing set up: Play, Start a
  Station, Play Your Station, Shuffle (the library or the favourites), Like
  This Song. `MusicEntity` is an album, artist, playlist, song, genre or Your
  Station; its query searches the library in memory. Pause, Next and the
  rest are the system's (RemoteCommands).
- **One way of playing**: `Voice` calls `player.play`, `radio.start`,
  `radio.like` as the screens do. It waits for `AppModel.shared` to restore
  the session, as CarPlay does from a cold start; signed out it says to sign
  in. Counts: `from` `siri` (`docs/STATS.md`).
- **On the device**: entities stay in the app; nothing is donated, given
  as vocabulary or put in Spotlight. The playlists, the albums played lately
  and the favourites are the phrases' suggestions.
- Siri's permission is asked once, when the window has a library. The
  entitlement: `docs/RELEASE.md`, Siri.

## Usage counts

Anonymous counts of which screens and features are used go to the
photographer's own OpenPanel (stats.numa.photo) through
`Jukebox/App/Stats.swift`, on unless Settings › Privacy turns them off:
"alles tracken wat je mag zonder cookie melding" (8 November 2026). A closed
list of events with coarse properties, never a title, an artist, a search or
a server: `docs/STATS.md`.

## Navidrome and the other Subsonic servers

Asked for on 8 November 2026: "Moet eigenlijk ook voor navidrome en die
ander". `docs/SERVERS.md` is the design: `MusicServer`
(`JukeboxKit/Sources/JukeboxKit/Server/MusicServer.swift`, a CONTRACT), one
protocol for Jellyfin and Subsonic that the app moves to from
`JellyfinClient`; how the app finds which server is at an address; what the
keychain keeps; and the map from every call to both APIs, measured on
Jellyfin 12.4 and Navidrome 0.64.2. `dev/navidrome-test-server.sh` starts
Navidrome on the same made-up library (user test/test, port 4533).

### In the app

The photographer, 9 November 2026, before the release: "Kun je die
navidunges en subsonic toevoegen dan Istie erna wel klaar voor release". The
whole app, not a part. Nothing in `Jukebox/` holds a `JellyfinClient` any
more; one `any MusicServer` goes where it did.

| Where | What it does with the server |
|---|---|
| `AppModel` | `MusicServers.open(credentials)` at a launch and a sign-in; hands it to the player, the radio, the library and the offline store. Once a launch, in the background, `currentCapabilities()` (and the version, for a sign-in the Jellyfin-only app kept); a changed session is saved and every store goes on with it (`use`). Sign-out: `server.signOut()` (Jellyfin forgets its token; Subsonic has none, the keychain forgets). |
| `Keychain` | One item as before, now `ServerCredentials`. The Jellyfin-only app's `Credentials` decodes as a Jellyfin session (JukeboxKit's `ServerCredentialsTests`), so the update signs nobody out. The library cache and the downloads' folder are named by the same server and user ids, so they stay too. |
| `OnboardingView` | One address field. `MusicServers.detect` (through `app.detectServer`) asks every candidate both ways at once. The account step says "Signing in to Tijmen's Music", "Jellyfin 12.4.0 · music.example.com"; a Subsonic server has no name: "Signing in to nas.local", "Navidrome 0.64.2 · nas.local:4533". User name and password everywhere; Use Quick Connect where the kit's sign-in is a `QuickConnectSignIn` (a Jellyfin with it on); Use an API Key where it is an `APIKeySignIn`, and at once when a password sign-in throws `needsAPIKey` (with the server's help link). Errors in words: no server there, the password would go over plain http (`passwordNeedsHTTPS`), the account may not play (`notAllowed`). |
| `LibraryStore` | `allTracks`, `allAlbums`, `allArtists`, `playlists`, `genres` (each server pages as suits it, in the kit); `setFavorite(_:item:)` with the `ItemRef` the heart knows (track, album, artist); the playlist calls; `MusicServerError`. |
| `AudioPlayer` | `streamURL(for:quality:playSessionID:)`; `report(.nowPlaying)` when an entry first plays (Subsonic shows it as playing; Jellyfin is told nothing), `.played` when it is not a skip (PlayOutcome, where every server counts it), `.progress`, `.stopped`. |
| `RadioController` | `instantMix(from: MixSeed)` where `.instantMix`: a playlist is `.playlist` when the library has it, a made-up mix starts from its first track, a genre the library split out has no id (Jellyfin then has nothing; Subsonic mixes by name). An artist's station: the server's `topSongs` where `.topSongs`, else (or when it had none) Last.fm as before. |
| `LyricsFinder` | `lyrics(for: track)` where `.lyrics`; an `unsupported` or `notFound` answer counts as none, so LRCLIB is asked. |
| `OfflineStore` | `downloadURL(for:quality:)`, `downloadsAllowed()`. Whether the server answers is `currentCapabilities()` (Jellyfin's public info, a Subsonic ping); a server that refuses the session (`unauthorized`) still answered. Plays heard offline go as `.played` and `.stopped`. |
| Artwork | `artworkURL(_:maxPixelSize:)` in `ArtworkView`, `StationArtwork`, Now Playing's accent and ground, the lock screen. A Subsonic URL carries the session's one token and salt, so a cover is always one URL and the cache holds. |
| Screens | `can(_:)` hides Lyrics (without `.lyrics` and LRCLIB), similar artists' request (`.similarArtists`), move handles (`.playlistReorder`), Normalize Volume (`.replayGain`; off, with why). `Playlist.isReadOnly` (someone else's): no Delete, Add Songs or Edit, and not among Add to Playlist's. Up Next says "From Navidrome's mix" (JukeboxKit's `PickReason.instantMix.text` still says Jellyfin's). |
| Settings | Server: the name, and under it the kind and version ("Navidrome 0.64.2", without Navidrome's build in brackets). The quality footers say AAC for Jellyfin, MP3 for a Subsonic server. |
| Stats | `app_open` and `signed_in` carry `server`: `jellyfin`, `navidrome`, or `subsonic` for every other (`none` signed out); `docs/STATS.md`. |

The screenshot walk signs in to the fake Jellyfin through the same screen:
`dev/fake-jellyfin.swift` answers `/rest/…` as Jellyfin 12.4 does (404, no
body: not a Subsonic server), so it is found as Jellyfin.
