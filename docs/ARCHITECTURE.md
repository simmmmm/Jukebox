# Jukebox: how it is built

Jukebox is the photographer's own music app for the iPhone and the iPad:
their Jellyfin server's music — artists, albums, songs, playlists — with
playlists the app makes up itself on Home and a radio that plays on from
anything. Asked for on 8 November 2026: "op de homepage wil ik dat de app zelf
leuke playlists verzint en of een goede radio functie heeft — ik vind vooral
de radiofunctie echt belangrijk". Design: Apple's HIG and native controls,
with a brand of its own, the Arch (`docs/BRAND.md`): two bands and a core,
Copper and Glow, Cabinet — a sibling of Numa in restraint, no longer in its
shapes — drawn by the rules of `docs/design/tells.md` ("less AI": light
means on air, flat grounds, titles in New York, facts not slogans).

## Layout

| Path | What |
|---|---|
| `JukeboxKit/` | Swift package, Foundation only, Swift 6 strict. Jellyfin, Last.fm and LRCLIB clients, the library index, the radio, the mixes, the LRC parser. Built and tested on Linux (`dev/kit-test.sh`) against a real Jellyfin (`dev/jellyfin-test-server.sh`). |
| `Jukebox/` | The SwiftUI app, iOS 26, Swift 5 mode with MainActor default isolation (project.yml). Compiled only on GitHub's macOS (`ci/app.sh`) — there is no Mac here, so Swift in `Jukebox/` is read twice before it is pushed. |
| `project.yml` | XcodeGen. Every file under `Jukebox/` is in the app; no .xcodeproj in git. |
| `ci/` | What `.github/workflows/ci.yml` runs. The workflow file itself is generic, because the Claude session may not push workflow files. |
| `dev/` | The test server, the made-up library, the kit tests, the icon (`make-icon.py`) and the brand's drawings (`brand/`). |
| `docs/` | This, `RADIO.md` (how the radio chooses), `BRAND.md` (the Arch, its rules and colours), `STATS.md` (the anonymous usage counts), `brand/` (the boards), `design/` (sketch D and its rules, `tells.md`: the reference for every screen). |

## Rules for every part

- **Contracts.** Files marked `CONTRACT` declare a public surface; their
  bodies are `fatalError("not built yet")` until the owner writes them. Do not
  change a contract's signatures: other parts are written against them at the
  same time. Add to a type in your own files (extensions, private helpers).
  If a contract is truly wrong, change it minimally and say so in your report.
- **Ownership.** Each part writes only its own files (table below). Shared
  components (`Jukebox/Components/*`, `Jukebox/App/*`) are the lead's; use
  them as they are and report what you would change.
- **Native first.** NavigationStack, List, ScrollView with LazyVGrid/LazyHStack,
  `.searchable`, `ContentUnavailableView`, `Menu`, `.contextMenu`,
  `.swipeActions`, `.refreshable`, `.toolbar`, sheets, SF Symbols. iOS 26 is
  the minimum: use its APIs plainly (Tab, `tabViewBottomAccessory`,
  `glassEffect` only where Apple's own apps use glass). No UIKit unless SwiftUI
  has nothing (MPVolumeView, AVRoutePickerView).
- **The Arch, from `Theme.swift`, `docs/BRAND.md` and `docs/design/tells.md`.**
  `Theme.accent` (Copper #A84A17 by day, Glow #FFB54D by night) is the one
  accent, with `Theme.onAccent` on it; one filled button per screen
  (`.buttonStyle(.prominent)`, a plain rectangle), every other action a
  word in the accent (`.secondary`) or a plain SF Symbol; titles in New
  York (`Font.serif(_:)`, and the bars' through `Theme.styleNavigationBars`);
  `SectionHeader` (a serif heading, a fact, See All) for a page's sections
  and `ListHeading` in a list; `Eyebrow` only for the one small label a
  screen may have ("On air"); `Hairline` between things instead of cards;
  `Theme.ground` under the main screens; one radius, `Theme.Radius.artwork`
  (6 pt). `ArchMark` for the mark and `StationArtwork` for a station — the
  arch only ever means a station, and only the station on the air is lit
  ("light means on air"); mixes, albums and playlists stay square.
  `RelativeDay` writes the facts ("Played Thursday", "Made at 06:00").
- **Comments say why**, in plain words; where the photographer decided
  something, quote them. Measurements rather than claims.
- **English UI**, as Numa's. Strings as literals (`Text("Albums")`); the
  String Catalog picks them up.
- **Swift you cannot compile.** Prefer plain, well-known API. No guessing at
  API names: if unsure whether a modifier exists on iOS 26, use the older
  one you are sure of. Mark nothing `@MainActor` by hand in the app (it is the
  default); mark `nonisolated` what must run elsewhere. `Sendable` value types
  from JukeboxKit cross freely.

## Ownership

| Part | Files |
|---|---|
| Lead | `project.yml`, `ci/`, `dev/`, `Jukebox/App/*`, `Jukebox/Components/*`, kit `Models.swift`, `NameKey.swift`, `HTTPTransport.swift`, `LibraryCache.swift` |
| Kit: Jellyfin | `JukeboxKit/Sources/JukeboxKit/Jellyfin/*` (client, DTOs), its tests |
| Kit: radio | `Library/LibrarySnapshot.swift`, `Radio/*`, tests, `docs/RADIO.md` (how it chooses, measured) |
| Kit: mixes and Last.fm | `Mixes/*`, `LastFM/*`, tests |
| Kit: lyrics | `Lyrics/*` — LRCParser, LyricsQuery, LRCLIBClient, LyricsCache — and their tests |
| Kit: artwork | `Artwork/CoverAccent.swift` — Now Playing's accent from its cover (BRAND.md) — `Artwork/CoverWall.swift` — the still page's wall and floor from it — their tests, and `dev/accent.py`, the accent in Python for sketches |
| Kit: servers | `Server/*` — MusicServer (the CONTRACT), JellyfinServer, ServerAddress — and `Subsonic/*` — SubsonicClient, its requests, answers, sign-in and MD5 — their tests (Subsonic*, JellyfinServer, ServerAddress, Navidrome's integration, the contract on both servers), `dev/navidrome-test-server.sh`, and `docs/SERVERS.md` |
| Kit: offline | `Offline/*` — OfflineManifest, KeepPolicy (the automatic keep), JellyfinClient.downloadURL — their tests, and `docs/OFFLINE.md` but its "In the app" |
| App: library | `Jukebox/Library/*` — LibraryStore and every library screen, AddToPlaylistSheet |
| App: player | `Jukebox/Player/*`, `Jukebox/Radio/RadioController.swift` — AudioPlayer, HistoryStore, Now Playing info, remote commands, audio session, playback reports, the radio's feeding |
| App: now playing | `Jukebox/NowPlaying/*` — MiniPlayer, NowPlayingView, SleeveRecord (the sleeve and its record in the cover's place), NowPlayingGround (the land, the wall), QueueView, LyricsView, AirPlay and volume |
| App: home and radio | `Jukebox/Home/*`, `Jukebox/Radio/*` except RadioController — MixStore, HomeView, MixDetailView, RadioView |
| App: shell | `Jukebox/Settings/*`, `Jukebox/Search/*` — OnboardingView (sign in, Quick Connect), SettingsView, SearchView |
| App: offline | `Jukebox/Offline/*` — OfflineStore (the songs on the phone per account, the queue, the keep's runs, offline or not, plays heard offline), OfflineDownloader (the background URLSession, JukeboxAppDelegate), OfflineDisk (the folders and files), the download control (OfflineDownloadButton), DownloadedView; `docs/OFFLINE.md`, "In the app" |

## The views each part must provide (the names others use)

`Navigator.swift`'s `routeDestinations()` and `JukeboxApp.swift` name these; each
must exist with exactly this initializer:

- Library: `LibraryView()`, `ArtistsView()`, `ArtistDetailView(artist: Artist)`,
  `AlbumsView()`, `AlbumDetailView(album: Album)`, `SongsView()`,
  `PlaylistsView()`, `PlaylistDetailView(playlist: Playlist)`, `GenresView()`,
  `GenreDetailView(genre: Genre)`, `FavoritesView()`, `RecentlyAddedView()`,
  `AddToPlaylistSheet(tracks: [Track])`.
- Offline: `DownloadedView()` (`Route.downloaded`, Library › Downloaded).
- Now playing: `MiniPlayer()` (inside `tabViewBottomAccessory`; reads
  `@Environment(\.tabViewBottomAccessoryPlacement)` to draw inline or
  expanded), `NowPlayingView()` (in a fullScreenCover). Sketch E's D2 and
  D1, as the photographer chose them ("D1 is reduced motion/batterij
  besparing d2 normaal", 8 November 2026): in the cover's place the album's
  sleeve as printed card with its black record half out of it, the label
  turning (`NowPlaying/SleeveRecord.swift`); under the whole page
  `NowPlayingGround` (`NowPlaying/NowPlayingGround.swift`), behind the page
  through `backgroundPreferenceValue`, told where the page put the sleeve's
  room and the title (`NowPlayingAnchorsKey`). Normally D2, the album's
  side as a giant record whose grooves cross the page, one band per song
  (`TurntableSide`, from `LibraryStore.tracks(inAlbum:)`), the playing
  song's band starting above its title and lighter where it has played,
  moving on one band when the song changes: one bitmap drawn once per
  album and screen, off the main thread. With Reduce Motion, Low Power
  Mode or Settings' Spin the Record off (`AppSettings.spinRecord`), D1: a
  wall and a floor of the cover's colours (JukeboxKit's `CoverWall`), and
  nothing moves. The arithmetic is `TurntableMeasures.swift` (the land,
  the sleeve's layout, `RecordMotion`'s numbers, the clock), checked on
  Linux by `dev/turntable-test.sh`. One timeline turns what turns, at most
  20 frames a second (30 once the land itself turns, sketch H), only while
  the sleeve shows, the music plays, the app is active and the page is D2;
  at rest it is paused. `docs/BRAND.md` says why each.
- Home and radio: `HomeView()`, `MixDetailView(mix: Mix)`, `RadioView()`,
  `StationDetailView(station: Station)` (`Route.station(station)`): a
  station's page, what it would play before it plays. Every tile and card of
  a station opens it rather than playing, because the photographer asked to
  see what the radio made first: "Als je nu klikt op een tegel van radio
  begint er meteen van alles te spelen ipv dat je kan zien wat je van de
  playlist gemaakt hebt" (8 November 2026). A long press's Play Station,
  Your Station's Play on Home and Radio, and every "Start Radio" still play
  at once.
- Shell: `OnboardingView()`, `SearchView()`, `SettingsView()` (Home's toolbar
  opens it as a sheet).

## The environment

`JukeboxApp` puts these in the environment; read them with
`@Environment(X.self)`: `AppModel`, `Navigator`, `AppSettings`, `LibraryStore`,
`HistoryStore`, `AudioPlayer`, `RadioController`, `MixStore`, `OfflineStore`.
`AppModel.client` is the signed-in `JellyfinClient`. Offline (`OfflineStore.isOffline`)
only songs on the phone play: a list's row asks `player.refusesOffline(track)`
before it plays, and `TrackRow` dims what cannot play.

Starting things, from any screen:
- an album: `player.play(tracks, startingAt: i, context: QueueContext(.album(album.id), title: album.name))`
- shuffle: the same with `shuffled: true`
- a station: `radio.start(.artist(key: artist.key, name: artist.name, id: artist.id))`,
  `radio.start(.track(id))`, `radio.start(station)`
- a station's page: `navigator.open(.station(station))`; the page asks
  `radio.preview(station, randomSeed:)` for its first 25 songs (chosen as
  `begin` chooses, the session kept) and plays them with
  `radio.start(station, preview: picks, from: i)`, so Play plays the list
  shown. The seed is the station's draw, `radio.pageSeed(for:)`, the same
  each time its page opens while the app runs, so going back and opening
  it again shows the list seen before; New Picks draws another
  (`radio.drawPageSeed(for:)`). The lists are kept by station and draw, so
  one station's page on two tabs each plays its own. A newer library,
  graph or dial makes the kept list stale
  (`radio.previewInputs` moves and the page chooses again, with the same
  seed), and the page chooses again when another song plays, as the list
  leaves out the one playing; a stale or unknown list starts the station
  afresh.
- going somewhere: `navigator.open(.album(album))`
- Now Playing: `navigator.isNowPlayingPresented = true`

## Jellyfin

The test server (`dev/jellyfin-test-server.sh`) runs Jellyfin 12.4 (the
`latest` image, November 2026), user `test`/`test`, 23 made-up artists, 358
tracks in MP3, FLAC and M4A, genres in clusters. Requests carry
`Authorization: MediaBrowser Client="Jukebox", Device="…", DeviceId="…", Version="…", Token="…"`.
Times are ticks (10 000 000 a second); dates have seven fractional digits.

## Scrobbling

Jukebox does not scrobble to Last.fm itself: the server does — Jellyfin
with its Last.fm plugin, Navidrome with its own Last.fm link — from the
playback reports the app already sends (Jellyfin's start/progress/stopped;
Subsonic's scrobble). The photographer, 8 November 2026: "Laat scrobblen
lekker via de server lopen." One place for every client, and no song twice
on Last.fm. The Last.fm key in Settings is only for the radio's similar
artists and songs.

## Lyrics

The photographer, 8 November 2026, from the TestFlight build: "Kun je ook
lyrics toevoegen". Now Playing's Lyrics panel (`LyricsView`, through
`LyricsFinder`) asks the server first (`/Audio/{id}/Lyrics`). Most libraries
have none, so then, while Settings' Find Lyrics Online is on (the default),
it asks LRCLIB (lrclib.net), a free, open lyrics database without a key that
Feishin uses too: `/api/get` with title, artist, album and length, and on a
404 (or no answer in 8 s: it may look beyond LRCLIB's own database)
`/api/search`, taking the record of the same title and artist nearest in
length, synced first, never one more than 3 s off (another recording, whose
timed lines would drift) or without a length. Artists are whole names or one
of the record's credits ("Daft Punk, Pharrell Williams"), never a name that
only begins with ours ("Queen" is not "Queensrÿche"). Only the title (without
"feat."), the main artist, the album and the length are sent. Answers are
kept on disk (`LyricsCache`, about 1.2 kB a song): found for 90 days, not
found for 3. Nothing is asked while the panel is closed, and the song's
lookup is cancelled when the song changes or the panel closes; while it is
open, the next song is looked up too, once the playing song's answer is in.
`LRCLIBLiveTests` asks the real LRCLIB where it answers within 3 s (GitHub's
runners) or with `LRCLIB_LIVE=1`, and skips itself elsewhere.

## Usage counts

Anonymous counts of which screens and features are used go to the
photographer's own Aptabase (stats.numa.photo) through `Jukebox/App/Stats.swift`,
on unless Settings › Privacy turns them off ("alles tracken wat je mag zonder
cookie melding", 8 November 2026): a closed list of events with coarse
properties, never a title, an artist, a search or a server — `docs/STATS.md`.

## Navidrome and the other Subsonic servers

Asked for on 8 November 2026: "Moet eigenlijk ook voor navidrome en die
ander". `docs/SERVERS.md` is the design: `MusicServer`
(`JukeboxKit/Sources/JukeboxKit/Server/MusicServer.swift`, a CONTRACT), one
protocol for Jellyfin and Subsonic that the app moves to from
`JellyfinClient`, how the app finds which server is at an address, what the
keychain keeps, and the map from every call to both APIs, measured on
Jellyfin 12.4 and Navidrome 0.64.2. `dev/navidrome-test-server.sh` starts
Navidrome on the same made-up library (user test/test, port 4533).
