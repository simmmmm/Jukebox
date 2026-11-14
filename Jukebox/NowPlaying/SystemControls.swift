// The two controls Now Playing takes from the system rather than drawing:
// the volume slider (MPVolumeView: the phone's own volume, the same as the
// buttons on its side, and the AirPlay speaker's when one plays) and the
// AirPlay picker (AVRoutePickerView: the system's list of speakers and
// headphones). SwiftUI has neither, so these are the only UIKit in Now
// Playing. Both are told they are on dark, whatever the phone's appearance:
// Now Playing always is.
//
// On the Mac there is no MPVolumeView: the volume is the player's own, as
// Music's window has it beside the system's (AudioPlayer.volume), and the
// picker is AppKit's AVRoutePickerView, which routes one player's sound.

import AVKit
import MediaPlayer
import SwiftUI
#if os(iOS)
import UIKit

/// The system volume slider, alone.
struct VolumeControl: UIViewRepresentable {
    func makeUIView(context: Context) -> NowPlayingSystemVolumeView {
        let view = NowPlayingSystemVolumeView(frame: .zero)
        // The filled part white, as Numa's slider; the rest the system's grey.
        view.tintColor = .white
        view.overrideUserInterfaceStyle = .dark
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

/// The AirPlay button: the system's picker of where the music plays.
struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView(frame: .zero)
        // Grey like the lyrics and queue buttons beside it; white while
        // the music plays somewhere else, as Music shows it.
        view.tintColor = UIColor(white: 1, alpha: 0.6)
        view.activeTintColor = .white
        // Speakers and headphones first: this is music, not video.
        view.prioritizesVideoDevices = false
        view.overrideUserInterfaceStyle = .dark
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#else

/// The player's own volume, 0 to 1, kept across launches.
struct VolumeControl: View {
    @Environment(AudioPlayer.self) private var player

    var body: some View {
        @Bindable var player = player
        Slider(value: $player.volume, in: 0...1) {
            Text("Volume")
        }
        .labelsHidden()
        // The filled part white, as on the iPhone.
        .tint(.white)
    }
}

/// The AirPlay button: AppKit's picker of where the player's sound goes.
struct RoutePicker: NSViewRepresentable {
    @Environment(AudioPlayer.self) private var player

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
