// Copy Share Link in a menu on the iPhone, the iPad and the Mac
// (ShareLinks.swift has the why): the server makes the link on the tap, and
// it goes to the pasteboard, for Messages or Mail.

import JukeboxKit
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct CopyShareLinkButton: View {
    let id: ItemID
    let tracks: [ItemID]

    @Environment(LibraryStore.self) private var library

    var body: some View {
        if library.can(.share) {
            Button("Copy Share Link", systemImage: "link") {
                Task {
                    guard let url = await library.shareLink(for: id, tracks: tracks) else { return }
                    #if os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    #else
                    UIPasteboard.general.url = url
                    #endif
                }
            }
        }
    }
}
