# The radio: how it chooses

The photographer, 8 November 2026: "ik vind vooral de radiofunctie echt
belangrijk". A station starts from anything: a song, an artist, an album, a
genre, a decade, a playlist or mix, the listener's own taste, the new, the
loved. It plays for as long as it is left on, stays near its seed without
being the same, keeps its rules, and listens: a skip, a thumbs up or down, or
a song heard to the end changes what comes next at once.

Code: `JukeboxKit/Sources/JukeboxKit/Radio/` and
`Library/LibrarySnapshot.swift`, Foundation only. Every number here is
printed by a test in `JukeboxKit/Tests/JukeboxKitTests/Radio*.swift`
(`dev/kit-test.sh --filter Radio`; lines starting `RADIO-EVAL`, and
`RADIO-CRITIC` for "What it does when …").

## How a station picks the next song

One dial runs through all of it: adventurousness, 0 (near and known) to 1
(further out and new), 0.35 by default.

1. **The seed becomes a profile**: weighted artists, genres, an era, and for
   some seeds tracks of their own. The seed artists' neighbours in the
   similarity graph join it; further out, their neighbours too.
2. **Every track gets a closeness** to that profile, 0 … 1: its best match
   (by artist, genre, track or era) plus a quarter of the second best. The
   best match is also the reason shown under it in Up Next.
3. **Closeness becomes a score**, with the listener's taste, how familiar
   the song is, and how long since it was heard.
4. **The session adjusts the score** for what it has learnt: skips, thumbs,
   likes, and artists heard lately.
5. **The rules decide what may play now**: no song again too soon, three
   tracks between two by one artist, never one album back to back, the seed
   artist at most one in five, nothing thumbed down.
6. **One track is drawn at random** from the best 8 to 60 left (more at a
   higher dial), in proportion to score.
7. **When nothing is left**, the station looks wider, then loosens the rules
   one at a time. It never stops on its own.
8. **Feedback counts at once**: the scores are worked out again before the
   next pick.

## The parts

| Type | What it is |
|---|---|
| `LibrarySnapshot` | The library at one moment, indexed by track number: each track's artists, genres, album, year and song; the tracks of each artist, genre, album, decade and song; how specific each genre is; which genres go together. Made once, read by everything. |
| `TasteProfile` | What the listener likes, −1 … 1, for every track, artist and genre, and how familiar each track is, 0 … 1. From Jellyfin's favourites and play counts and this device's history. |
| `SimilarityGraph` | Who sounds like whom: artists (and, from Last.fm, tracks) with weighted edges. From the library alone (`fromLibrary`), merged with Last.fm's when there is a key. Codable, kept on disk. |
| `Station` | A seed with a stable id ("artist-radiohead"), a title ("Radiohead Radio") and up to four covers. |
| `RadioSession` | One station playing: hands out tracks a few at a time, takes feedback, takes tracks back to choose again. A value type; `RadioController` in the app holds one. |
| `SplitMix64` | The radio's own random numbers, so a seed gives the same station everywhere (and the mixes can use the date as a seed). |

## The library as the radio reads it

### Names

Jellyfin 12.4 gives a joined tag as one name. On the test server 92 of 358
tracks have an artist like "MC Polder; Lyric Engine", and 294 a genre like
"Hip-Hop; Nederhop". The snapshot splits them:
- artists on ";", "|" and "feat." / "ft." / "featuring"; "&", "and" and "/"
  stay inside a name ("Simon & Garfunkel" and "AC/DC" are one artist);
- genres on ";" and "|"; "/" stays inside ("Singer/Songwriter" is one genre).

A part gets the id that name has elsewhere in the library, usually as an
album artist. "Various Artists" is nobody: on a compilation the song is by
its performer. A name NameKey folds to nothing ("!!!", "†‡†", punctuation
only) keeps its own lower-case spelling as its key, so each is an artist
and its station opens with them. With the empty key such a band had no
artist at all, and "!!! Radio" opened with someone else's song.

After splitting, the test server has its true 23 artists and 23 genres.
`snapshot.artistKeys(of:)`, `primaryArtistKey(of:)` and `genreKeys(of:)`
give the split keys, precomputed. `Track.artistKeys` runs NameKey on every
call (about 25 µs a name on Linux) and does not split. `PlayEvent(track:…)`
stores the split keys, so the history of a song that has left the library
still finds its artists.

An artist's genres and era come from the records filed under them; a guest
spot is someone else's record. MC Polder guesting on a jazz trio's album does
not make him jazz. Measured: with guest spots counted, Jazz and Nederhop came
out as "related genres" on the test server, and Jazz Radio played four
Nederhop songs in twenty.

### Songs

Tracks filed under one artist with one title are one song: "Karma Police" on
OK Computer, on the best-of, "(Remastered 2011)", "[Live]" or " - Single
Version". A part in brackets or after " - " is left out only when it names
the recording (remaster, live, version, edit, demo, mono, acoustic, single,
deluxe, feat., …). "Symphony No. 5 - II. Andante" stays apart from "- I.
Allegro", and a remix is a song of its own. The key is plain Swift, as
NameKey.title costs 25 µs a call on Linux.

The radio and the mixes play a song once, whichever recording. Its
familiarity is that of its most played recording, its last play the latest
of them, and a thumbs down or a skip counts for all of them. The test
server's 358 tracks are 351 songs (its made-up titles repeat within an
artist seven times).

### A genre the server lists joined

Jellyfin's /MusicGenres lists a joined tag as one genre: 19 of the test
server's 23 are like "Rock; Shoegaze", where the snapshot has "Rock" and
"Shoegaze". A genre seed the snapshot does not know is split the same way
(";" and "|"), and the station is the parts the library has
(`LibrarySnapshot.genreSeed`):
- each part weighted by how specific it is (`genreSpecificity`), as a tag
  goes from the general to the particular: "Rock; Shoegaze" is rock 0.40
  and shoegaze 0.60 on the test server;
- the parts' artists, by those weights, lead to their neighbours, as on any
  genre station;
- it opens with one of the tag's own songs, which carry every part;
- it is named after the most specific part, "Shoegaze Radio" ("Rock;
  Shoegaze Radio" reads as a tag), with every
  part in the subtitle ("Shoegaze and Rock from your library"). The id stays
  the seed's ("genre-rockshoegaze").

With none of the parts in the library, it is Your Station under the seed's
name. With one genre, every weight is 1 and it is the station it always was.

The test server's 19 joined genres × 10 random seeds × 20 picks
(RadioRealServerTests):

| | opens in the tag | picks with the part named | with any part |
|---|---|---|---|
| before: the seed's key only (Your Station) | 7 of 190 | 0.00 | 0.14 |
| the most specific part alone | 160 of 190 | 0.37 | 0.73 |
| the parts, by specificity | 190 of 190 | 0.35 | 0.81 |

In the 14 whose most specific part is one artist's, that artist plays every
fourth song, as often as separation allows: "Rock; Shoegaze" is Velvet
Static at 0.25 and rock or shoegaze at 0.72 ("Shoegaze" alone 0.69). The
lowest, "Classical; Piano", is at 0.47, with two classical artists for every
four slots. The live server's /MusicGenres has the same 23 names, and a
station from each opens in its tag.

## Taste

Each track's evidence, `e`:
- a favourite: +2;
- a play count `p`: +0.8 · log₂(1 + p), fading with the last play (a
  90-day half-life, never below 35%: forty plays two years ago is still
  liking);
- each event in this device's history: completed +1, partial +0.3, skipped
  −0.8, liked +3, disliked −4, fading with a 21-day half-life (measured: a
  completion three weeks ago counts 0.51 of one today; the test allows
  0.45 … 0.55). A skip of a song the listener knows is "not now" (below).

| | Formula |
|---|---|
| track affinity | `tanh(e / 3)` |
| familiarity | `1 − e^(−n/3)`; a favourite at least 0.6 |

`n` is plays: the larger of Jellyfin's count and this device's completions
(the player reports each completion to Jellyfin, so not both), plus half a
play for each partial or like and a quarter for each skip or thumbs down.

Artists and genres add up their tracks' evidence: the artist a track is
filed under fully, a guest half, dislikes at half (one bad song is not a bad
artist). History of tracks no longer in the library still counts for their
artists and genres. The total is scaled by the listener's own 90th
percentile (75th for genres), so the artists they like most come out near 1
whether they have played a hundred songs or a hundred thousand.

Everything is clamped before use: negative play counts, dates in the future,
NaN seconds. Nothing comes out NaN; the test feeds it all of these.

A thumbs down also keeps the song off the radio. A song whose last thumbs
on this device was down, in the last half year (the mixes' rule;
`thumbsDownDays`, 183), is left out of every station except a song station
started from it. A later thumbs up lifts it. As evidence alone (affinity
−0.87, a score × 0.44) a thumbs down was not enough ("What it does when …").

**Not now.** A thumbs down is "never" (above). A skip of a well-known song
(familiarity 0.6 or a favourite, counted without its skips) is "not now":
it counts × the clock's nearness (below) of its hour to now's, so against
the song in that slot and hardly elsewhere, and its last-heard time rests it
(the freshness, back to 0.84 after three days). Measured: a favourite
skipped Tuesday 08:00 is at 0.883 that evening (0.884 unskipped; 0.812
before this change), in Your Station's pool and allowed; the next Tuesday
morning 0.813. Its artist 0.423 (0.423). A song never heard, skipped, counts
−0.8 everywhere as before. A skip inside a session works as it did.

`topArtists`/`topGenres` leave out the disliked and put the never-heard
last, biggest first, so a new listener still gets a list. `topTracks` and
`lastHeard` are there for the mixes.

## The clock

"leren van wanneer ik welke muziek op prijs kan stellen en daar mijn 'your
station' op afbaken" (the photographer, 18 November 2026; the research is
`build/research/radio.md`). Only Your Station reads it: Discovery is about
the new, not the hour, and every other station has a seed of its own.

In `TasteData`, for `now` (the device's calendar):
1. Each history event gets a nearness `k = e^(2·(cos(2π·Δhour/24) − 1))`
   (about ±3 hours, round over midnight), × 0.3 on the other kind of day
   (weekday, weekend), on top of the 21-day fade.
2. Per artist and genre: its share of what was heard (positive outcomes)
   near now, against its share at the other hours. `L = ln((near + 0.05) /
   (rest + 0.05))`, at most 1, and 0 below ln 1.6.
3. `λ = n / (n + 12)`, `n` the sessions near now (45 minutes apart starts a
   new one; each counts once, by its nearest event).
4. Your Station chooses and weighs its 30 artists, 12 genres and 300 songs
   by affinity × `e^(λ·L)`, and its scores × `e^(λ·L)` of the track (its
   artist's, or its genres' on average, the larger).

When `λ·L` of a pick is 0.3 or more, its reason is "Often on weekday
mornings" (`PickReason.timeOfDay(TimeSlot)`, in Home's hours: morning from
5, afternoon 12, evening 17, night 21). `TasteProfile.timeFact` (in the app
`RadioController.yourStationFact`) is "Weekday mornings: Jazz and Vocal
Jazz", for Your Station's card: with λ 0.4 or more, and a genre at λ·L 0.3
in a sixth of the slot's plays; else nil.

Measured (`RadioClockTests`): a made-up listener, eight weeks, 1 213
events, a session most workday mornings (7–10, seven in ten all Jazz) and
weekend nights (21–2, seven in ten all Electronic), and one or two at any
hour. Your Station, 20 seeds × 30 picks, against the same without the clock:

| | Time-blind | Clock | Target |
|---|---|---|---|
| Jazz, Tuesday 08:00 (λ 0.62) | 0.177 | 0.398 (× 2.25) | ≥ 2× |
| Electronic, Saturday 23:00 (λ 0.47) | 0.412 | 0.558 (× 1.36) | ≥ 2×, not met: 0.82 is nearly all of it |
| Wednesday 15:00, any cluster | | at most 0.010 apart | ±0.03 |
| no pattern, 2 and 8 weeks, Tuesday and Saturday every 3 hours | | at most 0.027 apart | ±0.03 |
| "Often on …" | 0 | 239 and 183 of 600; 0 at 15:00 and without a pattern | |
| the fact | | both slots; none at 15:00 or without a pattern | |

Jazz on Tuesday 08:00 by weeks of history: 0 weeks 0.090 → 0.090 (λ 0),
1 week 0.113 → 0.292 (λ 0.27), 2 weeks 0.127 → 0.315 (0.42), 4 weeks
0.153 → 0.353 (0.56), 8 weeks 0.177 → 0.398 (0.62). Most of the lift is
there after a week.

The genre of the last two weeks' 264 plays, from the six weeks before:
mean log-probability −1.464 time-blind, −1.414 with the clock (perplexity
4.32 → 4.11).

Its ceiling: tags, not sound; one device (the iPhone mixes walking and the
car); slots of a few hours; an artist with morning and night songs is one
artist. `TasteProfile` with 20 000 tracks and events: 26–31 ms (release).

## The similarity graph, from the library

An edge is worked out between every two artists that share a genre (each
artist meets only its genre-mates, through an inverted index). Three kinds of
evidence:

| Evidence | Weight |
|---|---|
| genres | a weighted Jaccard of their genre shares, each genre weighted by its specificity `ln(1 + artists / artists with the genre)`, times a confidence that grows with the specificity they share (full at a genre one artist in twenty has); at most 0.6, as tags are weaker evidence than Last.fm's listeners |
| guests | 0.45 for one track together, up to 0.65 for three or more, when they share some genre (genre similarity 0.25 or more); 40% of that when they share none: a friendship more than a likeness |
| era | up to 0.15 for the same median year, nothing ten years apart; only between artists who share a genre |

They combine as independent evidence does, `1 − (1−a)(1−b)(1−c)`. Each
artist keeps its 30 strongest edges; an edge stays when either end keeps it,
so the graph is symmetric. Edges under 0.03 are dropped.

Measured: in a library where everyone is Rock, two artists who are both
"Rock; Shoegaze" get 0.61, two who are only "Rock" 0.20. On the test server,
where guests often cross genres, Velvet Static's neighbours without the 40%
rule were Iron Meadow 0.69, Kalimba Sound System 0.65 and Nightdrive 0.56
(house, synthwave), and Velvet Static Radio was 40% electronic. With it,
Kalimba Sound System 0.26 and Nightdrive 0.22 sit beside The Lanterns 0.24.

`addArtistEdge(a, b, weight:)` (for Last.fm) keeps the heavier of two edges
and counts `a`, the artist asked about, in `enrichedArtistCount`.
`addTrackEdge` is one way. `merge` keeps the heavier edge and unions the
enriched set. Decoding is lenient: a cache missing a part opens with that
part empty.

## Each step in detail

### 1. The seed becomes a profile

| Seed | Artists | Genres, era | First track |
|---|---|---|---|
| `.track` | its artists (0.88, a guest 0.75) | its genres; its year ±5 | that track, always (even if just heard) |
| `.artist` | the artist (0.88) | their records' genres; their median year, spread from their years (≥ 4) | one of their best-liked, drawn from the top 3 and any within 85% of the best (up to 12) |
| `.album` | the album's artists by share | the album's genres and year | a best-liked track from it |
| `.genre` | none of its own; its artists (half their records or more) lead to their neighbours | the genre, and genres that go with it (0.1 + 0.5 · adventurousness of their link); a joined one ("Rock; Shoegaze") its parts by specificity | a best-liked track of the genre (of a joined one, with every part) |
| `.decade` | the listener's liked artists with songs in it | the listener's genres in that decade (taste-weighted) | a best-liked track from it |
| `.collection` | its artists by share | its genres and era; its own tracks get a channel of 0.6 | a best-liked track from it |
| `.personal` | the 30 artists liked most | the 12 genres liked most; the 300 liked tracks get a channel of their own | from the listener's top 30 |
| `.discovery` | as `.personal` | as `.personal` | near their taste, unheard |
| `.favorites` | the favourites' artists | the favourites' genres; every favourite a channel of 0.85 | a favourite |

Then the neighbours:
- a seed artist's neighbour: the seed artist's weight × the edge × 0.95;
- a neighbour's neighbour: × the second edge × 0.8 × adventurousness.

A neighbour remembers whom it came through, for "Sounds like …". A seed not
in the library (an artist since removed) plays as Your Station under its own
title: a station always starts.

### 2. Closeness

Every track, in one pass over plain arrays, gets the best of its channels
plus a quarter of the second best, at most 1:

| Channel | Value |
|---|---|
| artist | the profile's weight of its artist; a guest counts 0.7 of that |
| genre | how much of the profile's genre it covers, rarer genres counting more, a little less for genres of its own the profile lacks; scaled so the best-covering track is 0.7 (0.9 on a genre station) |
| track | the seed track 1, Last.fm's similar tracks 0.35 … 0.95, `addCandidates` up to 0.9 × weight, collection members 0.6, favourites on Loved 0.85 |
| era | on a decade station, 1 inside the decade, falling off outside with a spread of 1 + 4 · adventurousness years; elsewhere the year scales closeness by 0.65 … 1 (0.85 when unknown) |

Near the familiar end a track must also sound like the station: closeness is
scaled by its genre fit. A track with no fit keeps 40% at adventurousness 0,
61% at 0.35, and all of it at 1. Instant Mix, Last.fm and similar-track
candidates skip this and the era: they judge how a track sounds better than
tags can.

The winning channel is the reason under the track in Up Next:
- artist: "More by X" (the seed's own) or "Sounds like X" (the artist it
  came through). An artist link three quarters as strong as the genre fit
  wins the reason, as who it is like says more than "More Rock";
- genre: "More Shoegaze" (the track's most telling genre);
- track: "Like “Song”", "From Jellyfin’s mix", or the reason given to
  `addCandidates`;
- era: "From the 1990s".

Taste gives the reason only where taste is the point:
- Your Station: "Often on weekday mornings" when the clock lifted it,
  else "One of your favourites" (a heart, or affinity 0.6, about eight
  recent plays), "Not heard in a while";
- Discovery: "New to you";
- Loved: "One of your favourites";
- a favourite on a genre station below 0.5: "One of your favourites".

A like that lifted a track by its artist (or a close neighbour, 0.55 or
more) gives "Because you liked “Song”".

### 3. The score

`base = closeness^γ × e^(taste) × familiarity × freshness`

| Term | Value |
|---|---|
| γ, how sharply closeness counts | 2.4 − 1.8 · adventurousness (2.4 … 0.6) |
| taste | (1.2 − 0.7a) · track affinity + (0.5 − 0.2a) · artist affinity + 0.2 · genre affinity |
| familiarity | e^(1.4 · (1 − 2a) · (familiarity − 0.35)): up to four times for a well-known song at 0, the other way round at 1. Discovery: e^(−(3 + 2a) · (familiarity − 0.35)), favourites × 0.15 |
| freshness | 1 − 0.75 · 2^(−hours since heard / 48): heard half a day ago 0.37, a week ago 0.93. Known songs (familiarity 0.6 up) not heard for 120 days × 1.2 |
| an `addCandidates` track | × (1 + weight) |

(`a` is adventurousness.)

### 4. Each pick

What the session has learnt multiplies the base:

| | Factor |
|---|---|
| skips | e^(−0.45 · artist pressure − 0.6 · Σ genre pressure²) |
| thumbs down | the artist × 0.02, a guest × 0.25; does not fade |
| variety | ÷ (1 + 0.5 · the artist's tracks in the last 30). A just-liked artist is exempt; so is the seed artist on a track, artist or album station, as the cap holds it |
| likes | × (1 + 1.5 · similarity to the liked track), fading by half every 15 tracks |

Of the tracks the rules allow, the best K (8 + 52 · adventurousness: 8 …
60) are drawn from at random in proportion to their score, never the
argmax. A seed sounds different each time it starts with another random
seed, and the same for the same one. Tracks that score the same come in the
session's own order (from its random seed): when nothing is known of the
listener most of a library ties, and the library's order made every
station open the same way (see "What it does when …").

The rules:
- a song (any of its recordings) plays again in a session only after
  `noRepeatHours` of music (at least 3) have played since. It is then back
  at 0.4 × its freshness (0.15 after 12 hours, 0.25 after 48), so a song
  near the seed beats a new one far from it, and a new one near beats it;
- at least `artistSeparation` (3) tracks between two by one artist. A guest
  counts as that artist, so "A; B" keeps B away too;
- never two from one album back to back;
- nothing heard in the last `noRepeatHours` (the `recentlyPlayed` passed in,
  and the taste's last-heard times);
- on an artist, song or album station, the seed's own artist at most one in
  five, after the first;
- never a song thumbed down, in this session or before (see Taste).

When nothing passes, the station first looks wider: the whole library, the
tracks outside its neighbourhood at a closeness of 0.03, taste deciding.
Then the rules loosen one at a time:
1. the cap off (with four artists, separation alone makes it one in four);
2. separation halved;
3. separation off;
4. the album rule off;
5. recently heard allowed.

Only then do songs of this session come back before `noRepeatHours`, and
every rule is tried again from the top with them. Eligible: a song that more
than all but four of the library came after (or, if nothing then keeps the
rule of that level, half of it; at most 50), the longest unheard by far the
likeliest (by the fourth power of how far back). A skipped song comes back
only at the very last.

A library of one song repeats it. Only an empty library, or one where every
song has a thumbs down, gives fewer tracks than asked. A library of four
artists with two songs each, two heard an hour ago, plays in exactly this
order: the six others, then the two heard lately, then repeats.

### 5. Listening

`record(_:)` changes the session, and the scores are worked out again before
the next pick (2.2 ms on 20 000 tracks), so `returnUnplayed` + `next` right
after a skip already reflects it.

- **Heard to the end** (`.finished`, or `.skipped` late enough to count as
  completed): the profile moves toward it. Its genres and artist go into a
  drift of at most 30% of the profile, 0.3 · (1 − e^(−accepted/6)), so the
  seed always keeps 70%. Pressure on its genres and artist eases.
- **Skip** (left within 30 s, or half of a short track): its artist gets
  pressure 1 (a guest 0.4). Each of its genres gets pressure by how much it
  set the track apart from what the station plays now: one minus its share
  of the station's best 300. Skipping Shoegaze on Rock Radio says "less
  Shoegaze" and leaves Rock alone, since every song there is Rock. Pressure
  counts by its square: one skip of a sub-genre is worth about 0.8, three
  about 0.15. It fades 2% a track, half in 34 tracks (about two hours).
  Tracks reached through a skipped artist ("Sounds like X" just after X was
  skipped) get e^(−0.25 · X's pressure) of it, times √ of X's thumbs-down
  factor when X was thumbed down.
- **Thumbs up**: a stronger pull (as three completions). Its artist and its
  graph neighbours, and its genres at half that, are lifted in the next
  picks.
- **Thumbs down**: the song is gone, and stays gone (see Taste). Its artist
  is all but gone (× 0.02); its genres get 1.5 skips' pressure. On a song,
  artist or album station the artist it is named after gets only × 0.12,
  and the artists reached through them keep their weight: one of
  Radiohead's songs thumbed down on Radiohead Radio is about the song, and
  everyone near is reached through Radiohead (measured in "What it does
  when …").
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
cluster); eras per cluster. The made-up listener loves Rock and Electronic
and likes Jazz (about 55% of it heard), plays a little Folk and Pop and
hardly any Hip-Hop, Classical or Metal. They have favourites, play counts,
and 400 events of history over two months.

**Artist stations**: 16 seeds (two of every cluster) × 3 random seeds × 50
picks. "Coherent" counts a pick by an artist of the seed's cluster, or by or
with the seed artist or a graph neighbour. "In cluster" counts the cluster
of the artist the pick is filed under, for seeds the listener plays and
seeds they do not.

| adventurousness | coherent | in cluster (played / unplayed seeds) | unheard | favourites | distinct artists in 50 | seed artist's share | separation / repeat / album violations |
|---|---|---|---|---|---|---|---|
| 0 | 1.000 | 0.971 (0.990 / 0.939) | 0.339 | 0.075 | 7.8 | 0.184 | 0 / 0 / 0 |
| 0.35 (default) | 1.000 | 0.962 (0.979 / 0.933) | 0.440 | 0.068 | 8.6 | 0.184 | 0 / 0 / 0 |
| 0.7 | 1.000 | 0.937 (0.957 / 0.902) | 0.619 | 0.058 | 9.7 | 0.182 | 0 / 0 / 0 |
| 1 | 0.941 | 0.791 (0.793 / 0.787) | 0.815 | 0.020 | 15.0 | 0.168 | 0 / 0 / 0 |

At 0 the station stays near and known (97% in cluster, a third unheard). At
1 it goes further out (79% in cluster, through second-degree neighbours and
related genres) with twice the artists and 82% unheard. A cluster has 7–8
artists, so 8.6 distinct in 50 is most of the neighbourhood.

**Listening** (adventurousness 0.35 unless said):

| What | Without | After |
|---|---|---|
| Thumbs down on a song by artist X (6 picks in): X's songs in the next 30, average over 48 stations | 5.25 | 0.02 |
| Three skips of Shoegaze on Rock Radio: Shoegaze's share of the next 30, 12 runs | 0.369 | 0.128 |
| Thumbs up at 0.6: the liked artist's share of the next 15 (separation 3 holds any artist to 0.25 at most) | 0.154 | 0.185 |
| … the liked artist and its close neighbours (edge ≥ 0.5) | 0.448 | 0.500 |
| … picks that say "Because you liked" | 0 | 0.348 |

**Every kind of seed**, 200 picks each (about 13 hours): 200 tracks, no
repeat in the first 150 and none within 12 hours of music, no separation
violations. The first track and the reasons of the first 50:

| Seed | First | Reasons in 50 |
|---|---|---|
| track | the seed track | similar artist 19, genre 15, by artist 9, favourite 6, seed 1 |
| artist | by the artist, affinity 0.85 | similar artist 32, by artist 10, genre 6, favourite 2 |
| album | from the album | similar artist 25, by artist 20, genre 4, seed 1 |
| genre (Jazz) | Jazz, affinity 0.91 | genre 43, favourite 7 |
| decade (1990s) | from 1999 | era 50 |
| collection (12 favourites) | from the playlist | by artist 21, genre 12, similar artist 12, seed 3, favourite 2 |
| personal | affinity 0.94 | favourite 50 |
| discovery | familiarity 0.00 | discovery 49, by artist 1 |
| favorites | a favourite | favourite 47, by artist 2, genre 1 |

### Speed

20 000 tracks and 20 000 history events, on a Xeon at 2.1 GHz, 4 cores, one
used. Two libraries: 600 artists and 32 genres, and a harder one with 1 914
artists and 295 genres, as real libraries have. Also 50 000 tracks of 3 337
artists and 432 genres (RadioCriticTests).

Release build (`KIT_DIR=… dev/kit-test.sh -c release -Xswiftc -enable-testing --filter "RadioPerformance|RadioCriticTests.testFiftyThousand"`):

| | 600 artists | 1 914 artists | 50 000 tracks | bar |
|---|---|---|---|---|
| `LibrarySnapshot(tracks:)` | 102 ms | 162 ms | 343 ms | 500 ms (20 000) |
| `TasteProfile(...)` | 11 ms | 14 ms | 27 ms | |
| `SimilarityGraph.fromLibrary` | 11 ms | 77 ms | 187 ms | |
| graph as JSON: size, encode, decode | 634 kB, 14 ms, 14 ms | 2.4 MB, 64 ms, 55 ms | | |
| session built + first `next(5)`, median (max) | 3.2 ms (3.9) | 4.2 ms (5.2) | 9.1 ms (10.2) | 300 ms |
| `next(5)`, median (max) | 0.3 ms (0.7) | 0.3 ms (1.2) | 0.2 ms (0.6) | 50 ms |
| feedback + `returnUnplayed` + `next(5)`, median (max) | 1.8 ms (2.8) | 2.1 ms (3.9) | 4.0 ms (7.2) | |

The song keys cost the snapshot 12 ms (600 artists) to 26 ms (1 914) over
the round before (90 and 136 ms).

Debug build (what `swift test` runs by default), 1 914 artists: snapshot
271 ms, graph 679 ms, session + first five 113 ms, `next(5)` 6.0 ms,
feedback + next 99 ms. 50 000 tracks: snapshot 652 ms, graph 2.7 s, session
+ first five 282 ms. The tests hold debug to 12 times the bar.

How it stays fast:
- The snapshot keys each distinct spelling once. The title index for `match`
  is built on the first `match`, behind a lock, as 20 000 NameKey titles
  take half a second on Linux.
- A session scores the whole library in one pass over arrays when its
  profile changes and keeps the pool sorted. A pick walks it best first and
  stops once nothing further down can reach the K-th best.

The same random seed gives the same station in every process: nothing
depends on a Dictionary's order. The listings below came out the same in two
separate runs.

### On the test server

`RadioRealLibraryFixture.swift`: the 358 tracks of
`dev/jellyfin-test-server.sh` as Jellyfin 12.4 gave them, joined tags and
all. `testFixtureMatchesTheLiveServer` checks the fixture against the live
server when `JELLYFIN_URL` is set: 358 of 358 the same. No listening
history, so taste plays no part.

The library is small: 23 artists, mostly three to a genre cluster, with
guests across clusters. Three tracks between two by one artist then leave
every fourth song to someone outside the cluster, and the radio picks that
one by the graph: a guest of the seed, or a neighbour of a neighbour.

**Velvet Static Radio**, adventurousness 0.35 (Velvet Static's neighbours:
Iron Meadow 0.59, Kalimba Sound System 0.26, The Lanterns 0.24, Nightdrive
0.22, Glass Animals Club 0.18):

```
 1. Gold Dream — Velvet Static (Rock, Shoegaze, 1997) · More by Velvet Static
 2. Lights City — Iron Meadow (Rock, Hard Rock, 1979) · Sounds like Velvet Static
 3. Dust Dance — The Lanterns (Rock, Alternative, 1996) · More Rock
 4. Gold Window — Kalimba Sound System (Electronic, House, 2014) · Sounds like Velvet Static
 5. Summer Road — Nightdrive (Electronic, Synthwave, 2015) · Sounds like Velvet Static
 6. Hollow Tide — Velvet Static; Iron Meadow (Rock, Shoegaze, 1997) · More by Velvet Static
 7. Rain Window — The Lanterns (Rock, Alternative, 1994) · More Rock
 8. Fire Heart — Kalimba Sound System; Hexagon Lights (Electronic, House, 2013) · Sounds like Velvet Static
 9. Summer Song — Glass Animals Club (Indie, Alternative, 2012) · Sounds like Velvet Static
10. Quiet Drive — Iron Meadow (Rock, Hard Rock, 1983) · Sounds like Velvet Static
11. Gold City — Velvet Static (Rock, Shoegaze, 1991) · More by Velvet Static
12. Wild Story — The Lanterns (Rock, Alternative, 1994) · More Rock
13. Morning Line — Nightdrive (Electronic, Synthwave, 2015) · Sounds like Velvet Static
14. Night Dream — Iron Meadow (Rock, Hard Rock, 1984) · Sounds like Velvet Static
15. River City — Paper Harbour; Glass Animals Club (Alternative, Indie, 2006) · Sounds like Velvet Static
16. Echo Machine — Velvet Static; Kalimba Sound System (Rock, Shoegaze, 1997) · More by Velvet Static
17. Harbour Road — The Lanterns (Rock, Alternative, 1996) · More Rock
18. Echo Story — Iron Meadow (Rock, Hard Rock, 1984) · Sounds like Velvet Static
19. Ocean Road — Glass Animals Club (Indie, Alternative, 2014) · Sounds like Velvet Static
20. Red Window — Kalimba Sound System (Electronic, House, 2013) · Sounds like Velvet Static
```

Velvet Static plays every fifth song (the cap). Kalimba Sound System and
Nightdrive are there because they are on four of Velvet Static's records;
with Last.fm's edges, artists who sound alike would take their place.

**Signal Dream Radio** (a song by "MC Polder; Lyric Engine"):

```
 1. Signal Dream — MC Polder; Lyric Engine (Hip-Hop, Nederhop, 2006) · Where the station started
 2. Signal Road — Concrete Poets; Amsterdam Strings (Hip-Hop, 1996) · Sounds like MC Polder
 3. Lights Tide — Clara Venn; Willow & Pine (Classical, Piano, 2004) · Sounds like Lyric Engine
 4. Rain Tide — Saskia de Wit (Jazz, Vocal Jazz, 2010) · Sounds like MC Polder
 5. Electric City — Lyric Engine (Hip-Hop, Rap, 2020) · More by Lyric Engine
 6. River Room — MC Polder (Hip-Hop, Nederhop, 2006) · More by MC Polder
 7. Lights Waltz — Concrete Poets (Hip-Hop, 2001) · Sounds like MC Polder
 8. River Dance — Amsterdam Strings (Classical, 1995) · Sounds like Lyric Engine
 9. Night Line — Blue Room Trio (Jazz, Bebop, 1962) · Sounds like MC Polder
10. Fire Mirror — Lyric Engine (Hip-Hop, Rap, 2018) · More by Lyric Engine
```

The test prints 20, 12 of them hip-hop. The server has three hip-hop
artists, so with separation and the cap about two songs in five go to their
guests: Lyric Engine and Amsterdam Strings share four songs, MC Polder and
Saskia de Wit three.

**Jazz Radio**: 15 of 20 jazz, the most three jazz artists allow. About every
fourth song comes from the jazz artists' neighbours: "Sounds like Saskia de
Wit" for MC Polder and Concrete Poets (guests on her songs), "Sounds like
Miles Ahead Quartet" for Low Orbit and Hexagon Lights.

**Listening, on The Lanterns Radio at 0.7.** The first eight:

```
1. Wild Drive — The Lanterns (Rock, Alternative, 1996) · More by The Lanterns
2. Electric Mirror — Iron Meadow (Rock, Hard Rock, 1984) · More Rock
3. Lights Machine — Velvet Static; Kalimba Sound System (Rock, Shoegaze, 1997) · More Rock
4. Glass Machine — Mira Lux (Pop, Electronic, 2027) · Sounds like The Lanterns
5. Red Letters — Sunny Side (Pop, Dance, 2011) · Sounds like The Lanterns
6. River Waltz — The Lanterns (Rock, Alternative, 1998) · More by The Lanterns
7. Velvet Machine — Paper Harbour (Alternative, Indie, 2003) · Sounds like The Lanterns
8. Echo Dance — Iron Meadow (Rock, Hard Rock, 1984) · More Rock
```

The listener gives "Electric Mirror" a thumbs down and skips both pop songs.
The queue after them is put back, and the next ten are chosen again:

```
 1. Ocean Story — The Lanterns (Rock, Alternative, 1998) · More by The Lanterns
 2. Satellite Line — Paper Harbour (Alternative, Indie, 2003) · Sounds like The Lanterns
 3. Static Mirror — Glass Animals Club; Iron Meadow (Indie, Alternative, 2012) · Sounds like The Lanterns
 4. Northern Letters — Velvet Static (Rock, Shoegaze, 1991) · More Rock
 5. Paper Dream — June Hollow; Old Mill Road (Folk, Indie, 2021) · Sounds like Glass Animals Club
 6. Fire Story — The Lanterns (Rock, Alternative, 1996) · More by The Lanterns
 7. Silver Parade — Glass Animals Club (Indie, Alternative, 2012) · Sounds like The Lanterns
 8. Glass Heart — Paper Harbour (Alternative, Indie, 2003) · Sounds like The Lanterns
 9. River Tide — June Hollow (Folk, Indie, 2021) · Sounds like Glass Animals Club
10. Fire Sky — Velvet Static (Rock, Shoegaze, 1991) · More Rock
```

No Iron Meadow song of their own (one as a guest, at √0.02 of its score),
and no pop: the slots where separation has blocked every rock artist in this
library go to folk and indie through Glass Animals Club.

## What it does when …

`RadioCriticTests.swift` tries the radio the way a demanding listener would
try to break it. Each case is a test that measures; where the first
measurement showed a weakness, the table gives the number after the fix.
The library is RadioFixtures' unless said.

| When … | Before | After |
|---|---|---|
| the library has 12 songs of 4 artists (6 stations × 120 picks) | every song before a repeat; then every rule off at once: 352 separation violations, 126 album back to back, a song back after 7 | the same first round; then 0 and 0, a song back after 12 at the soonest |
| one artist, 3 albums of 10 (4 × 90) | 125 album back to back | 2 (the last new songs of the first round), 0 after; a song back after 27 |
| nothing is known of the listener (the test server) | The Lanterns Radio opened with 3 different songs in 20 random seeds, Jazz Radio with 3 | 10 and 13 |
| no track has a genre or a year (20 artists, 6 × 40) | 0.64 of picks from the library's first half | 0.47; the artist's own every fifth, 20 artists |
| every track is Rock, one year (20 artists, 6 × 60) | — | 20 artists in 60, albums in no order (0.51), a skipped artist 1.17 → 0.83 of the next 20 |
| an artist station for an artist with one song | — | it first, never again, then 100% their genre |
| the same song is on its album and a best-of (40 of 120 tracks, 6 × 60) | 46 songs played twice | 0 (and 7 → 0 twice in a mix) |
| a song was thumbed down yesterday (4 songs, their artist's station, 10 × 60) | played 7 times | 0 |
| the seed artist's song gets a thumbs down on their station (32 stations, next 30) | the artist 5.9 → 0.3, their close neighbours 0.65 → 0.45 | 5.9 → 3.3, 0.65 → 0.70 |
| the station plays 1 000 songs (3 artist stations, all heard to the end) | the seed's cluster by hundreds 0.98 0.89 0.49 0.09 0.00 0.00 0.00 0.00 0.00 0.00 | 0.98 0.88 0.79 0.68 0.60 0.59 0.64 0.65 0.71 0.66; songs again in each hundred 0.00 0.04 0.35 0.54 0.59 0.63 0.69 0.71 0.81 0.78, never within 12 hours; distinct artists in 50: 8.3 → 16.3; no artist above 0.20 of any 50 |
| 50 skips in a row (4 stations) | — | no repeat, no skipped song back in the next 30, no score 0 (no underflow), 21 artists tried in the 50 |
| 50 thumbs down in a row (3 stations) | — | none back in the next 40, no repeat, never fewer than asked |
| the dial goes 0 ↔ 1 every 5 picks (200) | — | unheard 0.12 at 0, 0.74 at 1; no separation or album violation; no song within 12 hours |
| names: "Beyoncé", "Beyonce", "BEYONCÉ"; "Sigur Rós"/"Sigur Ros"; "AC/DC"; "The The"; "Simon & Garfunkel"/"and" | — | one artist each; a station from the plain spelling finds the library's ("Beyoncé Radio") |
| a guest only ever in "A; B" or "A feat. B" | — | their own station, opening with a song they are on, 20 of 20 in its genre |

## What was tried

Each round, in order; the numbers elsewhere in this doc are from the last.
Each round is in the test output of its time.

| Round | Change and why | Measured |
|---|---|---|
| 1. first version | — | coherence 0.95 at 0, 0.35 and 0.7 alike, falling only at 1; three Shoegaze skips 0.38 → 0.22; "Because you liked" on 71% of picks after a like |
| 2. skips | pressure that counts by its square, instead of a factor per skip, weighted by the genre's specificity: in a 60-artist library "Rock" (IDF 1.79) is barely commoner than "Shoegaze" (2.14), so every skip pushed on Rock as hard | 0.37 → 0.21 |
| | … weighted by how much a genre sets the track apart from the station's best 300 | 0.37 → 0.18 |
| | … fade slowed from 3% to 2% a track | 0.36 → 0.15 |
| 3. the dial | the incoherent picks at 0 were tracks where a neighbour was only a guest: a guest counts 0.7 (was 0.85), and the metric counts a pick with a neighbour on it | |
| | closeness scaled by genre fit near the familiar end, half at 0 | in cluster 0.92 / 0.92 / 0.89 / 0.71 |
| | … 60% at 0, with the other changes | 0.98 / 0.96 / 0.94 / 0.79 |
| | familiarity factor nine times → four: at nine it pulled a station from an artist the listener never plays toward the artists they do | familiar end against default: 0.864 / 0.880 at nine, 0.879 / 0.885 at four; the genre fit then made 0 the tightest |
| 4. variety | penalty 0.3 → 0.5 a recent track | distinct artists 8.7 → 9.6 at 0.35 (before the guest change took some neighbours away; 8.6 now) |
| 5. the test server | what the made-up library did not show (Names, and the graph): genres from an artist's own records, a guest edge without a shared genre at 40%, genre stations reaching out through their artists' neighbours | see those sections |
| 6. likes | the variety penalty from the liked track itself ate the boost: a just-liked artist exempt, boost 1.2 → 1.5 | liked artist 0.152 → 0.177 before, 0.154 → 0.185 after, near the 0.25 separation allows |
| | "Because you liked" only when the like's artist, or a neighbour of 0.55 or more, lifted the pick | 36% of the next 15 |
| 7. Instant Mix | candidates at weight 1 never reached a jazz station, as the genre fit and era scaled them down like any track: now exempt from both, and their weight raises the score up to twice | |
| 8. thumbs down | × 0.08 → × 0.02 | at × 0.08 Iron Meadow was back three songs later on the test server, when separation had blocked the rest |
| 9. short tracks | `PlayOutcome.of` counted "all but the last 20 s" as heard, so on the test server's 6-second tones every skip was a completion: that rule now only for tracks longer than 40 s | |
| 10. the critic's round ("What it does when …") | ties in the session's order, songs, the rules loosened one at a time, repeats after `noRepeatHours`, the kept thumbs down, the softer one for the station's own artist | |
| | repeats tried at a flat 0.5 | cluster 0.83–0.98 in every hundred of 1 000, but 68% repeats after the first 200 |
| | … 0.15 rising to 0.3 | 0.65 and 56% |
| | … 0.3 × freshness | 0.49 and 47% |
| | the station's own artist after a thumbs down at × 0.2 | 5.9 → 4.7, as if nothing was said |
| | … at × 0.07 | → 1.0 |
| 11. the clock and "not now" | Your Station by the hour (The clock); λ·L against the share overall, lifting both ways | Jazz × 1.33 at Tuesday 08:00, as morning Jazz made the overall share lean its way; Wednesday 15:00 Jazz 0.18 → 0.12 (a lift below 0) |
| | … against the share at the other hours, only up, from ln 1.25 | Jazz × 2.25, but 0.098 apart at Wednesday 15:00 (Rock lifted as the mornings left it) and 0.065 without a pattern |
| | … also the score × e^(λ·L), as the profile's weights stop at 1; from ln 1.6 | the table in The clock |
| | a known song's skip × its nearness to now | the listening rows above moved by up to 0.02 (the made-up history skips loved songs) |

## Building on it

- **Mixes** (`MixGenerator`). A `RadioSession` with a `.collection` seed
  (the tracks a mix is about) and `randomSeed: SplitMix64.stableSeed("daily-1-2026-11-08")`
  is a mood that is the same all day and new tomorrow, with the
  radio's rules for free. `next(40)` gives 40 tracks.
  - `TasteProfile.topArtists/topGenres/topTracks/lastHeard/familiarity`
    give what "On Repeat", "Rediscover" and "Deep Cuts" need.
  - `SimilarityGraph.weight(_:_:)` and `similarArtists` give the clusters
    for the moods (`MixBuilders.swift`: each named after its own songs,
    never one artist's).
  - `Station(seed:snapshot:)` names any station; `Station.id(for:)` gives
    its id without building it.
- **Last.fm** (`SimilarityService`):
  - `addArtistEdge(asked, similar, weight: match)` for each similar artist
    the library has (`snapshot.matchArtist`); the asked artist then counts
    in `enrichedArtistCount`;
  - `addTrackEdge(from:to:weight:)` for similar tracks (`snapshot.match`);
  - merge onto `SimilarityGraph.fromLibrary(snapshot)`. Last.fm's `match` is
    0 … 1 and library edges are rarely above 0.8, so Last.fm's strong links
    win.
- **The app** (`RadioController`):
  - after a skip or a thumbs: `record`, then `returnUnplayed(queued ids)`,
    then `next(n)`;
  - after a song heard to the end: `record(.finished)`, nothing to return;
  - a session may hand out a song again after `noRepeatHours` of music (and
    sooner in a library that has run out), so the queue must allow an id
    more than once in a session;
  - a thumbs down is kept by the history's `.disliked` event. Taking a
    thumb back must leave an event too (a `.liked` does it), or the song
    stays off the radio for half a year;
  - pass `history.trackIDs(since: now − noRepeatHours)` as `recentlyPlayed`;
  - Instant Mix at a weight of about 0.5, Last.fm's similar tracks about
    0.8, both via `addCandidates`;
  - a session and its first tracks take about 5 ms on 20 000 tracks, fine
    on the main actor; build the snapshot and the graph (100–220 ms
    together, release) off it.

## Limits

- The library alone knows only tags, guests and years. With few artists per
  genre, a station reaches its guests' genres early (the listings above).
  Last.fm's edges are what make "sounds like" right.
- No audio analysis: two songs of one artist are alike, whatever they sound
  like.
- Adventurousness is not remembered per station; that is the app's job.
- Repeats grow over a very long session: after 13 hours of an artist
  station on the made-up library a third of the songs were heard earlier,
  after three days four in five. The other choice was leaving the seed
  altogether.
- Songs are matched by artist and title: a cover by another artist is
  another song, and two different songs of one artist with one title
  ("Intro" on two albums) are one.
