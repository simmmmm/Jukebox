// Share… in a song's, an album's and an artist's menu: Apple's share sheet
// with the words and a link for a friend (JukeboxKit's Sharing, the same as
// Linux's Copy Link). The link is looked up only once a way to share is
// chosen, so the menu opens at once and nothing leaves the device for a
// menu opened and closed.

import CoreTransferable
import JukeboxKit
import SwiftUI
import UniformTypeIdentifiers

/// What the share sheet gets: the words and the link as one text, made
/// when the sheet asks for it.
nonisolated struct SharedMusic: Transferable, Sendable {
    let item: ShareItem
    let server: (any MusicServer)?

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .utf8PlainText) { shared in
            Data(await Sharing().text(for: shared.item, server: shared.server).text.utf8)
        }
    }
}

/// "Share…", as Music's menus have it.
struct ShareMenuItem: View {
    let item: ShareItem

    @Environment(LibraryStore.self) private var library

    var body: some View {
        ShareLink(item: SharedMusic(item: item, server: library.server), preview: SharePreview(item.name)) {
            Label("Share…", systemImage: "square.and.arrow.up")
        }
    }
}
