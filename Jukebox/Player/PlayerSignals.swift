// AVFoundation calls back on its own threads: KVO on whichever thread
// changed the property, a seek's completion wherever it finishes. The
// closures that receive those calls are made here, in nonisolated functions,
// so none of them is taken to be on the main actor (the app's default) and
// trapped for it; each handler the player passes hops to the main actor
// itself. Handlers take no arguments: the player reads what changed from the
// engine once it is on the main actor, so nothing that is not Sendable has
// to cross.

import AVFoundation
import Foundation

enum PlayerSignals {
    /// The queue player moved on to another item (gapless, by itself).
    nonisolated static func observeCurrentItem(of player: AVQueuePlayer,
                                               _ handler: @escaping @Sendable () -> Void) -> NSKeyValueObservation {
        player.observe(\.currentItem, options: [.new]) { _, _ in handler() }
    }

    /// Playing, paused or waiting for the network.
    nonisolated static func observeTimeControlStatus(of player: AVQueuePlayer,
                                                     _ handler: @escaping @Sendable () -> Void) -> NSKeyValueObservation {
        player.observe(\.timeControlStatus, options: [.initial, .new]) { _, _ in handler() }
    }

    /// An item became ready, or failed.
    nonisolated static func observeStatus(of item: AVPlayerItem,
                                          _ handler: @escaping @Sendable () -> Void) -> NSKeyValueObservation {
        item.observe(\.status, options: [.new]) { _, _ in handler() }
    }

    /// Every `interval` seconds while time moves, on the main queue.
    nonisolated static func every(_ interval: TimeInterval, on player: AVPlayer,
                                  _ handler: @escaping @Sendable () -> Void) -> Any {
        player.addPeriodicTimeObserver(forInterval: CMTime(seconds: interval, preferredTimescale: 600),
                                       queue: .main) { _ in handler() }
    }

    /// An exact seek (a scrubbed position should be where the finger let
    /// go), `done` when it has landed or was overtaken by another.
    nonisolated static func seek(_ player: AVPlayer, to seconds: TimeInterval,
                                 _ done: @escaping @Sendable () -> Void) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero) { _ in done() }
    }
}
