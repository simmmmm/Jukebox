// The number an album's page shows beside each song: the file's own track
// number, on its disc. "De nummers tellen nu gewoon op terwijl ze eigenlijk
// gematched zouden moeten zijn met hoeveelste nummer het is op t album of
// welke cd" (the photographer, 22 November 2026), of the day before's
// count of 1, 2, 3 by place.
//
// - A song with a number shows it, under a chosen version too: a version's
//   songs keep the numbers they have on the album.
// - A song without one shows none, while others on the album have theirs.
// - An album where no song has a number (a rip, the Oasis anniversary
//   album) counts its songs by their place on their disc instead, in the
//   whole album's order, so a version's songs keep those places as well.
// - Merged parts (AlbumMerge) are discs already; their files' numbers stand.

import Foundation

public enum AlbumNumbers {
    /// Each song's number by its id, for an album's songs in the album's
    /// order (disc, number, name); nil for a song that shows none.
    public static func of(_ album: [Track]) -> [ItemID: Int] {
        var numbers: [ItemID: Int] = [:]
        if album.contains(where: { $0.trackNumber != nil }) {
            for track in album {
                if let number = track.trackNumber { numbers[track.id] = number }
            }
            return numbers
        }
        var disc: Int?
        var place = 0
        for track in album {
            let this = track.discNumber ?? 1
            place = this == disc ? place + 1 : 1
            disc = this
            numbers[track.id] = place
        }
        return numbers
    }
}
