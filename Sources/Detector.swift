import Vision
import CoreML
import CoreImage
import ImageIO

/// Hittar förslag på produkter (rektanglar + förgrundsobjekt av vilken form som helst)
/// och läser all text. Vilken produkt det är avgörs senare av fingeravtryck, märke och text.
final class Detector {
    private var productRequest: VNRequest
    private let textRequest: VNRecognizeTextRequest
    private var frameCount = 0

    init() {
        // Lägg en tränad YOLO-modell i projektet och döp den till ProductDetector.mlmodel.
        // Finns ingen modell används enkel rektangeldetektering + förgrundsobjekt som ersättare.
        if let url = Bundle.main.url(forResource: "ProductDetector", withExtension: "mlmodelc"),
           let model = try? VNCoreMLModel(for: MLModel(contentsOf: url)) {
            let r = VNCoreMLRequest(model: model)
            r.imageCropAndScaleOption = .scaleFill
            productRequest = r
        } else {
            let r = VNDetectRectanglesRequest()
            r.minimumAspectRatio = 0.28
            r.minimumSize = 0.11
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

    func analyze(_ buffer: CVPixelBuffer) -> Analysis {
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

        // Förslag på produkter.
        var boxes: [CGRect] = []
        if let objs = productRequest.results as? [VNRecognizedObjectObservation] {
            boxes = objs.filter { $0.confidence > 0.3 }.map { $0.boundingBox }
        } else if let rects = productRequest.results as? [VNRectangleObservation] {
            boxes = rects.map { $0.boundingBox }
        }
        // Förgrundsobjekt av vilken form som helst (iOS 17+), på de bildrutor som inte kör extra OCR.
        if !useBlur, #available(iOS 17.0, *) {
            boxes += foregroundBoxes(handler)
        }
        boxes = Detector.nms(boxes)

        // All text (för märke och produktnamn) + datum.
        var lines: [TextLine] = []
        var dates: [DateBox] = []
        for t in (textRequest.results ?? []) {
            guard let cand = t.topCandidates(1).first else { continue }
            let text = cand.string
            if cand.confidence > 0.3 {
                lines.append(TextLine(rect: t.boundingBox, text: text))
            }
            if let date = DateParser.parse(text) {
                dates.append(DateBox(rect: t.boundingBox, date: date, text: text))
            }
        }

        let products = boxes.map { Detection(rect: $0, status: .found, expiry: nil) }
        return Analysis(products: products, dates: dates, lines: lines, size: size)
    }

    /// Tar bort dubbletter: behåller den största av rutor som täcker i stort sett samma sak.
    static func nms(_ boxes: [CGRect], iou: CGFloat = 0.6) -> [CGRect] {
        let sorted = boxes.sorted { $0.width * $0.height > $1.width * $1.height }
        var keep: [CGRect] = []
        for b in sorted where !keep.contains(where: { BoxTracker.iou($0, b) > iou }) {
            keep.append(b)
        }
        return keep
    }

    /// Apples förgrundsmask: hittar föremål som sticker ut, oavsett form (flaskor, påsar, burkar).
    @available(iOS 17.0, *)
    private func foregroundBoxes(_ handler: VNImageRequestHandler) -> [CGRect] {
        let req = VNGenerateForegroundInstanceMaskRequest()
        do { try handler.perform([req]) } catch { return [] }
        guard let obs = req.results?.first else { return [] }

        let mask = obs.instanceMask
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        guard CVPixelBufferGetPixelFormatType(mask) == kCVPixelFormatType_OneComponent8,
              let base = CVPixelBufferGetBaseAddress(mask) else { return [] }

        let mw = CVPixelBufferGetWidth(mask)
        let mh = CVPixelBufferGetHeight(mask)
        let stride = CVPixelBufferGetBytesPerRow(mask)
        let p = base.assumingMemoryBound(to: UInt8.self)

        var minX = [Int](repeating: mw, count: 256)
        var maxX = [Int](repeating: -1, count: 256)
        var minY = [Int](repeating: mh, count: 256)
        var maxY = [Int](repeating: -1, count: 256)
        for y in 0..<mh {
            let row = p + y * stride
            for x in 0..<mw {
                let v = Int(row[x])
                if v == 0 { continue }
                if x < minX[v] { minX[v] = x }
                if x > maxX[v] { maxX[v] = x }
                if y < minY[v] { minY[v] = y }
                if y > maxY[v] { maxY[v] = y }
            }
        }

        var out: [CGRect] = []
        for v in 1..<256 where maxX[v] >= 0 {
            let bw = CGFloat(maxX[v] - minX[v] + 1) / CGFloat(mw)
            let bh = CGFloat(maxY[v] - minY[v] + 1) / CGFloat(mh)
            if bw * bh < 0.02 { continue }          // för små
            if bw * bh > 0.92 { continue }          // hela bilden
            out.append(CGRect(x: CGFloat(minX[v]) / CGFloat(mw),
                              y: 1 - CGFloat(maxY[v] + 1) / CGFloat(mh),
                              width: bw, height: bh))
        }
        return out
    }
}
