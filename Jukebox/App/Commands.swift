// The keys, as Apple's Music has them, in the Mac's menu bar and on an
// iPad's keyboard (the iPad app on a Mac too): Space plays or pauses, ⌘→
// and ⌘← go to the next and the previous song, ⌘↑ and ⌘↓ turn the
// volume up and down on the Mac. ⌘, opens Settings: the Mac's Settings
// window, or the wide window's sheet on an iPad. ⌘F gives the window bar's
// search field the keys.

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct JukeboxCommands: Commands {
    let app: AppModel

    var body: some Commands {
        CommandMenu("Controls") {
            // Never disabled: a disabled item could still take Space from a
            // field typed in. With nothing to play, nothing happens.
            Button(app.player.isPlaying ? String(localized: "Pause") : String(localized: "Play")) {
                playOrPause()
            }
            .keyboardShortcut(.space, modifiers: [])
            Button("Next") { app.player.next() }
                .keyboardShortcut(.rightArrow)
                .disabled(!app.player.hasTrack)
            Button("Previous") { app.player.previous() }
                .keyboardShortcut(.leftArrow)
                .disabled(!app.player.hasTrack)
            // The Mac's volume is the player's own, with its slider in the
            // bar. On the iPad it is the system's, the keyboard's own keys
            // turn it, and the player's stays 1 (AudioPlayer.volume).
            #if os(macOS)
            Divider()
            Button("Increase Volume") { app.player.volume += 0.1 }
                .keyboardShortcut(.upArrow)
            Button("Decrease Volume") { app.player.volume -= 0.1 }
                .keyboardShortcut(.downArrow)
            #endif
        }
        // The wide window's search field, in its bar: ⌘F, as the Mac's Find.
        CommandGroup(before: .textEditing) {
            Button("Search") {
                // The page first, so the field there is the one that shows.
                app.navigator.showSearch()
                app.navigator.searchRequests += 1
            }
                .keyboardShortcut("f")
                .disabled(!app.navigator.isWide || app.phase != .signedIn)
        }
        #if os(iOS)
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { app.navigator.isSettingsPresented = true }
                .keyboardShortcut(",")
                // The wide window presents it; the tabs have their own way.
                .disabled(!app.navigator.isWide || app.phase != .signedIn)
        }
        #endif
    }

    private func playOrPause() {
        #if os(macOS)
        // The menu sees Space before a field does: typed into one (Search's,
        // a playlist's name), it is a space.
        if let field = NSApp.keyWindow?.firstResponder as? NSTextView {
            field.insertText(" ", replacementRange: field.selectedRange())
            return
        }
        #endif
        app.player.togglePlayPause()
    }
}
