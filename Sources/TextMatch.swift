import Foundation

/// Hjälpmedel för att jämföra text från kameran med märken och produktnamn.
enum TextMatch {
    static let stopp: Set<String> = ["och", "med", "utan", "the", "for", "pa", "av", "en", "ett",
                                     "kg", "ml", "cl", "dl", "st", "pkt", "gram"]

    /// Små bokstäver utan accenter: "Köttbuljong" -> "kottbuljong".
    static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }

    static func tokens(_ s: String) -> [String] {
        normalize(s)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
    }

    /// Finns ordet bland de lästa orden? Små läsfel (1 tecken) tillåts i ord med minst 5 tecken.
    static func hit(_ t: String, in words: Set<String>) -> Bool {
        if words.contains(t) { return true }
        guard t.count >= 5 else { return false }
        for w in words where abs(w.count - t.count) <= 1 {
            if distance(w, t) <= 1 { return true }
        }
        return false
    }

    /// Andel av produktnamnets ord (minst 3 tecken) som syns i texten.
    static func coverage(of title: String, in words: Set<String>) -> Float {
        let t = tokens(title).filter { $0.count >= 3 && !stopp.contains($0) }
        guard !t.isEmpty, !words.isEmpty else { return 0 }
        let hits = t.filter { hit($0, in: words) }.count
        return Float(hits) / Float(t.count)
    }

    static func distance(_ a: String, _ b: String) -> Int {
        let x = Array(a.utf8), y = Array(b.utf8)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var prev = Array(0...y.count)
        var cur = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            cur[0] = i
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &cur)
        }
        return prev[y.count]
    }
}
