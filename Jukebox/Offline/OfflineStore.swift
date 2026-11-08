// Music on the phone. The photographer, 8 November 2026, asked whether there
// was "cache in offline/downloads"; the library, the covers and the lyrics
// were kept, the songs only streamed. To the three parts proposed — download
// an album, a playlist or a mix; keep what is played often or lately, up to
// a size the listener chooses; offline, play only what is on the phone, the
// radio too — they answered "Alle drie". This store is the app's half of all
// three (docs/OFFLINE.md, "In the app"; JukeboxKit's Offline.swift is the
// manifest and the keep's choosing):
//
// - What is on the phone: the manifest (each song once, with every reason it
//   is there), the albums, playlists and mixes chosen, and the songs still to
//   fetch — per account, in Application Support (OfflineDisk.swift).
// - Fetching: a background URLSession (OfflineDownloader.swift), a couple of
//   dozen songs at a time, what the listener chose first; on Wi-Fi only unless
//   Settings allows mobile data. A song the server will not give is not asked
//   for again; one that failed on the way is tried again a while later.
// - The keep (KeepPolicy.plan): run a minute after the last play, at launch,
//   when Wi-Fi comes back and when its settings change; it fetches its list
//   in order and lets go of what fell out of it. It waits in Low Power Mode.
// - Offline: no network (NWPathMonitor) or a server that does not answer
//   (its public info, asked when the network changes, when a load or a song
//   fails, and every 30 s while it does not answer). The player and the
//   radio read `isOffline` and `canPlay`, and are told when it changes.
// - Plays heard offline: their reports wait here and go to the server, in
//   order, once it answers (Jellyfin counts a play at its start report, and
//   its Last.fm plugin scrobbles from them), so nothing heard offline is
//   missing there — counted when they arrive, not when they were heard.

import Foundation
import JukeboxKit
import Network
import Observation

/// What an album's, a playlist's or a mix's download is doing.
enum OfflineDownloadState: Equatable {
    case notDownloaded
    /// `fraction` of its songs on the phone; `waiting` when nothing can move
    /// until Wi-Fi, or any network, is back.
    case downloading(fraction: Double, waiting: OfflineWait?)
    case downloaded
}

enum OfflineWait: Equatable {
    case wifi
    case network
}

@Observable
final class OfflineStore {
    /// Every song on the phone, for the account signed in.
    private(set) var manifest = OfflineManifest()
    /// The albums, playlists and mixes chosen, newest first.
    private(set) var collections: [OfflineCollection] = []
    /// Songs still to fetch: what the listener chose first, then the keep's,
    /// best first.
    private(set) var wanted: [OfflineWanted] = []
    /// Songs the server would not give (gone, or a file it cannot send in the
    /// quality asked for): not asked for again until they are chosen again.
    private(set) var failed: Set<ItemID> = []
    /// The songs downloading, 0…1, a couple of times a second.
    private(set) var progress: [ItemID: Double] = [:]
    /// Moves whenever the songs on the phone change: the radio's songs on the
    /// phone are made again from it.
    private(set) var revision = 0

    private(set) var hasNetwork = true
    /// The mobile network, a hotspot, or Low Data Mode.
    private(set) var isExpensiveNetwork = false
    private(set) var isServerUnreachable = false
    private(set) var isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    /// No network, or a server that does not answer: only what is on the
    /// phone can play.
    var isOffline: Bool { !hasNetwork || isServerUnreachable }

    /// AppModel's: the player and the radio follow (`isOffline` changed).
    @ObservationIgnored var onConnectivityChange: (() -> Void)?
    /// AppModel's: the songs on the phone changed.
    @ObservationIgnored var onSongsChange: (() -> Void)?

    private let settings: AppSettings
    private let library: LibraryStore
    private let history: HistoryStore
    private let monitor = NWPathMonitor()
    /// One writer, in order: a slow write never lands after a newer one.
    private let writer = DispatchQueue(label: "Jukebox.offline", qos: .utility)

    @ObservationIgnored private var client: JellyfinClient?
    @ObservationIgnored private var account: String?
    @ObservationIgnored private var reports: [PendingPlay] = []
    /// Songs the session is fetching now.
    @ObservationIgnored private var inFlight: Set<ItemID> = []
    /// The session's own list was read after sign-in: until then nothing is
    /// started, so a song it is still fetching is not asked for twice.
    @ObservationIgnored private var isAdopted = false
    /// The account's state is read from disk. Until then the session's news
    /// waits (`held`): at a launch in the background, before the sign-in is
    /// restored, a finished song would otherwise look unwanted and be thrown away.
    @ObservationIgnored private var isLoaded = false
    @ObservationIgnored private var held: [OfflineDownloadEvent] = []
    @ObservationIgnored private var failures: [ItemID: Int] = [:]
    @ObservationIgnored private var retryAt: [ItemID: Date] = [:]
    @ObservationIgnored private var latestProgress: [ItemID: Double] = [:]
    @ObservationIgnored private var seen: SeenSettings
    @ObservationIgnored private var seenLibraryLoad: Date?
    @ObservationIgnored private var probeCount = 0
    @ObservationIgnored private var probeTask: Task<Void, Never>?
    @ObservationIgnored private var recheckTask: Task<Void, Never>?
    @ObservationIgnored private var progressTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var keepTask: Task<Void, Never>?
    @ObservationIgnored private var pumpTask: Task<Void, Never>?
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var powerToken: (any NSObjectProtocol)?

    /// The choices that change what the keep holds or how songs are fetched.
    private struct SeenSettings: Equatable {
        var keep: Bool
        var limit: Int
        var quality: DownloadQuality
        var cellular: Bool

        init(_ settings: AppSettings) {
            keep = settings.keepSongs
            limit = settings.keepLimitGB
            quality = settings.downloadQuality
            cellular = settings.downloadOverCellular
        }
    }

    /// Songs at once in the session: an album or a mix goes in one go, and
    /// so finishes while the app is in the background; the keep's thousand
    /// go a couple of dozen at a time.
    private static let window = 24

    init(settings: AppSettings, library: LibraryStore, history: HistoryStore) {
        self.settings = settings
        self.library = library
        self.history = history
        seen = SeenSettings(settings)
        OfflineBackgroundEvents.store = self
        OfflineDownloader.shared.attach { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        monitor.pathUpdateHandler = Self.pathHandler { [weak self] path in
            Task { @MainActor in self?.pathChanged(path) }
        }
        monitor.start(queue: DispatchQueue(label: "Jukebox.offline-network", qos: .utility))
        powerToken = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange,
                                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.powerChanged()
            }
        }
        observeSettings()
        observeHistory()
        observeLibrary()
    }

    // MARK: The account

    /// Signed in: the account's songs from disk, then what the session is
    /// still fetching for it, then the keep.
    func open(credentials: Credentials, client: JellyfinClient) async {
        let account = OfflinePaths.account(for: credentials)
        self.client = client
        guard self.account != account else { return }
        self.account = account
        isAdopted = false
        isLoaded = false
        inFlight = []
        let loaded = await Task.detached(priority: .userInitiated) { OfflineDisk.load(account) }.value
        guard self.account == account else { return }
        manifest = loaded.manifest
        collections = loaded.collections
        wanted = loaded.wanted
        failed = Set(loaded.failed)
        reports = loaded.reports
        isLoaded = true
        // What the session said meanwhile, now that it can be read: another
        // account's files go, this one's join the manifest.
        let earlier = held
        held = []
        for event in earlier { handle(event) }
        songsChanged()
        OfflineDownloader.shared.running { [weak self] tags in
            Task { @MainActor in self?.adopt(tags, account: account) }
        }
        checkServer()
        scheduleKeep(after: 10)
    }

    /// Signing out: the account's songs go with it, so the next account —
    /// perhaps on another server — never plays them, and no one's gigabytes
    /// are left behind where no Settings shows them. Its plays not yet told
    /// to the server are taken first (`takeReports`).
    func signOut() {
        let account = self.account
        OfflineDownloader.shared.cancel { _ in true }
        self.account = nil
        client = nil
        isAdopted = false
        isLoaded = false
        manifest = OfflineManifest()
        collections = []
        wanted = []
        failed = []
        progress = [:]
        latestProgress = [:]
        inFlight = []
        failures = [:]
        retryAt = [:]
        reports = []
        for task in [saveTask, keepTask, pumpTask, flushTask, recheckTask, probeTask, progressTask] { task?.cancel() }
        saveTask = nil
        keepTask = nil
        pumpTask = nil
        flushTask = nil
        recheckTask = nil
        probeTask = nil
        progressTask = nil
        probeCount += 1
        if isServerUnreachable { isServerUnreachable = false }
        songsChanged()
        if let account {
            writer.async { OfflineDisk.removeAccount(account) }
        }
    }

    /// The plays not yet told to the server, handed over (and forgotten here).
    func takeReports() -> [PendingPlay] {
        let taken = reports
        reports = []
        return taken
    }

    // MARK: What is on the phone

    func has(_ trackID: ItemID) -> Bool { manifest.has(trackID) }

    /// Whether the song can play now: anything online, offline only what is
    /// on the phone.
    func canPlay(_ trackID: ItemID) -> Bool { !isOffline || manifest.has(trackID) }

    /// The song's file, when it is on the phone.
    func localURL(for trackID: ItemID) -> URL? {
        guard let account, let file = manifest.file(trackID) else { return nil }
        return OfflinePaths.files(account).appendingPathComponent(file.fileName, isDirectory: false)
    }

    func collection(for reason: OfflineReason) -> OfflineCollection? {
        collections.first { $0.reason == reason }
    }

    func state(of reason: OfflineReason) -> OfflineDownloadState {
        guard let collection = collection(for: reason) else { return .notDownloaded }
        var total = 0
        var done = 0.0
        for id in Set(collection.trackIDs) where !failed.contains(id) {
            total += 1
            if manifest.has(id) {
                done += 1
            } else {
                done += progress[id] ?? 0
            }
        }
        guard total > 0, done < Double(total) else { return .downloaded }
        return .downloading(fraction: done / Double(total), waiting: waiting)
    }

    /// Why nothing moves, when nothing can: no network, or only mobile data
    /// and Download over Cellular off.
    var waiting: OfflineWait? {
        if !hasNetwork { return .network }
        if isExpensiveNetwork && !settings.downloadOverCellular { return .wifi }
        return nil
    }

    var songCount: Int { manifest.files.count }
    var chosenBytes: Int64 { manifest.chosenBytes }
    var keptBytes: Int64 { manifest.keptBytes }
    /// The songs only the keep holds, or that the keep holds too.
    var keptTrackIDs: [ItemID] { manifest.tracks(with: .kept) }
    /// Songs still to come.
    var queuedCount: Int { wanted.count }

    /// The bytes of a collection's songs on the phone.
    func bytes(of collection: OfflineCollection) -> Int64 {
        Set(collection.trackIDs).reduce(Int64(0)) { sum, id in sum + (manifest.file(id)?.bytes ?? 0) }
    }

    /// How many of a collection's songs are on the phone.
    func songsOnPhone(of collection: OfflineCollection) -> Int {
        Set(collection.trackIDs).filter { manifest.has($0) }.count
    }

    // MARK: Choosing

    /// An album, a playlist or a mix to the phone: its songs not there yet
    /// are fetched, those there already gain it as a reason.
    func download(_ collection: OfflineCollection) {
        guard account != nil, !collection.tracks.isEmpty else { return }
        // What kind of thing, never which (Stats).
        Stats.track(.downloadChosen, ["kind": collection.kind])
        let reason = collection.reason
        collections.removeAll { $0.reason == reason }
        collections.insert(collection, at: 0)
        // Chosen again after a song failed: it is tried again.
        for id in collection.trackIDs {
            failed.remove(id)
            failures[id] = nil
            retryAt[id] = nil
        }
        want(collection.tracks, for: reason)
        songsChanged()
        scheduleSave()
        pump()
    }

    /// Remove Download: the reason goes from its songs; a song another
    /// download or the keep also holds stays.
    func remove(_ reason: OfflineReason) {
        let freed = manifest.removeReason(reason)
        deleteFiles(freed)
        dropWanted(reason, from: nil)
        collections.removeAll { $0.reason == reason }
        songsChanged()
        scheduleSave()
    }

    /// Remove All Downloads, in Settings. The keep is turned off too: else
    /// it would fetch its songs again at once.
    func removeAll() {
        guard let account else { return }
        if settings.keepSongs { settings.keepSongs = false }
        OfflineDownloader.shared.cancel { $0.account == account }
        manifest = OfflineManifest()
        collections = []
        wanted = []
        failed = []
        inFlight = []
        progress = [:]
        latestProgress = [:]
        failures = [:]
        retryAt = [:]
        songsChanged()
        writer.async { OfflineDisk.removeAllFiles(of: account) }
        saveNow()
    }

    /// A playlist's page read its songs from the server: a downloaded
    /// playlist follows it — songs added there are fetched, songs taken out
    /// lose it as a reason. Playlists change in other apps too.
    func playlistLoaded(_ playlist: Playlist, tracks: [Track]) {
        let reason = OfflineReason.playlist(playlist.id)
        guard let at = collections.firstIndex(where: { $0.reason == reason }) else { return }
        let before = Set(collections[at].trackIDs)
        let after = Set(tracks.map(\.id))
        if collections[at].tracks != tracks || collections[at].item != .playlist(playlist) {
            collections[at].tracks = tracks
            collections[at].item = .playlist(playlist)
            scheduleSave()
        }
        let gone = before.subtracting(after)
        let added = tracks.filter { !before.contains($0.id) }
        guard !gone.isEmpty || !added.isEmpty else { return }
        if !gone.isEmpty {
            deleteFiles(manifest.removeReason(reason, from: Array(gone)))
            dropWanted(reason, from: gone)
        }
        if !added.isEmpty { want(added, for: reason) }
        songsChanged()
        scheduleSave()
        pump()
    }

    // MARK: Plays heard offline

    /// Whether a play's reports wait here: offline, or its start waits here
    /// already (so its stop goes after it, not before).
    func holdsReports(of playSessionID: String) -> Bool {
        isOffline || reports.contains { $0.playSessionID == playSessionID }
    }

    func holdStart(_ report: PlaybackReport) {
        reports.append(PendingPlay(trackID: report.trackID, playSessionID: report.playSessionID,
                                   startPosition: report.position, stopPosition: nil))
        // Reckoned, not measured: a month of listening offline is a few
        // thousand plays; past 5000 the oldest go.
        if reports.count > 5000 { reports.removeFirst(reports.count - 5000) }
        scheduleSave()
    }

    func holdStop(_ report: PlaybackReport) {
        if let at = reports.firstIndex(where: { $0.playSessionID == report.playSessionID }) {
            reports[at].stopPosition = report.position
        } else {
            // Its start reached the server before it went away.
            reports.append(PendingPlay(trackID: report.trackID, playSessionID: report.playSessionID,
                                       startPosition: nil, stopPosition: report.position))
        }
        scheduleSave()
    }

    // MARK: The network and the server

    /// Asks whether the server answers, unless asking already. Also from
    /// the player when a song fails on the network, and Home's Try Again.
    func checkServer(after delay: Double = 0) {
        guard let client, hasNetwork, probeTask == nil else { return }
        probeCount += 1
        let mine = probeCount
        let account = self.account
        probeTask = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            let answered: Bool
            do {
                _ = try await client.publicInfo()
                answered = true
            } catch {
                answered = false
            }
            guard let self, self.probeCount == mine else { return }
            self.probeTask = nil
            guard self.account == account, self.hasNetwork else { return }
            self.serverAnswered(answered)
        }
    }

    /// The app is in front again: the server may have come back, or gone,
    /// while it was away.
    func appBecameActive() {
        checkServer()
        pump()
    }

    // MARK: Saving

    /// After the downloads' background news (OfflineBackgroundEvents): saved
    /// at once, and the system told once it is on disk.
    func saveNowThenTellSystem() {
        saveNow()
        writer.async {
            Task { @MainActor in OfflineBackgroundEvents.tellSystem() }
        }
    }
}

// MARK: - Inside

private extension OfflineStore {
    /// Made outside the main actor: the monitor calls it on its own queue.
    /// Low Data Mode (`isConstrained`) counts as expensive, as NetworkCost
    /// has it.
    nonisolated static func pathHandler(_ update: @escaping @Sendable (OfflinePathState) -> Void)
        -> @Sendable (NWPath) -> Void {
        { path in
            update(OfflinePathState(isSatisfied: path.status == .satisfied,
                                    isExpensive: path.isExpensive || path.isConstrained))
        }
    }

    func songsChanged() {
        revision += 1
        onSongsChange?()
    }

    // MARK: The queue

    /// `tracks` wanted for `reason`: on the phone already, they gain it;
    /// else they join the queue, or gain it there.
    func want(_ tracks: [Track], for reason: OfflineReason) {
        let quality = settings.downloadQuality
        var position: [ItemID: Int] = [:]
        for (at, item) in wanted.enumerated() { position[item.trackID] = at }
        for track in tracks {
            if manifest.has(track.id) {
                manifest.addReason(reason, to: track.id)
                continue
            }
            if let at = position[track.id] {
                wanted[at].reasons.insert(reason)
            } else {
                position[track.id] = wanted.count
                let estimate = KeepPolicy.estimatedBytes(of: track, quality: quality)
                wanted.append(OfflineWanted(trackID: track.id, reasons: [reason], quality: quality, estimate: estimate))
            }
        }
        // What the listener chose goes before what the keep would like.
        if reason.isChosen {
            wanted = wanted.filter { $0.isChosen } + wanted.filter { !$0.isChosen }
        }
    }

    /// `reason` taken from the songs still to come (all of them, or those
    /// in `ids`); a song left with no reason is not fetched.
    func dropWanted(_ reason: OfflineReason, from ids: Set<ItemID>?) {
        var dropped = Set<ItemID>()
        for at in wanted.indices {
            let id = wanted[at].trackID
            guard ids?.contains(id) ?? true, wanted[at].reasons.contains(reason) else { continue }
            wanted[at].reasons.remove(reason)
            if wanted[at].reasons.isEmpty { dropped.insert(id) }
        }
        guard !dropped.isEmpty else { return }
        wanted.removeAll { $0.reasons.isEmpty }
        cancelDownloads(dropped)
    }

    func cancelDownloads(_ ids: Set<ItemID>) {
        guard !ids.isEmpty, let account else { return }
        OfflineDownloader.shared.cancel { $0.account == account && ids.contains($0.trackID) }
        inFlight.subtract(ids)
        for id in ids { clearProgress(id) }
    }

    func deleteFiles(_ files: [OfflineFile]) {
        guard !files.isEmpty, let account else { return }
        let names = files.map(\.fileName)
        writer.async { OfflineDisk.removeFiles(names, of: account) }
    }

    /// What the session still fetches since before this launch, taken as
    /// ours; what it fetches for no one is cancelled.
    func adopt(_ tags: [OfflineDownloadTag], account: String) {
        guard self.account == account else { return }
        let wantedIDs = Set(wanted.map(\.trackID))
        var stray = Set<OfflineDownloadTag>()
        for tag in tags {
            if tag.account == account, wantedIDs.contains(tag.trackID), !manifest.has(tag.trackID) {
                inFlight.insert(tag.trackID)
            } else {
                stray.insert(tag)
            }
        }
        let strays = stray
        if !strays.isEmpty { OfflineDownloader.shared.cancel { strays.contains($0) } }
        isAdopted = true
        pump()
    }

    /// As many songs as the window has room for, in the queue's order. The
    /// keep's wait while it is off or in Low Power Mode; a song that failed
    /// on the way waits its turn to be tried again.
    func pump() {
        guard isAdopted, let account, let client else { return }
        var running = inFlight.count
        guard running < Self.window else { return }
        let keepMayRun = settings.keepSongs && !isLowPower
        let cellular = settings.downloadOverCellular
        let now = Date()
        var nextRetry: Date?
        for item in wanted {
            guard running < Self.window else { break }
            let id = item.trackID
            guard !inFlight.contains(id), !failed.contains(id), !manifest.has(id) else { continue }
            guard item.isChosen || keepMayRun else { continue }
            if let at = retryAt[id], at > now {
                nextRetry = min(nextRetry ?? at, at)
                continue
            }
            let tag = OfflineDownloadTag(account: account, trackID: id, quality: item.quality)
            let url = client.downloadURL(trackID: id, quality: item.quality)
            // Low Data Mode holds back the keep, not what was chosen.
            OfflineDownloader.shared.start(tag, from: url, overCellular: cellular, inLowDataMode: item.isChosen,
                                           expectedBytes: item.estimate, isChosen: item.isChosen)
            inFlight.insert(id)
            running += 1
        }
        if let nextRetry { schedulePump(at: nextRetry) }
    }

    func schedulePump(at date: Date) {
        pumpTask?.cancel()
        let wait = max(1, date.timeIntervalSinceNow)
        pumpTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.pump()
        }
    }

    // MARK: The session's news

    func handle(_ event: OfflineDownloadEvent) {
        guard isLoaded else {
            if case .progress = event { return }
            held.append(event)
            return
        }
        switch event {
        case let .progress(tag, written: written, expected: expected):
            guard tag.account == account, inFlight.contains(tag.trackID) else { return }
            let estimate = wanted.first(where: { $0.trackID == tag.trackID })?.estimate ?? 0
            let total = expected > 0 ? expected : estimate
            guard total > 0 else { return }
            latestProgress[tag.trackID] = min(0.99, Double(written) / Double(total))
            scheduleProgress()
        case let .finished(tag, fileName: fileName, bytes: bytes):
            downloadFinished(tag, fileName: fileName, bytes: bytes)
        case let .failed(tag, permanent: permanent):
            downloadFailed(tag, permanent: permanent)
        case let .cancelled(tag):
            guard tag.account == account else { return }
            inFlight.remove(tag.trackID)
            clearProgress(tag.trackID)
            // Still wanted (Download over Cellular changed, which cancels
            // every download to ask again): it starts again.
            pump()
        }
    }

    func downloadFinished(_ tag: OfflineDownloadTag, fileName: String, bytes: Int64) {
        guard let account, tag.account == account else {
            // Another account's, or no one's: not kept.
            let other = tag.account
            writer.async { OfflineDisk.removeFiles([fileName], of: other) }
            return
        }
        let id = tag.trackID
        inFlight.remove(id)
        clearProgress(id)
        failures[id] = nil
        retryAt[id] = nil
        var item: OfflineWanted?
        if let at = wanted.firstIndex(where: { $0.trackID == id }) { item = wanted.remove(at: at) }
        if let existing = manifest.file(id) {
            // Fetched twice: the first stays, with this one's reasons too.
            if existing.fileName != fileName {
                writer.async { OfflineDisk.removeFiles([fileName], of: account) }
            }
            for reason in item?.reasons ?? [] { manifest.addReason(reason, to: id) }
        } else if let item {
            manifest.add(OfflineFile(trackID: id, fileName: fileName, bytes: bytes, savedAt: Date(),
                                     quality: tag.quality, reasons: item.reasons))
        } else {
            // No longer wanted (removed while it came).
            writer.async { OfflineDisk.removeFiles([fileName], of: account) }
            pump()
            return
        }
        songsChanged()
        scheduleSave()
        pump()
    }

    func downloadFailed(_ tag: OfflineDownloadTag, permanent: Bool) {
        guard tag.account == account else { return }
        let id = tag.trackID
        inFlight.remove(id)
        clearProgress(id)
        if permanent {
            failed.insert(id)
            scheduleSave()
        } else if isOffline {
            // The server is away, not the song: tried again once it is back
            // (`connectivityChanged` clears the waits), not counted against it.
            retryAt[id] = Date().addingTimeInterval(60)
        } else {
            let count = (failures[id] ?? 0) + 1
            failures[id] = count
            if count >= 6 {
                failed.insert(id)
                scheduleSave()
            } else {
                // A minute, then two, four, eight, sixteen.
                retryAt[id] = Date().addingTimeInterval(60 * pow(2, Double(count - 1)))
            }
            checkServer()
        }
        pump()
    }

    func scheduleProgress() {
        guard progressTask == nil else { return }
        progressTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, !Task.isCancelled else { return }
            self.progressTask = nil
            self.progress = self.latestProgress
        }
    }

    func clearProgress(_ id: ItemID) {
        latestProgress[id] = nil
        if progress[id] != nil { progress[id] = nil }
    }

    // MARK: The keep

    func scheduleKeep(after seconds: Double) {
        keepTask?.cancel()
        keepTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await self?.runKeep()
        }
    }

    func runKeep() async {
        guard let account else { return }
        guard settings.keepSongs else {
            dropKeep()
            return
        }
        // Only when its songs can come. Offline, on mobile data without
        // leave, or in Low Power Mode, the plan would let songs go to make
        // room for ones that cannot be fetched — and offline the songs it
        // let go of are the only ones that play. It runs again when Wi-Fi or
        // the server is back, and when Low Power Mode ends.
        guard !isOffline, waiting == nil, !isLowPower else { return }
        // The plan needs the library; it runs again once that has loaded.
        guard !library.tracks.isEmpty else { return }
        let tracks = library.tracks
        let events = history.history
        let current = manifest
        let limit = settings.keepLimitBytes
        let quality = settings.downloadQuality
        let plan = await Task.detached(priority: .utility) {
            KeepPolicy.plan(tracks: tracks, history: events, manifest: current, limitBytes: limit,
                            quality: quality, now: Date())
        }.value
        guard self.account == account, settings.keepSongs else { return }
        applyKeep(plan)
    }

    /// The plan: what fell out of the keep goes first, then its songs are
    /// queued in its order, after what the listener chose.
    func applyKeep(_ plan: KeepPlan) {
        var changed = false
        if !plan.remove.isEmpty {
            deleteFiles(manifest.removeReason(.kept, from: plan.remove))
            changed = true
        }
        let planned = Set(plan.download)
        let leaving = Set(wanted.filter { $0.reasons.contains(.kept) && !planned.contains($0.trackID) }.map(\.trackID))
        if !leaving.isEmpty { dropWanted(.kept, from: leaving) }
        let tracks = plan.download.compactMap { library.track(id: $0) }
        if !tracks.isEmpty { want(tracks, for: .kept) }
        var rank: [ItemID: Int] = [:]
        for (at, id) in plan.download.enumerated() { rank[id] = at }
        let chosen = wanted.filter { $0.isChosen }
        let kept = wanted.filter { !$0.isChosen }.sorted { a, b in
            (rank[a.trackID] ?? Int.max) < (rank[b.trackID] ?? Int.max)
        }
        wanted = chosen + kept
        if changed { songsChanged() }
        scheduleSave()
        pump()
    }

    /// Keep Songs I Play off: what it alone held goes, and it fetches nothing more.
    func dropKeep() {
        let holds = !manifest.tracks(with: .kept).isEmpty
        let queued = wanted.contains { $0.reasons.contains(.kept) }
        guard holds || queued else { return }
        if holds { deleteFiles(manifest.removeReason(.kept)) }
        if queued { dropWanted(.kept, from: nil) }
        songsChanged()
        scheduleSave()
    }

    // MARK: Watching

    func observeSettings() {
        withObservationTracking {
            _ = settings.keepSongs
            _ = settings.keepLimitGB
            _ = settings.downloadQuality
            _ = settings.downloadOverCellular
        } onChange: { [weak self] in
            Task { @MainActor in self?.settingsChanged() }
        }
    }

    func settingsChanged() {
        observeSettings()
        let now = SeenSettings(settings)
        let before = seen
        seen = now
        if now.cellular != before.cellular, let account {
            // A download asks once whether it may use mobile data: every one
            // is cancelled, and starts again asking anew (`handle`, cancelled).
            OfflineDownloader.shared.cancel { $0.account == account }
        }
        if now.keep != before.keep || now.limit != before.limit || now.quality != before.quality {
            scheduleKeep(after: now.keep ? 2 : 0)
        }
    }

    /// A play, a skip, a thumb: the keep is made again a minute after the
    /// last of them, not after each.
    func observeHistory() {
        withObservationTracking {
            _ = history.history
        } onChange: { [weak self] in
            Task { @MainActor in self?.historyChanged() }
        }
    }

    func historyChanged() {
        observeHistory()
        if settings.keepSongs { scheduleKeep(after: 60) }
    }

    /// The library from the server (play counts): the keep again. A load
    /// that failed: is the server there?
    func observeLibrary() {
        withObservationTracking {
            _ = library.lastLoaded
            _ = library.state
        } onChange: { [weak self] in
            Task { @MainActor in self?.libraryChanged() }
        }
    }

    func libraryChanged() {
        observeLibrary()
        if case .failed = library.state { checkServer() }
        if library.lastLoaded != seenLibraryLoad {
            seenLibraryLoad = library.lastLoaded
            if library.lastLoaded != nil { scheduleKeep(after: 15) }
        }
    }

    func powerChanged() {
        let low = ProcessInfo.processInfo.isLowPowerModeEnabled
        guard low != isLowPower else { return }
        isLowPower = low
        if low {
            // The keep waits; what the listener chose goes on.
            let keepOnly = Set(wanted.filter { !$0.isChosen }.map(\.trackID)).intersection(inFlight)
            cancelDownloads(keepOnly)
        } else {
            scheduleKeep(after: 5)
            pump()
        }
    }

    func pathChanged(_ path: OfflinePathState) {
        let wasOffline = isOffline
        let hadNetwork = hasNetwork
        let wasWiFi = hasNetwork && !isExpensiveNetwork
        if hasNetwork != path.isSatisfied { hasNetwork = path.isSatisfied }
        if isExpensiveNetwork != path.isExpensive { isExpensiveNetwork = path.isExpensive }
        if path.isSatisfied {
            // Back after none: offline until the server has answered, as a
            // server at home is not there from the mobile network.
            if !hadNetwork && !isServerUnreachable { isServerUnreachable = true }
            // A new network, or the same one changed: is the server on it?
            stopProbe()
            checkServer(after: hadNetwork ? 0 : 1)
        } else {
            stopProbe()
            recheckTask?.cancel()
            recheckTask = nil
        }
        if isOffline != wasOffline { connectivityChanged() }
        if path.isSatisfied && !path.isExpensive && !wasWiFi {
            // Wi-Fi again: the keep, and whatever waited for it.
            scheduleKeep(after: 5)
            pump()
        }
    }

    func stopProbe() {
        probeTask?.cancel()
        probeTask = nil
        probeCount += 1
    }

    func serverAnswered(_ answered: Bool) {
        let wasOffline = isOffline
        let unreachable = !answered
        if isServerUnreachable != unreachable { isServerUnreachable = unreachable }
        if isOffline != wasOffline { connectivityChanged() }
        recheckTask?.cancel()
        recheckTask = nil
        guard unreachable else { return }
        // Asked again every 30 s while it does not answer: the server back
        // (a restart, the router) ends offline by itself.
        recheckTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            self?.recheckTask = nil
            self?.checkServer()
        }
    }

    func connectivityChanged() {
        if !isOffline {
            // Back: what waited for the server is tried again now, and what
            // was heard meanwhile is told to it.
            retryAt = [:]
            failures = [:]
            flushReports()
            pump()
            scheduleKeep(after: 5)
        }
        onConnectivityChange?()
    }

    // MARK: Reports

    /// The plays heard offline, in order: the start (where Jellyfin counts
    /// the play, and its Last.fm plugin scrobbles), then the stop.
    func flushReports() {
        guard flushTask == nil, !reports.isEmpty, let client, !isOffline else { return }
        let account = self.account
        flushTask = Task { [weak self] in
            while true {
                guard let self, self.account == account, !self.isOffline,
                      let play = self.reports.first else { break }
                let session = play.playSessionID
                if let start = play.startPosition {
                    await client.reportStart(PlaybackReport(trackID: play.trackID, position: start, isPaused: false,
                                                            playSessionID: session))
                }
                // The stop can have come while the start went.
                let stop = self.reports.first(where: { $0.playSessionID == session })?.stopPosition
                if let stop {
                    await client.reportStopped(PlaybackReport(trackID: play.trackID, position: stop, isPaused: false,
                                                              playSessionID: session))
                }
                guard self.account == account else { break }
                self.reports.removeAll { $0.playSessionID == session }
                self.scheduleSave()
            }
            self?.flushTask = nil
        }
    }

    // MARK: Writing

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        guard let account else { return }
        let state = OfflineAccountState(manifest: manifest, collections: collections, wanted: wanted,
                                        failed: Array(failed), reports: reports)
        writer.async { OfflineDisk.save(state, of: account) }
    }
}

/// What NWPathMonitor said, as values that cross to the main actor.
nonisolated struct OfflinePathState: Sendable {
    let isSatisfied: Bool
    let isExpensive: Bool
}

/// The plays of an account signing out, told to its server on the way out
/// when it answers (AppModel.signOut).
enum OfflineReports {
    static func send(_ plays: [PendingPlay], with client: JellyfinClient) async {
        for play in plays {
            if let start = play.startPosition {
                await client.reportStart(PlaybackReport(trackID: play.trackID, position: start, isPaused: false,
                                                        playSessionID: play.playSessionID))
            }
            if let stop = play.stopPosition {
                await client.reportStopped(PlaybackReport(trackID: play.trackID, position: stop, isPaused: false,
                                                          playSessionID: play.playSessionID))
            }
        }
    }
}
