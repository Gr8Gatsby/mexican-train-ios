import AVFoundation
import SwiftUI
import UIKit

/// Lightweight AVFoundation wrapper. Reports availability up-front so the
/// view can show a "simulator fallback" path when there's no rear camera.
@MainActor
@Observable
final class CameraCapture: NSObject {
    enum State {
        case unknown, denied, unavailable, ready, capturing
    }

    private(set) var state: State = .unknown
    private(set) var session: AVCaptureSession?
    private let output = AVCapturePhotoOutput()
    private var continuation: CheckedContinuation<UIImage, Error>?

    var hasCamera: Bool { state == .ready || state == .capturing }

    func prepare() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            await configureSession()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted { await configureSession() } else { state = .denied }
        case .denied, .restricted:
            state = .denied
        @unknown default:
            state = .denied
        }
    }

    private func configureSession() async {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            state = .unavailable
            return
        }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            let session = AVCaptureSession()
            session.beginConfiguration()
            session.sessionPreset = .photo
            if session.canAddInput(input) { session.addInput(input) }
            if session.canAddOutput(output) { session.addOutput(output) }
            session.commitConfiguration()
            self.session = session
            Task.detached { session.startRunning() }
            state = .ready
        } catch {
            state = .unavailable
        }
    }

    func stop() {
        session?.stopRunning()
    }

    func capturePhoto() async throws -> UIImage {
        guard state == .ready else {
            throw CameraError.notReady
        }
        state = .capturing
        defer { state = .ready }
        let settings = AVCapturePhotoSettings()
        settings.isHighResolutionPhotoEnabled = false
        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            self.output.capturePhoto(with: settings, delegate: self)
        }
    }
}

enum CameraError: Error {
    case notReady
    case encodingFailed
}

extension CameraCapture: @preconcurrency AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard let cont = continuation else { return }
        continuation = nil
        if let error {
            cont.resume(throwing: error)
            return
        }
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            cont.resume(throwing: CameraError.encodingFailed)
            return
        }
        cont.resume(returning: image)
    }
}

/// SwiftUI preview wrapping AVCaptureVideoPreviewLayer.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.videoPreviewLayer.session = session
        v.videoPreviewLayer.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
