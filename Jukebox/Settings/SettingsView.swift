// Settings, in pages: a short list, each row opening one page, as the
// system's own Settings is laid out. The photographer, 19 November 2026,
// looking at the iPhone's one long sheet: "Voor een volgende versie moeten
// we ff de instellingen netjes opdelen in paginas, apple hig manier volgens
// mij kan dat ook op de gnome hig manier op Linux". The same pages in the
// same order as Linux's Preferences (Preferences.swift); on the Mac, its
// Settings window's toolbar of tabs.
//
// Each page a Form as the system's Settings draws one, each section its own
// view so a change in one (the library's progress, the Last.fm check)
// redraws only that one. A section's header only where it tells something
// the page's title does not (docs/design/tells.md, 5); nothing of Jukebox's
// own in them (4: no tracked uppercase labels).
//
// In a wide window (the iPad, the Mac, the iPad app on a Mac) the rows are
// Linux's (16-preferences.png): 15 rather than 13, the groups' titles bold
// and in sentence case ("ik wil dat de linux app en de apple app 1:1 op
// elkaar lijken", the photographer, 14 November 2026).
//
// On the Mac a settings window as the Mac's own apps have one: "op mac zijn
// de settings een beetje een tyfusbende geworden" (the photographer, 21
// November 2026, Accounts' buttons each on a row of their own, tinted,
// between the facts). So facts are LabeledContent rows; a section's actions
// stand together at its end, trailing, in the system's own push buttons
// (SettingsActions); each footer sits under the rows it speaks of. Every
// row, its words, its order and its footer, on every client:
// docs/design/settings.md.

import JukeboxKit
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Settings' pages, in their order on every client. Linux's Preferences has
/// the same ones but About, which is its own About window there, as the
/// Mac's is its app menu's About Jukebox.
enum SettingsPage: String, CaseIterable, Hashable {
    case accounts, playback, radio, library, downloads, privacy, about

    var title: LocalizedStringKey {
        switch self {
        case .accounts: "Accounts"
        case .playback: "Playback"
        case .radio: "Radio"
        case .library: "Library"
        case .downloads: "Downloads"
        case .privacy: "Privacy"
        case .about: "About"
        }
    }

    /// The app's own symbols where it has one (Home's person for Settings,
    /// Radio's waves and the Library's stack from the tabs), else the
    /// system Settings' own.
    var symbol: String {
        switch self {
        case .accounts: "person.crop.circle"
        case .playback: "play.circle"
        case .radio: "dot.radiowaves.left.and.right"
        case .library: "square.stack"
        case .downloads: "arrow.down.circle"
        case .privacy: "hand.raised"
        case .about: "info.circle"
        }
    }
}

extension EnvironmentValues {
    /// Closes Settings from any page: in a page pushed on the sheet's
    /// stack, a page's own `dismiss` would only go back to the list.
    @Entry var closeSettings: DismissAction? = nil
}

struct SettingsView: View {
    /// The Mac's Settings window (⌘,) rather than a sheet: no Done, the
    /// window has its own close button.
    let asWindow: Bool

    @Environment(\.dismiss) private var dismiss
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    init(asWindow: Bool = false) {
        self.asWindow = asWindow
    }

    var body: some View {
        #if os(macOS)
        Group {
            if asWindow {
                tabs
                    .countsScreen("settings")
            } else {
                sheet
                    .frame(width: 560)
                    .frame(minHeight: 400, idealHeight: 720)
            }
        }
        .environment(\.closeSettings, dismiss)
        #else
        sheet
            .environment(\.closeSettings, dismiss)
        #endif
    }

    #if os(macOS)
    /// The Mac's Settings window as its own apps have one: a toolbar of
    /// tabs, a page each. About is the app menu's About Jukebox.
    private var tabs: some View {
        TabView {
            ForEach(SettingsPage.allCases.filter { $0 != .about }, id: \.self) { page in
                SettingsPageForm(page: page)
                    // A settings window's width, not a page's, as Linux's
                    // dialog is: the rows' words and their controls within
                    // one glance.
                    .frame(width: 560)
                    .frame(minHeight: 360, idealHeight: 560)
                    .tabItem { Label(page.title, systemImage: page.symbol) }
                    .tag(page)
            }
        }
    }
    #endif

    private var sheet: some View {
        NavigationStack {
            SettingsRoot()
                .navigationTitle("Settings")
                .inlineTitle()
                .navigationDestination(for: SettingsPage.self) { page in
                    SettingsPageForm(page: page)
                        .navigationTitle(page.title)
                        .inlineTitle()
                        .modifier(SettingsDone())
                }
                .modifier(SettingsDone())
        }
        .countsScreen("settings")
        #if os(iOS)
        // A sheet on the iPad may call itself compact, being narrower than
        // the window: it is Linux's Preferences on every iPad all the same,
        // so its pages are told wide.
        .environment(\.horizontalSizeClass, settingsOnPad ? .regular : horizontalSizeClass)
        #endif
    }
}

/// Done on the list and on every page: the sheet closes from anywhere.
private struct SettingsDone: ViewModifier {
    @Environment(\.closeSettings) private var closeSettings

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { closeSettings?.callAsFunction() }
            }
        }
    }
}

private var settingsOnPad: Bool {
    #if os(iOS)
    return UIDevice.current.userInterfaceIdiom == .pad
    #else
    return false
    #endif
}

/// The list of pages: each its symbol in the accent and its name, as the
/// system's Settings lists its own, in three groups (whose music; how it
/// plays and what is kept; what is told and who made it). Beside Accounts
/// the server signed in to, as Settings shows the Wi-Fi joined.
private struct SettingsRoot: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Form {
            Section {
                row(.accounts, detail: app.credentials.map { ServerWords.name(of: $0) })
            }
            Section {
                ForEach([SettingsPage.playback, .radio, .library, .downloads], id: \.self) { page in
                    row(page)
                }
            }
            Section {
                row(.privacy)
                row(.about)
            }
        }
        .modifier(SettingsFormLook())
    }

    private func row(_ page: SettingsPage, detail: String? = nil) -> some View {
        NavigationLink(value: page) {
            LabeledContent {
                if let detail {
                    Text(verbatim: detail)
                        .lineLimit(1)
                }
            } label: {
                Label {
                    Text(page.title)
                } icon: {
                    Image(systemName: page.symbol)
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        // The walk's way in (ScreenshotTests), whatever the row's words.
        .accessibilityIdentifier("settings.page.\(page.rawValue)")
    }
}

/// One page: its sections in the order the one long sheet had them. Not
/// private: the Mac's snapshots draw each page alone (Snapshots.swift), as
/// an offscreen window has no toolbar for the tabs.
struct SettingsPageForm: View {
    let page: SettingsPage

    @Environment(\.isWide) private var isWide

    var body: some View {
        Form {
            switch page {
            case .accounts:
                SettingsAccountSection()
            case .playback:
                SettingsPlaybackSection()
                // Wide, the lyrics' row is Playback's own, as on Linux.
                if !isWide { SettingsLyricsSection() }
            case .radio:
                SettingsRadioSection()
                SettingsEnhanceRadioSection()
            case .library:
                SettingsLibrarySection()
                SettingsPagesSection(hasSidebar: isWide || settingsOnPad)
            case .downloads:
                SettingsDownloadsSection()
            case .privacy:
                NotCountedSection()
                SettingsHistorySection()
                SettingsPrivacySection()
            case .about:
                SettingsAboutSection()
            }
        }
        .modifier(SettingsFormLook())
    }
}

/// Wide, Linux's Preferences: the rows in 15, not the Mac's 13; the lines
/// under them 13 (SettingsDetailLabel). On the Mac libadwaita's boxed rows
/// and switches are the Mac's own: the grouped form, as System Settings
/// draws its panes.
private struct SettingsFormLook: ViewModifier {
    @Environment(\.isWide) private var isWide

    func body(content: Content) -> some View {
        Group {
            if isWide || settingsOnPad {
                content.desktopFont(Tokens.Size.body15.size)
            } else {
                content
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        .toggleStyle(.switch)
        #endif
    }
}

// MARK: - Account

private struct SettingsAccountSection: View {
    @Environment(AppModel.self) private var app
    @Environment(\.closeSettings) private var closeSettings
    @State private var isConfirmingSignOut = false
    /// Another saved account, asked about before it is signed out of.
    @State private var leaving: ServerCredentials?
    @State private var isAdding = false
    /// Why the switch to a card did not happen, under that card: its
    /// folder's name and the words.
    @State private var switchProblem: (account: String, words: String)?

    init() {}

    /// Each account kept as a card, the cards a radio group: one is always
    /// the one signed in. The photographer, 21 November 2026: "kun je op
    /// alle versies een toegevoegde server als een soort card tonen die
    /// werken als een soort radiobutton (er moet altijd 1 server actief
    /// zijn)". Each card its own section, so the grouped form draws it as
    /// one (no card of Jukebox's own in the system's: tells 6). Then Add
    /// Account… and Sign Out… of the one signed in, as on Linux.
    var body: some View {
        ForEach(cards, id: \.self) { account in
            let isActive = app.credentials?.isSameAccount(as: account) == true
            let key = OfflinePaths.account(for: account)
            Section {
                AccountCard(account: account, isActive: isActive, choose: { choose(account) }) {
                    AccountRadio(isOn: isActive)
                }
                .disabled(app.isSwitching)
                .swipeActions {
                    if !isActive {
                        Button("Sign Out", role: .destructive) { leaving = account }
                    }
                }
                .contextMenu {
                    if !isActive {
                        Button("Sign Out", role: .destructive) { leaving = account }
                    }
                }
            } footer: {
                // Why the switch to this one did not happen; under the one
                // signed in, the server's own note (On Your Jukebox is in the
                // library now; whether it counts every device is the
                // server's doing).
                if let switchProblem, switchProblem.account == key {
                    Text(switchProblem.words)
                } else if isActive, let note = ServerWords.playbackReportingNote(account) {
                    Text(note)
                }
            }
        }
        Section {
            SettingsActions {
                // Linux's words: "…", as each asks something before it acts.
                Button("Add Account…") {
                    isAdding = true
                }
                .disabled(app.credentials == nil)
                .sheet(isPresented: $isAdding) {
                    OnboardingView(isAdding: true)
                }
                // A dialog of its own, on another button than Sign Out's:
                // one view, one confirmation dialog.
                .confirmationDialog(leavingTitle, isPresented: Binding(get: { leaving != nil },
                                                                       set: { if !$0 { leaving = nil } }),
                                    titleVisibility: .visible) {
                    Button("Sign Out", role: .destructive) {
                        if let leaving { Task { await app.signOut(leaving) } }
                    }
                } message: {
                    Text("Jukebox forgets its library, recent stations and downloaded songs on this \(Device.model). The music plays on.")
                }
                // Of the card signed in: with others kept the next one is
                // signed in to (AppModel.signOut), with none the welcome.
                Button("Sign Out…", role: .destructive) {
                    isConfirmingSignOut = true
                }
                // The Mac's Settings window opens signed out too (⌘, from the
                // sign-in screen): nothing to sign out of then.
                .disabled(app.credentials == nil)
                .confirmationDialog(signOutTitle, isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
                    Button("Sign Out", role: .destructive) {
                        // The sheet first, so it does not hang over the swap
                        // to the sign-in screen, or the next account's Home.
                        closeSettings?.callAsFunction()
                        Task { await app.signOut() }
                    }
                } message: {
                    Text(signOutMessage)
                }
            }
        }
    }

    /// The accounts kept, in the order they were added; the session alone
    /// before the list knows it (the Mac's snapshots sign in past it).
    private var cards: [ServerCredentials] {
        if app.accounts.saved.isEmpty, let credentials = app.credentials { return [credentials] }
        return app.accounts.saved
    }

    /// Another card chosen: its server asked first (AppModel.switchAccount);
    /// switched, its Home with nothing over it; not, the words under it and
    /// the radio stays on the one signed in. There is no choosing none.
    private func choose(_ account: ServerCredentials) {
        guard app.credentials?.isSameAccount(as: account) != true, !app.isSwitching else { return }
        switchProblem = nil
        Task {
            if let words = await app.switchAccount(to: account) {
                switchProblem = (OfflinePaths.account(for: account), words)
            } else {
                closeSettings?.callAsFunction()
            }
        }
    }

    /// The menus' words too (AccountMenu.swift's SignOutWords).
    private var signOutTitle: Text { SignOutWords.title(app) }

    private var leavingTitle: Text {
        guard let leaving else { return Text("Sign out?") }
        return Text("Sign out of \(ServerWords.name(of: leaving)) as \(leaving.userName)?")
    }

    private var signOutMessage: String { SignOutWords.message(app) }
}

// MARK: - Playback

private struct SettingsPlaybackSection: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppModel.self) private var app
    @Environment(\.isWide) private var isWide

    init() {}

    var body: some View {
        @Bindable var settings = settings
        Section {
            if runsOnMac {
                // A Mac has no mobile network of its own: what costs data
                // there is a phone's hotspot or Low Data Mode (NetworkCost),
                // so the words say that.
                Picker("Streaming", selection: shown($settings.wifiQuality)) {
                    qualityOptions
                }
                Picker("Streaming on a Hotspot", selection: shown($settings.cellularQuality)) {
                    qualityOptions
                }
            } else {
                // Music's own words for the two.
                Picker("Wi-Fi Streaming", selection: shown($settings.wifiQuality)) {
                    qualityOptions
                }
                Picker("Cellular Streaming", selection: shown($settings.cellularQuality)) {
                    qualityOptions
                }
            }
            // The pickers' quality is the target (QualitySteps); Linux's words.
            Toggle(isOn: $settings.adjustsToConnection) {
                SettingsDetailLabel(title: "Adjust to the Connection",
                                    detail: "When a song has to wait for the network, the next ones stream lower until it holds again.")
            }
        } footer: {
            // Under the pickers it explains, as Linux's Streaming Quality's.
            Text("Original plays your files as they are. The others have \(app.serverKindName) convert them to \(format) at that rate, which uses less data.\(opus ? StreamQuality.efficientNote : "")")
        }
        Section {
            if !isWide {
                normalizeRow
            }
            Toggle(isOn: $settings.autoplay) {
                // Linux's words: what it plays, not a promise.
                SettingsDetailLabel(title: "Autoplay",
                                    detail: "When an album or a playlist ends, play on with a station from its last song.")
            }
            Picker(selection: $settings.crossfade) {
                ForEach(AppSettings.crossfades, id: \.self) { seconds in
                    Text(seconds == 0 ? "Off" : "\(seconds) s").tag(seconds)
                }
            } label: {
                SettingsDetailLabel(title: "Crossfade",
                                    detail: "A song fades out and the next fades in. Songs that follow each other on an album never fade.")
            }
            // In the player at launch, paused, rather than in Home's notice
            // (HandoffStore).
            Toggle(isOn: $settings.resumeOnLaunch) {
                SettingsDetailLabel(title: "Continue Where You Left Off",
                                    detail: "When Jukebox opens, the song you last played, here or on another device, is ready to play.")
            }
            if isWide {
                // Linux's order, and its lyrics row here rather than a
                // section of their own; the row says what LRCLIB is sent.
                normalizeRow
                Toggle(isOn: $settings.findLyricsOnline) {
                    SettingsDetailLabel(title: "Find Lyrics Online",
                                        detail: "When your server has no lyrics for a song, ask LRCLIB (lrclib.net), with its title, artist, album and length.")
                }
            }
            // Now Playing's motion (NowPlayingGround.swift): off, the page
            // is sketch D1, the still wall, as it is anyway in Low Power
            // Mode and with Reduce Motion.
            Toggle(isOn: $settings.spinRecord) {
                SettingsDetailLabel(title: "Spin the Record",
                                    detail: "Now Playing's record turns, and its grooves move on with each song. Off, as in Low Power Mode and with Reduce Motion, it stands still on a wall of the cover's colours.")
            }
        }
    }

    /// Only where the server gives songs a loudness (Jellyfin 10.9+, an
    /// OpenSubsonic server's ReplayGain): elsewhere the switch would do
    /// nothing, so it is off and says why.
    @ViewBuilder private var normalizeRow: some View {
        @Bindable var settings = settings
        if app.can(.replayGain) {
            Toggle(isOn: $settings.normalizeVolume) {
                SettingsDetailLabel(title: "Normalize Volume", detail: normalizeDetail)
            }
        } else {
            Toggle(isOn: .constant(false)) {
                SettingsDetailLabel(title: "Normalize Volume",
                                    detail: "\(app.serverKindName) doesn’t give songs a loudness, so each plays as it is.")
            }
            .disabled(true)
        }
    }

    /// AAC from Jellyfin, MP3 from a Subsonic server.
    private var format: String {
        app.credentials?.kind.convertedFormat ?? "AAC"
    }

    /// Jellyfin measures each song itself; a Subsonic server passes on what
    /// the files' ReplayGain tags say.
    private var normalizeDetail: LocalizedStringKey {
        if app.credentials?.kind.isSubsonic == true {
            return "Play every song at the loudness its ReplayGain tags give, so loud and quiet records sit side by side."
        }
        return "Play every song at the loudness Jellyfin measured, so loud and quiet records sit side by side."
    }

    private var qualityOptions: some View {
        ForEach(StreamQuality.offered(opus: opus), id: \.self) { quality in
            label(for: quality)
                .tag(quality)
        }
    }

    /// Whether this server makes Opus, so Efficient is offered.
    private var opus: Bool { app.can(.opusStream) }

    /// The picker's selection: a kept Efficient reads as Low on a server
    /// without Opus, so the picker always has its row.
    private func shown(_ quality: Binding<StreamQuality>) -> Binding<StreamQuality> {
        Binding(get: { quality.wrappedValue.shown(opus: opus) }, set: { quality.wrappedValue = $0 })
    }

    private func label(for quality: StreamQuality) -> Text {
        switch quality {
        case .original: Text("Original")
        case .high: Text("High (320 kbit/s)")
        case .normal: Text("Normal (256 kbit/s)")
        case .efficient: Text("Efficient (Opus, 128 kbit/s)")
        case .low: Text("Low (128 kbit/s)")
        }
    }
}

// MARK: - Downloads

/// Music on the phone (OfflineStore). The photographer, asked whether the app
/// should "automatisch bewaren wat je vaak of kort geleden hebt gespeeld, tot
/// een grootte die je kiest", answered "Alle drie" (8 November 2026): Keep
/// Songs I Play, on at 5 GB, beside the albums, playlists and mixes chosen on
/// their pages. The space each takes, and Remove All Downloads, asked first.
private struct SettingsDownloadsSection: View {
    @Environment(AppModel.self) private var app
    @Environment(AppSettings.self) private var settings
    @Environment(OfflineStore.self) private var offline
    @State private var isConfirmingRemoveAll = false

    init() {}

    var body: some View {
        @Bindable var settings = settings
        Section {
            if !offline.downloadsAllowed {
                // The server's admin turned downloads off for this user
                // (Jellyfin's "Allow media downloading", a Subsonic
                // server's download role): said once, as a fact.
                Text("\(serverName) doesn’t allow downloads for this account.")
                    .foregroundStyle(.secondary)
            }
            Toggle(isOn: $settings.keepSongs) {
                SettingsDetailLabel(title: "Keep Songs I Play",
                                    detail: "Songs you play often or lately stay on this \(Device.model), to play without a connection.")
            }
            if settings.keepSongs {
                Picker("Up To", selection: $settings.keepLimitGB) {
                    ForEach(AppSettings.keepLimits, id: \.self) { gigabytes in
                        Text("\(gigabytes) GB").tag(gigabytes)
                    }
                }
            }
            Picker("Download Quality", selection: $settings.downloadQuality) {
                ForEach(DownloadQuality.allCases, id: \.self) { quality in
                    label(for: quality)
                        .tag(quality)
                }
            }
            if runsOnMac {
                // As Streaming on a Hotspot above.
                Toggle("Download on a Hotspot", isOn: $settings.downloadOverCellular)
            } else {
                // Music's words, as Cellular Streaming above.
                Toggle("Download over Cellular", isOn: $settings.downloadOverCellular)
            }
        } footer: {
            // Under the choices it explains, as Linux's.
            qualityFooter
        }
        // What the downloads take, and the button that frees it, in a
        // section of their own, as Linux's.
        Section {
            LabeledContent("Downloaded") {
                Text(offline.chosenBytes, format: .byteCount(style: .file))
            }
            LabeledContent("Kept") {
                Text(keptLine)
            }
            if let status {
                LabeledContent(status) {
                    Text(LibraryText.songs(offline.queuedCount))
                }
            }
            SettingsActions {
                Button("Remove All Downloads", role: .destructive) {
                    isConfirmingRemoveAll = true
                }
                .disabled(offline.songCount == 0 && offline.queuedCount == 0)
                .confirmationDialog("Remove all downloads from this \(Device.model)?",
                                    isPresented: $isConfirmingRemoveAll, titleVisibility: .visible) {
                    Button("Remove All Downloads", role: .destructive) {
                        offline.removeAll()
                    }
                } message: {
                    Text("Every downloaded album, playlist, mix and kept song goes, and Keep Songs I Play is turned off. They still play from your server.")
                }
            }
        }
    }

    /// The kit's rate for each quality, so the words and the files agree.
    private func label(for quality: DownloadQuality) -> Text {
        let kilobits = (quality.aacBitrate ?? 0) / 1000
        switch quality {
        case .original: return Text("Original")
        case .high: return Text("High (\(kilobits) kbit/s)")
        case .normal: return Text("Normal (\(kilobits) kbit/s)")
        }
    }

    private var serverName: String {
        app.credentials?.serverName ?? String(localized: "Your server")
    }

    /// What each quality means on this kind of server: what the phone
    /// cannot play is converted even at Original, by Jellyfin to AAC at 256
    /// (docs/OFFLINE.md), by a Subsonic server to MP3 at 320
    /// (SubsonicClient.downloadURL); High and Normal to AAC or MP3.
    private var qualityFooter: Text {
        let model = Device.model
        if runsOnMac {
            if app.credentials?.kind.convertedFormat == "MP3" {
                return Text("Original is each file as it is, or MP3 at 320 kbit/s when this \(model) cannot play it; High and Normal have \(app.serverKindName) convert songs to MP3 at that rate, so more of them fit. Songs wait while this \(model) is on a hotspot unless Download on a Hotspot is on; kept songs wait in Low Power Mode.")
            }
            return Text("Original is each file as it is, or AAC at 256 kbit/s when this \(model) cannot play it; High and Normal have \(app.serverKindName) convert songs to AAC at that rate, so more of them fit. Songs wait while this \(model) is on a hotspot unless Download on a Hotspot is on; kept songs wait in Low Power Mode.")
        }
        if app.credentials?.kind.convertedFormat == "MP3" {
            return Text("Original is each file as it is, or MP3 at 320 kbit/s when this \(model) cannot play it; High and Normal have \(app.serverKindName) convert songs to MP3 at that rate, so more of them fit. Songs download on Wi-Fi unless Download over Cellular is on; kept songs wait in Low Power Mode.")
        }
        return Text("Original is each file as it is, or AAC at 256 kbit/s when this \(model) cannot play it; High and Normal have \(app.serverKindName) convert songs to AAC at that rate, so more of them fit. Songs download on Wi-Fi unless Download over Cellular is on; kept songs wait in Low Power Mode.")
    }

    /// "1.2 GB of 5 GB": what the keep holds, against its limit.
    private var keptLine: String {
        let kept = offline.keptBytes.formatted(.byteCount(style: .file))
        guard settings.keepSongs else { return kept }
        return String(localized: "\(kept) of \(settings.keepLimitGB) GB")
    }

    /// What the songs still to come are doing, when there are any.
    private var status: LocalizedStringKey? {
        guard offline.queuedCount > 0 else { return nil }
        switch offline.waiting {
        case .wifi?: return "Waiting for Wi-Fi"
        case .network?: return "Waiting for a Connection"
        case .notAllowed?: return "Paused"
        case nil:
            if offline.isLowPower && !hasChosenQueued { return "Paused in Low Power Mode" }
            return "Downloading"
        }
    }

    private var hasChosenQueued: Bool {
        offline.wanted.contains { $0.isChosen }
    }
}

// MARK: - Radio

private struct SettingsRadioSection: View {
    @Environment(AppSettings.self) private var settings
    @Environment(RadioController.self) private var radio
    @State private var isDragging = false

    init() {}

    var body: some View {
        @Bindable var settings = settings
        Section {
            #if os(macOS)
            // The Mac's own slider: its name at the start of the row and its
            // two ends beside it, as System Settings sets a dial.
            Slider(value: $settings.adventurousness, in: 0...1, label: {
                Text("Adventurousness")
            }, minimumValueLabel: {
                Text("Familiar")
            }, maximumValueLabel: {
                Text("Adventurous")
            }, onEditingChanged: { editing in
                editingChanged(editing)
            })
            .accessibilityValue(dialValue)
            // VoiceOver's steps and the arrow keys move it without a drag.
            .onChange(of: settings.adventurousness) { _, _ in
                if !isDragging { radio.adventurousnessChanged() }
            }
            #else
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                // The slider's own label is VoiceOver's; this one is the eyes'.
                Text("Adventurousness")
                    .accessibilityHidden(true)
                Slider(value: $settings.adventurousness, in: 0...1, label: {
                    Text("Adventurousness")
                }, onEditingChanged: { editing in
                    editingChanged(editing)
                })
                .accessibilityValue(dialValue)
                HStack {
                    Text("Familiar")
                    Spacer()
                    Text("Adventurous")
                }
                .desktopFont(Tokens.Size.fact13.size, phone: .footnote)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            }
            .padding(.vertical, Theme.Space.xs)
            // VoiceOver's swipes move the slider without a drag, so without
            // an end of editing either: each of those steps tells the radio.
            .onChange(of: settings.adventurousness) { _, _ in
                if !isDragging { radio.adventurousnessChanged() }
            }
            #endif
        } footer: {
            Text("Familiar stays close to where a station started and to songs you know. Adventurous goes further out and plays more that is new to you.")
        }
    }

    private func editingChanged(_ editing: Bool) {
        isDragging = editing
        // Once, when the finger lifts: the radio chooses its next songs
        // again, and every step of a drag would be wasted. So too the count
        // (Stats): where it was let go.
        if !editing {
            radio.adventurousnessChanged()
            Stats.track(.dialChanged, ["value": Stats.dial(settings.adventurousness)])
        }
    }

    private var dialValue: Text {
        let value = settings.adventurousness
        if value < 0.25 { return Text("Familiar") }
        if value < 0.5 { return Text("Mostly familiar") }
        if value < 0.75 { return Text("Somewhat adventurous") }
        return Text("Adventurous")
    }
}

// MARK: - Enhance Radio

/// Enhance Radio (`AppSettings.enhanceRadio`): Last.fm for who sounds like
/// whom, MusicBrainz and AcousticBrainz for how each song sounds, one
/// choice for both: "of lastfm en dit aan of beide uit" (the photographer,
/// 24 November 2026), as Better Radio asks it after signing in. Under it,
/// when on, the listener's Last.fm name, optional. The key is Jukebox's
/// own, never the listener's: "Kan die api ding … ook uit de app dan?"
/// (24 November 2026). As Linux's Preferences › Radio.
private struct SettingsEnhanceRadioSection: View {
    private enum Status: Equatable {
        case idle
        case checking
        case saved
        case problem(String)
    }

    @Environment(AppSettings.self) private var settings
    @Environment(RadioController.self) private var radio
    @Environment(\.isWide) private var isWide
    /// The listener's Last.fm name, optional: typed, saved with Return or
    /// on leaving, Last.fm asked, so the clock has their scrobbles from day
    /// one. Emptied, it is gone. Not a secret, so shown as typed.
    @State private var userDraft: String?
    @State private var userStatus: Status = .idle
    @State private var userTask: Task<Void, Never>?

    init() {}

    private var detail: LocalizedStringKey {
        "To find music that sounds alike, Jukebox sends the artist, song and album names in your library to Last.fm and ListenBrainz, and asks AcousticBrainz how each song sounds. Your Last.fm username goes too, if you add one. Nothing about your music server, your sign-in or this device is sent."
    }

    /// A build without Jukebox's key has nothing to offer here.
    @ViewBuilder var body: some View {
        if AppSettings.canEnhanceRadio { section }
    }

    private var section: some View {
        @Bindable var settings = settings
        return Section {
            // Wide, the line in the row, as Linux's subtitle and Playback's
            // rows; on the iPhone the section's footer.
            Toggle(isOn: $settings.enhanceRadio) {
                if isWide {
                    SettingsDetailLabel(title: "Enhance Radio", detail: detail)
                } else {
                    Text("Enhance Radio")
                }
            }
            .onChange(of: settings.enhanceRadio) { _, _ in radio.enhanceRadioChanged() }
            if settings.hasLastFM {
                TextField("Last.fm Username", text: userText, prompt: Text("Optional"))
                    .plainTextEntry()
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .disabled(userStatus == .checking)
                    .onSubmit(saveUser)
                    .onDisappear(perform: saveUser)
                statusRow
            }
        } footer: {
            // A Last.fm out of reach, said once and calmly by the switch,
            // as Linux's (RadioController.lastFMTrouble).
            if !isWide || radio.lastFMTrouble != nil || settings.hasLastFM {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    if !isWide { Text(detail) }
                    if settings.hasLastFM {
                        Text("With your Last.fm username, the radio learns when you play what from your scrobbles. Nothing is written to Last.fm.")
                    }
                    if let trouble = radio.lastFMTrouble { Text(trouble.text) }
                }
            }
        }
    }

    /// The field: the name saved until it is typed in.
    private var userText: Binding<String> {
        Binding {
            userDraft ?? settings.lastFMUser
        } set: { typed in
            userDraft = typed
            // Typing again: the last answer was about another name.
            if case .problem = userStatus { userStatus = .idle }
        }
    }

    /// Last.fm asked; only a name it knows, with plays it shows, is kept.
    /// Emptied, the name goes: the clock then reads this device alone.
    private func saveUser() {
        // The row leaves when the switch is off: nothing is asked then.
        guard settings.hasLastFM, let typed = userDraft.map(Self.trimmed), userStatus != .checking else { return }
        guard typed != Self.trimmed(settings.lastFMUser) else {
            userDraft = nil
            return
        }
        guard !typed.isEmpty else {
            settings.lastFMUser = ""
            radio.lastFMKeyChanged()
            userDraft = nil
            userStatus = .idle
            return
        }
        let key = settings.lastFMKey
        userTask?.cancel()
        userStatus = .checking
        userTask = Task {
            let check = await LastFMClient(apiKey: key).validateUser(typed)
            guard !Task.isCancelled else { return }
            guard check == .accepted else {
                userStatus = .problem(check.problem ?? "")
                return
            }
            settings.lastFMUser = typed
            radio.lastFMKeyChanged()
            userDraft = nil
            userStatus = .saved
        }
    }

    @ViewBuilder private var statusRow: some View {
        switch userStatus {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: Theme.Space.s) {
                ProgressView()
                    #if os(macOS)
                    // A row's spinner, not a page's.
                    .controlSize(.small)
                    #endif
                Text("Checking…")
            }
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
        case .saved:
            Label {
                Text("Last.fm knows this listener")
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        case let .problem(words):
            Label {
                Text(words)
            } icon: {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Lyrics

/// LRCLIB, when the server has no lyrics for a song: on unless turned off,
/// as the photographer asked for lyrics ("Kun je ook lyrics toevoegen", 8
/// November 2026) and most libraries have none of their own. The footer
/// says what leaves the phone, as Last.fm's does.
private struct SettingsLyricsSection: View {
    @Environment(AppSettings.self) private var settings

    init() {}

    var body: some View {
        @Bindable var settings = settings
        Section {
            Toggle("Find Lyrics Online", isOn: $settings.findLyricsOnline)
        } header: {
            SettingsHeader("Lyrics")
        } footer: {
            Text("When your server has no lyrics for a song, Jukebox looks them up on LRCLIB (lrclib.net), a free and open lyrics database. It sends the song's title, artist, album and length.")
        }
    }
}

// MARK: - Pages

/// Which pages the sidebar and the tabs show (AppSettings.hiddenPages): the
/// photographer, 15 November 2026, "kan je zelf bepalen hoe minimalistisch je
/// alles wilt hebben". In the sidebar's order; Home has no switch. The
/// playlists' own switch only where there is a sidebar: in the tabs it would
/// do nothing.
private struct SettingsPagesSection: View {
    let hasSidebar: Bool

    @Environment(AppSettings.self) private var settings

    init(hasSidebar: Bool) {
        self.hasSidebar = hasSidebar
    }

    var body: some View {
        Section {
            ForEach(AppSettings.Page.allCases, id: \.self) { page in
                if page != .sidebarPlaylists || hasSidebar {
                    Toggle(title(page), isOn: Binding(get: { settings.shows(page) },
                                                      set: { settings.setShows(page, $0) }))
                }
            }
        } header: {
            SettingsHeader("Pages")
        } footer: {
            Text("Home is always there. Pages that are off stay reachable from Home and Search.")
        }
    }

    private func title(_ page: AppSettings.Page) -> LocalizedStringKey {
        switch page {
        case .radio: "Radio"
        case .albums: "Albums"
        case .artists: "Artists"
        case .songs: "Songs"
        case .playlists: "Playlists"
        case .favorites: "Favorites"
        case .genres: "Genres"
        case .recentlyAdded: "Recently Added"
        case .downloaded: "Downloaded"
        case .sidebarPlaylists: "Playlists in the Sidebar"
        }
    }
}

// MARK: - Library

private struct SettingsLibrarySection: View {
    @Environment(LibraryStore.self) private var library

    init() {}

    var body: some View {
        Section {
            LabeledContent("Songs") { Text(library.tracks.count, format: .number) }
            LabeledContent("Albums") { Text(library.albums.count, format: .number) }
            LabeledContent("Artists") { Text(library.artists.count, format: .number) }
            if let lastLoaded = library.lastLoaded {
                LabeledContent("Last Loaded") {
                    // "5 minutes ago" stays true while the sheet is open.
                    TimelineView(.everyMinute) { _ in
                        Text(lastLoaded, format: .relative(presentation: .named))
                    }
                }
            }
            #if os(macOS)
            // The Mac's form draws a button as a push button: its progress
            // sits before it, not inside it, at the section's end.
            SettingsActions {
                loadingProgress
                Button {
                    Task { await library.refresh() }
                } label: {
                    isLoading ? Text("Refreshing Library…") : Text("Refresh Library")
                }
                .disabled(isLoading)
            }
            #else
            Button {
                Task { await library.refresh() }
            } label: {
                refreshLabel
            }
            .disabled(isLoading)
            #endif
        } footer: {
            if let failure {
                Text(failure)
            } else {
                Text("Jukebox keeps a copy of the list of your music, so it opens at once. It reads the server again each time it starts.")
            }
        }
    }

    @ViewBuilder private var refreshLabel: some View {
        HStack(spacing: Theme.Space.s) {
            if isLoading {
                Text("Refreshing Library…")
            } else {
                Text("Refresh Library")
            }
            Spacer(minLength: 0)
            loadingProgress
        }
    }

    @ViewBuilder private var loadingProgress: some View {
        if isLoading {
            if let progress {
                Text(progress, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProgressView()
                #if os(macOS)
                .controlSize(.small)
                #endif
        }
    }

    private var isLoading: Bool {
        if case .loading = library.state { return true }
        return false
    }

    private var progress: Double? {
        if case let .loading(progress) = library.state { return progress }
        return nil
    }

    private var failure: String? {
        if case let .failed(message) = library.state { return message }
        return nil
    }
}

// MARK: - History

private struct SettingsHistorySection: View {
    @Environment(HistoryStore.self) private var history
    @Environment(LibraryStore.self) private var library
    @Environment(AppSettings.self) private var settings
    @Environment(MixStore.self) private var mixes
    @State private var isConfirmingClear = false

    init() {}

    var body: some View {
        let count = history.history.events.count
        Section {
            LabeledContent("Plays Remembered") { Text(count, format: .number) }
            SettingsActions {
                Button("Clear Listening History", role: .destructive) {
                    isConfirmingClear = true
                }
                .disabled(count == 0)
                .confirmationDialog("Clear your listening history?", isPresented: $isConfirmingClear,
                                    titleVisibility: .visible) {
                    Button("Clear Listening History", role: .destructive) {
                        history.clear()
                        // Today's mixes were made from what is now forgotten.
                        Task { await mixes.rebuild(library: library, history: history, settings: settings) }
                    }
                } message: {
                    Text("The radio and your mixes start learning your taste again from your library and favorites. Play counts on the server stay as they are.")
                }
            }
        } header: {
            SettingsHeader("History")
        } footer: {
            Text("What you play, skip and give a thumbs up or down to is how the radio and your mixes learn your taste. It stays on this \(Device.model).")
        }
    }
}

// MARK: - Privacy

/// The anonymous usage counts (Stats, docs/STATS.md), on unless turned off
/// here: the photographer's choice, "alles tracken wat je mag zonder cookie
/// melding" (8 November 2026), as the app sets no cookie and keeps no id for
/// them. The footer says what is counted, and what never is, as
/// Last.fm's and Lyrics' footers say what leaves the phone.
private struct SettingsPrivacySection: View {
    @Environment(AppSettings.self) private var settings

    init() {}

    var body: some View {
        @Bindable var settings = settings
        Section {
            Toggle("Share Anonymous Usage", isOn: $settings.shareUsage)
        } footer: {
            Text("Jukebox counts which screens and features are used, never titles, artists, searches, server addresses or names, on the developer's own server, without cookies or a device id. It helps decide what to improve.")
        }
    }
}

// MARK: - About

private struct SettingsAboutSection: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Section {
            HStack(spacing: Theme.Space.m) {
                ShellAppMark(side: 44)
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    Text("Jukebox")
                        .desktopFont(Tokens.Size.body15.size, weight: .bold, phone: .headline)
                    // Linux's About's words, and the Mac's About Jukebox's.
                    Text("Music from your Jellyfin, Emby, Plex, Navidrome or other Subsonic server, with a radio that plays on from anything.")
                        .desktopFont(Tokens.Size.fact13.size, phone: .subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, Theme.Space.xs)
            .accessibilityElement(children: .combine)
            LabeledContent("Version", value: version)
        }
        // Help & Feedback (HelpViews.swift): the Mac's Help menu, and
        // Linux's Help and About Jukebox.
        Section {
            HelpItems(app: app)
        } header: {
            SettingsHeader("Help & Feedback")
        } footer: {
            Text("Diagnostic info is Jukebox's version, your system and the kind of server, to paste into a report. It never holds your server's address, your user name or a password.")
        }
    }

    /// "1.0 (42)": the build is the CI run that made it (TestFlight's number).
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}

// MARK: - Parts

/// A Mac, the app's own or the iPad's app on it (the photographer uses that
/// one): no mobile network of its own.
private var runsOnMac: Bool {
    #if os(macOS)
    return true
    #else
    return ProcessInfo.processInfo.isiOSAppOnMac
    #endif
}

/// A section's title: the system's own on the iPhone; wide, Linux's group
/// title (16-preferences.png), bold, in the text's colour, in sentence case.
private struct SettingsHeader: View {
    let title: LocalizedStringKey

    @Environment(\.isWide) private var isWide

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        if isWide {
            Text(title)
                .desktopFont(Tokens.Size.body15.size, weight: .bold)
                .foregroundStyle(.primary)
                .textCase(nil)
        } else {
            Text(title)
        }
    }
}

/// A section's actions, at its end. On the Mac in one row, trailing, as
/// System Settings sets a group's buttons, in the system's own push buttons
/// (docs/design/SYSTEM.md: the system's own controls keep the system's
/// shapes); on the iPhone and the iPad each its own row, as their Settings
/// has them.
private struct SettingsActions<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        #if os(macOS)
        HStack(spacing: Theme.Space.s) {
            Spacer(minLength: 0)
            content
        }
        .systemButtons()
        #else
        content
        #endif
    }
}

extension View {
    /// On the Mac, the system's push buttons without the window's Copper
    /// tint (JukeboxApp's appEnvironment), which drew them in Jukebox's
    /// quiet tinted look in a settings form; switches and sliders keep it.
    /// Elsewhere nothing.
    @ViewBuilder func systemButtons() -> some View {
        #if os(macOS)
        buttonStyle(.bordered).tint(Color?.none)
        #else
        self
        #endif
    }
}

/// A row's title with a line of grey under it, as Settings explains a switch.
private struct SettingsDetailLabel: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(title)
            Text(detail)
                .desktopFont(Tokens.Size.fact13.size, phone: .footnote)
                .foregroundStyle(.secondary)
        }
    }
}
