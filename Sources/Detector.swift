import Vision
import CoreML
import CoreImage
import ImageIO

/// Steg 1: hitta produkter. Steg 2: hitta datumtext. Paras ihop i BoxTracker.
final class Detector {
    private var productRequest: VNRequest
    private let textRequest: VNRecognizeTextRequest
    private var frameCount = 0

    init() {
        // Lägg en tränad YOLO-modell i projektet och döp den till ProductDetector.mlmodel.
        // Finns ingen modell används enkel rektangeldetektering som ersättare.
        if let url = Bundle.main.url(forResource: "ProductDetector", withExtension: "mlmodelc"),
           let model = try? VNCoreMLModel(for: MLModel(contentsOf: url)) {
            let r = VNCoreMLRequest(model: model)
            r.imageCropAndScaleOption = .scaleFill
            productRequest = r
        } else {
            // Känslighet v4 (v2 = 1,0 · v3 = ca 1,9 · v4 = ca 1,4)
            let r = VNDetectRectanglesRequest()
            r.minimumAspectRatio = 0.28
            r.minimumSize = 0.11           // minst 11 % av bilden
            r.minimumConfidence = 0.7
            r.quadratureTolerance = 17
            r.maximumObservations = 8
            productRequest = r
        }
        textRequest = VNRecognizeTextRequest()
        textRequest.usesLanguageCorrection = false
        textRequest.recognitionLanguages = ["en-US"]
    }

    /// Liggande buffert vrids upprätt åt Vision och Core Image.
    static func orientation(of buffer: CVPixelBuffer) -> CGImagePropertyOrientation {
        CVPixelBufferGetWidth(buffer) > CVPixelBufferGetHeight(buffer) ? .right : .up
    }

    /// Returnerar produktrutor, datumrutor och bildens storlek (upprätt).
    func analyze(_ buffer: CVPixelBuffer) -> ([Detection], [DateBox], CGSize) {
        frameCount += 1
        let w = CVPixelBufferGetWidth(buffer)
        let h = CVPixelBufferGetHeight(buffer)
        let landscape = w > h
        let orient = Detector.orientation(of: buffer)
        let size = landscape ? CGSize(width: h, height: w) : CGSize(width: w, height: h)

        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: orient)
        // Varannan bildruta: suddar ihop prickar (prickmatristext) och höjer kontrasten före OCR.
        let useBlur = frameCount % 2 == 0
        textRequest.recognitionLevel = useBlur ? .accurate : .fast
        if useBlur {
            let ci = CIImage(cvPixelBuffer: buffer)
            let processed = ci.applyingGaussianBlur(sigma: 1.5)
                .cropped(to: ci.extent)
                .applyingFilter("CIColorControls",
                                parameters: [kCIInputSaturationKey: 0.0, kCIInputContrastKey: 1.8])
            let textHandler = VNImageRequestHandler(ciImage: processed, orientation: orient)
            try? handler.perform([productRequest])
            try? textHandler.perform([textRequest])
        } else {
            try? handler.perform([productRequest, textRequest])
        }

        var boxes: [CGRect] = []
        if let objs = productRequest.results as? [VNRecognizedObjectObservation] {
            boxes = objs.filter { $0.confidence > 0.3 }.map { $0.boundingBox }
        } else if let rects = productRequest.results as? [VNRectangleObservation] {
            boxes = rects.map { $0.boundingBox }
        }

        var dates: [DateBox] = []
        for t in (textRequest.results ?? []) {
            guard let text = t.topCandidates(1).first?.string,
                  let date = DateParser.parse(text) else { continue }
            dates.append(DateBox(rect: t.boundingBox, date: date, text: text))
        }

        let products = boxes.map { Detection(rect: $0, status: .found, expiry: nil) }
        return (products, dates, size)
    }
}
