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

/// Where the music plays: the AirPlay glyph in the place it always had,
/// now opening one list (PlayOn.swift): this device, AirPlay (the system's
/// own picker, as a row), the Chromecasts on the network, the user's other
/// Jellyfin clients, the server's jukebox. No second button anywhere: "ik
/// wil alleen er voor waken dat we niet 10000 knopen krijgen" (the
/// photographer, 17 November 2026). Lit while the music plays elsewhere,
/// as Music shows AirPlay. Our own button rather than AVRoutePickerView:
/// the iPad app on a Mac, where build 68 crashed in Now Playing, gets the
/// list without AirPlay's row.
struct RoutePicker: View {
    /// On the app's own ground (the wide layout's bar), by day and by night,
    /// rather than on Now Playing's dark.
    let followsAppearance: Bool

    @Environment(AudioPlayer.self) private var player
    @State private var isOpen = false
    @State private var airPlays = false

    init(followsAppearance: Bool = false) {
        self.followsAppearance = followsAppearance
    }

    var body: some View {
        let elsewhere = player.playsOn != nil || airPlays
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
        .accessibilityValue(player.playsOn?.name ?? "")
        .popover(isPresented: $isOpen) {
            PlayOnList(isOpen: $isOpen)
                .presentationCompactAdaptation(.popover)
        }
        #if os(iOS)
        .onAppear { airPlays = Self.routeIsAirPlay }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in
            airPlays = Self.routeIsAirPlay
        }
        #endif
    }

    private func glyph(lit: Bool) -> AnyShapeStyle {
        if followsAppearance {
            return lit ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(HierarchicalShapeStyle.primary)
        }
        return AnyShapeStyle(Color.white.opacity(lit ? 1 : 0.6))
    }

    #if os(iOS)
    private static var routeIsAirPlay: Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.portType == .airPlay }
    }
    #endif
}

/// The list: looks only while it is open, so neither a launch nor the
/// screenshot walk asks for the local network.
private struct PlayOnList: View {
    @Binding var isOpen: Bool

    @Environment(AudioPlayer.self) private var player

    var body: some View {
        let playOn = player.playOn
        VStack(alignment: .leading, spacing: 0) {
            Text("Play On")
                .font(.headline)
                .padding(.horizontal, Theme.Space.m)
                .padding(.vertical, Theme.Space.s)
            row(nil, name: "This \(Device.model)", detail: nil)
            if offersAirPlay { airPlayRow }
            ForEach(devices) { device in
                row(device, name: device.name, detail: device.detail)
            }
            if playOn.devices.isEmpty {
                Text("Looking for devices on this network")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Theme.Space.m)
                    .padding(.vertical, Theme.Space.s)
            }
        }
        .padding(.vertical, Theme.Space.s)
        .frame(minWidth: 280, alignment: .leading)
        .onAppear { playOn.look() }
        .onDisappear { playOn.stopLooking() }
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

    private func row(_ device: PlayOnDevice?, name: String, detail: String?) -> some View {
        let chosen = device?.id == player.playsOn?.id
        return Button {
            isOpen = false
            player.playOn.choose(device)
        } label: {
            HStack(spacing: Theme.Space.m) {
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
                    .foregroundStyle(Theme.accent)
                    .opacity(chosen ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, Theme.Space.s)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    /// AirPlay is the system's to choose: its own picker lies over the row,
    /// unseen, and takes the tap.
    private var airPlayRow: some View {
        HStack(spacing: Theme.Space.m) {
            Text("AirPlay")
            Spacer(minLength: 0)
            Image(systemName: "airplay.audio")
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s)
        .overlay {
            SystemRoutePicker {
                // The sound goes to AirPlay from here: what played
                // elsewhere comes back first.
                if player.playsOn != nil { player.playOn.choose(nil) }
                player.playOn.airPlayOpened()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("AirPlay")
        // The row is the picker's button: VoiceOver says so.
        .accessibilityAddTraits(.isButton)
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
