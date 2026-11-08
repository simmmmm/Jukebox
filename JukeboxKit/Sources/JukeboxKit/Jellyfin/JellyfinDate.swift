// Jellyfin's dates, read by hand. It writes .NET's round-trip format with
// as many fractional digits as the value has: seven
// ("2026-11-08T01:26:04.5283094Z"), fewer when the last ones are zeros
// (seen on 12.4: "2026-11-08T01:26:17.446321Z"), or none. Foundation's
// ISO8601DateFormatter reads at most three fractional digits on some
// platforms and none unless told, and differs between Linux and Apple, so
// the format is parsed here, the same everywhere: plain arithmetic, no
// formatter, no calendar (fast enough for a library of 50 000 tracks with
// three dates each).
//
// Accepted: YYYY-MM-DD, then optionally T (or a space) and hh:mm, :ss,
// a fraction of any length, and Z, ±hh:mm, ±hhmm or ±hh. No zone is UTC:
// Jellyfin stores UTC and drops the Z on some fields of older servers.
// "0001-01-01T00:00:00" is .NET's DateTime.MinValue, Jellyfin's "never",
// and reads as nil.

import Foundation

enum JellyfinDate {
    static func parse(_ string: String) -> Date? {
        var p = Parser(Array(string.utf8))
        p.skipSpaces()
        guard let year = p.digits(exactly: 4), p.take(UInt8(ascii: "-")),
              let month = p.digits(exactly: 2), p.take(UInt8(ascii: "-")),
              let day = p.digits(exactly: 2) else { return nil }
        guard (1...12).contains(month), day >= 1, day <= daysIn(month: month, year: year) else { return nil }
        // DateTime.MinValue: "never".
        if year <= 1 { return nil }

        var hour = 0, minute = 0, second = 0
        var fraction = 0.0
        var offsetSeconds = 0
        if p.take(UInt8(ascii: "T")) || p.take(UInt8(ascii: "t")) || p.take(UInt8(ascii: " ")) {
            guard let h = p.digits(exactly: 2), p.take(UInt8(ascii: ":")),
                  let m = p.digits(exactly: 2) else { return nil }
            hour = h
            minute = m
            if p.take(UInt8(ascii: ":")) {
                guard let s = p.digits(exactly: 2) else { return nil }
                second = s
                if p.take(UInt8(ascii: ".")) || p.take(UInt8(ascii: ",")) {
                    guard let f = p.fraction() else { return nil }
                    fraction = f
                }
            }
            // 24:00:00 is allowed by ISO 8601 as the end of a day; 60 for a
            // leap second.
            guard hour <= 24, minute <= 59, second <= 60 else { return nil }
            if p.take(UInt8(ascii: "Z")) || p.take(UInt8(ascii: "z")) {
                offsetSeconds = 0
            } else if let sign = p.peek(), sign == UInt8(ascii: "+") || sign == UInt8(ascii: "-") {
                p.advance()
                guard let oh = p.digits(exactly: 2), oh <= 18 else { return nil }
                var om = 0
                if p.take(UInt8(ascii: ":")) {
                    guard let m = p.digits(exactly: 2) else { return nil }
                    om = m
                } else if let m = p.digits(exactly: 2) {
                    om = m
                }
                guard om <= 59 else { return nil }
                offsetSeconds = (oh * 3600 + om * 60) * (sign == UInt8(ascii: "-") ? -1 : 1)
            }
        }
        p.skipSpaces()
        guard p.atEnd else { return nil }

        let days = daysFromCivil(year: year, month: month, day: day)
        let whole = days * 86_400 + hour * 3600 + minute * 60 + second - offsetSeconds
        return Date(timeIntervalSince1970: Double(whole) + fraction)
    }

    /// Days since 1970-01-01 of a proleptic Gregorian date (Howard Hinnant's
    /// days_from_civil).
    static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let shiftedMonth = month > 2 ? month - 3 : month + 9
        let dayOfYear = (153 * shiftedMonth + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2:
            let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
            return leap ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    private struct Parser {
        let bytes: [UInt8]
        var index = 0

        init(_ bytes: [UInt8]) { self.bytes = bytes }

        var atEnd: Bool { index >= bytes.count }

        func peek() -> UInt8? { atEnd ? nil : bytes[index] }

        mutating func advance() { index += 1 }

        mutating func take(_ byte: UInt8) -> Bool {
            guard peek() == byte else { return false }
            index += 1
            return true
        }

        mutating func skipSpaces() {
            while let b = peek(), b == UInt8(ascii: " ") { index += 1 }
        }

        mutating func digits(exactly count: Int) -> Int? {
            guard index + count <= bytes.count else { return nil }
            var value = 0
            for i in index..<(index + count) {
                let b = bytes[i]
                guard b >= UInt8(ascii: "0"), b <= UInt8(ascii: "9") else { return nil }
                value = value * 10 + Int(b - UInt8(ascii: "0"))
            }
            index += count
            return value
        }

        /// The digits after the decimal point as a fraction of a second; any
        /// number of them, the ones past nanoseconds read and dropped.
        mutating func fraction() -> Double? {
            var value = 0
            var scale = 1
            var count = 0
            while let b = peek(), b >= UInt8(ascii: "0"), b <= UInt8(ascii: "9") {
                if count < 9 {
                    value = value * 10 + Int(b - UInt8(ascii: "0"))
                    scale *= 10
                }
                count += 1
                index += 1
            }
            guard count > 0 else { return nil }
            return Double(value) / Double(scale)
        }
    }
}
