# Mobile data

"streaming data kosten optimaliseren" (the photographer, 24 November 2026).

A network that costs data: the mobile network, a phone's hotspot or Low Data
Mode on Apple's systems (`NetworkCost`), a metered connection on Linux
(GLib's `network-metered`, `Linux/App/Platform.swift`). The rules are
JukeboxKit's `DataCost`, tested in `DataCostTests`.

## An hour on the mobile network

Fifteen songs of four minutes, five skipped after half a minute, four returns
to the app, a library of 20 000 songs. Measured on the test Jellyfin 12.4
where it says so; audio is the bitrate times the hour.

| What | Before | After | How known |
|---|---|---|---|
| Audio, iPhone (Cellular Streaming, Normal 256 kbit/s) | 115 MB | 115 MB | computed |
| Audio, Linux on a metered connection | Original: about 400 MB for FLAC, 144 MB for a 320 kbit/s MP3 | Normal: 115 MB | computed |
| Skipped songs and the next song held for the gapless move | up to 34 MB: AVPlayer fetches the rest of the file | up to 10 MB: a minute ahead (`preferredForwardBufferDuration`) | estimated from the code |
| Library read again on a return to the app (each after 5 min) | up to 40 MB: about 10 MB a read (0.45 KB a song as Jellyfin answers URLSession) | 0: only at a launch and a pull to refresh | measured per song |
| Handoff (a read every 15 s, a save every 30 s) | 0.8 MB (1.9 KB a read, 2.6 KB a save) | same | measured |
| Playback reports (every 10 s) | 0.2 MB | same | measured |
| Remote control's socket (a ping every 30 s) | under 0.1 MB | same | code |
| Covers | asked at the size shown (120 to 1600 px, Linux 128, 440, 880), kept on disk with the server's tag | same | code |
| Lyrics, a station's songs (Instant Mix, Last.fm) | a few KB, asked when shown or when the station starts, kept | same | code |
| AcousticBrainz's sound lookups | the iPhone waited for Wi-Fi; the Mac and Linux did not | every client waits | code |
| **The hour, iPhone** | **about 190 MB** | **about 130 MB** | |
| **The hour, Linux on a metered connection** | **about 440 MB (FLAC)** | **about 120 MB** | |

## What changed

- Linux streams at Streaming on a Metered Connection's quality there, as
  the iPhone at Cellular Streaming's; Download on a Metered Connection, off,
  as the Mac's Download on a Hotspot.
- A return to the window never reads the library again on a network that
  costs (`DataCost.libraryRefreshIsDue`).
- On the mobile network AVPlayer holds a minute ahead of the playhead.
  Linux's GStreamer already streams as it plays, and asks for the next
  song only a moment before the end.

## What did not

- **The quality itself.** Normal (256 kbit/s) is the biggest number left.
  Low (128 kbit/s) would make the hour about 70 MB. His choice.
- **A cache of songs just played.** AVPlayer and GStreamer fetch the stream
  themselves; keeping it means fetching it twice, or a stream of our own.
  Keep Songs I Play already keeps the songs played often, and they play
  from the device online too.
- **gzip in place of Brotli.** Jellyfin 12.4 answers URLSession's
  "gzip, deflate, br" with Brotli, 35% bigger than its gzip (a page of 358
  songs 161 KB against 104 KB; the albums 22.7 against 16.6 KB). Asking for
  gzip alone is one header, left until it is seen to work on an iPhone.
