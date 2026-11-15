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

    init(followsAppearance: Bool = false) {
        self.followsAppearance = followsAppearance
    }

    var body: some View {
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

    @Environment(AudioPlayer.self) private var player

    var body: some View {
        @Bindable var player = player
        if followsAppearance {
            // On the bar Linux's level: a line in the text's colour at 60 %,
            // not the accent (the designer's spec, §2), its knob under the
            // pointer.
            LineSlider(value: $player.volume, range: 0...1, fill: Color.primary.opacity(0.6))
                .accessibilityLabel("Volume")
        } else {
            Slider(value: $player.volume, in: 0...1) {
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

/// The AirPlay button: the system's picker of where the music plays. None
/// in the iPad app on a Mac: AVRoutePickerView is the other suspect for
/// build 68's crash there, and the Mac's own menu bar chooses the speaker.
struct RoutePicker: View {
    /// On the app's own ground (the wide layout's bar), by day and by night,
    /// rather than on Now Playing's dark.
    let followsAppearance: Bool

    init(followsAppearance: Bool = false) {
        self.followsAppearance = followsAppearance
    }

    var body: some View {
        if !ProcessInfo.processInfo.isiOSAppOnMac {
            SystemRoutePicker(followsAppearance: followsAppearance)
        }
    }
}

private struct SystemRoutePicker: UIViewRepresentable {
    let followsAppearance: Bool

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView(frame: .zero)
        // Grey like the lyrics and queue buttons beside it; full while
        // the music plays somewhere else, as Music shows it. On the bar
        // in full like the glyphs beside it, as Linux's, and lit in the
        // accent while it plays elsewhere, as a lit button there.
        if followsAppearance {
            view.tintColor = .label
            view.activeTintColor = UIColor(Theme.accent)
        } else {
            view.tintColor = UIColor(white: 1, alpha: 0.6)
            view.activeTintColor = .white
            view.overrideUserInterfaceStyle = .dark
        }
        // Speakers and headphones first: this is music, not video.
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#else

/// The AirPlay button: AppKit's picker of where the player's sound goes.
struct RoutePicker: NSViewRepresentable {
    /// The iPhone's call, kept the same: AppKit's picker follows the
    /// appearance by itself.
    let followsAppearance: Bool

    @Environment(AudioPlayer.self) private var player

    init(followsAppearance: Bool = false) {
        self.followsAppearance = followsAppearance
    }

    func makeNSView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView(frame: .zero)
        // A plain glyph, as the buttons beside it are.
        view.isRoutePickerButtonBordered = false
        // On the Mac the picker routes one player, not the whole system.
        view.player = player.routedPlayer
        return view
    }

    func updateNSView(_ nsView: AVRoutePickerView, context: Context) {}
}
#endif
