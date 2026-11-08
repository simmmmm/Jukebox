# Offline: what is on the phone

The photographer, 8 November 2026, asked whether there was "cache in
offline/downloads", and to the three parts proposed ("Downloaden bij een
album, een afspeellijst of een mix; automatisch bewaren wat je vaak of kort
geleden hebt gespeeld, tot een grootte die je kiest; offline speelt de app
alleen wat op de telefoon staat, ook de radio") answered "Alle drie".

The kit's half is in `JukeboxKit/Sources/JukeboxKit/Offline/`, Foundation
only: `Offline.swift` (the contract: the manifest, the keep's plan, the
download URL), `Keep.swift` (how the keep ranks and fills) and
`OfflineDownload.swift` (a quality's rate, a file's name, whether the admin
allows downloads). The tests are `Offline*Tests.swift` and
`KeepPolicy*Tests.swift` (`dev/kit-test.sh --filter Offline`, `--filter
Keep`); every number below is printed by one of them, on lines starting
`JELLYFIN-MEASURE` or `KEEP-MEASURE`, or was measured with curl where it says
so.

## The manifest

What is on the phone is one `OfflineManifest`, saved as JSON beside the
files: each song's file once, with every reason it is there.

| Reason | Why the song is there |
|---|---|
| `.album(id)` | Its album was downloaded. |
| `.playlist(id)` | A playlist with it was downloaded. |
| `.mix(id)` | A mix with it was downloaded (MixStore's id). |
| `.kept` | The automatic keep: played often or lately. |

The first three are *chosen*: the listener asked for them. A song stays while
it has a reason. Removing an album's download takes `.album(id)` from its
songs and hands back only the files left with no reason, which the app
deletes; a song a playlist also wants stays. `chosenBytes` counts every song
with a chosen reason (a song both chosen and kept is chosen: it stays when the
keep lets it go), `keptBytes` the songs only the keep holds.

- `add` a song saved; saved again (another quality, or two downloads of one
  song that crossed), the newest save is the file, with the reasons of both.
  When its name changed, the older file is no longer the manifest's and the
  app deletes it (`file(_:)` before `add` names it). Names made by
  `OfflineFile.fileName(trackID:contentType:)` are the same for the same song
  and kind of file, so a second save overwrites the first.
- `removeReason(_:from:)` is the keep letting go of a few; a song asked about
  that had no reason left is handed back too, so nothing stays for nothing.
- `forget` drops songs whose files are gone (the app checked the folder).
- `tracks(with:)` is by id, so the same manifest gives the same list; the app
  puts an album's songs in the album's order itself.
- `load` gives an empty manifest when the file is missing, does not read, or
  is of another `version`; the app then finds its files again or removes
  them. `save` writes atomically: a crash halfway leaves the old manifest,
  never half a new one that would read as empty and lose every reason.

The format on disk, version 1 (the test "The format on disk" reads it; when it
stops reading, the shape changed and the version must go up):

```json
{"files":{"t1":{"bytes":3924627,"fileName":"t1.m4a","quality":"normal",
  "reasons":[{"album":{"_0":"al1"}},{"kept":{}}],"savedAt":815800000,"trackID":"t1"}},"version":1}
```

## The keep

`KeepPolicy.plan` says what the automatic keep should change: the songs to
fetch, best first, and the songs to let go of (only songs the keep alone
holds). Songs someone chose are on the phone anyway: they are in neither list
and do not count against the limit.

### How much a song is wanted

A song's score has two sources.

**This device's history** (`ListeningHistory`), each play by how it ended,
fading with a half-life of 14 days:

| Outcome | Counts |
|---|---|
| completed | 1 |
| partial | 0.3 |
| liked (thumbs up) | 0.5 — it comes with a play of its own, recorded too, so it adds to that |
| skipped | −0.5 — "not now" as often as "not this": two skips undo one listen |
| disliked (thumbs down) | −2 |

**The server's own count**, every device's plays, so a song heard on the web
player or before this phone counts — and with an empty history it is all there
is: a favourite is 1.5 (a play and a half; more would let a few hundred
favourites never played crowd out this week's listening), and the play count
`0.6 × log2(1 + plays)` (1 play 0.6, 7 plays 1.8, 63 plays 3.6: "often" does
not grow without end), fading with its last play over 90 days but never below
a quarter, as the radio counts it: played forty times two years ago is still
"often", only not "lately". A song 12.4 marks played with no count (a play
reported without its start) counts as one play. A completed play here is
usually in the server's count too; the two are added, as the radio adds them:
one says "lately", the other "often".

A song whose last thumbs is down, within half a year, is not kept at all: the
radio leaves it out as long (`TasteData.thumbsDownDays`), and offline the
radio plays only what is on the phone. A thumbs up after it, or half a year,
brings it back. A song needs a score of 0.05 to be fetched — one completed
play two months ago; the server's count of a played song never falls below
it — so a song never heard is never fetched, however much room is left.

### Filling the limit

Best first, each song that still fits: a long song that does not fit leaves
its room to shorter ones further down. A song already kept counts by its real
bytes, the rest by `estimatedBytes`. Ties go by id, so the same inputs give
the same plan, in whatever order the library comes (tested). A kept song
whose song has left the library is let go. An empty library (not loaded yet)
plans nothing rather than empty the phone.

**The margin.** A song the keep holds stays unless one wanted half as much
again (1.5 times) needs its room. Every trade is a download, and without a
margin time alone trades songs back and forth: the server's count and the
history fade at different rates, so two songs close in score change places
on a day nothing was played. With the 14-day half-life, a kept song no longer
played keeps its place about eight days (14 × log2 1.5) after a newer one has
caught up with it.

### Sizes

`estimatedBytes` is the song's length at the quality's rate plus 3 kbit/s for
the m4a's index of its frames, measured on 12.4: a 240.05 s song came as
7 765 392 bytes at 256 kbit/s and 3 924 627 at 128, which is the rate and 2.8
kbit/s; the estimate is within 0.1% and 0.2% of those. At `.high` and
`.normal` that is the most that comes: a file the server sends as it is is
smaller. Track does not carry the original's bitrate, so `.original` assumes
900 kbit/s: CD-quality FLAC or ALAC of pop and rock is 800–1000 kbit/s, and a
library of MP3 and AAC is below it. Erring large does no harm (the keep holds
a little less than its limit until the real sizes are in); erring small would
fetch songs it must let go of again. A song of no known length counts as four
minutes, not as nothing.

1 GB (10⁹ bytes) holds, of 4-minute songs: 37 at Original (estimated), 128
at High, 254 at Normal.

### Half-life and margin

Chosen by measuring, on a made-up listener (`KeepPolicySimulationTests`): a
library of 2 000 songs of 150–330 s; a core of 30 that stay (favourites on the
server) and a rotation of 150 that turns over two songs a day; 30 plays a day,
three in four from the core and rotation (by rank, Zipf 0.8: completed 85%,
partial 10%, skipped 5%), the rest anywhere in the library (completed 40%,
partial 20%, skipped 40%), the server's count rising with each play heard. The
keep runs at the end of each day at High with 1 GB (about 128 songs). Over
days 30–120, the mean of three listeners: downloads a day, and the share of
the next day's plays already on the phone. A phone that knew the listener's
ranks (their top songs that fit) would have held 69.4%; the rest are songs
from anywhere in the library, which no keep can know.

| Half-life | no margin (1.0) | margin 1.5 | margin 2.0 | margin 3.0 |
|---|---|---|---|---|
| 7 days | 5.4 a day, 60.2% | 2.5, 60.0% | 1.5, 58.9% | 0.8, 57.2% |
| **14 days** | 3.7, 60.3% | **1.8, 59.3%** | 1.2, 58.6% | 0.8, 56.8% |
| 21 days | 3.2, 59.7% | 1.6, 58.6% | 1.0, 57.9% | 0.8, 56.2% |
| 30 days | 2.8, 59.0% | 1.3, 58.2% | 0.9, 57.0% | 0.8, 55.3% |

A shorter half-life follows the listener more closely and fetches more for
it; a larger margin fetches less and holds a little less. Two weeks with a
margin of 1.5 halves the downloads of no margin (1.8 a day against 3.7) for a
point fewer plays held, and nothing in the grid holds more with fewer
downloads (the test checks both). The month first guessed held less for as
many downloads (30 days, 1.5: 58.2% for 1.3; two weeks at a margin of 2: 58.6%
for 1.2). A margin of 2 would fetch a third less again (1.2 a day) but holds
1.7 points fewer than none.

**A small change**, after 90 days of one such listener (seed 4), at 14 days:

| Margin | A day with no plays | One more completed play of a song not kept (200 tries) |
|---|---|---|
| 1.0 | trades 2 songs | changes the keep in 34 tries, 0.41 songs on average, at most 2 fetched and 1 let go |
| **1.5** | trades none | changes it in 13 tries, 0.15 songs on average, at most 2 fetched and 1 let go |
| 2.0 | trades none | changes it in none |

At most: the song played comes in, the room it needs lets go of a song, and
what is left over takes a shorter one from further down.

The listener is a model, not a person: the table says how the choices compare,
not what a real phone will hold. The outcome values are choices, not
measurements (the model cannot test them: it is made of them).

### On the test server

The test server's library (`RadioRealLibraryFixture`, 358 tracks as 12.4
gives them) is tones of 5–8 s: 2 310 s in all, 74.8 MB at High estimated, so
1 GB holds every one and the limit never binds there.

- **Empty history, 1 GB at High:** 12 songs, the 12 the server has a play of
  (10 with a count, 2 with only a date). No favourites on that server.
- **A made-up month** (600 plays of 164 songs: 20 a day, 70% from three
  artists the listener loves — Velvet Static, The Lanterns, Hexagon Lights —
  heard to the end or nearly, the rest anywhere, skipped half the time),
  **1 GB at High:** 124 songs, 26.2 MB; all 46 songs by the three artists.
  The 47 heard and not kept were each skipped at least as often as they were
  heard; 7 of the 124 were not heard that month, only played on the server.
- **The same month at 2 MB**, a limit that binds: 1. Lights Sky — Hexagon
  Lights (7.53); 2. Silver Parade — Hexagon Lights (7.50); 3. Fire Story — The
  Lanterns (7.49); 4. River Waltz — The Lanterns (7.28); 5. Northern Road —
  Velvet Static (7.10); 6. Ghost Machine — The Lanterns; Paper Harbour (6.68);
  7. Northern Letters — Velvet Static (6.56); 8. Glass Road — Velvet Static
  (6.49); 9. Hollow Tide — Velvet Static; Iron Meadow (6.33).

### Speed

20 000 songs, a full history (20 000 events) and 300 kept, 4 GB: one plan in
0.054 s on its own, 0.084 s inside the whole suite (the debug build in
`swift:6.2-noble` on Linux).

## The download URL

`JellyfinClient.downloadURL(trackID:quality:)` is GET `/Audio/{id}/universal`
with `TranscodingProtocol=http`: a plain file a background download task can
fetch with no header, the token in the query as `ApiKey` (as `streamURL`;
`api_key` is refused on 12.4). Jellyfin sends the file itself when the phone
plays its container (`Container` is `streamURL`'s list: MP3, AAC, ALAC, FLAC,
WAV, AIFF) and, at High and Normal, it is no larger than the quality; else it
transcodes it to AAC in an m4a, as one response.

| Quality | `MaxStreamingBitrate` | `AudioBitRate` | What comes |
|---|---|---|---|
| Original | — | 256 000 | the file as it is; AAC 256 for a container the phone cannot play (Ogg, Opus, WMA …): a file the phone cannot play is no use on it |
| High | 281 600 | 256 000 | the file when it is at most 282 kbit/s, else AAC 256 |
| Normal | 140 800 | 128 000 | the file when it is at most 141 kbit/s, else AAC 128 |

"No larger" allows 10% for tags and the container: the test library's
128 kbit/s MP3 and M4A are 129.2 and 129.5 kbit/s with them, and asked for
exactly 128 Jellyfin re-encoded the M4A into a larger file (99 224 bytes, from
97 105) — AAC to AAC, worse and bigger.

### Measured on 12.4

8 November 2026, curl with no header, and the integration test
(`OfflineDownloadIntegrationTests`).

**The test library** (6–8 s mono tones), at every quality: the MP3 (200
audio/mpeg, 113 059 bytes), the FLAC (audio/flac, 105 111) and the M4A
(audio/mp4, 97 105) came as themselves, byte for byte the files
`/Items/{id}/Download` gives, with Content-Length and `Accept-Ranges: bytes`.
With the cap lowered to 70 kbit/s (the test does it by hand): 200 audio/mp4,
50 800–68 459 bytes (67.7–68.7 kbit/s: AAC LC 64 and the index), the boxes
`ftyp moov moof mdat mfra`, no Content-Length.

**A second server** (`dev/jellyfin-test-server.sh` with
`JUKEBOX_TEST_CONTAINER`, port 8097) with four 4-minute stereo files made with
ffmpeg from pink noise:

| File | Original | High | Normal |
|---|---|---|---|
| FLAC, 512 kbit/s | itself, 15 369 415 bytes, 0.16 s | AAC 256, 7 765 392, 2.3 s | AAC 128, 3 924 627, 1.9 s |
| MP3, 320 kbit/s | itself, 9 602 787, 0.05 s | AAC 256, 7 765 387, 2.2 s | AAC 128, 3 924 622, 1.9 s |
| AAC (m4a), 222 kbit/s | itself, 6 659 361, 0.04 s | itself | AAC 128, 3 883 289, 2.1 s |
| Ogg Vorbis, 96 kbit/s | AAC 256, 7 765 165, 2.0 s | AAC 256, 7 765 165, 2.4 s | AAC 128, 3 924 400, 1.8 s |

Every transcode: 200 audio/mp4, AAC LC stereo, 240.05 s to ffprobe,
`Transfer-Encoding: chunked`, `Accept-Ranges: none`. Jellyfin's ffmpeg writes
it with `-movflags empty_moov+delay_moov` (its transcode log): `ftyp`, a
`moov` with no duration, one `moof` for the whole song, `mdat`, `mfra` — a
fragmented MP4. The Ogg at High is larger than the Ogg (7.8 MB against 2.9):
the phone cannot play it, and Track does not carry the original's rate to ask
for less.

Four transcodes at once and an HLS stream from the same device: all four whole.
A transcode read slowly (`curl --limit-rate`, 8 s rather than 1.9): the same
bytes.

**Mono** is capped at 128 kbit/s by Jellyfin: asked for 256, the mono FLAC came
as AAC 128 (`-ab 128000 -ac 1` in its log); an AudioBitRate below that is kept
(96 → 96).

**No token:** 401. `api_key` for the token: 401.

### What was tried

- `/Items/{id}/Download`: the original, byte for byte, with a
  Content-Disposition naming the file — but 403 for a user whose admin turned
  "Allow media downloading" off, where the universal URL is 200 for the same
  user (measured on the second server). So the app keeps to what the admin said:
  `downloadsAllowed()` reads the user's `Policy.EnableContentDownloading`
  (true on the test server's admin).
- `/Audio/{id}/stream?static=true`: the original, never a transcode.
- `/Audio/{id}/stream.m4a` (and `.aac`, `.mp4`) with an AudioBitRate: always a
  transcode, even of a file already small enough (the 222 kbit/s AAC asked for
  256 came re-encoded, 7 724 036 bytes for 6 659 361). `.mp4` is sent as
  video/mp4.
- `TranscodingContainer=aac`: ADTS (200 audio/aac, the FLAC at High 7 681 532
  bytes in 1.9 s; on the test library `MPEG ADTS, AAC, v4 LC`). The fallback,
  should a phone not play the fragmented m4a; ADTS carries no index and no
  length, so a player works its length out from the bitrate.

### For the app

- Name the file by the answer's Content-Type, not the quality asked for:
  `OfflineFile.fileName(trackID:contentType:)` (audio/mpeg → mp3, audio/flac →
  flac, audio/mp4 → m4a, audio/aac → aac, wav, aiff; anything else m4a).
  AVPlayer reads a local file by its extension.
- A transcode has no Content-Length, so a task's expected bytes are unknown
  (−1), and it cannot be resumed from the middle; the file itself can.
- The fragmented m4a playing from a file in AVPlayer is not checked on a phone
  here. AVFoundation reads movie fragments (AVAsset's `containsFragments`);
  should the length show wrong or the file not play, ADTS above is the switch.
- The plan: let go first (`removeReason(.kept, from: plan.remove)`, delete the
  files it hands back), then fetch `plan.download` in its order, adding each
  with `[.kept]` and its real bytes, and plan again later; the plan is right
  whatever part of the last one was done.
- A chosen download removed: its songs left with no reason may be ones the
  keep wants. Adding them back with `[.kept]` and planning lets the keep let go
  of only those it does not want, rather than delete them and fetch them again.
- A song kept stays at the quality it was saved in when Settings' quality
  changes; the plan counts it by its real bytes.

## In the app

The photographer, 8 November 2026, asked whether there was "cache in
offline/downloads"; to the three parts proposed — download an album, a
playlist or a mix; keep what is played often or lately, up to a size they
choose; offline, play only what is on the phone, the radio too — "Alle
drie". `Jukebox/Offline/` is the app's half of all three; the manifest, the
keep's choosing and the download URL are the kit's (above).

### Where the songs are

One folder per account, `Application Support/Offline/<server id>-<user id>/`,
excluded from backup (the music is on the server; a backup of gigabytes of
it would only take the listener's iCloud space): `manifest.json` (the kit's
`OfflineManifest`), `collections.json` (the albums, playlists and mixes
chosen, with their songs in order — the manifest knows which songs a reason
holds, not their order, and offline a playlist's page cannot ask the
server), `queue.json` (songs still to fetch, those the server would not
give, and its last answer on downloading), `reports.json` (plays heard
offline) and `files/`, each song named by the kit's
`OfflineFile.fileName(trackID:contentType:)` from the Content-Type the
server sent — AVFoundation reads a local file's kind from its extension
(`OfflineDisk.swift`). A song saved again is the newest save, with the
reasons of both (the kit's `add`); the older file is deleted when its name
differs.

At sign-in the folder is checked against the manifest: a file that is gone
is forgotten (`forget`); a file the manifest does not know — a download
whose news was lost as the app was ended — joins it with the reasons it was
wanted for, or is removed when nothing wanted it.

**Signing out removes the account's folder**, downloads in flight included,
and a folder of any account other than the one signing in is removed as a
leftover. Decided so, rather than kept and hidden: sign-out already forgets
the library and the recent stations ("Jukebox forgets the library, your
recent stations and the downloaded songs on this iPhone", the dialog says
now), and songs kept for an account nobody is signed in to would be
gigabytes no Settings shows. The next account, perhaps on another server,
never plays the last one's songs: the folders are per account, and every
download carries its account in its tag, so one that finishes after the
sign-out is thrown away.

### Fetching

One background `URLSession` (`OfflineDownloader.swift`,
`com.tijmen.Jukebox.downloads`): downloads go on while the app is in the
background, suspended or ended, and the system wakes it with the news
(`JukeboxAppDelegate`, `application(_:handleEventsForBackgroundURLSession:)`;
the system is told once the news is saved). No capability or background
mode is needed for that, so `project.yml` is unchanged. Each task's
description is its tag — account, song, quality — so the news makes sense
after a relaunch, and news that comes before the account is read waits for
it.

- **24 songs at a time** in the session, in the queue's order: what the
  listener chose first, then the keep's, best first. An album or a mix goes
  in one go, so it finishes in the background; the keep's thousand go a
  couple of dozen at a time, refilled as each finishes.
- **Mobile data** only with Settings › Downloads › Download over Cellular
  (off by default): a request that may not use it waits for Wi-Fi by itself.
  Turning it on or off cancels every download, which starts again asking
  anew. Low Data Mode holds back the keep, not what was chosen.
- **A song the server will not give** (400, 404, 410, 415) is not asked for
  again until it is chosen again; its album or playlist is done without it
  ("11 of 12 songs" in Downloaded). One that failed on the way is tried
  again after 1, 2, 4, 8 and 16 minutes, then given up; while the server is
  away a failure does not count, and everything waiting is tried at once
  when it answers again.
- **Progress** per song from the bytes written; a song Jellyfin converts
  comes without a length, and its estimate (`KeepPolicy.estimatedBytes`,
  the rate asked for and a little over) stands in, held under 99%. Published
  twice a second; an album's, a playlist's or a mix's is its songs on the
  phone plus the parts of those coming, over its songs.
- **The server's admin** can turn "Allow media downloading" off for a
  user (`JellyfinClient.downloadsAllowed`, asked at sign-in and whenever
  the server answers again, kept in `queue.json` for a launch without the
  server). Off: nothing is fetched, downloads under way are cancelled and
  wait, the keep waits, the pages show no Download (only the control of
  one chosen before, to remove it), and Settings › Downloads says,
  in one line, that the server does not allow downloads for this account.
  What is on the phone stays and plays. The server does not refuse the
  download URL itself (the kit measured it), so the app keeps to it.

### Downloads you choose

The bar of an album's, a playlist's and a mix's page: `arrow.down.circle`,
then a ring in the accent around a stop square while it comes, then
`checkmark.circle`; the ring and the checkmark are menus with Remove
Download, asked first ("It still plays from your server. Songs another
download holds stay."). Its songs that nothing else holds go to the keep
while it can run, and its plan, a moment later, lets go of those it does
not want, rather than delete songs it would fetch again (the kit's advice
above); else they are deleted at once. A downloaded playlist follows the server each time
its page reads it: songs added there are fetched, songs taken out lose it
as a reason. A mix is kept as it was the day it was downloaded (MixStore
makes new mixes, with new ids, every day).

Library › Downloaded lists what is on the phone: albums, playlists and
mixes, newest first, each with one fact (how far, what it waits for, or its
songs and size), then "Songs you play", the keep's; Shuffle All plays all of
it. Songs on the phone have Music's small `arrow.down.circle.fill` after
their title in every list (`TrackRow`).

### The keep

Settings › Downloads › Keep Songs I Play, on at 5 GB (1, 2, 5, 10 or 20),
in Download Quality (High by default; the rates in its words are the kit's
`aacBitrate`; Original is each file as it is, or AAC at 256 when the phone
cannot play it). `KeepPolicy.plan` runs a minute after
the last play (each play moves it on), 10 s after sign-in, 15 s after the
library has loaded, 5 s after Wi-Fi, the server or full power comes back,
and when its settings change. It fetches its `download` list in its order
and deletes its `remove` list, removing first. It does not run while its
songs cannot come — offline, on mobile data without leave, in Low Power
Mode, or not allowed by the server — as it could let
songs go to make room for ones it cannot fetch, and offline those it let go
of are the only ones that play. Low Power Mode also cancels the keep's
downloads in flight; what was chosen goes on. Turned off, what the keep
alone held is deleted. Remove All Downloads turns it off too, or it would
fetch its songs again at once.

### Offline

Offline is no network (`NWPathMonitor`) or a server that does not answer
its public info (`/System/Info/Public`): asked at sign-in, when the network
changes (back after none, it counts as offline until the server has
answered — a server at home is not there from the mobile network), when a
library load or a song fails on the network, when the app comes to the
front, from Home's Try Again, and every 30 s while it does not answer.

- **The player** plays a song on the phone from its file always, online
  too: no data, and it starts at once. Offline: a list starts at its first
  song on the phone and holds only those; songs not on the phone are passed
  over in the queue; a song that streamed is left three seconds after it
  stops for want of the network; Play Next and Play Last take only songs on
  the phone. A tap on a song that is not on the phone says why on the mini
  player's line for five seconds — "You’re offline. “…” isn’t on this
  iPhone." — and nothing changes; lists dim such songs (secondary).
- **The radio** chooses from a snapshot of the library's songs on the phone
  (`LibrarySnapshot(tracks:)`, made again when the songs on the phone or the
  library change); a station on the air when the network goes is chosen
  again from it at once, and from the whole library when it comes back.
  Instant Mix and Last.fm are not asked while offline. A song's station of a
  song not on the phone becomes the kit's personal station among them.
- **Plays heard offline are queued, not dropped**: their start and stop
  reports wait in `reports.json` and go to the server in order once it
  answers, so Jellyfin counts them and its Last.fm plugin scrobbles them —
  at the time they arrive, not when they were heard (the reports carry no
  time). Progress reports made offline are dropped. At sign-out what is
  waiting is sent if the server answers, else it goes with the account.
- **Home's notice** says why first — "You’re offline." or "Can’t reach …" —
  then "The songs on this iPhone still play." when there are some, else
  "Showing your library from last time."; back online the library is read
  again and the notice goes by itself.

### Counted

`download_chosen` (`kind`: album, playlist, mix), `offline_play_started`
(`from`, as `play_started`) and `setting_changed` `keep_songs` (docs/STATS.md).
Not the quality, the size, Download over Cellular or how much is on the phone.

### Not done

- Downloads are not shown in an album's or a playlist's tile, nor on
  Home's shelves; only in their pages, their songs' rows and Downloaded.
- The keep's progress is not shown song by song; Settings says how many
  songs are still to come, and what they wait for.
- A download stopped by Low Power Mode, by Download over Cellular
  changing, or by the server's admin, starts again from its beginning: no
  resume data is kept (a plain file could resume; a converted one cannot).
