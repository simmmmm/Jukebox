// swift-tools-version: 6.2
// Jukebox for Linux: GTK 4 and libadwaita for the windows, GStreamer for the
// sound, and under them the same Swift as the iPhone's app. The photographer,
// 13 November 2026: "Maak hier ook een linux versie van, misschien toch een
// gedeelde codebase?" — so one codebase where it is not the screen: JukeboxKit
// whole, and `shared` below, the app's own stores (the library, the radio,
// the mixes, the history, the settings, the songs kept on the machine)
// compiled from Jukebox/ as they are.
// Only what draws or plays is written twice, each platform's own way
// (SwiftUI and AVFoundation there, GTK and GStreamer in Linux/App).
//
// The iPhone's app is not built from this file: project.yml is (XcodeGen).
//   dev/linux-build.sh   builds it in Docker;  docs/LINUX.md has the rest.
import PackageDescription

/// The files of Jukebox/ that Linux compiles too. One that gains an
/// `import SwiftUI` or `UIKit` leaves this list, or loses the import.
let shared = [
    "Jukebox/App/Accounts.swift",
    "Jukebox/App/AppSettings.swift",
    "Jukebox/App/PanelState.swift",
    "Jukebox/App/ServerWords.swift",
    "Jukebox/App/Stats.swift",
    "Jukebox/Components/ArtMeasures.swift",
    "Jukebox/Components/DesktopMeasures.swift",
    "Jukebox/Components/RelativeDay.swift",
    "Jukebox/Home/HomeShelves.swift",
    "Jukebox/Home/MixStore.swift",
    "Jukebox/Library/LibraryIndex.swift",
    "Jukebox/Library/LibraryStore.swift",
    "Jukebox/NowPlaying/LyricsFinder.swift",
    "Jukebox/NowPlaying/TurntableMeasures.swift",
    "Jukebox/NowPlaying/UpNextList.swift",
    "Jukebox/Offline/OfflineDisk.swift",
    "Jukebox/Offline/OfflineStore.swift",
    "Jukebox/Offline/OfflineText.swift",
    "Jukebox/Player/HandoffStore.swift",
    "Jukebox/Player/HistoryStore.swift",
    "Jukebox/Player/PlayOn.swift",
    "Jukebox/Player/PlayQueue.swift",
    "Jukebox/Radio/RadioController.swift",
]

let package = Package(
    name: "Jukebox",
    dependencies: [.package(path: "JukeboxKit")],
    targets: [
        .systemLibrary(name: "CAdw", path: "Linux/CAdw", pkgConfig: "libadwaita-1",
                       providers: [.apt(["libadwaita-1-dev"])]),
        .systemLibrary(name: "CGst", path: "Linux/CGst", pkgConfig: "gstreamer-1.0",
                       providers: [.apt(["libgstreamer1.0-dev"])]),
        .systemLibrary(name: "CSecret", path: "Linux/CSecret", pkgConfig: "libsecret-1",
                       providers: [.apt(["libsecret-1-dev"])]),
        .target(name: "CGlue", dependencies: ["CAdw", "CGst", "CSecret"], path: "Linux/CGlue"),
        .executableTarget(
            name: "Jukebox",
            dependencies: ["JukeboxKit", "CAdw", "CGst", "CGlue"],
            path: ".",
            sources: shared + ["Linux/App"],
            // As project.yml has it for the iPhone, so the shared files mean
            // the same on both: Swift 5 mode, the main actor by default.
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("InferSendableFromCaptures"),
                .enableUpcomingFeature("DisableOutwardActorInference"),
                .enableUpcomingFeature("GlobalActorIsolatedTypesUsability"),
            ]
        ),
    ]
)
