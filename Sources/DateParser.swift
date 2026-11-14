import Foundation

enum DateParser {
    /// Läser t.ex. 2027-03-15, 15.03.27, 15/03/2027, 03/2027 (slutet av månaden).
    static func parse(_ raw: String) -> Date? {
        let s = raw.replacingOccurrences(of: " ", with: "")
        if let n = nums(s, #"(\d{4})[-./](\d{1,2})[-./](\d{1,2})"#) { return make(n[0], n[1], n[2]) }
        if let n = nums(s, #"(\d{1,2})[-./](\d{1,2})[-./](\d{2,4})"#) { return make(n[2], n[1], n[0]) }
        if let n = nums(s, #"(\d{1,2})[-./](\d{4})"#) { return endOfMonth(n[1], n[0]) }
        return nil
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
