// The usage counts' parts that need AVFoundation or SwiftUI: why a song
// could not be played, and counting a screen once. Stats.swift itself is
// Foundation only, and Linux compiles it too (Package.swift); Linux's own
// of these are in Linux/App/Platform.swift.

import AVFoundation
import Foundation
import SwiftUI

extension Stats {
    /// Why a song could not be played, from the error AVFoundation gave:
    /// the network (a URL error, or one under it), the server (its setup,
    /// or not letting this client have the song), a file it cannot read.
    static func playbackFailure(_ error: Error?) -> String {
        guard let error else { return "other" }
        let failure = error as NSError
        let underlying = failure.userInfo[NSUnderlyingErrorKey] as? NSError
        if failure.domain == NSURLErrorDomain || underlying?.domain == NSURLErrorDomain { return "network" }
        guard failure.domain == AVFoundationErrorDomain else { return "other" }
        switch AVError.Code(rawValue: failure.code) {
        case .fileFormatNotRecognized?, .fileFailedToParse?, .decoderNotFound?, .decodeFailed?:
            return "unsupported"
        case .serverIncorrectlyConfigured?, .contentIsNotAuthorized?:
            return "server"
        default:
            return "other"
        }
    }
}

extension View {
    /// `action` once for as long as this view lives: a page pushed, a sheet
    /// or a cover opened, a panel shown. Not again when it shows again after
    /// what covered it has gone, as `onAppear` alone would: then Back would
    /// count as another visit.
    func countsOnce(_ action: @escaping () -> Void) -> some View {
        modifier(StatsOnce(action: action))
    }

    /// The `screen` event for this view, once for as long as it lives.
    /// `name` is a kind of screen from docs/STATS.md, never what it shows.
    func countsScreen(_ name: String) -> some View {
        countsOnce { Stats.track(.screen, ["name": name]) }
    }
}

private struct StatsOnce: ViewModifier {
    let action: () -> Void
    @State private var isCounted = false

    func body(content: Content) -> some View {
        content.onAppear {
            guard !isCounted else { return }
            isCounted = true
            action()
        }
    }
}
