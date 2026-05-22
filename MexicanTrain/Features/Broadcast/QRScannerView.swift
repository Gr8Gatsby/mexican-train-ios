import SwiftUI
import AVFoundation
import UIKit

/// Live camera preview that fires `onCode` when a QR is decoded. Reuses
/// `NSCameraUsageDescription` from Info.plist (already declared for the
/// pip-counting camera). Stops the session as soon as a code is read so
/// the host-list / join flow can take over.
struct QRScannerView: UIViewControllerRepresentable {
    var onCode: (String) -> Void
    var onError: (String) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode, onError: onError) }

    func makeUIViewController(context: Context) -> QRScannerController {
        let controller = QRScannerController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QRScannerController, context: Context) {}

    final class Coordinator: NSObject, QRScannerControllerDelegate {
        let onCode: (String) -> Void
        let onError: (String) -> Void
        init(onCode: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
            self.onCode = onCode
            self.onError = onError
        }
        func qrScanner(_ controller: QRScannerController, didScan code: String) { onCode(code) }
        func qrScanner(_ controller: QRScannerController, didFailWith message: String) { onError(message) }
    }
}

protocol QRScannerControllerDelegate: AnyObject {
    func qrScanner(_ controller: QRScannerController, didScan code: String)
    func qrScanner(_ controller: QRScannerController, didFailWith message: String)
}

final class QRScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    weak var delegate: QRScannerControllerDelegate?
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasReported = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
        addOverlay()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        hasReported = false
        if !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning { session.stopRunning() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func configureSession() {
        guard let device = AVCaptureDevice.default(for: .video) else {
            delegate?.qrScanner(self, didFailWith: "No camera available")
            return
        }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) { session.addInput(input) }
            let output = AVCaptureMetadataOutput()
            if session.canAddOutput(output) {
                session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: .main)
                output.metadataObjectTypes = [.qr]
            }
            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            view.layer.insertSublayer(preview, at: 0)
            previewLayer = preview
        } catch {
            delegate?.qrScanner(self, didFailWith: error.localizedDescription)
        }
    }

    private func addOverlay() {
        let box = UIView()
        box.layer.borderColor = UIColor(red: 200/255, green: 84/255, blue: 29/255, alpha: 1).cgColor
        box.layer.borderWidth = 3
        box.layer.cornerRadius = 14
        box.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(box)
        NSLayoutConstraint.activate([
            box.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.7),
            box.heightAnchor.constraint(equalTo: box.widthAnchor),
            box.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            box.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        let hint = UILabel()
        hint.text = "POINT AT THE HOST'S QR CODE"
        hint.textColor = UIColor.white.withAlphaComponent(0.9)
        hint.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        hint.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hint)
        NSLayoutConstraint.activate([
            hint.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hint.topAnchor.constraint(equalTo: box.bottomAnchor, constant: 18)
        ])
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !hasReported,
              let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let str = obj.stringValue else { return }
        hasReported = true
        delegate?.qrScanner(self, didScan: str)
    }
}
