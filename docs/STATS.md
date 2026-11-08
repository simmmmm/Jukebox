# Usage counts (Stats)

Anonymous counts of which screens and features of Jukebox are used, on the
photographer's own Aptabase server (`https://stats.numa.photo`, open source,
self-hosted), App Key `A-SH-1430104593` — not a secret: it ships in the app.
`Jukebox/App/Stats.swift` is all of it; every event is one line where it
happens. Numa-mac's counts (`app/Numa/Stats.swift`, `docs/STATS_PLAN.md`) are
the pattern, with one difference, below.

The photographer, 8 November 2026: "Kun je ook aptabase toevoegen van mijn
account en alles tracken wat je mag zonder cookie melding."

## Rules

1. **On by default, without asking.** Aptabase sets no cookie, keeps no
   device id and no IP address, and Jukebox stores nothing on the device for
   it; its sessions are a number in memory that changes after an hour. So
   there is nothing to consent to, as the photographer asked: "alles tracken
   wat je mag zonder cookie melding". Numa asks first and is off by default,
   because Numa had said "no analytics" until then; Jukebox never did.
2. **The switch.** Settings › Privacy › Share Anonymous Usage
   (`AppSettings.shareUsage`, UserDefaults `shareUsage`). Off, `Stats.track`
   returns before anything: Aptabase is not even set up while it is off (it
   is set up lazily, on the first event while on). Turning it off is the
   last event, `setting_changed` `share_usage` `off`, sent while it is still
   on; then nothing. Turning it on is not counted. A launch argument
   `-shareUsage NO` turns it off too (for a walk in the simulator).
3. **A closed list.** The events are `Stats.Name`. A new one goes there and
   in the table below, in the same change.
4. **Coarse properties from fixed lists only**: a kind of screen, a kind of
   seed, a bucket, on or off. Never a title, an artist, an album, a
   playlist's or a mix's name, a search, a server's address or name, a user
   name, an id of anything, an error's message. Counts and durations are in
   buckets (below), so no number tells one library from another.
5. **What Aptabase adds** to every event: the app's version and build, the
   system (iOS, iPadOS) and its version, the language, the device model, and
   whether it is a debug build (CI's simulator runs and Xcode builds are
   "debug" and kept apart on the server). Nothing else.
6. **Main actor.** `Stats.track` runs on the main actor, as everything in the
   app does by default; something running elsewhere hops there first.

Buckets:

| What | Buckets |
|---|---|
| A library's songs | `<100`, `100-999`, `1k-9k`, `10k+` |
| Seconds | `<1`, `1-5`, `5-30`, `30+` |
| Search results | `0`, `1-9`, `10+` |
| The radio's dial | `0-0.2`, `0.2-0.4`, `0.4-0.6`, `0.6-0.8`, `0.8-1` |

## Events

| Event | Properties | The question it answers | Where |
|---|---|---|---|
| `app_open` | none | How many starts, on which system, version, language and device | `JukeboxApp.init` |
| `signed_in` | `server` (`jellyfin`), `method` (`password`, `quick_connect`) | How people sign in; is Quick Connect worth it | OnboardingView |
| `sign_in_failed` | `reason` (`unreachable`, `not_jellyfin`, `wrong_password`, `other`) | Where people stop before the music | OnboardingView |
| `signed_out` | none | Do people leave, or move servers | `AppModel.signOut` |
| `library_loaded` | `tracks` (bucket), `from` (`cache`, `server`), `seconds` (bucket) | How large libraries are; how long a launch and a load take | LibraryStore |
| `screen` | `name`: a tab (`home`, `radio`, `library`, `search`), a pushed page's kind (`album`, `artist`, `playlist`, `genre`, `mix`, `station`, `artists`, `albums`, `songs`, `playlists`, `genres`, `favorites`, `recently_added`, `downloaded`), or `now_playing`, `lyrics`, `queue`, `settings` | Which screens are used, which never | MainTabView (tabs), `routeDestinations()` (pushes), the cover, panels and sheet |
| `play_started` | `from` (`album`, `playlist`, `mix`, `songs`, `favorites`, `search`, `artist`, `genre`, `station`, `other`), `shuffled` (bool) | Where music is started from; is Shuffle used | `AudioPlayer.play`, `playRadio` |
| `station_started` | `seed` (`track`, `artist`, `album`, `genre`, `decade`, `collection`, `personal`, `discovery`, `favorites`), `from` (`page`, `tile_menu`, `hero`, `menu`, `autoplay`, `search`; `picker` is reserved) | Which stations people play, and from where | each Start Radio, Play Station, Your Station's Play, a station's page, Autoplay |
| `station_page` | `action` (`opened`, `new_picks`, `row`, `play`) | Is the page looked at before playing; is New Picks used | StationDetailView |
| `radio_feedback` | `kind` (`skip`, `like`, `dislike`, `undo`) | Does the radio get told what is liked | RadioController |
| `dial_changed` | `value` (bucket) | Where people set the dial | the three dials, when let go |
| `track_ended` | `outcome` (`completed`, `partial`, `skipped`), `station` (bool) | How much is heard to the end, on the radio and off it | `AudioPlayer.deliver` |
| `lyrics_shown` | `source` (`server`, `lrclib`, `none`, `failed`), `synced` (bool) | How often lyrics are there, and from where | LyricsView |
| `mix_opened` | `kind` (the MixKind: `daily`, `newArrivals`, `rediscover`, `deepCuts`, `favorites`, `onRepeat`, `decade`, `genre`) | Which of Home's mixes are opened | MixDetailView |
| `mix_played` | `kind` (as above) | Which mixes are played | `AudioPlayer.playMix` |
| `playlist_created` | `from` (`library`, `mix`, `station`, `queue`, `add_to_playlist`) | Where playlists are made; is Save as Playlist used | PlaylistsView, MixDetailView, StationDetailView, QueueView, AddToPlaylistSheet |
| `playlist_songs_added` | `from` (`add_songs`, `add_to_playlist`) | How playlists are filled | AddSongsSheet, AddToPlaylistSheet |
| `favorite_set` | `item` (`track`, `album`, `artist`), `on` (bool) | Are favourites used, and for what | `LibraryStore.setFavorite`, once the server took it |
| `search_used` | `results` (bucket) | Is search used; how often it finds nothing | SearchView, once a search, when the typing first rests (1.5 s) |
| `setting_changed` | `name` (`wifi_quality`, `cellular_quality`, `normalize`, `autoplay`, `find_lyrics_online`, `spin_record`, `share_usage`, `keep_songs`), `value` (`original`, `high`, `normal`, `low`; `on`, `off`; `share_usage` only `off`) | Which settings are changed, to what; is Keep Songs I Play turned off | AppSettings, whoever changes it (Settings, the queue's Autoplay, Remove All Downloads for `keep_songs`) |
| `lastfm_key` | `state` (`added`, `removed`) | Do people add a Last.fm key | Settings, once Last.fm accepted it, or when emptied |
| `playback_error` | `reason` (`network`, `server`, `unsupported`, `other`) | How often a song does not play, and why | `AudioPlayer.itemFailed` |
| `download_chosen` | `kind` (`album`, `playlist`, `mix`) | Are downloads used, and for what | `OfflineStore.download`, each Download on a page |
| `offline_play_started` | `from` (as `play_started`'s) | Is music played offline, and from what | `AudioPlayer.play`, `playRadio`, while offline (with `play_started`) |

What the `from` of `station_started` means: `page` a station's page (its
Play or a song on it); `tile_menu` a station's long press, Play Station;
`hero` Your Station's Play on Home's card or Radio's; `menu` any Start Radio
of a song, album, artist, playlist, genre or mix (in a menu or under a
page's Play); `autoplay` Autoplay after an album or playlist ended; `search`
a Start Radio or a song in Search. Start a Station (the picker) opens the
station's page since 8 November 2026, so what it starts counts as `page`;
`picker` stays in the list for a picker that would play at once.

Downloads count only that one was chosen, of what kind, and that music
started while offline; not the download quality, the keep's size, Download
over Cellular, how much is on the phone, or what was removed.

Not counted: what is played, by whom or from where; titles, artists,
albums, genres, playlists' and mixes' names; what was searched for; server
addresses and names, user names; the Last.fm key; lyrics; error messages.
No crash or error reports (`trackError` is not used).

## The App Store

App Store Connect › App Privacy: **Usage Data › Product Interaction**, not
linked to the user, not used for tracking, purpose **Analytics**. Nothing
else is collected. `Jukebox/Resources/PrivacyInfo.xcprivacy` declares the
same, with UserDefaults' reason CA92.1 (the app's own settings), and
Aptabase's package brings its own manifest saying the same. XcodeGen puts the
manifest in the app's resources: `project.yml` takes everything under
`Jukebox/`, and XcodeGen (2.40.1 and later) gives a file of a type it has no
rule for, `.xcprivacy` among them, the Copy Bundle Resources phase.

A privacy policy for the App Store's listing should say the same in words:
anonymous counts of features used, on the developer's own server, no
cookies, no device id, no address, off in Settings › Privacy.
