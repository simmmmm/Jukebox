# Privacy

Jukebox - Music player plays the music on your own server. It has no account
of ours, no ads and no tracking. This page says what leaves your device, and
where it goes. 21 November 2026.

## Your music stays with your server

Your library, what you play, your favourites and playlists, the server's
address and your user name go only to the server you signed in to (Jellyfin,
Navidrome or another Subsonic server). Your password is kept in the device's
keychain. None of it reaches the developer.

## Anonymous usage counts

Jukebox counts which screens and features are used, so the developer can see
what is worth working on. It is on by default. **To turn it off: Settings ›
Privacy › Share Anonymous Usage.** Off, nothing is sent.

- **Where:** the developer's own server (`stats.numa.photo`), running
  OpenPanel, which is open source. No other company receives it.
- **What a count holds:** the name of an event from a fixed list ("a
  station was started"), a coarse property from a fixed list (the kind of
  screen, a size in buckets), the app's version, the system and its
  version, the language, the device model and the time.
- **What it never holds:** a title, an artist, an album, a playlist's name,
  what you searched for, your server's address or name, your user name, or
  an id of you or your device.
- **No cookie, and nothing stored on your device** for the counts.
- **Your IP address** reaches the server with each count, as it does with
  any request. The server reads a rough place from it (country, city) and
  ties the counts of one visit together with a salted hash of the address
  and the system's name. The salt changes, so the hash does not follow you
  over time.

The counts are not linked to you, so the developer cannot look up or delete
one person's counts: there is no way to tell whose they are.

## Lyrics

When your server has no lyrics for a song, Jukebox asks LRCLIB
(`lrclib.net`), a free lyrics database, with the song's title, artist, album
and length. To turn it off: Settings › Find Lyrics Online.

## Enhance Radio: Last.fm, MusicBrainz and AcousticBrainz

To find music that sounds alike, the radio asks Last.fm
(`ws.audioscrobbler.com`) which artists and songs are alike, with artist
names and song titles, using Jukebox's own key. It looks up how each song
sounds (acoustic or electronic, calm or driving) in MetaBrainz's open data:
ListenBrainz (`labs.api.listenbrainz.org`) finds the song in MusicBrainz by
its artist, title and album, and AcousticBrainz (`acousticbrainz.org`) gives
its sound, each song once, on the iPhone and the iPad over Wi-Fi or Ethernet
only. Nothing else about you is sent with them, apart from your IP address,
as with any request. With your Last.fm username in Settings, it also reads
your scrobbles. Nothing is written to Last.fm.

You choose right after signing in (Better Radio): Turn On or Not Now. **To
change it: Settings › Radio › Enhance Radio** (Preferences › Radio on
Linux). Off, Jukebox makes no request to Last.fm, ListenBrainz or
AcousticBrainz, and the radio chooses from your library and from what they
answered before, which stays on your device.

## Questions

Jukebox is made by Tijmen, in the Netherlands. Its source is public:
<https://github.com/simmmmm/Jukebox>. Questions about this page or your
data: open an issue there.
