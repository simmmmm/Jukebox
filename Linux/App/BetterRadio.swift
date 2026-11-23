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

    /// Shows it when due: signed in, the build has Jukebox's key, and
    /// Enhance Radio not yet chosen.
    static func askIfDue() {
        guard !isShowing, app.phase == .signedIn, AppSettings.canEnhanceRadio, !app.settings.radioChoiceMade else { return }
        isShowing = true
        let dialog = adw_alert_dialog_new("Better Radio",
                                          "To find music that sounds alike, Jukebox looks up artist and song names on Last.fm and MusicBrainz. Nothing about you is sent.")!
        adw_alert_dialog_add_response(ptr(dialog), "not-now", "Not Now")
        adw_alert_dialog_add_response(ptr(dialog), "turn-on", "Turn On")
        adw_alert_dialog_set_response_appearance(ptr(dialog), "turn-on", ADW_RESPONSE_SUGGESTED)
        adw_alert_dialog_set_default_response(ptr(dialog), "turn-on")
        adw_alert_dialog_set_close_response(ptr(dialog), "not-now")
        adw_dialog_set_can_close(ptr(dialog), 0)
        on(raw(dialog), "response", argument: { response in
            answer(response.map { String(cString: $0.assumingMemoryBound(to: CChar.self)) } == "turn-on")
        })
        adw_dialog_present(ptr(dialog), MainWindow.window)
    }

    /// Both together, Last.fm and AcousticBrainz, and the choice kept.
    static func answer(_ on: Bool) {
        app.settings.enhanceRadio = on
        app.settings.radioChoiceMade = true
        app.radio.enhanceRadioChanged()
        isShowing = false
    }
}
