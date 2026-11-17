import Foundation

enum DateParser {
    /// Läser t.ex. 2027-03-15, 15.03.27, 08-12-2026 (dag-månad-år), 03/2027 (slutet av månaden).
    /// Datum som verkar orimliga (för gamla eller för långt fram) ignoreras.
    static func parse(_ raw: String) -> Date? {
        let s = raw.replacingOccurrences(of: " ", with: "")
        let candidates: [Date?] = [
            nums(s, #"(?<!\d)(\d{4})[-./](\d{1,2})[-./](\d{1,2})(?!\d)"#).flatMap { make($0[0], $0[1], $0[2]) },
            nums(s, #"(?<!\d)(\d{1,2})[-./](\d{1,2})[-./](\d{4}|\d{2})(?!\d)"#).flatMap { make($0[2], $0[1], $0[0]) },
            nums(s, #"(?<!\d)(\d{1,2})[-./](\d{4})(?!\d)"#).flatMap { endOfMonth($0[1], $0[0]) }
        ]
        return candidates.compactMap { $0 }.first(where: plausible)
    }

    static func format(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    private static func plausible(_ d: Date) -> Bool {
        let now = Date()
        let lo = now.addingTimeInterval(-60 * 60 * 24 * 730)
        let hi = now.addingTimeInterval(60 * 60 * 24 * 365 * 6)
        return d > lo && d < hi
    }

    private static func nums(_ s: String, _ pattern: String) -> [Int]? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        let ns = s as NSString
        return (1..<m.numberOfRanges).compactMap { Int(ns.substring(with: m.range(at: $0))) }
    }

    private static func make(_ y: Int, _ m: Int, _ d: Int) -> Date? {
        let year = y < 100 ? 2000 + y : y
        guard (2020...2100).contains(year), (1...12).contains(m), (1...31).contains(d) else { return nil }
        return Calendar.current.date(from: DateComponents(year: year, month: m, day: d))
    }

    private static func endOfMonth(_ y: Int, _ m: Int) -> Date? {
        guard let first = make(y, m, 1) else { return nil }
        return Calendar.current.date(byAdding: DateComponents(month: 1, day: -1), to: first)
    }
}
