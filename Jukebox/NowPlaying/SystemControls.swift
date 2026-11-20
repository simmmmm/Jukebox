// The two controls Now Playing takes from the system rather than drawing:
// the volume slider (MPVolumeView: the phone's own volume, the same as the
// buttons on its side, and the AirPlay speaker's when one plays) and the
// AirPlay picker (AVRoutePickerView: the system's list of speakers and
// headphones). SwiftUI has neither, so these are the only UIKit in Now
// Playing. Both are told they are on dark, whatever the phone's appearance:
// Now Playing always is. The iPad's and the Mac's bar (PlayerBar) stands on
// the app's own ground, by day too, and asks them to follow the appearance.
//
// On the Mac there is no MPVolumeView: the volume is the player's own, as
// Music's window has it beside the system's (AudioPlayer.volume), and the
// picker is AppKit's AVRoutePickerView, which routes one player's sound.
// The iPad app on a Mac takes the player's own volume too, and has no
// AirPlay button: there, tapping the song to open Now Playing crashed
// (build 68, the photographer, 14 November 2026), and MPVolumeView and
// AVRoutePickerView, which the Mac's iOS runtime may lack, are the suspects.

import AVKit
import MediaPlayer
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// The volume: the system's on the iPhone and the iPad, the player's own on
/// the Mac and for the iPad app on a Mac.
struct VolumeControl: View {
    /// On the app's own ground (the wide layout's bar), by day and by night,
    /// rather than on Now Playing's dark.
    let followsAppearance: Bool

    @Environment(AudioPlayer.self) private var player

    init(followsAppearance: Bool = false) {
        self.followsAppearance = followsAppearance
    }

    var body: some View {
        // Playing elsewhere (PlayOn.swift): that device's own level, on
        // every platform; the phone's buttons still move the phone's.
        if player.playsOn != nil {
            PlayerVolumeSlider(followsAppearance: followsAppearance, remote: true)
        } else {
            local
        }
    }

    @ViewBuilder private var local: some View {
        #if os(iOS)
        if ProcessInfo.processInfo.isiOSAppOnMac {
            PlayerVolumeSlider(followsAppearance: followsAppearance)
        } else {
            SystemVolumeSlider(followsAppearance: followsAppearance)
        }
        #else
        PlayerVolumeSlider(followsAppearance: followsAppearance)
        #endif
    }
}

/// The player's own volume, 0 to 1, kept across launches.
private struct PlayerVolumeSlider: View {
    let followsAppearance: Bool
    /// The device it plays on elsewhere, not the listener's level here.
    var remote = false

    @Environment(AudioPlayer.self) private var player

    private var level: Binding<Double> {
        let player = player
        if remote {
            return Binding(get: { player.remoteVolume ?? 1 }, set: { player.setRemoteVolume($0) })
        }
        return Binding(get: { player.volume }, set: { player.volume = $0 })
    }

    var body: some View {
        if followsAppearance {
            // On the bar Linux's level: a line in the text's colour at 60 %,
            // not the accent (the designer's spec, §2), its knob under the
            // pointer.
            LineSlider(value: level, range: 0...1, fill: Color.primary.opacity(0.6))
                .accessibilityLabel("Volume")
        } else {
            Slider(value: level, in: 0...1) {
                Text("Volume")
            }
            .labelsHidden()
            // The filled part white, as on the iPhone.
            .tint(.white)
        }
    }
}

#if os(iOS)
/// The system volume slider, alone.
private struct SystemVolumeSlider: UIViewRepresentable {
    let followsAppearance: Bool

    func makeUIView(context: Context) -> NowPlayingSystemVolumeView {
        let view = NowPlayingSystemVolumeView(frame: .zero)
        if followsAppearance {
            // The level at 60 % of the text's colour, not the accent (the
            // designer's spec, §2).
            view.tintColor = .secondaryLabel
        } else {
            // The filled part white, as Numa's slider; the rest the system's grey.
            view.tintColor = .white
            view.overrideUserInterfaceStyle = .dark
        }
        return view
    }

    func updateUIView(_ uiView: NowPlayingSystemVolumeView, context: Context) {}
}

/// MPVolumeView without its own route button: AirPlay has its place in the
/// row below, as Music has it. The route button's switch
/// (`showsRouteButton`) has been deprecated since iOS 13, so the button is
/// hidden where it is laid out instead; when there is none, nothing happens.
final class NowPlayingSystemVolumeView: MPVolumeView {
    override func layoutSubviews() {
        super.layoutSubviews()
        for subview in subviews {
            if let button = subview as? UIButton {
                button.isHidden = true
            } else if subview is UISlider {
                // In the middle of the view's height: MPVolumeView lays its
                // slider out at the top, so it sat above the speaker glyphs
                // beside it, which SwiftUI centres — the photographer,
                // 9 November 2026: "Volume icoontjes staan nu niet goed
                // verticaal uitgelijnd".
                subview.center = CGPoint(x: subview.center.x, y: bounds.midY)
            }
        }
    }
}
#endif

#if os(iOS)
/// Where the system sends the sound while it plays here: the iPhone's own
/// speaker, or what was chosen in AirPlay's list or Control Center ("Living
/// Room", the AirPods, the car). Play On names it on top, under its own name:
/// the list said "This iPhone" whatever played, "AirPlay is verbonden maar er
/// staat hier this iPhone" (the photographer, 20 November 2026). One for the
/// app, followed as the route changes; the mini player's button reads it too.
@Observable
final class SystemRoute {
    static let shared = SystemRoute()

    /// The output's own name, nil for the device's speaker or earpiece
    /// (whose own names, "Speaker" and "Receiver", say nothing here).
    private(set) var name: String?
    private(set) var port: AVAudioSession.Port?
    @ObservationIgnored private var token: NSObjectProtocol?

    private init() {
        read()
        // Posted on a queue of the session's own: read on the main one.
        token = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification,
                                                       object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.read() }
        }
    }

    private func read() {
        let away = AVAudioSession.sharedInstance().currentRoute.outputs.first {
            $0.portType != .builtInSpeaker && $0.portType != .builtInReceiver
        }
        name = away?.portName
        port = away?.portType
    }

    /// AirPlay plays: the button is lit, as Music lights it.
    var isAirPlay: Bool { port == .airPlay }

    /// "Living Room", "Tijmen's AirPods", or "This iPhone".
    var title: String { name ?? "This \(Device.model)" }

    var symbol: String {
        guard let port else { return Device.symbol }
        switch port {
        case .airPlay: return "airplay.audio"
        case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP, .headphones: return "headphones"
        case .carAudio: return "car"
        case .HDMI: return "tv"
        default: return "hifispeaker"
        }
    }
}
#endif

extension Device {
    /// This device as a glyph, for the row that plays here.
    static var symbol: String {
        #if os(iOS)
        if ProcessInfo.processInfo.isiOSAppOnMac { return "laptopcomputer" }
        return UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        #else
        return "laptopcomputer"
        #endif
    }
}

/// Where the music plays: the AirPlay glyph in the place it always had,
/// opening one list (PlayOn.swift): what plays here now under its own name,
/// the Sonos rooms and Chromecasts on the network, the user's other Jellyfin
/// clients, the server's jukebox, and at its foot the system's own AirPlay
/// and Bluetooth picker as a row. No second button anywhere: "ik wil alleen
/// er voor waken dat we niet 10000 knopen krijgen" (the photographer, 17
/// November 2026). Lit while the music plays elsewhere, as Music shows
/// AirPlay.
///
/// Always our list, never the system's picker alone: that one cannot hold
/// another app's speakers (a Media Device Discovery extension could put them
/// there, docs/ARCHITECTURE.md), and the list looks for ours only once it
/// is open, so whether there are any is not known before. The mini player
/// takes this same view (`RoutePicker(followsAppearance: true)`).
struct RoutePicker: View {
    /// On the app's own ground (the wide layout's bar, the mini player), by
    /// day and by night, rather than on Now Playing's dark.
    let followsAppearance: Bool

    @Environment(AudioPlayer.self) private var player
    @State private var isOpen = false

    init(followsAppearance: Bool = false) {
        self.followsAppearance = followsAppearance
    }

    var body: some View {
        Button {
            isOpen = true
        } label: {
            Image(systemName: "airplay.audio")
                .font(followsAppearance ? .body : .title3)
                .foregroundStyle(glyph(lit: elsewhere))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("Play On")
        .accessibilityLabel("Play On")
        .accessibilityValue(PlayOnList.outputName(player))
        .popover(isPresented: $isOpen) {
            PlayOnList(isOpen: $isOpen)
                // On the iPhone a drawer from the bottom ("Vind zon drawer wel
                // prima hoor", the photographer, 20 November 2026); on the
                // iPad and the Mac a popover by the button, as Linux's menu.
                .presentationCompactAdaptation(.sheet)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var elsewhere: Bool {
        if player.playsOn != nil { return true }
        #if os(iOS)
        return SystemRoute.shared.isAirPlay
        #else
        return false
        #endif
    }

    private func glyph(lit: Bool) -> AnyShapeStyle {
        if followsAppearance {
            return lit ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(HierarchicalShapeStyle.primary)
        }
        return AnyShapeStyle(Color.white.opacity(lit ? 1 : 0.6))
    }
}

/// The list, Linux's Play On menu in Apple's controls: the heading, one row
/// a place the music can go, the one it goes to checked. It looks only
/// while it is open, so neither a launch nor the screenshot walk asks for
/// the local network.
private struct PlayOnList: View {
    @Binding var isOpen: Bool

    @Environment(AudioPlayer.self) private var player

    var body: some View {
        // All of it where it fits (the popover sizes to it), else scrolled.
        ViewThatFits(in: .vertical) {
            content
            ScrollView { content }
        }
        .frame(minWidth: 300, alignment: .topLeading)
        .onAppear { player.playOn.look() }
        .onDisappear { player.playOn.stopLooking() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Play On")
                .font(.serif(.title3))
                .padding(.horizontal, Theme.Space.l)
                .padding(.top, Theme.Space.l)
                .padding(.bottom, Theme.Space.s)
            // Here first, under the name of what it plays through now.
            row(nil, name: Self.hereName, symbol: Self.hereSymbol)
            ForEach(devices) { device in
                row(device, name: device.name, detail: device.detail, symbol: Self.symbol(of: device.kind))
            }
            if player.playOn.devices.isEmpty {
                Text("Looking for devices on this network")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Theme.Space.l)
                    .padding(.vertical, Theme.Space.s)
            }
            if offersAirPlay {
                Divider()
                    .padding(.vertical, Theme.Space.xs)
                airPlayRow
            }
        }
        .padding(.bottom, Theme.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// What plays the music now, for VoiceOver on the button.
    static func outputName(_ player: AudioPlayer) -> String {
        player.playsOn?.name ?? hereName
    }

    private static var hereName: String {
        #if os(iOS)
        SystemRoute.shared.title
        #else
        "This Mac"
        #endif
    }

    private static var hereSymbol: String {
        #if os(iOS)
        SystemRoute.shared.symbol
        #else
        Device.symbol
        #endif
    }

    private static func symbol(of kind: PlayOnDevice.Kind) -> String {
        switch kind {
        case .chromecast: "tv"
        case .upnp, .subsonicJukebox: "hifispeaker"
        case .jellyfin: "display"
        }
    }

    /// Not in the iPad app on a Mac: AVRoutePickerView is a suspect of
    /// build 68's crash there, and the Mac's menu bar chooses the speaker.
    private var offersAirPlay: Bool {
        #if os(iOS)
        !ProcessInfo.processInfo.isiOSAppOnMac
        #else
        true
        #endif
    }

    /// What was found, and the device playing even before it is found again.
    private var devices: [PlayOnDevice] {
        var devices = player.playOn.devices
        if let elsewhere = player.playsOn, !devices.contains(elsewhere) { devices.insert(elsewhere, at: 0) }
        return devices
    }

    private func row(_ device: PlayOnDevice?, name: String, detail: String? = nil, symbol: String) -> some View {
        let chosen = device?.id == player.playsOn?.id
        return Button {
            isOpen = false
            player.playOn.choose(device)
        } label: {
            label(name, detail: detail, symbol: symbol, checked: chosen)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private func label(_ name: String, detail: String?, symbol: String, checked: Bool) -> some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: symbol)
                .foregroundStyle(checked ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "checkmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .opacity(checked ? 1 : 0)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Theme.Space.l)
        .frame(minHeight: 44)
        .contentShape(.rect)
    }

    /// The system's own picker, for what only the system reaches: AirPlay
    /// speakers and Bluetooth headphones. Its button lies over the row,
    /// unseen, and takes the tap; what is chosen there comes back to the
    /// row on top, by its name.
    private var airPlayRow: some View {
        label(Self.airPlayTitle, detail: nil, symbol: "airplay.audio", checked: false)
            .overlay {
                SystemRoutePicker {
                    // The sound goes where the system sends it from here:
                    // what played elsewhere comes back first.
                    if player.playsOn != nil { player.playOn.choose(nil) }
                    player.playOn.airPlayOpened()
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Self.airPlayTitle)
            // The row is the picker's button: VoiceOver says so.
            .accessibilityAddTraits(.isButton)
    }

    /// The Mac's picker routes the player's sound to AirPlay; the iPhone's
    /// to Bluetooth too.
    private static var airPlayTitle: String {
        #if os(iOS)
        "AirPlay & Bluetooth…"
        #else
        "AirPlay…"
        #endif
    }
}

#if os(iOS)
/// The system's AirPlay picker, its glyph unseen: the row under it shows.
private struct SystemRoutePicker: UIViewRepresentable {
    let opened: () -> Void

    func makeCoordinator() -> RoutePickerDelegate { RoutePickerDelegate(opened: opened) }

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView(frame: .zero)
        view.tintColor = .clear
        view.activeTintColor = .clear
        // Speakers and headphones first: this is music, not video.
        view.prioritizesVideoDevices = false
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#else

/// AppKit's picker of where the player's sound goes, its glyph unseen.
private struct SystemRoutePicker: NSViewRepresentable {
    let opened: () -> Void

    @Environment(AudioPlayer.self) private var player

    func makeCoordinator() -> RoutePickerDelegate { RoutePickerDelegate(opened: opened) }

    func makeNSView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView(frame: .zero)
        view.isRoutePickerButtonBordered = false
        view.setRoutePickerButtonColor(.clear, for: .normal)
        view.setRoutePickerButtonColor(.clear, for: .active)
        // On the Mac the picker routes one player, not the whole system.
        view.player = player.routedPlayer
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ nsView: AVRoutePickerView, context: Context) {}
}
#endif

/// Told when the system's AirPlay list opens (counted, `play_on` `airplay`).
final class RoutePickerDelegate: NSObject, AVRoutePickerViewDelegate {
    let opened: () -> Void

    init(opened: @escaping () -> Void) {
        self.opened = opened
    }

    func routePickerViewWillBeginPresentingRoutes(_ routePickerView: AVRoutePickerView) {
        opened()
    }
}
