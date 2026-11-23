# Settings on every client

Settings on the Mac, the iPad and the iPhone; Preferences on Linux. They
have the same pages in the same order, the same rows in the same order and
the same words. Each client draws them in its own form. The photographer,
21 November 2026: "op mac zijn de settings een beetje een tyfusbende
geworden", then "check het echt goed met de rest ook".

The forms:
- **Mac**: a window with a toolbar of tabs. Each pane is a grouped
  `Form`, with facts as `LabeledContent`. A section's actions sit together
  in one row at its end, trailing, as the system's own push buttons
  (`SettingsActions`, `systemButtons()`).
- **iPad, iPhone**: a sheet with a list of pages, each page a `Form`. The
  iPad's rows are Linux's (15 pt, the explanation under each row). On the
  iPhone a few explanations are footers.
- **Linux**: `AdwPreferencesDialog`, one page each. A group's note is its
  description. Buttons sit under the rows (libadwaita 1.5 has no button
  row).

Code: `Jukebox/Settings/SettingsView.swift`, `Linux/App/Preferences.swift`.
Defaults: `AppSettings` (shared), so they are the same everywhere.

Key: ✓ there · — not there, with the reason.

## Accounts

Each account kept is a card, and the cards are a radio group: one is
always the one signed in. The photographer, 21 November 2026: "kun je op
alle versies een toegevoegde server als een soort card tonen die werken
als een soort radiobutton (er moet altijd 1 server actief zijn)". A card
holds, in this order:
- the radio;
- the kind's letter ("J", "E", "N", "P"), a round label in one ink, the
  accent on the one signed in;
- the server's name, in the serif;
- the kind and version, then the user ("Jellyfin 10.11.0 · test");
- the address.

Choosing another card switches to it (`AppModel.switchAccount`). If its
server does not answer, the radio stays where it was and the words say
why: under that card on Apple, a toast on Linux. There is no choosing
none.

| # | Row | Mac | iPad | iPhone | Linux | Note |
|---|---|---|---|---|---|---|
| 1 | A card for each account, even one | ✓ a section each, the system's radio | ✓ a section each, ◉ in the accent | ✓ the same | ✓ boxed list, a check button in radio mode before each row | GNOME's Settings chooses a power mode the same way |
| | *Footer of the card signed in*, from `ServerWords.playbackReportingNote` (Jellyfin and Emby only): "Playback Reporting is installed: Your Year counts every play, from every device." | ✓ | ✓ | ✓ | ✓ the group's note | About the server, so it stays here |
| 2 | Add Account… | ✓ trailing | ✓ row | ✓ row | ✓ the list's last row | |
| 3 | Sign Out…, of the one signed in | ✓ trailing | ✓ row | ✓ row | ✓ under the list | Asks first: "Sign out of Betsy as tijmen?" With others kept, the next is signed in to; with none, the welcome |

Sign out of another account from its card's context menu: a secondary
click or long press on Apple (or a swipe), a secondary click on Linux. So
an account whose server no longer answers can still go.

Code: `Jukebox/Settings/AccountCard.swift`, `Preferences.accountRow` on
Linux. The radio is the card's one swappable part. If several servers
ever play side by side, it becomes a toggle that keeps one on, and the
card stays as it is.

The sign-out dialog has the same words everywhere. Only the device's name
changes: "Mac", "iPhone", "iPad", "computer".
- Signing out of the account in use, with no other kept: "Playback stops and Jukebox forgets the
  library, your recent stations and the downloaded songs on this Mac. Your
  music, playlists and favorites stay on the server."
- The account in use, with another kept: the same, ending in "then goes on
  with Betsy".
- Another account: "Jukebox forgets its library, recent stations and
  downloaded songs on this Mac. The music plays on."

The account menu: Linux's primary menu lists the accounts, then Add
Account… and Sign Out…. The iPad's ≡ and the Mac's Account menu have the
same; the Mac asks over the main window (`Commands.swift`, RootView).

## Playback

| # | Row | Words under it | Mac | iPad | iPhone | Linux | Default |
|---|---|---|---|---|---|---|---|
| 1 | Streaming Quality | | "Streaming" | "Wi-Fi Streaming" | "Wi-Fi Streaming" | ✓ | Original |
| 2 | Streaming on a hotspot or cellular | | "Streaming on a Hotspot" | "Cellular Streaming" | "Cellular Streaming" | — Linux never sees a metered network (`Platform.swift`) | Normal |
| | *Footer of 1–2* | "Original plays your files as they are. The others have Jellyfin convert them to AAC at that rate, which uses less data." Where the server makes Opus (docs/SERVERS.md, "Opus"), the pickers have "Efficient (Opus, 128 kbit/s)" between Normal and Low and the footer adds "Efficient makes Opus instead, at half of Normal's data." | ✓ | ✓ | ✓ | ✓ | |
| 2a | Adjust to the Connection | "When a song has to wait for the network, the next ones stream lower until it holds again." Under the pickers, in their section (Linux: their group) | ✓ | ✓ | ✓ | ✓ | on |
| 3 | Autoplay | "When an album or a playlist ends, play on with a station from its last song." | ✓ | ✓ | ✓ | ✓ | on |
| 4 | Crossfade | "A song fades out and the next fades in. Songs that follow each other on an album never fade." | ✓ | ✓ | ✓ | ✓ | Off |
| 5 | Continue Where You Left Off | "When Jukebox opens, the song you last played, here or on another device, is ready to play." | ✓ | ✓ | ✓ | ✓ | on |
| 6 | Normalize Volume | Jellyfin: "…the loudness Jellyfin measured, so loud and quiet records sit side by side." Subsonic: "…its ReplayGain tags give…". Without loudness: off, dimmed, "Navidrome doesn't give songs a loudness, so each plays as it is." | ✓ | ✓ | ✓ (first, after the qualities) | ✓ | on |
| 7 | Find Lyrics Online | "When your server has no lyrics for a song, ask LRCLIB (lrclib.net), with its title, artist, album and length." | ✓ | ✓ | ✓ own section "Lyrics", footer | ✓ | on |
| 8 | Spin the Record | "Now Playing's record turns…" | ✓ | ✓ | ✓ | — Linux's record does not turn | on |

## Radio

| # | Row | Mac | iPad | iPhone | Linux | Default |
|---|---|---|---|---|---|---|
| 1 | Adventurousness, from Familiar to Adventurous | ✓ | ✓ | ✓ | ✓ (added 21 November; the panel's dial too) | 0.35 |
| | *Footer*: "Familiar stays close to where a station started and to songs you know. Adventurous goes further out and plays more that is new to you." | ✓ | ✓ | ✓ | ✓ | |
| 2 | Enhance Radio: "To find music that sounds alike, Jukebox sends the artist, song and album names in your library to Last.fm and ListenBrainz, and asks AcousticBrainz how each song sounds. Your Last.fm username goes too, if you add one. Nothing about your music server, your sign-in or this device is sent." Last.fm and AcousticBrainz together (24 November 2026) | ✓ in the row | ✓ in the row | ✓ footer | ✓ in the row | on, unless an old switch was turned off |
| 3 | Last.fm Username (optional) | ✓ | ✓ | ✓ | ✓ | empty |
| | *Footer*: "With your Last.fm username, the radio learns when you play what from your scrobbles. Nothing is written to Last.fm." | ✓ | ✓ | ✓ | — the row's title says it | |

Row 3 shows only while row 2 is on. A build without Jukebox's key (GitHub's
runners) shows neither. The key is Jukebox's own alone: the field for one's
own, Get a Free API Key, Change Key and Remove Key are gone ("Kan die api
ding … ook uit de app dan?", the photographer, 24 November 2026), and a key
kept from before is removed at launch.

Better Radio asks row 2 once, right after the first sign-in (SYSTEM.md, The
welcome and sign-in pages).

## Library

| # | Row | Mac | iPad | iPhone | Linux |
|---|---|---|---|---|---|
| 1 | Songs, Albums, Artists, Last Loaded | ✓ | ✓ | ✓ | ✓ (added) |
| 2 | Refresh Library, with its progress | ✓ trailing | ✓ row | ✓ row | ✓ (added) |
| | *Footer*: "Jukebox keeps a copy of the list of your music, so it opens at once. It reads the server again each time it starts." | ✓ | ✓ | ✓ | ✓ |
| 3 | Pages: Radio, Albums, Artists, Songs, Playlists, Favorites, Genres, Recently Added, Downloaded, Playlists in the Sidebar | ✓ | ✓ | ✓ without the sidebar's row (no sidebar) | ✓ |
| | *Footer*: "Home is always there. Pages that are off stay reachable from Home and Search." | ✓ | ✓ | ✓ | ✓ |

Every page is shown by default.

## Downloads

| # | Row | Mac | iPad | iPhone | Linux | Default |
|---|---|---|---|---|---|---|
| | "Betsy doesn't allow downloads for this account." (only when so) | row | row | row | in the note | |
| 1 | Keep Songs I Play: "Songs you play often or lately stay on this Mac, to play without a connection." | ✓ | ✓ | ✓ | ✓ | on |
| 2 | Up To (while 1 is on) | ✓ | ✓ | ✓ | ✓ | 5 GB |
| 3 | Download Quality | ✓ | ✓ | ✓ | ✓ | High |
| 4 | Download on a Hotspot / over Cellular | ✓ | ✓ | ✓ | — no metered network on Linux | off |
| | *Footer of 1–4*: what each quality means on this server, and when songs wait | ✓ | ✓ | ✓ | ✓ | |
| 5 | Downloaded, Kept, and what the queue is doing | ✓ | ✓ | ✓ | ✓ | |
| 6 | Remove All Downloads, asked first | ✓ trailing | ✓ row | ✓ row | ✓ | |

Rows 5 and 6 are in their own section on every client, so the footer sits
under the choices it explains.

## Privacy

| # | Row | Mac | iPad | iPhone | Linux | Default |
|---|---|---|---|---|---|---|
| 1 | Not Counted: Private Listening (Off, On, Until Jukebox Restarts), then each marked song, album or playlist with Count Again | ✓ | ✓ | ✓ | ✓ | Off |
| 2 | History: Plays Remembered, Clear Listening History (asked first) | ✓ | ✓ | ✓ | ✓ (added) | |
| | *Footer*: "What you play, skip and give a thumbs up or down to is how the radio and your mixes learn your taste. It stays on this Mac." | ✓ | ✓ | ✓ | ✓ | |
| 3 | Share Anonymous Usage | ✓ | ✓ | ✓ | ✓ | on |
| | *Footer*: "Jukebox counts which screens and features are used, never titles, artists, searches, server addresses or names, on the developer's own server, without cookies or a device id. It helps decide what to improve." | ✓ | ✓ | ✓ | ✓ (now the same words) | |

## About

The iPad and the iPhone have an About page in Settings: the mark, the
name, "Music from your Jellyfin, Emby, Plex, Navidrome or other Subsonic
server, with a radio that plays on from anything.", and the version "1.3
(build)". The Mac has About Jukebox in its app menu, and Linux has About
Jukebox in the main menu, with the same line and version
(`Linux/App/Version.swift` is held to `project.yml`).

Help & Feedback (23 November 2026, `docs/SUPPORT.md`), from
`Support.swift`:

| # | Row | Mac | iPad | iPhone | Linux |
|---|---|---|---|---|---|
| 1 | Jukebox Help, the site's help page | ✓ Help menu | ✓ About | ✓ About | ✓ Help (F1) in the primary menu; "Support Questions" in About |
| 2 | Report a Problem, GitHub's issues | ✓ Help menu | ✓ | ✓ | ✓ "Report an Issue" in About, libadwaita's words |
| 3 | Contact Support, once `Support.contact` is filled | ✓ | ✓ | ✓ | ✓ a link in About |
| 4 | Copy Diagnostic Info | ✓ Help menu | ✓ | ✓ | ✓ About › Troubleshooting › Debugging Information |

The sign-in page has "Trouble signing in?" and Copy Diagnostic Info under
its buttons on every client, in grey.

## Not in Settings anywhere

- **Play On** (AirPlay, Cast, UPnP): the bar's and Now Playing's picker on
  every client. There is nothing to set.
- **Your Year**: content, not a setting, so it left Settings on 21
  November 2026. Where it is now:
  - the iPhone: a row in Library, last;
  - the iPad and the Mac: a place in the sidebar, last, and Your Year in
    the ≡ menu and in the Mac's Account menu;
  - Linux: a place in the sidebar, last, and Your Year in the primary
    menu.
  It has no switch in Pages. Its note on Playback Reporting stays in
  Accounts, under the server's card.

## Mismatches found on 21 November 2026, all fixed

- **Mac**: buttons were each on a row of their own, in the window's tinted
  quiet style. They are now the system's push buttons, trailing, at the end
  of their section.
- **Mac, iPad, iPhone**: Your Year was a button between Server and Address.
  It had its own section for a while; now it is out of Settings (above).
- **Mac, iPad, iPhone**: the quality footers sat under the whole section.
  Playback and Downloads now have two sections each, so each footer is under
  the rows it explains.
- **Linux** was missing:
  - Address;
  - the Adventurousness dial in Preferences;
  - Get a Free API Key (since gone on every client with the key of one's
    own, 24 November 2026);
  - Library's counts and Refresh Library;
  - History (Plays Remembered, Clear Listening History);
  - the streaming footer;
  - Normalize Volume when the server gives no loudness. It is now shown off
    and dimmed, with the reason, as on Apple.
- **Words** that differed, now one:
  - Autoplay (Apple said "keep playing similar music");
  - Normalize Volume and Find Lyrics Online (Linux's were shorter);
  - the Last.fm footer;
  - Share Anonymous Usage's note;
  - Add Account… and Sign Out…, now with "…" on Apple too;
  - the sign-out dialog's title and text;
  - About's line.
  The explanations under rows now all end with a full stop.
