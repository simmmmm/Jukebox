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

The app's half — the folder, the background downloads, offline mode in the
player and the radio, Settings — is added here by the app.
