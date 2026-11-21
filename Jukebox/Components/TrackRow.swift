// A track in any list — an album's (its number), a playlist's or Songs'
// (its cover), Up Next (with why the radio chose it) — and the menu every
// track has, in a long press and behind its "…". A song on the phone has
// Music's small arrow after its title; offline, a song that is not on the
// phone is dimmed, as it cannot play (OfflineStore), and a tap on it says why.
// In a wide window (the iPad's, the Mac's) it is Linux's row (spec §3, §5):
// the length at its end, the song playing in the accent, its menu a
// right-click or a long press.

import JukeboxKit
import SwiftUI

struct TrackRow: View {
    enum Leading {
        case artwork
        case number(Int?)
        case none
    }

    let track: Track
    var leading: Leading = .artwork
    /// The second line; nil leaves it out (an album's own rows).
    var subtitle: String?
    var reason: PickReason?
    var showsMenu = true
    /// A playlist's own song in a wide window: Remove in its menu, where
    /// the iPhone swipes it away.
    var removal: (() -> Void)?
    /// Move Up and Move Down in its menu, where the playlist can be
    /// reordered (TrackMenu).
    var moveUp: (() -> Void)?
    var moveDown: (() -> Void)?

    @Environment(AudioPlayer.self) private var player
    @Environment(LibraryStore.self) private var library
    @Environment(AppModel.self) private var app
    @Environment(OfflineStore.self) private var offline
    @Environment(\.isWide) private var isWide
    /// The songs picked with this one in a wide list (TrackPicks), empty
    /// when it is not picked.
    @Environment(\.pickedTracks) private var pickedTracks
    @State private var isHovered = false

    init(_ track: Track, leading: Leading = .artwork, subtitle: String? = nil, reason: PickReason? = nil,
         showsMenu: Bool = true, removal: (() -> Void)? = nil,
         moveUp: (() -> Void)? = nil, moveDown: (() -> Void)? = nil) {
        self.track = track
        self.leading = leading
        self.subtitle = subtitle
        self.reason = reason
        self.showsMenu = showsMenu
        self.removal = removal
        self.moveUp = moveUp
        self.moveDown = moveDown
    }

    /// Why the radio chose it, in the kit's words but for the server's
    /// mix, which is the server's own: Jellyfin's, or Navidrome's.
    private func reasonText(_ reason: PickReason) -> String {
        if case .instantMix = reason {
            return String(localized: "From \(library.serverKind)’s mix")
        }
        return reason.text
    }

    /// Artwork, title, artist: the usual row.
    static func standard(_ track: Track) -> TrackRow {
        TrackRow(track, subtitle: track.artistLine)
    }

    /// The artist (or a guest) or the radio's reason under the title.
    private var hasSecondLine: Bool {
        !(subtitle ?? "").isEmpty || reason != nil
    }

    var body: some View {
        if isWide {
            wide
        } else {
            compact
        }
    }

    private var compact: some View {
        let onPhone = offline.has(track.id)
        let playable = onPhone || !offline.isOffline
        return HStack(spacing: Theme.Space.m) {
            switch leading {
            case .artwork:
                ArtworkView(track.artwork, size: 48, cornerRadius: Theme.Radius.artwork, sleeve: TitleSleeve.Words(track: track))
                    .opacity(playable ? 1 : 0.5)
            case let .number(number):
                Group {
                    if isCurrent {
                        Image(systemName: "waveform")
                            .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
                            .foregroundStyle(Theme.accent)
                            .accessibilityLabel("Playing")
                    } else {
                        Text(number.map(String.init) ?? "")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minWidth: 24, alignment: .center)
            case .none:
                EmptyView()
            }

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                HStack(spacing: 4) {
                    Text(track.name)
                        .lineLimit(1)
                        .foregroundStyle(playable ? HierarchicalShapeStyle.primary : HierarchicalShapeStyle.secondary)
                    if library.isFavorite(track.id) {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Favorite")
                    }
                    if onPhone {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Downloaded")
                    }
                }
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(playable ? HierarchicalShapeStyle.secondary : HierarchicalShapeStyle.tertiary)
                        .lineLimit(1)
                }
                if let reason {
                    Text(reasonText(reason))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)

            if isCurrent && showsArtwork {
                Image(systemName: "waveform")
                    .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
                    .foregroundStyle(Theme.accent)
                    .accessibilityLabel("Playing")
            }
            if showsMenu {
                Menu {
                    TrackMenu(track: track)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        // At least, not at most: the glyph grows with Larger Text.
                        .frame(minWidth: 32, minHeight: 44)
                        .contentShape(.rect)
                }
                .accessibilityLabel("More")
            }
        }
        // Its own height, the list's insets none (`trackListRow`): 4 above
        // and under what it holds, and 52 at the least for one line, 60 for
        // two (Tokens.Row); taller with the radio's reason or Larger Text.
        .padding(.vertical, Theme.Space.xs)
        .frame(minHeight: hasSecondLine ? Tokens.Row.twoLines : Tokens.Row.oneLine)
        .contentShape(.rect)
        .contextMenu {
            TrackMenu(track: track)
        } preview: {
            // Passed in explicitly: the preview is drawn in a hosting
            // controller of its own, and its cover (ArtworkView) needs the
            // AppModel's client. Were the environment not carried into it,
            // every long press on a song would crash.
            TrackPreview(track: track)
                .environment(app)
        }
    }

    /// Linux's row: numbered (an album's page, whose cover is the page's
    /// own), the number in a column of 32, 16, the title with a guest after
    /// it, 48 tall; else the cover 48, 12, the title over the artist, 64 tall
    /// (72 with the radio's reason). The length at the end, 13 tabular. The
    /// song playing: its title in the accent and, numbered, the bars for its
    /// number. No "…": the menu is a right-click, as on Linux, or a long press.
    private var wide: some View {
        let onPhone = offline.has(track.id)
        let playable = onPhone || !offline.isOffline
        let words = subtitle.flatMap { $0.isEmpty ? nil : $0 }
        return HStack(spacing: showsArtwork ? Theme.Space.m : Theme.Space.l) {
            switch leading {
            case .artwork:
                ArtworkView(track.artwork, size: 48, cornerRadius: Theme.Radius.artwork, sleeve: TitleSleeve.Words(track: track))
                    .opacity(playable ? 1 : 0.5)
            case let .number(number):
                Group {
                    if isCurrent {
                        Image(systemName: "waveform")
                            .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
                            .foregroundStyle(Theme.accent)
                            .accessibilityLabel("Playing")
                    } else {
                        Text(number.map(String.init) ?? "")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .desktopFont(Tokens.Size.body15.size)
                .frame(width: 32, alignment: .trailing)
            case .none:
                EmptyView()
            }

            if showsArtwork {
                VStack(alignment: .leading, spacing: 0) {
                    wideTitle(playable: playable)
                    if let words {
                        Text(words)
                            .desktopFont(Tokens.Size.fact13.size)
                            .foregroundStyle(playable ? HierarchicalShapeStyle.secondary : HierarchicalShapeStyle.tertiary)
                            .lineLimit(1)
                    }
                    if let reason {
                        // Linux's faint, 40 %.
                        Text(reasonText(reason))
                            .desktopFont(Tokens.Size.fact13.size)
                            .foregroundStyle(Color.primary.opacity(0.4))
                            .lineLimit(1)
                    }
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                    wideTitle(playable: playable)
                        .layoutPriority(1)
                    if let words {
                        Text(words)
                            .desktopFont(Tokens.Size.fact13.size)
                            .foregroundStyle(playable ? HierarchicalShapeStyle.secondary : HierarchicalShapeStyle.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)

            Text(track.duration.clock)
                .monospacedDigit()
                .desktopFont(Tokens.Size.fact13.size)
                .foregroundStyle(.secondary)
        }
        .frame(minHeight: showsArtwork ? (reason == nil ? Tokens.Row.wideCovered : Tokens.Row.wideReason) : Tokens.Row.wideNumbered)
        .contentShape(.rect)
        // The pointer over it: the whole row lit, 8 past its ends.
        .background {
            RoundedRectangle(cornerRadius: Theme.Space.s)
                // Picked: a little more, as a selected row is; never the
                // accent, which means on air.
                .fill(Color.primary.opacity(!pickedTracks.isEmpty ? 0.1 : isHovered ? 0.07 : 0))
                .padding(.horizontal, -Theme.Space.s)
        }
        .onHover { isHovered = $0 }
        .contextMenu {
            TrackMenu(track: track, removal: removal, picked: pickedTracks, moveUp: moveUp, moveDown: moveDown)
        } preview: {
            // As the iPhone's: the preview's hosting controller needs the
            // AppModel carried into it.
            TrackPreview(track: track)
                .environment(app)
        }
    }

    /// The title in 15, the playing song's in the accent. Nothing after
    /// it, as Linux's row: no heart, no arrow (the iPhone's are Music's).
    private func wideTitle(playable: Bool) -> some View {
        Text(track.name)
            .lineLimit(1)
            .foregroundStyle(isCurrent ? AnyShapeStyle(Theme.accent)
                             : playable ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .desktopFont(Tokens.Size.body15.size)
    }

    private var isCurrent: Bool { player.currentTrack?.id == track.id }

    private var showsArtwork: Bool {
        if case .artwork = leading { return true }
        return false
    }
}

/// The long press's preview: the cover, the title, the artist.
private struct TrackPreview: View {
    let track: Track

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            ArtworkView(track.artwork, size: 240, sleeve: TitleSleeve.Words(track: track))
            Text(track.name).font(.headline).lineLimit(2)
            Text(track.artistLine).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(Theme.Space.l)
        .frame(width: 272)
    }
}

/// Rating › None and one to five stars, the given one ticked: beside
/// Favorite in a song's and an album's menu, and only there, on a server
/// that keeps ratings. The photographer: "ik wil alleen er voor waken dat
/// we niet 10000 knopen krijgen" (17 November 2026), so no stars in rows
/// or bars.
struct RatingMenu: View {
    let item: ItemRef

    @Environment(LibraryStore.self) private var library

    var body: some View {
        Menu("Rating", systemImage: "star") {
            Picker("Rating", selection: Binding(get: { library.rating(item) ?? 0 },
                                                set: { stars in Task { await library.setRating(stars, item: item) } })) {
                Text("None").tag(0)
                ForEach(1...5, id: \.self) { stars in
                    Text(verbatim: String(repeating: "★", count: stars))
                        .accessibilityLabel(Text("\(stars) stars"))
                        .tag(stars)
                }
            }
            .pickerStyle(.inline)
        }
    }
}

/// Credits › who made the song, a section a role ("Composer", "Performers"),
/// where the server gave any (Navidrome's contributors, Jellyfin's
/// composer): the sleeve's back, quietly, in the song's menu and not as a
/// button of its own. One opens the artist's page when the library has
/// them. The words are LibraryIndex's, Linux's too.
struct CreditsMenu: View {
    let track: Track

    @Environment(LibraryStore.self) private var library
    @Environment(Navigator.self) private var navigator

    var body: some View {
        // The library's copy: Jellyfin's composers are read with the
        // library, not with a playlist's or the queue's songs.
        let groups = LibraryIndex.creditGroups(library.track(id: track.id) ?? track)
        if !groups.isEmpty {
            Menu("Credits", systemImage: "person.2") {
                ForEach(groups.indices, id: \.self) { i in
                    let group = groups[i]
                    Section(group.role) {
                        ForEach(group.credits, id: \.self) { credit in
                            let artist = library.artist(credit.artist)
                            Button(LibraryIndex.creditName(credit)) {
                                if let artist { navigator.open(.artist(artist)) }
                            }
                            .disabled(artist == nil)
                        }
                    }
                }
            }
        }
    }
}

/// What can be done with a track, in the groups Linux's menus have
/// (trackMenu, "en ook bij linux die menutjes ff mooier structureren", 20
/// November 2026): what its list does with it first (Remove from
/// Playlist; the queue's own section, QueueView), then playing it, keeping
/// it, where it is from, and last what is used least.
struct TrackMenu: View {
    let track: Track
    /// A playlist's own song, on a wide page: Remove from Playlist.
    var removal: (() -> Void)?
    /// Two or more picked with it (TrackPicks): the menu is theirs.
    var picked: [Track] = []
    /// A playlist of one's own the server can reorder, on a wide page:
    /// Move Up and Move Down, nil at its ends, as Linux's row has them.
    var moveUp: (() -> Void)?
    var moveDown: (() -> Void)?
    /// The song playing (the bar's, Full Player's): on a station, the
    /// station's lessons first, as Linux's songMenu.
    var isPlaying = false

    @Environment(AudioPlayer.self) private var player
    @Environment(RadioController.self) private var radio
    @Environment(LibraryStore.self) private var library
    @Environment(Navigator.self) private var navigator

    var body: some View {
        if picked.count > 1 {
            // No heading: the same sections as one song's, what the list
            // does with them (none yet: Remove is one entry's) and then
            // playing and keeping them.
            Section {
                Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                    player.playNext(picked)
                }
                Button("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward") {
                    player.addToQueue(picked)
                }
            }
            Section {
                Button("Add to Playlist…", systemImage: "text.badge.plus") {
                    navigator.addToPlaylist = AddToPlaylistRequest(tracks: picked)
                }
            }
        } else {
            single
        }
    }

    @ViewBuilder private var single: some View {
        if isPlaying, player.context?.isRadio == true {
            // Thumbs up teaches the station; Dislike (the queue's word,
            // QueueView) skips the song and keeps it, and songs like it, off.
            let liked = radio.liked.contains(track.id)
            let disliked = radio.disliked.contains(track.id)
            Section {
                Button(liked ? "Liked" : "More Like This", systemImage: liked ? "hand.thumbsup.fill" : "hand.thumbsup") {
                    radio.like(track)
                }
                Button(disliked ? "Undo Dislike" : "Dislike", systemImage: disliked ? "hand.thumbsdown.fill" : "hand.thumbsdown") {
                    radio.dislike(track)
                }
            }
        }
        if moveUp != nil || moveDown != nil || removal != nil {
            Section {
                if let moveUp {
                    Button("Move Up", systemImage: "arrow.up", action: moveUp)
                }
                if let moveDown {
                    Button("Move Down", systemImage: "arrow.down", action: moveDown)
                }
                if let removal {
                    Button("Remove from Playlist", systemImage: "minus.circle", role: .destructive) {
                        removal()
                    }
                }
            }
        }
        Section {
            Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                player.playNext([track])
            }
            Button("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward") {
                player.addToQueue([track])
            }
        }
        Section {
            Button("Add to Playlist…", systemImage: "text.badge.plus") {
                navigator.addToPlaylist = AddToPlaylistRequest(tracks: [track])
            }
            let favorite = library.isFavorite(track.id)
            Button(favorite ? "Undo Favorite" : "Favorite", systemImage: favorite ? "heart.slash" : "heart") {
                Task { await library.toggleFavorite(.track(track.id)) }
            }
            if library.can(.rating) {
                RatingMenu(item: .track(track.id))
            }
            Button("Start Radio", systemImage: "dot.radiowaves.left.and.right") {
                Stats.track(.stationStarted, ["seed": "track", "from": "menu"])
                radio.start(.track(track.id))
            }
        }
        Section {
            if let albumID = track.albumID, let album = library.album(id: albumID) {
                Button("Go to Album", systemImage: "square.stack") {
                    navigator.open(.album(album))
                }
            }
            if let ref = track.primaryArtist, let artist = library.artist(ref) {
                Button("Go to Artist", systemImage: "music.mic") {
                    navigator.open(.artist(artist))
                }
            }
            CreditsMenu(track: track)
        }
        Section {
            CopyShareLinkButton(id: track.id, tracks: [track.id])
            ShareMenuItem(item: .track(track))
            DontCountToggle(kind: .song, id: track.id, name: track.name)
        }
    }
}

extension View {
    /// A song's row in an iPhone's list: on the margin, with none of the
    /// list's own insets above and under it, so the row's own height
    /// (Tokens.Row, TrackRow) is the row's. The system's insets put some
    /// 15 above and under the "…"'s 44: rows of 75 (21 November 2026).
    /// On the row itself (the Button round a TrackRow), where the list
    /// reads it; `compact` false leaves a wide page's rows to `pageRow`.
    @ViewBuilder
    func trackListRow(_ compact: Bool = true) -> some View {
        if compact {
            listRowInsets(EdgeInsets(top: 0, leading: Theme.margin, bottom: 0, trailing: Theme.margin))
        } else {
            self
        }
    }
}
