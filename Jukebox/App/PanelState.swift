// The desktop's panel at the window's right, Up next or the song's words:
// whether it is open and on what, kept across launches. Closed until asked
// for, opened and closed from the player's bar ("Als optionele
// toevoegingen", the photographer of Feishin's panel, 14 November 2026;
// Linux/App/Panel.swift has the rest). Foundation and Observation only, so
// Linux's window and the iPad's and the Mac's inspector follow one state.

import Foundation
import Observation

@Observable
final class PanelState {
    /// "queue": Up next's raw value is its key in UserDefaults, and Linux's
    /// name for its page in the panel's stack.
    enum Content: String {
        case upNext = "queue"
        case lyrics
    }

    var isOpen: Bool { didSet { remember() } }
    var content: Content { didSet { remember() } }
    /// The window is narrow enough that the panel lies over the page
    /// (Linux's MainWindow follows its split view's `collapsed`, the iPad's
    /// and the Mac's WideShell its width: below 1280).
    var isOverlaid = false
    /// False while a screenshot walk opens and closes the panel: the
    /// listener's choice stays the listener's.
    var remembers = true
    /// Opened by the listener since launch.
    private var isOpenedHere = false

    /// What shows. Lying over the page it shows only once opened since
    /// launch: "At launch it opens again only where it docks; lying over the
    /// page at launch would hide the page" (the designer's spec, §3). The
    /// panel, the bar's buttons, the lyrics and the counting all read this
    /// one value. It needs a song too: the buttons are in the player's bar,
    /// which is hidden without one.
    var isShown: Bool { isOpen && (!isOverlaid || isOpenedHere) }

    init() {
        isOpen = UserDefaults.standard.bool(forKey: "panelOpen")
        content = UserDefaults.standard.string(forKey: "panelContent").flatMap(Content.init) ?? .upNext
    }

    /// The bar's buttons: the one shown closes the panel, the other turns
    /// it to its own.
    func toggle(_ choice: Content) {
        if isShown && content == choice {
            isOpen = false
        } else {
            content = choice
            isOpen = true
            isOpenedHere = true
        }
    }

    private func remember() {
        guard remembers else { return }
        UserDefaults.standard.set(isOpen, forKey: "panelOpen")
        UserDefaults.standard.set(content.rawValue, forKey: "panelContent")
    }
}
