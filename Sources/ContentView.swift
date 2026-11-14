import SwiftUI
import AVFoundation

final class CameraView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    private var overlays: [CALayer] = []

    func show(_ products: [Detection], _ dates: [DateBox]) {
        overlays.forEach { $0.removeFromSuperlayer() }
        overlays = []
        for p in products { add(p.rect, color: p.status.color, width: 3) }
        for d in dates { add(d.rect, color: .systemYellow, width: 2) }   // datum = gul outline
    }

    private func add(_ r: CGRect, color: UIColor, width: CGFloat) {
        let flipped = CGRect(x: r.minX, y: 1 - r.maxY, width: r.width, height: r.height)
        let frame = previewLayer.layerRectConverted(fromMetadataOutputRect: flipped)
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
    @Published var total = 0, withDate = 0, expired = 0
    weak var view: CameraView?

    func start() {
        camera.onResult = { [weak self] products, dates in
            self?.view?.show(products, dates)
            self?.total = products.count
            self?.withDate = products.filter { $0.expiry != nil }.count
            self?.expired = products.filter { $0.status == .expired }.count
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
