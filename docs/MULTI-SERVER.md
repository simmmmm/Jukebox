# Several servers at once: one library

A design, not built. The photographer, 21 November 2026, about one account
being active at a time: "ik zou niet weten waarom we die beperking moeten
hebben als er meer mogelijk zijn - we krijgen alleen het probleem dat
verschillende libraries verschillende features gaan hebben dus we moeten dan
kijken naar wat ze allemaal kunnen".

Today (`docs/ARCHITECTURE.md`, "Accounts"): several accounts kept, one
signed in. A switch stops the player and reopens every store. Each account
has its own library cache, downloads, history, recent stations and Last.fm
answers, named by server id and user id.

The aim: any number of accounts on, shown as one library on every client.
What a server lacks is decided per item, not per app.

## The idea in five lines

1. Every id in memory carries its account: `3fa9c1d2:<the server's id>`.
   Files on disk and everything sent to a server keep the server's own id.
2. `MergedServer` is a `MusicServer` made of the accounts that are on. It
   reads the tag, strips it and asks the right one. Every store already
   holds `any MusicServer`, so most call sites do not change.
3. With one account on, nothing is wrapped and nothing is tagged: today's
   path, untouched. Going from one to two tags every id in memory, so the
   queue, the station on air and the open pages are retagged in place
   (step 4); the music plays on.
4. The same album on two servers becomes one album; each song keeps its
   copies and plays from the best one that answers.
5. A capability is asked of the item's account: `library.can(.rating, for: id)`.

## 1. What each server can do

M: measured (`docs/SERVERS.md`). C: in the code, not measured. ?: unknown.
Capabilities are kept per account (`ServerCredentials.capabilities`) and
three are asked of the server itself, so the matrix is the usual answer, not
the rule. The rule is the account's own set.

| Feature | Jellyfin 12.4 | Emby 4.10 | Navidrome 0.64.2 / Subsonic | Plex 1.43.5 |
|---|---|---|---|---|
| Browse: songs, albums, artists | yes M | yes M | yes M (albums walked where a server will not search for nothing) | yes M |
| Search | yes M | yes C | `search3` M; playlists matched in the kit | `/hubs/search` C |
| Genres | as tagged, joined ("Folk; Indie") M; the snapshot splits them | split M | split, the id is the name M | the albums' only, songs carry none C |
| Multi-disc | disc numbers M | C | disc numbers and disc titles M | `parentIndex` C |
| Favourites (song, album, artist) | yes M | yes, another route M | `star` by kind M | a rating of 10 M (song; album and artist ?) |
| Ratings, 1 to 5 | no: its rating has no scale and no client shows it M | no C | API 1.6.0+, songs and albums M | no: its rating is the favourite C |
| Playlists: read | yes M | yes M | yes M | yes, smart ones read-only M |
| Playlists: create, add, remove | yes M | yes, ids in the query M | yes, 100 a request or a form POST M | yes M |
| Playlists: reorder | yes M | yes C | API 1.8.0+ M | yes M |
| A song twice in a playlist | yes M | yes M | yes M | no M |
| A playlist's picture | administrators only M | C | no | no |
| Lyrics from the server | 10.9+, synced M | none M | always; synced with `songLyrics` M | an .lrc beside the file, or Plex Pass C |
| Loudness (Normalize Volume) | 10.9+ M | none M | OpenSubsonic `replayGain` M | none C |
| Instant mix | yes: any shared genre, shuffled M | yes; a playlist's is empty M | API 1.11.0+; by genre without agents M | off (Plex Pass, not tried) ? |
| Similar artists | yes M | yes C | API 1.11.0+; `{}` without agents M | off ? |
| An artist's top songs | no | no | API 1.13.0+; `{}` without agents M | off ? |
| Play counted | the start report M | the same M | `scrobble` M | `/:/scrobble` M |
| Now playing, progress | yes M | yes M | with `playbackReport`, else `scrobble` only M | `/:/timeline` M |
| Last played date | yes M | with `Fields` M | OpenSubsonic `played` M | `lastViewedAt` C |
| Scrobbles to Last.fm (the server's job) | its plugin | ? | its own link | ? |
| Your Year from the server | Playback Reporting plugin, asked M | the same route; only its 404 measured ? | no | history not used, not tried ? |
| Quick Connect | when enabled M | no (404) M | no | no; Sign In with Plex, untested end to end |
| API key or token sign-in | no | no | when listed C | a token C |
| Capped streaming | AAC over HLS M | the same M | MP3, `maxBitRate` and `format` M | one progressive MP3; FLAC and AAC not measured ? |
| Downloads | Original, High, Normal; the user's policy asked M | the same M | `download`, or MP3 256 / 128; `downloadRole` M | the file, or MP3; always allowed C |
| Handoff (play state kept on the server) | all of it, as JSON M | the same M | `savePlayQueue`: its own song ids and the place M | none |
| Remote sessions (control and be controlled) | asked M | asked M | no; its jukebox where the user has the role, not measured on ? | no (Plex Companion not built) |
| Chromecast, Sonos, UPnP | yes M | yes C | yes M | Chromecast; UPnP on Linux C |
| Artwork at a size | `fillWidth`, exact M | `maxWidth` M | `getCoverArt?size=` M | `/photo/:/transcode` M |
| Share link | no | no | asked (`getShares`) M | no |
| Classical: credits, work, movement | composer only M | ? | all M | ? |
| Moods and tempo | no | no | yes M | not used ? |
| MusicBrainz ids | not read | not read | not read | not read |
| Bitrate and codec per song | not read | not read | not read | not read |
| Container per song | yes C | C | `suffix` M | yes C |
| Id shape | GUID | "378" | any string | "150" |

Three things follow:
- Ids collide across servers (Emby's "378", Plex's "150"), so ids need the
  account.
- `Track` has no bitrate and no MusicBrainz id on any server. Each API is
  believed to offer both (Jellyfin's `ProviderIds` and `MediaSources`,
  Subsonic's `musicBrainzId` and `bitRate`, Plex's `Guid` and `Media`):
  unverified. Until they are read, "best quality" and "same recording" work
  from names and containers.
- Navidrome has the most (ratings, top songs, share, moods, classical
  credits); Plex the least (no mixes, no loudness, no handoff).

## 2. Features that differ per item

The check moves from the app to the item. Small surface: 13 `can(` calls
and a handful of `capabilities.contains`.

| Today | Becomes | Used by |
|---|---|---|
| `library.can(.rating)` | `library.can(.rating, for: item.id)` | Rating in a song's and an album's menu |
| `library.can(.share)` | `can(.share, for:)` | Copy Share Link |
| `library.can(.playlistReorder)` | `can(.playlistReorder, for: playlist.id)` | move handles |
| `app.can(.lyrics)` | the playing song's account, or Find Lyrics Online | the Lyrics button (off when a song has none, as today) |
| `app.can(.replayGain)` | any account on has it | Normalize Volume; a song without gain plays as it is, as an untagged one does today |
| `.instantMix`, `.topSongs`, `.similarArtists` | the seed's account | the radio, an artist's page |
| `.remoteControl`, `.playbackReporting` | each account that has it | Play On, Your Year |

The rule, as it is now ("What a server lacks is not offered"):

| Case | What shows |
|---|---|
| One item, its account lacks the action | hidden |
| One item with copies on two servers | offered if any copy's account has it; done on those |
| Several items picked, some lack it | offered; done on those that can; one line after, "Rated 12 of 15. Jellyfin keeps no ratings." |
| A setting for the whole app | on if any account has it, with the footer naming who lacks it |
| A list sorted or filtered by it (by rating) | items without it sort last, unmarked |

Nothing is greyed out in a list of songs. A greyed star on every Jellyfin
row would be noise; hidden says the same.

## 3. Identity

**Ids.** The tag is 8 hex digits, FNV-1a of server id and user id
(`SavedAccounts.stableHash`, already there), then a colon. Fixed length, so
splitting never guesses, whatever a Subsonic id contains.

The same on every device for Jellyfin, Emby and Plex (the server's own id,
Plex's `machineIdentifier`). Not for a Subsonic server: its id is the address
signed in at (`ServerAddress`), so a phone on the public address and a PC on
the home one get two tags. A Plex account by pasted token is `token-` and
its MD5, the same wherever that token is used. A handoff that names
another server's song (section 6) works only where the tags agree.

| Where an id is kept | Kept per account today | With several on |
|---|---|---|
| Library cache (`library-<server>-<user>.json`) | yes | unchanged, bare ids; tagged on load |
| Downloads: manifest, files, queue, held reports | yes, a folder each | unchanged, bare |
| History (`history-<account>.json`) | yes | unchanged, bare; an event goes to its song's account, all are read together |
| Not counted marks | yes | unchanged, bare |
| Recent stations | yes | a station seeded by an id goes to that account's list; one seeded by a name (artist, genre, decade, Your Station) to every account on; read as one list, newest first |
| Last.fm answers and the graph | yes, a cache folder | artists and tags are by name already; song answers for a set of accounts get that set's own folder (a cache, asked again) |
| Play state on the server | the server | section 6 |
| Mix ids (kind, key, day) | no ids of the server | unchanged |
| Widget snapshot (`account` names the covers) | one account | the set's name |
| Keychain: `credentials` and `accounts` | | a third item, the accounts that are on; `credentials` stays the first of them, for older builds |

No migration and no cache version bump: nothing on disk changes shape.

**The same music on two servers.** `AlbumMerge` already puts one album back
together from parts, by title, first album artist and year. Across servers
the parts overlap, so one more step:

| Level | Same when | Then |
|---|---|---|
| Artist | same name key (`NameKey.artist`), as the index does today | one artist, `mergedIDs` for the others |
| Album | `AlbumMerge.key` and the year agree, and at least half of the smaller one's songs match | one album; `mergedIDs` |
| Song | same album (above), disc, track number, title key, length within 2 s | one song with `copies: [ItemID]`; the first account's is shown |
| Song only on one side (a bonus track) | | stays in the merged album |
| Other editions ("Deluxe"), same title by another artist | | apart, as today |

The song rule is the one `ServerContractTests` already proves on Jellyfin
against Navidrome: 358 songs matched by album artist, album, disc, track
and title, lengths within a second. Singles outside an album are not
matched in the first round.

| Merged value | Rule |
|---|---|
| Play count | the sum over copies (each server counts only what it streamed) |
| Last played, date added | the latest; the earliest |
| Favourite | any copy |
| Rating | the first copy that has one |
| Loudness, lyrics, credits, moods | the first copy that has them |

**Two users of one server** share every id, and each has their own
favourites and plays. Proposed: only one of them on at a time (section 10,
question 5).

## 4. Which copy plays

`Track` has no bitrate, so quality cannot lead yet. In order:

1. On this device (downloaded), from any account.
2. Its server answers. Offline becomes per account
   (`OfflineStore.isOffline` is one flag today).
3. The server is on this network (a private or `.local` address; Plex's
   `addresses` say local, remote, relay).
4. At Original quality, a lossless container (flac, wav) over a lossy
   one. An m4a counts as unknown: no server says whether it is ALAC.
5. The accounts' order in Settings.

Later, once bitrate is read: it goes between 3 and 4.

| When | What happens |
|---|---|
| A server stops answering mid-queue | the next song resolves again; a copy elsewhere plays, else the song is skipped and dimmed as offline songs are today |
| A song only on a silent server | dimmed (`refusesOffline`), per song |
| Everything silent | today's offline: only downloads play |
| The play is told to | the server it was streamed from, only. No play is ever told twice. |
| Heard offline | held in that account's `reports.json`, as now |

## 5. Writes

No server can hold another server's ids. So:

| Action | Rule |
|---|---|
| Favourite | every copy, at once; a silent server gets it when it answers (held like a play) |
| Rating | every copy whose account has ratings |
| New playlist | made on the server its songs are on. Songs of several: section 10, question 2 |
| Add to Playlist | the playlist's server. A song from elsewhere goes in by its copy there; with no copy there, it is left out and the sheet says how many |
| The picker in Add to Playlist | playlists that can take every picked song first; the rest under "Only some songs" |
| Remove, reorder, delete, picture | the playlist's server, as today |
| Don't Count Plays | this device, per account, as today |
| Sign out of one account | its files go as today; the others play on |

`MergedServer.createPlaylist` with ids of two accounts throws; the store
splits first.

## 6. The radio, mixes, history, handoff

Most of it is server-neutral already: the snapshot, the graph and Last.fm
work by artist and title keys.

| Part | Across servers |
|---|---|
| `LibrarySnapshot` | built from the merged, de-duplicated songs. Before de-duplication an artist on two servers would weigh double. |
| Similarity graph | by artist key: no change |
| Taste and the clock | from all histories read together, copies mapped to their one song |
| The server's mix | asked of the seed's account, when it has `.instantMix` and there is no Last.fm key. It only lifts songs the station already holds near, so a mix from one server cannot crowd out the other |
| Top songs | the first account on that has `.topSongs` and the artist |
| Home's mixes | from the merged library and history. A mix's draw uses a hash of the song's id, so mixes of the day change once when a second account comes on |
| Your Year | per account: Playback Reporting where it answers (every device), else this device's history for that account's songs. Added up; never both for one account, so nothing counts twice. The source line names each: "Jellyfin: every device. Navidrome: this device." |
| Scrobbling | each server scrobbles what it streamed: once |
| Downloads | one limit for the device; each song from its winning copy; a server that forbids downloads is passed over for a copy that allows them |
| The automatic keep | on the merged history |

Handoff and Play On take a queue, and a queue can now be mixed:

| | A queue of one server | A mixed queue |
|---|---|---|
| Handoff, Jellyfin or Emby on | as today | kept whole on the first Jellyfin or Emby: its state is JSON and holds tagged ids. Its own songs stay bare, so an older build still reads those. A Subsonic song in it is found only by a device signed in at the same address (section 3) |
| Handoff, only Subsonic on | as today | each server keeps its own songs of the queue; the others fall out |
| Handoff, only Plex | none, as today | none |
| Play On: Chromecast, Sonos, UPnP | as today | works: one song at a time, each from its own server's `castURL` |
| Play On: a Jellyfin or Emby client | up to 100 songs | that server's songs, one at a time; the row is off while another server's song plays |
| Being controlled | a session on each Jellyfin and Emby that is on | commands carry that server's ids |
| CarPlay, Siri, the widget | read the stores | nothing of their own: they follow |

## 7. Performance and caching

Measured today (`docs/RADIO.md`, "Speed", release build): the snapshot takes
102 to 162 ms for 20 000 songs and 343 ms for 50 000; the graph 187 ms for
50 000. N libraries cost what their sum costs.

| Question | Answer |
|---|---|
| On disk | one cache file per account, as now. Turning an account off drops it from memory, not from disk |
| Launch | every cache read at once, off the main actor; the first that is in shows; the merge runs again as each arrives |
| Refresh | per account, each with its own `lastAsked`; a slow server holds nobody up |
| The merge | one pass by key over albums and songs. Not measured: a test for it at 50 000 songs over two servers comes with the code, with a bar of 500 ms |
| Tagging ids on load | one string per id. Not measured |
| Memory | N libraries of `Track`. Not measured; the 50 000 case is the one to watch on an iPhone |
| Artwork | a URL of the owning server; the image cache is by URL, so nothing changes. A merged album shows the winning copy's cover |
| Search | in memory over the merged index, as now |

## 8. The screens

On every client in the same round (`docs/design/SYSTEM.md`, parity
checklist), each in its own form.

| | Today | With several on |
|---|---|---|
| Settings › Accounts (iPhone, iPad, Mac) | rows, the one signed in checked, a tap switches | a switch on each row; the last one on cannot go off. Drag to order (the order is rule 5 of section 4) |
| Linux, Preferences › Accounts | `AdwActionRow`s, one checked | `AdwSwitchRow`s, the same rule |
| Account menu (Mac menu bar, iPad's and Linux's menu) | an inline picker, one chosen | check items, several checked |
| Add Account | the sign-in sheet | the same; the new account comes on, merged |
| Welcome | one server | unchanged: the first sign-in is one server. No "add more" on the welcome |
| Turning one on or off | a switch stops the music | the music plays on unless the playing song is only on the account going off |
| A silent server | the switch is refused | its row says "Not answering"; its songs dim; the rest plays |

Where a server's name shows. Only with two or more on, and as a fact in
words, not a coloured badge:

| Place | What |
|---|---|
| A playlist's facts | "12 songs · on Navidrome": a playlist lives on one server |
| A song's and an album's menu | a last quiet line, "On Jellyfin and Navidrome" |
| Two albums that did not merge but look alike | the server's name in the tile's second line |
| Downloaded, Settings › Downloads | bytes per account |
| Settings' footers | "AAC from Jellyfin, MP3 from Navidrome"; "Navidrome doesn't allow downloads for this account" |
| Your Year | the source line (section 6) |
| Rows in lists | nothing |

Per client:

| Client | What changes |
|---|---|
| Linux | Preferences › Accounts, the primary menu, the facts lines; `AccountCheck` gains a two-account run |
| Mac, iPad | Settings, the Account menu, the facts lines; 1:1 with Linux |
| iPhone | Settings, the facts lines |
| CarPlay | nothing to build; lists come from the stores. Check: an account turned off pops to the root, as a switch does |
| Siri and Shortcuts | `Voice.find` searches the merged index; nothing to build |
| Widget | `WidgetSnapshot.account` becomes the set's name, so covers of another set never show |

## 9. The plan

Each step ships alone. S is days, M a week or so, L more.

| # | Ships | Seen by him | Risk | Effort |
|---|---|---|---|---|
| 1 | The kit: tagged ids and `MergedServer`, tested on two real servers | nothing | low: no app code calls it | S |
| 2 | The kit: the cross-server merge (albums, songs, copies, merged counts), with the 50 000 test | nothing | medium: a wrong merge hides music, so the rule is strict and tested on the two test servers' same library | M |
| 3 | The stores take a set of accounts: `LibraryStore` loads each cache and merges; history, downloads, recent stations and not-counted read and write per account; offline per account; the per-item `can` | nothing with one on. Behind a hidden setting, two on | high: every store. One account on stays on today's path | L |
| 4 | The switches, on every client, with the facts lines and the playlist rules; the queue, the station and the pages retagged when a second account comes on | several servers, one library | medium | M |
| 5 | Which copy plays, and falling back when a server goes silent | a song plays from the other server | medium | M |
| 6 | Your Year added up; handoff and Play On with a mixed queue; the widget | the edges | low | M |
| 7 | Later: bitrate and MusicBrainz ids read, quality in the order of copies | better picks | low | M |

**Step 1 in detail.** All in `JukeboxKit/Sources/JukeboxKit/Server/`, owner
"Kit: servers".

- `AccountTag.swift`: `AccountTag(credentials)`, 8 hex digits;
  `tag.wrap(id)`, `AccountTag.split(id) -> (tag, bare)?`.
- `Retag.swift`: `Track.retagged(_:)`, and the same for `Album`, `Artist`,
  `Playlist`, `Genre`, `SearchResults`, `PlaybackReport`, `PlayState`,
  `Station`. Every id inside is mapped: a song's album and artists, its
  credits, an album's `mergedIDs`. Not mapped: `playlistEntryID`, image
  tags, `fileKey` (they go back to the same server with the item).
- `MergedServer.swift`: `MergedServer(members: [any MusicServer])`,
  a `MusicServer`.

| Call | What `MergedServer` does |
|---|---|
| By an id (`track`, `album`, `albumTracks`, `setFavorite`, `setRating`, `lyrics`, `streamURL`, `castURL`, `downloadURL`, `artworkURL`, `report`, `shareURL`, every playlist change, `instantMix`, `similarArtists`, `topSongs`) | split, ask that member with the bare id, tag the answer |
| Everything (`allTracks`, `allAlbums`, `allArtists`, `playlists`, `genres`, `search`) | every member at once, tagged, joined. A member that fails is left out; all failing throws |
| `createPlaylist` | the member of its songs; two members: throws `unsupported` |
| `capabilities` | the union. New: `capabilities(for: ItemID)` and `member(for: ItemID)` |
| `kind`, `credentials`, `savePlayState`, `playState`, `downloadsAllowed`, `currentCapabilities`, `signOut` | the first member's. These are the calls that do not fit; steps 3 and 6 stop using them on a merged server (they ask `members`) |

The casts that need `members` later: `as? JellyfinServer` in
`YourYearLoader`, `PlayOn` (three), `RemoteControl` (two) and
`AppModel.refreshServer`.

Tests, `MergedServerTests`, in `dev/kit-test.sh` against the Jellyfin and
Navidrome test servers, which hold the same 358 songs:
- 716 songs, 108 albums, every id tagged, no two alike;
- every song asked back by its id is the same song, from its own server;
- a stream, a cover and a download URL point at the right host and carry
  the bare id;
- a favourite set through the merged server shows on that server only;
- a playlist made of one server's songs lands there; of two, it throws;
- with Navidrome stopped, the Jellyfin half still loads;
- a round trip of `retagged` over every model gives the model back;
- one member: every answer equals the plain server's with the tag added.

Done when the kit's tests pass and nothing in `Jukebox/` or `Linux/`
changed.

## 10. Open questions for him

1. Hetzelfde album op twee servers: samenvoegen tot één album (voorstel),
   of allebei laten zien met de naam van de server erbij?
2. Een playlist met nummers van verschillende servers. Voorstel: de playlist
   staat op één server, en een nummer van een andere server gaat erin via
   zijn kopie daar, anders niet. Alternatief: een Jukebox-playlist die
   alleen op dit apparaat staat en alles kan bevatten, maar niet synct. Wil
   je dat tweede ook?
3. Wie al meerdere accounts heeft: na de update blijft alleen het huidige
   aan staan en zet je de rest zelf aan (voorstel). Een nieuw account komt
   wel meteen aan. Goed zo?
4. Staat een nummer op twee servers, welke speelt? Voorstel: gedownload,
   dan bereikbaar, dan thuisnetwerk, dan lossless, dan jouw volgorde in
   Settings. Of wil je altijd de hoogste bitrate, ook als dat de server
   buiten de deur is?
5. Twee gebruikers van dezelfde server (jij en iemand anders) tegelijk
   aan: voorstel is nee, want hartjes en plays zijn van één persoon. Of wil
   je dat wel kunnen?
