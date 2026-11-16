// Up next as the panel shows it, on every platform: where the music comes
// from at the top (an album, a playlist or a mix with its cover, or the
// station), then the song playing and the ones to come, in the order they
// play. Songs queued from elsewhere come after "Then"; the foot counts what
// is left. Foundation only: Linux's panel (Linux/App/Panel.swift) and the
// iPad's and the Mac's draw these rows, each in its own controls, from the
// one queue both players are (PlayQueue). Values in, not a player.

import Foundation
import JukeboxKit

enum UpNextList {
    /// The top of the panel.
    enum Head: Equatable {
        /// The template mark, the station's name and the dial: the radio
        /// chooses the order, so no shuffle or repeat.
        case station(Station)
        /// An album, a playlist, a mix: its cover (a mix's collage of
        /// covers when it has one), its title and the line under it.
        case collection(title: String, line: String, cover: Artwork?, collage: [Artwork]?)
    }

    /// One row of the list.
    enum Item {
        /// `words`: on an album the song's guests after the title; otherwise
        /// the artist, under it.
        case song(QueueEntry, number: Int?, style: Style, playing: Bool, words: String)
        /// "Then": what plays after the album or playlist.
        case then
        case note(String)
        case foot(String)
    }

    /// Numbered rows for an album or playlist; rows with their cover for
    /// songs queued from elsewhere; rows with the radio's reason on a
    /// station, here and nowhere else (tells.md 5).
    enum Style { case numbered, covered, station }

    /// Nothing when nothing plays. `playing` stands in for a cover the
    /// library does not know.
    static func head(_ context: QueueContext?, playing: Track?, library: LibraryStore, mixes: MixStore) -> Head? {
        guard let context else { return nil }
        if let station = context.station { return .station(station) }
        var line = ""
        var cover = playing?.artwork
        var collage: [Artwork]?
        switch context.kind {
        case let .album(id):
            let album = library.album(id: id)
            line = album?.artistLine ?? ""
            cover = album?.artwork ?? cover
        case let .playlist(id):
            cover = library.playlists.first(where: { $0.id == id })?.artwork ?? cover
        case let .mix(id):
            if let mix = mixes.mixes.first(where: { $0.id == id }) {
                line = mix.subtitle
                collage = mix.artwork
            }
        default:
            break
        }
        return .collection(title: context.title, line: line, cover: cover, collage: collage)
    }

    /// The rows, in the order they play. `currentIndex` numbers them by
    /// place in the queue, as the album's own numbers when it was played
    /// from its start; `added` are the songs queued from elsewhere.
    static func items(current: QueueEntry?, upNext: [QueueEntry], context: QueueContext?, currentIndex: Int?,
                      added: Set<UUID>, autoplay: Bool, repeatMode: RepeatMode) -> [Item] {
        guard let current else { return [] }
        if context?.isRadio == true {
            return [.song(current, number: nil, style: .station, playing: true, words: current.track.artistLine)]
                + upNext.map { .song($0, number: nil, style: .station, playing: false, words: $0.track.artistLine) }
        }
        // On an album only the artists who are not the album's follow the
        // title; elsewhere the artist does.
        func words(_ track: Track) -> String {
            guard case .album = context?.kind else { return track.artistLine }
            return guests(track)
        }
        let first = (currentIndex ?? 0) + 1
        var items: [Item] = [.song(current, number: first, style: .numbered, playing: true, words: words(current.track))]
        // The songs queued from elsewhere that come after the rest: "Then".
        var split = upNext.count
        while split > 0, added.contains(upNext[split - 1].id) { split -= 1 }
        for (offset, entry) in upNext[..<split].enumerated() {
            items.append(.song(entry, number: first + 1 + offset, style: .numbered, playing: false, words: words(entry.track)))
        }
        // After the last song: Autoplay, as the iPhone says under its queue.
        // Repeat plays the queue again instead.
        let autoplays = autoplay && repeatMode == .off
        if split < upNext.count || autoplays { items.append(.then) }
        for entry in upNext[split...] {
            items.append(.song(entry, number: nil, style: .covered, playing: false, words: entry.track.artistLine))
        }
        if autoplays { items.append(.note("Autoplay plays on with music like the last song")) }
        let minutes = Int((upNext.reduce(0) { $0 + $1.track.duration } / 60).rounded())
        let count = upNext.count == 1 ? "1 song" : "\(upNext.count) songs"
        items.append(.foot(upNext.isEmpty ? "Nothing after this song" : minutes > 0 ? "\(count) · \(minutes) min" : count))
        return items
    }

    /// The artists of a song that are not its album's ("MC Polder" on a
    /// Blue Room Trio album). Names that share one tag ("Blue Room Trio;
    /// MC Polder") count apart. The same rule as Linux's `guests` in
    /// Parts.swift, which its album pages use.
    static func guests(_ track: Track) -> String {
        let own = Set((track.albumArtist?.name ?? "").components(separatedBy: "; "))
        return track.artists.flatMap { $0.name.components(separatedBy: "; ") }.filter { !own.contains($0) }.joined(separator: ", ")
    }
}
