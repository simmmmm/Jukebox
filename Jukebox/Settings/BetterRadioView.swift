// Better Radio: the one step after the first sign-in, and once after the
// update for those who never chose. "Standaard aan maar maak het onderdeel
// van een onboarding flow waarin dit kort en krachtig benoemd wordt, maar
// dan wordt het of lastfm en dit aan of beide uit" (the photographer, 24
// November 2026). Turn On is the default and the prominent one; Not Now
// turns Enhance Radio off. Either way it is not asked again: Settings ›
// Radio changes it later. As Linux's dialog (BetterRadio.swift there): the
// arch, the title in the sleeves' serif, two sentences, two buttons.

import SwiftUI

struct BetterRadioView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(RadioController.self) private var radio
    @Environment(\.isWide) private var isWide

    var body: some View {
        VStack(spacing: Theme.Space.l) {
            // The station's light: the radio is what this is about.
            ArchMark(size: isWide ? 56 : 64)
            Text("Better Radio")
                .desktopFont(Tokens.Size.pageTitle.size, design: .serif, phone: .serif(.largeTitle))
                .accessibilityAddTraits(.isHeader)
            Text("To find music that sounds alike, Jukebox looks up artist and song names on Last.fm and MusicBrainz. Nothing about you is sent.")
                .desktopFont(Tokens.Size.body15.size, phone: .body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: Theme.Space.s) {
                Button {
                    choose(true)
                } label: {
                    Text("Turn On")
                        .frame(maxWidth: isWide ? 200 : .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("betterRadio.turnOn")
                Button("Not Now") { choose(false) }
                    .controlSize(.large)
                    .accessibilityIdentifier("betterRadio.notNow")
            }
            .padding(.top, Theme.Space.s)
        }
        .padding(isWide ? Theme.Space.xxl : Theme.Space.xl)
        .frame(maxWidth: isWide ? 440 : .infinity)
        // Asked, not dismissed: a swipe would leave it unanswered.
        .interactiveDismissDisabled()
        #if os(iOS)
        .presentationDetents([.medium])
        #endif
    }

    /// Both together, Last.fm and AcousticBrainz, and the choice kept: the
    /// sheet's binding (radioChoiceMade) then closes it.
    private func choose(_ on: Bool) {
        settings.enhanceRadio = on
        settings.radioChoiceMade = true
        radio.enhanceRadioChanged()
    }
}
