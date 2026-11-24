// The playing cover's accent as the whole app's (AccentTokens): kept in one
// place, PlayingAccent, which Theme.accent, onAccent and quietInk read, so
// every view that draws the accent — the bar's progress and heart, the
// panel's tabs and playing row, a page's Play and quiet squares, the links,
// the places, the system's controls by the tint — follows the song without
// knowing of it. "ik wil het wel even zien dat het overal is doorgevoerd,
// zolang de gekozen kleur voldoet aan wcag contrast" (the photographer, 24
// November 2026). Nothing playing: Copper and Glow.

import JukeboxKit
import Observation
import SwiftUI

/// The accent of what plays, by day and by night.
@Observable
final class PlayingAccent {
    static let shared = PlayingAccent()

    var tokens = AccentTokens.brand

    /// The accent by night, which the mini player's block always is (dark
    /// by day too): Glow while nothing plays.
    var night: AccentColor { AccentColor(hex: tokens.accent.dark) }
}

/// The tint of a window, and what keeps PlayingAccent on the cover that
/// plays. In a modifier's body, not the scene's, so it is drawn again when
/// the accent changes.
struct PlayingTint: ViewModifier {
    @Environment(AudioPlayer.self) private var player
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .tint(Theme.accent)
            .task(id: coverURL) {
                // The cover's accent, once per cover (ImagePipeline keeps
                // it): the one Now Playing takes, at the same 120 pixels.
                var found: AccentColor?
                if let url = coverURL {
                    found = await ImagePipeline.shared.accent(for: url)
                    guard !Task.isCancelled else { return }
                }
                let tokens = coverURL == nil ? AccentTokens.brand : AccentTokens(cover: found)
                guard tokens != PlayingAccent.shared.tokens else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: Tokens.Motion.scene)) {
                    PlayingAccent.shared.tokens = tokens
                }
            }
    }

    /// The playing song's cover, small; nil while nothing plays.
    private var coverURL: URL? {
        guard let artwork = player.currentTrack?.artwork, let server = app.server else { return nil }
        return server.artworkURL(artwork, maxPixelSize: 120)
    }
}
