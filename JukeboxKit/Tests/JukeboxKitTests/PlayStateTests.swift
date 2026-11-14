// From one device to another (Server/PlayState.swift): what is kept of a
// queue, and that what one device saves another reads back, on every test
// server that runs — Jellyfin's DisplayPreferences, Navidrome's play queue.

import Foundation
import Testing
@testable import JukeboxKit

@Suite("Play state: the window of a queue")
struct PlayStateWindowTests {
    private func state(count: Int, index: Int) -> PlayState {
        PlayState(deviceID: "a", deviceName: "A", isPlaying: true,
                  queue: (0..<count).map { "t\($0)" }, index: index, position: 12)
    }

    @Test("A short queue is kept whole")
    func short() {
        let kept = state(count: 12, index: 5)
        #expect(kept.trackIDs.count == 12 && kept.index == 5 && kept.currentTrackID == "t5")
    }

    @Test("A long queue keeps 10 before and 50 after, the current song still current")
    func long() {
        let kept = state(count: 500, index: 200)
        #expect(kept.trackIDs.count == 61 && kept.index == 10 && kept.currentTrackID == "t200")
        #expect(kept.trackIDs.first == "t190" && kept.trackIDs.last == "t250")
        let atEnd = state(count: 500, index: 499)
        #expect(atEnd.trackIDs.count == 11 && atEnd.currentTrackID == "t499")
    }

    @Test("An index outside the queue, or no queue, never traps")
    func bounds() {
        #expect(state(count: 3, index: 9).currentTrackID == "t2")
        #expect(state(count: 3, index: -4).currentTrackID == "t0")
        #expect(state(count: 0, index: 0).currentTrackID == nil)
    }

    @Test("Own and live: by the device's id, or its name where the server keeps only that")
    func ownAndLive() {
        let now = Date()
        var kept = state(count: 3, index: 0)
        kept.updatedAt = now.addingTimeInterval(-30)
        #expect(kept.isOwn(ClientIdentity(clientVersion: "1", deviceName: "X", deviceID: "a")))
        #expect(kept.isOwn(ClientIdentity(clientVersion: "1", deviceName: "a", deviceID: "z")))
        #expect(!kept.isOwn(ClientIdentity(clientVersion: "1", deviceName: "X", deviceID: "z")))
        #expect(kept.isLive(now: now))
        kept.updatedAt = now.addingTimeInterval(-300)
        #expect(!kept.isLive(now: now))
        kept.updatedAt = now
        kept.isPlaying = nil
        #expect(!kept.isLive(now: now))
    }
}

@Suite("Play state: saved by one device, read by another", .serialized, .enabled(if: !TestServers.available.isEmpty))
struct PlayStateServerTests {
    @Test("What is saved comes back: the songs, the current one, the position, the device",
          arguments: TestServers.available)
    func roundTrip(_ test: TestServers.Case) async throws {
        let server = try await test.open()
        let tracks = try await server.allTracks(progress: nil).sorted { $0.id < $1.id }
        let queue = Array(tracks.prefix(8).map(\.id))
        let saved = PlayState(deviceID: "device-1", deviceName: "tijmen-pc", isPlaying: true,
                              queue: queue, index: 3, position: 42.5, title: "Kid A")
        try await server.savePlayState(saved)
        let read = try #require(try await server.playState())
        #expect(read.trackIDs == queue)
        #expect(read.index == 3 && read.currentTrackID == queue[3])
        #expect(abs(read.position - 42.5) < 0.01)
        #expect(read.deviceName == "tijmen-pc")
        #expect(abs(read.updatedAt.timeIntervalSinceNow) < 120)
        // A device knows its own save, by id or (Subsonic) by name.
        #expect(read.isOwn(ClientIdentity(clientVersion: "1", deviceName: "tijmen-pc", deviceID: "device-1")))
        #expect(!read.isOwn(ClientIdentity(clientVersion: "1", deviceName: "iPhone", deviceID: "device-2")))
        if server.kind == .jellyfin {
            // Jellyfin keeps all of it; a Subsonic server its API's part.
            #expect(read == saved || abs(read.updatedAt.timeIntervalSince(saved.updatedAt)) < 0.001)
            #expect(read.isPlaying == true && read.title == "Kid A" && read.deviceID == "device-1")
        }

        // A second save replaces the first: one state a user.
        let later = PlayState(deviceID: "device-2", deviceName: "iPhone", isPlaying: false,
                              queue: Array(queue.reversed()), index: 0, position: 0)
        try await server.savePlayState(later)
        let again = try #require(try await server.playState())
        #expect(again.deviceName == "iPhone" && again.trackIDs == Array(queue.reversed()) && again.index == 0)
    }

    @Test("A station that played comes back with its queue (Jellyfin keeps it)")
    func station() async throws {
        guard let jellyfin = TestServers.available.first(where: { $0.name == "Jellyfin" }) else { return }
        let server = try await jellyfin.open()
        let ids = try await server.allTracks(progress: nil).prefix(3).map(\.id)
        let station = Station(id: "personal", seed: .personal, title: "Your Station")
        try await server.savePlayState(PlayState(deviceID: "d", deviceName: "pc", isPlaying: true,
                                                 queue: Array(ids), index: 1, position: 3, station: station))
        #expect(try await server.playState()?.station == station)
    }
}
