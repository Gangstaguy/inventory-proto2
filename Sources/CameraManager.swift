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
        if session.canAddInput(input) { session.addInput(input) }
        // Högre upplösning ger läsbara små datum. Faller tillbaka till 1080p.
        session.sessionPreset = session.canSetSessionPreset(.hd4K3840x2160) ? .hd4K3840x2160 : .hd1920x1080
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }
        if let conn = output.connection(with: .video) {
            if #available(iOS 17.0, *) { conn.videoRotationAngle = 90 }
            else { conn.videoOrientation = .portrait }
        }
        session.commitConfiguration()

        do {
            try device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            device.unlockForConfiguration()
        } catch {}

        session.startRunning()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        // Max ca 7 analyser i sekunden (4K är tungt).
        let now = CACurrentMediaTime()
        guard now - lastRun > 0.15,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastRun = now
        let (products, dates, size) = detector.analyze(buffer)
        DispatchQueue.main.async { self.onResult?(products, dates, size) }
    }
}
