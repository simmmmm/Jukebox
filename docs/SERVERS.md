# Servers: Jellyfin, Navidrome and the other Subsonic servers

The photographer, 8 November 2026: "Moet eigenlijk ook voor navidrome en die
ander" — Jukebox, made for their Jellyfin server, should also play from
Navidrome and the other servers that speak the Subsonic API (OpenSubsonic:
Navidrome, Gonic, Airsonic-Advanced, Ampache's Subsonic API, LMS), as Feishin,
their reference player, does.

This is the design of the layer between the app and a server, and the map
from each thing the app asks to Jellyfin's and Subsonic's requests. The
protocol is `JukeboxKit/Sources/JukeboxKit/Server/MusicServer.swift`
(CONTRACT); both servers are built and tested against it, the kit's half
done (9 November 2026), the app's move to it the next round's. Every number
below was measured on 8 and 9 November 2026 against the two test servers,
unless it says otherwise:

- Jellyfin 12.4.0 (`dev/jellyfin-test-server.sh`), the measurements in
  `JellyfinClient.swift`'s comments;
- Navidrome 0.64.2 (10114574), the `deluan/navidrome:latest` image of
  September 2026 (`dev/navidrome-test-server.sh`, new in this round), on
  the same made-up library: 23 artists, 54 albums, 358 tracks in MP3, FLAC
  and M4A, 5 to 8 seconds each, no lyrics, no ReplayGain tags, no artist
  images; Navidrome's Last.fm, Spotify, Deezer and ListenBrainz agents off,
  as the tests must not need the internet.

The OpenSubsonic specification was read at its commit c1fd43f (2 November
2026); Feishin's Subsonic code at 155e562 (3 November 2026).

## The layer

| Type | What it is |
|---|---|
| `MusicServer` | One signed-in session, Jellyfin or Subsonic: every call the app makes, server-neutral, async throws, in the kit's own models (`Track`, `Album`, `Artist`, `Playlist`, `Genre`, `Lyrics`, `SearchResults`). What `AppModel`, `LibraryStore`, `AudioPlayer`, `RadioController` and the screens hold instead of `JellyfinClient`. |
| `ServerSignIn` | Signing in to a server that has answered: user name and password. `APIKeySignIn` and `QuickConnectSignIn` refine it where the server offers them (`signIn as? any QuickConnectSignIn`), so the optional ways are types, not flags that can lie. |
| `MusicServers` | The entry points: `candidateAddresses(for:)`, `detect(_:)`, `signIn(to:)`, `open(_:)`. |
| `DetectedServer` | What answered at an address before signing in: kind, URL, id, name, version, Subsonic's API version, what it offers. |
| `ServerCredentials`, `ServerSecret` | The session as the keychain keeps it. Reads the old Jellyfin-only `Credentials` JSON. |
| `ServerKind`, `SubsonicFlavour` | `.jellyfin` or `.subsonic(flavour: .navidrome / .gonic / .airsonic / .ampache / .lms / .subsonic / .other(type))`. |
| `ServerCapability` | What a server can do beyond the library, as a set, so the app hides what it lacks. |
| `ItemRef`, `MixSeed`, `PlaybackEvent` | What the calls take where Subsonic needs more than an id: which kind of item a favourite is, what a mix starts from, which moment of a play is reported. |
| `MusicServerError` | Every server's errors as the app tells them apart. |

The servers, in `JukeboxKit/Sources/JukeboxKit/`:
- `Server/JellyfinServer.swift`: Jellyfin as a `MusicServer`, a thin wrapper
  around `JellyfinClient`, which stays as it is; it adds one thing, an entry
  id for each place of a song that is in a playlist twice (below);
- `Server/ServerAddress.swift`: the candidates and the detection;
- `Subsonic/`: `SubsonicClient` (the `MusicServer`), `SubsonicRequests`
  (the one connection every call goes through), `SubsonicDTO` (the answers'
  shapes, read leniently, and the mapping into the models), `SubsonicSignIn`,
  and an MD5 written out in Swift (`CryptoKit` is Apple's only; the kit is
  Foundation only and tested on Linux).

## Decisions

1. **One protocol for what the app uses, not for what servers can do.** The
   app sorts, filters and searches the library in memory (`LibraryIndex`),
   so `MusicServer` has no `AlbumQuery`/`TrackQuery`: it has "all of it"
   (`allTracks`, `allAlbums`, `allArtists`, `playlists`, `genres`), one item,
   an album's tracks, a playlist's entries and the calls only the server can
   answer. Each server pages as suits it: Jellyfin 2000 tracks a page, three
   at once (measured, `JellyfinClient.allTracks`); Subsonic one `search3`
   (below). `LibraryStore.allAlbums`/`allArtists`' paging moves into the
   servers.
2. **Jellyfin keeps its client.** `JellyfinServer` wraps `JellyfinClient`
   rather than `JellyfinClient` conforming: several of its methods have the
   protocol's names with other parameters (`setFavorite(_:itemID:)`,
   `lyrics(trackID:)`), and the wrapper is where `JellyfinError` becomes
   `MusicServerError`. The client, its tests and its measurements stay.
3. **Subsonic through the Subsonic API only**, also for Navidrome. Feishin
   uses Navidrome's own API for Navidrome (`/auth/login`, a JWT in
   `x-nd-authorization`, `/api/song` and `/api/album` with sorting and
   filtering on the server); Jukebox sorts and filters in memory, and one client for
   every Subsonic server is one set of answers to read and test. What
   Navidrome's API would add is not needed: `search3` gives every song in one
   request (25 ms for 358, below).
4. **Token authentication, made once.** `t = md5(password + salt)` with a
   random salt at sign-in, the pair kept in the keychain and sent with every
   call: never the password. One salt for the session because every image
   and stream URL carries it, and the image cache is keyed by URL
   (`ImagePipeline`: `NSCache<NSURL, …>` and `URLCache`); a fresh salt per
   request would make every cover a new download. Navidrome accepts the same
   salt on every call (every measurement here used one). Feishin does the
   same: a salt of 12 characters at sign-in, `u`, `s` and `t` kept as its
   credential, `userId` the user name.
5. **Server kind is found, not asked.** The person types an address; the
   app asks both ways at once and knows (below). No "Jellyfin or Subsonic?"
   picker.
6. **Capabilities, not flavours.** What the app shows depends on
   `ServerCapability`, from what the server says it has (Jellyfin's version
   and Quick Connect, OpenSubsonic's extensions, Subsonic's API version),
   never on "is this Navidrome". A Gonic that grows lyrics gets lyrics.
7. **Playlist entries are made up for Subsonic.** Subsonic has no entry ids
   (`updatePlaylist` removes by position); the kit makes one per place,
   "<songID>#<n>", and reads the playlist again before every change
   (below).
8. **One rule for when a play counts, the app's, on every server.** The
   player decides with `PlayOutcome` (not a skip: 30 s, or half of a short
   track); Jellyfin counts at the start report, Subsonic at `scrobble
   submission=true`, sent at that moment. Navidrome's own rule (more than
   half the track, measured) is not used: `reportPlayback` goes with
   `ignoreScrobble=true`, as Feishin sends it. So a skip counts nowhere and
   a play counts once on every server.
9. **Converted streams and downloads are MP3 on Subsonic.** Navidrome
   converts to Ogg Opus when only `maxBitRate` is given (measured), which
   AVPlayer cannot play. `format=mp3` is the one target every Subsonic
   server converts to; Navidrome's AAC is ADTS, which carries no length
   (below, "Downloads, measured").
10. **The keychain entry migrates in place.** `ServerCredentials` decodes
    the Jellyfin-only app's `Credentials` (tested,
    `ServerCredentialsTests`), so nobody is signed out by the update.

## What the app asks of a server

Every use of `JellyfinClient` and its types in `Jukebox/`, at the branch's
base (8 November 2026; other agents are changing the app in this round, so
lines may have moved). The app moved to `MusicServer` on 9 November 2026:
docs/ARCHITECTURE.md, "Navidrome and the other Subsonic servers", "In the
app", says where each part of it is used.

**The session** (`AppModel`, `Keychain`, `LibraryStore`, `SearchView`, `SettingsView`)

| Where | What | Becomes |
|---|---|---|
| AppModel.swift:25, 26 | `credentials: Credentials?`, `client: JellyfinClient?` | `ServerCredentials?`, `server: (any MusicServer)?` |
| AppModel.swift:28, 38 | `ClientIdentity(clientName:clientVersion:deviceName:deviceID:)` | unchanged (Subsonic's `c` is `clientName`) |
| AppModel.swift:59–60 | `client(for: URL) -> JellyfinClient(serverURL:identity:)` | `MusicServers.signIn(to:identity:)` |
| AppModel.swift:66, 74, 106–113 | `Keychain.loadCredentials()`, `signIn(_ credentials:)`, `JellyfinClient(credentials:identity:)`, `player.client =`, `radio.client =`, `library.open(client:credentials:)` | `MusicServers.open(_:identity:)`; the same three assignments |
| AppModel.swift:84, 103 | `Keychain.deleteCredentials()`, `client?.signOut()` | `server?.signOut()` |
| Keychain.swift:12, 27, 38 | `save(_: Credentials)`, `loadCredentials() -> Credentials?`, `JSONDecoder().decode(Credentials.self, …)` | `ServerCredentials` (reads the old entry) |
| LibraryStore.swift:43, 51, 61, 63 | `client`, `credentials`, `open(client:credentials:)`, `serverID`/`userID` compared | the same with `MusicServer` and `ServerCredentials` |
| LibraryStore.swift:352 | `serverName` (`credentials?.serverName`) | `credentials.serverName` |
| LibraryStore.swift:494–498 | `cacheURL(for:)` from `serverID` and `userID` | the same fields |
| SearchView.swift:41–60 | `app.credentials?.userID` keys the recent searches | the same field |
| SettingsView.swift:50–53, 78 | `serverName`, `userName`, `serverURL` shown | the same fields; also `kind.displayName` and `serverVersion` |

**Signing in** (`OnboardingView`)

| Where | What | Becomes |
|---|---|---|
| OnboardingView.swift:113 | `JellyfinClient.candidateAddresses(for:)` | `MusicServers.candidateAddresses(for:)` |
| :121–139 | per candidate `quickConnectEnabled()` and `publicInfo()` at once, `client.serverURL` | `MusicServers.detect(_:)` (it asks every candidate at once) |
| :150, 168 | `JellyfinError.invalidServerAddress`, `.transport` | `MusicServerError` |
| :190–191, 262, 279, 329, 397 | `ServerInfo` (`name`, `version`: "Jellyfin \(version)"), `offersQuickConnect` | `DetectedServer` (`kind.displayName` + `version`), `.quickConnect in capabilities` |
| :358 | `signIn(username:password:)` | `ServerSignIn.signIn(username:password:)` |
| :423, 433, 435 | `quickConnectStart()`, `quickConnectState(secret:)`, `signIn(quickConnectSecret:)` | `QuickConnectSignIn`, the same three |
| :464, 473 | `.unauthorized`, `.notFound` | `MusicServerError`, plus `.needsAPIKey` (an API key field) and `.passwordNeedsHTTPS` |

**The library** (`LibraryStore`, `AlbumsView`, `ArtistsView`, `PlaylistsView`)

| Where | What | Becomes |
|---|---|---|
| LibraryStore.swift:401 | `allTracks(progress:)` | `allTracks(progress:)` |
| :404, 408 | `playlists()`, `genres()` | the same |
| :440–452 | `albums(AlbumQuery(sort: .name, start:, limit: 1000))`, `artists(start:limit: 1000)` in pages | `allAlbums()`, `allArtists()` |
| :228–239 | `setFavorite(_:itemID:)` for a track, album or artist | `setFavorite(_:item: ItemRef)`: the store knows which (`index.trackPosition`, `albumPosition`, `artistPosition`) |
| :253–254 | `playlistTracks(playlistID:)` | the same |
| :266–267, 276–278 | `createPlaylist(name:trackIDs:)`, `addToPlaylist(playlistID:trackIDs:)` | the same |
| :289–292, 302–304 | `removeFromPlaylist(playlistID:entryIDs:)`, `movePlaylistEntry(playlistID:entryID:to:)`, from `track.playlistEntryID` | the same |
| :308–309 | `deletePlaylist(id:)` | the same |
| :253, 266, 276, 289, 302, 303, 308 | `throw JellyfinError.notSignedIn / .notFound` | `MusicServerError` |
| AlbumsView.swift:209–214 | `tracks(TrackQuery(albumID:))` before the library is in | `albumTracks(albumID:)` |
| ArtistsView.swift:274–275 | `similarArtists(artistID:limit: 20)` | the same; empty where the server has nothing |
| PlaylistsView.swift:382 | `track.playlistEntryID ?? track.id` as the row's id | unchanged ("<songID>#<n>" is unique too) |

**Playing** (`AudioPlayer`, `NowPlayingInfo`, `ArtworkView`, `NowPlayingParts`, `LyricsView`, `RadioController`, `AppSettings`, `SettingsView`)

| Where | What | Becomes |
|---|---|---|
| AudioPlayer.swift:102 | `client: JellyfinClient?` | `server: (any MusicServer)?` |
| :613–616 | `streamURL(trackID:quality:playSessionID:)` | `streamURL(for: Track, quality:playSessionID:)` |
| :634 | `track.normalizationGain` | unchanged; Subsonic fills it from `replayGain.trackGain` |
| :675–677 | `PlaybackReport(…)`, `reportStopped` | `report(.stopped, …)` |
| :937–952 | `reportStart`, held until the play is not a skip | `report(.played, …)`, the same moment; and `report(.nowPlaying, …)` when the entry begins |
| :956–963 | `reportProgress` (every 10 s, pause, resume, seek) | `report(.progress, …)` |
| NowPlayingInfo.swift:22, 78–80 | `client: JellyfinClient?`, `imageURL(_:maxPixelSize: 600)` | `artworkURL(_:maxPixelSize:)` |
| ArtworkView.swift:119–121 | `app.client`, `imageURL(_:maxPixelSize:)` | `app.server`, `artworkURL` |
| NowPlayingParts.swift:55–63 | the same at 240 px | the same |
| LyricsView.swift:61–67 | `lyrics(trackID:)` | `lyrics(for: Track)` |
| RadioController.swift:50, 527–531 | `client`, `instantMix(seedID:limit: 100)` | `instantMix(from: MixSeed, limit:)` |
| RadioController.swift:583–611 | `instantMixSeed(for:)` and `isJellyfinID` (a GUID check for made-up genre and mix ids) | the seed's kind says it: `MixSeed.genre(name:id:)` with `id` nil for a split genre; `isJellyfinID` goes |
| AppSettings.swift:13–47, SettingsView.swift:118–124 | `StreamQuality` (Wi-Fi and cellular) | unchanged |

Not used by the app today, in the protocol because the task and a large
library want them: `search`, `track(id:)`, `album(id:)`, `artist(id:)`,
`topSongs`. Strings that say "Jellyfin" and must say "your server" or the
kind's name in the app round: QueueView.swift:272, 274; LyricsView.swift:37;
SettingsView.swift:104, 113, 421; OnboardingView.swift:85, 170, 279, 337,
384, 496; SearchView.swift:272; ArtistsView.swift:42; AlbumsView.swift:42;
SongsView.swift:41; AddSongsSheet.swift:57; PlaylistsView.swift:73, 236;
LibraryView.swift:119; LibraryParts.swift:21, 79; MixDetailView.swift:87;
HomeParts.swift:73; StationDetailView.swift:108.

## Which server is at an address

**The addresses to try** (`MusicServers.candidateAddresses`): the address as
typed, normalized as `JellyfinAddress` does, and two more rules:
- Navidrome's web app is at "/app" ("http://nas:4533/app/#/album/all",
  whose "#…" is cut off already): a last path segment "/app" is cut off.
  Only the last: "/app/music" is a reverse proxy's path and stays. Gonic's
  web pages are "/admin/…": "/admin" and what follows is cut off, as
  Jellyfin's "/web" and what follows is now.
- The ports that mean plain http when no scheme is typed: Jellyfin's 8096,
  and now Navidrome's 4533, Gonic's 4747, Airsonic's 4040 and LMS's 5082
  (their documented defaults; Navidrome's measured).
- When no port and no "https://" were typed, the same host over http on
  8096, 4533, 4747, 4040 and 5082 follows the address as typed (Jellyfin's
  rule, extended: a fresh install listens on its own port only).

**Asking** (`MusicServers.detect`): every candidate at once, both ways at
once, 15 s each:
1. `GET {base}/System/Info/Public`. JSON with a non-empty `Id`: Jellyfin
   (`ServerName`, `Version`, `Id`; measured: `"ProductName":"Jellyfin
   Server","Version":"12.4.0"`). Then `GET /QuickConnect/Enabled`, as now.
2. `GET {base}/rest/ping.view?v=1.16.1&c=Jukebox&f=json`, no credentials.
   A `subsonic-response` object with `status` and `version` is a Subsonic
   server, whatever the status: unauthenticated, Navidrome answers
   `{"status":"failed","version":"1.16.1","type":"navidrome","serverVersion":"0.64.2 (10114574)","openSubsonic":true,"error":{"code":10,"message":"missing parameter: 'u'"}}`
   (HTTP 200); a server may answer 40 (wrong user), 30 (our `v` is newer
   than it knows: it still proved itself, and its `version` is what we send
   from then on) or ok. Without `f=json` Navidrome answers the same in XML;
   an answer starting `<subsonic-response` is a Subsonic server that does
   not speak JSON (before API 1.4.0) and gets "This server is too old for
   Jukebox".
3. For an OpenSubsonic server (`openSubsonic: true`):
   `GET {base}/rest/getOpenSubsonicExtensions.view?v=…&c=Jukebox&f=json`,
   which must answer without credentials (the spec; measured on Navidrome).
   Its list becomes capabilities (below).

Measured across: Jellyfin 12.4 answers `/rest/ping.view` with 404 and no
body; Navidrome answers `/System/Info/Public` with 302 to `/app/` and then
its web app's HTML. So each server answers only its own question, and if
both ever did, Jellyfin wins (its API gives more).

**Choosing**: the first candidate in order that proved to be a server wins;
a later one wins only once every earlier one has failed. So the address as
typed wins whenever it works, as now, but a fallback port no longer adds its
timeout to the wait: the longest wait is one 15 s timeout, not six.
Nothing proved: the first candidate's error, as now (`.transport` when
nothing answered, `.invalidServerAddress` when something did).

The `DetectedServer` of a Subsonic server: `id` is its URL (Subsonic servers
have no id; the caches are kept by server and user), `name` the host
(Subsonic servers have no name: "Signing in to nas.local · Navidrome
0.64.2"), `version` the `serverVersion` (or the API version), `apiVersion`
the ping's `version`.

## Signing in, and what the keychain keeps

**Jellyfin**: as now. POST /Users/AuthenticateByName or Quick Connect; the
access token is kept (`ServerSecret.jellyfinToken`).

**Subsonic**:
1. A salt of 16 random hex digits; `t = md5(password + salt)` in lower-case
   hex. `GET /rest/ping.view?u=&t=&s=&v=&c=Jukebox&f=json`.
2. ok: the session is `ServerSecret.subsonicToken(token: t, salt: s)`. Then
   `getUser?username=` once, to say at once when the user may not stream
   (`streamRole` false) rather than at the first song. The password is not
   kept anywhere.
3. 40 ("Wrong username or password", measured with a wrong token):
   `.unauthorized`, the sign-in screen's message as now.
4. 41 ("Token authentication not supported", servers that keep only a hash
   of the password) or 42 ("authentication mechanism not supported"):
   - the server lists `apiKeyAuthentication`: `.needsAPIKey(helpURL:)`; the
     screen asks for an API key and links the error's `helpUrl`. A key is
     preferred to keeping the password: it can be revoked, and a password is
     often the person's everywhere. `signIn(apiKey:)` pings with `apiKey`
     and no `u` (the spec: `u` with a key is error 43), then `tokenInfo`
     gives the user's name. Kept: `ServerSecret.subsonicAPIKey`.
   - otherwise the password itself, `p=enc:<hex>`, but only over https or
     to a home-network address (`JellyfinAddress.isHomeNetwork`): it goes
     with every request, in every stream URL. Plain http to a public host:
     `.passwordNeedsHTTPS`. Kept: `ServerSecret.subsonicPassword`, the one
     case where the keychain holds a password, because the server takes
     nothing else.
5. A server older than API 1.13.0 (no tokens) is case 4 without the key.

Measured on Navidrome 0.64.2: token ok; `p=enc:74657374` ("test") ok; a
wrong token 40; an `apiKey` 10 "missing parameter: 'u'" (it does not list
`apiKeyAuthentication`); `apiKey` with `u` 40; no `v` or no `c` 10;
`v=1.8.0` ok.

**What the keychain keeps** (`ServerCredentials`, JSON, one generic
password item as now, readable after first unlock): kind, server URL, id,
name and version, Subsonic's API version, user id and name, the secret, and
the capabilities as last seen (so a launch without the network shows the
same screens). For Subsonic the secret is the token and salt, an API key, or
— only in case 4 — the password. The token and salt are as good as the
password to that server (like Jellyfin's token), but they are not the
password, and unlike Jellyfin's token Subsonic cannot revoke them: they hold
until the password changes. Signing out forgets them; Subsonic has no
sign-out request.

## Talking Subsonic

Every request: `GET {base}/rest/{endpoint}.view` with `u` (or `apiKey`),
`t`, `s` (or `p`), `v` (the lower of 1.16.1 and the server's), `c=Jukebox`
and `f=json`; the answer is `{"subsonic-response": {status, version, type,
serverVersion, openSubsonic, error?: {code, message, helpUrl?}, …}}`, HTTP
200 even for errors (measured: an unknown song is 200 with error 70). The
query is escaped as `JellyfinClient.url` escapes it (only A–Z a–z 0–9 - . _
~ stay), and dates are read with `JellyfinDate`, which takes Navidrome's nine
fractional digits ("2026-11-08T10:14:28.62878675Z").

Long lists of ids (a playlist's songs): up to 100 ids and positions go in
one GET; more go in one form POST (`application/x-www-form-urlencoded`,
everything in the body, the credentials too) where the server lists
`formPost` — asked only then, 2 ms. Navidrome lists it: a playlist of all
358 songs in one POST of 10.8 kB, 25–31 ms (measured; Navidrome itself also
took them in one GET of 10.9 kB, but a reverse proxy in front answers 414
past its 8 kB request line, nginx's default). Without `formPost`, 100 a
request, as JellyfinClient does: 100 `&songId=` with Navidrome's
22-character ids are 3 kB.

### Errors

| Subsonic | Meaning | `MusicServerError` |
|---|---|---|
| 0 | generic | `.server(status: 0, message:)` |
| 10 | a parameter missing | `.server` (a bug of ours) |
| 20, 30 | the API versions do not fit | `.server`, "This server is too old/new for Jukebox" |
| 40 | wrong user or password | `.unauthorized` |
| 41, 42 | tokens (or this way) not supported | `.needsAPIKey` or the password (signing in) |
| 43 | conflicting ways of signing in | `.server` (a bug of ours) |
| 44 | invalid API key | `.unauthorized` |
| 50 | not allowed for this user | `.notAllowed` |
| 70 | not found | `.notFound` |
| HTTP 404 | no such endpoint (measured: `getSonicSimilarTracks` on Navidrome, 404, empty body) | `.unsupported` |
| HTTP 401/403 | a reverse proxy in front | `.unauthorized` / `.notAllowed` |
| not JSON | a web page | `.decoding`; at detection, not a server |

Jellyfin's become `MusicServerError` one for one (`init(_: JellyfinError)`,
tested), with 403 as `.notAllowed`.

## The map

Jellyfin's side is `JellyfinClient` as it is (its comments have the
measurements). "Navidrome" is what 0.64.2 answered; "otherwise" is what the
app does where a Subsonic server lacks it.

### Who

| Member | Jellyfin | Subsonic |
|---|---|---|
| `kind`, `credentials` | from sign-in | from sign-in |
| `capabilities` | `ServerCapability.jellyfin` | from the API version and the extensions (below) |
| `currentCapabilities()` | `/System/Info/Public` (version) | `ping` + `getOpenSubsonicExtensions` |
| `signOut()` | POST /Sessions/Logout | none: the keychain forgets |

### The library

| Member | Jellyfin | Subsonic, and what it answers |
|---|---|---|
| `allTracks(progress:)` | GET /Items `IncludeItemTypes=Audio`, 2000 a page, three at once | `search3?query=&artistCount=0&albumCount=0&songCount=1000&songOffset=` until a short page → `searchResult3.song[]` (Child, below). An empty query must list everything (the OpenSubsonic spec, for offline sync); Navidrome: 358 songs in one answer, 382 kB, 17–26 ms (6 runs), pages of 100 at offsets 0/300/358 gave 100/58/0, `songCount=5000` gave 358. Total for `progress`: the sum of the albums' `songCount` (358, right). Otherwise (a server whose empty search gives fewer songs than that sum): walk the albums, `getAlbum` each, four at once — 54 albums 124–160 ms one after another, 140–144 ms four at once on localhost; each costs a round trip on a phone. |
| `allAlbums()` | GET /Items `IncludeItemTypes=MusicAlbum`, 1000 a page | `getAlbumList2?type=alphabeticalByName&size=500&offset=` until a short page (500 is the spec's maximum; Navidrome took 1000 for its 54) → `albumList2.album[]` (AlbumID3). 35 kB, 4–6 ms. |
| `allArtists()` | GET /Artists/AlbumArtists, 1000 a page | `getArtists` (not paged) → `artists.index[].artist[]` (ArtistID3), `ignoredArticles`. Navidrome: the 23 album artists, each with `roles` ["albumartist","artist","maincredit"], 4 kB, 2 ms. (The test library's guests are all album artists elsewhere, so whether Navidrome lists a guest-only artist is not measured here.) |
| `playlists()` | GET /Items `IncludeItemTypes=Playlist` | `getPlaylists` → `playlists.playlist[]`: `id, name, comment, owner, public, songCount, duration, created, changed, coverArt ("pl-<id>"), readonly`. |
| `genres()` | GET /MusicGenres | `getGenres` → `genres.genre[]`: `value, songCount, albumCount`, no id: the id is the name. Navidrome splits tags itself: 23 genres ("Electronic" 74 songs, 11 albums), where Jellyfin lists 19 of 23 joined ("Rock; Shoegaze"). |

### One item

| Member | Jellyfin | Subsonic |
|---|---|---|
| `track(id:)` | /Items?Ids= | `getSong?id=` → `song`; unknown: error 70 "Song not found" (measured) → `.notFound` |
| `album(id:)` | /Items?Ids= | `getAlbum?id=` → `album` (AlbumID3 with `song[]`) |
| `artist(id:)` | /Items?Ids= | `getArtist?id=` → `artist` (ArtistID3 with `album[]`); the biography is `getArtistInfo2`'s (below) |
| `albumTracks(albumID:)` | /Items?ParentId= in ParentIndexNumber, IndexNumber, SortName | `getAlbum?id=` → `album.song[]`, in disc and track order (measured on "Dust Parades": 1-1 … 1-7) |
| `search(_:limit:)` | four /Items and /Artists requests at once | `search3?query=&artistCount=&albumCount=&songCount=` → `searchResult3 {artist[], album[], song[]}`; playlists: `getPlaylists` filtered by name in the kit (Subsonic does not search playlists). Navidrome "night": the artist Nightdrive, 10 albums (some by Nightdrive without "night" in the name), 20 songs. |

### Changes

| Member | Jellyfin | Subsonic |
|---|---|---|
| `setFavorite(_:item:)` | POST/DELETE /UserFavoriteItems/{id} | `star` / `unstar` with `id=` (a song), `albumId=` or `artistId=` by `ItemRef`. Navidrome took all three, and `id=` for an album or an artist too; an unknown id is ok (logged "Cannot star/unstar unknown id"). The item's `starred` date is the favourite (`getStarred2` lists them; not needed, the items say it). |
| `playlistTracks(playlistID:)` | GET /Playlists/{id}/Items, `PlaylistItemId` | `getPlaylist?id=` → `playlist.entry[]` (Child) in order, duplicates kept; entry ids made as below |
| `createPlaylist(name:trackIDs:)` | POST /Playlists (ids in the body) | `createPlaylist?name=&songId=…` → `playlist.id` (API 1.14.0+ answers with the playlist; measured; before, the newest playlist of that name). More than 100: one form POST with `formPost`, else the first 100 and then `updatePlaylist` 100 at a time. A playlist with no songs: `name` alone (measured ok, `songCount` 0). An unknown song id is dropped silently (measured: ok, `songCount` 0). |
| `addToPlaylist(playlistID:trackIDs:)` | POST /Playlists/{id}/Items?ids= | `updatePlaylist?playlistId=&songIdToAdd=…`, at the end, in order, duplicates kept (measured A B C A + D A → A B C A D A) |
| `removeFromPlaylist(playlistID:entryIDs:)` | DELETE /Playlists/{id}/Items?entryIds= | `getPlaylist`, then `updatePlaylist?playlistId=&songIndexToRemove=…` with the entries' positions there. All positions count in the playlist before the change (measured: removing 0 and 2 of A B C A D A left B A D A); a position past the end is ignored (measured: ok, nothing removed). |
| `movePlaylistEntry(playlistID:entryID:to:)` | POST /Playlists/{id}/Items/{entry}/Move/{index}; for a place of a song that repeats, below | `getPlaylist`, the move made in the list, then one `updatePlaylist` that removes every place from the first the move touches and adds the songs from there on in the new order. Measured: removals and additions in one request apply the removals first, by the positions before the change (A B C D E, remove 1 and 3, add X: A C E X); a server that adds first ends the same, as the additions go after every place removed. A move near the end of a long playlist sends a few songs. |
| `deletePlaylist(id:)` | DELETE /Items/{id} | `deletePlaylist?id=`; unknown: 70 (measured) |

### What only the server knows

| Member | Jellyfin | Subsonic | Otherwise |
|---|---|---|---|
| `similarArtists(artistID:limit:)` | GET /Items/{id}/Similar | `getArtistInfo2?id=&count=&includeNotPresent=false` → `artistInfo2.similarArtist[]` (ArtistID3), also `biography`, `smallImageUrl`… From Last.fm on the server: Navidrome without its agents answers `{}` (measured, 4 ms). | empty: the artist page has the radio's own graph, as with Jellyfin's thin answers |
| `instantMix(from:limit:)` | GET /Items/{seed}/InstantMix | `.track`, `.album`: `getSimilarSongs?id=&count=` (it takes a song, album or artist id); `.artist`: `getSimilarSongs2?id=&count=`; `.playlist`: its first song's `getSimilarSongs`; `.genre`: `getRandomSongs?genre=&size=` (the name). → `similarSongs.song[]` / `similarSongs2.song[]` / `randomSongs.song[]`. Navidrome without agents mixes by genre: a jazz song's 20 were all jazz (Miles Ahead Quartet 10, Saskia de Wit 5, the seed's Blue Room Trio 5), an electronic artist's 20 were electronic 14 and pop 6; 12–34 ms. | empty: the radio's own picks carry the station, as now (`(try? …) ?? []`) |
| `topSongs(of:limit:)` | none | `getTopSongs?id=&count=` where `topSongsByArtistId` is listed (Navidrome lists it), else `?artist=<name>` → `topSongs.song[]`. From Last.fm: Navidrome without agents answers `{}` (measured both ways). | the app's own Last.fm, as now, or the listener's most played |
| `lyrics(for:)` | GET /Audio/{id}/Lyrics | with `songLyrics`: `getLyricsBySongId?id=` → `lyricsList.structuredLyrics[]`: `lang, synced, offset (ms; positive: sooner), displayArtist, displayTitle, line[] {start (ms, synced only), value}`; the synced one first, then the first; a line starts at `(start − offset) / 1000` s. Without it: `getLyrics?artist=&title=` → `lyrics.value`, plain text split into lines. None: Navidrome answers `lyricsList: {}` and `lyrics: {value: ""}` (measured) → nil; an unknown id 70. | "No lyrics for this song" |

### Playing

| Member | Jellyfin | Subsonic |
|---|---|---|
| `streamURL(for:quality:playSessionID:)` | /Audio/{id}/universal, AAC over HLS when capped | `stream?id=` and the credentials. `.original`: `format=raw`, the file as it is (the API's "no conversion", 1.9.0+: without a format a server converts by its player settings, which Airsonic's are by default for FLAC; Navidrome sends the file either way) — unless its format is one AVPlayer cannot play (Ogg, Opus, WMA, APE, WavPack, DSD, by `Track.container`, Subsonic's `suffix`), then MP3 at 320. Capped: `maxBitRate=<kbit/s>&format=mp3` (320, 256, 128). `playSessionID` is not sent: Subsonic has no play sessions. |
| `downloadURL(for:quality:)` | JellyfinClient.downloadURL (docs/OFFLINE.md) | `.original`: `download?id=`, the file byte for byte (MP3 at 320 for what AVPlayer cannot play); `.high`, `.normal`: `stream?id=&maxBitRate=256` / `128` with `format=mp3`. Below. |
| `downloadsAllowed()` | /Users/Me's Policy.EnableContentDownloading | `getUser?username=` → `downloadRole`; true when absent or without getUser (404) |
| `artworkURL(_:maxPixelSize:)` | /Items/{id}/Images/Primary?fillWidth=&fillHeight=&tag= | `getCoverArt?id=<artwork.tag ?? artwork.itemID>&size=<px>` and the credentials (it needs them: without, error 10, measured) |
| `report(_:_:)` | below | below |

### Streaming, measured

Navidrome 0.64.2 with its default conversions, one file of each kind (`file`
read what came):

| Asked | MP3, 129 kbit/s | FLAC, 100 kbit/s | M4A, 126 kbit/s |
|---|---|---|---|
| nothing | the file, audio/mpeg, Content-Length, Accept-Ranges | the file, audio/flac | the file, audio/mp4 |
| `maxBitRate=128` | **Ogg Opus**, audio/ogg | the file (under the cap) | the file (under the cap) |
| `maxBitRate=64` | Ogg Opus | Ogg Opus | Ogg Opus |
| `maxBitRate=128&format=mp3` | MP3, audio/mpeg | MP3 | MP3 |
| `maxBitRate=128&format=aac` | AAC in ADTS, audio/aac | AAC | AAC |
| `format=raw&maxBitRate=64` | the file | the file | the file |
| `maxBitRate=320` | the file | the file | the file |

So Navidrome, like Jellyfin, sends the file when it is under the cap, and
converts only above it; but its own choice is Ogg Opus, which AVPlayer
cannot play: Jukebox always says `format=mp3` with a cap. AAC came out
right on Navidrome too, but MP3 is the format every Subsonic server
converts to (Navidrome's, Gonic's, Airsonic's and LMS's documented
conversions all have it; only Navidrome's is measured here), and at
128–320 kbit/s the difference does not show on a phone.

A converted stream has no Content-Length and no Accept-Ranges (measured).
`estimateContentLength=true` gives a Content-Length, but a guess: 49 397
told, 48 499 sent (MP3 at 64 kbit/s), and AVPlayer waits for what it was
told — so it is not asked for. Seeking in a converted stream is the player
round's to measure on a phone; where the server lists `transcodeOffset`
(Navidrome does) a stream can start part-way (`timeOffset=` seconds,
measured: half the bytes at 3 s of 6), which is the fallback if AVPlayer
cannot seek in it. A second request for the same conversion answered a
Range request with 206 (Navidrome keeps conversions for a while). An
unknown id is 200 with a JSON error (application/json), not audio:
AVPlayer fails the item, as for any bad URL.

### Downloads, measured

Navidrome 0.64.2, 9 November 2026, curl with no header (as a background
download task fetches), one mono file of each kind: MP3 129 kbit/s 97 196
bytes, FLAC 97 kbit/s 69 347, M4A (AAC) 126 kbit/s 80 892; `file` and
`ffprobe` read what came.

| Asked | MP3 | FLAC | M4A |
|---|---|---|---|
| `download` | the file byte for byte, audio/mpeg, Content-Length, Accept-Ranges: bytes | the file, audio/flac | the file, audio/mp4 |
| `stream` `format=mp3&maxBitRate=256` (`.high`) | the file (under the cap) | MP3 256, 161 541 bytes | MP3 **128**, 81 065 (Navidrome caps a lossy file's conversion at its own rate) |
| `format=mp3&maxBitRate=128` (`.normal`) | MP3 128, 96 779 bytes (129 is over the cap) | MP3 128, 80 875 | MP3 128, 81 065 |
| `format=aac&maxBitRate=256` | ADTS AAC, audio/aac; ffprobe: 6.42 s for 6.03 | ADTS; 4.96 s for 5.00 | ADTS; 5.41 s for 5.00 |
| `format=m4a&maxBitRate=256` | **Ogg Opus**, audio/ogg | **Ogg Opus** | the file (no m4a conversion: Navidrome sends it as it is) |
| `format=raw` | the file | the file | the file |

Every MP3 conversion: 200 audio/mpeg, CBR, a length ffprobe reads within
0.05 s, chunked with no Content-Length (no total for progress, not
resumable) — except a conversion Navidrome has made before, which comes
from its cache with a Content-Length (seen in the live tests). So `.high`
and `.normal` are MP3: AVPlayer plays it from a file, every Subsonic server
converts to it, and its length is right; ADTS says nothing of its length
(ffprobe was 8% off, a scrubber would be too), and not every server has
AAC. (These sine tones are smaller as FLAC than as any MP3; a real FLAC is
800–1000 kbit/s, and an AAC of 256 at `.high` comes as MP3 256, one
generation more, the same size.) `OfflineFile.fileName` names each by its
Content-Type: mp3, flac, m4a.

Downloads turned off (`ND_ENABLEDOWNLOADS=false`, a second Navidrome):
`getUser`'s `downloadRole` false; `download` 200 with a JSON error 50
"downloads are disabled"; `stream` converts as before — so it is
`downloadsAllowed()` that keeps to what the admin said, as on Jellyfin. An
unknown id: 200, application/json, error 70; no credentials: error 10.
Every Subsonic error is HTTP 200 with JSON: **the app's downloader must
not keep an answer whose Content-Type is not audio** (OfflineDownloader
keeps any 2xx today, and would save the JSON as "<id>.m4a").

`getUser` (Navidrome 0.64.2, the test user, its admin): `streamRole` and
`downloadRole` true, `playlistRole` **false** — and it makes playlists all
the same, so no other role is read as a rule.

OpenSubsonic's `transcoding` extension (`getTranscodeDecision`, a POST with
what the player can play) would let the server choose; Navidrome lists it.
Not used now: `format=mp3` works on every server; worth a look once the
player plays from Subsonic.

### Artwork, measured

| Cover id (Navidrome) | Answer |
|---|---|
| an album's, `al-<id>_<hash>` | image/jpeg, `Cache-Control: public, max-age=31536000, immutable` (the hash changes with the image, as Jellyfin's tag) |
| a song's, `dc-<albumId>:1` (the disc's cover) | image/jpeg, `public, no-cache` with an ETag: revalidated, 304 |
| a playlist's, `pl-<id>` | image/png, a mosaic, 599 × 599 unscaled |
| an artist's, `ar-<id>` (no image in the library) | image/webp, `no-store`: a placeholder. `getArtists` gives no `coverArt` for these artists (measured), so `Artist.imageTag` is nil and the app draws initials, as for Jellyfin. |
| an album's plain id | the album's cover, `no-cache` |
| unknown | 200, application/json, an error: `ImagePipeline` reads no image from it (`UIImage(data:)` is nil) and draws the placeholder |

`size=300` scales to 300 on the longer side.

### Playback reports

The player's moments stay as they are (`AudioPlayer`); `PlaybackEvent` names
them:

| Event | When (AudioPlayer) | Jellyfin | Subsonic with `playbackReport` | Subsonic without |
|---|---|---|---|---|
| `.nowPlaying` | the entry begins (new) | nothing: its start report counts a play | `reportPlayback?mediaId=&mediaType=song&state=starting&positionMs=&ignoreScrobble=true`, then `state=playing` | `scrobble?id=&submission=false` |
| `.played` | heard long enough to count (`reportStartIfNeeded`, PlayOutcome not `.skipped`) | POST /Sessions/Playing | `scrobble?id=&submission=true&time=<now − position, ms>` | the same |
| `.progress` | every 10 s, pause, resume, seek; only after `.played` | POST /Sessions/Playing/Progress | `reportPlayback` `state=playing` or `paused`, `positionMs`, `ignoreScrobble=true` | on resume, `submission=false` again; else nothing |
| `.stopped` | the entry stops being current; only after `.played` | POST /Sessions/Playing/Stopped | `reportPlayback` `state=stopped`, `ignoreScrobble=true` | nothing |

Measured on Navidrome 0.64.2, a fresh song for each case (5–8 s long):
- `scrobble submission=false`: play count 0, the song in `getNowPlaying`
  (`minutesAgo` 0, `playerName` the `c`, and with `playbackReport` also
  `state`, `positionMs`, `playbackRate`);
- `submission=true`: 1, `played` set to that minute; twice: 2;
- `reportPlayback` starting, playing, stopped at 1 s: 0;
- stopped at 30%, 45%, 49%, 50% of the track: 0; at 55%, 70%, 90%, and at
  the end: 1 — Navidrome counts when more than half was heard, by the
  reported position (stopped at the end at once, without the time passing,
  counted), Last.fm's rule; whether 4 minutes also counts could not be
  measured on 8-second tracks;
- stopped at the end without a start: 1; two plays to the end: 2;
- paused at 2 s: `getNowPlaying` shows `state: paused, positionMs: 2000`
  four seconds later; 0;
- everything with `ignoreScrobble=true`, to the end: 0;
- starting and playing with `ignoreScrobble=true`, then `scrobble
  submission=true`, then stopped at the end with `ignoreScrobble=true`: 1,
  and the album's `playCount` 1 and `played` set. Exactly once.

So `ignoreScrobble=true` with our own `scrobble` counts every play exactly
once, at the moment the app decides, which is what Feishin sends too
(`reportPlayback` with `ignoreScrobble: true`, starting then playing at a
start; `scrobble submission` for the count). On Jellyfin the play counts at
the start report (measured on 12.4): the same moment. The difference from
Navidrome's own rule (more than half): a play heard for 31 s of a
four-minute song counts in Jukebox and would not in Navidrome's; one rule
for the radio's taste on every server outweighs it, and Jellyfin counts it
too. A server that also scrobbles to Last.fm or ListenBrainz (Navidrome
can) forwards what Jukebox counts: if the photographer scrobbles there and
wants Last.fm's own rule, `.played` for Subsonic can move to "half or 4
minutes" — a question for them, not decided here.

`PlaybackReport` stays as it is; Subsonic does not use `playSessionID`.

## Playlist entries

Subsonic's `getPlaylist` lists songs, not entries, and `updatePlaylist`
removes by position. A position is not an identity: after a removal or a
move, every later position is another song's. So:
- **The id**: `playlistTracks` gives each place "<songID>#<n>", n counting
  that song's earlier places in the list from 0 (A B A → "A#0", "B#0",
  "A#1"). It holds when other songs move or go; it is unique, so
  `PlaylistsView`'s rows need no count of their own.
- **A change** (`removeFromPlaylist`, `movePlaylistEntry`) reads the
  playlist again first and finds each entry there: the n-th place of its
  song, or its last place if there are fewer now (the list was changed
  elsewhere: removing "A#1" when only one A is left removes that A), or
  nothing (it is gone: skipped, as Jellyfin skips an unknown entry id).
- **Removing** sends the positions found, all at once (they count in the
  list before the change, measured).
- **Moving** writes again only the part of the list the move changes
  (above, the map). `index` is the place the entry ends up in, as on
  Jellyfin (measured on 12.4: A to 2 in A B C D gives B C A D; every move
  in a list of six checked against that rule, SubsonicMappingTests). A
  change made on another device between the read and the write is
  overwritten; a playlist is edited by one person at a time, and the read
  is milliseconds before the write.
- **A lost request loses no song.** In one request where it fits; else, on
  a server without `formPost`, the additions go first, then the removals,
  highest first: a request lost on the way leaves a song twice, never one
  gone (tested by failing each request of a move in turn). The earlier
  version wrote a move as the whole list again, the first 100 songs by
  `createPlaylist?playlistId=` and then the rest: a second request lost
  lost every song after the hundredth.

**Jellyfin**, found by the contract test (ServerContractTests): 12.4's
`PlaylistItemId` is the song's own id, so a song twice in a playlist has
one entry id for both places (measured: A B A gave A, B, A). Removing it
removes every place (A B A C A, remove A: B C), and a move moves the first,
and not by its rule (A B A C A, A to 3: B A A C A). So `JellyfinServer`
gives the places of such a playlist "<id>#<n>", as Subsonic's are made,
and changes one place by removing the song (every place, one DELETE) and
adding it back at the places it keeps, in order from the start, with
`POST /Playlists/{id}/Items?ids=&position=` (measured to insert there and
to keep it: `GET /Playlists/{id}`'s `ItemIds` agreed). Not atomic, as
Jellyfin has no call that is: a request lost after the DELETE leaves that
song's places out, never another song's. `POST /Playlists/{id}` with `Ids`
would write the whole list at once, but on 12.4 the items then showed the
new order while the playlist kept the old one, and the next change went on
from the old: not used. A playlist where no song repeats keeps Jellyfin's
own ids and calls, as before.

## The models, from Subsonic's answers

The models were server-neutral in shape already; the mapping
(`SubsonicDTO.swift`, tested on Navidrome's own answers in
SubsonicMappingTests, and on the live server):

**Track** ← `Child` (`search3`, `getSong`, `getAlbum.song`, `getPlaylist.entry`, the mixes)

| Track | Subsonic | Note |
|---|---|---|
| `id` | `id` | |
| `name` | `title` | |
| `albumID`, `albumName` | `albumId`, `album` | |
| `artists` | `artists[] {id, name}` (OpenSubsonic), else `[artistId, artist]` | Navidrome splits a joined tag: "Amsterdam Strings; Clara Venn" is `artists` [Amsterdam Strings, Clara Venn] with `artist` and `displayArtist` the joined string (92 of 358 tracks have two or more, as Jellyfin's 92 joined names). LibrarySnapshot's split leaves split names as they are. |
| `albumArtist` | `albumArtists[0]` (OpenSubsonic), else the album's `artistId`/`artist` | without OpenSubsonic, `allTracks` takes it from `allAlbums` by `albumId` |
| `genres` | `genres[].name` (OpenSubsonic), else `[genre]` | 294 of 358 have two or more (Jellyfin's 294 joined) |
| `year`, `trackNumber`, `discNumber` | `year`, `track`, `discNumber` | |
| `duration` | `duration` | whole seconds (Jellyfin's ticks were exact) |
| `imageTag` | `coverArt` | the getCoverArt id ("dc-<albumId>:1" on Navidrome: one per disc, shared by its songs) |
| `albumImageTag` | nil | `artwork` falls back to the album only without `imageTag` |
| `isFavorite` | `starred` present | a date |
| `playCount` | `playCount` | absent when 0 (measured) |
| `lastPlayed` | `played` (OpenSubsonic) | absent before the first play; without it nil, and the taste weighs play counts at 0.6 |
| `dateAdded` | `created` | |
| `normalizationGain` | `replayGain.trackGain` (OpenSubsonic, dB) | the same reference as Jellyfin's (−18 LUFS, ReplayGain 2.0), and the player only ever plays softer; Navidrome gives `replayGain: {}` for files without the tags (measured) |
| `playlistEntryID` | made: "<songID>#<n>" | playlists only |

**Album** ← `AlbumID3`: `id`, `name`, `artists[]` (else `[artistId, artist]`),
`year`, `genres[].name` (else `[genre]`), `coverArt` → `imageTag`,
`songCount` → `trackCount`, `duration`, `starred` → `isFavorite`, `created`
→ `dateAdded`, `playCount`, `played` → `lastPlayed`.

**Artist** ← `ArtistID3`: `id`, `name`, `coverArt` → `imageTag` (absent
without an image, measured), `starred`, `albumCount`; no `genres` (the
snapshot has them from the tracks), no `songCount`, no `overview` (the
biography is `getArtistInfo2`'s, Last.fm's on the server; the artist page
can ask for it).

**Playlist** ← `playlist`: `id`, `name`, `coverArt` → `imageTag`,
`songCount` → `trackCount`, `duration`, `created` → `dateAdded`.

**Genre** ← `genre`: `value` → `id` and `name`, `songCount`, `albumCount`.

In the models since the first round (Models.swift):
- `Track.container: String?` — Subsonic's `suffix` (Jellyfin leaves it nil:
  its universal URL lists what the player plays and Jellyfin decides) — so
  `.original` asks for a conversion of a file AVPlayer cannot play, on
  Subsonic, where nothing converts it otherwise.
- `Playlist.isReadOnly: Bool` — OpenSubsonic's `readonly` (Navidrome:
  false for one's own, measured), else Subsonic's `owner` ≠ the user — so
  Edit is not offered where the server would answer 50. False on Jellyfin.
- The comments say "the server", with Subsonic's field beside Jellyfin's.

## Capabilities

| Capability | Jellyfin | Subsonic: when | Navidrome 0.64.2 (measured) | Without it, the app |
|---|---|---|---|---|
| `quickConnect` | /QuickConnect/Enabled true (the 12.4 test server: true) | never | — | no Quick Connect button |
| `apiKeySignIn` | never | `apiKeyAuthentication` listed | not listed | password only |
| `instantMix` | always | API 1.11.0+ | yes, by genre without agents | the radio's own picks |
| `similarArtists` | always | API 1.11.0+ | yes, but `{}` without agents | the radio's graph only |
| `topSongs` | never | API 1.13.0+ (by id with `topSongsByArtistId`) | yes (both), `{}` without agents | Last.fm, or the listener's most played |
| `lyrics` | 10.9+ | always (`getLyrics`, API 1.2.0) | yes | no lyrics button |
| `syncedLyrics` | 10.9+ | `songLyrics` listed | `songLyrics` 1, 2 | plain lines |
| `playlistReorder` | always | API 1.8.0+ (`updatePlaylist`'s removals and additions) | yes | no move handles |
| `replayGain` | 10.9+ | OpenSubsonic | yes | Normalize Volume off, with a footnote |
| `playbackTimeline` | always | `playbackReport` listed | listed | `scrobble` only |
| `lastPlayed` | always | OpenSubsonic (`played`) | yes | taste at 0.6, Recently Played from this device |
| `transcodeOffset` | never (HLS seeks) | `transcodeOffset` listed | listed | (player round) |

Navidrome 0.64.2's `getOpenSubsonicExtensions`, without credentials:
`transcodeOffset` 1, `formPost` 1, `songLyrics` 1 2, `indexBasedQueue` 1,
`transcoding` 1, `playbackReport` 1, `topSongsByArtistId` 1. Unused here:
`indexBasedQueue` (the play queue kept on the server), `transcoding`
(above), and `sonicSimilarity` (`getSonicSimilarTracks`, not on Navidrome:
404) — the last is worth adding to `instantMix` where a server lists it.

The rest of the library works the same on every server. Where a Subsonic
server lacks a call the protocol has no capability for: `search3` with an
empty query that lists fewer songs than the albums hold — the albums are
walked; no `formPost` — 100 ids a request; no `getOpenSubsonicExtensions`
(not OpenSubsonic) — no extensions.

## Measuring

`dev/navidrome-test-server.sh` starts Navidrome on the Docker network
`jukebox` (`http://navidrome:4533` from the kit's tests,
`http://localhost:4533` from here) on Jellyfin's made-up library, read-only,
makes the user test/test through `/auth/createAdmin` (Navidrome's own API:
a fresh server has no user), and waits for the scan (`getScanStatus`, an
empty `search3`, the albums and artists unchanged for one more look: 358 of
358 in 6 s from a fresh database, 2.4 s again). A look that fails is one
look; a scan that has not settled in 4 minutes ends the script with an
error and Navidrome's log (CI's log has it then); the image is pulled again
up to four times. `--reset` forgets Navidrome's database; the play counts
the tests make live in it until then. `ci/kit.sh` runs Jellyfin's script,
then this one, then `dev/kit-test.sh`, which passes `NAVIDROME_URL`,
`NAVIDROME_USER` and `NAVIDROME_PASSWORD` when the container runs, as it
does Jellyfin's.

The tests (9 November 2026, `dev/kit-test.sh` with both servers: 111
XCTest tests, 2 skipped — LRCLIB's live ones, no internet here — and 236
swift-testing tests in 22 suites, none failed):

| Suite | What |
|---|---|
| SubsonicClientTests | The token (md5(password + salt), one salt a session, in every request and URL, the password nowhere), error 41 (an API key, or the password only over https or at home), the envelope's every error and HTTP's, versions, capabilities, the stream, download and artwork URLs, the reports with and without `playbackReport`, the mixes, lyrics, favourites, `downloadsAllowed`. MD5 against RFC 1321's vectors, the padding's edges and `md5sum`. |
| SubsonicMappingTests | Navidrome's answers into Track, Album, Artist, Playlist, Genre, Lyrics and SearchResults, and other servers' shapes (numbers for ids, one object for a list, no OpenSubsonic); `allTracks` in pages, and by the albums where a server does not page or will not search for nothing; every playlist change against a playlist kept as Navidrome keeps it, long ones with and without `formPost`, and a request lost at each step. |
| JellyfinServerTests | A song twice in a Jellyfin playlist, against a playlist kept as 12.4 keeps it: its places, removing one, every move of six, a lost request. |
| ServerAddressTests | The candidates for what people type; where a password may go; detection of Jellyfin, Navidrome, other Subsonic servers and neither; the order; both real servers as typed, from Navidrome's web app's address and by the host alone ("navidrome" found at :4533). |
| NavidromeIntegrationTests | The real Navidrome: signing in, the library's numbers (358, 54, 23, 23 genres; 92 tracks with guests, 294 with two genres or more), every album's order, a known track, unknown ids, a playlist of all 358 by form POST, the files at every quality, artwork, now playing, the mixes without agents. |
| ServerContractTests | The same checks through `any MusicServer` on both servers, opened as the app opens them; and that the two give the same library: 358 tracks matched by album artist, album, disc, track and title, with the same credits, genres, years and lengths (within a second), the same 54 albums and 23 artists. |

Measured by them on Navidrome 0.64.2 (localhost, Docker): `allTracks`
(getAlbumList2, then one search3) 51–59 ms, in pages of 100 71 ms; a move
in a playlist of 358 (read, one POST) 50 ms; mixes 7–32 ms, 20 songs each,
all sharing a genre with the seed for a track, an album and a genre, 11 of
20 for an artist; play counts 0 → 0 at `.nowPlaying` → 1 at `.played` → 1
after progress and a stop at the end, on Jellyfin and Navidrome alike.

## The next rounds

- **Kit** (done, 9 November 2026): `ServerAddress` (candidates,
  detection) with tests against both test servers; `JellyfinServer`;
  `SubsonicClient` with its answers decoded from the shapes above and an
  integration suite against Navidrome; a shared contract suite run on both
  servers; MD5 with RFC 1321's test vectors; `MusicServers`' bodies.
- **App** (done, 9 November 2026; docs/ARCHITECTURE.md, "In the app"):
  the tables in "What the app asks of a server"; the sign-in screen's API
  key field and its two new messages; the strings that say Jellyfin;
  `RadioController`'s seeds; the player's `.nowPlaying`; the offline
  downloader refusing a non-audio answer (above).
- **Open**: when a play counts for Last.fm (above); seeking in a converted
  stream (above); OpenSubsonic's `sonicSimilarity` for `instantMix` where a
  server lists it; Navidrome's `transcoding` decision.
