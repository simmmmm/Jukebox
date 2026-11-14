# Offline: what is on the phone

The photographer, 8 November 2026, asked whether there was "cache in
offline/downloads". To the three parts proposed ("Downloaden bij een
album, een afspeellijst of een mix; automatisch bewaren wat je vaak of kort
geleden hebt gespeeld, tot een grootte die je kiest; offline speelt de app
alleen wat op de telefoon staat, ook de radio") he answered "Alle drie".

The app's half is `Jukebox/Offline/`. The kit's half is
`JukeboxKit/Sources/JukeboxKit/Offline/`, Foundation only:

- `Offline.swift`: the manifest, the keep's plan, the download URL.
- `Keep.swift`: how the keep ranks and fills.
- `OfflineDownload.swift`: a quality's rate, a file's name, whether the admin
  allows downloads.

Tests: `Offline*Tests.swift` and `KeepPolicy*Tests.swift`
(`dev/kit-test.sh --filter Offline`, `--filter Keep`). Every number below is
printed by one of them, on lines starting `JELLYFIN-MEASURE` or
`KEEP-MEASURE`, or was measured with curl where it says so.

## The manifest

One `OfflineManifest`, saved as JSON beside the files: each song's file once,
with every reason it is there.

| Reason | Why the song is there |
|---|---|
| `.album(id)` | Its album was downloaded. |
| `.playlist(id)` | A playlist with it was downloaded. |
| `.mix(id)` | A mix with it was downloaded (MixStore's id). |
| `.kept` | The automatic keep: played often or lately. |

The first three are *chosen*. A song stays while it has a reason: removing an
album's download takes `.album(id)` from its songs and hands back only the
files left with no reason, which the app deletes. `chosenBytes` counts every
song with a chosen reason (chosen and kept counts as chosen: it stays when the
keep lets it go); `keptBytes` the songs only the keep holds.

| Call | What it does |
|---|---|
| `add` | A song saved. Saved again (another quality, or two crossing downloads): the newest save is the file, with the reasons of both. If its name changed the app deletes the older file (`file(_:)` before `add` names it). |
| `removeReason(_:from:)` | The keep letting go. A song asked about that had no reason left is handed back too, so nothing stays for nothing. |
| `forget` | Drops songs whose files are gone (the app checked the folder). |
| `tracks(with:)` | By id, so the same manifest gives the same list. The app puts an album's songs in the album's order itself. |
| `load` | Empty when the file is missing, does not read, or has another `version`; the app then finds its files again or removes them. |
| `save` | Atomic: a crash halfway leaves the old manifest, never half a new one that reads as empty and loses every reason. |

`OfflineFile.fileName(trackID:contentType:)` gives the same name for the same
song and kind of file, so a second save overwrites the first.

On disk, version 1. The test "The format on disk" reads it; when it stops
reading, the shape changed and the version must go up.

```json
{"files":{"t1":{"bytes":3924627,"fileName":"t1.m4a","quality":"normal",
  "reasons":[{"album":{"_0":"al1"}},{"kept":{}}],"savedAt":815800000,"trackID":"t1"}},"version":1}
```

## The keep

`KeepPolicy.plan` returns the songs to fetch, best first, and the songs to let
go of (only those the keep alone holds). Chosen songs are in neither list and
do not count against the limit.

### Score

Two sources, added as the radio adds them: one says "lately", the other
"often". A completed play here is usually in the server's count too.

**This device's history** (`ListeningHistory`), each play by how it ended,
with a half-life of 14 days:

| Outcome | Counts |
|---|---|
| completed | 1 |
| partial | 0.3 |
| liked (thumbs up) | 0.5, on top of its own play, which is recorded too |
| skipped | −0.5: "not now" as often as "not this"; two skips undo one listen |
| disliked (thumbs down) | −2 |

**The server's count**: every device's plays, so the web player and plays
before this phone count. With an empty history it is all there is.

- A favourite is 1.5: a play and a half. More would let a few hundred
  favourites never played crowd out this week's listening.
- The play count is `0.6 × log2(1 + plays)`: 1 play 0.6, 7 plays 1.8, 63
  plays 3.6. "Often" does not grow without end.
- It fades with its last play over 90 days, never below a quarter, as the
  radio counts it: forty plays two years ago is still "often", not "lately".
- A song 12.4 marks played with no count (a play reported without its start)
  counts as one play.

**Thumbs down**: a song whose last thumbs is down, within half a year, is not
kept. The radio leaves it out as long (`TasteData.thumbsDownDays`), and
offline the radio plays only what is on the phone. A thumbs up after it, or
half a year, brings it back.

**Threshold 0.05** to be fetched: one completed play two months ago. The
server's count of a played song never falls below it. A song never heard is
never fetched, however much room is left.

### Filling the limit

Best first, each song that still fits; a long song that does not fit leaves
its room to shorter ones further down. A kept song counts by its real bytes,
the rest by `estimatedBytes`. Ties go by id, so the same inputs give the same
plan in any library order (tested). A kept song that left the library is let
go. An empty library (not loaded yet) plans nothing rather than empty the
phone.

**The margin**: a kept song stays unless one wanted 1.5 times as much needs
its room. Every trade is a download. Without a margin, time alone trades
songs back and forth: the server's count and the history fade at different
rates, so two close songs swap on a day nothing was played. At a 14-day
half-life, a kept song no longer played keeps its place about eight days
(14 × log2 1.5) after a newer one has caught up.

### Sizes

`estimatedBytes` is the length at the quality's rate plus 3 kbit/s for the
m4a's frame index. Measured on 12.4 (the FLAC row of the second server's
table, below): at 256 and 128 kbit/s the transcode is the rate plus 2.8
kbit/s, and the estimate is within 0.1% and 0.2%.

- At `.high` and `.normal` that is the most that comes; a file sent as it is
  is smaller.
- `.original` assumes 900 kbit/s, as Track does not carry the original's
  bitrate. CD-quality FLAC or ALAC of pop and rock is 800–1000 kbit/s; MP3 and
  AAC are below it.
- Erring large is harmless: the keep holds a little under its limit until the
  real sizes are in. Erring small would fetch songs it must let go again.
- A song of no known length counts as four minutes.

1 GB (10⁹ bytes) holds, of 4-minute songs: 37 at Original (estimated), 128 at
High, 254 at Normal.

### Choosing half-life and margin

Measured on a made-up listener (`KeepPolicySimulationTests`): 2 000 songs of
150–330 s; a core of 30 that stay (favourites on the server); a rotation of
150 that turns over two songs a day. 30 plays a day: three in four from core
and rotation (by rank, Zipf 0.8: completed 85%, partial 10%, skipped 5%), the
rest anywhere (completed 40%, partial 20%, skipped 40%); the server's count
rises with each play heard. The keep runs at each day's end, High, 1 GB
(about 128 songs). Measured over days 30–120, mean of three listeners:
downloads a day, and the share of the next day's plays already on the phone.
A phone that knew the listener's ranks (their top songs that fit) would hold
69.4%; the rest come from anywhere in the library, which no keep can know.

| Half-life | no margin (1.0) | margin 1.5 | margin 2.0 | margin 3.0 |
|---|---|---|---|---|
| 7 days | 5.4 a day, 60.2% | 2.5, 60.0% | 1.5, 58.9% | 0.8, 57.2% |
| **14 days** | 3.7, 60.3% | **1.8, 59.3%** | 1.2, 58.6% | 0.8, 56.8% |
| 21 days | 3.2, 59.7% | 1.6, 58.6% | 1.0, 57.9% | 0.8, 56.2% |
| 30 days | 2.8, 59.0% | 1.3, 58.2% | 0.9, 57.0% | 0.8, 55.3% |

A shorter half-life follows the listener closer and fetches more; a larger
margin fetches less and holds a little less. **14 days, margin 1.5** halves
the downloads of no margin (1.8 a day against 3.7) for a point fewer plays
held, and nothing in the grid holds more with fewer downloads (the test
checks both). The month first guessed held less for as many downloads
(30 days, 1.5: 58.2% for 1.3; 14 days, margin 2: 58.6% for 1.2). Margin 2
would fetch a third less again (1.2 a day) but holds 1.7 points fewer than
none.

**A small change**, after 90 days of one such listener (seed 4), at 14 days:

| Margin | A day with no plays | One more completed play of a song not kept (200 tries) |
|---|---|---|
| 1.0 | trades 2 songs | changes the keep in 34 tries, 0.41 songs on average, at most 2 fetched and 1 let go |
| **1.5** | trades none | changes it in 13 tries, 0.15 songs on average, at most 2 fetched and 1 let go |
| 2.0 | trades none | changes it in none |

At most: the song played comes in, its room lets go of a song, and what is
left takes a shorter one from further down.

The listener is a model: the tables compare choices, not what a real phone
will hold. The outcome values are choices, not measurements; the model is
made of them and cannot test them.

### On the test server

The library (`RadioRealLibraryFixture`, 358 tracks as 12.4 gives them) is
tones of 5–8 s: 2 310 s, 74.8 MB at High estimated. 1 GB holds all of it, so
the limit never binds.

- **Empty history, 1 GB at High:** 12 songs, the 12 the server has a play of
  (10 with a count, 2 with only a date). No favourites on that server.
- **A made-up month, 1 GB at High:** 600 plays of 164 songs, 20 a day; 70%
  from three loved artists (Velvet Static, The Lanterns, Hexagon Lights),
  heard to the end or nearly; the rest anywhere, skipped half the time.
  Kept: 124 songs, 26.2 MB, all 46 by the three artists. The 47 heard and not
  kept were each skipped at least as often as heard. 7 of the 124 were not
  heard that month, only played on the server.
- **The same month at 2 MB** (a limit that binds): 1. Lights Sky — Hexagon
  Lights (7.53); 2. Silver Parade — Hexagon Lights (7.50); 3. Fire Story — The
  Lanterns (7.49); 4. River Waltz — The Lanterns (7.28); 5. Northern Road —
  Velvet Static (7.10); 6. Ghost Machine — The Lanterns; Paper Harbour (6.68);
  7. Northern Letters — Velvet Static (6.56); 8. Glass Road — Velvet Static
  (6.49); 9. Hollow Tide — Velvet Static; Iron Meadow (6.33).

**Speed**: 20 000 songs, 20 000 history events, 300 kept, 4 GB: one plan in
0.054 s alone, 0.084 s inside the whole suite (debug build, `swift:6.2-noble`
on Linux).

## The download URL

`JellyfinClient.downloadURL(trackID:quality:)` is GET `/Audio/{id}/universal`
with `TranscodingProtocol=http`: a plain file a background task fetches with
no header. The token is in the query as `ApiKey`, as for `streamURL`
(`api_key` is refused on 12.4). Jellyfin sends the file itself when the phone
plays its container (`Container` is `streamURL`'s list: MP3, AAC, ALAC, FLAC,
WAV, AIFF) and, at High and Normal, it is no larger than the quality. Else it
transcodes to AAC in an m4a, as one response.

| Quality | `MaxStreamingBitrate` | `AudioBitRate` | What comes |
|---|---|---|---|
| Original | — | 256 000 | the file as it is; AAC 256 for a container the phone cannot play (Ogg, Opus, WMA …), since that file is no use on it |
| High | 281 600 | 256 000 | the file when it is at most 282 kbit/s, else AAC 256 |
| Normal | 140 800 | 128 000 | the file when it is at most 141 kbit/s, else AAC 128 |

"No larger" allows 10% for tags and container: the test library's 128 kbit/s
MP3 and M4A are 129.2 and 129.5 kbit/s with them. Asked for exactly 128,
Jellyfin re-encoded the M4A into a larger file (99 224 bytes, from 97 105):
AAC to AAC, worse and bigger.

### Measured on 12.4

8 November 2026, curl with no header, and `OfflineDownloadIntegrationTests`.

**The test library** (6–8 s mono tones), every quality: the MP3 (200
audio/mpeg, 113 059 bytes), FLAC (audio/flac, 105 111) and M4A (audio/mp4,
97 105) came as themselves, byte for byte what `/Items/{id}/Download` gives,
with Content-Length and `Accept-Ranges: bytes`. With the cap lowered to
70 kbit/s (by hand in the test): 200 audio/mp4, 50 800–68 459 bytes
(67.7–68.7 kbit/s: AAC LC 64 and the index), boxes `ftyp moov moof mdat mfra`,
no Content-Length.

**A second server** (`dev/jellyfin-test-server.sh` with
`JUKEBOX_TEST_CONTAINER`, port 8097), four 4-minute stereo files made with
ffmpeg from pink noise:

| File | Original | High | Normal |
|---|---|---|---|
| FLAC, 512 kbit/s | itself, 15 369 415 bytes, 0.16 s | AAC 256, 7 765 392, 2.3 s | AAC 128, 3 924 627, 1.9 s |
| MP3, 320 kbit/s | itself, 9 602 787, 0.05 s | AAC 256, 7 765 387, 2.2 s | AAC 128, 3 924 622, 1.9 s |
| AAC (m4a), 222 kbit/s | itself, 6 659 361, 0.04 s | itself | AAC 128, 3 883 289, 2.1 s |
| Ogg Vorbis, 96 kbit/s | AAC 256, 7 765 165, 2.0 s | AAC 256, 7 765 165, 2.4 s | AAC 128, 3 924 400, 1.8 s |

- Every transcode: 200 audio/mp4, AAC LC stereo, 240.05 s to ffprobe,
  `Transfer-Encoding: chunked`, `Accept-Ranges: none`.
- It is a fragmented MP4: Jellyfin's ffmpeg uses
  `-movflags empty_moov+delay_moov` (its transcode log), giving `ftyp`, a
  `moov` with no duration, one `moof` for the whole song, `mdat`, `mfra`.
- The Ogg at High is larger than the Ogg (7.8 MB against 2.9): the phone
  cannot play it, and Track does not carry its rate to ask for less.
- Four transcodes at once plus an HLS stream from the same device: all four
  whole. A transcode read slowly (`curl --limit-rate`, 8 s rather than 1.9):
  the same bytes.
- Mono is capped at 128 kbit/s: asked for 256, the mono FLAC came as AAC 128
  (`-ab 128000 -ac 1` in the log). A lower AudioBitRate is kept (96 → 96).
- No token: 401. `api_key` for the token: 401.

### Other URLs tried

| URL | Result |
|---|---|
| `/Items/{id}/Download` | The original, byte for byte, with a Content-Disposition naming the file. 403 for a user whose admin turned "Allow media downloading" off, where the universal URL is 200 for the same user (measured on the second server). |
| `/Audio/{id}/stream?static=true` | The original, never a transcode. |
| `/Audio/{id}/stream.m4a` (`.aac`, `.mp4`) with an AudioBitRate | Always a transcode, even of a file small enough (the 222 kbit/s AAC asked for 256 came re-encoded, 7 724 036 bytes for 6 659 361). `.mp4` is sent as video/mp4. |
| `TranscodingContainer=aac` | ADTS (200 audio/aac; the FLAC at High 7 681 532 bytes in 1.9 s; on the test library `MPEG ADTS, AAC, v4 LC`). The fallback should a phone not play the fragmented m4a. ADTS has no index and no length, so a player works the length out from the bitrate. |

The universal URL ignores the admin's setting, so the app keeps to it:
`downloadsAllowed()` reads the user's `Policy.EnableContentDownloading` (true
on the test server's admin).

## In the app

### Where the songs are

One folder per account, `Application Support/Offline/<server id>-<user id>/`
(`OfflineDisk.swift`), excluded from backup: the music is on the server, and
gigabytes of it would only take the listener's iCloud space.

| File | Holds |
|---|---|
| `manifest.json` | The kit's `OfflineManifest`. |
| `collections.json` | The albums, playlists and mixes chosen, songs in order. The manifest knows which songs a reason holds, not their order, and offline a playlist's page cannot ask the server. |
| `queue.json` | Songs still to fetch, those the server would not give, and its last answer on downloading. |
| `reports.json` | Plays heard offline. |
| `files/` | The songs, named by `OfflineFile.fileName(trackID:contentType:)` from the answer's Content-Type, not the quality asked: audio/mpeg → mp3, audio/flac → flac, audio/mp4 → m4a, audio/aac → aac, wav, aiff; anything else m4a. AVPlayer reads a local file's kind by its extension. A song saved again follows the kit's `add`. |

At sign-in the folder is checked against the manifest. A file that is gone is
forgotten (`forget`). A file the manifest does not know (a download whose news
was lost as the app was ended) joins it with the reasons it was wanted for, or
is removed when nothing wanted it.

**Signing out removes the account's folder**, downloads in flight included.
A folder of any other account than the one signing in is removed as a
leftover. Decided so, rather than kept and hidden: sign-out already forgets
the library and recent stations ("Jukebox forgets the library, your recent
stations and the downloaded songs on this iPhone", the dialog says now), and
songs for an account nobody is signed in to would be gigabytes no Settings
shows. The next account, perhaps on another server, never plays the last
one's songs: folders are per account, and every download carries its account
in its tag, so one finishing after the sign-out is thrown away.

### Fetching

One background `URLSession` (`OfflineDownloader.swift`,
`com.tijmen.Jukebox.downloads`). Downloads go on while the app is in the
background, suspended or ended; the system wakes it with the news
(`JukeboxAppDelegate`, `application(_:handleEventsForBackgroundURLSession:)`)
and is told once the news is saved. This needs no capability or background
mode, so `project.yml` is unchanged. Each task's description is its tag
(account, song, quality), so the news makes sense after a relaunch; news that
comes before the account is read waits for it.

| Case | Behaviour |
|---|---|
| Order | **24 songs at a time**, in queue order: what the listener chose first, then the keep's, best first. An album or a mix goes in one go, so it finishes in the background; the keep's thousand go a couple of dozen at a time, refilled as each finishes. |
| Mobile data | Only with Settings › Downloads › Download over Cellular (off by default); a request that may not use it waits for Wi-Fi by itself. Toggling it cancels every download, which starts again asking anew. Low Data Mode holds back the keep, not what was chosen. |
| Refused (400, 404, 410, 415) | Not asked for again until chosen again. Its album or playlist is done without it ("11 of 12 songs" in Downloaded). |
| Failed on the way | Tried again after 1, 2, 4, 8 and 16 minutes, then given up. While the server is away a failure does not count, and everything waiting is tried at once when it answers. |
| Progress | Per song from the bytes written. A song Jellyfin converts has no Content-Length (a task's expected bytes are −1, and it cannot resume from the middle; the file itself can); its estimate (`KeepPolicy.estimatedBytes`, the rate asked and a little over) stands in, held under 99%. Published twice a second. A collection's progress is its songs on the phone plus the parts of those coming, over its songs. |

**The server's admin** can turn downloads off for a user (Jellyfin's "Allow
media downloading", a Subsonic server's download role):
`MusicServer.downloadsAllowed`, asked at sign-in and whenever the server
answers again, kept in `queue.json` for a launch without the server. When off,
nothing is fetched: downloads under way are cancelled and wait, and the keep
waits. Pages show no Download, only the control of one chosen before, to
remove it. Settings › Downloads says in one line that the server does not
allow downloads for this account. What is on the phone stays and plays.

### Downloads you choose

The bar of an album's, playlist's and mix's page: `arrow.down.circle`, then a
ring in the accent around a stop square while it comes, then
`checkmark.circle`. The ring and the checkmark are menus with Remove
Download, asked first ("It still plays from your server. Songs another
download holds stay."). Its songs nothing else holds go to the keep while it
can run, added back with `[.kept]`; its plan a moment later lets go of only
those it does not want, rather than delete songs it would fetch again. When
the keep cannot run they are deleted at once.

A downloaded playlist follows the server each time its page reads it: songs
added there are fetched, songs taken out lose it as a reason. A mix stays as
it was the day it was downloaded (MixStore makes new mixes, with new ids,
every day).

Library › Downloaded lists albums, playlists and mixes, newest first, each
with one fact (how far, what it waits for, or its songs and size), then "Songs
you play", the keep's. Shuffle All plays all of it. Songs on the phone show
Music's small `arrow.down.circle.fill` after their title in every list
(`TrackRow`).

### The keep

Settings › Downloads › Keep Songs I Play: on, at 5 GB (1, 2, 5, 10 or 20).
Download Quality is High by default; the rates in its words are the kit's
`aacBitrate`; Original is each file as it is, or AAC 256 when the phone cannot
play it.

`KeepPolicy.plan` runs a minute after the last play (each play moves it on),
10 s after sign-in, 15 s after the library has loaded, 5 s after Wi-Fi, the
server or full power comes back, and when its settings change. It lets go
first (`removeReason(.kept, from: plan.remove)`, deleting the files handed
back), then fetches `plan.download` in order, adding each with `[.kept]` and
its real bytes. The plan is right whatever part of the last one was done. A
kept song stays at the quality it was saved in when Settings' quality
changes; the plan counts its real bytes.

It does not run while its songs cannot come: offline, on mobile data without
leave, in Low Power Mode, or not allowed by the server. Else it could let
songs go for ones it cannot fetch, and offline the ones let go are the only
ones that play. Low Power Mode also cancels the keep's downloads in flight;
what was chosen goes on. Turned off, what the keep alone held is deleted.
Remove All Downloads turns it off too, or it would fetch its songs again at
once.

### Offline

Offline is no network (`NWPathMonitor`), or a server that does not answer
`MusicServer.currentCapabilities()` (Jellyfin's `/System/Info/Public`, a
Subsonic server's ping; one that answers but no longer takes the session is
there). Asked at sign-in; when the network changes (back after none, it counts
as offline until the server has answered: a server at home is not there from
the mobile network); when a library load or a song fails on the network; when
the app comes to the front; from Home's Try Again; and every 30 s while it does
not answer.

| Part | Offline behaviour |
|---|---|
| Player | Plays a song on the phone from its file always, online too: no data, starts at once. Offline a list starts at its first song on the phone and holds only those; songs not on the phone are passed over in the queue; a song that streamed is left three seconds after it stops for want of the network; Play Next and Play Last take only songs on the phone. A tap on a song not on the phone shows why on the mini player's line for five seconds ("You’re offline. “…” isn’t on this iPhone.") and changes nothing. Lists dim such songs (secondary). |
| Radio | Chooses from a snapshot of the library's songs on the phone (`LibrarySnapshot(tracks:)`, remade when those songs or the library change). A station on the air when the network goes is chosen again from it at once, and from the whole library when it comes back. Instant Mix and Last.fm are not asked. A song's station of a song not on the phone becomes the kit's personal station among them. |
| Plays | **Queued, not dropped.** Start and stop reports wait in `reports.json` and go to the server in order once it answers (as `played` and `stopped`, `MusicServer.report`), so the server counts them and its Last.fm scrobbles them, at the time they arrive (the reports carry no time). Progress reports made offline are dropped. At sign-out what waits is sent if the server answers, else it goes with the account. |
| Home's notice | Why first ("You’re offline." or "Can’t reach …"), then "The songs on this iPhone still play." when there are some, else "Showing your library from last time." Back online the library is read again and the notice goes by itself. |

### Counted

`download_chosen` (`kind`: album, playlist, mix), `offline_play_started`
(`from`, as `play_started`) and `setting_changed` `keep_songs`
(docs/STATS.md). Not the quality, the size, Download over Cellular or how much
is on the phone.

### Not done

- Not checked on a phone: AVPlayer playing the fragmented m4a from a file.
  AVFoundation reads movie fragments (AVAsset's `containsFragments`); if the
  length shows wrong or the file does not play, switch to ADTS
  (`TranscodingContainer=aac`, above).
- Downloads are not shown in an album's or playlist's tile, nor on Home's
  shelves; only in their pages, their songs' rows and Downloaded.
- The keep's progress is not shown song by song; Settings says how many songs
  are still to come, and what they wait for.
- A download stopped by Low Power Mode, a Download over Cellular change or the
  server's admin starts again from the beginning: no resume data is kept (a
  plain file could resume; a converted one cannot).
