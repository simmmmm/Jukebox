// Choose Picture… in a playlist's "…": the listener's own photograph as
// its cover, where the server takes one (JukeboxKit's PlaylistCovers: a
// Jellyfin or Emby administrator). "Voor de app van een fotograaf"
// (features.md; "doe alles", 18 November 2026). The iPhone and the iPad
// choose from Photos; the Mac from its files, as its apps do.

import ImageIO
import JukeboxKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// A picture of any size or kind ImageIO reads (a camera's HEIC, a 50 MB
/// TIFF) as a JPEG of 1200 at most on its longer side, upright: what a
/// server's cover is shown at, 880 at the largest.
nonisolated func playlistPictureJPEG(_ data: Data) -> Data? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
              kCGImageSourceCreateThumbnailFromImageAlways: true,
              kCGImageSourceCreateThumbnailWithTransform: true,
              kCGImageSourceThumbnailMaxPixelSize: 1200,
          ] as CFDictionary) else { return nil }
    let out = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(out as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
    return CGImageDestinationFinalize(destination) ? out as Data : nil
}

extension View {
    /// The picker for Choose Picture…, shown while `isPresented`; the
    /// picture chosen goes to the server as `playlist`'s.
    func playlistPicturePicker(isPresented: Binding<Bool>, for playlist: Playlist,
                               failed: Binding<String?>) -> some View {
        modifier(PlaylistPicturePicker(isPresented: isPresented, playlist: playlist, failed: failed))
    }
}

private struct PlaylistPicturePicker: ViewModifier {
    @Binding var isPresented: Bool
    let playlist: Playlist
    @Binding var failed: String?

    @Environment(LibraryStore.self) private var library
    @State private var item: PhotosPickerItem?

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .fileImporter(isPresented: $isPresented, allowedContentTypes: [.image]) { result in
                guard case let .success(url) = result else { return }
                let opened = url.startAccessingSecurityScopedResource()
                let data = try? Data(contentsOf: url)
                if opened { url.stopAccessingSecurityScopedResource() }
                send(data)
            }
        #else
        content
            .photosPicker(isPresented: $isPresented, selection: $item, matching: .images)
            .onChange(of: item) { _, chosen in
                guard let chosen else { return }
                item = nil
                Task { send(try? await chosen.loadTransferable(type: Data.self)) }
            }
        #endif
    }

    private func send(_ data: Data?) {
        Task {
            guard let data, let jpeg = await Task.detached(operation: { playlistPictureJPEG(data) }).value else {
                failed = String(localized: "That picture could not be read.")
                return
            }
            do {
                try await library.setCover(jpeg, of: playlist)
            } catch {
                failed = error.localizedDescription
            }
        }
    }
}
