import Foundation
import Accelerate

/// Sökindex över alla produktbilder (fingeravtryck). Läses från appens Data-filer.
final class ProductIndex {
    private static let dim = 512

    let count: Int
    private var matrix: [Float]     // count * 512, normaliserade vektorer
    private var scores: [Float]
    private let meta: [[String]]    // [streckkod, titel, varumärke, mängd] per rad

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
        self.count = n
        self.matrix = m
        self.scores = [Float](repeating: 0, count: n)
        self.meta = meta
    }

    /// Returnerar de k bästa *produkterna* (en träff per streckkod).
    func search(_ query: [Float], k: Int = 3) -> [ProductMatch] {
        let dim = ProductIndex.dim
        guard query.count == dim else { return [] }
        var sum: Float = 0
        for x in query { sum += x * x }
        let norm = sum.squareRoot()
        guard norm > 0 else { return [] }
        let q = query.map { $0 / norm }

        vDSP_mmul(matrix, 1, q, 1, &scores, 1, vDSP_Length(count), 1, vDSP_Length(dim))

        let best = (0..<count).sorted { scores[$0] > scores[$1] }.prefix(80)
        var seen = Set<String>()
        var out: [ProductMatch] = []
        for i in best {
            let m = meta[i]
            if seen.contains(m[0]) { continue }
            seen.insert(m[0])
            out.append(ProductMatch(streckkod: m[0], titel: m[1], varumarke: m[2],
                                    mangd: m[3], score: scores[i]))
            if out.count == k { break }
        }
        return out
    }
}
