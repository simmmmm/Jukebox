// The wide layout's bar under the window, on the iPad and the Mac, as
// Linux's (Linux/App/PlayerBar.swift) and the designer's spec (§2) have it:
// 88 tall, three zones from DesktopMeasures. The song at the left, the
// transport and where it is in the song in the window's middle, the panel's
// buttons and the sound at the right. Redrawn on Linux for the photographer's
// "ook klopt er geen fuck van deze verhoudingen" (14 November 2026): the
// middle is the window's middle, whatever the song's title.
//
// The same as Linux's, zone for zone ("ik wil dat de linux app en de apple
// app 1:1 op elkaar lijken", the photographer, 14 November 2026), with
// Apple's own where it looks and works the same: SF Symbols, a Slider for
// the position, the system's AirPlay picker and volume. A flat ground one
// step up from the page and a hairline on top; over Now Playing's room the
// room's ground and dark, no hairline: the bar is its transport there.

import JukeboxKit
import SwiftUI

struct PlayerBar: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(RadioController.self) private var radio
    @Environment(LibraryStore.self) private var library
    @Environment(Navigator.self) private var navigator
    @Environment(AppModel.self) private var app
    @Environment(AppSettings.self) private var settings
    @Environment(PanelState.self) private var panel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    /// The bar's width, which sets its zones.
    @State private var width: CGFloat = 1024

    init() {}

    var body: some View {
        let inRoom = navigator.isNowPlayingPresented
        // Three zones in a row: the middle one a share of the row in the
        // row's own middle, the two outer ones what is left, half each
        // (DesktopMeasures, the same numbers as Linux's ThreeZones).
        let zones = DesktopMeasures.zones(width: Int(width))
        HStack(spacing: 0) {
            songZone
                .padding(.leading, Theme.Space.l)
                .frame(width: CGFloat(max(0, zones.start)), alignment: .leading)
            VStack(spacing: Theme.Space.s) {
                transport
                PlayerBarPosition()
            }
            .frame(width: CGFloat(zones.middle))
            tools
                .padding(.trailing, Theme.Space.l)
                .frame(width: CGFloat(max(0, zones.end)), alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 88)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            width = newWidth
        }
        .background {
            // Down under the iPad's home indicator too.
            Self.groundFor(inRoom: inRoom).ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            if !inRoom {
                Hairline(inset: 0)
            }
        }
        // Over the room always dark, as Now Playing is.
        .environment(\.colorScheme, inRoom ? .dark : colorScheme)
    }

    /// Sidebar, panel and bar: one step up from the page (the designer's
    /// spec, §1), #1B1918 by night and #ECE7DF by day.
    static let ground = Color(light: 0xECE7DF, dark: 0x1B1918)

    /// The bar's and the panel's ground: their own, or over Now Playing's
    /// room the room's (#121110, with the scheme dark), no ground of their
    /// own, as Linux's `in-room` has it.
    static func groundFor(inRoom: Bool) -> Color {
        inRoom ? Theme.ground : Self.ground
    }

    // MARK: The song

    @ViewBuilder private var songZone: some View {
        if let track = player.currentTrack {
            HStack(spacing: Theme.Space.l) {
                Button {
                    navigator.isNowPlayingPresented = true
                } label: {
                    HStack(spacing: Theme.Space.m) {
                        ArtworkView(track.artwork, size: 56, cornerRadius: Theme.Radius.artwork)
                        VStack(alignment: .leading, spacing: Theme.Space.xs) {
                            Text(track.name)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            secondLine(track)
                                .font(.footnote)
                                .lineLimit(1)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("Now Playing")
                // A hand over the song may open the room: its sleeve's
                // cover and colour fetched now, as Linux draws its sleeve
                // on hover.
                .onHover { inside in
                    if inside { prefetchRoom(track) }
                }
                .accessibilityIdentifier("bar.song")
                .accessibilityLabel(spokenTitle(track))
                .accessibilityHint("Opens Now Playing")
                // Go to Album, Go to Artist, Start Radio, the heart: the
                // song's own menu, as a right-click on Linux's bar.
                .contextMenu {
                    TrackMenu(track: track)
                }

                // Not This on a station, then the heart, 4 apart.
                HStack(spacing: Theme.Space.xs) {
                    if player.context?.station != nil {
                        notThisButton(track)
                    }
                    heartButton(track)
                }
            }
        }
    }

    /// The artist; on a station, the station after its mark in the accent
    /// ("MC Polder  ⌂ Your Station"); the player's error while it keeps it,
    /// as the mini player shows it, or a song that does not play reads as a
    /// broken button.
    @ViewBuilder private func secondLine(_ track: Track) -> some View {
        if let error = player.errorMessage {
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(verbatim: error)
            }
            .foregroundStyle(.secondary)
        } else {
            HStack(spacing: Theme.Space.s) {
                if !track.artistLine.isEmpty {
                    Text(track.artistLine)
                        .foregroundStyle(.secondary)
                }
                if let station = player.context?.station {
                    HStack(spacing: Theme.Space.xs) {
                        ArchMark(size: 12, style: .template)
                        Text(station.title)
                    }
                    .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    /// The room's cover at about its sleeve's size (0.62 of a window's
    /// height, some 560 points) and at the 120 pixels its colour is taken
    /// from (NowPlayingGround), into ImagePipeline's cache.
    private func prefetchRoom(_ track: Track) {
        guard let artwork = track.artwork, let server = app.server else { return }
        let sleeve = server.artworkURL(artwork, maxPixelSize: ImagePipeline.bucket(Int(560 * displayScale)))
        let tone = server.artworkURL(artwork, maxPixelSize: 120)
        Task {
            _ = await ImagePipeline.shared.image(for: sleeve)
            _ = await ImagePipeline.shared.averageColor(for: tone)
        }
    }

    private func spokenTitle(_ track: Track) -> String {
        if let station = player.context?.station {
            return "\(track.name), \(station.title)"
        }
        return track.artistLine.isEmpty ? track.name : "\(track.name), \(track.artistLine)"
    }

    /// Less like this: skips the song and keeps it, and songs like it, off
    /// the station. Tapped again, taken back.
    private func notThisButton(_ track: Track) -> some View {
        let disliked = radio.disliked.contains(track.id)
        return Button {
            radio.dislike(track)
        } label: {
            Image(systemName: disliked ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                // Given, in the accent, as Linux's.
                .foregroundStyle(disliked ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                .frame(width: 32, height: 32)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Not This")
        .accessibilityLabel("Dislike")
        .accessibilityHint("Skips this song and plays less like it")
        .accessibilityAddTraits(disliked ? .isSelected : [])
    }

    /// The heart, in the accent when given. Given on a station it teaches
    /// the station too, as Now Playing's does.
    private func heartButton(_ track: Track) -> some View {
        let favorite = library.isFavorite(track.id)
        return Button {
            let turningOn = !library.isFavorite(track.id)
            // like() toggles: a song already thumbed up would lose its thumb.
            if turningOn, let station = radio.station, player.context?.station?.id == station.id,
               !radio.liked.contains(track.id) {
                radio.like(track)
            }
            Task { await library.toggleFavorite(.track(track.id)) }
        } label: {
            Image(systemName: favorite ? "heart.fill" : "heart")
                .foregroundStyle(favorite ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                .frame(width: 32, height: 32)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(favorite ? "Undo Favorite" : "Favorite")
        .accessibilityLabel(favorite ? "Undo Favorite" : "Favorite")
    }

    // MARK: The transport

    /// Shuffle, previous, play, next, repeat: shuffle and repeat flank the
    /// transport, as every desktop player has them ("mis ook nog repeat,
    /// repeat all en shuffle", the photographer, 14 November 2026). Play in
    /// a faint circle, as Linux's, never the accent: the page's Play is the
    /// one filled button.
    private var transport: some View {
        let onStation = player.context?.isRadio == true
        return HStack(spacing: Theme.Space.l) {
            modeButton(symbol: "shuffle", isOn: player.isShuffled, label: String(localized: "Shuffle"),
                       onStation: onStation) {
                player.toggleShuffle()
            }
            transportButton("backward.fill", label: "Previous", size: 32) { player.previous() }
            transportButton(player.isPlaying ? "pause.fill" : "play.fill",
                            label: player.isPlaying ? "Pause" : "Play", size: 40, font: .title3) {
                player.togglePlayPause()
            }
            .background(Color.primary.opacity(0.1), in: .circle)
            transportButton("forward.fill", label: "Next", size: 32) { player.next() }
            modeButton(symbol: player.repeatMode == .one ? "repeat.1" : "repeat", isOn: player.repeatMode != .off,
                       label: repeatLabel, onStation: onStation) {
                player.cycleRepeat()
            }
        }
        .disabled(!player.hasTrack)
    }

    private func transportButton(_ symbol: String, label: LocalizedStringKey, size: CGFloat, font: Font = .body,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(font)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size, height: size)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Shuffle or repeat: quieter than the transport until on, then in the
    /// accent. A station chooses its own order, so there they rest, dimmed.
    private func modeButton(symbol: String, isOn: Bool, label: String, onStation: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .foregroundStyle(isOn && !onStation ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 32, height: 32)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(onStation)
        .help(onStation ? "The station chooses the order" : label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var repeatLabel: String {
        switch player.repeatMode {
        case .off: String(localized: "Repeat")
        case .all: String(localized: "Repeat All")
        case .one: String(localized: "Repeat One")
        }
    }

    // MARK: The tools

    /// Lyrics and Up Next, which open the panel (PanelState), then AirPlay
    /// and the volume.
    private var tools: some View {
        HStack(spacing: Theme.Space.s) {
            // Only where there are lyrics to be had (the server's, or
            // LRCLIB's when Settings allow it), as on the iPhone.
            if app.can(.lyrics) || settings.findLyricsOnline {
                panelButton(.lyrics, symbol: "quote.bubble", label: "Lyrics", id: "bar.lyrics")
            }
            panelButton(.upNext, symbol: "list.bullet", label: "Up Next", id: "bar.upNext")
            RoutePicker(followsAppearance: true)
                .frame(width: 32, height: 32)
                .padding(.leading, Theme.Space.l)
            HStack(spacing: Theme.Space.s) {
                Image(systemName: player.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VolumeControl(followsAppearance: true)
                    .frame(width: 96, height: 32)
            }
        }
    }

    /// One of the panel's buttons: lit while the panel shows its content,
    /// as a pressed toggle on Linux (the glyph in the accent on a faint fill
    /// of it); pressed then, it closes the panel.
    private func panelButton(_ content: PanelState.Content, symbol: String, label: LocalizedStringKey,
                             id: String) -> some View {
        let isLit = panel.isShown && panel.content == content
        return Button {
            panel.toggle(content)
        } label: {
            Image(systemName: symbol)
                .foregroundStyle(isLit ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                .frame(width: 32, height: 32)
                .background(isLit ? Theme.accent.opacity(0.15) : Color.clear, in: .rect(cornerRadius: Theme.Space.s))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityIdentifier(id)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isLit ? .isSelected : [])
    }
}

/// Where the song is: the time heard, a Slider, the song's length. Apart
/// from the bar, as the clock ticks twice a second and the rest of the bar
/// changes only with the song. A drag seeks once, when it lets go.
private struct PlayerBarPosition: View {
    @Environment(AudioPlayer.self) private var player
    /// Where the hand holds it, while it does.
    @State private var held: TimeInterval?
    @State private var isEditing = false

    var body: some View {
        let duration = player.duration
        let shown = held ?? min(player.elapsed, duration)
        HStack(spacing: Theme.Space.s) {
            Text(duration > 0 ? shown.clock : "--:--")
                .frame(width: 40, alignment: .trailing)
            Slider(value: Binding(get: { shown }, set: { value in
                held = value
                // A step without a hand on it (the keys, VoiceOver) seeks at once.
                if !isEditing {
                    player.seek(to: value)
                    held = nil
                }
            }), in: 0...max(1, duration), onEditingChanged: { editing in
                isEditing = editing
                guard !editing else { return }
                if let held { player.seek(to: held) }
                held = nil
            })
            .controlSize(.small)
            .disabled(duration <= 0)
            .accessibilityLabel("Position")
            .accessibilityValue(duration > 0 ? String(localized: "\(shown.clock) of \(duration.clock)") : "")
            Text(duration > 0 ? duration.clock : "--:--")
                .frame(width: 40, alignment: .leading)
        }
        .font(.footnote)
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }
}
