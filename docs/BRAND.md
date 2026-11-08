# Jukebox's brand: the Arch

Jukebox had borrowed Numa's look, eclipse and all. The photographer, on the
TestFlight build of 8 November 2026:

> "Het heeft nu wel heel weinig eigen branding en je hergebruikt nu het numa
> logo daar mag je wel meer eigen vorm aan geven."

Four directions were drawn and judged (Arch, Tonearm, Selector, Dial;
[comparison.png](brand/comparison.png)). The photographer chose:

> "Die arch is leuk."

What was built is the judge's synthesis, "Arch, sharpened": Arch's mark,
icon, colours, station art and motion; Tonearm's Copper as the light-mode
accent, its heavier cut of the mark for small sizes, and its rule that a
station's name is drawn into the art only from 200 pt; Dial's Familiar ⟷
Adventurous dial with its words in the accent, under the station on the
air; Selector's "lit means endless". Arch's board,
[board.png](brand/board.png), is the direction as it was judged; where the
app differs from it, it says so below. The second round the same day,
sketch D (below), replaced "lit means endless" with "light means on air",
drew every other arch flat, took the station's name out of the art and
Numa's grey spaced labels out of the screens.

The cabinet's arch as the frame of everything: two bands around a window,
and in the window the one thing that changes — the music.

## Less AI: sketch D

The Arch as first built still read as someone else's. The photographer, on
the TestFlight build of 8 November 2026:

> "Ik vind het nogsteeds wel heel erg op Apple Music lijken … zo laat het
> wel heel erg weinig eigen smaak toe."

> "Kun je het design iets minder ai maken?"

The tells were listed, each with its rule ([design/tells.md](design/tells.md)),
and sketch D drew them applied to Home, Now Playing and Radio
([design/sheet-d.png](design/sheet-d.png); the screens alone in
`design/home-after.png`, `home-after-light.png`, `nowplaying-after.png`,
`radio-after.png`). The photographer, of sketch D:

> "Ja nice dit, maak dit maar dan refinen we later wel. Als batterij een
> zorg wordt moeten we ook ff kijken wat we daar aan kunnen doen."

`docs/design/` stays as the reference: a screen that differs from it says
why. Before a screen ships, tells.md's checklist: is anything lit that is
not on air; is there an uppercase label, or more than one small label;
does any line tell what is already seen; is anything rounded that is not
artwork or a system control; is there more than one filled button; is a
title set in the sans.

Jukebox stays a sibling of Numa in restraint and in care — Apple's own
controls, one filled button a screen — and no longer in its shapes, nor in
its labels: Numa's small grey spaced labels went with sketch D.

## The rules

1. **The arch only ever means a station.** The mark, a station's artwork,
   the mark before a station's name in Now Playing and the mini player.
   Nothing else is drawn as an arch.
2. **Light means on air.** Only the station that plays is lit: its
   artwork's tubes in their own oranges, with one soft glow on its room
   (`StationArtwork`, by `RadioController.stationOnAir`). Every other arch
   is flat — two bands, Copper outside and Glow inside, and a flat core; no
   blur, no bloom — the mark included, everywhere. No button, card or
   ground glows. (It replaces the Arch's first rule, "lit means endless",
   under which every station glowed at once.) Home's mixes, which end, are
   square collages; albums and playlists stay square and uncropped.
3. **Flat grounds.** Warm paper, #F6F3EE, by day; #121110 by night
   (`Theme.ground`); Cabinet, #1E0A07, under Now Playing. No vignettes, no
   gradients behind a screen. The system's own grounds where the system
   draws a list (Settings, the library's long lists).
4. **Titles in a serif, as on sleeves.** New York (`Font.serif(_:)`, the
   system font's serif design) at regular weight: the large and inline
   navigation-bar titles (`Theme.styleNavigationBars`, at launch, with
   Dynamic Type), a page's title, a section's heading. Everything else in
   SF Pro; times in tabular figures.
5. **Sentence-case headings, at most one small label.** "Mixes", "Played
   lately", "Stations" (`SectionHeader`, `ListHeading`). The one small
   label a screen may have is "On air" (`Eyebrow`, in the accent). No
   tracked uppercase anywhere.
6. **Facts, not slogans.** "Made at 06:00", "Played Thursday", "Not played
   yet", a mix's artists (`RelativeDay`). No line that says what is already
   seen ("Endless music from everything you love", "Plays on for as long as
   you listen" went). The radio's reasons for a song appear only in the
   queue. The dial shows its two ends, Familiar and Adventurous, and
   nothing else.
7. **On the ground, not on cards.** Content sits on the page, separated by
   hairlines and space (`Hairline`). One radius, 6 pt, for artwork
   (`Theme.Radius.artwork`); nothing else Jukebox draws is rounded — the
   system's own controls keep theirs. One filled button a screen, a plain
   rectangle in the accent with 6 pt corners and no glow; every other
   action is a word in the accent or a plain SF Symbol. No pills with icon
   and label.
8. **Editorial, left-aligned.** Titles, rows and Now Playing's words start
   at the margin; shelves run off the right edge so the next tile peeks in.
   Centred only where Apple centres: the transport, a page's own header.
9. **One accent pair.** Copper by day, Glow by night: one hue seen in two
   exposures. Nothing else in the interface is orange; the tubes' own
   oranges are for the station on the air and the app icon only. The one
   exception is Now Playing, whose accent is its cover's (below).
10. **No jukebox cabinet.** No bubble tubes, chrome, grilles or selector
    buttons — no Wurlitzer. The arch is the whole of it; the record player
    on Now Playing is drawn, not rendered.
11. **Native first.** The chrome is Apple's: tab bar, lists, sheets, the
    system Slider tinted with the accent, SF Symbols for every glyph but the
    mark.

## Colours

`Jukebox/Components/Theme.swift`, `Theme.Arch` and `Theme.ground`; the
accent pair is the asset catalog's `AccentColor`.

| Name | Hex | Use | Contrast |
|---|---|---|---|
| Copper | `#A84A17` | The accent in light mode: tint, selection, the one filled button, a text button; the outer band of every flat arch | 5.74:1 on white, 5.15:1 on `#F2F2F7`; white on it 5.74:1 |
| Glow | `#FFB54D` | The accent in dark mode, and wherever Jukebox is always dark (Now Playing, the art); the inner band of every flat arch | 11.97:1 on black, 9.70:1 on `#1C1C1E`, 10.86:1 on Cabinet |
| Ink | `#2A1505` | Words and glyphs on Glow (`Theme.onAccent` in dark mode) | 9.91:1 on Glow |
| Paper | `#F6F3EE` | The ground of the main screens by day (`Theme.ground`) | — |
| Night | `#121110` | The ground of the main screens by night (`Theme.ground`) | — |
| Cabinet | `#1E0A07` | Now Playing's ground, the app icon's, the welcome's mark's tile, a station's room until its cover's colour is known; the launch screen in dark mode | white on it 19.06:1 |
| Mark core | `#F7A136` / `#FFF1D6` | The flat mark's core, by day / by night (decoration: amber on white is 2.08:1, never for words) | — |
| Outer tube | `#F07E36` | The station on the air only: its outer tube, and its glow | — |
| Inner tube | `#FFB44C` | The station on the air only: its inner tube, and its glow | — |

Contrast as WCAG 2 computes it (`python3 dev/brand/contrast.py`).
Now Playing is always dark, and its accent is the colour of the cover that
plays, at Glow's weight; a station's room is always dark, so its art reads
the same in either appearance. The
icon's other oranges (the tubes' feet and hot lines, the core's light, the
room's glow) are `dev/brand/icon.py`'s, for the icon alone.

## Now Playing's accent: the cover's

The photographer, 8 November 2026: "kan je de kleur uit de albumhoes pakken
voor de steunkleur?" On Now Playing, what is Glow elsewhere — the progress,
the station's name and mark, a thumb or heart given, the dial, Up Next's
toggles — takes the hue of the cover that plays
(`JukeboxKit/…/Artwork/CoverAccent.swift`, the steps in its comment;
`dev/accent.py` is the same in Python for sketches):

- the hue the eye picks out (a histogram of hue, vivid parts weighed most),
  not the average, which makes red stripes on cream beige;
- at Glow's lightness, so it weighs on Cabinet what Glow does and only the
  hue changes from album to album; a little darker where a hue has no room
  there (red), never under Oklab 0.70: 6.7:1 or more on Cabinet;
- Glow for a cover without a colour of its own (black and white, grey);
- eased over half a second when the song changes, at once when Now Playing
  opens.

The rest of the app keeps Copper and Glow: the brand stays put, the record
playing colours its own page only. `docs/design/accent.png` is the test
library's covers with their accents.

## The mark

Two bands with round caps and a core, concentric about the spring point
(16, 14) in a 32-unit box: width 24, height 28, baseline 30, band stroke
2.6, gaps 2.2. [mark.svg](brand/mark.svg), [mark-dark.svg](brand/mark-dark.svg),
[mark-template.svg](brand/mark-template.svg).

- **Flat:** Copper outside, Glow inside, the core amber by day and a warm
  white by night. No bloom: the mark is never on air.
- **Template:** every part in the foreground colour; in the accent before a
  station's name (Now Playing, the mini player).
- **The heavy cut, 20 pt and below** (Tonearm's optical cut): stroke 3.2,
  gaps 1.9, a core 5.6 wide, width 26, so the three parts stay three at 16
  and 11 pt ([mark-small-template.svg](brand/mark-small-template.svg)).
- **Warm-up:** on the welcome screen the bands start as cold glass and come
  on one by one — the outer, the inner, the core — in about 1.2 s, as a
  fade, not a glow. Under Reduce Motion it is on at once.
- **No breathing.** The mark's tubes used to dim and come back while a
  station played. It went with sketch D: a mark that moves for ever is a
  glow by other means, and beside the turning record it would run the
  screen at 60 frames a second where the record asks for 30 (see the
  turntable, below).

`dev/brand/geom.py` is the one source of the geometry; `ArchCut` in
`ArchMark.swift` carries the same numbers. Change both together.

## Type

Titles in New York, the system's serif, at regular weight, as titles on
sleeves are set: `Font.serif(_:)` (`.system(style, design: .serif, weight:
.regular)`, so it follows Dynamic Type), and the navigation bars' titles
through UIKit's appearance (`UIFontDescriptor.withDesign(.serif)` scaled by
`UIFontMetrics`). Home's large title says what part of the day it is
("Tonight", `RelativeDay.partOfDay`). Everything else in SF Pro; times and
counts in tabular figures (`.monospacedDigit()`).

## The app icon

The mark lit on Cabinet, as the tubes of a jukebox's arch light the room
they stand in: the tubes in their oranges with halos and a hot line each,
the core, the floor and the window lit by them. Three appearances in the
asset catalog's single-size format: default, dark (a darker room) and
tinted (a grey ramp on black, which the system tints). All three opaque
RGB, as App Store Connect wants. `python3 dev/make-icon.py` redraws them
from `dev/brand/icon.py` (Chromium through node's playwright).

## Station artwork

[stations.png](brand/stations.png), drawn by `dev/brand/station.py` with
the app's numbers (`StationArtCut` in `StationArtwork.swift`). The board
draws every station lit; since sketch D only the one on the air is.

- **The window** is the arch, filled with the station's music: one cover for
  a song's or an album's station; four covers as two-by-two panes for an
  artist, a genre, a decade or a playlist, when there are four; else one.
- **The room** is the first cover's own colour, darkened and flat: its hue,
  its saturation held to 0.5, brightness 0.14. `ImagePipeline` works the
  average colour out once per cover (8 × 8 pixels) and keeps it; until it
  is known, the room is Cabinet.
- **The bands** around the window: flat, Copper outside and Glow inside.
  On the air, and only then, they are the tubes' own oranges with one soft
  glow on the room.
- **Your Station, Discovery and Loved** have no one seed to show: their
  window holds the core, flat — a warm white for Your Station, a paler one
  for Discovery, a rosier one for Loved — and lit, from its top to its
  foot, while on the air.
- **No name in the art.** The station's name is real Text under or beside
  it, in the reader's text size; a station's page sets its title in the
  serif right under the art, so the art no longer repeats it.
- **Under 60 pt** (rows, the mini player) the bands are heavier and the
  window shows one cover: four would be specks.

## The turntable

Now Playing's cover is a record (`NowPlaying/Turntable.swift`; its
measures, plain arithmetic, in `NowPlaying/TurntableMeasures.swift`). The
photographer, 8 November 2026: "Ik vind de platenspeler ideeen leuk maar
dan zou ik ook de plaat willen zien draaien met de album art er op het
liefst in een soort perspectief van licht erboven." Sketch C rendered it
([design/turntable-c.png](design/turntable-c.png)); sketch D drew it
([design/nowplaying-after.png](design/nowplaying-after.png)), and that is
what was built first. Then, on the TestFlight build with their own library
the same day:

> "Kun je de platenspeler iets leuker maken, de hoes er achter zetten en de
> naald zetten op welk nummer het is van het album"

So the sleeve stands behind the deck, the record shows the album's songs,
and the needle sits on the playing one:

- **The deck,** tipped back 46° (`rotation3DEffect`, perspective 0.4): a
  matte plinth with one soft falloff of the light from above, on the
  plinth only; a matte platter.
- **The sleeve:** the album's cover, upright behind the deck, as if the
  record had just come out of it. Not tipped: a flat square, 0.66 of the
  plinth's width (about the record's own width seen as far back as the far
  edge; larger, it spanned the far edge and read as a wall), above the
  record, a little left of the middle and clear of the arm's pivot. Its
  lower part is hidden behind the plinth's far edge. The one radius for
  artwork, 6 pt: a sleeve's sharper corner would be a second radius. A
  little in the shade (black at 0.14), so it does not outshine the record
  in front of it, and a hard, unblurred shadow cast forward onto the
  plinth by the same light as the arm's, short of the platter. An image,
  drawn once.
- **Room for both** (`TurntableLayout`): the deck as wide as it fits, as
  before; the sleeve shows 60% of itself above the far edge, and the deck
  gives up to a tenth of its width for that; with less room less of the
  sleeve shows, and under 30% it is left out. Sleeve and deck are centred
  together. On an iPhone 17 Pro with a station's dial (370 × 331 points
  for the record) the deck is 285 wide under a 188-point sleeve; without
  the dial it keeps its 317, under 209; on an iPhone SE there is no room,
  and no sleeve; in a 13-inch iPad's left column, 705 under 466. No cover,
  no sleeve, and the deck stays where it was.
- **The picture disc:** the song's cover cut round on vinyl, fine groove
  rings over it at low opacity. One faint pair of sheen wedges, half a turn
  apart, that do not turn: the light stays where it is while the record
  turns under it.
- **The album's songs as bands** (`TurntableSide`): a darker ring with a
  faint light edge where one song ends and the next begins, as the smooth
  vinyl between a record's tracks shows. The songs of the playing song's
  disc (`LibraryStore.tracks(inAlbum:)`, in disc and track order), from
  the outer groove (the first) to the run-out by the label (the last), each
  as wide as it is long. No album, an album the library does not know, or
  a disc of one song: no bands. The record's three made-up gaps went.
- **The label:** a flat colour from the cover (its average colour,
  `ImagePipeline.averageColor`, as a station's room has it: the hue, the
  saturation held to 0.45, brightness 0.3), and on it, printed straight and
  small in paper white, the album's title in the serif above the hole and
  its artist under it; "Disc 2" under them when the album has several
  discs. No side, no speed: a file has neither. A fine ring in the same
  ink, where it was Glow. Until the cover's colour is known, the dark brown
  it was.
- **The arm:** a flat two-tone shape — a bone tube, a near-black headshell
  and counterweight, a pivot — with a hard, unblurred shadow. Its angle is
  where the song is on its album: (the lengths of the disc's songs before
  it + the time played) ÷ the disc's length, from the outer groove (about
  12°) to the label (about 34°), so the needle sits in the song's band and
  creeps inward through it. A song alone goes across the whole record, as
  before. Down on the record while it plays; lifted (a small rise, a longer
  shadow) when paused; on its rest beside the platter with nothing to play.
  Under Reduce Motion it fades between these instead of moving.
- **The cue:** when the song changes the arm lifts (0.14 s), swings to the
  new song's band (0.32 s) and drops (0.14 s): 0.6 s, eased. In an album's
  own order the new band begins where the last one ended, so the arm lifts
  and drops where it is. Under Reduce Motion it fades to the new place.
- **The spin:** a turn in 10 s, and a coast to a stop of 0.8 s when the
  music pauses.

Not built, though sketch C had them: a 33⅓ selector (the record turns at
six turns a minute, so it would say what is not so) and a pilot light
while it plays (light means on air, and only a station is).

The battery, as the photographer asked ("Als batterij een zorg wordt…"):

- The disc — cover, grooves, the bands between the songs, the label and
  its words — is drawn once into one layer (`drawingGroup`); turning it
  changes only that layer's rotation. Nothing else on the deck is redrawn
  while it turns. The values the record is drawn from are taken before the
  timeline, so each frame hands it the same ones and it is not drawn again;
  the label's colour arrives once per cover and is not animated.
- The sleeve is an image, drawn once, outside the turning layer; its
  shadow is drawn with the plinth.
- It turns slowly, a turn in 10 s rather than a real 33⅓'s 1.8 s ("mag ie
  nog veel zachter draaien hoor"), on a timeline of at most 20 frames a
  second (1.8° a frame), and the timeline is paused whenever the record
  rests: at rest the deck costs nothing.
- It turns only while all of these hold: Now Playing shows the record (not
  closed, not the lyrics or the queue), the music plays, the app is active,
  Reduce Motion is off, Low Power Mode is off (`ProcessInfo`, kept up to
  date by its notification), and Settings › Playback › Spin the Record is on
  (`AppSettings.spinRecord`, on by default). Otherwise it rests at its angle.
- The arm reads the song's position itself, in steps of a 400th of the way
  from the outer groove to the label (a twentieth of a degree), so most of
  the player's twice-a-second ticks redraw nothing: on a forty-minute side
  the arm moves once in six seconds. Now Playing works out the album's
  side from the song alone, not its clock, so it is not evaluated twice a
  second either.
- The cue is three animations set off by the change of song (`withAnimation`
  on the arm's state, and the swing keyed to the song), not a timeline;
  while the arm is up it does not read the clock.
- The mark next to the station's name no longer breathes (see the mark).

The deck is hidden from VoiceOver; every control around it is Apple's.

## The launch screen

White by day, Cabinet by night (`LaunchBackground`). At night the icon,
opened, grows into its own room rather than into a grey; by day the
launch screen is white, a step from Home's paper (not yet changed with
sketch D: see Not done yet). The step from Cabinet to
Home's black is the one moment the screen changes anyway — the app
arriving — where the old near-black (#141414) made the same step for no
reason of its own. While the session is restored, the app keeps the
launch screen's ground (`RootView`), so there is one step, not two.

## Where it lives

| Piece | Code |
|---|---|
| Colours, grounds, type, the one radius, headings, buttons, hairlines | `Theme.swift` (`Theme.Arch`, `Theme.accent`, `Theme.onAccent`, `Theme.ground`, `Font.serif`, `SectionHeader`, `ListHeading`, `Eyebrow`, `Hairline`, `.prominent`, `.secondary`), `Assets.xcassets/AccentColor` |
| Facts in words | `Components/RelativeDay.swift`; a station's kind, `StationText` in `Home/HomeParts.swift`; when a station last played, `HomeShelves.stationDates` |
| The mark, its shapes | `Components/ArchMark.swift` (`ArchMark`, `ArchMarkFace`, `ArchCut`, `ArchLine`, `ArchCore`, `ArchWindow`) |
| Station artwork, lit on the air | `Components/StationArtwork.swift`; the cover's colour in `ArtworkView.swift` (`ImagePipeline.averageColor`) |
| Home: "Tonight", Your Station flat beside its name, Mixes, Played lately | `Home/HomeView.swift` (`HomeStationHero`, also on Radio while nothing plays) |
| Radio: on air, Stations, the dial | `Radio/RadioView.swift`; `Radio/RadioOnAirCard.swift` (`RadioOnAirCard`, `RadioThumbs`, `RadioDial`, also on a station's page and in Now Playing) |
| Now Playing: the record, its sleeve, the needle on the album's song, the station's name in Glow after its mark | `NowPlaying/Turntable.swift`, `NowPlaying/TurntableMeasures.swift` (checked by `dev/turntable-test.sh`), `NowPlaying/NowPlayingView.swift` |
| The mini player's station (11 pt, template, accent) | `NowPlaying/MiniPlayer.swift` |
| The welcome's mark coming on, About's | `Settings/ShellAppMark.swift`, `Settings/OnboardingView.swift`, `Settings/SettingsView.swift` |
| Mixes: square, their artists under them | `Components/Tiles.swift` (`MixCard`) |
| The launch screen: white by day, Cabinet by night | `Assets.xcassets/LaunchBackground`, and `RootView`'s launching phase |
| The icon | `Assets.xcassets/AppIcon.appiconset`, `dev/make-icon.py`, `dev/brand/icon.py` |
| The drawings | `dev/brand/` (`geom.py`, `icon.py`, `station.py`, `covers.py`, `render.js`); sketch D in `docs/design/` |

## Not done yet

- Sketch D is to be refined ("dan refinen we later wel"): the screens are
  built to it, and CI's screenshots are what to compare against it.
- The app icon still glows: it is the icon of the Arch's first round, and
  redrawing it flat is a decision of its own. The launch screen likewise.
- The library's long lists (Artists, Songs, Playlists, an album's or a
  playlist's songs) keep the system's grounds, not paper.
- `dev/brand/station.py` still draws every station lit; the app draws them
  flat unless on the air.
- The Radio tab's glyph is still SF Symbols' radio waves: the board's arch
  there needs the heavy cut as a custom SF Symbol (a `.symbolset` with its
  weights), which wants Apple's SF Symbols app to make and check.
- Icon Composer's layered `.icon` (Liquid Glass's depth on iOS 26) wants
  Icon Composer on a Mac; the flat icons above are what iOS 18-style
  appearances need and what iOS 26 shows from them.
