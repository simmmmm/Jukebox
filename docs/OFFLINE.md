## In the app

The photographer, 8 November 2026, asked whether there was "cache in
offline/downloads"; to the three parts proposed — download an album, a
playlist or a mix; keep what is played often or lately, up to a size they
choose; offline, play only what is on the phone, the radio too — "Alle
drie". `Jukebox/Offline/` is the app's half of all three; the manifest, the
keep's choosing and the download URL are the kit's (above).

### Where the songs are

One folder per account, `Application Support/Offline/<server id>-<user id>/`,
excluded from backup (the music is on the server; a backup of gigabytes of
it would only take the listener's iCloud space): `manifest.json` (the kit's
`OfflineManifest`), `collections.json` (the albums, playlists and mixes
chosen, with their songs in order — the manifest knows which songs a reason
holds, not their order, and offline a playlist's page cannot ask the
server), `queue.json` (songs still to fetch, those the server would not
give, and its last answer on downloading), `reports.json` (plays heard
offline) and `files/`, each song named by the kit's
`OfflineFile.fileName(trackID:contentType:)` from the Content-Type the
server sent — AVFoundation reads a local file's kind from its extension
(`OfflineDisk.swift`). A song saved again is the newest save, with the
reasons of both (the kit's `add`); the older file is deleted when its name
differs.

At sign-in the folder is checked against the manifest: a file that is gone
is forgotten (`forget`); a file the manifest does not know — a download
whose news was lost as the app was ended — joins it with the reasons it was
wanted for, or is removed when nothing wanted it.

**Signing out removes the account's folder**, downloads in flight included,
and a folder of any account other than the one signing in is removed as a
leftover. Decided so, rather than kept and hidden: sign-out already forgets
the library and the recent stations ("Jukebox forgets the library, your
recent stations and the downloaded songs on this iPhone", the dialog says
now), and songs kept for an account nobody is signed in to would be
gigabytes no Settings shows. The next account, perhaps on another server,
never plays the last one's songs: the folders are per account, and every
download carries its account in its tag, so one that finishes after the
sign-out is thrown away.

### Fetching

One background `URLSession` (`OfflineDownloader.swift`,
`com.tijmen.Jukebox.downloads`): downloads go on while the app is in the
background, suspended or ended, and the system wakes it with the news
(`JukeboxAppDelegate`, `application(_:handleEventsForBackgroundURLSession:)`;
the system is told once the news is saved). No capability or background
mode is needed for that, so `project.yml` is unchanged. Each task's
description is its tag — account, song, quality — so the news makes sense
after a relaunch, and news that comes before the account is read waits for
it.

- **24 songs at a time** in the session, in the queue's order: what the
  listener chose first, then the keep's, best first. An album or a mix goes
  in one go, so it finishes in the background; the keep's thousand go a
  couple of dozen at a time, refilled as each finishes.
- **Mobile data** only with Settings › Downloads › Download over Cellular
  (off by default): a request that may not use it waits for Wi-Fi by itself.
  Turning it on or off cancels every download, which starts again asking
  anew. Low Data Mode holds back the keep, not what was chosen.
- **A song the server will not give** (400, 404, 410, 415) is not asked for
  again until it is chosen again; its album or playlist is done without it
  ("11 of 12 songs" in Downloaded). One that failed on the way is tried
  again after 1, 2, 4, 8 and 16 minutes, then given up; while the server is
  away a failure does not count, and everything waiting is tried at once
  when it answers again.
- **Progress** per song from the bytes written; a song Jellyfin converts
  comes without a length, and its estimate (`KeepPolicy.estimatedBytes`,
  the rate asked for and a little over) stands in, held under 99%. Published
  twice a second; an album's, a playlist's or a mix's is its songs on the
  phone plus the parts of those coming, over its songs.
- **The server's admin** can turn "Allow media downloading" off for a
  user (`JellyfinClient.downloadsAllowed`, asked at sign-in and whenever
  the server answers again, kept in `queue.json` for a launch without the
  server). Off: nothing is fetched, downloads under way are cancelled and
  wait, the keep waits, the pages show no Download (only the control of
  one chosen before, to remove it), and Settings › Downloads says,
  in one line, that the server does not allow downloads for this account.
  What is on the phone stays and plays. The server does not refuse the
  download URL itself (the kit measured it), so the app keeps to it.

### Downloads you choose

The bar of an album's, a playlist's and a mix's page: `arrow.down.circle`,
then a ring in the accent around a stop square while it comes, then
`checkmark.circle`; the ring and the checkmark are menus with Remove
Download, asked first ("It still plays from your server. Songs another
download holds stay."). Its songs that nothing else holds go to the keep
while it can run, and its plan, a moment later, lets go of those it does
not want, rather than delete songs it would fetch again (the kit's advice
above); else they are deleted at once. A downloaded playlist follows the server each time
its page reads it: songs added there are fetched, songs taken out lose it
as a reason. A mix is kept as it was the day it was downloaded (MixStore
makes new mixes, with new ids, every day).

Library › Downloaded lists what is on the phone: albums, playlists and
mixes, newest first, each with one fact (how far, what it waits for, or its
songs and size), then "Songs you play", the keep's; Shuffle All plays all of
it. Songs on the phone have Music's small `arrow.down.circle.fill` after
their title in every list (`TrackRow`).

### The keep

Settings › Downloads › Keep Songs I Play, on at 5 GB (1, 2, 5, 10 or 20),
in Download Quality (High by default; the rates in its words are the kit's
`aacBitrate`; Original is each file as it is, or AAC at 256 when the phone
cannot play it). `KeepPolicy.plan` runs a minute after
the last play (each play moves it on), 10 s after sign-in, 15 s after the
library has loaded, 5 s after Wi-Fi, the server or full power comes back,
and when its settings change. It fetches its `download` list in its order
and deletes its `remove` list, removing first. It does not run while its
songs cannot come — offline, on mobile data without leave, in Low Power
Mode, or not allowed by the server — as it could let
songs go to make room for ones it cannot fetch, and offline those it let go
of are the only ones that play. Low Power Mode also cancels the keep's
downloads in flight; what was chosen goes on. Turned off, what the keep
alone held is deleted. Remove All Downloads turns it off too, or it would
fetch its songs again at once.

### Offline

Offline is no network (`NWPathMonitor`) or a server that does not answer
its public info (`/System/Info/Public`): asked at sign-in, when the network
changes (back after none, it counts as offline until the server has
answered — a server at home is not there from the mobile network), when a
library load or a song fails on the network, when the app comes to the
front, from Home's Try Again, and every 30 s while it does not answer.

- **The player** plays a song on the phone from its file always, online
  too: no data, and it starts at once. Offline: a list starts at its first
  song on the phone and holds only those; songs not on the phone are passed
  over in the queue; a song that streamed is left three seconds after it
  stops for want of the network; Play Next and Play Last take only songs on
  the phone. A tap on a song that is not on the phone says why on the mini
  player's line for five seconds — "You’re offline. “…” isn’t on this
  iPhone." — and nothing changes; lists dim such songs (secondary).
- **The radio** chooses from a snapshot of the library's songs on the phone
  (`LibrarySnapshot(tracks:)`, made again when the songs on the phone or the
  library change); a station on the air when the network goes is chosen
  again from it at once, and from the whole library when it comes back.
  Instant Mix and Last.fm are not asked while offline. A song's station of a
  song not on the phone becomes the kit's personal station among them.
- **Plays heard offline are queued, not dropped**: their start and stop
  reports wait in `reports.json` and go to the server in order once it
  answers, so Jellyfin counts them and its Last.fm plugin scrobbles them —
  at the time they arrive, not when they were heard (the reports carry no
  time). Progress reports made offline are dropped. At sign-out what is
  waiting is sent if the server answers, else it goes with the account.
- **Home's notice** says why first — "You’re offline." or "Can’t reach …" —
  then "The songs on this iPhone still play." when there are some, else
  "Showing your library from last time."; back online the library is read
  again and the notice goes by itself.

### Counted

`download_chosen` (`kind`: album, playlist, mix), `offline_play_started`
(`from`, as `play_started`) and `setting_changed` `keep_songs` (docs/STATS.md).
Not the quality, the size, Download over Cellular or how much is on the phone.

### Not done

- Downloads are not shown in an album's or a playlist's tile, nor on
  Home's shelves; only in their pages, their songs' rows and Downloaded.
- The keep's progress is not shown song by song; Settings says how many
  songs are still to come, and what they wait for.
- A download stopped by Low Power Mode, by Download over Cellular
  changing, or by the server's admin, starts again from its beginning: no
  resume data is kept (a plain file could resume; a converted one cannot).
