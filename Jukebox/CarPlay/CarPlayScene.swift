// CarPlay: "we missen iets echt extreem belangrijks in de ios app, carplay!"
// (the photographer, 16 November 2026). Apple's templates, not a screen of
// Jukebox's own: the car draws them in its own style, and an audio app may
// only use lists, a tab bar and Now Playing. Three tabs, as the phone's
// first three: Home (Your Station, the mixes, played lately, recently
// added), Radio (the stations the Radio tab lists) and Library (playlists,
// albums, artists, favourites, downloaded). Everything plays through the
// calls the phone's screens make, so the queue, the radio, offline and the
// counts behave the same; nothing here chooses or queues by itself.
//
// Now Playing is CarPlay's own, fed by NowPlayingInfo and RemoteCommands as
// the lock screen is. Its buttons are Now Playing's on the phone, in the
// car's form: on a station the thumbs, otherwise shuffle and repeat.
//
// No lyrics in the car, and no screen that asks for the phone but the one
// that says to sign in there: Apple's CarPlay addendum for audio apps.

#if os(iOS)
import CarPlay
import JukeboxKit
import Observation
import UIKit

/// Named in project.yml's scene manifest (CPTemplateApplicationSceneSessionRoleApplication)
/// by this Objective-C name, so the plist does not depend on the module's.
@objc(CarPlaySceneDelegate)
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate, CPNowPlayingTemplateObserver {
    /// The phone's model: CarPlay can launch the app without its window,
    /// and both must play the same queue.
    private let app = AppModel.shared
    private var interface: CPInterfaceController?

    private let home = CPListTemplate(title: String(localized: "Home"), sections: [])
    private let radio = CPListTemplate(title: String(localized: "Radio"), sections: [])
    private let library = CPListTemplate(title: String(localized: "Library"), sections: [])
    private lazy var tabs = CPTabBarTemplate(templates: [home, radio, library])
    /// Launching, or signed out: the one notice the car shows.
    private let notice = CPListTemplate(title: "Jukebox", sections: [])

    // MARK: Connecting

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        interface = interfaceController
        // Is CarPlay used (Stats, `screen`): once a connection.
        Stats.track(.screen, ["name": "carplay"])
        home.tabTitle = String(localized: "Home")
        home.tabImage = UIImage(systemName: "house.fill")
        radio.tabTitle = String(localized: "Radio")
        radio.tabImage = UIImage(systemName: "dot.radiowaves.left.and.right")
        library.tabTitle = String(localized: "Library")
        library.tabImage = UIImage(systemName: "square.stack.fill")

        let nowPlaying = CPNowPlayingTemplate.shared
        nowPlaying.isUpNextButtonEnabled = true
        nowPlaying.upNextTitle = String(localized: "Up Next")
        nowPlaying.add(self)

        watchLists()
        watchPlayer()
        // Launched by the car alone, the phone's window never asked for the
        // session; restore does nothing when the window already has.
        // Then, as the phone's window does when it comes to the front: is
        // the server there. A car is often far from the home network, and
        // offline only the songs on the phone play.
        Task {
            await app.restore()
            if app.phase == .signedIn { app.offline.appBecameActive() }
        }
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        CPNowPlayingTemplate.shared.remove(self)
        interface = nil
    }

    // MARK: Keeping the lists current

    /// Every list read again when what it shows changes: the library loads,
    /// the mixes are made, a station is played. Observation's change comes
    /// once a registration, so the hop to the main actor gathers a burst of
    /// changes into one refresh.
    private func watchLists() {
        guard interface != nil else { return }
        withObservationTracking {
            refreshLists()
        } onChange: {
            Task { @MainActor [weak self] in self?.watchLists() }
        }
    }

    private func refreshLists() {
        guard let interface else { return }
        guard app.phase == .signedIn else {
            notice.emptyViewTitleVariants = app.phase == .signedOut
                ? [String(localized: "Sign in on your iPhone")] : ["Jukebox"]
            notice.emptyViewSubtitleVariants = app.phase == .signedOut
                ? [String(localized: "Open Jukebox on your iPhone and sign in to your music server.")] : []
            if interface.rootTemplate !== notice {
                interface.setRootTemplate(notice, animated: false, completion: nil)
            }
            return
        }
        home.updateSections(homeSections())
        radio.updateSections(radioSections())
        library.updateSections(librarySections())
        let empty = app.library.tracks.isEmpty ? [String(localized: "Loading your library")] : []
        home.emptyViewTitleVariants = empty
        radio.emptyViewTitleVariants = empty
        // Settings › Pages, as the phone's tabs: Radio off, its tab goes;
        // every library kind off, the Library's.
        var shown: [CPTemplate] = [home]
        if app.settings.shows(.radio) { shown.append(radio) }
        if app.settings.showsLibrary { shown.append(library) }
        if tabs.templates.map({ ObjectIdentifier($0) }) != shown.map({ ObjectIdentifier($0) }) {
            tabs.updateTemplates(shown)
        }
        // Replaced only when it is not the root yet: setting it again would
        // pop what the driver has opened.
        if interface.rootTemplate !== tabs {
            interface.setRootTemplate(tabs, animated: false, completion: nil)
        }
    }

    // MARK: Home

    private func homeSections() -> [CPListSection] {
        let lib = app.library
        guard !lib.tracks.isEmpty else { return [] }
        let station = row(String(localized: "Your Station"), detail: String(localized: "Made from what you play"),
                          symbol: "dot.radiowaves.left.and.right") { [weak self] in
            guard let self else { return }
            self.startStation(self.app.radio.station(for: .personal))
        }
        station.isPlaying = app.radio.stationOnAir(player: app.player)?.seed == .personal
        let mixes = app.mixes.mixes.map { mix in
            row(mix.title, detail: mix.subtitle, artwork: mix.artwork.first) { [weak self] in
                self?.app.player.playMix(mix)
                self?.showNowPlaying()
            }
        }
        let played = lib.recentlyPlayedAlbums.prefix(12).map(albumRow)
        let added = lib.recentlyAddedAlbums.prefix(20).map(albumRow)
        return fit([(nil, [station]), (String(localized: "Mixes"), mixes),
                    (String(localized: "Played lately"), played), (String(localized: "Recently added"), added)])
    }

    // MARK: Radio

    /// As the Radio tab lists them: the three of the listener's own taste,
    /// those played lately, then the suggested ones by artist, genre and
    /// decade.
    private func radioSections() -> [CPListSection] {
        guard !app.library.tracks.isEmpty else { return [] }
        let built = app.mixes.stations
        func own(_ seed: StationSeed) -> Station { built.first { $0.seed == seed } ?? app.radio.station(for: seed) }
        var mine = [own(.personal), own(.discovery)]
        if let loved = built.first(where: { $0.seed == .favorites }) {
            mine.append(loved)
        } else if app.mixes.builtAt == nil && !app.library.favoriteTracks.isEmpty {
            mine.append(app.radio.station(for: .favorites))
        }
        var seen = Set(mine.map(\.id))
        mine += app.radio.recentStations.filter { seen.insert($0.id).inserted }
        let suggested = built.filter { seen.insert($0.id).inserted }
        let onAir = app.radio.stationOnAir(player: app.player)?.id
        func rows(_ stations: [Station]) -> [CPListItem] {
            stations.map { station in
                let item = row(station.title, detail: station.subtitle, artwork: station.artwork.first) { [weak self] in
                    self?.startStation(station)
                }
                // Light means on air: the station that plays is marked.
                item.isPlaying = station.id == onAir
                return item
            }
        }
        return fit([(String(localized: "Stations"), rows(mine)), (String(localized: "Suggested"), rows(suggested))])
    }

    private func startStation(_ station: Station) {
        Stats.track(.stationStarted, ["seed": Stats.seed(station.seed), "from": "carplay"])
        app.radio.start(station)
        showNowPlaying()
    }

    // MARK: Library

    private func librarySections() -> [CPListSection] {
        let settings = app.settings
        let lib = app.library
        var kinds: [CPListItem] = []
        if settings.shows(.playlists) {
            kinds.append(push(String(localized: "Playlists"), symbol: "music.note.list") { [weak self] in
                guard let self else { return [] }
                return self.app.library.playlists.map(self.playlistRow)
            })
        }
        if settings.shows(.albums) {
            kinds.append(push(String(localized: "Albums"), symbol: "square.stack") { [weak self] in
                guard let self else { return [] }
                return self.app.library.albums(sortedBy: .title).map(self.albumRow)
            })
        }
        if settings.shows(.artists) {
            kinds.append(push(String(localized: "Artists"), symbol: "music.mic") { [weak self] in
                guard let self else { return [] }
                return self.app.library.artistsByName.map(self.artistRow)
            })
        }
        if settings.shows(.favorites) {
            kinds.append(row(String(localized: "Favorites"), symbol: "heart") { [weak self] in
                guard let self else { return }
                let context = QueueContext(.favorites, title: String(localized: "Favorite Songs"))
                self.interface?.pushTemplate(self.songs(String(localized: "Favorites"), self.app.library.favoriteTracks,
                                                        context: context), animated: true, completion: nil)
            })
        }
        if settings.shows(.downloaded) {
            kinds.append(push(String(localized: "Downloaded"), symbol: "arrow.down.circle") { [weak self] in
                self?.downloadedRows() ?? []
            })
        }
        for kind in kinds { kind.accessoryType = .disclosureIndicator }
        // Read here so the list refreshes when they come or change.
        _ = (lib.playlists.count, lib.albums.count, lib.artists.count, app.offline.collections.count)
        return fit([(nil, kinds)])
    }

    private func albumRow(_ album: Album) -> CPListItem {
        row(album.name, detail: album.artistLine, artwork: album.artwork) { [weak self] in
            guard let self else { return }
            let tracks = self.app.library.tracks(inAlbum: album.id)
            self.interface?.pushTemplate(self.songs(album.name, tracks, context: QueueContext(.album(album.id), title: album.name)),
                                         animated: true, completion: nil)
        }
    }

    private func artistRow(_ artist: Artist) -> CPListItem {
        // Its songs, not its albums: an album under an artist would be one
        // level more than CarPlay's five with Now Playing and Up Next.
        row(artist.name, artwork: artist.artwork) { [weak self] in
            guard let self else { return }
            let tracks = self.app.library.tracks(by: artist)
            self.interface?.pushTemplate(self.songs(artist.name, tracks, context: QueueContext(.artist(artist.id), title: artist.name)),
                                         animated: true, completion: nil)
        }
    }

    private func playlistRow(_ playlist: Playlist) -> CPListItem {
        let item = CPListItem(text: playlist.name, detailText: nil)
        item.userInfo = playlist.artwork
        // The row's spinner shows while the server sends the songs.
        item.handler = { [weak self] _, done in
            Task { @MainActor in
                defer { done() }
                guard let self, let tracks = try? await self.app.library.tracks(in: playlist) else { return }
                let context = QueueContext(.playlist(playlist.id), title: playlist.name)
                self.interface?.pushTemplate(self.songs(playlist.name, tracks, context: context), animated: true, completion: nil)
            }
        }
        return item
    }

    /// Library › Downloaded, as on the phone: everything on it shuffled,
    /// then each album, playlist and mix kept, then the songs kept as played.
    private func downloadedRows() -> [CPListItem] {
        let offline = app.offline
        let lib = app.library
        let kept = offline.keptTrackIDs.compactMap { lib.track(id: $0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let downloaded = QueueContext(.other, title: "Downloaded")
        var rows: [CPListItem] = []
        let everything = offline.collections.flatMap(\.tracks) + kept
        if !everything.isEmpty {
            rows.append(row(String(localized: "Shuffle All"), symbol: "shuffle") { [weak self] in
                guard let self else { return }
                var seen = Set<ItemID>()
                let tracks = everything.filter { self.app.offline.has($0.id) && seen.insert($0.id).inserted }
                self.play(tracks, context: downloaded, shuffled: true)
            })
        }
        for collection in offline.collections {
            let context: QueueContext
            let artwork: Artwork?
            switch collection.item {
            case let .album(album):
                context = QueueContext(.album(album.id), title: album.name)
                artwork = album.artwork
            case let .playlist(playlist):
                context = QueueContext(.playlist(playlist.id), title: playlist.name)
                artwork = playlist.artwork
            case let .mix(mix):
                context = QueueContext(.mix(mix.id), title: mix.title)
                artwork = mix.artwork.first
            }
            rows.append(row(collection.title, artwork: artwork) { [weak self] in
                guard let self else { return }
                self.interface?.pushTemplate(self.songs(collection.title, collection.tracks, context: context),
                                             animated: true, completion: nil)
            })
        }
        if !kept.isEmpty {
            rows.append(row(String(localized: "Songs"), detail: HomeText.songs(kept.count), symbol: "music.note") { [weak self] in
                guard let self else { return }
                self.interface?.pushTemplate(self.songs(String(localized: "Songs"), kept, context: downloaded),
                                             animated: true, completion: nil)
            })
        }
        return rows
    }

    // MARK: Songs

    /// An album's, a playlist's, an artist's songs: Play and Shuffle on top,
    /// then each song, which plays the list from there.
    private func songs(_ title: String, _ tracks: [Track], context: QueueContext) -> CPListTemplate {
        let actions = [
            row(String(localized: "Play"), symbol: "play.fill") { [weak self] in self?.play(tracks, context: context) },
            row(String(localized: "Shuffle"), symbol: "shuffle") { [weak self] in
                self?.play(tracks, context: context, shuffled: true)
            },
        ]
        let rows = tracks.enumerated().map { index, track in
            row(track.name, detail: track.artistLine, artwork: track.artwork) { [weak self] in
                self?.play(tracks, from: index, context: context)
            }
        }
        let list = CPListTemplate(title: title, sections: fit([(nil, tracks.isEmpty ? [] : actions), (nil, rows)]))
        list.emptyViewTitleVariants = [String(localized: "No songs")]
        return list
    }

    private func play(_ tracks: [Track], from index: Int = 0, context: QueueContext, shuffled: Bool = false) {
        app.player.play(tracks, startingAt: index, context: context, shuffled: shuffled)
        showNowPlaying()
    }

    // MARK: Now Playing

    /// After a tap that plays, Now Playing, as Apple asks of an audio app;
    /// back to it when it is already open under Up Next. Pushing a template
    /// that is in the stack already would raise.
    private func showNowPlaying() {
        guard let interface else { return }
        let nowPlaying = CPNowPlayingTemplate.shared
        if interface.topTemplate === nowPlaying { return }
        if interface.templates.contains(where: { $0 === nowPlaying }) {
            interface.pop(to: nowPlaying, animated: true, completion: nil)
        } else {
            interface.pushTemplate(nowPlaying, animated: true, completion: nil)
        }
    }

    private func watchPlayer() {
        guard interface != nil else { return }
        withObservationTracking {
            updateNowPlayingButtons()
        } onChange: {
            Task { @MainActor [weak self] in self?.watchPlayer() }
        }
    }

    /// On a station its thumbs, as the phone's Now Playing and the lock
    /// screen have them (RadioController.like and dislike); otherwise
    /// shuffle and repeat, which a station has no use for: it chooses the
    /// order and never ends.
    private func updateNowPlayingButtons() {
        let player = app.player
        var buttons: [CPNowPlayingButton] = []
        if player.context?.isRadio == true, let track = player.currentTrack {
            let disliked = app.radio.disliked.contains(track.id)
            let liked = app.radio.liked.contains(track.id)
            buttons.append(button(disliked ? "hand.thumbsdown.fill" : "hand.thumbsdown", selected: disliked) { [weak self] in
                guard let self, let track = self.app.player.currentTrack else { return }
                self.app.radio.dislike(track)
            })
            buttons.append(button(liked ? "hand.thumbsup.fill" : "hand.thumbsup", selected: liked) { [weak self] in
                guard let self, let track = self.app.player.currentTrack else { return }
                self.app.radio.like(track)
            })
        } else if player.hasTrack {
            buttons.append(button("shuffle", selected: player.isShuffled) { [weak self] in
                self?.app.player.toggleShuffle()
            })
            buttons.append(button(player.repeatMode == .one ? "repeat.1" : "repeat",
                                  selected: player.repeatMode != .off) { [weak self] in
                self?.app.player.cycleRepeat()
            })
        }
        CPNowPlayingTemplate.shared.updateNowPlayingButtons(buttons)
    }

    private func button(_ symbol: String, selected: Bool, action: @escaping () -> Void) -> CPNowPlayingButton {
        let button = CPNowPlayingImageButton(image: UIImage(systemName: symbol) ?? UIImage()) { _ in action() }
        button.isSelected = selected
        return button
    }

    /// Up Next: what comes after the song that plays; a song tapped plays
    /// from there, as in the phone's queue.
    func nowPlayingTemplateUpNextButtonTapped(_ nowPlayingTemplate: CPNowPlayingTemplate) {
        let rows = app.player.upNext.map { entry in
            row(entry.track.name, detail: entry.track.artistLine) { [weak self] in
                self?.app.player.skip(to: entry)
                self?.showNowPlaying()
            }
        }
        let list = CPListTemplate(title: String(localized: "Up Next"), sections: fit([(nil, rows)]))
        list.emptyViewTitleVariants = [String(localized: "Nothing up next")]
        interface?.pushTemplate(list, animated: true, completion: nil)
    }

    // MARK: Rows

    private func row(_ text: String, detail: String? = nil, artwork: Artwork? = nil, symbol: String? = nil,
                     action: @escaping () -> Void) -> CPListItem {
        let item = CPListItem(text: text, detailText: detail, image: symbol.flatMap { UIImage(systemName: $0) })
        // Its cover, loaded by `fit` once the row is one the car shows.
        item.userInfo = artwork
        item.handler = { _, done in
            action()
            done()
        }
        return item
    }

    /// A row that opens a list made when it is tapped, so the library's
    /// long lists are only made when wanted.
    private func push(_ title: String, symbol: String, rows: @escaping () -> [CPListItem]) -> CPListItem {
        row(title, symbol: symbol) { [weak self] in
            let list = CPListTemplate(title: title, sections: self?.fit([(nil, rows())]) ?? [])
            self?.interface?.pushTemplate(list, animated: true, completion: nil)
        }
    }

    /// Covers from the app's own image cache, as the phone's rows; set when
    /// they come.
    private func setArtwork(_ artwork: Artwork?, on item: CPListItem) {
        guard let artwork, let server = app.server else { return }
        let url = server.artworkURL(artwork, maxPixelSize: 200)
        if let image = ImagePipeline.shared.cached(url) {
            item.setImage(image)
            return
        }
        Task { @MainActor in
            if let image = await ImagePipeline.shared.image(for: url) { item.setImage(image) }
        }
    }

    /// Within what the car allows: so many sections, so many rows in all.
    /// Rows past the limit are left off, the first ones kept. Empty
    /// sections go.
    private func fit(_ sections: [(String?, [CPListItem])]) -> [CPListSection] {
        var left = Int(CPListTemplate.maximumItemCount)
        var covers = 60
        var result: [CPListSection] = []
        for (header, items) in sections where !items.isEmpty && left > 0
            && result.count < Int(CPListTemplate.maximumSectionCount) {
            let kept = Array(items.prefix(left))
            left -= kept.count
            // ponytail: covers for the first 60 rows of a list only, so
            // Albums does not fetch hundreds at once; scrolling further
            // shows rows without one. Load on scroll if that is missed.
            for item in kept.prefix(max(0, covers)) {
                setArtwork(item.userInfo as? Artwork, on: item)
            }
            covers -= kept.count
            result.append(CPListSection(items: kept, header: header, sectionIndexTitle: nil))
        }
        return result
    }
}
#endif
