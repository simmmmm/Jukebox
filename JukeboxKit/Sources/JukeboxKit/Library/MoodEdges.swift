// Moods and tempo as the radio's evidence, where the library is tagged with
// them (OpenSubsonic's `moods` and `bpm`; Navidrome passes MOOD and BPM).
// Songs that share a mood, at a near tempo, are near each other: a station
// that starts from a song goes on in its mood. Untagged songs get nothing,
// so a library without the tags plays as before.
//
// The seam: edges between tracks, as Last.fm's similar tracks are
// (SimilarityGraph.addTrackEdge), merged into the graph the radio already
// has (RadioController); nothing in Radio/ changes. Weaker than Last.fm's
// (at most `strongest`): a tag is one person's word for a song, Last.fm's
// is a crowd's listening.

import Foundation

public enum MoodEdges {
    /// The heaviest edge a mood can make.
    public static let strongest = 0.5
    /// Edges kept per song.
    public static let perTrack = 20

    /// One way from each tagged song to its nearest.
    // ponytail: every pair within a mood is weighed, so a mood tagged on
    // n songs costs n² here; sample each mood's songs if a library tags
    // tens of thousands alike.
    public static func graph(for tracks: [Track]) -> SimilarityGraph {
        var graph = SimilarityGraph()
        var byMood: [String: [Int]] = [:]
        var moods: [Set<String>] = []
        for (i, track) in tracks.enumerated() {
            let set = Set((track.moods ?? []).map(NameKey.genre).filter { !$0.isEmpty })
            moods.append(set)
            for mood in set { byMood[mood, default: []].append(i) }
        }
        guard !byMood.isEmpty else { return graph }
        for (i, own) in moods.enumerated() where !own.isEmpty {
            var near: [Int: Double] = [:]
            for mood in own {
                for j in byMood[mood] ?? [] where j != i && near[j] == nil {
                    let shared = Double(own.intersection(moods[j]).count)
                    let jaccard = shared / Double(own.union(moods[j]).count)
                    near[j] = strongest * jaccard * tempo(tracks[i].bpm, tracks[j].bpm)
                }
            }
            let kept = near.filter { $0.value > 0.02 }
                .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
                .prefix(perTrack)
            for (j, weight) in kept {
                graph.addTrackEdge(from: tracks[i].id, to: tracks[j].id, weight: weight)
            }
        }
        return graph
    }

    /// 1 for the same tempo, nothing 40 beats apart; 0.7 when either has
    /// none (a mood alone says less). Half or double time counts as near:
    /// 70 and 140 are the same pulse.
    static func tempo(_ a: Int?, _ b: Int?) -> Double {
        guard let a, let b, a > 0, b > 0 else { return 0.7 }
        let x = Double(a), y = Double(b)
        let apart = min(abs(x - y), abs(2 * x - y), abs(x - 2 * y))
        return max(0, 1 - apart / 40)
    }
}
