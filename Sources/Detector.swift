import Vision
import CoreML

/// Steg 1: hitta produkter. Steg 2: hitta datumtext. Steg 3: para ihop och färgsätt.
final class Detector {
    private var productRequest: VNRequest
    private let textRequest: VNRecognizeTextRequest

    init() {
        // Lägg en tränad YOLO-modell i projektet och döp den till ProductDetector.mlmodel.
        // Finns ingen modell används enkel rektangeldetektering som ersättare.
        if let url = Bundle.main.url(forResource: "ProductDetector", withExtension: "mlmodelc"),
           let model = try? VNCoreMLModel(for: MLModel(contentsOf: url)) {
            let r = VNCoreMLRequest(model: model)
            r.imageCropAndScaleOption = .scaleFill
            productRequest = r
        } else {
            let r = VNDetectRectanglesRequest()
            r.minimumAspectRatio = 0.2
            r.minimumSize = 0.05
            r.minimumConfidence = 0.5
            r.maximumObservations = 30
            productRequest = r
        }
        textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .fast
        textRequest.usesLanguageCorrection = false
    }

    func analyze(_ buffer: CVPixelBuffer) -> ([Detection], [DateBox]) {
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up)
        try? handler.perform([productRequest, textRequest])

        // Produkter
        var boxes: [CGRect] = []
        if let objs = productRequest.results as? [VNRecognizedObjectObservation] {
            boxes = objs.filter { $0.confidence > 0.4 }.map { $0.boundingBox }
        } else if let rects = productRequest.results as? [VNRectangleObservation] {
            boxes = rects.map { $0.boundingBox }
        }

        // Datum
        var dates: [DateBox] = []
        for t in (textRequest.results ?? []) {
            guard let text = t.topCandidates(1).first?.string,
                  let date = DateParser.parse(text) else { continue }
            dates.append(DateBox(rect: t.boundingBox, date: date))
        }

        // Para ihop: ett datum hör till produkten som innehåller dess mittpunkt.
        let today = Calendar.current.startOfDay(for: Date())
        let products = boxes.map { box -> Detection in
            let match = dates.first { box.contains(CGPoint(x: $0.rect.midX, y: $0.rect.midY)) }
            guard let m = match else { return Detection(rect: box, status: .found, expiry: nil) }
            return Detection(rect: box, status: m.date < today ? .expired : .valid, expiry: m.date)
        }
        return (products, dates)
    }
}
