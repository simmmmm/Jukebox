# Releasing Jukebox on the App Store

The photographer, 9 November 2026: "Kun je die navidunges en subsonic
toevoegen dan Istie erna wel klaar voor release werkzaamheden denk, denk er
geen geld aan te kunnen verdienen verder of zo". So: free, no in-app
purchases, no ads, no account of ours. Everything App Store Connect asks for,
ready to paste; what is still open is marked **Open**.

## The listing

**Name** (30 characters at most, unique on the App Store) — **Open**: "Jukebox"
alone is very likely taken. Candidates that say what it is:

- Jukebox — for Jellyfin
- Jukebox Player
- Jukebox: Jellyfin & Navidrome (29)

**Subtitle** (30): Your music server, on the air

**Category**: Music. Secondary: none.

**Price**: Free. All countries.

**Promotional text** (170, can change without review):

> Play your own music from Jellyfin, Navidrome or any Subsonic server — with a
> radio that learns what you skip, mixes made from your listening, and your
> music offline.

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
> Home has playlists Jukebox makes for you from what you play: Daily Mixes,
> On Repeat, Rediscover, Deep Cuts, New Arrivals, Loved Tracks, and a mix
> for each genre and decade of your library.
>
> NOW PLAYING
> The album's sleeve with its record half out, on a page that is the record
> itself, its grooves moving gently while it plays. Its colour comes from the
> cover. Synced lyrics, from your server or from LRCLIB.
>
> OFFLINE
> Download an album, a playlist or a mix. Jukebox also keeps what you play
> most, up to a size you choose, so your favourite music plays without a
> network — the radio too.
>
> AND
> Favourites and playlists that stay in sync with your server. AirPlay,
> the lock screen and Control Center, Up Next. iPhone and iPad.
>
> Jukebox has no account, no ads and no tracking. Your music and your
> listening stay between the app and your own server.

**Keywords** (100, comma-separated, no spaces needed):
`jellyfin,navidrome,subsonic,music server,self-hosted,radio,flac,offline,library,player,nas,plex`

(Leave "plex" out if Review objects to naming a product the app does not
support.)

**Support URL** — **Open**: a page with a way to reach the photographer;
the repository's README works (`https://github.com/simmmmm/Jukebox`).

**Privacy Policy URL** — **Open**: where `docs/privacy.md` (below) is
published.

**Copyright**: 2026 Tijmen (or the name the photographer publishes under).

## Screenshots

Required: iPhone 6.9" (1320 × 2868) and iPad 13" (2064 × 2752). From the
screenshot walk (`ci/screenshots.sh`, made-up library and covers, ours to
use): Home, Now Playing (D2), a station's page, an album, Up Next with the
dial, Lyrics, Settings › Downloads. The walk runs on an iPhone 17 Pro
(1206 × 2622) today; for the store, one run on an iPhone 17 Pro Max and the
iPad 13". Text over the pictures: none (tells.md).

## App Privacy (the questionnaire)

- Do you or your third-party partners collect data from this app? **Yes.**
- Data type: **Usage Data → Product Interaction.** Only this.
  - Linked to the user's identity? **No.** (No account, no device id, no
    address kept: docs/STATS.md.)
  - Used for tracking? **No.**
  - Purposes: **Analytics.**
- Everything else: **not collected.** The music, the server's address, the
  user name and the password go only to the listener's own server and stay
  in the keychain; lyrics are looked up at LRCLIB with title, artist, album
  and length, which is not data about the person.

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

## Before submitting

1. The release build from main on TestFlight, played through on a phone:
   sign in to Jellyfin and to the Navidrome demo, a station, a download,
   airplane mode.
2. `MARKETING_VERSION` 1.0 (project.yml); the build number is CI's run
   number.
3. In App Store Connect: the listing above, the screenshots, App Privacy,
   age rating, the review notes; "Manually release this version" so the
   photographer chooses the day.
