import Foundation
import CoreGraphics
import CoreVideo

/// Hela kedjan för en bildruta:
/// hitta rutor → läs datum → spåra → fingeravtryck → sök i produktindexet.
final class Pipeline {
    private let detector = Detector()
    private let productTracker = BoxTracker()
    private let dateTracker = DateTracker()
    private let embedder = Embedder()
    private let index = ProductIndex()

    var statusText: String {
        let modell = embedder != nil ? "modell ✓" : "modell saknas"
        let idx = index.map { "index \($0.count) bilder" } ?? "index saknas"
        return "\(modell) · \(idx)"
    }

    func process(_ buffer: CVPixelBuffer) -> ([Detection], [DateBox], CGSize) {
        let (raw, dates, size) = detector.analyze(buffer)
        let heldDates = dateTracker.update(dates)
        var products = productTracker.update(raw, dates: heldDates)

        if let embedder = embedder, let index = index {
            let orient = Detector.orientation(of: buffer)
            // Högst 2 nya fingeravtryck per bildruta så att appen hänger med.
            for id in productTracker.idsNeedingIdentification(limit: 2) {
                guard let rect = productTracker.rect(of: id),
                      let v = embedder.embed(buffer: buffer, orientation: orient, rect: rect),
                      let avg = productTracker.addEmbedding(id, v) else { continue }
                productTracker.setMatches(id, index.search(avg, k: 3))
            }
            products = productTracker.snapshot()
        }
        return (products, heldDates, size)
    }
}
