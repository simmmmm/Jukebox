// Settings, a sheet from Home and Radio: a Form as the system's own Settings
// draws one, each section its own view so a change in one (the library's
// progress, the Last.fm check) redraws only that one. The system's own
// section headers, as the system's Settings has them; nothing of its own
// (docs/design/tells.md, 4: no tracked uppercase labels of Jukebox's).

import JukeboxKit
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    init() {}

    var body: some View {
        NavigationStack {
            Form {
                SettingsAccountSection()
                SettingsPlaybackSection()
                SettingsDownloadsSection()
                SettingsRadioSection()
                SettingsLastFMSection(savedKey: settings.lastFMAPIKey)
                SettingsLyricsSection()
                SettingsLibrarySection()
                SettingsHistorySection()
                SettingsPrivacySection()
                SettingsAboutSection()
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .countsScreen("settings")
    }
}

// MARK: - Account

private struct SettingsAccountSection: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingSignOut = false

    init() {}

    var body: some View {
        Section {
            if let credentials = app.credentials {
                // Its name, and under it which kind of server it is and its
                // version ("Navidrome 0.64.2"): the sign-in screen's words.
                LabeledContent {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(verbatim: credentials.serverName)
                        Text(verbatim: ServerWords.product(credentials.kind, version: credentials.serverVersion))
                            .font(.footnote)
                    }
                } label: {
                    Text("Server")
                }
                LabeledContent("User", value: credentials.userName)
                LabeledContent("Address") {
                    Text(verbatim: credentials.serverURL.absoluteString)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
            Button("Sign Out", role: .destructive) {
                isConfirmingSignOut = true
            }
            .confirmationDialog(signOutTitle, isPresented: $isConfirmingSignOut, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    // The sheet first, so it does not hang over the swap to
                    // the sign-in screen.
                    dismiss()
                    Task { await app.signOut() }
                }
            } message: {
                Text("Playback stops and Jukebox forgets the library, your recent stations and the downloaded songs on this \(UIDevice.current.model). Your music, playlists and favorites stay on the server.")
            }
        } header: {
            Text("Account")
        }
    }

    private var signOutTitle: Text {
        if let name = app.credentials?.serverName {
            return Text("Sign out of \(name)?")
        }
        return Text("Sign out?")
    }
}

// MARK: - Playback

private struct SettingsPlaybackSection: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppModel.self) private var app

    init() {}

    var body: some View {
        @Bindable var settings = settings
        Section {
            // Music's own words for the two.
            Picker("Wi-Fi Streaming", selection: $settings.wifiQuality) {
                qualityOptions
            }
            Picker("Cellular Streaming", selection: $settings.cellularQuality) {
                qualityOptions
            }
            // Only where the server gives songs a loudness (Jellyfin 10.9+,
            // an OpenSubsonic server's ReplayGain): elsewhere the switch
            // would do nothing, so it is off and says why.
            if app.can(.replayGain) {
                Toggle(isOn: $settings.normalizeVolume) {
                    SettingsDetailLabel(title: "Normalize Volume", detail: normalizeDetail)
                }
            } else {
                Toggle(isOn: .constant(false)) {
                    SettingsDetailLabel(title: "Normalize Volume",
                                        detail: "\(app.serverKindName) doesn’t give songs a loudness, so each plays as it is")
                }
                .disabled(true)
            }
            Toggle(isOn: $settings.autoplay) {
                SettingsDetailLabel(title: "Autoplay",
                                    detail: "When an album or playlist ends, keep playing similar music")
            }
            // Now Playing's motion (NowPlayingGround.swift): off, the page
            // is sketch D1, the still wall, as it is anyway in Low Power
            // Mode and with Reduce Motion.
            Toggle(isOn: $settings.spinRecord) {
                SettingsDetailLabel(title: "Spin the Record",
                                    detail: "Now Playing's record turns, and its grooves move on with each song. Off, as in Low Power Mode and with Reduce Motion, it stands still on a wall of the cover's colours.")
            }
        } header: {
            Text("Playback")
        } footer: {
            Text("Original plays your files as they are. The others have \(app.serverKindName) convert them to \(format) at that rate, which uses less data.")
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
            return "Play every song at the loudness its ReplayGain tags give, so loud and quiet records sit side by side"
        }
        return "Play every song at the loudness Jellyfin measured, so loud and quiet records sit side by side"
    }

    private var qualityOptions: some View {
        ForEach(StreamQuality.allCases, id: \.self) { quality in
            label(for: quality)
                .tag(quality)
        }
    }

    private func label(for quality: StreamQuality) -> Text {
        switch quality {
        case .original: Text("Original")
        case .high: Text("High (320 kbit/s)")
        case .normal: Text("Normal (256 kbit/s)")
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
                                    detail: "Songs you play often or lately stay on this \(UIDevice.current.model), to play without a connection")
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
            // Music's words, as Cellular Streaming above.
            Toggle("Download over Cellular", isOn: $settings.downloadOverCellular)
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
            Button("Remove All Downloads", role: .destructive) {
                isConfirmingRemoveAll = true
            }
            .disabled(offline.songCount == 0 && offline.queuedCount == 0)
            .confirmationDialog("Remove all downloads from this \(UIDevice.current.model)?",
                                isPresented: $isConfirmingRemoveAll, titleVisibility: .visible) {
                Button("Remove All Downloads", role: .destructive) {
                    offline.removeAll()
                }
            } message: {
                Text("Every downloaded album, playlist, mix and kept song goes, and Keep Songs I Play is turned off. They still play from your server.")
            }
        } header: {
            Text("Downloads")
        } footer: {
            qualityFooter
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

    /// What each quality means on this kind of server: Jellyfin converts
    /// what the phone cannot play to AAC even at Original (docs/OFFLINE.md),
    /// a Subsonic server converts to MP3 at High and Normal.
    private var qualityFooter: Text {
        let model = UIDevice.current.model
        if app.credentials?.kind.isSubsonic == true {
            return Text("Original is each file as it is; High and Normal have \(app.serverKindName) convert songs to MP3 at that rate, so more of them fit. Songs download on Wi-Fi unless Download over Cellular is on; kept songs wait in Low Power Mode.")
        }
        return Text("Original is each file as it is, or AAC at 256 kbit/s when this \(model) cannot play it; High and Normal have Jellyfin convert songs to AAC at that rate, so more of them fit. Songs download on Wi-Fi unless Download over Cellular is on; kept songs wait in Low Power Mode.")
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
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                // The slider's own label is VoiceOver's; this one is the eyes'.
                Text("Adventurousness")
                    .accessibilityHidden(true)
                Slider(value: $settings.adventurousness, in: 0...1, label: {
                    Text("Adventurousness")
                }, onEditingChanged: { editing in
                    isDragging = editing
                    // Once, when the finger lifts: the radio chooses its next
                    // songs again, and every step of a drag would be wasted.
                    // So too the count (Stats): where it was let go.
                    if !editing {
                        radio.adventurousnessChanged()
                        Stats.track(.dialChanged, ["value": Stats.dial(settings.adventurousness)])
                    }
                })
                .accessibilityValue(dialValue)
                HStack {
                    Text("Familiar")
                    Spacer()
                    Text("Adventurous")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            }
            .padding(.vertical, Theme.Space.xs)
            // VoiceOver's swipes move the slider without a drag, so without
            // an end of editing either: each of those steps tells the radio.
            .onChange(of: settings.adventurousness) { _, _ in
                if !isDragging { radio.adventurousnessChanged() }
            }
        } header: {
            Text("Radio")
        } footer: {
            Text("Familiar stays close to where a station started and to songs you know. Adventurous goes further out and plays more that is new to you.")
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

// MARK: - Last.fm

/// The listener's own Last.fm key — the photographer's choice (8 November
/// 2026): the radio works without it, and knows who sounds like whom far
/// better with it. A key is kept only once Last.fm has accepted it, so a
/// typo never takes the radio's Last.fm away.
private struct SettingsLastFMSection: View {
    private enum KeyStatus: Equatable {
        case idle
        case checking
        case works
        case rejected
    }

    private static let createKeyURL = URL(string: "https://www.last.fm/api/account/create")!

    @Environment(AppSettings.self) private var settings
    @Environment(RadioController.self) private var radio
    @State private var draft: String
    @State private var status: KeyStatus = .idle
    /// Not the view's own task: a key pasted just before Done is still
    /// checked and kept after the sheet has closed.
    @State private var checkTask: Task<Void, Never>?

    init(savedKey: String) {
        _draft = State(initialValue: savedKey)
    }

    var body: some View {
        Section {
            TextField("API Key", text: $draft, prompt: Text("Paste your Last.fm API key"))
                .font(.body.monospaced())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { check(draft, after: .zero) }
                .onChange(of: draft) { _, newValue in
                    // Typing: once it rests.
                    check(newValue, after: .milliseconds(600))
                }
                .onAppear {
                    // The saved key, checked again each time Settings opens:
                    // a revoked key shows here rather than as a quieter radio.
                    if status == .idle, !Self.trimmed(draft).isEmpty {
                        check(draft, after: .zero)
                    }
                }
            statusRow
            Link("Get a Free API Key", destination: Self.createKeyURL)
        } header: {
            Text("Last.fm")
        } footer: {
            Text("With a key, the radio knows which artists and songs sound alike. Only artist names and song titles are sent to Last.fm.")
        }
    }

    @ViewBuilder private var statusRow: some View {
        switch status {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: Theme.Space.s) {
                ProgressView()
                Text("Checking…")
            }
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
        case .works:
            Label {
                Text("Key works")
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        case .rejected:
            Label {
                Text("Last.fm did not accept this key")
            } icon: {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    private func check(_ text: String, after delay: Duration) {
        checkTask?.cancel()
        let key = Self.trimmed(text)
        status = key.isEmpty ? .idle : .checking
        checkTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            if key.isEmpty {
                // Emptied on purpose: the radio goes on without Last.fm.
                guard settings.hasLastFM else { return }
                settings.lastFMAPIKey = ""
                radio.lastFMKeyChanged()
                Stats.track(.lastFMKey, ["state": "removed"])
                return
            }
            let works = await LastFMClient(apiKey: key).validateKey()
            guard !Task.isCancelled else { return }
            status = works ? .works : .rejected
            guard works, key != Self.trimmed(settings.lastFMAPIKey) else { return }
            settings.lastFMAPIKey = key
            radio.lastFMKeyChanged()
            Stats.track(.lastFMKey, ["state": "added"])
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
            Text("Lyrics")
        } footer: {
            Text("When your server has no lyrics for a song, Jukebox looks them up on LRCLIB (lrclib.net), a free and open lyrics database. It sends the song's title, artist, album and length.")
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
            Button {
                Task { await library.refresh() }
            } label: {
                refreshLabel
            }
            .disabled(isLoading)
        } header: {
            Text("Library")
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
            if isLoading {
                if let progress {
                    Text(progress, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                ProgressView()
            }
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
        } header: {
            Text("History")
        } footer: {
            Text("What you play, skip and give a thumbs up or down to is how the radio and your mixes learn your taste. It stays on this \(UIDevice.current.model).")
        }
    }
}

// MARK: - Privacy

/// The anonymous usage counts (Stats, docs/STATS.md), on unless turned off
/// here: the photographer's choice, "alles tracken wat je mag zonder cookie
/// melding" (8 November 2026), as Aptabase sets no cookie and keeps no device
/// id or address. The footer says what is counted, and what never is, as
/// Last.fm's and Lyrics' footers say what leaves the phone.
private struct SettingsPrivacySection: View {
    @Environment(AppSettings.self) private var settings

    init() {}

    var body: some View {
        @Bindable var settings = settings
        Section {
            Toggle("Share Anonymous Usage", isOn: $settings.shareUsage)
        } header: {
            Text("Privacy")
        } footer: {
            Text("Jukebox counts which screens and features are used — never titles, artists, searches, server addresses or names — on the developer's own server, without cookies or a device id. It helps decide what to improve.")
        }
    }
}

// MARK: - About

private struct SettingsAboutSection: View {
    var body: some View {
        Section {
            HStack(spacing: Theme.Space.m) {
                ShellAppMark(side: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Jukebox")
                        .font(.headline)
                    Text("Made for Jellyfin, Navidrome and other Subsonic servers")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, Theme.Space.xs)
            .accessibilityElement(children: .combine)
            LabeledContent("Version", value: version)
        } header: {
            Text("About")
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

/// A row's title with a line of grey under it, as Settings explains a switch.
private struct SettingsDetailLabel: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
