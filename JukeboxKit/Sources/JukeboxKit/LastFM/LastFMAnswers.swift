// Last.fm's JSON, read leniently. Its answers are XML turned into JSON on
// the server, and it shows: `match` is a string in artist.getsimilar
// ("0.87") and a number in track.getsimilar (0.87); play counts and ranks
// are strings in artist.gettoptracks; a list of one is sometimes the one
// object rather than an array of it; an empty list is sometimes "" or
// missing. Every number here may come as a string or a number, every list as
// a list, one object or nothing, and an element that does not read is left
// out rather than failing the whole answer.

import Foundation

/// A number as Last.fm writes it: 0.87, "0.87", 12, "12", or nothing.
struct LastFMNumber: Decodable, Sendable {
    let value: Double?

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
        } else if let number = try? container.decode(Double.self) {
            value = number.isFinite ? number : nil
        } else if let text = try? container.decode(String.self) {
            let number = Double(text.trimmingCharacters(in: .whitespaces))
            value = number.flatMap { $0.isFinite ? $0 : nil }
        } else {
            value = nil
        }
    }
}

/// A name as Last.fm writes it: a string, or (for an artist named "311") a
/// number.
struct LastFMText: Decodable, Sendable {
    let value: String

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            value = text
        } else if let number = try? container.decode(Int.self) {
            value = String(number)
        } else {
            value = ""
        }
    }
}

/// A track's artist: {"name": "…", "mbid": …} in most answers, {"#text": "…"}
/// in some, a plain string in others.
struct LastFMArtistName: Decodable, Sendable {
    let value: String

    enum CodingKeys: String, CodingKey {
        case name
        case text = "#text"
    }

    init(from decoder: any Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            let name = (try? container.decodeIfPresent(LastFMText.self, forKey: .name))?.value
            let text = (try? container.decodeIfPresent(LastFMText.self, forKey: .text))?.value
            value = name ?? text ?? ""
        } else {
            value = (try? LastFMText(from: decoder))?.value ?? ""
        }
    }
}

/// A list as Last.fm writes it: an array, one object, or "" / nothing.
struct LastFMList<Element: Decodable & Sendable>: Decodable, Sendable {
    let items: [Element]

    /// Takes any value and nothing from it: what moves an array past an
    /// element that did not read.
    private struct Skip: Decodable {
        init(from decoder: any Decoder) throws {}
    }

    init(from decoder: any Decoder) throws {
        if var array = try? decoder.unkeyedContainer() {
            var items: [Element] = []
            while !array.isAtEnd {
                if let item = try? array.decode(Element.self) {
                    items.append(item)
                } else if (try? array.decode(Skip.self)) == nil {
                    // Neither read: the container did not move, so stop
                    // rather than loop.
                    break
                }
            }
            self.items = items
        } else if let one = try? Element(from: decoder) {
            items = [one]
        } else {
            items = []
        }
    }
}

/// {"error": 10, "message": "Invalid API key - You must be granted a valid key by last.fm"}
struct LastFMErrorAnswer: Decodable, Sendable {
    let error: LastFMNumber?
    let message: LastFMText?
}

/// artist.getsimilar:
/// {"similarartists": {"artist": [{"name": "Cher", "mbid": "…", "match": "1", "url": "…"}], "@attr": {"artist": "…"}}}
struct LastFMSimilarArtistsAnswer: Decodable, Sendable {
    struct Body: Decodable, Sendable {
        let artist: LastFMList<Item>?
    }

    struct Item: Decodable, Sendable {
        let name: LastFMText?
        let match: LastFMNumber?
    }

    let similarartists: Body?
}

/// track.getsimilar:
/// {"similartracks": {"track": [{"name": "…", "playcount": 123, "match": 0.87, "artist": {"name": "…"}}]}}
struct LastFMSimilarTracksAnswer: Decodable, Sendable {
    struct Body: Decodable, Sendable {
        let track: LastFMList<Item>?
    }

    struct Item: Decodable, Sendable {
        let name: LastFMText?
        let match: LastFMNumber?
        let artist: LastFMArtistName?
    }

    let similartracks: Body?
}

/// artist.gettoptracks:
/// {"toptracks": {"track": [{"name": "…", "playcount": "123", "listeners": "45", "@attr": {"rank": "1"}}]}}
struct LastFMTopTracksAnswer: Decodable, Sendable {
    struct Body: Decodable, Sendable {
        let track: LastFMList<Item>?
    }

    struct Item: Decodable, Sendable {
        struct Attributes: Decodable, Sendable {
            let rank: LastFMNumber?
        }

        let name: LastFMText?
        let playcount: LastFMNumber?
        let attributes: Attributes?

        enum CodingKeys: String, CodingKey {
            case name, playcount
            case attributes = "@attr"
        }
    }

    let toptracks: Body?
}
