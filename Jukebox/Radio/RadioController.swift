// CONTRACT — signatures fixed; bodies the player agent's (docs/ARCHITECTURE.md).
//
// The radio in the app: one RadioSession (JukeboxKit) for the station that
// plays, fed into the player a few tracks ahead. A station starts within a
// moment from the library alone; Jellyfin's Instant Mix and, with a key,
// Last.fm's similar tracks join it as they arrive. Feedback — a skip, a
// thumbs up or down, a track heard to the end — goes to the session, and
// after a skip or a thumbs the tracks ahead are chosen again.

import Foundation
import JukeboxKit
import Observation

@Observable
final class RadioController {
    /// The station playing, if one is.
    private(set) var station: Station?
    /// Starting: the first tracks are being chosen.
    private(set) var isStarting = false
    /// The graph from the library and Last.fm, as far as it is known.
    private(set) var graph = SimilarityGraph()
    /// Liked and disliked in this session, for the thumbs' state.
    private(set) var liked: Set<ItemID> = []
    private(set) var disliked: Set<ItemID> = []

    var client: JellyfinClient?

    init(player: AudioPlayer, library: LibraryStore, history: HistoryStore, settings: AppSettings) {
        fatalError("not built yet")
    }

    /// After sign-in: the graph from the library, then Last.fm in the
    /// background when there is a key.
    func prepare() { fatalError("not built yet") }

    func start(_ seed: StationSeed) { fatalError("not built yet") }
    func start(_ station: Station) { fatalError("not built yet") }
    func stop() { fatalError("not built yet") }

    /// The player is this many tracks from the end of a station's queue.
    func playerNeedsMore() { fatalError("not built yet") }

    /// From the player, for every track of a station that ended: heard to
    /// the end, or left after `listened` seconds.
    func trackEnded(_ track: Track, listened: TimeInterval) { fatalError("not built yet") }

    func like(_ track: Track) { fatalError("not built yet") }
    /// Thumbs down: skip it if it plays, and less like it from here.
    func dislike(_ track: Track) { fatalError("not built yet") }

    /// The dial moved: the tracks ahead are chosen again.
    func adventurousnessChanged() { fatalError("not built yet") }

    /// Settings changed the Last.fm key.
    func lastFMKeyChanged() { fatalError("not built yet") }

    /// The station seed for a track, artist, album …, named and with
    /// artwork, for "Start Radio" buttons.
    func station(for seed: StationSeed) -> Station { fatalError("not built yet") }
}
