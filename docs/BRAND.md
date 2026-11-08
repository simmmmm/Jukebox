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
   (`Theme.ground`). Under Now Playing the record's own: the album's side
   as land, or a wall and a floor of the cover's colours, Cabinet where
   there is no cover (below). No vignettes, no gradients behind a screen. The system's own grounds where the system
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
    buttons — no Wurlitzer. The arch is the whole of it; the sleeve and
    its record on Now Playing are drawn, not rendered.
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
| Land | `#131010`, `#211A17`, `#3F3127` | Now Playing's ground in D2: the ground, its grooves, the grooves played (below) | white on the played grooves 12.50:1 |
| Cabinet | `#1E0A07` | Now Playing's ground where there is no cover to take one from, the app icon's, the welcome's mark's tile, a station's room until its cover's colour is known; the launch screen in dark mode | white on it 19.06:1 |
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
voor de steunkleur?", and then "Of een complementaire kleur, kijk maar wat
het beste uitkomt". On Now Playing, what is Glow elsewhere — the progress,
the station's name and mark, a thumb or heart given, the dial, Up Next's
toggles — takes a colour of the cover that plays
(`JukeboxKit/…/Artwork/CoverAccent.swift`, the steps in its comment;
`dev/accent.py` is the same in Python for sketches):

- the cover's second colour: a colour of its own that stands apart from
  its main one (60° of hue or more) — the orange sun on a purple sky, the
  teal corner of a pink haze — so the controls stand out from the art
  above them and still belong to it. Tried against the main colour and the
  true complement (`docs/design/accent-choice.png`): the main colour melts
  into the record; the complement brings a colour the cover does not have
  (acid lime under a sunset, cyan under red stripes);
- a cover with one colour: that one; with none (black and white, grey):
  Glow;
- the hue the eye picks out (a histogram of hue, vivid parts weighed most),
  not the average, which makes red stripes on cream beige;
- at Glow's lightness, so it weighs on Cabinet what Glow does and only the
  hue changes from album to album; a little darker where a hue has no room
  there (red), never under Oklab 0.70: 6.7:1 or more on Cabinet, and as
  much on D2's land (4.7:1 where it crosses the grooves played); D1's
  floor is darkened until the accent on it is 4.5:1 or more (below);
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
  sleeve, below).

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

## Now Playing: the sleeve, and the side as land

Now Playing's cover was first a record player. The photographer, 8
November 2026: "Ik vind de platenspeler ideeen leuk maar dan zou ik ook de
plaat willen zien draaien met de album art er op het liefst in een soort
perspectief van licht erboven." Sketch C rendered it
([design/turntable-c.png](design/turntable-c.png)); sketch D drew it
([design/nowplaying-after.png](design/nowplaying-after.png)): the song's
cover as a picture disc on a deck tipped back, and then, on "Kun je de
platenspeler iets leuker maken, de hoes er achter zetten en de naald zetten
op welk nummer het is van het album", the sleeve behind the deck and the
arm on the song's place on its album. On the TestFlight build it still
stood apart from the page:

> "Het moet minder een los object zijn en meer verweven zitten met de
> pagina"

Sketch E drew the sleeve as the thing itself and the page's ground as the
record's world ("Maak ook even een hele andere abstractere variant waarbij
de hoes de hoes is maar de achtergrond helemaal anders"), and the
photographer chose, the same day:

> "Dus ik denk dat d1 en d2 vooral d2 het best gaan werken. D1 is reduced
> motion/batterij besparing d2 normaal. F1 toch net iets te extreem denk"

So the deck, its plinth and its arm went. What was built:
`NowPlaying/SleeveRecord.swift` (the sleeve and its record),
`NowPlaying/NowPlayingGround.swift` (the ground, and the one timeline), the
arithmetic in `NowPlaying/TurntableMeasures.swift` (checked on Linux by
`dev/turntable-test.sh`), D1's colours in JukeboxKit's
`Artwork/CoverWall.swift` (`CoverWallTests`).

- **The sleeve:** the album's cover as printed card, square, at the one
  radius for artwork (6 pt). A thickness at its foot and a hair of its open
  edge, in the cover's own colour darkened (its average with 45% black, so
  a cream sleeve has a light edge); paper grain (a fixed noise, white or
  black at up to 15%); faint ring wear where a record has pressed it (white
  at 4%, softened); a little light along its top edge, its open edge a
  little in shade; and a soft shadow from a light above, four shadows
  each cast on their own: black at full strength on the land, on a wall the
  wall's own dark (its hue at saturation 0.55, brightness 0.10) and softer,
  as a shadow falls on coloured paper. Upright it stands at the margin, as
  large as leaves a third of its width for the record before the screen's
  edge: 284 points on an iPhone 17 Pro, with 94 points of record. On the
  iPad sideways the whole record shows, and the two are centred in their
  column (`SleeveLayout`). In the middle of the room the page gives it.
- **The record:** black vinyl half out of the sleeve's open edge, 0.955 of
  the sleeve, its centre 8 points beyond the edge. Fine grooves (white at
  4.5%, every third at 7.5%), the album's songs as bands (`TurntableSide`:
  the songs of the playing song's disc, each as wide as it is long, the
  smooth darker vinyl between two with a light edge; no album or a disc of
  one song, no bands), the run-out, and the label: the cover's colour (its
  average's hue, the saturation held to 0.45, brightness 0.3) with the
  album's title in the serif above the hole and its artist under it,
  printed small in paper white, "Disc 2" when the album has discs. Two
  faint wedges of sheen on the grooves, which do not turn. The label turns
  a turn in 10 s, as before ("mag ie nog veel zachter draaien hoor"), and
  coasts to a stop in 0.8 s when the music pauses.
- **D2, the side as land** — Now Playing as it normally is. The page's
  ground is the album's side as a record far larger than the screen. On an
  iPhone 17 Pro its grooves run from 1440 points from its centre to 420,
  the centre below the screen and 300 from the left, a groove every 5.2
  points; on the iPad sideways from 1900 to 700, the centre 820 from the
  left, every 5.6; other screens in proportion to their diagonal
  (`LandGeometry`). One dark tone (#211A17 on #131010, every fifth groove a
  little wider), crossing the page as gentle arcs: a horizon. One band per
  song of the album, as wide as the song is long, 26 points of smooth land
  between two songs with a faint light edge. The playing song's band starts
  28 points above its title, under the sleeve; its grooves played so far
  are a tone lighter (#3F3127), a groove at a time. On a song change the
  land moves on one band in 0.6 s, eased, so the new song's band starts
  where the last one's did; another album's land fades in over 0.4 s, and
  the old one stays where it was until it has. A song with no album, or
  alone on its disc, is one band: the whole side.
- **D1, the wall** — the same page when nothing may move: Reduce Motion,
  Low Power Mode, or Settings › Playback › Spin the Record off. Two flat
  fields of the cover's own colours (`CoverWall`): a wall from the top of
  the screen to the sleeve's foot — across the screen upright, across the
  sleeve's side to the controls' column on the iPad sideways — and a floor
  under the title and the controls. The wall is the cover's colour that
  stands out from the sleeve (a dark cover's light, a light cover's ink),
  between Oklab lightness 0.36 and 0.88, chroma at most 0.12; the floor is
  the cover's own dark, darkened until the accent on it is 4.5:1 or more and
  white 7:1 or more. A light wall gets Ink at the top (the grabber, Close,
  More) and a dark status bar (the presentation turns light; its words stay
  white); on the iPad sideways, where the status bar runs over the wall and
  the floor at once, the wall is darkened until white reads on it, 4.5:1.
  Nothing turns, the label neither. Under the lyrics and the queue, where
  there is no sleeve to stand on it, all floor. Without a cover, and until
  its colours are known, Cabinet. Sketch E's Quiet Rooms comes out #B7B38E
  over #2E2F1F (it drew #C2BD97 over #2F3020), Night Machines #A7614A over
  #372018 (#A15841 over #331B13).

Not built, though sketch E had it: a faint wedge of light across the land
(5%, from the land's centre), a full-screen gradient for a change the eye
does not find on a phone.

The battery, as the photographer asked ("Als batterij een zorg wordt…"):

- The land is one bitmap, drawn once per album's side and screen, off the
  main thread, never per frame: at most 0.75 pixels a point and 2900 a
  side — an iPhone 17 Pro's is 2161 pixels, 18 MB, an iPad's at most 32 MB
  — and let go of in D1. Its grooves are 1.5 points wide, dark on dark:
  drawn at 0.71 pixels a point and shown at 3 they read as drawn at 3, a
  little softer. Radio plays a new album nearly every song, and each is
  drawn once.
- The grooves played are the same bitmap again in the lighter tone, clipped
  to a ring that changes only when the song reaches the next groove: on
  Velvet Songs' fifth song (262 s, a band of 24 grooves) once in 10.5 s.
  Only the small view that reads the song's clock is evaluated twice a
  second, and most of those times it changes nothing.
- One timeline turns all that turns: at most 20 frames a second while the
  label alone turns (1.8° a frame), 30 when the land turns too, and only
  while the sleeve is on the screen, the music plays, the app is active and
  the page is D2. At rest it is paused, and the page costs nothing.
- The land is ready to turn for sketch H (a record "not quite round", its
  lines swaying at 33⅓ or on the beat): its bitmap is shown oval first,
  then turned about a pin that may sit off its true centre, on that same
  timeline. The numbers are `RecordMotion`'s, in one place: 33⅓ a minute,
  the pin 0 points off, 0% oval. Round and pinned at its centre, turning it
  would change no pixel, so until H gives other numbers it is not turned.
- The record is drawn once into one layer (`drawingGroup`) and only its
  rotation changes; the values it is drawn from are taken before the
  timeline, so each frame hands it the same ones. The sleeve, its grain
  and shadows, the record's shadow and the sheen are drawn once.
- The mark next to the station's name no longer breathes (see the mark).

The sleeve, the record and the ground are hidden from VoiceOver; every
control around them is Apple's.

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
| Now Playing: the sleeve and its record, the side as land (D2) or the wall (D1), the station's name in the accent after its mark | `NowPlaying/SleeveRecord.swift`, `NowPlaying/NowPlayingGround.swift`, `NowPlaying/TurntableMeasures.swift` (checked by `dev/turntable-test.sh`), `NowPlaying/NowPlayingView.swift`; the wall's colours in JukeboxKit's `Artwork/CoverWall.swift` |
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
