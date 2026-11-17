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
//
// The look: in his car (build 243) "carplay werkte trouwens, zag er niet
// heel best uit nog met donker icoon en lichtere tekst". The rows' glyphs
// were SF Symbols as templates, which CarPlay tints in a tab bar and Now
// Playing but not in a list row: there they came out in the default dark
// ink beside the car's light text. Every image a row shows is now drawn
// for the car's own traits, in both its looks (`carImage`). Home as the
// sketch he approved ("Ja, bouwen", 17 November 2026): Your Station first
// with its arch, the mixes as one row of covers, then the albums.

#if os(iOS)
import CarPlay
import JukeboxKit
import Observation
import SwiftUI
import UIKit

/// Named in project.yml's scene manifest (CPTemplateApplicationSceneSessionRoleApplication)
/// by this Objective-C name, so the plist does not depend on the module's.
@objc(CarPlaySceneDelegate)
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate, CPNowPlayingTemplateObserver {
    /// The phone's model: CarPlay can launch the app without its window,
    /// and both must play the same queue.
    private let app = AppModel.shared
    private var interface: CPInterfaceController?
    /// The account whose lists show: another signed in (Accounts.swift),
    /// what the driver had opened of the last one's goes.
    private var shownAccount: String?

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
        // The car plays from the phone: music left on a TV or another
        // client at home comes here, where it was (PlayOn.swift).
        if app.player.playsOn != nil { app.player.playHere() }
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
        let account = app.credentials.map { OfflinePaths.account(for: $0) }
        if let account, account != shownAccount {
            if shownAccount != nil, interface.templates.count > 1 {
                interface.popToRootTemplate(animated: false, completion: nil)
            }
            shownAccount = account
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
        let station = yourStationRow(ownStation(.personal))
        var mixes: [CPListTemplateItem] = []
        if let row = mixesRow(app.mixes.mixes) { mixes.append(row) }
        let played = lib.recentlyPlayedAlbums.prefix(12).map(albumRow)
        let added = lib.recentlyAddedAlbums.prefix(20).map(albumRow)
        return fit([(nil, [station]), (String(localized: "Mixes"), mixes),
                    (String(localized: "Played lately"), played), (String(localized: "Recently added"), added)])
    }

    /// Your Station, first on Home and on Radio: its arch, lit while it is
    /// on the air, and the one fact the phone's Home gives, the song on the
    /// air or when it last played. At its end Play in the accent; on the
    /// air CarPlay's own playing bars in its place.
    private func yourStationRow(_ station: Station) -> CPListItem {
        let player = app.player
        let onAir = app.radio.stationOnAir(player: player)?.seed == .personal
        let fact: String? = onAir
            ? player.currentTrack.map { "\($0.name) · \($0.artistLine)" }
            : RelativeDay.lastPlayed(HomeShelves.stationDates(events: app.history.history.events)[station.id])
        let item = CPListItem(text: String(localized: "Your Station"), detailText: fact,
                              image: stationMark(onAir: onAir),
                              accessoryImage: onAir ? nil : glyph("play.fill", color: accent),
                              accessoryType: .none)
        item.isPlaying = onAir
        item.playingIndicatorLocation = .trailing
        item.handler = { [weak self] _, done in
            self?.startStation(station)
            done()
        }
        return item
    }

    /// The mixes as one row of covers side by side, as many as the car
    /// takes; a cover plays its mix, the row's words open them all as a
    /// list.
    private func mixesRow(_ mixes: [Mix]) -> CPListImageRowItem? {
        guard !mixes.isEmpty else { return nil }
        let shown = Array(mixes.prefix(Int(CPMaximumNumberOfGridImages)))
        let side = CPListImageRowItem.maximumImageSize
        let pixels = Int(max(side.width, side.height) * carScale)
        let urls = shown.map { mix in mix.artwork.first.flatMap { art in app.server?.artworkURL(art, maxPixelSize: pixels) } }
        let blank = coverPlaceholder(side) ?? UIImage()
        let item = CPListImageRowItem(text: shown.map(\.title).joined(separator: " · "),
                                      images: urls.map { url in url.flatMap { ImagePipeline.shared.cached($0) } ?? blank })
        item.listImageRowHandler = { [weak self] _, index, done in
            if shown.indices.contains(index) { self?.playMix(shown[index]) }
            done()
        }
        item.handler = { [weak self] _, done in
            guard let self else { return done() }
            let rows = mixes.map { mix in
                self.row(mix.title, detail: mix.subtitle, artwork: mix.artwork.first) { [weak self] in self?.playMix(mix) }
            }
            let list = CPListTemplate(title: String(localized: "Mixes"), sections: self.fit([(nil, rows)]))
            self.interface?.pushTemplate(list, animated: true, completion: nil)
            done()
        }
        for (index, url) in urls.enumerated() {
            guard let url, ImagePipeline.shared.cached(url) == nil else { continue }
            Task { @MainActor in
                guard let image = await ImagePipeline.shared.image(for: url) else { return }
                var images = item.gridImages
                guard images.indices.contains(index) else { return }
                images[index] = image
                item.update(images)
            }
        }
        return item
    }

    private func playMix(_ mix: Mix) {
        app.player.playMix(mix)
        showNowPlaying()
    }

    // MARK: Radio

    /// As the Radio tab lists them: the three of the listener's own taste,
    /// those played lately, then the suggested ones by artist, genre and
    /// decade.
    private func radioSections() -> [CPListSection] {
        guard !app.library.tracks.isEmpty else { return [] }
        let built = app.mixes.stations
        let own = ownStation
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
                if station.seed == .personal { return yourStationRow(station) }
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

    /// A station of the listener's own taste as the mixes built it, with
    /// their covers; else as the radio makes it.
    private func ownStation(_ seed: StationSeed) -> Station {
        app.mixes.stations.first { $0.seed == seed } ?? app.radio.station(for: seed)
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
        let item = row(album.name, detail: album.artistLine, artwork: album.artwork) { [weak self] in
            guard let self else { return }
            let tracks = self.app.library.tracks(inAlbum: album.id)
            self.interface?.pushTemplate(self.songs(album.name, tracks, context: QueueContext(.album(album.id), title: album.name)),
                                         animated: true, completion: nil)
        }
        // It opens its songs, as the sketch's chevrons say.
        item.accessoryType = .disclosureIndicator
        return item
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
        let item = CPListItem(text: text, detailText: detail, image: symbol.flatMap { glyph($0) })
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
        // Until it comes, a quiet square in the car's own fill.
        item.setImage(rowPlaceholder)
        Task { @MainActor in
            if let image = await ImagePipeline.shared.image(for: url) { item.setImage(image) }
        }
    }

    /// Within what the car allows: so many sections, so many rows in all.
    /// Rows past the limit are left off, the first ones kept. Empty
    /// sections go.
    private func fit(_ sections: [(String?, [CPListTemplateItem])]) -> [CPListSection] {
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
            for case let item as CPListItem in kept.prefix(max(0, covers)) {
                setArtwork(item.userInfo as? Artwork, on: item)
            }
            covers -= kept.count
            result.append(CPListSection(items: kept, header: header, sectionIndexTitle: nil))
        }
        return result
    }

    // MARK: Images for the car

    /// The car's traits: its scale, light or dark as the car is now.
    private var carTraits: UITraitCollection {
        interface?.carTraitCollection ?? UITraitCollection.current
    }

    private var carScale: CGFloat {
        carTraits.displayScale > 0 ? carTraits.displayScale : 2
    }

    /// The accent, Glow on a dark car and Copper on a light one: the
    /// asset catalog's pair (Theme.accent). Not the lit tube's orange,
    /// which is for art only (docs/BRAND.md).
    private var accent: UIColor {
        UIColor(named: "AccentColor") ?? .tintColor
    }

    /// An image drawn once for each of the car's looks and kept together,
    /// so the car takes the one for its light or dark, also when it turns
    /// at dusk: CarPlay shows a row's image as it is, and an image drawn
    /// for the phone's look was the dark glyph on the dark car.
    private func carImage(_ draw: (UITraitCollection) -> UIImage?) -> UIImage? {
        let asset = UIImageAsset()
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = carTraits.modifyingTraits { $0.userInterfaceStyle = style }
            if let image = draw(traits) { asset.register(image, with: traits) }
        }
        return asset.image(with: carTraits) ?? draw(carTraits)
    }

    /// A row's glyph in the car's own ink (light on a dark car), or in
    /// the accent.
    private func glyph(_ name: String, color: UIColor = .label) -> UIImage? {
        carImage { traits in
            UIImage(systemName: name, compatibleWith: traits)?
                .withTintColor(color.resolvedColor(with: traits), renderingMode: .alwaysOriginal)
        }
    }

    /// Where a cover comes: the car's secondary fill, never a fixed dark
    /// on the dark car.
    private func coverPlaceholder(_ size: CGSize) -> UIImage? {
        carImage { traits in
            UIGraphicsImageRenderer(size: size, format: UIGraphicsImageRendererFormat(for: traits)).image { _ in
                UIColor.secondarySystemFill.resolvedColor(with: traits).setFill()
                UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: Theme.Radius.artwork).fill()
            }
        }
    }

    /// Drawn once a connection, at the first row that waits for its cover.
    private lazy var rowPlaceholder = coverPlaceholder(CPListItem.maximumImageSize)

    /// Your Station's arch at the size a row shows, for the car's scale.
    private func stationMark(onAir: Bool) -> UIImage? {
        let size = CPListItem.maximumImageSize
        let renderer = ImageRenderer(content: CarStationMark(side: min(size.width, size.height), onAir: onAir))
        renderer.scale = carScale
        return renderer.uiImage
    }
}

/// Your Station's image in the car: the mark on Cabinet, as on the icon.
/// Light means on air (docs/design/tells.md, 1): the tubes in their own
/// oranges with their one soft glow only while it plays; otherwise flat,
/// Copper outside and Glow inside. Cabinet in either look of the car, so
/// the mark always has its room.
private struct CarStationMark: View {
    let side: CGFloat
    let onAir: Bool

    var body: some View {
        let mark = side * 0.72
        let cut = ArchCut.forSize(mark)
        let line = StrokeStyle(lineWidth: cut.stroke * mark / 32, lineCap: .round)
        ZStack {
            Theme.Arch.cabinet
            if onAir {
                tubes(cut: cut, line: StrokeStyle(lineWidth: line.lineWidth * 2.2, lineCap: .round))
                    .frame(width: mark, height: mark)
                    .blur(radius: side * 0.03)
                    .opacity(0.42)
            }
            ZStack {
                tubes(cut: cut, line: line)
                ArchCore(cut: cut).fill(Theme.Arch.markCore)
            }
            .frame(width: mark, height: mark)
        }
        .frame(width: side, height: side)
        .clipShape(.rect(cornerRadius: Theme.Radius.artwork))
        // The core's warm white: the dark of the Cabinet behind it.
        .environment(\.colorScheme, .dark)
    }

    private func tubes(cut: ArchCut, line: StrokeStyle) -> some View {
        ZStack {
            ArchLine(tube: 0, cut: cut).stroke(onAir ? Theme.Arch.outerTube : Theme.Arch.copper, style: line)
            ArchLine(tube: 1, cut: cut).stroke(onAir ? Theme.Arch.innerTube : Theme.Arch.glow, style: line)
        }
    }
}
#endif
