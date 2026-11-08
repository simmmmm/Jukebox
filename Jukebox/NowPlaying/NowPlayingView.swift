// Now Playing: what plays, full screen and always dark, on Cabinet, flat.
// As sketch D draws it (docs/design/nowplaying-after.png): in the cover's
// place the record player (Turntable.swift), the song's cover turning on it
// as a picture disc — the photographer, 8 November 2026: "dan zou ik ook de
// plaat willen zien draaien met de album art er op" — then, from the margin,
// the title in the serif, the artist, and the station in Glow after its
// mark; the thumbs as plain glyphs beside the title; the slim scrubber; the
// transport; while a station plays its dial with its two ends in the place
// of the volume; and Lyrics, AirPlay and Up Next at the foot. Lyrics and the
// queue take the record's place at a tap. A pull down anywhere on the
// record, or on the top, closes it.
//
// The controls stay white; the accent (Glow, as Now Playing is always dark)
// marks only what is the radio's or what is on: the progress, the thumbs up
// given, the station's name, the dial. Gone with sketch D: the cover's
// colours blurred behind everything, "Playing From", the station as a
// spaced label in a capsule, round buttons.

import JukeboxKit
import SwiftUI
import UIKit

/// What the big area shows: the record, or in its place the lyrics or the
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

    @ScaledMetric(relativeTo: .title) private var skipGlyph: CGFloat = 30
    @ScaledMetric(relativeTo: .largeTitle) private var playGlyph: CGFloat = 44

    var body: some View {
        ZStack {
            // Cabinet, flat: no cover blurred behind it, no vignette
            // (tells.md, 2).
            Theme.Arch.cabinet
                .ignoresSafeArea()
                .accessibilityHidden(true)
            GeometryReader { proxy in
                // An iPad held sideways: the record on the left, the rest on
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
        // Once each time it opens (Stats), not again when a sheet over it closes.
        .countsScreen("now_playing")
    }

    // MARK: Layouts

    private var tallLayout: some View {
        VStack(spacing: 0) {
            if panel == .cover {
                turntable
                    .padding(.horizontal, Theme.Space.l)
                    .padding(.vertical, Theme.Space.s)
                    .transition(.opacity)
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
                    turntable
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

    /// The record player, the song's cover on its record (Turntable.swift).
    private var turntable: some View {
        Turntable(artwork: currentTrack?.artwork, isPlaying: player.isPlaying)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

                Spacer(minLength: 0)

                if let track = currentTrack {
                    Menu {
                        TrackMenu(track: track)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .accessibilityLabel("More")
                }
            }
        }
        .padding(.top, Theme.Space.s)
        .padding(.horizontal, Theme.Space.m)
        .contentShape(.rect)
        .gesture(dismissDrag)
    }

    // MARK: The title

    /// From the margin, as a sleeve's back is set: the title in the serif,
    /// the artist, and where it plays from — the station in Glow after its
    /// mark, or the album, mix or playlist in grey.
    private var titleRow: some View {
        HStack(alignment: .top, spacing: Theme.Space.s) {
            VStack(alignment: .leading, spacing: 2) {
                title(.serif(.title))
                artistLine(.title3)
                source
                    .padding(.top, Theme.Space.s)
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
                ArtworkView(currentTrack?.artwork, size: 60)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show Record")

            VStack(alignment: .leading, spacing: 2) {
                title(.serif(.title3))
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

    /// Where it plays from. A station: its mark and its name in Glow, which
    /// go to the Radio tab, where its dial is. Anything else: its name in
    /// grey ("From Velvet Songs").
    @ViewBuilder private var source: some View {
        if let station = playingStation {
            Button {
                navigator.tab = .radio
                close()
            } label: {
                HStack(spacing: 6) {
                    ArchMark(size: 16, style: .template)
                    Text(station.title)
                        .lineLimit(1)
                }
                .foregroundStyle(Theme.accent)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Station: \(station.title)")
            .accessibilityHint("Opens Radio")
        } else if let contextTitle {
            Text("From \(contextTitle)")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    /// While a station plays, its thumbs, plain (RadioThumbs); otherwise the
    /// heart.
    @ViewBuilder private var trackButtons: some View {
        if let track = currentTrack {
            if playingStation != nil {
                RadioThumbs(track: track)
            } else {
                favoriteButton(track)
            }
        }
    }

    /// The heart, while no station plays (with one, a song is loved from
    /// the "…" menu, and the thumbs take its place). Loving a song while
    /// the radio plays still teaches it (radioStation): a song loved on a
    /// station is the clearest "more like this" the listener gives.
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
            Image(systemName: favorite ? "heart.fill" : "heart")
                .font(.title3)
                .foregroundStyle(favorite ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                .symbolEffect(.bounce, value: favorite)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
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
            if playingStation != nil {
                // The station's dial in the volume's place: the system
                // Slider with its two ends (RadioDial), as on the Radio tab.
                // The volume stays on the phone's own buttons.
                RadioDial()
                    .padding(.top, Theme.Space.s)
                    .padding(.bottom, Theme.Space.m)
            } else {
                volume
            }
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

    /// Lyrics and Up Next take the record's place; a second tap gives it
    /// back. Plain glyphs: the one shown is white, the others grey.
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
                .contentShape(.rect)
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.margin)
                .padding(.vertical, Theme.Space.s)
                .background(Color.black.opacity(0.7))
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
