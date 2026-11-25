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

        // Produkter: blå/grön/röd ruta efter datum, text efter vilken produkt den bedömts vara.
        for p in products {
            let known = p.match != nil
            let frame = add(p.rect, imageSize,
                            color: known ? p.status.color : p.status.color.withAlphaComponent(0.5),
                            width: known ? 3 : 1.5)
            addProductLabel(p, in: frame)
        }
        // Datum: gul = gäller, orange = har passerat. Etiketten visar vad OCR läste → tolkat datum.
        for d in dates {
            let color: UIColor = d.date < today ? .systemOrange : .systemYellow
            let frame = add(d.rect, imageSize, color: color, width: 2)
            addLabel("\(d.text) → \(DateParser.format(d.date))", above: frame)
        }
    }

    static func isSure(_ p: Detection) -> Bool {
        guard let m = p.match else { return false }
        return m.score >= Config.minScore && p.margin >= Config.minMargin
    }

    /// Svart etikett = säker träff. Orange etikett med "?" = osäker (visar även näst bästa alternativ).
    private func addProductLabel(_ p: Detection, in frame: CGRect) {
        guard let m = p.match else { return }
        let sure = CameraView.isSure(p)
        let prefix = sure ? "" : "? "
        let likhet = String(format: "%.2f", m.sim)
        var detaljer = "likhet \(likhet)"
        if m.brandHit { detaljer += " · märke ✓" }
        if m.brandMismatch { detaljer += " · märke ✗" }
        if m.titleCov > 0 { detaljer += " · text \(Int(m.titleCov * 100)) %" }
        var text = "\(prefix)\(m.titel) – \(m.varumarke)\n\(m.mangd) · \(detaljer)"
        if !sure, let alt = p.alternative {
            text += "\neller: \(alt.titel) – \(alt.varumarke)"
        }
        let t = CATextLayer()
        t.string = text
        t.fontSize = 11
        t.isWrapped = true
        t.truncationMode = .end
        t.foregroundColor = UIColor.white.cgColor
        t.backgroundColor = (sure ? UIColor.black.withAlphaComponent(0.7)
                                  : UIColor.systemOrange.withAlphaComponent(0.9)).cgColor
        t.contentsScale = window?.screen.scale ?? 3
        t.frame = CGRect(x: frame.minX + 3, y: frame.minY + 3,
                         width: max(frame.width - 6, 150), height: sure ? 30 : 44)
        layer.addSublayer(t)
        overlays.append(t)
    }

    private func addLabel(_ text: String, above frame: CGRect) {
        let t = CATextLayer()
        t.string = text
        t.fontSize = 12
        t.foregroundColor = UIColor.white.cgColor
        t.backgroundColor = UIColor.black.withAlphaComponent(0.65).cgColor
        t.contentsScale = window?.screen.scale ?? 3
        t.frame = CGRect(x: frame.minX, y: max(0, frame.minY - 18),
                         width: max(frame.width, 190), height: 16)
        layer.addSublayer(t)
        overlays.append(t)
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

    private func add(_ r: CGRect, _ img: CGSize, color: UIColor, width: CGFloat) -> CGRect {
        let frame = convert(r, img)
        let l = CAShapeLayer()
        l.path = UIBezierPath(roundedRect: frame, cornerRadius: 4).cgPath
        l.strokeColor = color.cgColor
        l.fillColor = UIColor.clear.cgColor
        l.lineWidth = width
        layer.addSublayer(l)
        overlays.append(l)
        return frame
    }
}

final class ScanModel: ObservableObject {
    let camera = CameraManager()
    @Published var total = 0
    @Published var withDate = 0
    @Published var expired = 0
    @Published var identified = 0
    @Published var status = "startar..."
    weak var view: CameraView?

    func start() {
        camera.onResult = { [weak self] products, dates, size in
            guard let self = self else { return }
            self.view?.show(products, dates, imageSize: size)
            self.total = products.count
            self.withDate = products.filter { $0.expiry != nil }.count
            self.expired = products.filter { $0.status == .expired }.count
            self.identified = products.filter { CameraView.isSure($0) }.count
        }
        camera.onStatus = { [weak self] text in self?.status = text }
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
            HStack(spacing: 14) {
                Label("\(model.total)", systemImage: "square.stack.3d.up").foregroundStyle(.blue)
                Label("\(model.identified)", systemImage: "checkmark.seal").foregroundStyle(.white)
                Label("\(model.withDate)", systemImage: "calendar").foregroundStyle(.green)
                Label("\(model.expired)", systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            }
            .font(.headline)
            .padding(10)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.top, 8)
        }
        .overlay(alignment: .bottom) {
            Text(model.status)
                .font(.caption2)
                .padding(6)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 8)
        }
        .onAppear { model.start() }
    }
}
