# The radio: what else it could know

"laat hem ook alternatieven uitzoeken hoe we dit beter kunnen doen", then
"ik zou het niet perse willen runnen maar de data ervan gebruiken om betere
radio's te bouwen" (the photographer, 20 November 2026, after Gorillaz on
Moans Radio; `RADIO.md`, "The server's mix").

Researched on the web that day, with live lookups for Hania Rani, Nils
Frahm, Gorillaz, Angèle and Cocteau Twins. Recommendation 1 (AcousticBrainz) was built on 23 November 2026
(`RADIO.md`, "How it sounds"); the rest is not. The
frame is the app's: the client does the work, the server stays as it is,
it runs on the iPhone and on Linux, and the kit is Foundation only.
"Unverified" means read in a search result or a forum, not checked.

## Where the radio stands

| It knows | From | Good for | Falls short |
|---|---|---|---|
| who is near whom | Last.fm's similar artists (a key) | "Sounds like Hania Rani": Nils Frahm 1.0, Eydís Evensen 0.72 | per artist, not per song; nothing without a key |
| which songs go together | Last.fm's similar tracks (a key) | well-known songs | empty for "Moans" |
| genres | the files, Last.fm's tags | a tagged library | two thirds of his songs have none; the words are broad |
| how loud | the server's gain | a metalcore song on a calm station | says nothing else about the sound |

What is missing is how a song sounds. Listener data is per artist, and tags
call Hania Rani and Gorillaz both "electronic".

## Data to look up

All of it is open and needs no account. None of it needs anything on the
server.

| Source | Key | What it gives | Coverage | Matching his files | Licence | For the radio |
|---|---|---|---|---|---|---|
| **AcousticBrainz** | none | per recording: acoustic or electronic, danceable, party, relaxed, timbre, loudness, dynamics, BPM, key | 7.6 million recordings, frozen June 2022. "Says" is there; "Moans" (2023) never will be | by MusicBrainz recording ID | CC0 | "sounds like": the one source that told his piano from the three |
| **ListenBrainz** | none for these | similar artists and similar recordings, from what people play in one session; artist and title to MusicBrainz IDs | artists good; recordings thin ("Says" 86, "Moans" 0) | by name, through its own lookup | CC0 (unverified) | "listened together", beside Last.fm |
| **MusicBrainz** | none | genres and tags down to the recording, 2 227 genres | wide | by ID | genres and tags CC BY-NC-SA 3.0, not CC0 | fills the songs without a genre, in the same broad words |
| **Discogs** | none at 25 calls a minute | styles per album ("Esja": Ambient, Modern Classical, Minimal) | wide for albums | artist and album | dumps CC0, API terms (unverified) | finer than genres, per album |

Left out: GetSongBPM (a key and a link back, tempo only), Spotify's audio
features (closed), Cyanite (commercial), Music4All and MTG-Jamendo
(research sets, not lookups).

**Matching.** The kit reads no MusicBrainz IDs today. Jellyfin has them
in `ProviderIds`, OpenSubsonic in `musicBrainzId`, Plex in its guids when
the files were tagged with Picard (all three unverified on a real server).
Without them, ListenBrainz turns artist and title into IDs, one call a
second: about an hour for his 3 780 songs, once.

**AcousticBrainz in numbers.** `mood_acoustic` is 0.72 to 0.99 for six
calm piano tracks (a hand-picked sample, not a rate), and 0.01 to 0.15
for five of Gorillaz, Angèle and Cocteau Twins. Its
classical-or-not guess was right for all six. Weaker: danceability, party,
timbre. Wrong: its electronic guess (9 of 11), voice or instrumental, BPM.
MetaBrainz's own verdict on the high-level values is that they are of
little use; take the two or three that hold, not the set.
- Live API, 25 recordings a call, about 24 bytes kept per song. The data
  no longer changes, so a cache never goes stale.
- The site says the API stays "for now". The dumps stay: 40 GB for the
  high-level values, too big to ship, small enough to cut a table from.

## A map of our own

Every artist and every genre gets a place by the sound of its recordings,
on a few axes: acoustic to electronic, calm to driving, sparse to dense,
dark to bright, quiet to loud. Who is listened to together draws the
neighbourhoods. The radio then has a distance of its own between any two
artists or genres, where a tag only matches or not: "ambient" next to
"modern classical", far from "hip-hop", whatever the files say.

Built from open data and his library only:
- **On the client.** The mean of the AcousticBrainz values of each of his
  artists' songs, and of each genre's. Nothing shipped, no licence
  question. It also places "Moans": by its artist. One to two days once
  the lookups are cached.
- **A table in the app.** 2 227 genres on 8 axes is 18 kB. Cut once from
  the dump joined to MusicBrainz's genres: three to five days, and the
  CC BY-NC-SA question for an app that is sold.
- **The neighbourhoods.** ListenBrainz's similar artists, where there is
  no Last.fm key. With his key they add little.

## Models on the device

Not now: he would rather use the data, and it is the largest build.
- An embedding per song (MusiCNN 3.2 MB and 200 numbers a song,
  Discogs-EffNet 18 MB and 1 280) ranks "sounds like" best of all.
- Cost for 20 000 songs, estimated: half a second to a second a song,
  mostly fetching 30 seconds of it, so 1.5 to 6 hours on Linux; on an
  iPhone only in the foreground. 16 MB of vectors, or 100 MB. Finding
  the nearest is a few milliseconds by plain search.
- Two runtimes outside the kit (Core ML, ONNX Runtime), and every client
  works it out again: the server keeps nothing.
- Licences: Essentia is AGPL, its model files CC BY-NC-SA.
- A cheaper kind: five numbers from the kit's own FFT (centroid, flux,
  zero crossings, energy, range). On ten tracks they split piano from the
  three as cleanly. Same fetch, no model.

## What a server already knows

Detect it, then trust it; nothing to install by us.
- Navidrome: the `sonicSimilarity` extension where a plugin provides it.
- Jellyfin: AudioMuse-AI's own route (its InstantMix falls back to the
  genre mix, so ask the route). A container he would run himself.
- Plex: `/library/metadata/{id}/nearest`, with Plex Pass (unverified).

A `sonicMix` capability from these three would let a proven mix be a
candidate again, weighted by the server's own score.

## His own listening

Artist pairs heard together in sessions he chose, and a station's skips
remembered for that station. Milliseconds, kilobytes, nothing leaves the
device. Grows slowly, and says nothing of music never played. The radio's
own picks must not count, or it confirms itself.

## How others turn the dial

Pandora describes a song by some 450 attributes and offers named modes
(Discovery, Deep Cuts, Crowd Faves). Plexamp ranks by distance in sound.
Spotify names a taste profile, skips and editors, no method. Nothing
official from Apple. What to take: the dial as a radius in sound, once
there is a sound to measure.

## What to build next

**1. A sound profile from AcousticBrainz.** Built 23 November 2026, after
the coverage check: 3 720 of his 4 091 songs matched (0.909), 3 007 with
AcousticBrainz data (0.735). `RADIO.md`, "How it sounds", has what it
keeps and what it does. The plan as it was:
No key, CC0, all in the kit, so every client and server at once.
1. Coverage first: IDs for his 3 780 songs, then one count call per 25.
   Under about half covered, stop and take the five-number analysis
   instead.
2. `AcousticBrainzClient` in the kit: 25 a call, the same recording under
   another ID on a miss, a cache of 24 bytes a song.
3. A profile per song; a song without data takes its artist's mean, the
   first piece of the map.
4. In the score beside loudness, and shaped like it: a bell around the
   station's median, widened by the dial. Last.fm stays "who is near";
   this adds "what it sounds like".
5. `RADIO-MIX` on a recorded fixture: a calm piano seed, the share of
   picks that are acoustic, before and after.
6. Settings and PRIVACY.md: artist and song names go to MetaBrainz.

About a week, an estimate. The gain is the case of 20 November: Gorillaz
off a piano station even where Last.fm and the tags say nothing.

**2. ListenBrainz where Last.fm is empty, and without a key.**
Similar recordings as track edges (`addTrackEdge`) for songs like "Says";
similar artists as edges (`addArtistEdge`) for a listener with no Last.fm
key, who today gets a fifth to a third of this station right
(`RADIO.md`). Three to four days, an estimate: a client like Last.fm's, a
recorded fixture, one `RADIO-EVAL` row. Its lookup is also step 1 above.

Later: the map's table, his own listening as a station's memory, the
`sonicMix` capability.

## The Last.fm key, as it is today

- Jukebox's own, built into every client since 21 November 2026
  (docs/RADIO.md, Last.fm's key), so no device needs one typed in.
- The listener's own, optional, in place of it: Settings, Last.fm, on the
  iPhone, the iPad and the Mac; Preferences, Radio, Last.fm, on Linux. It is
  kept in that device's settings and does not travel.
- A key Last.fm refuses later is off for that run, and the line under
  Enhance Radio with Last.fm and a station's page say so; "rate limit" or
  no answer says so too and is asked again later, a minute, then longer
  (`RADIO.md`, Last.fm's key).
- An empty answer is kept for 30 days: "Moans" has no similar songs on
  Last.fm, and will not be asked again until then.
- Names were asked as filed: his "Angele", without the accent, is a page
  of its own on Last.fm, tagged "Slayer" and "Megadeth". Since 23
  November 2026 the page is chosen among Last.fm's spellings of the name
  (`RADIO.md`, Last.fm's tags): "Angèle", "pop", "indie pop".

## Sources

- https://raw.githubusercontent.com/jellyfin/jellyfin/master/Emby.Server.Implementations/Library/MusicManager.cs
- https://acousticbrainz.org/download and https://acousticbrainz.readthedocs.io/api.html
- https://blog.metabrainz.org/2022/02/16/acousticbrainz-making-a-hard-decision-to-end-the-project/
- https://labs.api.listenbrainz.org/ and https://listenbrainz.readthedocs.io/en/latest/users/api/index.html
- https://musicbrainz.org/doc/MusicBrainz_API/Rate_Limiting and https://musicbrainz.org/doc/MusicBrainz_Database/Download
- https://www.discogs.com/developers
- https://essentia.upf.edu/models.html and https://essentia.upf.edu/licensing_information.html
- https://navidrome.org/docs/usage/integration/audiomuse/ and https://github.com/NeptuneHub/AudioMuse-AI
- https://raw.githubusercontent.com/pkkid/python-plexapi/master/plexapi/audio.py
- https://techcrunch.com/2019/03/19/pandora-switches-up-its-classic-listening-experience-with-modes
