# Jukebox's design system

One app on every client. The iPhone follows Apple's HIG, Linux GNOME's, and
the iPad and the Mac in a wide window copy Linux's window 1:1. Jukebox's own
soul sits on top of all of them: the Arch, Copper and Glow, the serif, flat
grounds (`docs/BRAND.md`, `tells.md`). Where the two HIGs disagree, or say
something odd, this page decides.

The photographer, 20 November 2026: "Laat een agent ook een design systeem
maken. We blijven teveel parity hebben. Apple hig en gnome hig nemen we
zeker mee hè maar er zitten gekke dingen in".

A new screen, or a change to one, starts here. A component changes on every
client in the same round.

## Tokens

One source: `Jukebox/Components/Tokens.swift` (Foundation only, in
`Package.swift`'s `shared` and the widget's sources). `Theme.swift`,
`JukeboxWidget.swift` and Linux's `Style.swift`, `Drawings.swift` read it.
Change a value there and nowhere else. The asset catalog's `AccentColor` is
the one copy left (Xcode reads it before any code runs): keep it equal to
`Tokens.accent`.

### Colour

| Token | Day | Night | For |
|---|---|---|---|
| `accent` | Copper `#A84A17` | Glow `#FFB54D` | What is chosen, playing or touched; the filled button; words that act |
| `onAccent` | `#FFFFFF` | Ink `#2A1505` | Words on the accent |
| `quietInk` | `#953F12` | `#FFB54D` | The quiet button's word, on the accent at 12 % |
| `ground` | Paper `#F6F3EE` | Night `#121110` | Every main screen, flat |
| `raised` | `#ECE7DF` | `#1B1918` | Sidebar, panel, bar; Home's cards |
| `raisedLighter` | `#F1EDE6` | `#242120` | Home's music to go on with |
| `lifted` | `#FBF9F5` | `#242120` | Menus, popovers, dialogs |
| `notice` | `#F6E6D1` | `#2E2517` | A soft warning (server out of reach) |
| quiet ink | secondary label | 60 % of the text | Facts (Apple's `.secondary`, Linux's `.fact`) |

Art only, never text: Cabinet `#1E0A07`, the mark's core `#F7A136` /
`#FFF1D6`, the lit tubes `#F07E36` and `#FFB44C` (`Tokens.Arch`). Now
Playing alone takes its cover's accent.

### Type

Titles in the serif at regular weight: New York on Apple
(`Font.serif(_:)`), the system's serif on Linux (`.serif`). Everything else
the system's sans. Times and counts in tabular figures.

| Token | Wide (pt = px) | iPhone | For |
|---|---|---|---|
| `pageTitle` | 40 / 48 | `.largeTitle` serif | A page's own title |
| `heroTitle` | 32 / 40 | `.title` serif | An album's, a station's head |
| `sectionTitle` | 24 / 32 | `.title2` serif | A section's heading |
| `panelHead` | 20 / 28 | `.title3` serif | The panel's head, a list's heading |
| `body15` | 15 / 20 | `.body` | Rows, buttons |
| `fact13` | 13 / 16 | `.footnote` | Facts |

### Space, radius, motion

- **Space**, the 4-point grid: 4, 8, 12, 16, 24, 32 (`Tokens.Space`). A
  page's margin is 20 on the iPhone, `DesktopMeasures` wide.
  `dev/grid-check.sh` walks both.
- **Radius**: 6 for artwork and the filled button and its twin. What holds
  them is concentric: a tile's hover 14 (6 + 8), Home's cards 18 (6 + 12).
  The system's own controls keep the system's shapes.
- **Motion**: 0.15 s for what appears under the pointer, 0.2 s for fades
  and hovers, 0.3 s for lyrics' lines (`Tokens.Motion`).

## Components

Each with its rule, its Apple form and its GNOME form.

### The filled button and its quiet twin
One filled button a screen: Play, Sign In, Try Again. Beside it in a page's
row, its twin: same size, on the accent at 12 %, `quietInk` (Shuffle, New
Picks, Stop, Continue). 36 tall, 96 wide at the least, 15 bold, 6 corners.
Play and its twin always as a pair, Play first.
- Apple: `.buttonStyle(.action)` / `.quietAction`, `PagePlayButtons`
  (`Components/Theme.swift`). Sign In and Try Again: `.prominent`.
- GNOME: `playButton` / `quietButton` (`Linux/App/Parts.swift`), CSS
  `button.page-button`, `button.quiet` (`Style.swift`). Sign In:
  `suggested-action`.

### Text buttons and plain symbols
Every other action is a word in the accent or a plain symbol. Never an
icon-and-label pill.
- Apple: `.buttonStyle(.secondary)`; SF Symbols, `.plain`.
- GNOME: `wordButton` (`flat accent word`), `iconButton` with `flat`;
  Adwaita's symbolic icons and `Glyphs` (`Style.swift`).

### Rows and lists
Content on the ground, parted by hairlines. Rows 48 tall, 64 with a cover.
The song playing in the accent. Songs are picked with Ctrl and Shift wide.
- Apple: `TrackRow` (`Components/TrackRow.swift`), `Hairline`; the iPhone
  adds a "…" on each row, as touch has no secondary click.
- GNOME: `TrackRow`, `trackList` (`Parts.swift`), `listview.rows`.

### Cards and the raised ground
Only Home's Your Station, the music to go on with and the offline notice
stand on a card: `raised`, flat, 18 corners at 12 in. No cards in cards.
- Apple: `HomeCardButtonStyle`, `HomeOfflineNotice` (`Home/HomeView.swift`).
- GNOME: `.home-card`, `.home-card.notice` (`Style.swift`, `Pages.swift`).

### Section headings
Sentence case, in the serif, a fact beside it ("Made at 06:00"), See All
when it goes somewhere. 40 above, 16 below wide.
- Apple: `SectionHeader`, `ListHeading` (`Theme.swift`).
- GNOME: `sectionTitle` (`Parts.swift`).

### The page title
Serif, left on the margin, at most one fact under it. Home's names the part
of the day ("This evening"). An album's, artist's, playlist's or mix's head:
the art, the title, the facts, the pair of buttons, the heart, the "…".
- Apple: the navigation bar's large title on the iPhone
  (`Theme.styleNavigationBars`); `PageTitle`, `PageHead`
  (`Components/WidePage.swift`) wide.
- GNOME: `pageTitle`, `heading` (`Parts.swift`, `Pages.swift`).

### Menus and context menus
Every song's menu in the same sections and order, on every client:

1. what its list does with it: Move Up, Move Down, Remove from Queue or
   Playlist; on a station Don't Play X Here, Dislike;
2. Play Next, Add to Queue;
3. Add to Playlist…, the heart, Rating, Start Radio;
4. Go to Album, Go to Artist, Credits;
5. Copy Link, Share, Don't Count Plays;
6. what cannot be undone (Delete Playlist), alone, last.

An album's, artist's, playlist's or mix's menu and "…" keep this order with
what applies (Play first on a tile, as it has no button). Menus sit on
`lifted`.
- Apple: `TrackMenu` (`Components/TrackRow.swift`), `Section`s; `.contextMenu`
  on the iPhone, a secondary click wide; `MoreMenu` (`WidePage.swift`).
- GNOME: `trackMenu`, `albumMenu`, `menuSections`, `popoverMenu`,
  `moreButton` (`Parts.swift`): GMenu sections.

### Sheets, drawers and popovers
- Apple: `.sheet` for a task (Add to Playlist, Settings), `.popover` wide
  for a choice; Play On in AirPlay's own picker.
- GNOME: `AdwDialog` for a task (`Choosers.swift`), `GtkPopoverMenu` for a
  choice, the panel as a drawer under 1280 (`Panel.swift`). Toasts for a
  moment's news (`MainWindow.toast`).

### Notices and empty states
A whole window's state (loading, couldn't load, no music): the platform's
status page, centred, sentence-case title, one action. A page with nothing
in it: one plain line at the margin, where its content would start.
- Apple: `ContentUnavailableView` (`Home/HomeParts.swift`,
  `Library/LibraryParts.swift`).
- GNOME: `emptyPage` (status page) and `emptyLine` (`Parts.swift`).

### The player bar and the mini player
Wide: the bar, 88 across the window's foot, three zones from
`DesktopMeasures`; Play 40, the rest 32. The iPhone: the system's tab
accessory (the mini player), the arch before a station's name.
- Apple: `PlayerBar` (`NowPlaying/PlayerBar.swift`), `MiniPlayer`
  (`NowPlaying/MiniPlayer.swift`).
- GNOME: `PlayerBar.swift`, `.player-bar`.

### Artwork and arch artwork
Square, 6 corners, uncropped: albums, playlists, mixes (a collage of four).
The arch means a station and nothing else; only the one on air is lit.
Without a cover, the title sleeve.
- Apple: `ArtworkView`, `StationArtwork`, `ArchMark` (`Components/`).
- GNOME: `Artwork.swift`, `StationArt`, `Draw.mark` (`Drawings.swift`).

### Search
One field at the header's end on every page wide (⌘F, Ctrl+F); a click
shows the Search page. The iPhone: the tab bar's own Search tab.
- Apple: `SearchView` (`Search/SearchView.swift`), the toolbar's field.
- GNOME: `Nav.searchField`, `Pages.swift`.

### The welcome and sign-in pages
Centred, as a platform's welcome is: the mark, the name in the serif, one
line of what it is, the fields in one group, Sign In filled, the other ways
in (Sign In with Plex, Use Quick Connect) as words in the accent under it.
- Apple: `OnboardingView` (`Settings/OnboardingView.swift`).
- GNOME: `SignInPage.swift`.

## Where the HIGs differ

| Question | Jukebox decides | Why |
|---|---|---|
| Heading case | Sentence case for every heading and empty state, in the serif; Title Case for buttons and menu items | Headings are Jukebox's voice (tells 4); controls are the platform's |
| A song's queue word | "Play Last" on Apple, "Add to Queue" on GNOME; same place in the menu | Each platform's own music app's word |
| The heart's word | "Favorite" / "Undo Favorite" on Apple, "Add to" / "Remove from Favorites" on GNOME | The same |
| More | "…" on Apple, "⋮" on GNOME | Each platform's glyph |
| A row's actions | "…" on each row on the iPhone; secondary click and Shift+F10 wide | Touch has no secondary click |
| Alignment | Left, on the margin; centred only where the platform centres (the transport, the iPhone's page head, a welcome) | Editorial (tells 8) |
| Accent | Copper and Glow everywhere, never the system's blue or GNOME's | One app |
| Grounds | Jukebox's flat grounds, menus `lifted`; the system's where it draws a list (Settings, Preferences) | Flat grounds (tells 2) |
| Filled buttons | One a screen, plain, 6 corners; no GNOME pill, no Apple capsule | One radius (tells 6) |
| Destructive items | Last, alone in their section; Apple's red role | GNOME's order, Apple's colour |
| Wide window | Linux's layout on the iPad and the Mac; native only where the OS has a place (menu bar, toolbar search, traffic lights) | "ik wil dat de linux app en de apple app 1:1 op elkaar lijken" |

## Parity checklist

Walk it before any screen ships, on every client.

- Does it exist on every client, each in its own form?
- Are the colours tokens, with no hex outside `Tokens.swift` and art?
- Is there one filled button, and is its neighbour the quiet twin?
- Are the other actions words in the accent or plain symbols?
- Are headings sentence case in the serif, with one small label at most?
- Is everything on the margin, centred only where the platform centres?
- Do its menus follow the song's sections and order?
- Is the only light the station on air?
- Does the empty state say the same words on every client?
- Has it been seen: the Linux walk (`dev/linux-screens.sh`) and CI's
  screenshots, by day and by night?

## Audit, 20 November 2026

Walked: Linux at 1440×900 dark and light and 400×800
(`dev/linux-screens.sh`), and CI's screenshots of main 6b73549 (iPhone,
iPad, Mac snapshots), with the menus read in the code.

### Fixed

- Tokens: `Theme.swift`, `Style.swift`, `Drawings.swift`, `Downloads.swift`,
  `MainWindow.swift` and the widget held their own hex values; all read
  `Tokens.swift` now.
- Artist, playlist and mix "…" on Apple put Start Radio first; now in a
  song's order (`ArtistsView.swift`, `PlaylistsView.swift`,
  `MixDetailView.swift`).
- Linux's artist and mix ⋮ missed Play Next and Add to Queue
  (`Pages.swift`).
- Empty states in Title Case on Apple, and different words from Linux's;
  now sentence case, the same words ("Could not load your music", "No music
  yet") (`HomeParts.swift`, `LibraryParts.swift`, `FavoritesView.swift` and
  others).
- Linux's "No music yet" had no Check Again; the Mac's had (`Pages.swift`).
- Linux's Sign In with Plex and Use Quick Connect were grey flat buttons;
  now words in the accent, as the Mac's (`SignInPage.swift`).

### Open, with a proposal

- **Two filled buttons**: `.prominent` (40 wide, 44 on the iPhone, full
  width) and `.action` (36). Proposal: one, 36, and Sign In compact on
  every client.
- **The welcome's mark**: a sleeve with its record on Apple, the icon's
  tile on Linux (`OnboardingView.swift`, `SignInPage.swift`). Proposal: the
  sleeve on both, drawn with `Draw` on Linux.
- **The artist page**: Play alone wide, Play and Shuffle on the iPhone
  (`ArtistsView.swift`). Proposal: the pair everywhere.
- **Album menu on tiles**: Linux has Play and no heart, Apple the heart and
  no Play; Home's and Search's album menus on Apple are short
  (`HomeParts.swift` `HomeAlbumMenu`, `SearchView.swift`). Proposal: one
  `albumMenu` on Apple, Linux's items plus the heart.
- **Playlist rows**: Linux has Move Up and Move Down, Apple only Remove
  (`TrackRow.swift`). Proposal: add them to `TrackMenu`'s first section.
- **Picked songs**: Linux keeps the list's section, Apple drops it.
- **Mix and station tiles**: Apple has Shuffle, Play Next, Show Station;
  Linux only Play (`HomeParts.swift`, `Pages.swift`). Proposal: Linux's tiles
  take Apple's items.
- **Mix "…"**: Save as Playlist… on Apple only.
- **The bar's and Full Player's "…"**: Apple shows the whole `TrackMenu`;
  Linux's `songMenu` has the station's lessons and no Play Next or links
  (`PlayerBar.swift` on both). Proposal: `TrackMenu` with the station's
  section first, on both.
- **Primary menu**: Linux has Sign Out…, Mini Player, Keyboard Shortcuts,
  About; the iPad's has Settings… and Private Listening
  (`MainWindow.swift`, `WideShell.swift`).
- **Recent searches**: Remove on Apple only.
- **In-page empty states**: Apple centres a `ContentUnavailableView`
  (Favorites, Downloaded, a playlist), Linux writes one line at the margin.
  Proposal: Linux's line on Apple too.
- **Type sizes on Apple**: wide pages pass Linux's sizes as numbers to
  `desktopFont`. Proposal: read `Tokens.Size`.
