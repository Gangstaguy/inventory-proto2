import UIKit

/// Justera här efter att du testat på riktiga produkter.
enum Config {
    /// Under detta likhetsvärde markeras en träff som osäker.
    static let minScore: Float = 0.75
    /// Om bästa och näst bästa produkt ligger närmare varandra än så här markeras träffen som osäker.
    static let minMargin: Float = 0.03
}

struct ProductMatch {
    var streckkod: String
    var titel: String
    var varumarke: String
    var mangd: String
    var score: Float      // likhet 0–1 (cosinus), inte en sannolikhet
}

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
    var id: Int = -1
    var match: ProductMatch? = nil
    var margin: Float = 1                 // skillnad mellan bästa och näst bästa produkt
    var alternative: ProductMatch? = nil  // näst bästa produkt
}

struct DateBox {
    var rect: CGRect
    var date: Date
    var text: String   // råtexten som OCR läste, visas på skärmen för felsökning
}
