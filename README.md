# Jukebox

Your Jellyfin music on the iPhone and the iPad: artists, albums, songs and
playlists; playlists Jukebox makes up for you on Home; and a radio that plays
on from any song, artist, album, genre or decade and learns from what you skip.

## TestFlight

Built and uploaded by GitHub's macOS runners, so no Mac is needed.

1. App Store Connect › Apps › `+` › New App: iOS, name *Jukebox*, bundle ID
   `com.tijmen.Jukebox` (register it under Certificates, Identifiers & Profiles ›
   Identifiers if it is not offered), SKU `jukebox`.
2. This repository's secrets (Settings › Secrets and variables › Actions):
   `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` — the same as
   Numa-mac's, an App Store Connect API key with the Admin role.
3. Actions › CI › Run workflow, with "Upload to TestFlight" ticked — or a commit
   whose message has `[testflight]`.

## Last.fm (optional)

The radio works from your library alone. With a free Last.fm API key
(last.fm/api/account/create) in Settings, it also knows which artists and songs
sound alike, and the stations get much better. Only artist names and song
titles are sent to Last.fm.

## Development

See `docs/ARCHITECTURE.md`. `dev/jellyfin-test-server.sh` and `dev/kit-test.sh`
test JukeboxKit on Linux against a real Jellyfin in Docker.
