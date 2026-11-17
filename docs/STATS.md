# Usage counts (Stats)

Anonymous counts of which screens and features of Jukebox are used, sent to
the photographer's own OpenPanel server (`https://stats.numa.photo`, open
source, self-hosted).

- `Jukebox/App/Stats.swift` is all of it. Every event is one line where it
  happens.
- An event is one POST to `/api/track`, made in `Stats.swift`; no package.
- The client id and secret (`Stats.clientID`, `Stats.clientSecret`) come from
  the OpenPanel project. They are not secrets: they ship in the app. While the
  id is empty nothing is sent.
- Numa-mac's counts (`app/Numa/Stats.swift`, `docs/STATS_PLAN.md`) are the
  pattern, with one difference (rule 1).

The photographer, 8 November 2026: "Kun je ook aptabase toevoegen van mijn
account en alles tracken wat je mag zonder cookie melding."

OpenPanel replaced Aptabase on 13 November 2026. The photographer wants to see
the order of what someone does in one visit and where a visit ends ("user
flows heb ik oneindig veel meer aan dan aantal bezoekers"); Aptabase only
counts.

## Rules

1. **On by default, without asking**, as the photographer asked: "alles
   tracken wat je mag zonder cookie melding".
   - Jukebox sets no cookie, stores nothing on the device for the counts, and
     sends no id.
   - The server ties one visit's events together itself: a salted hash of the
     request's address and user agent (OpenPanel's `device-id.ts`). The salt
     changes, so the hash does not follow someone over time.
   - The server also reads a rough place (country, city) from the address.
   - Numa asks first and is off by default, because Numa had said "no
     analytics" until then. Jukebox never did.
   - Not yet checked on the running server: how often the salt changes, and
     that the address itself is not kept with an event.
2. **The switch**: Settings › Privacy › Share Anonymous Usage
   (`AppSettings.shareUsage`, UserDefaults `shareUsage`).
   - Off: `Stats.track` returns before anything. No request is made.
   - Turning it off sends one last event, `setting_changed` `share_usage`
     `off`, while it is still on. Then nothing.
   - Turning it on is not counted.
   - The launch argument `-shareUsage NO` turns it off too (for a walk in the
     simulator).
3. **A closed list.** The events are `Stats.Name`. A new one goes there and in
   the table below, in the same change.
4. **Coarse properties from fixed lists only**: a kind of screen, a kind of
   seed, a bucket, on or off. Never a title, an artist, an album, a
   playlist's or a mix's name, a search, a server's address or name, a user
   name, an id of anything, an error's message. Counts and durations are in
   buckets (below), so no number tells one library from another.
5. **Every event also carries** the app's version and build, the system
   (iOS, iPadOS, macOS) and its version (in the user agent), the language, the device
   model, the time, and `debug` for a debug build (CI's simulator runs and
   Xcode builds, kept apart on the server).
   **The Mac** sends the same events from the same `Stats.swift`: its user
   agent says "Macintosh; Intel Mac OS X" with the system's version, and the
   model is the Mac's own (`hw.model`, "Mac15,6"). Its switch is in the
   Settings window, Privacy.
   **Linux** sends the same events from the same `Stats.swift`, for the
   screens it has, as system `Linux`: the model is the word "Linux" and the
   user agent says "X11; Linux x86_64". Never the distribution, the desktop
   or the machine's name. Its switch is Preferences › Privacy › Share
   Anonymous Usage.
6. **Unsent events** wait in memory for the next one, 200 at most, and are
   gone when the app quits.
7. **Main actor.** `Stats.track` runs on the main actor, as everything in the
   app does by default. Code running elsewhere hops there first.

Buckets:

| What | Buckets |
|---|---|
| A library's songs | `<100`, `100-999`, `1k-9k`, `10k+` |
| Seconds | `<1`, `1-5`, `5-30`, `30+` |
| Search results | `0`, `1-9`, `10+` |
| Accounts kept | `1`, `2`, `3+` |
| The radio's dial | `0-0.2`, `0.2-0.4`, `0.4-0.6`, `0.6-0.8`, `0.8-1` |

## Events

| Event | Properties | The question it answers | Where |
|---|---|---|---|
| `app_open` | `server` (`jellyfin`, `navidrome`, `subsonic`, `none`) | How many starts, on which system, version, language and device; which kinds of server are used | `AppModel.restore`, once a launch, when the keychain has said |
| `signed_in` | `server` (`jellyfin`, `navidrome`, `subsonic`), `method` (`password`, `quick_connect`, `api_key`) | How people sign in, and to what; is Quick Connect worth it | OnboardingView |
| `sign_in_failed` | `reason` (`unreachable`, `not_a_server`, `wrong_password`, `needs_api_key`, `needs_https`, `other`) | Where people stop before the music | OnboardingView |
| `signed_out` | none | Do people leave, or move servers | `AppModel.signOut`, of any saved account |
| `account_added` | `server` (`jellyfin`, `navidrome`, `subsonic`), `count` (the accounts kept now: `1`, `2`, `3+`) | Do people keep more than one account, and of which kinds | `AppModel.signIn`, when the account is new on the device (the first included; not a sign-in again, not the migration) |
| `account_switched` | none | Is the switch between accounts used | `AppModel.switchAccount`, once the server answered (or offline, with songs on the device) |
| `library_loaded` | `tracks` (bucket), `from` (`cache`, `server`), `seconds` (bucket) | How large libraries are; how long a launch and a load take | LibraryStore |
| `screen` | `name`: a tab (`home`, `radio`, `library`, `search`), a place in the wide window (`home`, `radio`, `search`, `playlist`, or a library kind: `albums`, `artists`, `songs`, `playlists`, `favorites`, `genres`, `recently_added`, `downloaded`), a pushed page's kind (`album`, `artist`, `playlist`, `genre`, `mix`, `station`, `artists`, `albums`, `songs`, `playlists`, `genres`, `favorites`, `recently_added`, `downloaded`), or `now_playing`, `lyrics`, `queue`, `settings`; `carplay` once each time the car connects. The wide window never sends `library`: its kinds are places there | Which screens are used, which never; is CarPlay used | MainTabView (tabs), CarPlaySceneDelegate (`carplay`), WideShell (the wide window's places, and Search from its field), `routeDestinations()` (pushes), the cover, panels and sheet |
| `play_started` | `from` (`album`, `playlist`, `mix`, `songs`, `favorites`, `search`, `artist`, `genre`, `station`, `other`, `siri`), `shuffled` (bool) | Where music is started from; is Shuffle used; is Siri | `AudioPlayer.play`, `playRadio`; `siri` for what Siri or Shortcuts played (`Stats.nextFrom`); a station they start counts `station` here and `siri` in `station_started` |
| `station_started` | `seed` (`track`, `artist`, `album`, `genre`, `decade`, `collection`, `personal`, `discovery`, `favorites`), `from` (`page`, `tile_menu`, `hero`, `menu`, `autoplay`, `search`, `carplay`, `siri`; `picker` is reserved) | Which stations people play, and from where | each Start Radio, Play Station, Your Station's Play, a station's page, Autoplay |
| `station_page` | `action` (`opened`, `new_picks`, `row`, `play`) | Is the page looked at before playing; is New Picks used | StationDetailView |
| `radio_feedback` | `kind` (`skip`, `like`, `dislike`, `undo`) | Does the radio get told what is liked | RadioController |
| `dial_changed` | `value` (bucket) | Where people set the dial | the three dials, when let go |
| `track_ended` | `outcome` (`completed`, `partial`, `skipped`), `station` (bool) | How much is heard to the end, on the radio and off it | `AudioPlayer.deliver` |
| `lyrics_shown` | `source` (`server`, `lrclib`, `none`, `failed`), `synced` (bool) | How often lyrics are there, and from where | LyricsView |
| `mix_opened` | `kind` (the MixKind: `daily` (the moods; the word is kept so the counts go on), `newArrivals`, `rediscover`, `deepCuts`, `favorites`, `onRepeat`, `decade`, `genre`) | Which of Home's mixes are opened | MixDetailView |
| `mix_played` | `kind` (as above) | Which mixes are played | `AudioPlayer.playMix` |
| `playlist_created` | `from` (`library`, `mix`, `station`, `queue`, `add_to_playlist`) | Where playlists are made; is Save as Playlist used | PlaylistsView, MixDetailView, StationDetailView, QueueView, AddToPlaylistSheet |
| `playlist_songs_added` | `from` (`add_songs`, `add_to_playlist`) | How playlists are filled | AddSongsSheet, AddToPlaylistSheet |
| `favorite_set` | `item` (`track`, `album`, `artist`), `on` (bool) | Are favourites used, and for what | `LibraryStore.setFavorite`, once the server took it |
| `rating_set` | `item` (`track`, `album`), `stars` (`0` to `5`; `0` is None) | Are ratings used, on the servers that keep them, and how | `LibraryStore.setRating`, once the server took it |
| `search_used` | `results` (bucket) | Is search used; how often it finds nothing | SearchView, once a search, when the typing first rests (1.5 s) |
| `setting_changed` | `name` (`wifi_quality`, `cellular_quality`, `normalize`, `autoplay`, `find_lyrics_online`, `spin_record`, `resume_on_launch`, `share_usage`, `keep_songs`; `page_` and a page's name for Settings › Pages: `page_radio`, `page_albums`, `page_artists`, `page_songs`, `page_playlists`, `page_favorites`, `page_genres`, `page_recently_added`, `page_downloaded`, `page_sidebar_playlists`), `value` (`original`, `high`, `normal`, `low`; `on`, `off`; `share_usage` only `off`) | Which settings are changed, to what; is Keep Songs I Play turned off; which pages are switched off | AppSettings, whoever changes it (Settings, the queue's Autoplay, Remove All Downloads for `keep_songs`) |
| `lastfm_key` | `state` (`added`, `removed`) | Do people add a Last.fm key | Settings (Preferences on Linux), once Last.fm accepted it, or Remove |
| `playback_error` | `reason` (`network`, `server`, `unsupported`, `other`) | How often a song does not play, and why | `AudioPlayer.itemFailed` |
| `download_chosen` | `kind` (`album`, `playlist`, `mix`) | Are downloads used, and for what | `OfflineStore.download`, each Download on a page |
| `offline_play_started` | `from` (as `play_started`'s) | Is music played offline, and from what | `AudioPlayer.play`, `playRadio`, while offline (with `play_started`) |
| `sleep_timer_set` | `value` (`15`, `30`, `45`, `60`, `end_of_song`, `end_of_queue`, `off`) | Is the sleep timer used, and for how long | `PlayQueue.setSleepTimer`, each choice in a sleep timer's menu; not when it ends by itself |

### `server`

The kind of server, coarsely (`Stats.server`):

- `jellyfin`
- `navidrome`
- `subsonic` for every other Subsonic server: Gonic, Airsonic, Ampache, LMS,
  the original, and one that names itself in its own word (that word is never
  sent)
- `none` when signed out

Never which server, its name, address or version. Asked for with Navidrome
and the other Subsonic servers (9 November 2026). Before that, `app_open` had
no properties and was counted in `JukeboxApp.init`, `signed_in`'s `server` was
always `jellyfin`, and `not_a_server` was `not_jellyfin`.

### `station_started`'s `from`

| Value | Where the station was started |
|---|---|
| `page` | A station's page: its Play, or a song on it |
| `tile_menu` | A station's long press, Play Station |
| `hero` | Your Station's Play, on Home's card or Radio's |
| `menu` | Any Start Radio of a song, album, artist, playlist, genre or mix (in a menu or under a page's Play) |
| `autoplay` | Autoplay after an album or playlist ended |
| `search` | A Start Radio or a song in Search |
| `carplay` | A station on CarPlay's Home or Radio |
| `siri` | Siri or Shortcuts: Your Station, Start a Station, a genre, "Play … radio" |
| `picker` | Reserved. Start a Station (the picker) opens the station's page since 8 November 2026, so what it starts counts as `page`; `picker` stays for a picker that would play at once. |

### Downloads

Counted: that a download was chosen, of what kind, and that music started
while offline. Not counted: the download quality, the keep's size, Download
over Cellular, how much is on the phone, or what was removed.

## Never in an event

- What is played, by whom or from where
- Titles, artists, albums, genres, playlists' and mixes' names
- What was searched for
- Server addresses and names, user names
- The Last.fm key
- Lyrics
- Error messages

No crash or error reports.

## The App Store

App Store Connect › App Privacy: **Usage Data › Product Interaction** and
**Location › Coarse Location** (the place the server reads from the
address), both not linked to the user, not used for tracking, purpose
**Analytics**. Nothing else is collected. Published 16 November 2026.

`Jukebox/Resources/PrivacyInfo.xcprivacy` declares the same, with
UserDefaults' reason CA92.1 (the app's own settings). XcodeGen puts the
manifest in the app's resources: `project.yml` takes everything under
`Jukebox/`, and XcodeGen (2.40.1 and later) gives a file of a type it has no
rule for, `.xcprivacy` among them, the Copy Bundle Resources phase.

A privacy policy for the App Store's listing should say the same in words:
anonymous counts of features used, on the developer's own server, no cookies,
no id kept on the device, a rough place read from the address, off in
Settings › Privacy.
