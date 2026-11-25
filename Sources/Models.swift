import UIKit

/// Justera här efter att du testat på riktiga produkter.
enum Config {
    /// Poäng (bildlikhet + text/märke) under detta markeras som osäker.
    static let minScore: Float = 0.80
    /// Om bästa och näst bästa produkt ligger närmare varandra än så här markeras träffen som osäker.
    static let minMargin: Float = 0.03
    /// Bonus när märket (t.ex. ICA, Coop) syns i texten på förpackningen.
    static let brandBoost: Float = 0.12
    /// Avdrag när ett annat märke syns i texten än det träffen har.
    static let brandMismatch: Float = 0.10
    /// Bonus när produktnamnets ord syns i texten (0–1 gånger detta).
    static let titleBoost: Float = 0.10
}

struct ProductMatch {
    var streckkod: String
    var titel: String
    var varumarke: String
    var mangd: String
    var score: Float          // slutpoäng: bildlikhet + text/märke (används för beslut)
    var sim: Float            // ren bildlikhet (cosinus 0–1), inte en sannolikhet
    var brandHit: Bool        // märket syns i texten
    var brandMismatch: Bool   // ett annat märke syns i texten
    var titleCov: Float       // andel av produktnamnets ord som syns i texten
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

/// En rad text som kameran läst (för märke och produktnamn).
struct TextLine {
    var rect: CGRect
    var text: String
}

struct Analysis {
    var products: [Detection]
    var dates: [DateBox]
    var lines: [TextLine]
    var size: CGSize
}
