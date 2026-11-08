// Settings, a sheet from Home and Radio: a Form as the system's own Settings
// draws one, each section its own view so a change in one (the library's
// progress, the Last.fm check) redraws only that one. Numa's grey spaced
// labels over the sections; nothing else of its own.

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
                SettingsRadioSection()
                SettingsLastFMSection(savedKey: settings.lastFMAPIKey)
                SettingsLibrarySection()
                SettingsHistorySection()
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
                LabeledContent("Server", value: credentials.serverName)
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
                Text("Playback stops and Jukebox forgets the library and your recent stations on this \(UIDevice.current.model). Your music, playlists and favorites stay on the server.")
            }
        } header: {
            Eyebrow("Account")
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
            Toggle(isOn: $settings.normalizeVolume) {
                SettingsDetailLabel(title: "Normalize Volume",
                                    detail: "Play every song at the loudness Jellyfin measured, so loud and quiet records sit side by side")
            }
            Toggle(isOn: $settings.autoplay) {
                SettingsDetailLabel(title: "Autoplay",
                                    detail: "When an album or playlist ends, keep playing similar music")
            }
        } header: {
            Eyebrow("Playback")
        } footer: {
            Text("Original plays your files as they are. The others have Jellyfin convert them to AAC at that rate, which uses less data.")
        }
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
                    if !editing { radio.adventurousnessChanged() }
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
            Eyebrow("Radio")
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
            Eyebrow("Last.fm")
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
                return
            }
            let works = await LastFMClient(apiKey: key).validateKey()
            guard !Task.isCancelled else { return }
            status = works ? .works : .rejected
            guard works, key != Self.trimmed(settings.lastFMAPIKey) else { return }
            settings.lastFMAPIKey = key
            radio.lastFMKeyChanged()
        }
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
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
            Eyebrow("Library")
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
            Eyebrow("History")
        } footer: {
            Text("What you play, skip and give a thumbs up or down to is how the radio and your mixes learn your taste. It stays on this \(UIDevice.current.model).")
        }
    }
}

// MARK: - About

private struct SettingsAboutSection: View {
    var body: some View {
        Section {
            HStack(spacing: Theme.Space.m) {
                ShellAppMark(diameter: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Jukebox")
                        .font(.headline)
                    Text("Made for Jellyfin")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, Theme.Space.xs)
            .accessibilityElement(children: .combine)
            LabeledContent("Version", value: version)
        } header: {
            Eyebrow("About")
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
