// Now Playing: what plays, full screen and always dark, as Music has it —
// the cover large over its own colours blurred, the title and the artist,
// the scrubber, the transport, the system's volume and AirPlay, and in the
// cover's place, at a tap, the lyrics or the queue. While a station plays,
// its thumbs sit under the transport, beside the station's name: the radio
// is the photographer's favourite part ("ik vind vooral de radiofunctie
// echt belangrijk", 8 November 2026), and what it learns from is one tap
// away here. A pull down anywhere on the cover, or on the top, closes it.

import JukeboxKit
import SwiftUI
import UIKit

/// What the big area shows: the cover, or in its place the lyrics or the
/// queue, as Music swaps them.
enum NowPlayingPanel: Hashable {
    case cover
    case lyrics
    case queue
}

struct NowPlayingView: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(RadioController.self) private var radio
    @Environment(LibraryStore.self) private var library
    @Environment(Navigator.self) private var navigator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var panel: NowPlayingPanel = .cover
    /// How far the view has been pulled down to close it.
    @State private var dragOffset: CGFloat = 0
    /// True while a pull is held. SwiftUI resets it when the system cancels
    /// the pull (a call, Siri), which never reaches onEnded.
    @GestureState private var isPulling = false
    /// Counted, so each tap plays the glyph's bounce once.
    @State private var previousTaps = 0
    @State private var nextTaps = 0
    @Namespace private var coverSpace

    @ScaledMetric(relativeTo: .title) private var skipGlyph: CGFloat = 30
    @ScaledMetric(relativeTo: .largeTitle) private var playGlyph: CGFloat = 44

    var body: some View {
        ZStack {
            NowPlayingBackdrop(artwork: currentTrack?.artwork)
            GeometryReader { proxy in
                // An iPad held sideways: the cover on the left, the rest on
                // the right, as Music lays it out. The iPhone is portrait.
                let wide = proxy.size.width > proxy.size.height && proxy.size.width >= 700
                VStack(spacing: 0) {
                    header
                    if wide {
                        wideLayout
                    } else {
                        tallLayout
                            .frame(maxWidth: 560)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .overlay(alignment: .top) {
            ZStack {
                errorBanner
            }
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.85),
                       value: player.errorMessage)
        }
        // A pull down closes it; over the lyrics and the queue only the top
        // does, so their own scrolling and reordering keep working.
        .contentShape(.rect)
        .gesture(dismissDrag, including: panel == .cover ? .all : .subviews)
        .offset(y: dragOffset)
        .accessibilityAction(.escape) {
            close()
        }
        .environment(\.colorScheme, .dark)
        // The cover's own presentation dark too, so the status bar, the
        // menus and the system's volume and AirPlay views are drawn for dark
        // even when the phone is in light mode. A presentation's preference:
        // the app under it keeps its own appearance.
        .preferredColorScheme(.dark)
        .onChange(of: player.errorMessage) { _, message in
            if let message {
                UIAccessibility.post(notification: .announcement, argument: message)
            }
        }
        .onChange(of: isPulling) { _, pulling in
            // A cancelled pull would leave the view where the finger was.
            // Looked at after this update, when an onEnded that did run has
            // already closed the view or settled it.
            guard !pulling else { return }
            Task {
                guard dragOffset > 0, navigator.isNowPlayingPresented else { return }
                settle()
            }
        }
        // "Add to Playlist…" from the "…" menu, Up Next or History: the tab
        // view's sheet cannot show while this cover is over it, so the
        // sheet is presented from here (MainTabView holds its own back).
        .sheet(item: Binding(get: { navigator.addToPlaylist },
                             set: { navigator.addToPlaylist = $0 })) { request in
            AddToPlaylistSheet(tracks: request.tracks)
        }
    }

    // MARK: Layouts

    private var tallLayout: some View {
        VStack(spacing: 0) {
            if panel == .cover {
                coverArea
                    .padding(.horizontal, Theme.Space.xl)
                    .padding(.vertical, Theme.Space.l)
                titleRow
                    .padding(.horizontal, Theme.Space.xl)
                    .transition(.opacity)
            } else {
                compactHeader
                    .padding(.horizontal, Theme.Space.xl)
                    .padding(.vertical, Theme.Space.m)
                    .transition(.opacity)
                panelContent
                    .frame(maxHeight: .infinity)
            }
            controls
        }
    }

    private var wideLayout: some View {
        HStack(spacing: Theme.Space.xxl * 1.5) {
            Group {
                switch panel {
                case .cover:
                    coverArea
                case .lyrics:
                    LyricsView()
                case .queue:
                    QueueView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                titleRow
                    .padding(.horizontal, Theme.Space.xl)
                controls
                Spacer(minLength: 0)
            }
            .frame(width: 440)
        }
        .padding(.horizontal, Theme.Space.xxl)
        .padding(.vertical, Theme.Space.l)
    }

    @ViewBuilder private var panelContent: some View {
        switch panel {
        case .cover:
            EmptyView()
        case .lyrics:
            LyricsView()
                .transition(.opacity)
        case .queue:
            QueueView()
                .transition(.opacity)
        }
    }

    // MARK: Top

    private var header: some View {
        VStack(spacing: Theme.Space.xs) {
            Capsule()
                .fill(Color.white.opacity(0.35))
                .frame(width: 36, height: 5)
                .accessibilityHidden(true)
            HStack(spacing: Theme.Space.m) {
                Button {
                    close()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.title3.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")

                VStack(spacing: 2) {
                    if let title = contextTitle {
                        Eyebrow("Playing From")
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)

                // As wide as the close button, so the title is centred.
                Color.clear
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            }
        }
        .padding(.top, Theme.Space.s)
        .padding(.horizontal, Theme.Space.m)
        .contentShape(.rect)
        .gesture(dismissDrag)
    }

    // MARK: The cover and the title

    private var coverArea: some View {
        GeometryReader { proxy in
            let side = max(0, min(proxy.size.width, proxy.size.height))
            bigCover(side: side)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    /// The cover sits back a little while paused and comes forward when the
    /// music plays, as Music's does; still under Reduce Motion.
    private func bigCover(side: CGFloat) -> some View {
        let playing = player.isPlaying
        return NowPlayingCover(artwork: currentTrack?.artwork, drawnSide: side, cornerRadius: Theme.Radius.card)
            .nowPlayingMatched("cover", in: coverSpace, enabled: !reduceMotion)
            .frame(width: side, height: side)
            .shadow(color: Color.black.opacity(playing ? 0.45 : 0.25), radius: playing ? 28 : 14, y: playing ? 14 : 6)
            .scaleEffect(playing ? 1 : 0.84)
            .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.68), value: playing)
    }

    private var titleRow: some View {
        HStack(spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                title(.title2.bold())
                artistLine(.title3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trackButtons
        }
        .padding(.bottom, Theme.Space.xs)
    }

    /// Over the lyrics and the queue: the cover small, the title beside it.
    private var compactHeader: some View {
        HStack(spacing: Theme.Space.m) {
            Button {
                show(.cover)
            } label: {
                NowPlayingCover(artwork: currentTrack?.artwork, drawnSide: 60, cornerRadius: Theme.Radius.artwork)
                    .nowPlayingMatched("cover", in: coverSpace, enabled: !reduceMotion)
                    .frame(width: 60, height: 60)
                    .shadow(color: Color.black.opacity(0.3), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show Cover")

            VStack(alignment: .leading, spacing: 2) {
                title(.headline)
                artistLine(.subheadline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trackButtons
        }
    }

    @ViewBuilder private func title(_ font: Font) -> some View {
        if let track = currentTrack {
            Text(track.name)
                .font(font)
                .lineLimit(1)
        } else {
            Text("Not Playing")
                .font(font)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    /// The artist's name, which goes to the artist when the library knows them.
    @ViewBuilder private func artistLine(_ font: Font) -> some View {
        if let track = currentTrack, !track.artistLine.isEmpty {
            if let found = libraryArtist(for: track) {
                Button {
                    navigator.open(.artist(found))
                } label: {
                    Text(track.artistLine)
                        .font(font)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the artist")
            } else {
                Text(track.artistLine)
                    .font(font)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder private var trackButtons: some View {
        if let track = currentTrack {
            favoriteButton(track)
            Menu {
                TrackMenu(track: track)
            } label: {
                NowPlayingRoundGlyph(systemName: "ellipsis")
            }
            .accessibilityLabel("More")
        }
    }

    /// The heart. While the radio's station plays, a heart is a thumbs up
    /// too: a song loved on a station is the clearest "more like this" the
    /// listener gives, and it should not take a second tap on the thumb to
    /// teach the station so. Taking the heart back leaves the thumb as it
    /// is: not loving a song any more is not disliking it, and the thumb has
    /// its own button beside the station's name.
    private func favoriteButton(_ track: Track) -> some View {
        let favorite = library.isFavorite(track.id)
        return Button {
            let turningOn = !library.isFavorite(track.id)
            // like() toggles: a song already thumbed up would lose its thumb.
            if turningOn, radioStation != nil, !radio.liked.contains(track.id) {
                radio.like(track)
            }
            Task { await library.toggleFavorite(track.id) }
        } label: {
            NowPlayingRoundGlyph(systemName: favorite ? "heart.fill" : "heart", isOn: favorite)
                .symbolEffect(.bounce, value: favorite)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(favorite ? "Undo Favorite" : "Favorite")
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 0) {
            NowPlayingScrubber()
                .padding(.top, Theme.Space.l)
            transport
                .padding(.vertical, Theme.Space.s)
            if let station = playingStation, let track = currentTrack {
                stationRow(station, track)
                    .padding(.bottom, Theme.Space.m)
            }
            volume
            bottomRow
                .padding(.top, Theme.Space.xs)
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.bottom, Theme.Space.s)
    }

    private var transport: some View {
        HStack(spacing: 0) {
            Button {
                previousTaps += 1
                player.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: skipSize))
                    .symbolEffect(.bounce, value: previousTaps)
            }
            .buttonStyle(NowPlayingTransportStyle(diameter: skipSize * 1.9))
            .accessibilityLabel("Previous")

            Spacer(minLength: 0)

            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: playSize))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(NowPlayingTransportStyle(diameter: playSize * 1.7))
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

            Spacer(minLength: 0)

            Button {
                nextTaps += 1
                player.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: skipSize))
                    .symbolEffect(.bounce, value: nextTaps)
            }
            .buttonStyle(NowPlayingTransportStyle(diameter: skipSize * 1.9))
            .accessibilityLabel("Next")
        }
        .padding(.horizontal, Theme.Space.l)
        .disabled(currentTrack == nil)
    }

    /// The station's row: thumbs down, its name, thumbs up. A thumbs down
    /// skips the song and plays less like it; a thumbs up plays more like
    /// it; either way the songs ahead are chosen again (RadioController).
    private func stationRow(_ station: Station, _ track: Track) -> some View {
        let liked = radio.liked.contains(track.id)
        let disliked = radio.disliked.contains(track.id)
        return HStack(spacing: Theme.Space.m) {
            Button {
                radio.dislike(track)
            } label: {
                NowPlayingRoundGlyph(systemName: disliked ? "hand.thumbsdown.fill" : "hand.thumbsdown", isOn: disliked)
                    .symbolEffect(.bounce, value: disliked)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dislike")
            .accessibilityHint("Skips this song and plays less like it")
            .accessibilityAddTraits(disliked ? .isSelected : [])

            Spacer(minLength: 0)
            stationChip(station)
            Spacer(minLength: 0)

            Button {
                radio.like(track)
            } label: {
                NowPlayingRoundGlyph(systemName: liked ? "hand.thumbsup.fill" : "hand.thumbsup", isOn: liked)
                    .symbolEffect(.bounce, value: liked)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Like")
            .accessibilityHint("Plays more like this song")
            .accessibilityAddTraits(liked ? .isSelected : [])
        }
    }

    /// The station's name as Numa's grey label in a faint capsule; it goes
    /// to the Radio tab, where the station's dial is.
    private func stationChip(_ station: Station) -> some View {
        Button {
            navigator.tab = .radio
            close()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(Theme.eyebrow)
                Text(station.title.uppercased())
                    .font(Theme.eyebrow)
                    .tracking(Theme.eyebrowTracking)
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.1), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Station: \(station.title)")
        .accessibilityHint("Opens Radio")
    }

    private var volume: some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: "speaker.fill")
                .accessibilityHidden(true)
            NowPlayingVolumeSlider()
                .frame(height: 30)
            Image(systemName: "speaker.wave.3.fill")
                .accessibilityHidden(true)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var bottomRow: some View {
        HStack {
            panelToggle(.lyrics, symbol: "quote.bubble", onSymbol: "quote.bubble.fill", label: "Lyrics")
            Spacer()
            NowPlayingAirPlayButton()
                .frame(width: 44, height: 44)
            Spacer()
            panelToggle(.queue, symbol: "list.bullet", onSymbol: "list.bullet", label: "Up Next")
        }
        .padding(.horizontal, Theme.Space.s)
    }

    /// Lyrics and Up Next take the cover's place; a second tap gives it back.
    private func panelToggle(_ target: NowPlayingPanel, symbol: String, onSymbol: String,
                             label: LocalizedStringKey) -> some View {
        let isOn = panel == target
        return Button {
            show(isOn ? .cover : target)
        } label: {
            Image(systemName: isOn ? onSymbol : symbol)
                .font(.title3)
                .foregroundStyle(isOn ? HierarchicalShapeStyle.primary : HierarchicalShapeStyle.secondary)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(isOn ? 0.18 : 0), in: .circle)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .disabled(currentTrack == nil && !isOn)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// "Could not play …", for the five seconds the player keeps it.
    @ViewBuilder private var errorBanner: some View {
        if let message = player.errorMessage {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .padding(.horizontal, Theme.Space.l)
                .padding(.vertical, Theme.Space.s)
                .background(Color.black.opacity(0.6), in: .capsule)
                .padding(.horizontal, Theme.margin)
                .padding(.top, 64)
                .transition(bannerTransition)
        }
    }

    private var bannerTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity)
    }

    // MARK: Closing

    private var dismissDrag: some Gesture {
        // Global: the view moves under the finger, so its own coordinates
        // would move with it.
        DragGesture(minimumDistance: 16, coordinateSpace: .global)
            .updating($isPulling) { _, pulling, _ in
                pulling = true
            }
            .onChanged { value in
                let down = value.translation.height
                if dragOffset == 0 {
                    // Down, and more down than sideways: a sideways swipe
                    // is not a close.
                    guard down > 0, down > abs(value.translation.width) else { return }
                }
                dragOffset = max(0, down)
            }
            .onEnded { value in
                if dragOffset > 0, value.translation.height > 140 || value.predictedEndTranslation.height > 480 {
                    close()
                } else {
                    settle()
                }
            }
    }

    private func close() {
        navigator.isNowPlayingPresented = false
    }

    /// Back up, for a pull that was not a close.
    private func settle() {
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 0.82)) {
            dragOffset = 0
        }
    }

    private func show(_ new: NowPlayingPanel) {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.86)) {
            panel = new
        }
    }

    // MARK: State

    private var currentTrack: Track? {
        player.currentTrack
    }

    private var playingStation: Station? {
        player.context?.station
    }

    /// The radio's station, while it is what plays: the radio has one and
    /// the queue is its. Not while a new station is still being tuned in
    /// over the old one's last song, nor when the radio has stopped and the
    /// queue still carries a station's name: the thumb would teach nothing,
    /// or the wrong station.
    private var radioStation: Station? {
        guard let station = radio.station, player.context?.station?.id == station.id else { return nil }
        return station
    }

    private var contextTitle: String? {
        guard let title = player.context?.title, !title.isEmpty else { return nil }
        return title
    }

    private var skipSize: CGFloat {
        min(skipGlyph, 44)
    }

    private var playSize: CGFloat {
        min(playGlyph, 64)
    }

    private func libraryArtist(for track: Track) -> Artist? {
        guard let ref = track.primaryArtist else { return nil }
        return library.artist(ref)
    }
}

/// The cover as it flies between its big place and its small one.
/// matchedGeometryEffect flies a view by offering it the frames in between,
/// and ArtworkView keeps the size it is given, so on its own it would slide
/// without growing or shrinking. Here it
/// is drawn at `drawnSide` (its image fetched for that size, so the big cover
/// stays sharp) and scaled to the square it is offered: at rest that is
/// `drawnSide`, and the scale is 1.
private struct NowPlayingCover: View {
    let artwork: Artwork?
    let drawnSide: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        Color.clear
            .overlay {
                GeometryReader { proxy in
                    let scale = drawnSide > 0 ? proxy.size.width / drawnSide : 1
                    ArtworkView(artwork, size: drawnSide, cornerRadius: cornerRadius)
                        .scaleEffect(scale)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
    }
}

private extension View {
    /// The cover's flight between its big place and its small one, as
    /// Music's; none under Reduce Motion, where the two only crossfade.
    @ViewBuilder
    func nowPlayingMatched(_ id: String, in namespace: Namespace.ID, enabled: Bool) -> some View {
        if enabled {
            matchedGeometryEffect(id: id, in: namespace)
        } else {
            self
        }
    }
}
