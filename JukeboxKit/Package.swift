// swift-tools-version: 6.0
// JukeboxKit: everything Jukebox does that is not drawing or playing sound —
// talking to Jellyfin and Last.fm, the library's index, the radio, the
// mixes on Home. Foundation only, so it builds and is tested on Linux
// (dev/kit-test.sh, against a real Jellyfin in Docker) as well as in the app.
import PackageDescription

let package = Package(
    name: "JukeboxKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "JukeboxKit", targets: ["JukeboxKit"]),
    ],
    targets: [
        .target(name: "JukeboxKit"),
        .testTarget(name: "JukeboxKitTests", dependencies: ["JukeboxKit"]),
    ]
)
