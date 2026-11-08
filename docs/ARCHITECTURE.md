# Jukebox: how it is built

Jukebox is the photographer's own music app for the iPhone and the iPad:
their Jellyfin server's music — artists, albums, songs, playlists — with
playlists the app makes up itself on Home and a radio that plays on from
anything. Asked for on 8 November 2026: "op de homepage wil ik dat de app zelf
leuke playlists verzint en of een goede radio functie heeft — ik vind vooral
de radiofunctie echt belangrijk". Design: Apple's HIG and native controls,
branded as a sibling of Numa (white accent, the eclipse, grey section labels).

## Layout

| Path | What |
|---|---|
| `JukeboxKit/` | Swift package, Foundation only, Swift 6 strict. Jellyfin and Last.fm clients, the library index, the radio, the mixes. Built and tested on Linux (`dev/kit-test.sh`) against a real Jellyfin (`dev/jellyfin-test-server.sh`). |
| `Jukebox/` | The SwiftUI app, iOS 26, Swift 5 mode with MainActor default isolation (project.yml). Compiled only on GitHub's macOS (`ci/app.sh`) — there is no Mac here, so Swift in `Jukebox/` is read twice before it is pushed. |
| `project.yml` | XcodeGen. Every file under `Jukebox/` is in the app; no .xcodeproj in git. |
| `ci/` | What `.github/workflows/ci.yml` runs. The workflow file itself is generic, because the Claude session may not push workflow files. |
| `dev/` | The test server, the made-up library, the kit tests, the icon. |

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
- **Numa's signatures, from `Theme.swift`.** `Theme.accent` (white in dark,
  #141414 in light) is the one accent; one filled button per screen
  (`.buttonStyle(.prominent)`), others `.secondary`; `Eyebrow` for small grey
  spaced labels; `SectionHeader` for shelves; `StationArtwork`/`JukeboxMark`
  for the eclipse. Spaces and radii from `Theme`.
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
| App: library | `Jukebox/Library/*` — LibraryStore and every library screen, AddToPlaylistSheet |
| App: player | `Jukebox/Player/*`, `Jukebox/Radio/RadioController.swift` — AudioPlayer, HistoryStore, Now Playing info, remote commands, audio session, playback reports, the radio's feeding |
| App: now playing | `Jukebox/NowPlaying/*` — MiniPlayer, NowPlayingView, QueueView, LyricsView, AirPlay and volume |
| App: home and radio | `Jukebox/Home/*`, `Jukebox/Radio/*` except RadioController — MixStore, HomeView, MixDetailView, RadioView |
| App: shell | `Jukebox/Settings/*`, `Jukebox/Search/*` — OnboardingView (sign in, Quick Connect), SettingsView, SearchView |

## The views each part must provide (the names others use)

`Navigator.swift`'s `routeDestinations()` and `JukeboxApp.swift` name these; each
must exist with exactly this initializer:

- Library: `LibraryView()`, `ArtistsView()`, `ArtistDetailView(artist: Artist)`,
  `AlbumsView()`, `AlbumDetailView(album: Album)`, `SongsView()`,
  `PlaylistsView()`, `PlaylistDetailView(playlist: Playlist)`, `GenresView()`,
  `GenreDetailView(genre: Genre)`, `FavoritesView()`, `RecentlyAddedView()`,
  `AddToPlaylistSheet(tracks: [Track])`.
- Now playing: `MiniPlayer()` (inside `tabViewBottomAccessory`; reads
  `@Environment(\.tabViewBottomAccessoryPlacement)` to draw inline or
  expanded), `NowPlayingView()` (in a fullScreenCover).
- Home and radio: `HomeView()`, `MixDetailView(mix: Mix)`, `RadioView()`.
- Shell: `OnboardingView()`, `SearchView()`, `SettingsView()` (Home's toolbar
  opens it as a sheet).

## The environment

`JukeboxApp` puts these in the environment; read them with
`@Environment(X.self)`: `AppModel`, `Navigator`, `AppSettings`, `LibraryStore`,
`HistoryStore`, `AudioPlayer`, `RadioController`, `MixStore`. `AppModel.client`
is the signed-in `JellyfinClient`.

Starting things, from any screen:
- an album: `player.play(tracks, startingAt: i, context: QueueContext(.album(album.id), title: album.name))`
- shuffle: the same with `shuffled: true`
- a station: `radio.start(.artist(key: artist.key, name: artist.name, id: artist.id))`,
  `radio.start(.track(id))`, `radio.start(station)`
- going somewhere: `navigator.open(.album(album))`
- Now Playing: `navigator.isNowPlayingPresented = true`

## Jellyfin

The test server (`dev/jellyfin-test-server.sh`) runs Jellyfin 12.4 (the
`latest` image, November 2026), user `test`/`test`, 23 made-up artists, 358
tracks in MP3, FLAC and M4A, genres in clusters. Requests carry
`Authorization: MediaBrowser Client="Jukebox", Device="…", DeviceId="…", Version="…", Token="…"`.
Times are ticks (10 000 000 a second); dates have seven fractional digits.
