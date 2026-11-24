// The download control of an album's, a playlist's and a mix's page, as
// Music has it in the bar: arrow.down.circle to download, a ring filling as
// it comes (a stop square in it, as the system's own), checkmark.circle once
// it is all on the phone — a menu then, with Remove Download, asked again
// before anything goes.

import JukeboxKit
import SwiftUI

/// The bar's download control for one album, playlist or mix.
struct OfflineDownloadButton: View {
    /// What Download would save, as the page has it now.
    let collection: OfflineCollection
    /// The page's removal dialog (`offlineRemovalDialog`): on the page, not
    /// here, so it stays open when the ring turns into the checkmark.
    @Binding var isConfirmingRemoval: Bool
    /// In a wide page's head, one of its quiet squares after the version
    /// filter, not a glyph in the window's bar: "de downloadknop komt een
    /// beetje lullig uit zo, die zou eigenlijk bij de play shuffle hartje
    /// puntjes horen" (the photographer, 24 November 2026). The iPhone keeps
    /// it in its bar.
    var inHead = false

    @Environment(OfflineStore.self) private var offline

    var body: some View {
        if inHead {
            control
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
        } else {
            control
        }
    }

    @ViewBuilder private var control: some View {
        switch offline.state(of: collection.reason) {
        case .notDownloaded:
            Button {
                offline.download(collection)
            } label: {
                if inHead {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(Theme.quietInk)
                        .quietSquare()
                } else {
                    Label("Download", systemImage: "arrow.down.circle")
                }
            }
            .disabled(collection.tracks.isEmpty)
            .accessibilityLabel("Download")
        case let .downloading(fraction: fraction, waiting: waiting):
            Menu {
                Group {
                    if let waiting {
                        Text(OfflineText.waiting(waiting))
                    }
                    Button("Remove Download", systemImage: "trash", role: .destructive) {
                        isConfirmingRemoval = true
                    }
                }
                .menuIcons()
            } label: {
                if inHead {
                    OfflineProgressRing(fraction: fraction, side: 16)
                        .quietSquare()
                } else {
                    OfflineProgressRing(fraction: fraction)
                }
            }
            .accessibilityLabel(Text("Downloading"))
            .accessibilityValue(Text(waiting.map(OfflineText.waiting) ?? OfflineText.percent(fraction)))
        case .downloaded:
            Menu {
                Button("Remove Download", systemImage: "trash", role: .destructive) {
                    isConfirmingRemoval = true
                }
                .menuIcons()
            } label: {
                if inHead {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(Theme.quietInk)
                        .quietSquare()
                } else {
                    Label("Downloaded", systemImage: "checkmark.circle")
                }
            }
            .accessibilityLabel("Downloaded")
        }
    }
}

/// How much of a download is on the phone: a thin ring in the accent around
/// a stop square, as the system draws a download that can be stopped.
struct OfflineProgressRing: View {
    let fraction: Double
    /// Its side when not the bar's own (a head's quiet square: 16).
    var fixedSide: CGFloat?

    @ScaledMetric(relativeTo: .body) private var scaledSide: CGFloat = 22

    init(fraction: Double, side: CGFloat? = nil) {
        self.fraction = fraction
        self.fixedSide = side
    }

    private var side: CGFloat { fixedSide ?? scaledSide }

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
        .animation(.linear(duration: Tokens.Motion.settle), value: shown)
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
            .confirmationDialog(Text("Remove “\(name)” from this \(Device.model)?"),
                                isPresented: $isPresented, titleVisibility: .visible) {
                Button("Remove Download", role: .destructive) {
                    offline.remove(reason)
                }
            } message: {
                Text("It still plays from your server. Songs another download holds stay.")
            }
    }
}
