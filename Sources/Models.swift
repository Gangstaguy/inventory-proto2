import UIKit

enum ProductStatus {
    case found      // blå: produkt hittad, inget datum
    case valid      // grön: datum hittat, ej utgången
    case expired    // röd: datum hittat, utgången

    var color: UIColor {
        switch self {
        case .found: return .systemBlue
        case .valid: return .systemGreen
        case .expired: return .systemRed
        }
    }
}

/// Alla rektanglar är normaliserade (0–1), Vision-format (origo nere till vänster).
struct Detection {
    var rect: CGRect
    var status: ProductStatus
    var expiry: Date?
}

struct DateBox {
    var rect: CGRect
    var date: Date
    var text: String   // råtexten som OCR läste, visas på skärmen för felsökning
}
