// Better Radio: the one step after the first sign-in, and once after the
// update for those who never chose, as the iPhone's, the iPad's and the
// Mac's sheet (Jukebox/Settings/BetterRadioView.swift). "Standaard aan maar
// maak het onderdeel van een onboarding flow waarin dit kort en krachtig
// benoemd wordt, maar dan wordt het of lastfm en dit aan of beide uit" (the
// photographer, 24 November 2026). GNOME's form for one question: an alert
// dialog, Turn On the suggested response and the default, Not Now beside
// it. Asked, not dismissed: Escape does not close it. Preferences › Radio
// changes it later.

import CAdw
import JukeboxKit

enum BetterRadio {
    private static var isShowing = false
    /// The dialog on screen: closed by hand once answered, as it cannot
    /// close itself (can-close is off, so Escape does not dismiss it, and
    /// that also kept a response from closing it: Turn On did nothing,
    /// "als ik druk gebeurt er niets", the photographer, 23 November 2026).
    private static var shown: UnsafeMutablePointer<AdwDialog>?

    /// Shows it when due: signed in, the build has Jukebox's key, and
    /// Enhance Radio not yet chosen.
    static func askIfDue() {
        guard !isShowing, app.phase == .signedIn, AppSettings.canEnhanceRadio, !app.settings.radioChoiceMade else { return }
        isShowing = true
        let dialog = adw_alert_dialog_new("Better Radio",
                                          "To find music that sounds alike, Jukebox sends the artist, song and album names in your library to Last.fm and ListenBrainz, and asks AcousticBrainz how each song sounds. Your Last.fm username goes too, if you add one. Nothing about your music server, your sign-in or this device is sent.")!
        adw_alert_dialog_add_response(ptr(dialog), "not-now", "Not Now")
        adw_alert_dialog_add_response(ptr(dialog), "turn-on", "Turn On")
        adw_alert_dialog_set_response_appearance(ptr(dialog), "turn-on", ADW_RESPONSE_SUGGESTED)
        adw_alert_dialog_set_default_response(ptr(dialog), "turn-on")
        adw_alert_dialog_set_close_response(ptr(dialog), "not-now")
        adw_dialog_set_can_close(ptr(dialog), 0)
        on(raw(dialog), "response", argument: { response in
            answer(response.map { String(cString: $0.assumingMemoryBound(to: CChar.self)) } == "turn-on")
        })
        shown = ptr(dialog)
        adw_dialog_present(ptr(dialog), MainWindow.window)
    }

    /// Both together, Last.fm and AcousticBrainz, and the choice kept.
    static func answer(_ on: Bool) {
        app.settings.enhanceRadio = on
        app.settings.radioChoiceMade = true
        app.radio.enhanceRadioChanged()
        if let dialog = shown { adw_dialog_force_close(dialog) }
        shown = nil
        isShowing = false
    }
}
