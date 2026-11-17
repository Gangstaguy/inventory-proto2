import CoreGraphics
import Foundation

/// Stabiliserar rutorna: en ruta visas först när den setts i flera bildrutor i rad,
/// och den glider mjukt i stället för att hoppa. Datum "minns" i några bildrutor.
final class BoxTracker {
    private struct Track {
        var rect: CGRect
        var hits: Int
        var misses: Int
        var expiry: Date?
        var dateAge: Int
    }

    private var tracks: [Track] = []
    private let confirmHits = 3
    private let maxMisses = 4

    static func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let i = a.intersection(b)
        if i.isNull { return 0 }
        let inter = i.width * i.height
        let union = a.width * a.height + b.width * b.height - inter
        return union > 0 ? inter / union : 0
    }

    static func blend(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(x: a.minX + (b.minX - a.minX) * t,
               y: a.minY + (b.minY - a.minY) * t,
               width: a.width + (b.width - a.width) * t,
               height: a.height + (b.height - a.height) * t)
    }

    func update(_ detections: [Detection]) -> [Detection] {
        var unmatched = Array(detections.indices)
        for i in tracks.indices {
            var bestJ: Int? = nil
            var bestIou: CGFloat = 0.3
            for j in unmatched {
                let v = BoxTracker.iou(tracks[i].rect, detections[j].rect)
                if v > bestIou { bestIou = v; bestJ = j }
            }
            if let j = bestJ {
                let d = detections[j]
                tracks[i].rect = BoxTracker.blend(tracks[i].rect, d.rect, 0.4)
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
                tracks[i].misses += 1
            }
            if tracks[i].dateAge > 8 { tracks[i].expiry = nil }
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

final class DateTracker {
    private var items: [(box: DateBox, age: Int)] = []

    func update(_ new: [DateBox]) -> [DateBox] {
        for i in items.indices { items[i].age += 1 }
        for n in new {
            if let k = items.firstIndex(where: { BoxTracker.iou($0.box.rect, n.rect) > 0.3 }) {
                items[k] = (box: n, age: 0)
            } else {
                items.append((box: n, age: 0))
            }
        }
        items.removeAll { $0.age > 3 }
        return items.map { $0.box }
    }
}
