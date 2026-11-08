// The download control of an album's, a playlist's and a mix's page, as
// Music has it in the bar: arrow.down.circle to download, a ring filling as
// it comes (a stop square in it, as the system's own), checkmark.circle once
// it is all on the phone — a menu then, with Remove Download, asked again
// before anything goes.

import JukeboxKit
import SwiftUI
import UIKit

/// The bar's download control for one album, playlist or mix.
struct OfflineDownloadButton: View {
    /// What Download would save, as the page has it now.
    let collection: OfflineCollection
    /// The page's removal dialog (`offlineRemovalDialog`): on the page, not
    /// here, so it stays open when the ring turns into the checkmark.
    @Binding var isConfirmingRemoval: Bool

    @Environment(OfflineStore.self) private var offline

    var body: some View {
        switch offline.state(of: collection.reason) {
        case .notDownloaded:
            Button {
                offline.download(collection)
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
            .disabled(collection.tracks.isEmpty)
        case let .downloading(fraction: fraction, waiting: waiting):
            Menu {
                if let waiting {
                    Text(OfflineText.waiting(waiting))
                }
                Button("Remove Download", systemImage: "trash", role: .destructive) {
                    isConfirmingRemoval = true
                }
            } label: {
                OfflineProgressRing(fraction: fraction)
            }
            .accessibilityLabel(Text("Downloading"))
            .accessibilityValue(Text(waiting.map(OfflineText.waiting) ?? OfflineText.percent(fraction)))
        case .downloaded:
            Menu {
                Button("Remove Download", systemImage: "trash", role: .destructive) {
                    isConfirmingRemoval = true
                }
            } label: {
                Label("Downloaded", systemImage: "checkmark.circle")
            }
        }
    }
}

/// How much of a download is on the phone: a thin ring in the accent around
/// a stop square, as the system draws a download that can be stopped.
struct OfflineProgressRing: View {
    let fraction: Double

    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 22

    var body: some View {
        // Never quite empty: a ring at nothing reads as no download at all.
        let shown = CGFloat(min(1, max(0.03, fraction)))
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.35), lineWidth: 2)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Rectangle()
                .fill(Theme.accent)
                .frame(width: side * 0.28, height: side * 0.28)
        }
        .frame(width: side, height: side)
        .animation(.linear(duration: 0.4), value: shown)
    }
}

extension View {
    /// Remove Download, asked first: what goes, and what stays.
    func offlineRemovalDialog(_ isPresented: Binding<Bool>, for reason: OfflineReason, name: String) -> some View {
        modifier(OfflineRemovalDialog(isPresented: isPresented, reason: reason, name: name))
    }
}

private struct OfflineRemovalDialog: ViewModifier {
    @Binding var isPresented: Bool
    let reason: OfflineReason
    let name: String

    @Environment(OfflineStore.self) private var offline

    func body(content: Content) -> some View {
        content
            .confirmationDialog(Text("Remove “\(name)” from this \(UIDevice.current.model)?"),
                                isPresented: $isPresented, titleVisibility: .visible) {
                Button("Remove Download", role: .destructive) {
                    offline.remove(reason)
                }
            } message: {
                Text("It still plays from your server. Songs another download holds stay.")
            }
    }
}
