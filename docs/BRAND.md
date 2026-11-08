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
app differs from it, it says so below.

The cabinet's arch as the frame of everything: two tubes of light around a
window, and in the window the one thing that changes — the music.

Jukebox stays a sibling of Numa in restraint and in care — Apple's own
controls, one filled button a screen, small grey spaced section labels —
and no longer in its shapes.

## The rules

1. **The arch only ever means a station.** The mark, a station's artwork,
   the mark before a station's name in Now Playing and the mini player.
   Nothing else is drawn as an arch.
2. **Lit means endless.** Only the radio, which plays for as long as it is
   left on, is drawn lit. Home's mixes, which end, stay square collages with
   no glow; albums and playlists stay square and uncropped.
3. **One accent pair.** Copper by day, Glow by night: one hue seen in two
   exposures. Nothing else in the interface is orange; the tubes' own
   oranges are for art only (the icon, a station's artwork, the welcome).
4. **No jukebox cabinet.** No bubble tubes, chrome, grilles or selector
   buttons — no Wurlitzer. The arch and its light are the whole of it.
5. **Native first.** The chrome is Apple's: tab bar, lists, sheets, the
   system Slider tinted with the accent, SF Symbols for every glyph but the
   mark.

## Colours

`Jukebox/Components/Theme.swift`, `Theme.Arch`; the accent pair is the asset
catalog's `AccentColor`.

| Name | Hex | Use | Contrast |
|---|---|---|---|
| Copper | `#A84A17` | The accent in light mode: tint, selection, the one filled button | 5.74:1 on white, 5.15:1 on `#F2F2F7`; white on it 5.74:1 |
| Glow | `#FFB54D` | The accent in dark mode, and wherever Jukebox is always dark (Now Playing, the art) | 11.97:1 on black, 9.70:1 on `#1C1C1E`, 10.86:1 on Cabinet |
| Ink | `#2A1505` | Words and glyphs on Glow (`Theme.onAccent` in dark mode) | 9.91:1 on Glow |
| Cabinet | `#1E0A07` | The ground of the icon, the welcome's icon, Your Station's card on Home, the Radio tab's wide card, every lit core; the launch screen in dark mode | white on it 19.06:1 |
| Cabinet haze | `#4A1D0F` | The top of a lit ground's gradient, where the tubes light the room | — |
| Filament | `#FFF4DE` | The core's light | — |
| Mark core | `#F7A136` / `#FFF1D6` | The lit mark's core, by day / by night (decoration: amber on white is 2.08:1, never for words) | — |
| Outer tube | `#F07E36` → `#D45A22` | Art only: the outer tube, top to feet | — |
| Inner tube | `#FFB44C` → `#F49A30` | Art only: the inner tube | — |
| Tube hearts | `#FFC08A`, `#FFE3AE` | Art only: the hot line down each tube | — |
| Core in art | `#FFFBF0` → `#FFD58E`, bloom `#FFC46A` | Art only: the lit core | — |
| Room glow | `#FF8A2A` | Art only: the light the tubes throw (the icon) | — |

Contrast as WCAG 2 computes it (`python3 dev/brand/contrast.py`).
Now Playing is always dark, so there the accent is always Glow; the
artwork's room is always dark, so the on-air badge on it is Glow too.

## The mark

Two tubes of light with round caps and a core, concentric about the spring
point (16, 14) in a 32-unit box: width 24, height 28, baseline 30, tube
stroke 2.6, gaps 2.2. [mark.svg](brand/mark.svg) (lit on light),
[mark-dark.svg](brand/mark-dark.svg) (lit on dark),
[mark-template.svg](brand/mark-template.svg).

- **Lit:** the tubes in the accent, the core as light (amber by day, a warm
  white by night), a soft bloom where it is dark around it.
- **Template:** every part in the foreground colour.
- **The heavy cut, 20 pt and below** (Tonearm's optical cut): stroke 3.2,
  gaps 1.9, a core 5.6 wide, width 26, so the three parts stay three at 16
  and 11 pt ([mark-small-template.svg](brand/mark-small-template.svg)).
- **Breathing:** while a station plays, the tubes dim to half and come back,
  one after the other, 1.4 s a step. Never under Reduce Motion.
- **Warm-up:** on the welcome screen the icon's tubes start as cold glass and
  light one by one — the outer tube, the inner, the core — in about 1.2 s.
  Under Reduce Motion it is lit at once.

`dev/brand/geom.py` is the one source of the geometry; `ArchCut` in
`ArchMark.swift` carries the same numbers. Change both together.

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
the app's numbers (`StationArtCut` in `StationArtwork.swift`).

- **The window** is the arch, filled with the station's music: one cover for
  a song's or an album's station; four covers as two-by-two panes for an
  artist, a genre, a decade or a playlist, when there are four; else one.
  The board's slices for genres and decades were dropped: every station
  with four covers uses panes.
- **The room** is the first cover's own colour, darkened: its hue, its
  saturation held to 0.5, brightness 0.14 (0.28 where the tubes light it).
  `ImagePipeline` works the average colour out once per cover (8 × 8
  pixels) and keeps it; until it is known, the room is Cabinet.
- **The tubes** around the window, with a soft glow on the room.
- **Your Station, Discovery and Loved** have no one seed to show: their
  window holds the lit core. Your Station's is the filament; Discovery's a
  paler, newer light; Loved's a warmer, rosier one.
- **The name** is drawn under the window only from 200 pt (a station's
  page). Shelves keep real Text under the tile, which follows Dynamic Type.
- **Under 60 pt** (rows, the mini player) the tubes are heavier and the
  window shows one cover: four would be specks.

## The launch screen

White by day, Cabinet by night (`LaunchBackground`). At night the icon,
opened, grows into its own room rather than into a grey; by day the
launch screen is the page Home is drawn on. The step from Cabinet to
Home's black is the one moment the screen changes anyway — the app
arriving — where the old near-black (#141414) made the same step for no
reason of its own. While the session is restored, the app keeps the
launch screen's ground (`RootView`), so there is one step, not two.

## Where it lives

| Piece | Code |
|---|---|
| Colours | `Theme.swift` (`Theme.Arch`, `Theme.accent`, `Theme.onAccent`), `Assets.xcassets/AccentColor` |
| The mark, its shapes, the live icon | `Components/ArchMark.swift` (`ArchMark`, `ArchCut`, `ArchLine`, `ArchCore`, `ArchWindow`, `ArchAppIcon`) |
| Station artwork | `Components/StationArtwork.swift`; the cover's colour in `ArtworkView.swift` (`ImagePipeline.averageColor`) |
| Home's toolbar mark (16 pt, lit), the loading screen (48 pt) | `Home/HomeView.swift`, `Home/HomeParts.swift` |
| Your Station's card on Home (Cabinet, the lit core) | `Home/HomeView.swift`, `HomeStationHero` |
| The Radio tab's cards; the dial's words | `Radio/RadioView.swift`; `Radio/RadioOnAirCard.swift` (`RadioDial`), also on a station's page |
| Now Playing: the breathing mark over "Playing From", the station's name in Glow, the thumbs up in Glow, the progress in Glow | `NowPlaying/NowPlayingView.swift`, `NowPlaying/NowPlayingParts.swift` |
| The mini player's mark while a station plays (11 pt, template, accent) | `NowPlaying/MiniPlayer.swift` |
| The welcome's warm-up, About's icon | `Settings/ShellAppMark.swift`, `Settings/OnboardingView.swift`, `Settings/SettingsView.swift` |
| Mixes: square, a scrim under the title, no glow | `Components/Tiles.swift` (`MixCard`) |
| The launch screen: white by day, Cabinet by night | `Assets.xcassets/LaunchBackground`, and `RootView`'s launching phase |
| The icon | `Assets.xcassets/AppIcon.appiconset`, `dev/make-icon.py`, `dev/brand/icon.py` |
| The drawings | `dev/brand/` (`geom.py`, `icon.py`, `station.py`, `covers.py`, `render.js`) |

## Not done yet

- The Radio tab's glyph is still SF Symbols' radio waves: the board's arch
  there needs the heavy cut as a custom SF Symbol (a `.symbolset` with its
  weights), which wants Apple's SF Symbols app to make and check.
- Icon Composer's layered `.icon` (Liquid Glass's depth on iOS 26) wants
  Icon Composer on a Mac; the flat icons above are what iOS 18-style
  appearances need and what iOS 26 shows from them.
