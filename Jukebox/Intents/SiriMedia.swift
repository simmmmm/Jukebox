// "Play <anything in the library> in Jukebox", on the iPhone and in the car:
// SiriKit's media intent, INPlayMediaIntent, handled in the app itself
// (iOS 14 and later), no Intents extension. Apple: "In iOS 14 and later, you
// can set up handling for INPlayMediaIntent directly in your app"
// (SiriKit, Improving Siri Media Interactions and App Selection).
//
// Why SiriKit and not App Intents alone: an App Shortcut's phrase matches
// only the names the app suggested beforehand, never any album of the
// library. App Intents' own audio schema (MediaIntents' AudioSearch, which
// hands the app what was said) is iOS 27; Jukebox is built with Xcode 26
// for iOS 26. Siri's media domain hears the name, the album, the artist and
// the kind of thing said, and the app finds it (Voice.find).
//
// Needs: project.yml's INIntentsSupported, INSupportedMediaCategories and
// NSSiriUsageDescription; the Siri entitlement (Jukebox-iOS.entitlements)
// and SiriKit on the App ID (docs/RELEASE.md). Native macOS has no
// INPlayMediaIntentHandling: the Mac has the App Intents.
//
// Nothing is donated and no vocabulary is given: the library's names stay
// in the app.

#if os(iOS)
import Intents
import JukeboxKit
import UIKit

extension JukeboxAppDelegate {
    /// SiriKit asks the app itself for a handler; the app may have been
    /// launched in the background for it, as CarPlay launches it. The
    /// selector by hand: in an extension, so UIKit finds it for certain.
    @objc(application:handlerForIntent:)
    func application(_ application: UIApplication, handlerFor intent: INIntent) -> Any? {
        intent is INPlayMediaIntent ? SiriMedia() : nil
    }
}

/// `nonisolated`: SiriKit calls it off the main actor; the library is the
/// main actor's, so each step hops there through Voice.
nonisolated final class SiriMedia: NSObject, INPlayMediaIntentHandling {
    /// What was asked for, in the app's words, for the hop to the main actor.
    struct Request: Sendable {
        var name: String?
        var kind: MusicEntity.Kind?
        var artist: String?
        var genre: String?
        /// "Play Radiohead radio": a station from it.
        var asStation: Bool
    }

    func resolveMediaItems(for intent: INPlayMediaIntent) async -> [INPlayMediaMediaItemResolutionResult] {
        let search = intent.mediaSearch
        let type = search?.mediaType ?? .unknown
        var kind: MusicEntity.Kind?
        switch type {
        case .album: kind = .album
        case .artist: kind = .artist
        case .song: kind = .song
        case .playlist: kind = .playlist
        case .genre: kind = .genre
        default: kind = nil
        }
        // Siri puts a name where it heard what it is: "the album Blue" in
        // albumName, "Radiohead" in artistName.
        var name = search?.mediaName
        if name == nil, let album = search?.albumName {
            name = album
            kind = kind ?? .album
        }
        if name == nil, let artist = search?.artistName {
            name = artist
            kind = kind ?? .artist
        }
        let stationTypes: [INMediaItemType] = [.station, .musicStation, .radioStation, .algorithmicRadioStation]
        let request = Request(name: name, kind: kind, artist: search?.artistName, genre: search?.genreNames?.first,
                              asStation: stationTypes.contains(type))
        let entity: MusicEntity
        let asStation: Bool
        switch await Self.find(request) {
        case .signedOut:
            return [INPlayMediaMediaItemResolutionResult.unsupported(forReason: .loginRequired)]
        case .nothing:
            return [INPlayMediaMediaItemResolutionResult.unsupported()]
        case let .item(found, station):
            entity = found
            asStation = station
        }
        let item = INMediaItem(identifier: (asStation ? Self.stationPrefix : "") + entity.id, title: entity.name,
                               type: Self.type(of: entity.kind, asStation: asStation), artwork: nil)
        return [INPlayMediaMediaItemResolutionResult.success(with: item)]
    }

    func handle(intent: INPlayMediaIntent) async -> INPlayMediaIntentResponse {
        guard let id = intent.mediaItems?.first?.identifier else {
            return INPlayMediaIntentResponse(code: .failure, userActivity: nil)
        }
        let played = await Self.play(id, shuffled: intent.playShuffled == true)
        return INPlayMediaIntentResponse(code: played ? .success : .failure, userActivity: nil)
    }

    private static let stationPrefix = "radio/"

    private static func type(of kind: MusicEntity.Kind, asStation: Bool) -> INMediaItemType {
        if asStation { return .station }
        switch kind {
        case .album: return .album
        case .artist: return .artist
        case .playlist: return .playlist
        case .song: return .song
        case .genre, .station: return .station
        }
    }

    /// No name at all ("Play some music in Jukebox"): Your Station,
    /// as Jukebox's radio is what it plays when nothing is named.
    enum Found: Sendable {
        case signedOut
        case nothing
        case item(MusicEntity, asStation: Bool)
    }

    @MainActor private static func find(_ request: Request) async -> Found {
        guard let app = await Voice.ready() else { return .signedOut }
        let library = app.library
        guard let name = request.name, !name.isEmpty else {
            if let genre = request.genre, let found = Voice.find(genre, kind: .genre, artist: nil, in: library).first {
                return .item(found, asStation: false)
            }
            return .item(.yourStation, asStation: false)
        }
        let found = request.kind.map { Voice.find(name, kind: $0, artist: request.artist, in: library) }
            ?? Voice.find(name, in: library)
        guard let first = found.first else { return .nothing }
        return .item(first, asStation: request.asStation)
    }

    @MainActor private static func play(_ id: String, shuffled: Bool) async -> Bool {
        guard let app = await Voice.ready() else { return false }
        let asStation = id.hasPrefix(stationPrefix)
        guard let entity = Voice.entity(id: asStation ? String(id.dropFirst(stationPrefix.count)) : id, in: app.library)
        else { return false }
        return await Voice.play(entity, asStation: asStation, shuffled: shuffled, app: app).played
    }

    /// Siri's permission, asked once (Apple: "Request authorization from
    /// your iOS app, whether you're handling intents in an app extension or
    /// in your app").
    /// Not the main actor's (the class is nonisolated), so the answer, which
    /// comes on another queue, lands in a closure that belongs to none.
    static func askOnce() {
        guard INPreferences.siriAuthorizationStatus() == .notDetermined else { return }
        INPreferences.requestSiriAuthorization { _ in }
    }
}
#endif
