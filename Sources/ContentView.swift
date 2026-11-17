import SwiftUI
import AVFoundation

final class CameraView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    private var overlays: [CALayer] = []

    func show(_ products: [Detection], _ dates: [DateBox], imageSize: CGSize) {
        overlays.forEach { $0.removeFromSuperlayer() }
        overlays = []
        let today = Calendar.current.startOfDay(for: Date())
        for p in products { add(p.rect, imageSize, color: p.status.color, width: 3) }
        // Datum: gul = gäller, orange = har passerat.
        for d in dates {
            add(d.rect, imageSize, color: d.date < today ? .systemOrange : .systemYellow, width: 2)
        }
    }

    /// Vision-ruta (0–1, origo nere till vänster) → skärmkoordinater för resizeAspectFill.
    private func convert(_ r: CGRect, _ img: CGSize) -> CGRect {
        let vw = bounds.width, vh = bounds.height
        guard img.width > 0, img.height > 0, vw > 0, vh > 0 else { return .zero }
        let scale = max(vw / img.width, vh / img.height)
        let dw = img.width * scale, dh = img.height * scale
        let ox = (vw - dw) / 2, oy = (vh - dh) / 2
        return CGRect(x: ox + r.minX * dw, y: oy + (1 - r.maxY) * dh,
                      width: r.width * dw, height: r.height * dh)
    }

    private func add(_ r: CGRect, _ img: CGSize, color: UIColor, width: CGFloat) {
        let frame = convert(r, img)
        let l = CAShapeLayer()
        l.path = UIBezierPath(roundedRect: frame, cornerRadius: 4).cgPath
        l.strokeColor = color.cgColor
        l.fillColor = UIColor.clear.cgColor
        l.lineWidth = width
        layer.addSublayer(l)
        overlays.append(l)
    }
}

final class ScanModel: ObservableObject {
    let camera = CameraManager()
    private let productTracker = BoxTracker()
    private let dateTracker = DateTracker()
    @Published var total = 0
    @Published var withDate = 0
    @Published var expired = 0
    weak var view: CameraView?

    func start() {
        camera.onResult = { [weak self] products, dates, size in
            guard let self = self else { return }
            let d = self.dateTracker.update(dates)
            let p = self.productTracker.update(products, dates: d)
            self.view?.show(p, d, imageSize: size)
            self.total = p.count
            self.withDate = p.filter { $0.expiry != nil }.count
            self.expired = p.filter { $0.status == .expired }.count
        }
        camera.start()
    }
}

struct CameraRepresentable: UIViewRepresentable {
    let model: ScanModel
    func makeUIView(context: Context) -> CameraView {
        let v = CameraView()
        v.previewLayer.session = model.camera.session
        v.previewLayer.videoGravity = .resizeAspectFill
        model.view = v
        return v
    }
    func updateUIView(_ uiView: CameraView, context: Context) {}
}

struct ContentView: View {
    @StateObject private var model = ScanModel()

    var body: some View {
        ZStack(alignment: .top) {
            CameraRepresentable(model: model).ignoresSafeArea()
            HStack(spacing: 16) {
                Label("\(model.total)", systemImage: "square.stack.3d.up").foregroundStyle(.blue)
                Label("\(model.withDate)", systemImage: "calendar").foregroundStyle(.green)
                Label("\(model.expired)", systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            }
            .font(.headline)
            .padding(10)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.top, 8)
        }
        .onAppear { model.start() }
    }
}
