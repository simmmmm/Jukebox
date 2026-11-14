# Jukebox's brand: the Arch

The cabinet's arch frames everything: two bands around a window, and in the
window the one thing that changes, the music.

## Where it came from

Jukebox first wore Numa's look, eclipse and all. The photographer, on
TestFlight, 8 November 2026:

> "Het heeft nu wel heel weinig eigen branding en je hergebruikt nu het numa
> logo daar mag je wel meer eigen vorm aan geven."

Of four directions, Arch, Tonearm, Selector and Dial
([comparison.png](brand/comparison.png)), he chose: "Die arch is leuk."
What was built is the judge's synthesis, "Arch, sharpened". It takes:

- from Arch: the mark, icon, colours, station art and motion
  ([board.png](brand/board.png) is the board as judged; where the app
  differs, this file says so);
- from Tonearm: Copper as the light-mode accent, the heavy cut of the mark,
  and the station's name in the art only from 200 pt (later dropped);
- from Dial: the Familiar ⟷ Adventurous dial, its words in the accent,
  under the station on the air;
- from Selector: "lit means endless", every station glowing at once (later
  replaced).

## What it reaches for: sketch D

The same day the Arch still read as someone else's:

> "Ik vind het nogsteeds wel heel erg op Apple Music lijken … zo laat het
> wel heel erg weinig eigen smaak toe."

> "Kun je het design iets minder ai maken?"

Sketch D answered ([design/sheet-d.png](design/sheet-d.png); the screens in
`design/home-after.png`, `home-after-light.png`, `nowplaying-after.png`,
`radio-after.png`): light means on air, every other arch flat, the name out
of the art, Numa's small grey spaced labels out of the screens. He said:

> "Ja nice dit, maak dit maar dan refinen we later wel. Als batterij een
> zorg wordt moeten we ook ff kijken wat we daar aan kunnen doen."

Its rules, said as what to reach for ("niet 'minder ai' maar vooral meer
ziel", 14 November 2026), are [design/tells.md](design/tells.md). Walk its
checklist before a screen ships. `docs/design/` is the reference; a screen
that differs says why. Jukebox stays Numa's sibling in restraint and care
(Apple's controls, one filled button a screen); its shapes and labels are
its own.

## The rules

1. **The arch means a station:** the mark, a station's art, the mark before
   a station's name in Now Playing and the mini player. Nothing else.
2. **Light means on air.** Only the station playing is lit: tubes in their
   oranges, one soft glow on its room (`StationArtwork`, by
   `RadioController.stationOnAir`). Every other arch, the mark too, is
   flat: Copper outside, Glow inside, flat core, with no blur or bloom.
   Buttons, cards and grounds are unlit. Home's mixes, which end, are square collages; albums and
   playlists square and uncropped.
3. **Flat grounds,** one colour with no vignette or gradient: Paper by
   day, Night by night (`Theme.ground`); under
   Now Playing the record's own; the system's where it draws a list
   (Settings, the library's long lists).
4. **Titles in a serif, as on sleeves:** New York at regular weight,
   `Font.serif(_:)` (`.system(style, design: .serif, weight: .regular)`, so
   it follows Dynamic Type). For page titles, section headings, and
   navigation-bar titles large and inline (`Theme.styleNavigationBars`, at
   launch: `UIFontDescriptor.withDesign(.serif)` scaled by
   `UIFontMetrics`). Home's large title names the part of the day
   ("Tonight", `RelativeDay.partOfDay`). All else SF Pro; times and counts
   in tabular figures (`.monospacedDigit()`).
5. **Sentence-case headings:** "Mixes", "Played lately", "Stations"
   (`SectionHeader`, `ListHeading`). One small label a screen at most, "On
   air" (`Eyebrow`, in the accent). Never tracked uppercase.
6. **Facts:** "Made at 06:00", "Played Thursday", "Not played yet", a mix's
   artists (`RelativeDay`). Each line says something new ("Endless music
   from everything you love" and "Plays on for as long as you listen"
   went). The radio's reasons show only in the queue. The dial shows its
   two ends, Familiar and Adventurous, and nothing else.
7. **On the ground:** content on the page, parted by hairlines and space
   (`Hairline`). One radius, 6 pt, for artwork (`Theme.Radius.artwork`);
   system controls keep their shapes. One filled button a screen: a plain
   accent rectangle, 6 pt corners, unlit. Other actions are a word in the
   accent or a plain SF Symbol, never an icon-and-label pill.
8. **Editorial, left-aligned:** titles, rows and Now Playing's words at the
   margin; shelves run off the right edge so the next tile peeks in. Centre
   only where Apple does: the transport, a page's own header.
9. **One accent pair:** Copper by day, Glow by night, one hue in two
   exposures. Nothing else is orange; the tubes' oranges are for the
   station on the air and the app icon. Now Playing alone takes its
   cover's accent.
10. **The arch is the whole cabinet:** no bubble tubes, chrome, grilles or
    selector buttons, no Wurlitzer. The sleeve and record are drawn, not
    rendered.
11. **Native first:** Apple's tab bar, lists, sheets, the system Slider
    tinted with the accent, SF Symbols for every glyph but the mark.

## The 4-point grid

Every distance and size is on a 4-point grid, on both platforms: 4, 8, 12,
16, 24, 32 and multiples (`Theme.Space`). The photographer, 14 November
2026: "zorg dat alles past op een 4pt grid". `dev/grid-check.py` checks it.
The one radius, 6, is the brand's own and not a distance. What is drawn in
its own units (the mark, a station's art, the sleeve and record, Now
Playing's ground) and font sizes are outside the grid; a line marked
`grid-ok` says why (a hairline is a pixel; the system's grabber is 36 by 5).

## Colours

`Jukebox/Components/Theme.swift` (`Theme.Arch`, `Theme.ground`); the
accent pair is the asset catalog's `AccentColor`. Contrast is WCAG 2's
(`python3 dev/brand/contrast.py`).

| Name | Hex | Use | Contrast |
|---|---|---|---|
| Copper | `#A84A17` | Light-mode accent: tint, selection, the filled button, text buttons; outer band of a flat arch | 5.74:1 on white, 5.15:1 on `#F2F2F7`; white on it 5.74:1 |
| Glow | `#FFB54D` | Dark-mode accent, and where Jukebox is always dark (Now Playing, the art); inner band of a flat arch | 11.97:1 on black, 9.70:1 on `#1C1C1E`, 10.86:1 on Cabinet |
| Ink | `#2A1505` | Words and glyphs on Glow (`Theme.onAccent`, dark) | 9.91:1 on Glow |
| Paper | `#F6F3EE` | Main screens' ground by day | — |
| Night | `#121110` | Main screens' ground by night | — |
| Land | `#131010`, `#211A17`, `#3F3127` | D2's ground, grooves, grooves played | white on grooves played 12.50:1 |
| Cabinet | `#1E0A07` | Now Playing without a cover; the app icon; the welcome mark's tile; a station's room until its colour is known; the dark launch screen | white on it 19.06:1 |
| Mark core | `#F7A136` / `#FFF1D6` | The flat mark's core, day / night; decoration only (amber on white 2.08:1) | — |
| Outer tube | `#F07E36` | On air only: outer tube and its glow | — |
| Inner tube | `#FFB44C` | On air only: inner tube and its glow | — |

Now Playing and a station's room are always dark, so the art reads the
same in either appearance. The icon's other oranges (tube feet, hot lines,
core light, room glow) are `dev/brand/icon.py`'s alone.

## Now Playing's accent: the cover's

"kan je de kleur uit de albumhoes pakken voor de steunkleur?", then "Of een
complementaire kleur, kijk maar wat het beste uitkomt" (8 November 2026).
On Now Playing, what is Glow elsewhere (progress, the station's name and
mark, a thumb or heart given, the dial, Up Next's toggles) takes a colour
of the cover: `JukeboxKit/…/Artwork/CoverAccent.swift`, steps in its
comment; `dev/accent.py` is the same in Python for sketches.

- **Its second colour,** 60° of hue or more from the main one (the orange
  sun on a purple sky, the teal corner of a pink haze): it stands out from
  the art and belongs to it. Tried against both
  (`docs/design/accent-choice.png`): the main colour melts into the record;
  the true complement brings a colour the cover lacks (acid lime under a
  sunset, cyan under red stripes).
- One colour: that one. None (black and white, grey): Glow.
- The hue the eye picks out (a hue histogram, vivid parts weighed most),
  not the average, which turns red stripes on cream beige.
- At Glow's lightness, so it weighs on Cabinet what Glow does and only the
  hue changes. A little darker where a hue
  has no room (red), never under Oklab 0.70: 6.7:1 or more on Cabinet and
  on D2's land, 4.7:1 over the grooves played. D1's floor darkens until
  the accent is 4.5:1 or more on it.
- Eased over 0.5 s on a song change; at once when Now Playing opens.

Elsewhere Copper and Glow stay. `docs/design/accent.png`: the test
library's covers with their accents.

## The mark

Two round-capped bands and a core, concentric about (16, 14) in a 32-unit
box: width 24, height 28, baseline 30, stroke 2.6, gaps 2.2.
[mark.svg](brand/mark.svg), [mark-dark.svg](brand/mark-dark.svg),
[mark-template.svg](brand/mark-template.svg).

- **Flat:** Copper outside, Glow inside, core amber by day, warm white by
  night. Never on air, so never lit.
- **Template:** all in the foreground colour; in the accent before a
  station's name (Now Playing, the mini player).
- **Heavy cut, 20 pt and below:** stroke 3.2, gaps 1.9, core 5.6 wide,
  width 26, so the parts stay three at 16 and 11 pt
  ([mark-small-template.svg](brand/mark-small-template.svg)).
- **Warm-up:** on the welcome screen the bands start as cold glass and fade
  on one by one, outer, inner, core, in about 1.2 s. At once under Reduce
  Motion.
- **Still while playing.** It once breathed; sketch D stilled it. Endless
  motion is a glow by other means, and beside the record it would run the
  screen at 60 fps where the record needs 30.

`dev/brand/geom.py` is the geometry's one source; `ArchCut` in
`Components/ArtMeasures.swift` carries the same numbers, for both
platforms. Change both together.

## The app icon

The mark lit on Cabinet, as a jukebox's tubes light their room: tubes in
their oranges with halos and a hot line each, the core, and floor and
window lit by them. Three appearances, single-size: default, dark (a darker
room), tinted (a grey ramp on black for the system to tint). All opaque
RGB, as App Store Connect wants. `python3 dev/make-icon.py` redraws them
from `dev/brand/icon.py` (Chromium through node's playwright).

## Station artwork

[stations.png](brand/stations.png), from `dev/brand/station.py` with the
app's numbers (`StationArtCut` in `Components/ArtMeasures.swift`, shared with Linux).

- **Window:** the arch, filled with the music. One cover for a song's or
  album's station; four as two-by-two panes for an artist, genre, decade
  or playlist when there are four, else one.
- **Room:** the first cover's colour, flat: its hue, saturation held to
  0.5, brightness 0.14. `ImagePipeline` takes the average once per cover
  (8 × 8 pixels) and keeps it; until then, Cabinet.
- **Bands:** flat Copper outside, Glow inside; on air only, the tubes'
  oranges with one soft glow on the room.
- **Your Station, Discovery, Loved** have no one seed: the window holds the
  core, flat (warm white, paler, rosier), lit top to foot while on air.
- **Name:** real text under or beside the art, at the reader's text size.
  A station's page sets its title in the serif right under the art.
- **Under 60 pt** (rows, the mini player): heavier bands, one cover; four
  would be specks.

## Now Playing: the sleeve and the side as land

The way here, 8 November 2026. "Ik vind de platenspeler ideeen leuk maar
dan zou ik ook de plaat willen zien draaien met de album art er op het
liefst in een soort perspectief van licht erboven." Sketch C rendered it
([design/turntable-c.png](design/turntable-c.png)); sketch D drew it
([design/nowplaying-after.png](design/nowplaying-after.png)): the cover as
a picture disc on a deck tipped back. "Kun je de platenspeler iets leuker
maken, de hoes er achter zetten en de naald zetten op welk nummer het is
van het album" put the sleeve behind the deck and the arm on the song's
place on its album. On TestFlight:

> "Het moet minder een los object zijn en meer verweven zitten met de
> pagina"

Sketch E made the sleeve the thing itself and the ground the record's world
("Maak ook even een hele andere abstractere variant waarbij de hoes de hoes
is maar de achtergrond helemaal anders"). He chose:

> "Dus ik denk dat d1 en d2 vooral d2 het best gaan werken. D1 is reduced
> motion/batterij besparing d2 normaal. F1 toch net iets te extreem denk"

The deck, plinth and arm went. Code: `NowPlaying/SleeveRecord.swift`
(sleeve, record), `NowPlaying/NowPlayingGround.swift` (ground, the one
timeline), `NowPlaying/TurntableMeasures.swift` (arithmetic, checked on
Linux by `dev/turntable-test.sh`), JukeboxKit's `Artwork/CoverWall.swift`
(D1's colours, `CoverWallTests`).

### The sleeve

- The cover as printed card, square, 6 pt radius.
- A thickness at its foot and a hair of its open edge, in its average
  colour with 45% black (a cream sleeve gets a light edge).
- Grain: fixed noise, white or black, up to 15%. Ring wear: white at 4%,
  softened.
- A little light on its top edge, its open edge a little in shade.
- Four soft shadows from above, each cast alone: black at full strength on
  the land; on a wall, the wall's dark (its hue, saturation 0.55,
  brightness 0.10), softer, as on coloured paper.
- Upright, at the margin, as large as leaves a third of its width for the
  record: 284 pt on an iPhone 17 Pro, 94 pt of record. iPad sideways: the
  whole record shows, both centred in their column (`SleeveLayout`). In
  the middle of the room, the page gives it.

### The record

- Black vinyl half out of the open edge, 0.955 of the sleeve, centre 8 pt
  beyond the edge.
- Grooves white at 4.5%, every third 7.5%.
- Bands for the songs of the playing song's disc, each as wide as it is
  long, smooth darker vinyl with a light edge between (`TurntableSide`).
  No album or a one-song disc: no bands.
- The run-out. The label in the cover's colour (average's hue, saturation
  0.45, brightness 0.3): album title in the serif above the hole, artist
  below, small, paper white; "Disc 2" when there are discs.
- Two faint sheen wedges on the grooves that hold still.
- The label turns once in 10 s ("mag ie nog veel zachter draaien hoor"),
  coasting to a stop in 0.8 s on pause.

### D2, the side as land

Normal Now Playing: the ground is the album's side, a record far larger
than the screen (`LandGeometry`).

| Screen | Grooves from centre | Centre | Groove every |
|---|---|---|---|
| iPhone 17 Pro | 1440 to 420 pt | below the screen, 300 from the left | 5.2 pt |
| iPad sideways | 1900 to 700 pt | 820 from the left | 5.6 pt |
| Others | scaled by diagonal | | |

- `#211A17` grooves on `#131010`, every fifth a little wider, crossing the
  page as gentle arcs: a horizon.
- One band per song, as wide as it is long; 26 pt of smooth land with a
  faint light edge between.
- The playing band starts 28 pt above the title, under the sleeve. Grooves
  played are `#3F3127`, a groove at a time.
- Song change: the land moves one band in 0.6 s, eased, so the new band
  starts where the old did. A new album's land fades in over 0.4 s; the
  old one stays where it was until it has.
- No album, or alone on its disc: one band, the whole side.

### D1, the wall

When nothing may move: Reduce Motion, Low Power Mode, or Settings ›
Playback › Spin the Record off. Two flat fields (`CoverWall`):

- **Wall,** top of screen to the sleeve's foot (iPad sideways: across the
  sleeve's side to the controls' column). The cover's colour that stands
  out from the sleeve (a dark cover's light, a light cover's ink), Oklab
  lightness 0.36 to 0.88, chroma at most 0.12.
- **Floor,** under title and controls: the cover's dark, darkened until the
  accent is 4.5:1 or more and white 7:1 or more.
- A light wall gets Ink at the top (grabber, Close, More) and a dark status
  bar; the presentation turns light, its words stay white. iPad sideways,
  where the status bar spans both, the wall darkens until white reads at
  4.5:1.
- Nothing turns, label included. Under lyrics and queue: all floor. No
  cover, or colours not yet known: Cabinet.
- Sketch E's covers, built (drawn): Quiet Rooms `#B7B38E` over `#2E2F1F`
  (`#C2BD97` over `#2F3020`); Night Machines `#A7614A` over `#372018`
  (`#A15841` over `#331B13`).

Left out of sketch E: a 5% wedge of light from the land's centre, a
full-screen gradient for a change the eye misses on a phone.

### The battery

"Als batterij een zorg wordt…":

- **Land:** one bitmap per album side and screen, drawn off the main
  thread, never per frame. At most 0.75 px a point and 2900 px a side:
  iPhone 17 Pro 2161 px, 18 MB; iPad at most 32 MB. Dropped in D1.
  Grooves are 1.5 pt, dark on dark: at 0.71 px a point shown at 3 they read
  as drawn at 3, a little softer. Radio plays a new album nearly every
  song; each is drawn once.
- **Grooves played:** the same bitmap in the lighter tone, clipped to a
  ring that changes only at the next groove: on Velvet Songs' fifth song
  (262 s, 24 grooves) once in 10.5 s. Only the small view reading the
  song's clock is evaluated, twice a second, mostly changing nothing.
- **One timeline:** at most 20 fps while only the label turns (1.8° a
  frame), 30 when the land turns too; only while the sleeve is on screen,
  music plays, the app is active and the page is D2. Otherwise paused, at
  no cost.
- **Ready for sketch H** (a record "not quite round", swaying at 33⅓ or on
  the beat): the bitmap is shown oval, then turned about a pin that may sit
  off-centre, on the same timeline. `RecordMotion` holds the numbers: 33⅓
  rpm, pin 0 pt off, 0% oval. Round and centred, turning changes no pixel,
  so until H it does not turn.
- **Record:** drawn once into one layer (`drawingGroup`); only rotation
  changes, with its values fixed before the timeline. Sleeve, grain,
  shadows, record shadow and sheen: drawn once.
- The mark by the station's name is still (see the mark).

Sleeve, record and ground are hidden from VoiceOver; every control around
them is Apple's.

## The launch screen

White by day, Cabinet by night (`LaunchBackground`). At night the opening
icon grows into its own room. By day white, a step from Home's paper (not
yet changed for sketch D). The step from Cabinet to Home falls when the app
arrives, when the screen changes anyway; the old near-black (`#141414`)
made it for no reason. While the session restores, the app keeps the
launch ground (`RootView`): one step, not two.

## On Linux

The same brand on GNOME, in GTK 4 and libadwaita's own controls
(`Linux/App/Style.swift`), and the same drawings, in cairo
(`Linux/App/Drawings.swift`, from `ArtMeasures.swift`):

- Copper by day, Glow by night, white and Ink on them, as libadwaita's
  accent; Paper and Night as the grounds.
- Titles in a serif, regular: New York, else Source Serif 4, Source Serif
  Pro, Noto Serif, DejaVu Serif. Times in tabular figures.
- One radius, 6 pt, for artwork; rows and tiles on the ground.
- A station's art as the iPhone draws it (`StationArt`): one cover or four
  panes, the room in the first cover's colour, the three cores, the small
  cut under 60 pt. Lit only on air, by `RadioController.stationOnAir`.
- Mixes, and playlists without an image, as collages of four.
- The mark on its tile on the sign-in page, still (no warm-up yet).
- Now Playing: the sleeve with its record half out, still. No land yet.

## Where it lives

| Piece | Code |
|---|---|
| Colours, grounds, type, radius, headings, buttons, hairlines | `Theme.swift` (`Theme.Arch`, `Theme.accent`, `Theme.onAccent`, `Theme.ground`, `Font.serif`, `SectionHeader`, `ListHeading`, `Eyebrow`, `Hairline`, `.prominent`, `.secondary`), `Assets.xcassets/AccentColor` |
| Facts in words | `Components/RelativeDay.swift`; a station's kind, `StationText` in `Home/HomeParts.swift`; last played, `HomeShelves.stationDates` |
| The mark | `Components/ArchMark.swift` (`ArchMark`, `ArchMarkFace`, `ArchLine`, `ArchCore`, `ArchWindow`); its numbers, `ArchCut`, in `Components/ArtMeasures.swift` |
| Station artwork | `Components/StationArtwork.swift`; cover colour in `ArtworkView.swift` (`ImagePipeline.averageColor`) |
| Home: "Tonight", Your Station, Mixes, Played lately | `Home/HomeView.swift` (`HomeStationHero`, also on Radio while nothing plays) |
| Radio: on air, Stations, the dial | `Radio/RadioView.swift`; `Radio/RadioOnAirCard.swift` (`RadioOnAirCard`, `RadioThumbs`, `RadioDial`, also on a station's page and Now Playing) |
| Now Playing | `NowPlaying/SleeveRecord.swift`, `NowPlaying/NowPlayingGround.swift`, `NowPlaying/TurntableMeasures.swift` (`dev/turntable-test.sh`), `NowPlaying/NowPlayingView.swift`; JukeboxKit's `Artwork/CoverWall.swift` |
| Mini player's station (11 pt, template, accent) | `NowPlaying/MiniPlayer.swift` |
| Welcome's mark coming on, About's | `Settings/ShellAppMark.swift`, `Settings/OnboardingView.swift`, `Settings/SettingsView.swift` |
| Mixes: square, artists under them | `Components/Tiles.swift` (`MixCard`) |
| Launch screen | `Assets.xcassets/LaunchBackground`, `RootView`'s launching phase |
| Icon | `Assets.xcassets/AppIcon.appiconset`, `dev/make-icon.py`, `dev/brand/icon.py` |
| Drawings | `dev/brand/` (`geom.py`, `icon.py`, `station.py`, `covers.py`, `render.js`); sketch D in `docs/design/` |

## Next

- Refine sketch D ("dan refinen we later wel"); compare CI's screenshots
  against it.
- Redraw the app icon and launch screen flat: they still glow, from the
  first round, and that is a decision of its own.
- The library's long lists (Artists, Songs, Playlists, an album's or
  playlist's songs) still use the system's grounds, not paper.
- `dev/brand/station.py` and the board still light every station; the app
  lights only the one on air.
- The Radio tab's glyph is still SF Symbols' radio waves. The board's arch
  there needs the heavy cut as a custom SF Symbol (a `.symbolset` with its
  weights), made in Apple's SF Symbols app.
- Icon Composer's layered `.icon` (Liquid Glass depth, iOS 26) needs Icon
  Composer on a Mac. The flat icons serve iOS 18-style appearances and
  what iOS 26 shows from them.
