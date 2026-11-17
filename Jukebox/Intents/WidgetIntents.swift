// The widget's two buttons: Your Station, and one of Home's mixes. Their
// own intents rather than Play Your Station's (MusicIntents.swift): what a
// widget starts counts `from: widget`, not `siri` (docs/STATS.md), and a mix
// is no MusicEntity. Hidden from Shortcuts and Siri: they are the widget's.
//
// In the app and in the widget both (project.yml): a widget's Button needs
// the intent's type, and an audio intent is performed in the app's own
// process, which launches in the background for it as it does for Siri. So
// the widget's copy never performs; WIDGET_EXTENSION (the widget's build
// settings) leaves the app's world out of it.

import AppIntents

nonisolated struct PlayYourStationFromWidget: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play Your Station"
    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await Self.run()
        #endif
        return .result()
    }

    #if !WIDGET_EXTENSION
    @MainActor private static func run() async {
        // Signed out the widget says so itself; nothing to answer here.
        guard let app = await Voice.ready() else { return }
        _ = await Voice.start(app.radio.station(for: .personal), app: app, from: "widget")
    }
    #endif
}

nonisolated struct PlayMixFromWidget: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play Mix"
    static let isDiscoverable = false

    @Parameter(title: "Mix")
    var mixID: String

    init() {}

    init(mixID: String) {
        self.mixID = mixID
    }

    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await Self.run(mixID)
        #endif
        return .result()
    }

    #if !WIDGET_EXTENSION
    @MainActor private static func run(_ id: String) async {
        guard let app = await Voice.ready() else { return }
        // Ready means the library is in; the mixes are made after it. A mix's
        // id is its kind, key and day, so the morning after, before the app
        // has run, yesterday's mix is today's of the same kind.
        for _ in 0..<80 {
            let mixes = app.mixes.mixes
            let mix = mixes.first { $0.id == id } ?? mixes.first { id.hasPrefix($0.kind.rawValue + "-") }
            if let mix, !app.mixes.isBuilding {
                // Counted as the widget's (Stats, play_started `from`).
                Stats.nextFrom = "widget"
                app.player.playMix(mix)
                return
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
    #endif
}
