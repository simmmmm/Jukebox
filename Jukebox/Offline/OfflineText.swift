// The few words offline says, short enough for the mini player's one line,
// and a list's question before a tapped song plays: is it on the phone?

import JukeboxKit
import UIKit

extension AudioPlayer {
    /// A song tapped in a list: offline, one that is not on the phone says
    /// so, briefly, and does not play (true). The player's own rule would
    /// start an album's first song on the phone for its first row, as it
    /// does for Play.
    func refusesOffline(_ track: Track) -> Bool {
        guard let offline, offline.isOffline, !offline.has(track.id) else { return false }
        showError(OfflineText.notOnPhone(track))
        return true
    }
}

/// What offline says. First why ("You’re offline."), so the mini player's
/// one line says it even when the rest is cut off.
enum OfflineText {
    static var device: String { UIDevice.current.model }

    static func notOnPhone(_ track: Track) -> String {
        String(localized: "You’re offline. “\(track.name)” isn’t on this \(device).")
    }

    static var noneOnPhone: String {
        String(localized: "You’re offline. None of these songs are on this \(device).")
    }

    static var nothingFurther: String {
        String(localized: "You’re offline. Nothing further in the queue is on this \(device).")
    }

    static func nothingForStation(_ title: String) -> String {
        String(localized: "You’re offline. No songs on this \(device) for \(title).")
    }

    static func waiting(_ wait: OfflineWait) -> String {
        switch wait {
        case .wifi: return String(localized: "Waiting for Wi-Fi")
        case .network: return String(localized: "Waiting for a connection")
        case .notAllowed: return String(localized: "Downloads are off on your server")
        }
    }

    static func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)))
    }
}
