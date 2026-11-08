# The radio: how it chooses

The photographer, 8 November 2026: "ik vind vooral de radiofunctie echt
belangrijk". A station starts from anything (a song, an artist, an album, a
genre, a decade, a playlist or mix, the listener's own taste, the new, the
loved) and plays for as long as it is left on. It stays near its seed without
being the same, keeps its rules, and listens: a skip, a thumbs up or down, a
song heard to the end changes what comes next at once.

The code is in `JukeboxKit/Sources/JukeboxKit/Radio/` and
`Library/LibrarySnapshot.swift`, Foundation only. The measurements below come
from the tests in `JukeboxKit/Tests/JukeboxKitTests/Radio*.swift`; every
number here is printed by one of them (`dev/kit-test.sh --filter Radio`,
lines starting `RADIO-EVAL`).

## The parts

| Type | What it is |
|---|---|
| `LibrarySnapshot` | The library at one moment, indexed by track number: artists, genres, album, year of each track; tracks of each artist, genre, album and decade; how specific each genre is; which genres go together. Made once, read by everything. |
| `TasteProfile` | What the listener likes, −1 … 1, for every track, artist and genre, and how familiar each track is, 0 … 1. From Jellyfin's favourites and play counts and this device's history. |
| `SimilarityGraph` | Who sounds like whom: artists (and, from Last.fm, tracks) with weighted edges. From the library alone (`fromLibrary`), merged with Last.fm's when there is a key. Codable, kept on disk. |
| `Station` | A seed with a stable id ("artist-radiohead"), a title ("Radiohead Radio") and up to four covers. |
| `RadioSession` | One station playing: hands out tracks a few at a time, takes feedback, takes tracks back to choose again. A value type; `RadioController` in the app holds one. |
| `SplitMix64` | The radio's own random numbers, so a seed gives the same station everywhere (and the mixes can use the date as a seed). |

### Names as the server gives them

Jellyfin 12.4 gives a joined tag as one name. On the test server 92 of 358
tracks have an artist like "MC Polder; Lyric Engine", and 294 a genre like
"Hip-Hop; Nederhop". The snapshot splits them:
- artists on ";", "|" and "feat." / "ft." / "featuring", not on "&", "and"
  or "/" ("Simon & Garfunkel" and "AC/DC" are one artist);
- genres on ";" and "|", not on "/" ("Singer/Songwriter" is one genre).

A part gets the id that name has elsewhere in the library, usually as an
album artist. "Various Artists" is nobody: on a compilation the performer is
who a song is by.

After splitting, the test server has 23 artists and 23 genres, which is what
it has. `snapshot.artistKeys(of:)`, `primaryArtistKey(of:)` and
`genreKeys(of:)` give the split keys. They are precomputed, unlike
`Track.artistKeys`, which runs NameKey on every call (about 25 µs a name on
Linux) and does not split. `PlayEvent(track:…)` stores the split keys too,
so the history of a song that has left the library still finds its artists.

An artist's genres and era are those of the records filed under them. A
guest spot is someone else's record: MC Polder guesting on a jazz trio's
album does not make him jazz. Measured: with guest spots counted, Jazz and
Nederhop came out as "related genres" on the test server, and Jazz Radio
played four Nederhop songs in twenty.

### Taste

Each track's evidence, `e`:
- a favourite: +2;
- a play count `p`: +0.8 · log₂(1 + p), fading with the last play (a
  90-day half-life, never below 35%: forty plays two years ago is still
  liking);
- each event in this device's history: completed +1, partial +0.3,
  skipped −0.8, liked +3, disliked −4, fading with a 21-day half-life
  (measured: a completion three weeks ago counts 0.51 of one today, the
  test allows 0.45 … 0.55).

Track affinity is `tanh(e / 3)`. Familiarity is `1 − e^(−n/3)`, where `n`
is plays (the larger of Jellyfin's count and this device's completions, not
both: the player reports each completion to Jellyfin), plus half a play for
each partial or like and a quarter for each skip. A favourite is at least
0.6.

Artists and genres add up their tracks' evidence: the artist a track is
filed under fully, a guest half, dislikes at half (one bad song is not a bad
artist). History for tracks no longer in the library counts for their
artists and genres. The total is scaled by the listener's own 90th
percentile (75th for genres), so the artists they like most come out near 1
whether they have played a hundred songs or a hundred thousand.

Everything is clamped before it is used: negative play counts, dates in the
future, NaN seconds. Nothing comes out NaN; the test feeds it all of these.

`topArtists`/`topGenres` leave out the disliked. The never-heard come last,
biggest first, so a new listener still gets a list. `topTracks` and
`lastHeard` are there for the mixes.

### The graph, from the library

Between every two artists that share a genre (each artist only meets its
genre-mates, through an inverted index):

- **Genres**: a weighted Jaccard of their genre shares. Each genre is
  weighted by how specific it is, `ln(1 + artists / artists with the genre)`.
  This is multiplied by a confidence that grows with the specificity they
  share, full at a genre one artist in twenty has. Up to 0.6 in all, as tags
  are weaker evidence than Last.fm's listeners. Measured (in a library
  where everyone is Rock): two artists who are both "Rock; Shoegaze" get
  0.61, two who are only "Rock" get 0.20.
- **Guests**: 0.45 for one track together, up to 0.65 for three or more.
  That holds when the two share some genre (genre similarity 0.25 or more).
  When they share none, it is 40% of that: a friendship more than a
  likeness. Measured on the test server, where guests often cross genres:
  before this, Velvet Static's neighbours were Iron Meadow 0.69 and then
  Kalimba Sound System 0.65 and Nightdrive 0.56 (house, synthwave), and
  Velvet Static Radio was 40% electronic. After it, Kalimba Sound System
  0.26 and Nightdrive 0.22 sit beside The Lanterns 0.24.
- **Era**: up to 0.15 for the same median year, nothing ten years apart,
  only between artists who share a genre.

These combine as independent evidence does, `1 − (1−a)(1−b)(1−c)`. Each
artist keeps its 30 strongest edges. An edge stays when either end keeps it,
so the graph is symmetric. Edges under 0.03 are dropped.

`addArtistEdge(a, b, weight:)` (for Last.fm) keeps the heavier of two edges
and counts `a`, the artist that was asked about, in `enrichedArtistCount`.
`addTrackEdge` is one way. `merge` keeps the heavier edge and unions the
enriched set. Decoding is lenient: a cache missing a part opens with that
part empty.

## How a station chooses

### 1. The seed becomes a profile

| Seed | Artists | Genres, era | First track |
|---|---|---|---|
| `.track` | its artists (0.88, a guest 0.75) | its genres; its year ±5 | that track, always (even if just heard) |
| `.artist` | the artist (0.88) | their records' genres; their median year, spread from their years (≥ 4) | one of their best-liked, drawn from the top 3 |
| `.album` | the album's artists by share | the album's genres and year | a best-liked track from it |
| `.genre` | (none of its own); its artists (half their records or more) lead to their neighbours | the genre, and genres that go with it (0.1 + 0.5 · adventurousness of their link) | a best-liked track of the genre |
| `.decade` | the listener's liked artists with songs in it | the listener's genres in that decade (taste-weighted) | a best-liked track from it |
| `.collection` | its artists by share | its genres and era; its own tracks get a channel of 0.6 | a best-liked track from it |
| `.personal` | the 30 artists liked most | the 12 genres liked most; the 300 liked tracks get a channel of their own | from the listener's top 30 |
| `.discovery` | as `.personal` | as `.personal` | near their taste, unheard |
| `.favorites` | the favourites' artists | the favourites' genres; every favourite a channel of 0.85 | a favourite |

Then the neighbours. Each seed artist's neighbours in the graph get the seed
artist's weight × the edge × 0.95. Further out, the neighbours' neighbours
get × the second edge × 0.8 × adventurousness. A neighbour remembers whom it
came through, for "Sounds like …". A seed that is not in the library (an
artist since removed) plays as Your Station under its own title. A station
never refuses to start.

### 2. Closeness

Every track (all of them, in one pass over plain arrays) gets the best of
its channels plus a quarter of the second best, at most 1:

- **artist**: the profile's weight of its artist; a guest counts 0.7 of
  that;
- **genre**: how much of the profile's genre it covers, the rarer genres
  counting more, a little less for genres of its own the profile does not
  have, scaled so the best-covering track is 0.7 (0.9 on a genre station);
- **track**: the seed track 1, Last.fm's similar tracks 0.35 … 0.95,
  `addCandidates` up to 0.9 × weight, collection members 0.6, favourites on
  Loved 0.85;
- **era**: on a decade station, 1 inside the decade, falling off outside
  with a spread of 1 + 4 · adventurousness years. Elsewhere the year scales
  closeness by 0.65 … 1 (0.85 when unknown).

Near the familiar end, a track must also sound like the station. Closeness
is scaled by its genre fit: a track with none keeps 40% at adventurousness
0, 61% at 0.35, and all of it at 1. Instant Mix, Last.fm and similar-track
candidates skip this and the era: they have judged how a track sounds better
than tags can.

The channel that won is the reason under the track in Up Next:
- artist → "More by X" (the seed's own) or "Sounds like X" (the artist it
  came through). An artist link three quarters as strong as the genre fit
  wins the reason: who it is like says more than "More Rock";
- genre → "More Shoegaze" (the track's most telling genre);
- track → "Like “Song”", "From Jellyfin’s mix", or whatever reason
  `addCandidates` was given;
- era → "From the 1990s".

Taste supplies the reason only where taste is the point:
- Your Station: "One of your favourites" (a heart, or affinity 0.6, about
  eight recent plays), "Not heard in a while";
- Discovery: "New to you";
- Loved: "One of your favourites";
- a favourite on a genre station below 0.5: "One of your favourites".

A like that lifted a track by its artist (or a close neighbour, by 0.55 or
more) gives "Because you liked “Song”".

### 3. The score

`base = closeness^γ × e^(taste) × familiarity × freshness`

- γ = 2.4 − 1.8 · adventurousness (2.4 … 0.6): how sharply closeness counts.
- taste = (1.2 − 0.7a) · track affinity + (0.5 − 0.2a) · artist affinity +
  0.2 · genre affinity.
- familiarity = e^(1.4 · (1 − 2a) · (familiarity − 0.35)): up to four times
  for a song known well at 0, the other way round at 1. Discovery uses
  e^(−(3 + 2a) · (familiarity − 0.35)), and favourites × 0.15.
- freshness = 1 − 0.75 · 2^(−hours since heard / 48); a song heard half a
  day ago is at 0.37, a week ago 0.93. Known songs not heard for 120 days
  get × 1.2 (from 0.2 up).
- an `addCandidates` track × (1 + weight).

### 4. Each pick

What the session has learnt multiplies the base:
- skips: e^(−0.45 · artist pressure − 0.6 · Σ genre pressure²);
- thumbs down: the artist × 0.02, a guest × 0.25, not fading;
- variety: an artist heard lately counts against itself,
  ÷ (1 + 0.5 · their tracks in the last 30). A just-liked artist is
  exempt; on an artist station the seed artist is exempt too, as the cap
  holds it;
- likes: × (1 + 1.5 · similarity to the liked track), fading by half every
  15 tracks.

Of the tracks the rules allow, the best K (8 + 52 · adventurousness: 8 …
60) are drawn from at random in proportion to their score. It is never the
argmax, so the same seed differs each time it is started with another
random seed, and is the same for the same one.

The rules:
- never a track twice in a session;
- at least `artistSeparation` (3) tracks between two by one artist. A guest
  counts as that artist, so "A; B" keeps B away too;
- never two from one album back to back;
- nothing heard in the last `noRepeatHours` (the `recentlyPlayed` passed in,
  and the taste's last-heard times);
- on an artist, song or album station, the seed's own artist at most one in
  five, after the first.

When nothing passes, the station looks wider first: the whole library, the
tracks outside its neighbourhood at a closeness of 0.03, taste deciding.
Then the rules loosen, in this order:
1. separation halved, and the cap off;
2. separation and the album rule off;
3. recently heard allowed;
4. repeats allowed, of tracks not among the last half of the library (at
   most 50 back).

A station never ends on its own: a library of one song repeats it. Only an
empty library, or one where every song has a thumbs down, gives fewer
tracks than asked. The test of a library of four artists with two songs
each, two of them heard an hour ago, gets exactly this order: the six
others first, then the two heard lately, then repeats.

### 5. Listening

`record(_:)` changes the session; the scores are worked out again before
the next pick (2.2 ms on 20 000 tracks), so `returnUnplayed` + `next` right
after a skip already reflects it.

- **Heard to the end** (`.finished`, or `.skipped` late enough to count as
  completed): the profile moves toward it. Its genres and artist go into a
  drift that takes at most 30% of the profile, 0.3 · (1 − e^(−accepted/6)):
  the seed always keeps 70%. Pressure on its genres and artist eases.
- **Skip** (left within 30 s, or half of a short track): its artist gets
  pressure 1 (a guest 0.4). Each of its genres gets pressure by how much it
  set the track apart from what the station plays now: one minus its share
  of the station's best 300. Skipping Shoegaze on Rock Radio says "less
  Shoegaze", not "less Rock", since every song there is Rock. The pressure
  counts by its square: one skip of a sub-genre is worth about 0.8, three
  about 0.15. It fades 2% a track, half in 34 tracks (about two hours).
  Tracks reached through a skipped artist ("Sounds like X" just after X was
  skipped) get e^(−0.25 · X's pressure) of it.
- **Thumbs up**: a stronger pull (as three completions). Its artist and its
  graph neighbours, and its genres at half that, are lifted in the next
  picks.
- **Thumbs down**: the track is gone for the session. Its artist is all but
  gone (× 0.02), its genres get 1.5 skips' pressure.
- `addCandidates(ids, weight:, reason:)`: Jellyfin's Instant Mix, Last.fm's
  similar tracks. In the order given, the first a little more.
- `settings` can change at any time: the next `next` builds the profile
  again for the new adventurousness.

## Measured

### The made-up library

`RadioFixtures.swift`: 60 artists in 8 genre clusters (Rock, Electronic,
Jazz, Hip-Hop, Classical, Folk, Pop, Metal), each with three sub-genres,
some artists with a second sub-genre or the next cluster's genre; 1 819
tracks on 2–4 albums each; a guest on 15% of tracks (80% from the same
cluster); eras per cluster.

The made-up listener loves Rock and Electronic and likes Jazz (about 55% of
it heard). They play a little Folk and Pop and hardly any Hip-Hop, Classical
or Metal. They have favourites, play counts, and 400 events of history over
two months.

Artist stations: 16 seeds (two of every cluster) × 3 random seeds × 50 picks.
"Coherent" counts a pick by an artist of the seed's cluster, or by or with
the seed artist or a graph neighbour. "In cluster" counts the cluster of the
artist the pick is filed under, for seeds the listener plays and seeds they
do not.

| adventurousness | coherent | in cluster (played / unplayed seeds) | unheard | favourites | distinct artists in 50 | seed artist's share | separation / repeat / album violations |
|---|---|---|---|---|---|---|---|
| 0 | 1.000 | 0.970 (0.990 / 0.938) | 0.340 | 0.073 | 7.8 | 0.184 | 0 / 0 / 0 |
| 0.35 (default) | 1.000 | 0.961 (0.978 / 0.933) | 0.441 | 0.069 | 8.6 | 0.184 | 0 / 0 / 0 |
| 0.7 | 1.000 | 0.939 (0.959 / 0.904) | 0.619 | 0.060 | 9.5 | 0.183 | 0 / 0 / 0 |
| 1 | 0.939 | 0.787 (0.791 / 0.780) | 0.822 | 0.021 | 15.0 | 0.170 | 0 / 0 / 0 |

The dial does what it says. At 0 the station stays near and known (97% in
cluster, a third unheard). At 1 it goes further out (79% in cluster, through
second-degree neighbours and related genres) with twice the artists and 82%
unheard. A cluster has 7–8 artists, so 8.6 distinct in 50 is most of the
neighbourhood.

Listening (adventurousness 0.35 unless said):

| What | Without | After |
|---|---|---|
| Thumbs down on a song by artist X (6 picks in): X's songs in the next 30, average over 48 stations | 5.33 | 0.02 |
| Three skips of Shoegaze on Rock Radio: Shoegaze's share of the next 30, 12 runs | 0.364 | 0.147 |
| Thumbs up at 0.6: the liked artist's share of the next 15 (separation 3 holds any artist to 0.25 at most) | 0.154 | 0.185 |
| … the liked artist and its close neighbours (edge ≥ 0.5) | 0.448 | 0.498 |
| … picks that say "Because you liked" | 0 | 0.363 |

Every kind of seed, 200 picks each: 200 tracks, no repeats, no separation
violations. The first track and the reasons of the first 50:

| Seed | First | Reasons in 50 |
|---|---|---|
| track | the seed track | similar artist 19, genre 16, by artist 9, favourite 5, seed 1 |
| artist | by the artist, affinity 0.85 | similar artist 33, by artist 10, genre 5, favourite 2 |
| album | from the album | similar artist 25, by artist 19, genre 5, seed 1 |
| genre (Jazz) | Jazz, affinity 0.91 | genre 44, favourite 6 |
| decade (1990s) | from 1999 | era 50 |
| collection (12 favourites) | from the playlist | by artist 20, similar artist 13, genre 12, seed 3, favourite 2 |
| personal | affinity 0.94 | favourite 49, rediscover 1 |
| discovery | familiarity 0.00 | discovery 50 |
| favorites | a favourite | favourite 48, genre 2 |

### Speed

20 000 tracks, 20 000 history events, on this machine (Xeon at 2.1 GHz, 4
cores; one core used). Two libraries: 600 artists and 32 genres, and a
harder one with 1 914 artists and 295 genres, as real libraries have.

Release build (`KIT_DIR=… dev/kit-test.sh -c release -Xswiftc -enable-testing --filter RadioPerformance`):

| | 600 artists | 1 914 artists | bar |
|---|---|---|---|
| `LibrarySnapshot(tracks:)` | 90 ms | 136 ms | 500 ms |
| `TasteProfile(...)` | 11 ms | 13 ms | |
| `SimilarityGraph.fromLibrary` | 14 ms | 83 ms | |
| graph as JSON: size, encode, decode | 634 kB, 20 ms, 18 ms | 2.4 MB, 72 ms, 59 ms | |
| session built + first `next(5)`, median (max) | 4.3 ms (4.9) | 4.7 ms (5.7) | 300 ms |
| `next(5)`, median (max) | 0.4 ms (0.9) | 0.3 ms (1.3) | 50 ms |
| feedback + `returnUnplayed` + `next(5)`, median (max) | 2.3 ms (4.8) | 2.2 ms (4.1) | |

Debug build (what `swift test` runs by default), 1 914 artists: snapshot
232 ms, graph 802 ms, session + first five 124 ms, `next(5)` 6.9 ms,
feedback + next 111 ms. The tests hold debug to 12 times the bar.

How:
- The snapshot keys each distinct spelling once. The title index for `match`
  is built on the first `match`, behind a lock, as 20 000 NameKey titles
  take half a second on Linux.
- A session scores the whole library in one pass over arrays when its
  profile changes, and keeps the pool sorted. A pick walks it best first and
  stops once nothing further down can reach the K-th best.

The same random seed gives the same station in every process: nothing
depends on a Dictionary's order. The test server's listings below came out
the same in two separate runs.

### On the test server

`RadioRealLibraryFixture.swift`: the 358 tracks of `dev/jellyfin-test-server.sh`,
as Jellyfin 12.4 gave them, joined tags and all. `testFixtureMatchesTheLiveServer`
checks the fixture against the live server when `JELLYFIN_URL` is set: 358
of 358 the same. No listening history: taste plays no part here.

This library is small: 23 artists, mostly three to a genre cluster, with
guests across clusters. Three tracks between two by one artist then leave
every fourth song to someone outside the cluster. The radio picks that one
by the graph: a guest of the seed, or a neighbour of a neighbour.

**Velvet Static Radio**, adventurousness 0.35 (Velvet Static's neighbours:
Iron Meadow 0.59, Kalimba Sound System 0.26, The Lanterns 0.24, Nightdrive
0.22, Glass Animals Club 0.18):

```
 1. Glass Road — Velvet Static (Rock, Shoegaze, 1997) · More by Velvet Static
 2. Fire Tide — Iron Meadow (Rock, Hard Rock, 1979) · Sounds like Velvet Static
 3. Ocean Story — The Lanterns (Rock, Alternative, 1998) · More Rock
 4. Static Heart — Kalimba Sound System; Hexagon Lights (Electronic, House, 2014) · Sounds like Velvet Static
 5. Summer Road — Nightdrive (Electronic, Synthwave, 2015) · Sounds like Velvet Static
 6. Hollow Tide — Velvet Static; Iron Meadow (Rock, Shoegaze, 1997) · More by Velvet Static
 7. Wild Story — The Lanterns (Rock, Alternative, 1994) · More Rock
 8. Red Window — Kalimba Sound System (Electronic, House, 2013) · Sounds like Velvet Static
 9. Echo Garden — Glass Animals Club (Indie, Alternative, 2012) · Sounds like Velvet Static
10. Winter Dance — Iron Meadow (Rock, Hard Rock, 1983) · Sounds like Velvet Static
11. Northern Letters — Velvet Static (Rock, Shoegaze, 1991) · More by Velvet Static
12. Glass Dance — The Lanterns; Mira Lux (Rock, Alternative, 1994) · More Rock
13. Winter Line — Nightdrive (Electronic, Synthwave, 2015) · Sounds like Velvet Static
14. Electric Mirror — Iron Meadow (Rock, Hard Rock, 1984) · Sounds like Velvet Static
15. River City — Paper Harbour; Glass Animals Club (Alternative, Indie, 2006) · Sounds like Velvet Static
16. Lights Machine — Velvet Static; Kalimba Sound System (Rock, Shoegaze, 1997) · More by Velvet Static
17. Ghost Line — The Lanterns (Rock, Alternative, 1996) · More Rock
18. Fire Fields — Iron Meadow (Rock, Hard Rock, 1984) · Sounds like Velvet Static
19. Iron Road — Glass Animals Club (Indie, Alternative, 2014) · Sounds like Velvet Static
20. Night Waltz — Kalimba Sound System (Electronic, House, 2013) · Sounds like Velvet Static
```

Velvet Static plays every fifth song (the cap). Kalimba Sound System and
Nightdrive are there because they are on four of Velvet Static's records;
with Last.fm's edges they would give way to who sounds alike.

**Signal Dream Radio** (a song by "MC Polder; Lyric Engine"):

```
 1. Signal Dream — MC Polder; Lyric Engine (Hip-Hop, Nederhop, 2006) · Where the station started
 2. Hollow Dance — Concrete Poets (Hip-Hop, 1996) · Sounds like MC Polder
 3. Signal Garden — Clara Venn; Amsterdam Strings (Classical, Piano, 2004) · Sounds like Lyric Engine
 4. Glass Garden — Saskia de Wit (Jazz, Vocal Jazz, 2010) · Sounds like MC Polder
 5. Electric City — Lyric Engine (Hip-Hop, Rap, 2020) · More by Lyric Engine
 6. Quiet City — MC Polder (Hip-Hop, Nederhop, 2006) · More by MC Polder
 7. Lights Waltz — Concrete Poets (Hip-Hop, 2001) · Sounds like MC Polder
 8. Wild Road — Amsterdam Strings (Classical, 1995) · Sounds like Lyric Engine
 9. Quiet Window — Clara Venn (Classical, Piano, 2004) · Sounds like Lyric Engine
10. Rain Waltz — Lyric Engine (Hip-Hop, Rap, 2018) · More by Lyric Engine
```

(20 in the test output, 12 of them hip-hop. The server has three hip-hop
artists, so with separation and the cap about two songs in five go to
their guests: Lyric Engine and Amsterdam Strings share four songs, MC
Polder and Saskia de Wit three.)

**Jazz Radio**: 15 of 20 jazz, the most three jazz artists allow. About
every fourth song comes from the jazz artists' neighbours in the graph:
"Sounds like Saskia de Wit" for MC Polder (on two of her songs), "Sounds
like Miles Ahead Quartet" for Low Orbit.

**Listening, on The Lanterns Radio at 0.7.** The first eight:

```
1. Quiet Heart — The Lanterns; Mira Lux (Rock, Alternative, 1996) · More by The Lanterns
2. Electric Mirror — Iron Meadow (Rock, Hard Rock, 1984) · More Rock
3. Echo Machine — Velvet Static; Kalimba Sound System (Rock, Shoegaze, 1997) · More Rock
4. Summer Dream — Sunny Side (Pop, Dance, 2017) · Sounds like The Lanterns
5. Northern Heart — Mira Lux (Pop, Electronic, 2021) · Sounds like The Lanterns
6. Ghost Machine — The Lanterns; Paper Harbour (Rock, Alternative, 1994) · More by The Lanterns
7. Silver Parade — Glass Animals Club (Indie, Alternative, 2012) · Sounds like The Lanterns
8. Quiet Drive — Iron Meadow (Rock, Hard Rock, 1983) · More Rock
```

The listener gives "Electric Mirror" a thumbs down and skips both pop songs.
The queue after them is put back, and the next ten are chosen again:

```
 1. River Story — The Lanterns; Paper Harbour (Rock, Alternative, 1994) · More by The Lanterns
 2. Silver Dream — Glass Animals Club; Velvet Static (Indie, Alternative, 2012) · Sounds like The Lanterns
 3. Night Line — Sunny Side (Pop, Dance, 2023) · Sounds like The Lanterns
 4. Signal Sky — Old Mill Road; Neon Hearts (Folk, Americana, 1976) · Sounds like Mira Lux
 5. Velvet Machine — Paper Harbour (Alternative, Indie, 2003) · Sounds like The Lanterns
 6. Static Dream — The Lanterns (Rock, Alternative, 1996) · More by The Lanterns
 7. Echo Garden — Glass Animals Club (Indie, Alternative, 2012) · Sounds like The Lanterns
 8. Velvet Tide — Velvet Static; Nightdrive (Rock, Shoegaze, 1997) · More Rock
 9. Blue Room — June Hollow (Folk, Indie, 2021) · Sounds like Glass Animals Club
10. Electric Story — Paper Harbour (Alternative, Indie, 2006) · Sounds like The Lanterns
```

No Iron Meadow, and one pop song instead of two: the third and fourth
slots, where separation has blocked every rock artist in this library, go
to the least-skipped of what is left.

## What was tried

The numbers above are the last of these rounds; each is in the test output
of its time.

1. **First version.** Coherence was the same at adventurousness 0, 0.35 and
   0.7 (0.95), and only fell at 1. Three skips of Shoegaze took its share
   from 0.38 to 0.22, and "Because you liked" was on 71% of the picks after
   a like.
2. **Skips as pressure that counts by its square**, instead of a factor per
   skip. With the genre's specificity as the weight, Shoegaze still only went
   0.37 → 0.21: in a 60-artist library "Rock" (IDF 1.79) is barely commoner
   than "Shoegaze" (2.14), so every skip pushed on Rock as hard. Weighting by
   how much a genre sets the track apart from the station's own best 300
   gave 0.37 → 0.18. With the fade slowed from 3% to 2% a track, 0.36 → 0.15.
3. **The dial.** The incoherent picks at 0 were tracks where a neighbour
   was only a guest. A guest now counts 0.7 instead of 0.85, and the metric
   counts a pick with a neighbour on it. Then closeness was scaled by genre
   fit near the familiar end. Half at 0 gave in cluster 0.92 / 0.92 / 0.89 /
   0.71; 60% gave 0.98 / 0.96 / 0.94 / 0.79 with the other changes. The
   familiarity factor went from nine times to four. At nine, the familiar
   end was less in cluster than the default (0.864 against 0.880): it pulled
   a station from an artist the listener never plays toward the artists they
   do. At four, 0.879 against 0.885, and the genre fit then made 0 the
   tightest.
4. **Variety.** The variety penalty went from 0.3 to 0.5 a recent track:
   distinct artists 8.7 → 9.6 at 0.35 then. That was before the guest
   change took some neighbours away; it is 8.6 now.
5. **The test server** showed what the made-up library did not. Guests
   across genres made Velvet Static Radio 40% electronic, and guest spots
   made Jazz and Nederhop "related". The changes: genres from an artist's
   own records, a guest edge without a shared genre at 40%, and genre
   stations reaching out through their artists' neighbours.
6. **Likes** barely moved the liked artist (0.152 → 0.177): the variety
   penalty from the liked track itself ate the boost. A just-liked artist
   is now exempt and the boost is 1.5 instead of 1.2: 0.154 → 0.185, near
   the 0.25 the separation rule allows. "Because you liked" now needs the
   like's artist, or a neighbour of 0.55 or more, to be what lifted the
   pick: 36% of the next 15.
7. **Instant Mix candidates** at weight 1 never made it onto a jazz station:
   the genre fit and era scaled them down like any other track. They are now
   exempt from both, and their weight raises the score up to twice.
8. **Thumbs down** at × 0.08 let Iron Meadow back three songs later on the
   test server, when separation had blocked the rest; × 0.02 does not.
9. **Short tracks**: `PlayOutcome.of` counted "all but the last 20 s" as
   heard, so on the test server's 6-second tones every skip was a
   completion. That rule now applies only to tracks longer than 40 s.

## Building on it

- **Mixes** (`MixGenerator`). A `RadioSession` with a `.collection` seed
  (the tracks a mix is about) and `randomSeed: SplitMix64.stableSeed("daily-1-2026-11-08")`
  is a daily mix that is the same all day and new tomorrow, with the
  radio's rules for free. `next(40)` gives 40 tracks.
  - `TasteProfile.topArtists/topGenres/topTracks/lastHeard/familiarity`
    give what "On Repeat", "Rediscover" and "Deep Cuts" need.
  - `SimilarityGraph.weight(_:_:)` and `similarArtists` give the clusters
    for Daily Mix 1…6.
  - `Station(seed:snapshot:)` names any station; `Station.id(for:)` gives
    its id without building it.
- **Last.fm** (`SimilarityService`):
  - `addArtistEdge(asked, similar, weight: match)` for each similar artist
    the library has (`snapshot.matchArtist`); the asked artist then counts
    in `enrichedArtistCount`.
  - `addTrackEdge(from:to:weight:)` for similar tracks (`snapshot.match`).
  - Merge onto `SimilarityGraph.fromLibrary(snapshot)`.
  - Last.fm's `match` is 0 … 1, and library edges are rarely above 0.8, so
    Last.fm's strong links win.
- **The app** (`RadioController`):
  - after a skip or a thumbs, `record`, then `returnUnplayed(queued ids)`,
    then `next(n)`;
  - after a song heard to the end, `record(.finished)` (no need to return
    anything);
  - pass `history.trackIDs(since: now − noRepeatHours)` as `recentlyPlayed`;
  - Instant Mix at a weight of about 0.5, Last.fm's similar tracks about
    0.8, both via `addCandidates`;
  - building a session and its first tracks takes about 5 ms on 20 000
    tracks: it can happen on the main actor, but the snapshot and the graph
    (100–220 ms together, release) should not.

## Limits

- The library alone knows only tags, guests and years. On a library with
  few artists per genre, a station reaches its guests' genres early (the
  listings above). Last.fm's edges are what make "sounds like" right.
- No audio analysis: two songs of one artist are alike, whatever they sound
  like.
- Adventurousness is not remembered per station; that is the app's.
