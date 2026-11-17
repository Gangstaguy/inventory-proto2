import CoreGraphics
import Foundation

/// Stabiliserar rutorna: visas först efter ett par träffar, glider mjukt,
/// förutsäger rörelsen och behåller rutan en stund om produkten tappas i någon bildruta.
final class BoxTracker {
    private struct Track {
        var rect: CGRect
        var vx: CGFloat = 0
        var vy: CGFloat = 0
        var hits: Int
        var misses: Int
        var expiry: Date?
        var dateAge: Int
    }

    private var tracks: [Track] = []
    private let confirmHits = 2
    private let maxMisses = 10

    static func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let i = a.intersection(b)
        if i.isNull { return 0 }
        let inter = i.width * i.height
        let union = a.width * a.height + b.width * b.height - inter
        return union > 0 ? inter / union : 0
    }

    /// 0 = ingen match. Tål snabba rörelser: nära mittpunkt + liknande storlek räcker.
    static func match(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let i = iou(a, b)
        let dx = a.midX - b.midX, dy = a.midY - b.midY
        let dist = (dx * dx + dy * dy).squareRoot()
        let ratio = (a.width * a.height) / max(b.width * b.height, 0.0001)
        let near: CGFloat = (dist < 0.12 && ratio > 0.4 && ratio < 2.5) ? 0.3 + (0.12 - dist) : 0
        return max(i, near)
    }

    static func blend(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(x: a.minX + (b.minX - a.minX) * t,
               y: a.minY + (b.minY - a.minY) * t,
               width: a.width + (b.width - a.width) * t,
               height: a.height + (b.height - a.height) * t)
    }

    func update(_ raw: [Detection], dates: [DateBox]) -> [Detection] {
        // Para ihop produkter med datum som "hålls kvar" av DateTracker.
        let detections = raw.map { det -> Detection in
            var d = det
            if let m = dates.first(where: { det.rect.contains(CGPoint(x: $0.rect.midX, y: $0.rect.midY)) }) {
                d.expiry = m.date
            }
            return d
        }

        var unmatched = Array(detections.indices)
        for i in tracks.indices {
            let predicted = tracks[i].rect.offsetBy(dx: tracks[i].vx, dy: tracks[i].vy)
            var bestJ: Int? = nil
            var bestScore: CGFloat = 0.2
            for j in unmatched {
                let s = BoxTracker.match(predicted, detections[j].rect)
                if s > bestScore { bestScore = s; bestJ = j }
            }
            if let j = bestJ {
                let d = detections[j]
                let new = BoxTracker.blend(predicted, d.rect, 0.5)
                tracks[i].vx = 0.5 * tracks[i].vx + 0.5 * (new.midX - tracks[i].rect.midX)
                tracks[i].vy = 0.5 * tracks[i].vy + 0.5 * (new.midY - tracks[i].rect.midY)
                tracks[i].rect = new
                tracks[i].hits += 1
                tracks[i].misses = 0
                if let e = d.expiry {
                    tracks[i].expiry = e
                    tracks[i].dateAge = 0
                } else {
                    tracks[i].dateAge += 1
                }
                unmatched.removeAll { $0 == j }
            } else {
                // Tappad i den här bildrutan: glid vidare i samma riktning.
                tracks[i].rect = predicted
                tracks[i].vx *= 0.7
                tracks[i].vy *= 0.7
                tracks[i].misses += 1
            }
            if tracks[i].dateAge > 15 { tracks[i].expiry = nil }
        }
        for j in unmatched {
            let d = detections[j]
            tracks.append(Track(rect: d.rect, hits: 1, misses: 0, expiry: d.expiry, dateAge: 0))
        }
        tracks.removeAll { $0.misses > maxMisses }

        let today = Calendar.current.startOfDay(for: Date())
        return tracks.filter { $0.hits >= confirmHits }.map { t in
            var status = ProductStatus.found
            if let e = t.expiry { status = e < today ? .expired : .valid }
            return Detection(rect: t.rect, status: status, expiry: t.expiry)
        }
    }
}

/// Håller kvar datumrutor en stund så de inte blinkar.
final class DateTracker {
    private var items: [(box: DateBox, age: Int)] = []

    func update(_ new: [DateBox]) -> [DateBox] {
        for i in items.indices { items[i].age += 1 }
        for n in new {
            if let k = items.firstIndex(where: { BoxTracker.match($0.box.rect, n.rect) > 0.2 }) {
                items[k] = (box: n, age: 0)
            } else {
                items.append((box: n, age: 0))
            }
        }
        items.removeAll { $0.age > 8 }
        return items.map { $0.box }
    }
}
