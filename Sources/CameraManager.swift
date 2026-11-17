import AVFoundation
import QuartzCore

final class CameraManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    var onResult: (([Detection], [DateBox], CGSize) -> Void)?

    private let queue = DispatchQueue(label: "camera.frames")
    private let detector = Detector()
    private var lastRun: CFTimeInterval = 0

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] ok in
            guard ok else { return }
            self?.queue.async { self?.configure() }
        }
    }

    private func configure() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        session.beginConfiguration()
        session.sessionPreset = .hd1920x1080
        if session.canAddInput(input) { session.addInput(input) }
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }
        if let conn = output.connection(with: .video) {
            if #available(iOS 17.0, *) { conn.videoRotationAngle = 90 }
            else { conn.videoOrientation = .portrait }
        }
        session.commitConfiguration()
        session.startRunning()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        // Max ca 10 analyser i sekunden – lugnare och snällare mot batteriet.
        let now = CACurrentMediaTime()
        guard now - lastRun > 0.1,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastRun = now
        let (products, dates, size) = detector.analyze(buffer)
        DispatchQueue.main.async { self.onResult?(products, dates, size) }
    }
}
