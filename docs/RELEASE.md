# Releasing Jukebox on the App Store

The photographer, 9 November 2026: "Kun je die navidunges en subsonic
toevoegen dan Istie erna wel klaar voor release werkzaamheden denk, denk er
geen geld aan te kunnen verdienen verder of zo". So: free, no in-app
purchases, no ads, no account of ours. Everything App Store Connect asks for,
ready to paste; what is still open is marked **Open**.

## The listing

**Name** (30 characters at most, unique on the App Store): Jukebox - Music
player (22). The photographer, 15 November 2026: "Jukebox - Music player heet
de app nu".

**Subtitle** (30): Your music server, on the air

No em dashes in the store's texts: "ik wil geen em dashes in text" (the
photographer, 16 November 2026).

**Category**: Music. Secondary: none.

**Price**: Free. All countries.

**Promotional text** (170, can change without review):

> Play your own music from Jellyfin, Navidrome or any Subsonic server - with
> a radio that learns what you skip, mixes made from your listening, and
> your music offline.

**Description** (4000):

> Jukebox plays the music on your own server: Jellyfin, Navidrome, or any
> server that speaks the Subsonic API. Type its address once; Jukebox finds
> out which server it is.
>
> THE RADIO
> Start a station from any song, album, artist or genre, or let Your Station
> play from everything you love. It chooses from your own library, listens
> to what you skip and what you play to the end, and a dial goes from
> Familiar to Adventurous. Thumbs down, and you hear less like it.
>
> MIXES
> Home has playlists Jukebox makes for you from what you play: moods named
> after their songs ("Rock & Shoegaze", "1990s Jazz"), On Repeat,
> Rediscover, Deep Cuts, New Arrivals, Loved Tracks, and a mix for each
> genre and decade of your library.
>
> NOW PLAYING
> The album's sleeve with its record half out, on a page that is the record
> itself, its grooves moving gently while it plays. Its colour comes from the
> cover. Synced lyrics, from your server or from LRCLIB.
>
> OFFLINE
> Download an album, a playlist or a mix. Jukebox also keeps what you play
> most, up to a size you choose, so your favourite music plays without a
> network, the radio too.
>
> AND
> Favourites and playlists that stay in sync with your server. AirPlay,
> the lock screen and Control Center, Up Next. iPhone and iPad.

(**Open**: "iPhone, iPad and Mac" once the Mac ships, below.)
>
> Jukebox has no account and no ads. What you play is never sent to us:
> Jukebox counts, anonymously, which features are used and on what kind of
> device, and the server that receives the counts reads a rough location
> (country and city) from the connection. Share Anonymous Usage in Settings
> turns that off. Lyrics your server does not have are looked up at LRCLIB
> by the song's title, artist, album and length; Find Lyrics Online in
> Settings turns that off too. Last.fm is asked only with your own key, by
> artist names and song titles.

**Keywords** (100, comma-separated, no spaces needed):
`jellyfin,navidrome,subsonic,music server,self-hosted,radio,flac,offline,library,player,nas,plex`

(Leave "plex" out if Review objects to naming a product the app does not
support.)

**Support URL**: `https://github.com/simmmmm/Jukebox`.

**Privacy Policy URL**:
`https://github.com/simmmmm/Jukebox/blob/main/docs/PRIVACY.md`
([PRIVACY.md](PRIVACY.md); it answers once that file is on main).

**Copyright**: 2026 Tijmen Steenvoorden.

**The Mac's description** differs in two paragraphs: Now Playing is "The
album's sleeve with its record half out, and Up Next or the lyrics beside
it. Synced lyrics, from your server or from LRCLIB.", and the last line of
AND is "AirPlay, Up Next. iPhone, iPad and Mac."

## In App Store Connect (16 November 2026)

Filled in and saved for the iPhone's and the Mac's version 1.0: the texts
above, the screenshots, the review notes, "Manually release this version",
subtitle and category, the age rating (4+), App Privacy's answers, the
price (free) and all 175 countries.

Also set, as the photographer chose (16 November 2026): Content Rights
"No, it does not contain, show, or access third-party content"; the
Digital Services Act "not a trader"; App Privacy published.

Version 1.0, build 163, was submitted for review on 16 November 2026, the
iPhone's and then the Mac's ("goed genoeg om iig het er uit te krijgen",
the photographer). Release is manual: approved, each waits for him. The
Mac's build was not played on a Mac before it went.

## Screenshots

- **Sizes**: iPhone 1206 × 2622 (the 17 Pro, the set App Store Connect
  requires; the Pro Max's 1320 × 2868 is an optional second set), iPad 13"
  2752 × 2064, Mac 1440 × 900. PNG without alpha, ten at most each.
- **The round**: a push of the branch `store-walk` (`ci/app.sh`) walks the
  Mac's own window (`MacScreenshotTests.swift`), an iPhone 17 Pro and the
  13-inch iPad, against the made-up library, covers ours to use.
- **The set**: `dev/store-shots.sh` picks it from that round into
  `build/appstore/{iphone,ipad,mac}/`, in the listing's order, and checks
  each size. Home with a station on the air first, then Now Playing, a
  station, an album, Up Next with the dial, Radio, the albums; the iPad
  and the Mac have Lyrics too.
- **Open**: the iPhone's Lyrics (the walk's song has none) and Settings ›
  Downloads are not in the set.
- **Text over the pictures**: none (tells.md).

## App Privacy (the questionnaire)

Published 16 November 2026.

- Do you or your third-party partners collect data from this app? **Yes.**
- Data types: **Usage Data → Product Interaction** and **Location → Coarse
  Location** (the server reads a country and a city from the address of
  each count). For both:
  - Linked to the user's identity? **No.** (No account, no device id, no
    address kept: docs/STATS.md.)
  - Used for tracking? **No.**
  - Purposes: **Analytics.**
- Everything else: **not collected.** The music, the server's address, the
  user name and the password go only to the listener's own server and stay
  in the keychain; lyrics are looked up at LRCLIB with title, artist, album
  and length, and with the listener's own Last.fm key the radio asks Last.fm
  by artist names and song titles: neither is data about the person.

This matches `Jukebox/Resources/PrivacyInfo.xcprivacy`.

## Age rating

Every question **None / No**, except: **Unrestricted Web Access: No**;
**User-Generated Content: No**. The music is the listener's own, from their
own server; Jukebox shows no content of its own. Result: 4+.

## Export compliance

`ITSAppUsesNonExemptEncryption` is false in project.yml: only the system's
HTTPS. No questions at upload.

## App Review

**Sign-in required**: yes. Review cannot use the photographer's own server,
so the notes point at Navidrome's public demo:

> Jukebox is a player for the user's own music server (Jellyfin, Navidrome
> or another Subsonic server). To review it, please sign in to Navidrome's
> public demo server:
>
> Server: demo.navidrome.org
> User name: demo
> Password: demo
>
> Then: Home shows mixes made from the library; Radio starts a station; any
> album, the record in Now Playing, Lyrics, Up Next with the station's
> dial. Downloads (an album's ↓ button) work against the demo server too.
>
> NSAllowsArbitraryLoads: many people run their music server at home over
> plain http on their own network (for example 192.168.1.10:8096); Jukebox
> asks for the local network for the same reason. Passwords are never sent
> over plain http to the internet: the app refuses that (docs/SERVERS.md).

Check before submitting that demo.navidrome.org is up and the demo user can
play and download.

## The Mac

The Mac's Jukebox is the same app: a native macOS destination of the same
target (project.yml), with the same bundle ID. So it ships through the same
App Store Connect record, one purchase for the iPhone, the iPad and the Mac
(universal purchase).

- The platform is there (Apps › Jukebox › macOS App, 16 November 2026), and
  `mac_upload=true` in `ci/app.sh`: a [testflight] run uploads the Mac's
  build after the iPhone's.
- The Mac's version page needs its own screenshots: the store's round
  (Screenshots, above).

## Builds

- **A push** builds the iPhone's app and the Mac's, unsigned. A red Mac
  build makes the run red (`mac_gates=true`).
- **On main** the screenshot walk runs after the
  builds. An upload, when asked (README, TestFlight), archives and uploads
  in their place.
- **On a work branch** only the two builds run: no screenshots unless the
  branch's name ends in "walk", and never an upload, whatever the commit
  says.
- **A fast loop**: the photographer's Mac, a MacBook, builds over SSH. The
  build is signed with that Mac's Apple Development certificate from a
  Terminal session on the Mac itself, because an SSH session cannot reach
  the keychain. Such a debug build has no provisioning profile, so it keeps
  the sign-in in the file-based keychain and stays signed in from one build
  to the next (`Jukebox/App/Keychain.swift`).

## Before submitting

1. The release build from main on TestFlight, played through on a phone:
   sign in to Jellyfin and to the Navidrome demo, a station, a download,
   airplane mode. Once the Mac uploads, the same on the Mac.
2. `MARKETING_VERSION` 1.0 (project.yml); the build number is CI's run
   number.
3. In App Store Connect: the listing above, the screenshots, App Privacy,
   age rating, the review notes; "Manually release this version" so the
   photographer chooses the day.

## Linux

`dev/linux-flatpak.sh release` builds the Flatpak (`docs/LINUX.md`) from a
pushed commit and attaches it to GitHub's release `v<MARKETING_VERSION>`. A
new release starts as a draft: the photographer publishes it, and chooses
the day. A version is released once; the next file needs the next number.
