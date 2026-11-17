// The widget's side of the app: WidgetSnapshot written into the App
// Group's folder whenever what the widget shows changes (signed in or out,
// Your Station on the air or not, Home's first mixes), each mix's cover as a
// small JPEG beside it, and the widget's timeline reloaded. Nothing else:
// the widget has no screen in the app.
//
// Started in JukeboxApp.init, which runs on every launch, also one in the
// background for a widget's button, CarPlay or Siri: what they start lights
// the widget too.
//
// The iPhone's and the iPad's: the Mac has no widget (docs/ARCHITECTURE.md,
// The widget).

#if os(iOS)
import JukeboxKit
import UIKit
import WidgetKit

enum WidgetDoors {
    /// What was last written: a reload only when the widget would change,
    /// as WidgetKit gives an app a daily budget of them.
    private static var written: WidgetSnapshot?
    /// Writes one after another: a cover still loading is not overtaken.
    private static var writing: Task<Void, Never>?

    /// Follows the stores, as CarPlay's lists do: `withObservationTracking`
    /// reads what the widget shows and is armed again on every change.
    static func follow(_ app: AppModel) {
        let now = withObservationTracking {
            snapshot(of: app)
        } onChange: {
            Task { @MainActor in follow(app) }
        }
        guard let now, now != written else { return }
        written = now
        let previous = writing
        writing = Task {
            await previous?.value
            await write(now, app: app)
        }
    }

    /// Nil while launching: the keychain has not said yet.
    private static func snapshot(of app: AppModel) -> WidgetSnapshot? {
        switch app.phase {
        case .launching:
            return nil
        case .signedOut:
            return WidgetSnapshot(signedIn: false, onAir: false, mixes: [])
        case .signedIn:
            // Light means on air (tells.md, 1): while it plays, not while
            // it waits paused, when the widget's Play is wanted again.
            var onAir = false
            if case .personal? = app.radio.stationOnAir(player: app.player)?.seed {
                onAir = app.player.isPlaying
            }
            let mixes = app.mixes.mixes.prefix(3).map { WidgetSnapshot.Mix(id: $0.id, title: $0.title) }
            return WidgetSnapshot(signedIn: true, onAir: onAir, mixes: mixes)
        }
    }

    private static func write(_ snapshot: WidgetSnapshot, app: AppModel) async {
        guard let folder = WidgetSnapshot.folder else { return }
        let files = FileManager.default
        try? files.createDirectory(at: folder, withIntermediateDirectories: true)
        // Yesterday's covers, and every one after a sign-out, go.
        let wanted = Set(snapshot.mixes.map { WidgetSnapshot.cover(of: $0.id) })
        for name in (try? files.contentsOfDirectory(atPath: folder.path)) ?? []
        where name.hasSuffix(".jpg") && !wanted.contains(name) {
            try? files.removeItem(at: folder.appendingPathComponent(name))
        }
        for mix in snapshot.mixes {
            let file = folder.appendingPathComponent(WidgetSnapshot.cover(of: mix.id))
            // A mix's id is its day's: its cover does not change that day.
            guard !files.fileExists(atPath: file.path),
                  let artwork = app.mixes.mixes.first(where: { $0.id == mix.id })?.artwork.first,
                  // 120 pixels, the size a row's thumbnail fetches, so it is
                  // often in the cache; the widget draws it at 40 points.
                  let url = app.server?.artworkURL(artwork, maxPixelSize: 120),
                  let image = await ImagePipeline.shared.image(for: url),
                  let jpeg = image.jpegData(compressionQuality: 0.8) else { continue }
            try? jpeg.write(to: file, options: .atomic)
        }
        guard let json = try? JSONEncoder().encode(snapshot) else { return }
        try? json.write(to: folder.appendingPathComponent(WidgetSnapshot.file), options: .atomic)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
#endif
