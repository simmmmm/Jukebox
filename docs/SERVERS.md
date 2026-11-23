# Servers: Jellyfin, Emby, Plex, Navidrome and the other Subsonic servers

The photographer, 8 November 2026: "Moet eigenlijk ook voor navidrome en die
ander". Jukebox, made for their Jellyfin server, also plays from Navidrome and
the other servers that speak the Subsonic API (OpenSubsonic: Navidrome, Gonic,
Airsonic-Advanced, Ampache's Subsonic API, LMS), as Feishin, their reference
player, does.

This doc is the layer between the app and a server, and the map from each call
to Jellyfin's and Subsonic's requests. The protocol is
`JukeboxKit/Sources/JukeboxKit/Server/MusicServer.swift` (CONTRACT). The kit's
half was done on 9 November 2026; the app moved to it the same day.

Every number was measured on 8 and 9 November 2026 against the two test
servers, unless it says otherwise:

- Jellyfin 12.4.0 (`dev/jellyfin-test-server.sh`); the measurements are in
  `JellyfinClient.swift`'s comments.
- Navidrome 0.64.2 (10114574), the `deluan/navidrome:latest` image of
  September 2026 (`dev/navidrome-test-server.sh`), on the same made-up
  library: 23 artists, 54 albums, 358 tracks in MP3, FLAC and M4A, 5 to 8
  seconds each, no lyrics, no ReplayGain tags, no artist images. Navidrome's
  Last.fm, Spotify, Deezer and ListenBrainz agents are off: the tests must not
  need the internet.

Read: the OpenSubsonic specification at commit c1fd43f (2 November 2026);
Feishin's Subsonic code at 155e562 (3 November 2026).

## The layer

| Type | What it is |
|---|---|
| `MusicServer` | One signed-in session, Jellyfin or Subsonic: every call the app makes, server-neutral, async throws, in the kit's own models (`Track`, `Album`, `Artist`, `Playlist`, `Genre`, `Lyrics`, `SearchResults`). `AppModel`, `LibraryStore`, `AudioPlayer`, `RadioController` and the screens hold it instead of `JellyfinClient`. |
| `ServerSignIn` | Signing in to a server that has answered: user name and password. `APIKeySignIn` and `QuickConnectSignIn` refine it where the server offers them (`signIn as? any QuickConnectSignIn`): the optional ways are types, not flags that can lie. |
| `MusicServers` | The entry points: `candidateAddresses(for:)`, `detect(_:)`, `signIn(to:)`, `open(_:)`. |
| `DetectedServer` | What answered at an address before signing in: kind, URL, id, name, version, Subsonic's API version, what it offers. |
| `ServerCredentials`, `ServerSecret` | The session as the keychain keeps it. Reads the old Jellyfin-only `Credentials` JSON. |
| `ServerKind`, `SubsonicFlavour` | `.jellyfin` or `.subsonic(flavour: .navidrome / .gonic / .airsonic / .ampache / .lms / .subsonic / .other(type))`. |
| `ServerCapability` | What a server can do beyond the library, as a set, so the app hides what it lacks. |
| `ItemRef`, `MixSeed`, `PlaybackEvent` | What the calls take where Subsonic needs more than an id: which kind of item a favourite is, what a mix starts from, which moment of a play is reported. |
| `MusicServerError` | Every server's errors as the app tells them apart. |

The servers, in `JukeboxKit/Sources/JukeboxKit/`:
- `Server/JellyfinServer.swift`: Jellyfin as a `MusicServer`, a thin wrapper
  around `JellyfinClient`, which stays as it is. It adds an entry id for each
  place of a song that is in a playlist twice (below).
- `Server/ServerAddress.swift`: the candidates and the detection.
- `Server/PlayState.swift`: the play state kept on the server (below).
- `Subsonic/`: `SubsonicClient` (the `MusicServer`), `SubsonicRequests` (the
  one connection every call goes through), `SubsonicDTO` (the answers'
  shapes, read leniently, and the mapping into the models), `SubsonicSignIn`,
  and an MD5 written out in Swift (`MD5.swift`: `CryptoKit` is Apple's only,
  and the kit is Foundation only and tested on Linux).

## Decisions

1. **One protocol for what the app uses, not for what servers can do.** The
   app sorts, filters and searches the library in memory (`LibraryIndex`), so
   `MusicServer` has no `AlbumQuery`/`TrackQuery`. It has "all of it"
   (`allTracks`, `allAlbums`, `allArtists`, `playlists`, `genres`), one item,
   an album's tracks, a playlist's entries, and the calls only the server can
   answer. Each server pages as suits it (Jellyfin 2000 tracks a page, three
   at once, measured in `JellyfinClient.allTracks`; Subsonic one `search3`),
   so the paging of `LibraryStore.allAlbums`/`allArtists` lives in the servers.
2. **Jellyfin keeps its client.** `JellyfinServer` wraps `JellyfinClient`
   instead of making it conform: several of its methods have the protocol's
   names with other parameters (`setFavorite(_:itemID:)`, `lyrics(trackID:)`).
   The wrapper turns `JellyfinError` into `MusicServerError`. The client, its
   tests and its measurements stay.
3. **Subsonic through the Subsonic API only**, also for Navidrome: one client
   for every Subsonic server is one set of answers to read and test. Feishin
   uses Navidrome's own API for Navidrome (`/auth/login`, a JWT in
   `x-nd-authorization`, `/api/song` and `/api/album`, sorted and filtered on
   the server); Jukebox needs none of it, as `search3` gives every song in one
   request (25 ms for 358).
4. **Token authentication, made once.** `t = md5(password + salt)` with one
   random salt for the session, kept in the keychain; never the password
   ("Signing in").
5. **Server kind is found, not asked.** The person types an address; the app
   asks both ways at once and knows ("Which server is at an address"). There
   is no "Jellyfin or Subsonic?" picker.
6. **Capabilities, not flavours.** What the app shows depends on
   `ServerCapability`, from what the server says it has (Jellyfin's version
   and Quick Connect, OpenSubsonic's extensions, Subsonic's API version),
   never on "is this Navidrome". A Gonic that grows lyrics gets lyrics.
7. **Playlist entries are made up for Subsonic**, which has none: "<songID>#<n>"
   per place ("Playlist entries").
8. **One rule for when a play counts, the app's, on every server**: the
   player's `PlayOutcome` (not a skip: 30 s, or half of a short track), not
   Navidrome's ("Playback reports"). A skip counts nowhere; a play counts once
   on every server.
9. **Converted streams and downloads are MP3 on Subsonic** ("Streaming,
   measured", "Downloads, measured").
10. **The keychain entry migrates in place.** `ServerCredentials` decodes the
    Jellyfin-only app's `Credentials` (tested, `ServerCredentialsTests`), so
    nobody is signed out by the update.

## What the app asks of a server

All of `MusicServer`, since 9 November 2026; docs/ARCHITECTURE.md
("Navidrome and the other Subsonic servers", "In the app") says where each
part is used. The app's old types became the kit's: `Credentials` →
`ServerCredentials` (the keychain entry is read in place), `JellyfinClient` →
`any MusicServer` (`app.server`, `player.server`, `radio.server`, the
library's), `JellyfinError` → `MusicServerError`, `ServerInfo` →
`DetectedServer`, and Quick Connect → `QuickConnectSignIn`. The radio's seeds
are `MixSeed` (`.genre(name:id:)` with `id` nil for a split genre), so its old
`isJellyfinID` GUID check is gone. `ClientIdentity` is unchanged (Subsonic's
`c` is `clientName`). The sign-in screen and Settings show the server as
`kind.displayName` and its version.

The app calls every member except `search`, `track(id:)`, `album(id:)` and
`artist(id:)`: it searches and looks up in `LibraryStore`. `topSongs` is
called by `RadioController` where the server has `.topSongs`. The app's
strings that said "Jellyfin" say "your server" or the kind's name.

## Which server is at an address

**The addresses to try** (`MusicServers.candidateAddresses`): the address as
typed, normalized as `JellyfinAddress` does, with these rules:
- Navidrome's web app is at "/app" ("http://nas:4533/app/#/album/all"; the
  "#…" is already cut). A last path segment "/app" is cut off. Only the last:
  "/app/music" is a reverse proxy's path and stays.
- Gonic's web pages are "/admin/…": "/admin" and what follows is cut off, as
  Jellyfin's "/web" and what follows is.
- The ports that mean plain http when no scheme is typed: Jellyfin's 8096,
  Navidrome's 4533, Gonic's 4747, Airsonic's 4040 and LMS's 5082 (their
  documented defaults; Navidrome's measured).
- When no port and no "https://" were typed, the same host over http on 8096,
  4533, 4747, 4040, 5082 and Plex's 32400 follows the address as typed (Jellyfin's rule,
  extended: a fresh install listens on its own port only).

**Asking** (`MusicServers.detect`): at home every candidate at once, both
ways at once, 15 s each. A name on the internet is asked alone first and
its fallback ports only after it fails: a public host lets a port it does
not serve time out, and those requests hung beside the one that works
(hardening after App Review's `unreachable` at demo.navidrome.org, 22
November 2026, whose cause is not confirmed). A redirect
(http:// to https://, same path) gives the server its new address, so the
password goes straight there. Every answer 401 or 403: a proxy's sign-in in
front, said so rather than "no server". On Linux the kit follows redirects
itself: corelibs Foundation crashes when two requests at once are redirected.
1. `GET {base}/System/Info/Public`. JSON with a non-empty `Id` is Jellyfin
   (`ServerName`, `Version`, `Id`; measured: `"ProductName":"Jellyfin
   Server","Version":"12.4.0"`), or Emby ("Emby", below). Then `GET
   /QuickConnect/Enabled`.
2. `GET {base}/rest/ping.view?v=1.16.1&c=Jukebox&f=json`, no credentials. A
   `subsonic-response` object with `status` and `version` is a Subsonic
   server, whatever the status. Unauthenticated, Navidrome answers (HTTP 200):
   `{"status":"failed","version":"1.16.1","type":"navidrome","serverVersion":"0.64.2 (10114574)","openSubsonic":true,"error":{"code":10,"message":"missing parameter: 'u'"}}`.
   A server may also answer 40 (wrong user), ok, or 30 (our `v` is newer than
   it knows: it has still proved itself, and its `version` is what we send
   from then on). Without `f=json` Navidrome answers the same in XML. An
   answer starting `<subsonic-response` is a Subsonic server without JSON
   (before API 1.4.0): "This server is too old for Jukebox".
3. An OpenSubsonic server (`openSubsonic: true`):
   `GET {base}/rest/getOpenSubsonicExtensions.view?v=…&c=Jukebox&f=json`,
   which answers without credentials (the spec; measured on Navidrome). Its
   list becomes capabilities (below).

Each server answers only its own question (measured): Jellyfin 12.4 answers
`/rest/ping.view` with 404 and no body; Navidrome answers
`/System/Info/Public` with 302 to `/app/` and then its web app's HTML. If both
ever answered, Jellyfin wins (its API gives more).

**Choosing**: the first candidate in order that proved to be a server wins; a
later one wins only once every earlier one has failed. So the address as
typed wins whenever it works, and a fallback port adds no timeout: the longest
wait is one 15 s timeout, not six. When nothing proved itself: the first
candidate's error (`.transport` when nothing answered, `.invalidServerAddress`
when something did).

A Subsonic server's `DetectedServer`:
- `id` is its URL (Subsonic servers have no id; the caches are kept by server
  and user);
- `name` is the host (Subsonic servers have no name: "Signing in to nas.local
  · Navidrome 0.64.2");
- `version` is the `serverVersion` (or the API version);
- `apiVersion` is the ping's `version`.

## Signing in, and what the keychain keeps

**Jellyfin**: POST /Users/AuthenticateByName or Quick Connect. The access
token is kept (`ServerSecret.jellyfinToken`).

**Subsonic**:
1. A salt of 16 random hex digits; `t = md5(password + salt)` in lower-case
   hex. `GET /rest/ping.view?u=&t=&s=&v=&c=Jukebox&f=json`.
2. ok: the session is `ServerSecret.subsonicToken(token: t, salt: s)`. Then
   `getUser?username=` once, to say at once when the user may not stream
   (`streamRole` false), not at the first song. The password is kept nowhere.
   The token and salt go with every call. One salt for the session, because
   every image and stream URL carries it and the image cache is keyed by URL
   (`ImagePipeline`: `NSCache<NSURL, …>` and `URLCache`): a fresh salt per
   request would make every cover a new download. Navidrome accepts the same
   salt on every call (every measurement here used one). Feishin does the
   same: a salt of 12 characters at sign-in, `u`, `s` and `t` kept as its
   credential, `userId` the user name.
3. 40 ("Wrong username or password", measured with a wrong token):
   `.unauthorized`, the sign-in screen's message.
4. 41 ("Token authentication not supported", servers that keep only a hash of
   the password) or 42 ("authentication mechanism not supported"):
   - The server lists `apiKeyAuthentication`: `.needsAPIKey(helpURL:)`. The
     screen asks for an API key and links the error's `helpUrl`. A key beats
     keeping the password: it can be revoked, and a password is often the
     person's everywhere. `signIn(apiKey:)` pings with `apiKey` and no `u`
     (the spec: `u` with a key is error 43), then `tokenInfo` gives the user's
     name. Kept: `ServerSecret.subsonicAPIKey`.
   - Otherwise the password itself, `p=enc:<hex>`: it goes with every
     request, in every stream URL. Only after "This Server Gets Your
     Password" and Sign In Anyway (`.passwordItself`, kept per address),
     over https too. Plain http away from home also after "This Server
     Isn't Secure" (below), else `.passwordNeedsHTTPS`. Home is an address
     of the home's shape on a network the device is on now
     (`LocalNetwork`): 192.168.1.10 is home only while an interface is in
     its subnet, 100.64/10 only while Tailscale is up. Kept:
     `ServerSecret.subsonicPassword`, the one case
     where the keychain holds a password, because the server takes nothing
     else.
5. A server older than API 1.13.0 (no tokens) is case 4 without the key.

Measured on Navidrome 0.64.2: token ok; `p=enc:74657374` ("test") ok; a wrong
token 40; an `apiKey` 10 "missing parameter: 'u'" (it does not list
`apiKeyAuthentication`); `apiKey` with `u` 40; no `v` or no `c` 10; `v=1.8.0`
ok.

**What the keychain keeps** (`ServerCredentials`, JSON, one generic password
item, readable after first unlock): kind, server URL, id, name and version,
Subsonic's API version, user id and name, the secret, and the capabilities as
last seen (so a launch without the network shows the same screens). For
Subsonic the secret is the token and salt, an API key, or (only in case 4) the
password.

The token and salt are as good as the password to that server, like
Jellyfin's token. They are not the password, but Subsonic cannot revoke them:
they hold until the password changes. Signing out forgets them; Subsonic has
no sign-out request.

## Talking Subsonic

Every request is `GET {base}/rest/{endpoint}.view` with `u` (or `apiKey`),
`t`, `s` (or `p`), `v` (the lower of 1.16.1 and the server's), `c=Jukebox`
and `f=json`. The answer is `{"subsonic-response": {status, version, type,
serverVersion, openSubsonic, error?: {code, message, helpUrl?}, …}}`, HTTP
200 even for errors (measured: an unknown song is 200 with error 70).
- The query is escaped as `JellyfinClient.url` escapes it (only A–Z a–z 0–9
  - . _ ~ stay).
- Dates are read with `JellyfinDate`, which takes Navidrome's nine fractional
  digits ("2026-11-08T10:14:28.62878675Z").

**Long lists of ids** (a playlist's songs):
- Up to 100 ids and positions go in one GET.
- More go in one form POST (`application/x-www-form-urlencoded`, everything in
  the body, the credentials too) where the server lists `formPost`. That is
  asked only then, 2 ms. Navidrome lists it: a playlist of all 358 songs in
  one POST of 10.8 kB, 25–31 ms (measured).
- Navidrome also took them in one GET of 10.9 kB, but a reverse proxy in front
  answers 414 past its 8 kB request line (nginx's default).
- Without `formPost`: 100 a request, as JellyfinClient does. 100 `&songId=`
  with Navidrome's 22-character ids are 3 kB.

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

Jellyfin's errors become `MusicServerError` one for one (`init(_:
JellyfinError)`, tested), with 403 as `.notAllowed`.

## The map

Jellyfin's side is `JellyfinClient` as it is (its comments have the
measurements). "Navidrome" is what 0.64.2 answered. "Otherwise" is what the
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
| `allTracks(progress:)` | GET /Items `IncludeItemTypes=Audio`, 2000 a page, three at once | `search3?query=&artistCount=0&albumCount=0&songCount=1000&songOffset=` until a short page → `searchResult3.song[]` (Child, below). Otherwise: walk the albums (note 1). |
| `allAlbums()` | GET /Items `IncludeItemTypes=MusicAlbum`, 1000 a page | `getAlbumList2?type=alphabeticalByName&size=500&offset=` until a short page (500 is the spec's maximum; Navidrome took 1000 for its 54) → `albumList2.album[]` (AlbumID3). 35 kB, 4–6 ms. |
| `allArtists()` | GET /Artists/AlbumArtists, 1000 a page | `getArtists` (not paged) → `artists.index[].artist[]` (ArtistID3), `ignoredArticles`. Navidrome: the 23 album artists, each with `roles` ["albumartist","artist","maincredit"], 4 kB, 2 ms (note 2). |
| `playlists()` | GET /Items `IncludeItemTypes=Playlist` | `getPlaylists` → `playlists.playlist[]`: `id, name, comment, owner, public, songCount, duration, created, changed, coverArt ("pl-<id>"), readonly`. |
| `genres()` | GET /MusicGenres | `getGenres` → `genres.genre[]`: `value, songCount, albumCount`, no id: the id is the name. Navidrome splits tags itself: 23 genres ("Electronic" 74 songs, 11 albums), where Jellyfin lists 19 of 23 joined ("Rock; Shoegaze"). |

1. `allTracks`: an empty query must list everything (the OpenSubsonic spec,
   for offline sync). Navidrome: 358 songs in one answer, 382 kB, 17–26 ms (6
   runs). Pages of 100 at offsets 0/300/358 gave 100/58/0; `songCount=5000`
   gave 358. The total for `progress` is the sum of the albums' `songCount`
   (358, right). A server whose empty search gives fewer songs than that sum:
   walk the albums, `getAlbum` each, four at once. 54 albums took 124–160 ms
   one after another, 140–144 ms four at once on localhost; each costs a round
   trip on a phone.
2. `allArtists`: the test library's guests are all album artists elsewhere,
   so whether Navidrome lists a guest-only artist is not measured.

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
| `setRating(_:item:)` | none (`unsupported`; "Ratings" below) | `setRating?id=&rating=` 1 to 5, 0 takes it away, `id=` for a song and an album alike (Navidrome 0.64.2 answers error 10 to `albumId=`, 70 to an unknown id; it takes an artist's id too, not used). Read back as `userRating` on songs (absent when unrated) and albums (0 when unrated), measured on getSong, search3, getAlbum, getAlbumList2. |
| `playlistTracks(playlistID:)` | GET /Playlists/{id}/Items, `PlaylistItemId` | `getPlaylist?id=` → `playlist.entry[]` (Child) in order, duplicates kept; entry ids made as below |
| `createPlaylist(name:trackIDs:)` | POST /Playlists (ids in the body) | `createPlaylist?name=&songId=…` → `playlist.id` (API 1.14.0+ answers with the playlist, measured; before, the newest playlist of that name). More than 100: one form POST with `formPost`, else the first 100 and then `updatePlaylist` 100 at a time. No songs: `name` alone (measured ok, `songCount` 0). An unknown song id is dropped silently (measured: ok, `songCount` 0). |
| `addToPlaylist(playlistID:trackIDs:)` | POST /Playlists/{id}/Items?ids= | `updatePlaylist?playlistId=&songIdToAdd=…`, at the end, in order, duplicates kept (measured A B C A + D A → A B C A D A) |
| `removeFromPlaylist(playlistID:entryIDs:)` | DELETE /Playlists/{id}/Items?entryIds= | `getPlaylist`, then `updatePlaylist?playlistId=&songIndexToRemove=…` with the entries' positions there. All positions count in the playlist before the change (measured: removing 0 and 2 of A B C A D A left B A D A); a position past the end is ignored (measured: ok, nothing removed). |
| `movePlaylistEntry(playlistID:entryID:to:)` | POST /Playlists/{id}/Items/{entry}/Move/{index}; for a place of a song that repeats, below | `getPlaylist`, the move made in the list, then one `updatePlaylist` that removes every place from the first the move touches and adds the songs from there on in the new order (note). |
| `deletePlaylist(id:)` | DELETE /Items/{id} | `deletePlaylist?id=`; unknown: 70 (measured) |

Note on moving: removals and additions in one request apply the removals
first, by the positions before the change (measured: A B C D E, remove 1 and
3, add X: A C E X). A server that adds first ends the same, as the additions
go after every place removed. A move near the end of a long playlist sends a
few songs.

### What only the server knows

| Member | Jellyfin | Subsonic | Otherwise |
|---|---|---|---|
| `similarArtists(artistID:limit:)` | GET /Items/{id}/Similar | `getArtistInfo2?id=&count=&includeNotPresent=false` → `artistInfo2.similarArtist[]` (ArtistID3), also `biography`, `smallImageUrl`… From Last.fm on the server: Navidrome without its agents answers `{}` (measured, 4 ms). | empty: the artist page has the radio's own graph, as with Jellyfin's thin answers |
| `instantMix(from:limit:)` | GET /Items/{seed}/InstantMix | `.track`, `.album`: `getSimilarSongs?id=&count=` (it takes a song, album or artist id); `.artist`: `getSimilarSongs2?id=&count=`; `.playlist`: its first song's `getSimilarSongs`; `.genre`: `getRandomSongs?genre=&size=` (the name). → `similarSongs.song[]` / `similarSongs2.song[]` / `randomSongs.song[]`. Navidrome without agents mixes by genre: a jazz song's 20 were all jazz (Miles Ahead Quartet 10, Saskia de Wit 5, the seed's Blue Room Trio 5), an electronic artist's 20 were electronic 14 and pop 6; 12–34 ms. | empty: the radio's own picks carry the station (`(try? …) ?? []`) |
| `topSongs(of:limit:)` | none | `getTopSongs?id=&count=` where `topSongsByArtistId` is listed (Navidrome lists it), else `?artist=<name>` → `topSongs.song[]`. From Last.fm: Navidrome without agents answers `{}` (measured both ways). | the app's own Last.fm, or the listener's most played |
| `lyrics(for:)` | GET /Audio/{id}/Lyrics | with `songLyrics`: `getLyricsBySongId?id=` → `lyricsList.structuredLyrics[]`: `lang, synced, offset (ms; positive: sooner), displayArtist, displayTitle, line[] {start (ms, synced only), value}`; the synced one first, then the first; a line starts at `(start − offset) / 1000` s. Without it: `getLyrics?artist=&title=` → `lyrics.value`, plain text split into lines. None: Navidrome answers `lyricsList: {}` and `lyrics: {value: ""}` (measured) → nil; an unknown id 70. | "No lyrics for this song" |

### Playing

| Member | Jellyfin | Subsonic |
|---|---|---|
| `streamURL(for:quality:playSessionID:)` | /Audio/{id}/universal, AAC over HLS when capped | `stream?id=` and the credentials. `.original`: `format=raw`, the file as it is (note). Capped: `maxBitRate=<kbit/s>&format=mp3` (320, 256, 128). `playSessionID` is not sent: Subsonic has no play sessions. |
| `downloadURL(for:quality:)` | JellyfinClient.downloadURL (docs/OFFLINE.md) | `.original`: `download?id=`, the file byte for byte (MP3 at 320 for what AVPlayer cannot play); `.high`, `.normal`: `stream?id=&maxBitRate=256` / `128` with `format=mp3`. Below. |
| `downloadsAllowed()` | /Users/Me's Policy.EnableContentDownloading | `getUser?username=` → `downloadRole`; true when absent or without getUser (404) |
| `artworkURL(_:maxPixelSize:)` | /Items/{id}/Images/Primary?fillWidth=&fillHeight=&tag= | `getCoverArt?id=<artwork.tag ?? artwork.itemID>&size=<px>` and the credentials (it needs them: without, error 10, measured) |
| `report(_:_:)` | below | below |

Note on `.original`: `format=raw` is the API's "no conversion" (1.9.0+).
Without a format a server converts by its player settings, which on Airsonic
by default convert FLAC; Navidrome sends the file either way. A file AVPlayer
cannot play (Ogg, Opus, WMA, APE, WavPack, DSD, by `Track.container`,
Subsonic's `suffix`) comes as MP3 at 320.

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

- Navidrome, like Jellyfin, sends the file under the cap and converts only
  above it, to Ogg Opus, which AVPlayer cannot play. So Jukebox always says
  `format=mp3` with a cap: AAC came out right on Navidrome too, but MP3 is the
  format every Subsonic server converts to (Navidrome's, Gonic's, Airsonic's
  and LMS's documented conversions; only Navidrome's is measured), and at
  128–320 kbit/s the difference does not show on a phone.
- A converted stream has no Content-Length and no Accept-Ranges (measured).
  `estimateContentLength=true` is not asked for: its Content-Length is a
  guess (49 397 told, 48 499 sent, MP3 at 64 kbit/s), and AVPlayer waits for
  what it was told.
- A second request for the same conversion answered a Range request with 206
  (Navidrome keeps conversions for a while).
- Where the server lists `transcodeOffset` (Navidrome does), a stream can
  start part-way (`timeOffset=` seconds; measured: half the bytes at 3 s of
  6). That is the fallback if AVPlayer cannot seek in a converted stream,
  which is still to be measured on a phone.
- An unknown id is 200 with a JSON error (application/json), not audio:
  AVPlayer fails the item, as for any bad URL.

### Downloads, measured

Navidrome 0.64.2, 9 November 2026, curl with no header (as a background
download task fetches), one mono file of each kind: MP3 129 kbit/s 97 196
bytes, FLAC 97 kbit/s 69 347, M4A (AAC) 126 kbit/s 80 892. `file` and
`ffprobe` read what came.

| Asked | MP3 | FLAC | M4A |
|---|---|---|---|
| `download` | the file byte for byte, audio/mpeg, Content-Length, Accept-Ranges: bytes | the file, audio/flac | the file, audio/mp4 |
| `stream` `format=mp3&maxBitRate=256` (`.high`) | the file (under the cap) | MP3 256, 161 541 bytes | MP3 **128**, 81 065 (Navidrome caps a lossy file's conversion at its own rate) |
| `format=mp3&maxBitRate=128` (`.normal`) | MP3 128, 96 779 bytes (129 is over the cap) | MP3 128, 80 875 | MP3 128, 81 065 |
| `format=aac&maxBitRate=256` | ADTS AAC, audio/aac; ffprobe: 6.42 s for 6.03 | ADTS; 4.96 s for 5.00 | ADTS; 5.41 s for 5.00 |
| `format=m4a&maxBitRate=256` | **Ogg Opus**, audio/ogg | **Ogg Opus** | the file (no m4a conversion: Navidrome sends it as it is) |
| `format=raw` | the file | the file | the file |

- Every MP3 conversion: 200 audio/mpeg, CBR, a length ffprobe reads within
  0.05 s, chunked with no Content-Length (no total for progress, not
  resumable). A conversion Navidrome has made before comes from its cache with
  a Content-Length (seen in the live tests).
- So `.high` and `.normal` are MP3: AVPlayer plays it from a file, every
  Subsonic server converts to it, and its length is right. ADTS AAC carries no
  length (ffprobe was 8% off, a scrubber would be too), and not every server
  has AAC.
- These sine tones are smaller as FLAC than as any MP3. A real FLAC is
  800–1000 kbit/s; an AAC of 256 at `.high` comes as MP3 256, one generation
  more, the same size.
- `OfflineFile.fileName` names each file by its Content-Type: mp3, flac, m4a.

Downloads turned off (`ND_ENABLEDOWNLOADS=false`, a second Navidrome):
`getUser`'s `downloadRole` is false; `download` answers 200 with a JSON error
50 "downloads are disabled"; `stream` converts as before. So
`downloadsAllowed()` is what keeps to what the admin said, as on Jellyfin.
An unknown id: 200, application/json, error 70; no credentials: error 10.

Every Subsonic error is HTTP 200 with JSON, so `OfflineDownloader` fails for
good a 2xx answer whose Content-Type contains json or xml or starts with
`text/`, instead of keeping it as a song.

`getUser` (Navidrome 0.64.2, the test user, its admin): `streamRole` and
`downloadRole` true, `playlistRole` **false**, and it makes playlists all the
same. So no other role is read as a rule.

OpenSubsonic's `transcoding` extension (`getTranscodeDecision`, a POST with
what the player can play) would let the server choose; Navidrome lists it.
Not used, as `format=mp3` works on every server ("Open").

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

The player's moments are `AudioPlayer`'s; `PlaybackEvent` names them:

| Event | When (AudioPlayer) | Jellyfin | Subsonic with `playbackReport` | Subsonic without |
|---|---|---|---|---|
| `.nowPlaying` | the entry begins | nothing: its start report counts a play | `reportPlayback?mediaId=&mediaType=song&state=starting&positionMs=&ignoreScrobble=true`, then `state=playing` | `scrobble?id=&submission=false` |
| `.played` | heard long enough to count (`reportStartIfNeeded`, PlayOutcome not `.skipped`) | POST /Sessions/Playing | `scrobble?id=&submission=true&time=<now − position, ms>` | the same |
| `.progress` | every 10 s, pause, resume, seek; only after `.played` | POST /Sessions/Playing/Progress | `reportPlayback` `state=playing` or `paused`, `positionMs`, `ignoreScrobble=true` | on resume, `submission=false` again; else nothing |
| `.stopped` | the entry stops being current; only after `.played` | POST /Sessions/Playing/Stopped | `reportPlayback` `state=stopped`, `ignoreScrobble=true` | nothing |

Measured on Navidrome 0.64.2, a fresh song for each case (5–8 s long):
- `scrobble submission=false`: play count 0, the song in `getNowPlaying`
  (`minutesAgo` 0, `playerName` the `c`, and with `playbackReport` also
  `state`, `positionMs`, `playbackRate`).
- `submission=true`: 1, `played` set to that minute; twice: 2.
- `reportPlayback` starting, playing, stopped at 1 s: 0.
- Stopped at 30%, 45%, 49%, 50% of the track: 0; at 55%, 70%, 90%, and at the
  end: 1. Navidrome counts when more than half was heard, by the reported
  position (stopped at the end at once, without the time passing, counted):
  Last.fm's rule. Whether 4 minutes also counts could not be measured on
  8-second tracks.
- Stopped at the end without a start: 1; two plays to the end: 2.
- Paused at 2 s: `getNowPlaying` shows `state: paused, positionMs: 2000` four
  seconds later; 0.
- Everything with `ignoreScrobble=true`, to the end: 0.
- Starting and playing with `ignoreScrobble=true`, then `scrobble
  submission=true`, then stopped at the end with `ignoreScrobble=true`: 1, and
  the album's `playCount` 1 and `played` set. Exactly once.

So `ignoreScrobble=true` with our own `scrobble` counts every play exactly
once, at the moment the app decides (decision 8), as Feishin sends it
(`reportPlayback` with `ignoreScrobble: true`, starting then playing at a
start; `scrobble submission` for the count). Jellyfin counts at the start
report (measured on 12.4): the same moment. A play heard for 31 s of a
four-minute song counts in Jukebox and would not by Navidrome's rule; one
rule for the radio's taste on every server outweighs that, and Jellyfin
counts it too.

A server that also scrobbles to Last.fm or
ListenBrainz (Navidrome can) forwards what Jukebox counts. If the photographer
scrobbles there and wants Last.fm's own rule, `.played` for Subsonic can move
to "half or 4 minutes": a question for them, not decided here.

`PlaybackReport` stays as it is; Subsonic does not use `playSessionID`.

## Play state, from one device to another

`savePlayState` and `playState` (`Server/PlayState.swift`, with the
measurements):
- Jellyfin: POST and GET `/DisplayPreferences/jukebox?userId=&client=Jukebox`,
  the state as JSON under CustomPrefs "playState". Jellyfin keeps all of
  PlayState.
- Subsonic: `savePlayQueue` (`id` for every song, `current`, `position` in
  ms, saved as `c` = "Jukebox (device)") and `getPlayQueue`. The server keeps
  the songs, the current one, the position and who saved it.

## Playing on other devices

Play On sends the music to another player. Measured on Jellyfin 12.4, 17
November 2026; `PlayOnTests` and `JellyfinSessionsIntegrationTests`.

- **Jellyfin's other clients** (`Jellyfin/JellyfinSessions.swift`):
  `GET /Sessions?controllableByUserId=`, keeping sessions with
  SupportsRemoteControl and Audio, never this device's. Jellyfin passes
  commands over the client's websocket: a session that only posted
  `/Sessions/Capabilities/Full` stayed SupportsRemoteControl false, and was
  listed once its `/socket?ApiKey=` was open (`api_key` there: 403). Then
  `POST /Sessions/{id}/Playing?playCommand=PlayNow&itemIds=&startIndex=&startPositionTicks=`
  arrives as a `Play` message, `PlayLast` adds, `/Playing/{Pause, Unpause,
  Stop, NextTrack, PreviousTrack, Seek}` as `Playstate`, and
  `/Sessions/{id}/Command` with `SetVolume` (0 to 100, a string) as
  `GeneralCommand`. What it plays is the session's NowPlayingItem and
  PlayState. The far client reports its own plays.
- **A Subsonic server's jukebox** (`Subsonic/SubsonicJukebox.swift`):
  `jukeboxControl` with `action` status, set, add, skip (index, offset in
  whole seconds), start, stop, setGain (0 to 1); each answers
  `jukeboxStatus`, currentIndex -1 for none. Offered only when getUser says
  `jukeboxRole` and a status answers: Navidrome keeps its jukebox off unless
  `Jukebox.Enabled`. Not measured on a server with it on.
- **A cast device** fetches the file itself: `castURL(for:)`, a plain file
  with the credentials in the query and the type the LOAD names. Jellyfin:
  `/Audio/{id}/universal` with TranscodingProtocol http and
  TranscodingContainer mp3. With `Container=mp3` an M4A came as audio/mpeg
  (97 831 bytes), a FLAC as audio/mpeg (129 508), an MP3 as itself (113 059);
  with `mp3,aac,m4a|aac,mp4|aac,flac` the FLAC came as itself, audio/flac.
  A Jellyfin track says its container but not an M4A's codec (it may be
  ALAC), so a FLAC goes as it is and everything else but MP3 as Jellyfin's
  MP3 at 320. Subsonic: `stream?format=raw` for mp3, flac and aac,
  `format=mp3&maxBitRate=320` for the rest. Emby: Jellyfin's, the token as
  `api_key`. Plex: the file with `X-Plex-Token` for mp3 and flac, the
  transcoder's MP3 at 320 for the rest.
- **Emby's other clients** as Jellyfin's ("Emby"). **Plex**: Chromecasts
  only; its own players are not offered.

## Playlist entries

Subsonic's `getPlaylist` lists songs, not entries, and `updatePlaylist`
removes by position. A position is not an identity: after a removal or a
move, every later position is another song's. So:
- **The id**: `playlistTracks` gives each place "<songID>#<n>", n counting
  that song's earlier places in the list from 0 (A B A → "A#0", "B#0",
  "A#1"). It holds when other songs move or go, and it is unique, so
  `PlaylistsView`'s rows need no count of their own.
- **A change** (`removeFromPlaylist`, `movePlaylistEntry`) reads the playlist
  again first and finds each entry there: the n-th place of its song; or its
  last place if there are fewer now (the list was changed elsewhere: removing
  "A#1" when only one A is left removes that A); or nothing (it is gone:
  skipped, as Jellyfin skips an unknown entry id).
- **Removing** sends the positions found, all at once (they count in the list
  before the change, measured).
- **Moving** writes again only the part of the list the move changes (the
  map, "Changes"). `index` is the place the entry ends up in, as on Jellyfin
  (measured on 12.4: A to 2 in A B C D gives B C A D; every move in a list of
  six is checked against that rule, SubsonicMappingTests). A change made on
  another device between the read and the write is overwritten: a playlist is
  edited by one person at a time, and the read is milliseconds before the
  write.
- **A lost request loses no song.** The change goes in one request where it
  fits. Otherwise, on a server without `formPost`, the additions go first,
  then the removals, highest first: a request lost on the way leaves a song
  twice, never one gone (tested by failing each request of a move in turn).
  An earlier version wrote a move as the whole list again, the first 100 songs
  by `createPlaylist?playlistId=` and then the rest; there, a lost second
  request lost every song after the hundredth.

**Jellyfin** (found by the contract test, ServerContractTests): 12.4's
`PlaylistItemId` is the song's own id, so a song twice in a playlist has one
entry id for both places (measured: A B A gave A, B, A). Removing it removes
every place (A B A C A, remove A: B C). A move moves the first, and not by its
rule (A B A C A, A to 3: B A A C A). So:
- `JellyfinServer` gives the places of such a playlist "<id>#<n>", as
  Subsonic's are made.
- It changes one place by removing the song (every place, one DELETE) and
  adding it back at the places it keeps, in order from the start, with
  `POST /Playlists/{id}/Items?ids=&position=` (measured to insert there and to
  keep it: `GET /Playlists/{id}`'s `ItemIds` agreed).
- This is not atomic, as Jellyfin has no call that is: a request lost after
  the DELETE leaves that song's places out, never another song's.
- `POST /Playlists/{id}` with `Ids` would write the whole list at once. On
  12.4 the items then showed the new order while the playlist kept the old
  one, and the next change went on from the old: not used.
- A playlist where no song repeats keeps Jellyfin's own ids and calls.

## The models, from Subsonic's answers

The models were already server-neutral in shape. The mapping is in
`SubsonicDTO.swift`, tested on Navidrome's own answers in
SubsonicMappingTests and on the live server.

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
| `container` | `suffix` | Jellyfin leaves it nil (its universal URL lists what the player plays and Jellyfin decides). On Subsonic, `.original` asks for a conversion of a file AVPlayer cannot play, as nothing converts it otherwise. |

**Album** ← `AlbumID3`: `id`, `name`, `artists[]` (else `[artistId, artist]`),
`year`, `genres[].name` (else `[genre]`), `coverArt` → `imageTag`, `songCount`
→ `trackCount`, `duration`, `starred` → `isFavorite`, `created` →
`dateAdded`, `playCount`, `played` → `lastPlayed`.

**Artist** ← `ArtistID3`: `id`, `name`, `coverArt` → `imageTag` (absent
without an image, measured), `starred`, `albumCount`. No `genres` (the
snapshot has them from the tracks), no `songCount`, no `overview` (the
biography is `getArtistInfo2`'s, Last.fm's on the server; the artist page can
ask for it).

**Playlist** ← `playlist`: `id`, `name`, `coverArt` → `imageTag`, `songCount`
→ `trackCount`, `duration`, `created` → `dateAdded`. `isReadOnly` is
OpenSubsonic's `readonly` (Navidrome: false for one's own, measured), else
Subsonic's `owner` ≠ the user, so Edit is not offered where the server would
answer 50. False on Jellyfin.

**Genre** ← `genre`: `value` → `id` and `name`, `songCount`, `albumCount`.

`Track.container: String?` and `Playlist.isReadOnly: Bool` were added for
Subsonic in the first round (Models.swift), whose comments say "the server",
with Subsonic's field beside Jellyfin's.

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
| `rating` | never | API 1.6.0+ (`setRating`) | yes, songs and albums | no Rating in the menus |
| `remoteControl` | `/Sessions?controllableByUserId=` answers (Emby too) | never | — | not listed in others' Play On |
| `share` | never | `getShares` answers | yes; 501 with `ND_ENABLESHARING=false` | no Copy Share Link |
| `playbackReporting` | the plugin's query answers this user (Emby: the same route; only its 404 without the plugin measured) | never | — | On Your Jukebox from this device only |

The last three (18 November 2026, "zorg dat je ook alleen die opties toont
als het beschikbaar is op die server en dat je dat ook zeker weet") are
asked, not known: `currentCapabilities()` tries each (`ServerProbe`). A yes
is an answer; a no is 404, 403 or 501; anything else (no network, a
timeout) keeps what was known, so nothing comes and goes with the Wi-Fi.
Asked at every sign-in, switch and launch (`refreshServer`). Kept by name,
so a build that meets one it does not know passes it over. Proven both ways
by the kit's `ServerFeaturesTests` and Linux's `JUKEBOX_CHECK=remote`.

- **Remote control**, measured on Jellyfin 12.4 and Emby 4.10: after
  `/Sessions/Capabilities/Full` (`SupportsMediaControl`, `SupportedCommands`
  `SetVolume`) and the socket open, the session is listed to the user's
  other sessions; `Play`, `Playstate` and `GeneralCommand` messages arrive
  (Emby's ids as numbers). A progress report alone sets the session's
  NowPlayingItem, position, IsPaused and VolumeLevel without counting a
  play (12.4: PlayCount 0 → 0), so a controlled Jukebox says what it plays
  that way.
- **Playback Reporting** 19.0.0.0 on Jellyfin 12.4: one table,
  PlaybackActivity (DateCreated, UserId, ItemId, ItemType, ItemName,
  PlaybackMethod, ClientName, DeviceName, PlayDuration in seconds), read by
  POST `/user_usage_stats/submit_custom_query` (`{"colums": […], "results":
  [[text]]}`); an administrator 200, another user 403, no plugin 404 (Emby
  without it: 404). A play of 15 s was kept, one of 2 s not. `SELECT *`
  fails on a row with no PlaybackMethod, so columns are named; every query
  is of the signed-in user's id (hex only), as an administrator reads the
  whole household.
- **Moods and tempo** (no capability, data): Navidrome sends `moods` and
  `bpm` on every song, `[]` and 0 when untagged; the kit keeps them as nil
  then. `MoodEdges` turns them into track edges for the radio.
- **Plex**: its history (`viewedAt`), moods and sonic similarity are not
  used, and not tried: the test Plex is unclaimed and has no way out
  (moods come from plex.tv's agents, sonic similarity needs Plex Pass).

Ratings (17 November 2026). Jellyfin 12.4 keeps a per-user
`UserData.Rating`, a number without a scale: POST /UserItems/{id}/UserData
with `Rating` 8 kept 8 and set `Likes` true; `Rating` null did not clear it,
DELETE /UserItems/{id}/Rating did (measured). /UserItems/{id}/Rating itself
takes only `likes`. No sort by it (`ItemSortBy` has none), and none of
Jellyfin's own clients shows it: jellyfin-web's rating button
(`src/elements/emby-ratingbutton/emby-ratingbutton.js`) is the heart, which
reads `Likes` and sets the favourite. Stars only Jukebox could see are not
offered there.

Navidrome 0.64.2's `getOpenSubsonicExtensions`, without credentials:
`transcodeOffset` 1, `formPost` 1, `songLyrics` 1 2, `indexBasedQueue` 1,
`transcoding` 1, `playbackReport` 1, `topSongsByArtistId` 1.

Not used: `indexBasedQueue` (the play state uses plain `savePlayQueue`),
`transcoding` and `sonicSimilarity` (`getSonicSimilarTracks`, not on
Navidrome: 404; both in "Open").

The rest of the library works the same on every server. Where a Subsonic
server lacks a call the protocol has no capability for, the kit works around
it: the albums are walked (`allTracks`), 100 ids go in a request (no
`formPost`), and a server that is not OpenSubsonic has no extensions.

## Emby (17 November 2026)

The photographer: "emby en plex kunnen beide toch". Emby is Jellyfin's
ancestor, so it is no third client: `JellyfinClient` with `isEmby`, inside
`JellyfinServer`, `ServerKind.emby`. Measured on Emby 4.10.2
(`dev/emby-test-server.sh`, `emby/embyserver:latest`, the made-up library),
without Emby Premiere: nothing Jukebox uses asks for it, transcoding
included.

| | Jellyfin 12.4 | Emby 4.10 | So |
|---|---|---|---|
| Found | `ProductName` "Jellyfin Server" in /System/Info/Public | no `ProductName`; `/System/Ping` says "Emby Server" | the ping is asked only without a `ProductName` |
| Header | `Authorization: MediaBrowser …` | the same works (`X-Emby-Authorization` not needed); Client is not percent-decoded, Device is | unchanged |
| Token in a URL | `ApiKey` (`api_key` 401) | `api_key` (`ApiKey` 401) | `tokenKey` |
| Path | `/` | `/`; `/emby/System/Info/Public` answers too | unchanged (an address typed with `/emby`: not tried further) |
| Ids | GUIDs | numbers as strings ("378"); GenreItems' ids are JSON numbers (not read) | unchanged |
| One item | `/Items?Ids=` | nothing without `Recursive=true` and the type; an unreadable id is ignored and the whole library comes | both sent to both; Emby takes only the id asked for |
| Lists | play count, last played and year by default | only with `Fields=UserDataPlayCount,UserDataLastPlayedDate,ProductionYear` | `fields(_:)` |
| `/Users/Me` | the user | 500 ("Me" read as an id) | `/Users/{id}` on Emby |
| Favourites | `/UserFavoriteItems/{id}` | 404; `/Users/{id}/FavoriteItems/{id}` | the 10.8 fallback, as it was |
| New playlist | JSON body | body not read (500); query | query on Emby, 100 ids, the rest added |
| Playlist entries | the song's id | one per place ("1", "2", …): a song twice needs no `#n` | unchanged |
| A gone playlist | 404 | 500 | `.notFound` on Emby |
| Mix | `limit` | `limit` + 1; a playlist's mix is empty | cut to `limit`; the radio's own picks carry a playlist |
| Lyrics | `/Audio/{id}/Lyrics` | subtitle streams; that route is read as a stream (500) | none: no `.lyrics` |
| Loudness | NormalizationGain | none | no `.replayGain` |
| Artist counts | `AlbumCount`, `SongCount` | none (`ChildCount` is songs) | nil: no "3 albums" on a tile |
| Covers | `fillWidth`/`fillHeight` | ignored (600 px came for 300); `maxWidth`/`maxHeight` | on Emby; covers beside the files are not read, the test script uploads them |
| Genres | as tagged ("Folk; Indie") | split ("Folk", "Indie") | unchanged |
| Stream, download | `/Audio/{id}/universal` | the same answers: files as they are, HLS (AAC) when capped, m4a over http for a download | unchanged |
| Plays | counted at the start report | the same (twice for two starts; a stop alone counts nothing) | unchanged |
| Quick Connect | /QuickConnect/Enabled | 404 | no button |
| Play state | `/DisplayPreferences/jukebox` | the same | unchanged |
| Sign-out | /Sessions/Logout | the same (401 after) | unchanged |

Emby's capabilities: `ServerCapability.emby`, Jellyfin's without `lyrics`,
`syncedLyrics` and `replayGain`.

Play On: Jellyfin's Sessions API as it is, measured on 4.10.2 by
`JellyfinSessionsIntegrationTests` (a second client with its socket open is
listed and receives Play, Playstate and SetVolume). The socket is
`/embywebsocket?api_key=&deviceId=` where Jellyfin's is `/socket?ApiKey=`
(`sessionSocketPath`); a cast URL carries the token as `api_key`
(`tokenKey`). Emby sends a Play message's `ItemIds` as JSON numbers
([378, 89, 279]), Jellyfin as strings: the far client's to read.

Not measured: lyrics on Emby (the test files have none), Emby before 4.10,
an Emby with its first-run wizard finished (the test script stops before
its last step: the API works without it).

## Plex (17 November 2026)

The owner: "emby en plex kunnen beide toch". `Plex/PlexServer.swift` (the
`MusicServer`) and `Plex/PlexSignIn.swift` (finding one, plex.tv's sign-in,
a token). Plex Media Server's own HTTP API with `Accept: application/json`.
Measured on 1.43.5 (`dev/plex-test-server.sh`: unclaimed, on an internal
Docker network with no way out, the made-up library read by the
"Personal Media Artists" agent).

**Found** at an address like any other: `GET /identity`, which every Plex
server answers without a token, `machineIdentifier` and `version`. Its name
is the root's `friendlyName` where it shows it, else the host. 32400 is one
of the fallback ports, and plain http when typed.

**Signing in.** A Plex server has no user names or passwords of its own.
- **Sign In with Plex**, Plex's PIN flow: `POST https://plex.tv/api/v2/pins`
  with `strong=true`; the person signs in at
  `https://app.plex.tv/auth#?clientID=…&code=…&context[device][product]=Jukebox`
  in the browser (Apple's web sign-in on the iPhone, iPad and Mac, with
  `forwardUrl=jukebox://plex` so the sheet can close; the default browser
  through GTK on Linux), while the app asks `GET /api/v2/pins/{id}` every
  2 s for `authToken`. Then `GET /api/v2/resources?includeHttps=1&includeRelay=1`:
  the servers (`provides` has "server"), one's own first; with an address
  typed, only that server; several, the person chooses. The address: every
  one at once, `GET /identity` with the token, 5 s; the first in order that
  answers wins, the typed one first, then local, remote, relay. Kept: the
  server's `accessToken` for this account (`ServerSecret.plexToken`); the
  user is plex.tv's `GET /api/v2/user` `id`, so a sign-in again is the same
  account. `X-Plex-Client-Identifier` is the installation's own
  (`ClientIdentity.deviceID`).
- **A token** (X-Plex-Token), for a server reached without plex.tv: where an
  API key goes (`PlexSignIn` is an `APIKeySignIn`; a password asked of it
  throws `needsAPIKey` with Plex's page on finding a token). Tried on
  `/library/sections`; the user is named by the server's `/myplex/account`
  (its owner) and kept apart by the token (`token-` and its MD5), since the
  server does not say whose a token is. The same person by plex.tv is
  another account.
- Untested end to end: no plex.tv account was used. The PIN, resources and
  user answers' shapes are Plex's documentation's (`PlexSignInTests`).
- Every address is kept with the account in that order
  (`ServerCredentials.addresses`), so one signed in at home plays away from
  it: the session's first request asks them all as the sign-in does (at
  once, 5 s, the first in order that answers; `PlexReach`), and a request
  the chosen one no longer answers asks again. The account itself is not
  rewritten. A token pasted for one address has only that one.

**The map.**

| Member | Plex |
|---|---|
| `allTracks`, `allAlbums`, `allArtists` | every music section's (`/library/sections`, type "artist"), `/library/sections/{id}/all?type=10/9/8`, 1000 a page. Tracks carry no genres: the album's. |
| `playlists` | `/playlists?playlistType=audio`; a smart one is read-only |
| `genres` | the albums' genres, counted |
| one item, `albumTracks`, `search` | `/library/metadata/{id}`, `…/children`, `/hubs/search` |
| `setFavorite` | `PUT /:/rate?rating=10` (five stars), `-1` clears it (measured both) |
| playlists' changes | `POST /playlists?type=audio&uri=server://{machine}/com.plexapp.plugins.library/library/metadata/{ids}`, `PUT …/items?uri=`, `DELETE …/items/{playlistItemID}`, `PUT …/items/{id}/move?after={id}` (none: first) |
| `lyrics` | the file's stream of `streamType` 4 (an .lrc or Plex Pass's), its `key` as text |
| `streamURL`, `downloadURL` | below |
| `artworkURL` | `/photo/:/transcode?width=&height=&url=<thumb>` and the token |
| `report` | below |
| play state, mixes, similar artists, top songs, loudness | none: off |

**Measured on 1.43.5**:
- A playlist holds a song once: 150, 151, 150 made two items; adding 150
  again added nothing (`leafCountAdded` 0). `playlistItemID` names each
  place.
- Moves: A B C D, the first to 2 gave B C A D, as on Jellyfin.
- An unclaimed server answers its own network's gateway and itself without
  a token; another container on its network got 401 whatever
  `ALLOWED_NETWORKS` said, so `dev/kit-test.sh` runs the Plex tests in its
  network namespace.

**Streaming.** The file as it is: `Part.key`
(`/library/parts/123/…/file.mp3`, `Track.fileKey`) and the token: 200 with
Content-Length, 206 for a range (measured). That is what Jukebox's gapless
and normalisation want, as on every server. Capped, or a file the player
cannot play (Ogg, Opus, …, as Subsonic's rule): the universal music
transcoder as one progressive MP3, never HLS:
`/music/:/transcode/universal/start.mp3?path=/library/metadata/{id}&protocol=http&directPlay=0&directStream=1&maxAudioBitrate=`.
Plex's Generic profile has no music target (400), so the request adds one
(`X-Plex-Client-Profile-Extra`, MP3 over http). An MP3 under the cap is
copied (200 audio/mpeg, no Content-Length, `Accept-Ranges: none`,
measured). A FLAC or AAC converted is not measured: the server fetches its
converters from plex.tv, which the test server cannot reach. Downloads:
the file (`?download=1`) at Original, MP3 256 or 128 at High and Normal.
`downloadsAllowed` is true: Plex's `allowSync` is its own (Plex Pass's)
downloads, false on a server without it.

**Reports.** `.nowPlaying` and `.progress` are `/:/timeline` (`state`
playing or paused, `time` in ms); `.played` is `/:/scrobble`, the one play;
`.stopped` the timeline at 0 s. A timeline with `duration` that reaches the
end counts a play of its own (measured: twice with the scrobble), so none is
sent; without it neither a timeline at the end nor a stop there counted.
The test plays a song to its end: one play.

**Capabilities**: `lyrics`, `syncedLyrics`, `playlistReorder`,
`playbackTimeline`, `lastPlayed` (`lastViewedAt`). Off: `instantMix` (Plex's
sonic mixes need Plex Pass and an analysed library), `similarArtists` (names
from its online agent, not items), `topSongs`, `replayGain` (loudness is in
the file's streams, not the listing), `transcodeOffset`, `rating` (its one
rating is the favourite here), and the handoff (Plex keeps no state of a
client's for another to read).

**Play On**: Chromecasts only. `castURL` is the file with the token for an
MP3 or a FLAC, else the transcoder's MP3 at 320. Plex's own players
(Plex Companion) are not offered: not built.

**Tests**: `PlexSignInTests` (no server: detection, the token, the PIN,
the resources and the choice of address, the mapping, the URLs, the
reports, lyrics, the keychain) and `PlexIntegrationTests` (the real server:
358 songs, 54 albums, 23 artists; the file, a range, the copied MP3, a
cover; a favourite; a playlist's every change; one play counted).

## Classical music (14 November 2026)

The photographer: "iets wat ik ook graag zou willen supporten is klassieke muziek hoe veel fanaten het wél zouden willen zien". The research and its measurements are in `build/design-round/classical/research.md`.

| | Navidrome 0.64.2 | Jellyfin 12.4 |
|---|---|---|
| Composer, conductor, performers with instrument, lyricist | `contributors` in search3 → `Track.credits` | composer only, in People |
| Work, movement, grouping | `works`, `movements`, `groupings` → `work`, `movement`, `grouping` | not kept |
| Act (disc title) | album's `discTitles`, joined in `allTracks` and `albumTracks` | not kept |

People on every Jellyfin page is costly. On the 358-track test server, a page of 2000 took 133–140 ms with `Fields=People` and 36 ms without (medians of 7; 512 kB against 440 kB), and returned no composer at all.

So `JellyfinServer.allTracks` asks for People afterwards. It asks by id, 100 ids per request and three requests at once. It asks only for tracks on albums that `Classical.classicalAlbumIDs` recognises:
- the test server's 37 classical tracks take 20–44 ms;
- finding the classical albums takes 47 ms for 20 000 pop tracks;
- a failed People request costs the composers, never the library.

Where tags are missing, works come from titles (`Classical/Works.swift`; `ClassicalTests`, 15 tests). Search by catalogue number uses `CatalogueNumber.normalize`.

## Measuring

`dev/navidrome-test-server.sh`:
- starts Navidrome on the Docker network `jukebox` (`http://navidrome:4533`
  from the kit's tests, `http://localhost:4533` from here) on Jellyfin's
  made-up library, read-only;
- makes the user test/test through `/auth/createAdmin` (Navidrome's own API:
  a fresh server has no user);
- waits for the scan: `getScanStatus`, an empty `search3`, the albums and
  artists unchanged for one more look. 358 of 358 in 6 s from a fresh
  database, 2.4 s again. A look that fails is one look. A scan that has not
  settled in 4 minutes ends the script with an error and Navidrome's log (so
  CI's log has it). The image is pulled again up to four times;
- `--reset` forgets Navidrome's database; the play counts the tests make live
  in it until then.

`ci/kit.sh` runs Jellyfin's script, then this one, then `dev/kit-test.sh`.
That passes `NAVIDROME_URL`, `NAVIDROME_USER` and `NAVIDROME_PASSWORD` when
the container runs, as it does Jellyfin's.

The tests on 9 November 2026 (`dev/kit-test.sh` with both servers): 111
XCTest tests, 2 skipped (LRCLIB's live ones, no internet here), and 236
swift-testing tests in 22 suites; none failed.

| Suite | What |
|---|---|
| SubsonicClientTests | The token (md5(password + salt), one salt a session, in every request and URL, the password nowhere), error 41 (an API key, or the password only over https or at home), the envelope's every error and HTTP's, versions, capabilities, the stream, download and artwork URLs, the reports with and without `playbackReport`, the mixes, lyrics, favourites, `downloadsAllowed`. MD5 against RFC 1321's vectors, the padding's edges and `md5sum`. |
| SubsonicMappingTests | Navidrome's answers into Track, Album, Artist, Playlist, Genre, Lyrics and SearchResults, and other servers' shapes (numbers for ids, one object for a list, no OpenSubsonic); `allTracks` in pages, and by the albums where a server does not page or will not search for nothing; every playlist change against a playlist kept as Navidrome keeps it, long ones with and without `formPost`, and a request lost at each step. |
| JellyfinServerTests | A song twice in a Jellyfin playlist, against a playlist kept as 12.4 keeps it: its places, removing one, every move of six, a lost request. |
| ServerAddressTests | The candidates for what people type; where a password may go; detection of Jellyfin, Navidrome, other Subsonic servers and neither; the order; both real servers as typed, from Navidrome's web app's address and by the host alone ("navidrome" found at :4533). |
| NavidromeIntegrationTests | The real Navidrome: signing in, the library's numbers (358, 54, 23, 23 genres; 92 tracks with guests, 294 with two genres or more), every album's order, a known track, unknown ids, a playlist of all 358 by form POST, the files at every quality, artwork, now playing, the mixes without agents. |
| ServerContractTests | The same checks through `any MusicServer` on both servers, opened as the app opens them; and that the two give the same library: 358 tracks matched by album artist, album, disc, track and title, with the same credits, genres, years and lengths (within a second), the same 54 albums and 23 artists. |

Measured by them on Navidrome 0.64.2 (localhost, Docker):
- `allTracks` (getAlbumList2, then one search3) 51–59 ms; in pages of 100,
  71 ms.
- A move in a playlist of 358 (read, one POST): 50 ms.
- Mixes 7–32 ms, 20 songs each, all sharing a genre with the seed for a
  track, an album and a genre; 11 of 20 for an artist.
- Play counts 0 → 0 at `.nowPlaying` → 1 at `.played` → 1 after progress and
  a stop at the end, on Jellyfin and Navidrome alike.

## Open

The kit and the app's move were done on 9 November 2026 (in the app also the
sign-in screen's API key field and its two new messages, and the player's
`.nowPlaying`). Still open:
- When a play counts for Last.fm ("Playback reports").
- Seeking in a converted stream, to measure on a phone; `transcodeOffset`'s
  `timeOffset=` is the fallback ("Streaming, measured").
- OpenSubsonic's `sonicSimilarity` for `instantMix`, where a server lists it.
- Navidrome's `transcoding` decision (`getTranscodeDecision`), worth a look
  now that the player plays from Subsonic.
