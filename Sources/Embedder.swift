import Vision
import CoreML
import CoreImage
import ImageIO

/// Gör ett fingeravtryck (512 tal) av en utklippt produkt med Core ML-modellen.
final class Embedder {
    private let request: VNCoreMLRequest

    init?() {
        guard let url = Bundle.main.url(forResource: "ProductEmbedder", withExtension: "mlmodelc"),
              let ml = try? MLModel(contentsOf: url),
              let vm = try? VNCoreMLModel(for: ml) else { return nil }
        let r = VNCoreMLRequest(model: vm)
        r.imageCropAndScaleOption = .centerCrop   // samma som indexet: mitten-kvadrat av produktbilden
        request = r
    }

    /// `rect` är normaliserad (Vision-format) i den upprätta bilden.
    func embed(buffer: CVPixelBuffer, orientation: CGImagePropertyOrientation, rect: CGRect) -> [Float]? {
        let upright = CIImage(cvPixelBuffer: buffer).oriented(orientation)
        let ext = upright.extent
        let box = CGRect(x: ext.minX + rect.minX * ext.width,
                         y: ext.minY + rect.minY * ext.height,
                         width: rect.width * ext.width,
                         height: rect.height * ext.height).intersection(ext)
        guard !box.isNull, box.width > 16, box.height > 16 else { return nil }

        let crop = upright.cropped(to: box)
            .transformed(by: CGAffineTransform(translationX: -box.minX, y: -box.minY))
        let handler = VNImageRequestHandler(ciImage: crop, orientation: .up)
        do { try handler.perform([request]) } catch { return nil }

        guard let obs = request.results?.first as? VNCoreMLFeatureValueObservation,
              let arr = obs.featureValue.multiArrayValue else { return nil }
        var v = [Float](repeating: 0, count: arr.count)
        var sum: Float = 0
        for i in 0..<arr.count {
            let x = arr[i].floatValue
            v[i] = x
            sum += x * x
        }
        let norm = sum.squareRoot()
        guard norm > 0 else { return nil }
        return v.map { $0 / norm }
    }
}
