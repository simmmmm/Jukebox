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
A colour, a size or a duration changes there and nowhere else; both
clients read every group (the welcome's build-up keeps its own timing, as
art). The asset catalog's `AccentColor` is a copy Xcode reads before any
code runs: `dev/accent-check.sh` holds it equal to `Tokens.accent`, and
`ci/app.sh` runs it.

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
| facts | the system's secondary | the text at 60 % | Facts: Apple's `.secondary`, Linux's `.fact` |

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
- **Rows** (`Tokens.Row`): a song's row on the iPhone 52 for one line (44
  for the finger, a little air) and 60 for two; wide, for the pointer, 48
  numbered, 64 with a cover, 72 with the radio's reason.
- **Radius**: 6 for artwork, and for the filled button and its twin on
  Apple (GNOME's own button corners on Linux, which are 6 too). What holds
  them is concentric: a tile's hover 14 (6 + 8), Home's cards 18 (6 + 12).
  The system's own controls keep the system's shapes.
- **Motion**: 0.15 s for what appears under the pointer, 0.2 s for fades
  and hovers, 0.25 s for a part of the window moving, 0.3 s for lyrics'
  lines, up to 0.5 s for a cover's colours taking the room (`Tokens.Motion`).
- **Drawn art**: the record, the sleeve and the room's own colours
  (`Tokens.Art`), never for chrome.

## Components

Each with its rule, its Apple form and its GNOME form.

### The filled button and its quiet twin
One filled button a screen: Play, Sign In, Try Again, one size everywhere,
compact. Beside it in a page's row, its twin: same size, on the accent at
12 %, `quietInk` (Shuffle, New Picks, Stop, Continue). 36 tall, 96 wide at
the least, 15 bold, 6 corners. Play and its twin always as a pair, Play
first, on every page that plays (an album's, an artist's, a playlist's, a
mix's).
- Apple: `.buttonStyle(.action)` / `.quietAction`, `PagePlayButtons`
  (`Components/Theme.swift`); `.prominent` is the same filled button.
- GNOME: `playButton` / `quietButton` (`Linux/App/Parts.swift`), CSS
  `button.page-button`, `button.quiet` (`Style.swift`); Sign In and Try
  Again `suggested-action page-button`.

### Text buttons and plain symbols
Every other action is a word in the accent or a plain symbol. Never an
icon-and-label pill.
- Apple: `.buttonStyle(.secondary)`; SF Symbols, `.plain`.
- GNOME: `wordButton` (`flat accent word`), `iconButton` with `flat`;
  Adwaita's symbolic icons and `Glyphs` (`Style.swift`).

### Rows and lists
Content on the ground, parted by hairlines. A song's row is as tall as
`Tokens.Row` says and no taller: on the iPhone 52, 60 with a second line
(the list's own insets none: they stood rows of 75 round the "…", "Ook
heb ik t idee dat nummers nu wel erg veel padding boven en onder
krijgen", 21 November 2026); wide 48, 64 with a cover. The song playing
in the accent. Songs are picked with Ctrl and Shift wide.

An album's songs are numbered by their place on their disc, 1, 2, 3…, in
the album's order (disc, the file's track number, the name); the file's
number only orders them, as tags read 2, 3, 4 or 6, 7, 7, 8 ("Ik kan geen
touw vastknopen waarom de nummers allemaal verschillend zijn", 21 November
2026; `LibraryIndex.placeOnDisc`). Up Next numbers by place in the queue.
- Apple: `TrackRow` (`Components/TrackRow.swift`), `Hairline`; the iPhone
  adds a "…" on each row, as touch has no secondary click, and its lists
  put `.trackListRow()` on each song's row.
- GNOME: `TrackRow`, `trackList` (`Parts.swift`), `listview.rows`.

### The version filter
On an album's or a playlist's page, between the hairline and the songs,
when they hold two or more versions: All, then Original (if any), then the
others by name ("All · Remastered · Unplugged"). The version is read from
the title's end (`TrackVersion`, JukeboxKit): "(Unplugged)", "[Live]",
"(Remastered 2014)", " - Live at Wembley"; "(feat. X)" and "(Part 2)" are
none. The rows, the head's count and length, Play and Shuffle take the
chosen version's songs, in the page's order; the "…", the download, Add
Songs and Start Radio the whole. The rows leave out the marker every one
would say. The page's own choice, not kept; All when opened. A playlist
is not reordered under a version; Remove still works. "ik wil bijv alle
unplugged nummers er uit kunnen filteren of alle remastered als ze er zijn
zeg maar?" (21 November 2026).
- Apple: `LibraryVersionPicker` (`Library/LibraryParts.swift`), a
  segmented `Picker` for up to three kinds, a menu past that;
  `\.hidesVersion` for the rows (`TrackRow`).
- GNOME: `versionChoices` (`Parts.swift`), linked toggle buttons;
  `trackList`'s `name` and `canMove`.

### Cards and the raised ground
Your Station before it plays (Home, and Radio on the iPhone), the music to go
on with and the offline notice stand on a card: `raised`, flat, 18 corners
at 12 in. No cards in cards.
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
what applies (Play first on a tile, as it has no button; Play and Shuffle
on a mix's). A page's "…" leaves out what has a button beside it (the
heart wide). A station's tile: Play Station (Show Full Player on the air) ·
Go to Station. The song playing (the bar, Full Player): a song's menu with
the station's lessons as its list's section. A toggle in a menu (Don't
Count Plays) is a check on Apple and on GNOME plain words that say what
it does (Count Plays Again while marked); GNOME's checks and radio items
live only on a submenu's page (Rating). The primary menu: Private
Listening, Settings or Preferences, the accounts, Add Account…, Sign Out…
(the Mac's in Settings), and where the platform has them Mini Player,
Keyboard Shortcuts, About. Linux's menus sit on `lifted`; Apple's are the
system's own.
- Apple: `TrackMenu` (`Components/TrackRow.swift`), `Section`s; `.contextMenu`
  on the iPhone, a secondary click wide; `MoreMenu` (`WidePage.swift`).
- GNOME: `trackMenu`, `albumMenu`, `menuSections`, `popoverMenu`,
  `moreButton` (`Parts.swift`): GMenu sections.

### Sheets, drawers and popovers
- Apple: `.sheet` for a task (Add to Playlist, Settings), a `Menu` or
  `.popover` for a choice.
- GNOME: `AdwDialog` for a task (`Choosers.swift`), `GtkPopoverMenu` for a
  choice, the panel as a drawer under 1280 (`Panel.swift`). Toasts for a
  moment's news (`MainWindow.toast`).

### Notices and empty states
A whole window's state (loading, couldn't load, no music): the platform's
status page, centred, sentence-case title, one action. A page with nothing
in it: one plain line at the margin, where its content would start, in the
same words on every client.
- Apple: `ContentUnavailableView` (`Home/HomeParts.swift`,
  `Library/LibraryParts.swift`); `EmptyLine` (`Theme.swift`).
- GNOME: `emptyPage` (status page) and `emptyLine` (`Parts.swift`).

### Lyrics
The Lyrics button (Now Playing's on the iPhone, the bar's wide) and the
panel's Lyrics tab are there where lyrics can be had at all, and off,
dimmed, for a song known to have none or to be instrumental: "Kan je t
knoppie gewoon disablen toch?" (21 November 2026). On while it is still
asked. Open on a song without, they give way to the sleeve or Up Next; no
"No lyrics" line.
- Apple: `NowPlayingView`'s bottom row, `PlayerBar`, `PanelView`;
  `LyricsFinder.hasNone`.
- GNOME: `PlayerBar.swift`, `Panel.swift` (`songHasNoLyrics`).

### The player bar and the mini player
Wide: the bar, 88 across the window's foot, three zones from
`DesktopMeasures`; Play 40, the rest 32. The Mini Player window on the
Mac and Linux.

The iPhone: Spotify's structure, Jukebox's soul (21 November 2026). A
block 58 tall, 8 in from the screen's edges, 8 pt corners, in the cover's
colour darkened until Glow on it is 4.5:1 (dark glass tinted with it on
iOS 26). On the left a 44 pt record, the cover as its label, turning while
it plays (still when paused and under Reduce Motion). The title in the
serif, white; under it the artist at 70%, or the arch and the station's
name in Glow. On the right the heart (filled in Glow), next and play or
pause, 44 each; next gives way first when the title would keep less than
120, and past Large type. A 2 pt Glow line on a faint track along the
block's foot. Swipe left for next, right for previous. No AirPlay: Now
Playing has it. Under it Jukebox's own tabs on a fade and a blur from the
screen's foot; no system tab bar, so one glass, not two.
- Apple: `PlayerBar` (`NowPlaying/PlayerBar.swift`), `MiniPlayer`
  (`NowPlaying/MiniPlayer.swift`), `MacMiniPlayer.swift`.
- GNOME: `PlayerBar.swift`, `.player-bar`; the Mini Player in `Extras.swift`.

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
Centred, as a platform's welcome is: the mark on its sleeve with the record
half out, the name in the serif, one line of what it is, the fields in one
group, Sign In filled and compact, the other ways in (Sign In with Plex, Use
Quick Connect) as words in the accent under it.
- Apple: `OnboardingView` (`Settings/OnboardingView.swift`), `WelcomeSleeve`
  (`ShellAppMark.swift`), built up as a jukebox switched on.
- GNOME: `SignInPage.swift`, `Draw.welcomeSleeve` (`Drawings.swift`), at
  rest.

## Where the HIGs differ

| Question | Jukebox decides | Why |
|---|---|---|
| Heading case | Sentence case for every heading and empty state; Title Case for buttons, tabs and menu items | Headings are Jukebox's voice (tells 4); controls are the platform's |
| A song's queue word | "Play Last" on Apple, "Add to Queue" on GNOME; same place in the menu | Each platform's own music app's word |
| The heart's word | "Favorite" / "Undo Favorite" on Apple, "Add to" / "Remove from Favorites" on GNOME | The same |
| More | "…" on Apple, "⋮" on GNOME | Each platform's glyph |
| A row's actions | "…" on each row on the iPhone; secondary click and Shift+F10 wide | Touch has no secondary click |
| Alignment | Left, on the margin; centred only where the platform centres (the transport, the iPhone's page head, a welcome) | Editorial (tells 8) |
| Accent | Copper and Glow everywhere, never the system's blue or GNOME's | One app |
| Grounds | Jukebox's flat grounds, menus `lifted`; the system's where it draws a list (Settings, Preferences) | Flat grounds (tells 2) |
| Filled buttons | One a screen, plain; 6 corners on Apple, GNOME's own on Linux; never a pill or capsule | One radius (tells 6) |
| Menus' ground | Linux's on `lifted`; Apple's the system's | GNOME's grey popovers read as another app's; Apple's menus are glass, drawn by the system |
| Menu icons | SF Symbols in Apple's menus; none in GNOME's | Each platform's menus as its own apps draw them |
| Menu checks | A check on Apple; on GNOME only in a submenu (Rating), a toggle in the menu itself as words (Don't Count Plays, Count Plays Again) | GTK keeps a check's room before every item of a menu page that has one, which stood the whole menu in from GNOME's edge ("het lijkt wel of je rekening hebt gehouden met meer iconen qua padding", 21 November 2026) |
| Destructive items | Remove from a list first, in its list's section; what cannot be undone (Delete) last and alone; Apple's red role on both | GNOME's order, Apple's colour |
| A choice among a few (the version filter) | Apple's segmented control, a menu past three kinds; GNOME's linked toggle buttons (libadwaita 1.5 has no toggle group) | Each platform's own control for one of a few |
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

Walked: Linux at 1440×900 dark and light and 400×800 light
(`dev/linux-screens.sh`) beside CI's screenshots of main 6b73549: the iPad's
walk against Linux's twins, the Mac's light snapshots against Linux light,
the iPhone against 400×800. The menus read in the code on both.

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
- Linux's panel tab said "Now playing", the Mac's "Now Playing"; a control,
  so header capitals (`Panel.swift`).

### Fixed in the second round ("Los ze op", 20 November 2026)

- **One filled button**: `.prominent` is `.action`'s filled button, 36 and
  compact (`Theme.swift`); Linux's Sign In and Try Again are `page-button`
  (`SignInPage.swift`, `Pages.swift`).
- **One welcome**: Linux draws the sleeve with its record
  (`Draw.welcomeSleeve`, `SignInPage.swift`).
- **The artist page**: Play and Shuffle everywhere (`ArtistsView.swift`,
  `Pages.swift`).
- **Album menus**: one on every tile and row, Linux's items plus the heart,
  Play first (`LibraryAlbumMenu` for Home and Search too, `albumMenu`); the
  album page's "…" without Play, and without the heart where it stands
  beside it (`AlbumsView.swift`, `Pages.swift`).
- **Artist tiles and rows**: Start Radio · Share in two sections; Search's
  with Share (`ArtistsView.swift`, `SearchView.swift`).
- **Genre tiles**: Start Radio on Linux's too (`Pages.swift`).
- **Playlist rows**: Move Up and Move Down on Apple (`TrackRow.swift`,
  `PlaylistsView.swift`). Picked songs: no "N Songs" heading on Apple.
- **Mix and station tiles**: the same items on both (`HomeParts.swift`,
  `Pages.swift`, `Parts.swift` `stationMenu`); "Go to Station" on both.
- **Mix "…"**: Save as Playlist… on Linux too.
- **The bar's and Full Player's "…"**: a song's menu with the station's
  lessons first, on both (`TrackMenu`, Linux's `songMenu`).
- **Primary menu**: Sign Out… in the iPad's ≡ (`AccountMenu.swift`,
  `WideShell.swift`); Linux has Private Listening already.
- **Recent searches**: Remove on Linux too (`Pages.swift`).
- **In-page empty states**: one line at the margin on Apple too, Linux's
  words (`EmptyLine`; Favorites, Downloaded, Playlists, a playlist, Genres,
  Songs, Your Year, Lyrics).
- **The iPhone's album page**: the artist plain. **Played lately**: "Artist
  · Today" on every client (`AlbumsView.swift`, `HomeView.swift`).
- **Tokens**: Apple's wide type sizes and durations, the drawn art's
  colours on both, the welcome's field ground (`Tokens.Size`,
  `Tokens.Motion`, `Tokens.Art`, `Tokens.field`).
- **AccentColor**: checked against `Tokens.accent` (`dev/accent-check.sh`).
- **The iPhone's sign-in**: the compact Sign In stood at the left under a
  centred welcome (walk of 3d172e5); its buttons and words are centred
  under the fields now, as the iPad's and Linux's (`OnboardingView.swift`).

### Still open

- **Sign Out… on the Mac**: in Settings, not the Account menu
  (`Commands.swift` has nowhere to ask first).
- **Search's genres**: Apple's Search shows genres, Linux's has no genre
  section.
- **Several picked songs**: neither client offers Remove or Move for all of
  them (`removal` is per song on both).
- **The iPhone's mini player**: its song menu has no station section yet
  (`MiniPlayer.swift`).
- **A station's lesson word**: "Dislike" on Apple, "Not This" on Linux.
- **The welcome's build-up**: Apple's arches come on one by one; Linux's
  picture stands still.
- **Copy in empty states**: Apple's say "your music" where they said "Your
  Library", as Linux's; the photographer's to override.
