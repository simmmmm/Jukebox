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

| # | Row | Mac | iPad | iPhone | Linux | Note |
|---|---|---|---|---|---|---|
| 1 | Each account kept, the one signed in checked; click to switch | ✓ (with 2 or more) | ✓ (2+) | ✓ (2+) | ✓ (always) | Sign out of another: its context menu or swipe (Apple), its Sign Out… (Linux) |
| 2 | Server: name, then kind and version ("Jellyfin 10.11.0") | ✓ | ✓ | ✓ | ✓ in the account's row | |
| 3 | User | ✓ | ✓ | ✓ | ✓ in the account's row | |
| 4 | Address | ✓ | ✓ | ✓ | ✓ | Linux's added 21 November |
| 5 | Add Account… | ✓ trailing | ✓ row | ✓ row | ✓ in the group's header | GNOME puts a group's action there |
| 6 | Sign Out… | ✓ trailing | ✓ row | ✓ row | ✓ on each account | Asks first: "Sign out of Betsy as tijmen?" |
| 7 | Your Year | ✓ own section, Show… | ✓ own section | ✓ own section | ✓ row, a subpage | Footer, from `ServerWords.playbackReportingNote`: "Playback Reporting is installed: Your Year counts every play, from every device." |

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
Account… and Sign Out…. The iPad's ≡ has the same. The Mac's menu bar has
the accounts and Add Account…, but Sign Out… stays in Settings, where it can
ask first (`Commands.swift`).

## Playback

| # | Row | Words under it | Mac | iPad | iPhone | Linux | Default |
|---|---|---|---|---|---|---|---|
| 1 | Streaming Quality | | "Streaming" | "Wi-Fi Streaming" | "Wi-Fi Streaming" | ✓ | Original |
| 2 | Streaming on a hotspot or cellular | | "Streaming on a Hotspot" | "Cellular Streaming" | "Cellular Streaming" | — Linux never sees a metered network (`Platform.swift`) | Normal |
| | *Footer of 1–2* | "Original plays your files as they are. The others have Jellyfin convert them to AAC at that rate, which uses less data." | ✓ | ✓ | ✓ | ✓ | |
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
| 2 | Enhance Radio with Last.fm: "Artists and songs are looked up on Last.fm to find what sounds alike. Nothing about you is sent, unless you add your Last.fm username." | ✓ in the row | ✓ in the row | ✓ footer | ✓ in the row | on |
| 3 | Last.fm: API Key "Jukebox's own" · Your Key (optional) · Save / Cancel · once kept, •••• with Change Key and Remove Key | ✓ | ✓ | ✓ | ✓ | Jukebox's key |
| 4 | Username (optional), once a key is in use | ✓ | ✓ | ✓ | ✓ | empty |
| 5 | Get a Free API Key | ✓ | ✓ | ✓ | ✓ (added) | |
| | *Footer*: "The radio asks Last.fm which artists and songs sound alike… Only artist names, song titles and your username are sent; nothing is written to Last.fm." | ✓ | ✓ | ✓ | ✓ (now the same words) | |

Rows 3 to 5 show only while row 2 is on.

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

## Not in Settings anywhere

- **Play On** (AirPlay, Cast, UPnP): the bar's and Now Playing's picker on
  every client. There is nothing to set.

## Mismatches found on 21 November 2026, all fixed

- **Mac**: buttons were each on a row of their own, in the window's tinted
  quiet style. They are now the system's push buttons, trailing, at the end
  of their section.
- **Mac, iPad, iPhone**: Your Year was a button between Server and Address.
  It now has its own section, with the Playback Reporting note as its
  footer.
- **Mac, iPad, iPhone**: the quality footers sat under the whole section.
  Playback and Downloads now have two sections each, so each footer is under
  the rows it explains.
- **Linux** was missing:
  - Address;
  - the Adventurousness dial in Preferences;
  - Get a Free API Key;
  - Library's counts and Refresh Library;
  - History (Plays Remembered, Clear Listening History);
  - the streaming footer;
  - Normalize Volume when the server gives no loudness. It is now shown off
    and dimmed, with the reason, as on Apple.
- **Words** that differed, now one:
  - Autoplay (Apple said "keep playing similar music");
  - Normalize Volume and Find Lyrics Online (Linux's were shorter);
  - Last.fm's row names ("Last.fm API Key", "Change", "Remove" on Linux);
  - the Last.fm footer;
  - Share Anonymous Usage's note;
  - Add Account… and Sign Out…, now with "…" on Apple too;
  - the sign-out dialog's title and text;
  - About's line.
  The explanations under rows now all end with a full stop.
