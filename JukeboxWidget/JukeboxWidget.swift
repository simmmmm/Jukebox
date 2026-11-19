// Jukebox's widget: doors into the music, not a second Now Playing. The
// lock screen and Control Center show what plays already; this gives what
// they do not, Your Station and Home's mixes, one tap from playing.
//
// - Small: Your Station, the mark lit and "On air" while it plays,
//   otherwise a Play.
// - Medium: the same, and beside it Home's first three mixes, each a
//   Play by itself.
// - The lock screen: the mark, Your Station's Play. The iPhone's and the
//   iPad's: the Mac has no accessory families.
// - A control (Control Center, the Lock Screen, the Action Button, and the
//   Mac's Control Center and menu bar): Your Station's Play.
//
// One target for the iPhone, the iPad and the Mac (project.yml): the Mac's
// desktop and Notification Center show the same Small and Medium.
//
// The buttons are WidgetIntents.swift's, performed by the app; a tap
// anywhere else opens the app. Everything shown comes from the snapshot
// the app writes (App/WidgetDoors.swift): the widget never asks the server.
//
// The Arch's rules (docs/design/tells.md): a flat ground, the mark flat
// unless on the air, titles in the serif, square covers in the one radius,
// one filled button, "On air" the one label.

import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif
import WidgetKit

@main
struct JukeboxWidgets: WidgetBundle {
    var body: some Widget {
        DoorsWidget()
        YourStationControl()
    }
}

/// Your Station as a control: in Control Center, on the Lock Screen (the
/// iPhone's) and on the Action Button, which takes any control. The same
/// door as the widget's Play, so the same intent, performed by the app and
/// counted `from: widget`. A control shows a symbol, not a drawing, so the
/// radio's waves stand in for the mark, as in Siri's Your Station shortcut
/// (MusicIntents.swift). Asked by the listener's hand, never by a car.
struct YourStationControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.tijmen.Jukebox.YourStation") {
            ControlWidgetButton(action: PlayYourStationFromWidget()) {
                Label("Your Station", systemImage: "dot.radiowaves.left.and.right")
            }
        }
        .displayName("Your Station")
        .description("Plays Your Station.")
    }
}

struct DoorsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Doors", provider: DoorsProvider()) { entry in
            DoorsView(entry: entry)
        }
        .configurationDisplayName("Jukebox")
        .description("Your Station and Home's mixes.")
        .supportedFamilies(families)
    }

    /// The Mac has no lock screen's families.
    private var families: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .systemMedium, .accessoryCircular]
        #else
        [.systemSmall, .systemMedium]
        #endif
    }
}

// MARK: - The timeline

nonisolated struct DoorsEntry: TimelineEntry {
    let date: Date
    /// Nil before the app has written one: shown as signed out.
    let snapshot: WidgetSnapshot?
    /// Each mix's cover, by its id, as the app saved it.
    let covers: [String: Data]
}

/// One entry, kept until the app reloads it: the widget changes only when
/// the app does something (WidgetDoors), never by the clock.
nonisolated struct DoorsProvider: TimelineProvider {
    func placeholder(in context: Context) -> DoorsEntry {
        DoorsEntry(date: Date(), snapshot: WidgetSnapshot(signedIn: true, account: "", onAir: false, mixes: []), covers: [:])
    }

    func getSnapshot(in context: Context, completion: @escaping (DoorsEntry) -> Void) {
        completion(current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DoorsEntry>) -> Void) {
        completion(Timeline(entries: [current()], policy: .never))
    }

    private func current() -> DoorsEntry {
        let snapshot = WidgetSnapshot.read()
        var covers: [String: Data] = [:]
        if let folder = WidgetSnapshot.folder, let snapshot {
            for mix in snapshot.mixes {
                covers[mix.id] = try? Data(contentsOf: folder.appendingPathComponent(snapshot.cover(of: mix)))
            }
        }
        return DoorsEntry(date: Date(), snapshot: snapshot, covers: covers)
    }
}

// MARK: - The views

struct DoorsView: View {
    let entry: DoorsEntry

    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        content
            .containerBackground(for: .widget) {
                #if os(iOS)
                if family == .accessoryCircular {
                    AccessoryWidgetBackground()
                } else {
                    ground
                }
                #else
                ground
                #endif
            }
    }

    /// The page's ground (Theme.ground), flat.
    private var ground: Color {
        Color(rgb: scheme == .dark ? 0x121110 : 0xF6F3EE)
    }

    private var signedIn: Bool { entry.snapshot?.signedIn == true }
    private var onAir: Bool { entry.snapshot?.onAir == true }

    @ViewBuilder private var content: some View {
        switch family {
        #if os(iOS)
        case .accessoryCircular:
            lockScreen
        #endif
        case .systemMedium where signedIn && !(entry.snapshot?.mixes.isEmpty ?? true):
            HStack(spacing: 16) {
                station
                mixes
            }
        default:
            if signedIn { station } else { signedOut }
        }
    }

    /// Quiet: the mark, flat, and where to go.
    private var signedOut: some View {
        VStack(alignment: .leading, spacing: 0) {
            ArchDrawing(size: 32, lit: false)
            Spacer(minLength: 0)
            Text("Sign in in Jukebox")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// Your Station: the mark, and Play or "On air".
    private var station: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                ArchDrawing(size: 44, lit: onAir)
                Spacer(minLength: 0)
                if !onAir {
                    // The widget's one filled button (tells.md, 6).
                    Button(intent: PlayYourStationFromWidget()) {
                        Image(systemName: "play.fill")
                            .font(.body)
                            .foregroundStyle(Color(rgb: scheme == .dark ? 0x2A1505 : 0xFFFFFF))
                            .frame(width: 36, height: 36)
                            .background(accent, in: .rect(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Play Your Station"))
                }
            }
            Spacer(minLength: 0)
            if onAir {
                Text("On air")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
            }
            Text("Your Station")
                .font(.system(.title3, design: .serif))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// Home's first mixes, each one tap from playing, hairlines between.
    private var mixes: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array((entry.snapshot?.mixes ?? []).enumerated()), id: \.element.id) { index, mix in
                if index > 0 { Hairline() }
                Button(intent: PlayMixFromWidget(mixID: mix.id)) {
                    HStack(spacing: 12) {
                        cover(mix)
                            .frame(width: 40, height: 40)
                            .clipShape(.rect(cornerRadius: 6))
                        Text(mix.title)
                            .font(.system(.subheadline, design: .serif))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Play \(mix.title)"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private func cover(_ mix: WidgetSnapshot.Mix) -> some View {
        if let image = coverImage(mix) {
            image.resizable().scaledToFill()
        } else {
            Rectangle().fill(Color.primary.opacity(0.08))
        }
    }

    /// The cover the app saved, in the platform's own image type.
    private func coverImage(_ mix: WidgetSnapshot.Mix) -> Image? {
        guard let data = entry.covers[mix.id] else { return nil }
        #if os(iOS)
        return UIImage(data: data).map { Image(uiImage: $0) }
        #else
        return NSImage(data: data).map { Image(nsImage: $0) }
        #endif
    }

    #if os(iOS)
    /// The mark in the lock screen's one colour; Your Station's Play while
    /// it is off the air.
    @ViewBuilder private var lockScreen: some View {
        let mark = ArchDrawing(size: 32, lit: onAir, template: true)
            .widgetAccentable()
            .opacity(signedIn ? 1 : 0.4)
        if signedIn && !onAir {
            Button(intent: PlayYourStationFromWidget()) { mark }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Play Your Station"))
        } else {
            mark
        }
    }
    #endif

    /// Copper by day, Glow by night (Theme.accent).
    private var accent: Color {
        Color(rgb: scheme == .dark ? 0xFFB54D : 0xA84A17)
    }
}

/// The Arch (ArchShapes.swift), as ArchMark draws it: Copper outside, Glow
/// inside, the core flat. Lit, while Your Station is on the air, its tubes
/// in their own oranges with the one soft glow, as a station's art on the
/// air (StationArtwork.swift). `template`: one colour, the lock screen's.
private struct ArchDrawing: View {
    let size: CGFloat
    let lit: Bool
    var template = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let cut = ArchCut.forSize(size)
        let width = cut.stroke * size / 32
        let line = StrokeStyle(lineWidth: width, lineCap: .round)
        let outer = ArchLine(tube: 0, cut: cut)
        let inner = ArchLine(tube: 1, cut: cut)
        ZStack {
            if template {
                outer.stroke(style: line)
                inner.stroke(style: line)
                ArchCore(cut: cut).fill(Color.primary.opacity(lit ? 1 : 0.6))
            } else {
                if lit {
                    ZStack {
                        outer.stroke(Color(rgb: 0xF07E36), style: StrokeStyle(lineWidth: width * 2.2, lineCap: .round))
                        inner.stroke(Color(rgb: 0xFFB44C), style: StrokeStyle(lineWidth: width * 2.2, lineCap: .round))
                    }
                    .blur(radius: size / 16)
                    .opacity(0.42)
                }
                outer.stroke(Color(rgb: lit ? 0xF07E36 : 0xA84A17), style: line)
                inner.stroke(Color(rgb: lit ? 0xFFB44C : 0xFFB54D), style: line)
                // The mark's core: amber on the paper, a warm white by night.
                ArchCore(cut: cut).fill(Color(rgb: scheme == .dark ? 0xFFF1D6 : 0xF7A136))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A hairline between rows, one pixel (Theme.swift's Hairline).
private struct Hairline: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(height: 1 / displayScale)
            .accessibilityHidden(true)
    }
}

extension Color {
    /// An sRGB colour by its hex, as Theme.swift's and the brand board's.
    init(rgb: UInt32) {
        self.init(.sRGB,
                  red: Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255,
                  opacity: 1)
    }
}
