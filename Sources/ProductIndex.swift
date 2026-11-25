import Foundation
import Accelerate

/// Sökindex över alla produktbilder (fingeravtryck), sorterat även per märke.
/// Sökningen kombinerar bildlikhet med märke och text som kameran läst.
final class ProductIndex {
    private static let dim = 512

    let count: Int
    private var matrix: [Float]     // count * 512, normaliserade vektorer
    private var scores: [Float]
    private var adjusted: [Float]
    private let meta: [[String]]    // [streckkod, titel, varumärke, mängd] per rad

    // Märkesregister: varje märke ("ica", "coop", "garant"...) med sina ord och rader.
    private let rowEntries: [[Int32]]
    private let entryTokens: [[String]]
    private let entryRows: [[Int32]]

    init?() {
        guard let vUrl = Bundle.main.url(forResource: "index_vektorer", withExtension: "bin"),
              let sUrl = Bundle.main.url(forResource: "index_skala", withExtension: "bin"),
              let mUrl = Bundle.main.url(forResource: "index_meta", withExtension: "json"),
              let vData = try? Data(contentsOf: vUrl),
              let sData = try? Data(contentsOf: sUrl),
              let mData = try? Data(contentsOf: mUrl),
              let meta = try? JSONDecoder().decode([[String]].self, from: mData) else { return nil }

        let n = meta.count
        let dim = ProductIndex.dim
        guard n > 0, vData.count == n * dim, sData.count == n * 4 else { return nil }
        guard meta.allSatisfy({ $0.count >= 4 }) else { return nil }

        // Avkvantisera int8 -> Float32 (en gång vid start).
        var m = [Float](repeating: 0, count: n * dim)
        vData.withUnsafeBytes { (vRaw: UnsafeRawBufferPointer) in
            sData.withUnsafeBytes { (sRaw: UnsafeRawBufferPointer) in
                let q = vRaw.bindMemory(to: Int8.self)
                let s = sRaw.bindMemory(to: Float.self)
                for i in 0..<n {
                    let sc = s[i]
                    let base = i * dim
                    for j in 0..<dim {
                        m[base + j] = Float(q[base + j]) * sc
                    }
                }
            }
        }

        // Bygg märkesregistret (märken kan stå som "ICA, ICA Basic" -> två märken).
        var entryIndex: [String: Int] = [:]
        var tokens: [[String]] = []
        var rows: [[Int32]] = []
        var rowEntries = [[Int32]](repeating: [], count: n)
        for i in 0..<n {
            let parts = meta[i][2].split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "/" })
            for part in parts {
                let key = TextMatch.normalize(String(part)).trimmingCharacters(in: .whitespaces)
                if key.isEmpty { continue }
                let e: Int
                if let existing = entryIndex[key] {
                    e = existing
                } else {
                    e = tokens.count
                    entryIndex[key] = e
                    tokens.append(TextMatch.tokens(key))
                    rows.append([])
                }
                rows[e].append(Int32(i))
                rowEntries[i].append(Int32(e))
            }
        }

        self.count = n
        self.matrix = m
        self.scores = [Float](repeating: 0, count: n)
        self.adjusted = [Float](repeating: 0, count: n)
        self.meta = meta
        self.rowEntries = rowEntries
        self.entryTokens = tokens
        self.entryRows = rows
    }

    /// Vilka märken syns i texten? (alla ord i märkesnamnet måste synas)
    private func detectedBrands(_ words: Set<String>) -> Set<Int32> {
        var out = Set<Int32>()
        if words.isEmpty { return out }
        for e in 0..<entryTokens.count {
            let t = entryTokens[e]
            if t.isEmpty { continue }
            if t.count == 1 && t[0].count < 3 { continue }
            if t.allSatisfy({ TextMatch.hit($0, in: words) }) { out.insert(Int32(e)) }
        }
        return out
    }

    private func topIndices(_ a: [Float], k: Int) -> [Int] {
        var idx: [Int] = []
        idx.reserveCapacity(k + 1)
        var floor = -Float.infinity
        for i in 0..<a.count {
            let v = a[i]
            if idx.count == k && v <= floor { continue }
            var pos = idx.count
            while pos > 0 && a[idx[pos - 1]] < v { pos -= 1 }
            idx.insert(i, at: pos)
            if idx.count > k { idx.removeLast() }
            if idx.count == k { floor = a[idx[k - 1]] }
        }
        return idx
    }

    /// Returnerar de k bästa *produkterna* (en träff per streckkod).
    /// `words` = ord som kameran läst på just den här förpackningen.
    func search(_ query: [Float], words: Set<String>, k: Int = 3) -> [ProductMatch] {
        let dim = ProductIndex.dim
        guard query.count == dim else { return [] }
        var sum: Float = 0
        for x in query { sum += x * x }
        let norm = sum.squareRoot()
        guard norm > 0 else { return [] }
        let q = query.map { $0 / norm }

        vDSP_mmul(matrix, 1, q, 1, &scores, 1, vDSP_Length(count), 1, vDSP_Length(dim))

        // Märken som syns i texten får förtur i urvalet av kandidater.
        let detected = detectedBrands(words)
        adjusted = scores
        if !detected.isEmpty {
            var boosted = Set<Int32>()
            for e in detected { for r in entryRows[Int(e)] { boosted.insert(r) } }
            for r in boosted { adjusted[Int(r)] += Config.brandBoost }
        }

        var seen = Set<String>()
        var cands: [ProductMatch] = []
        for i in topIndices(adjusted, k: 120) {
            let m = meta[i]
            if seen.contains(m[0]) { continue }
            seen.insert(m[0])

            let brandHit = rowEntries[i].contains { detected.contains($0) }
            let mismatch = !detected.isEmpty && !brandHit
            let cov = TextMatch.coverage(of: m[1], in: words)

            var final = scores[i] + Config.titleBoost * cov
            if brandHit { final += Config.brandBoost }
            if mismatch { final -= Config.brandMismatch }

            cands.append(ProductMatch(streckkod: m[0], titel: m[1], varumarke: m[2], mangd: m[3],
                                      score: final, sim: scores[i], brandHit: brandHit,
                                      brandMismatch: mismatch, titleCov: cov))
            if cands.count >= 40 { break }
        }
        cands.sort { $0.score > $1.score }
        return Array(cands.prefix(k))
    }
}
