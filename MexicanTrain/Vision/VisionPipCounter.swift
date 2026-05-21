import CoreML
import Vision
import UIKit

/// Production pip counter backed by a bundled CoreML object-detection model.
///
/// Model contract (target shape; document any deviation when wiring the real
/// model in):
/// - Input: a single 640×640 RGB image (the YOLOv11-class baseline).
/// - Output: bounding boxes with class labels matching the regex
///   `^tile[-_]?(\d{1,2})[-_](\d{1,2})$` — e.g. `tile-5-3`, `tile_12_12`.
///   Each detection's class encodes the (a, b) half-values of a domino.
/// - Each detection has a confidence in [0, 1]; we collapse low-confidence
///   detections into the result's confidence bucket (see `bucket(for:)`).
struct VisionPipCounter: PipCounter {
    let model: VNCoreMLModel

    /// Try to instantiate from the bundled model. Returns nil when the
    /// .mlmodel file isn't present — the caller falls back to MockPipCounter.
    static func loadFromBundle() -> VisionPipCounter? {
        let candidates = ["DominoDetector"]
        for name in candidates {
            if let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc")
                ?? Bundle.main.url(forResource: name, withExtension: "mlmodel") {
                if let mlModel = try? MLModel(contentsOf: url),
                   let vnModel = try? VNCoreMLModel(for: mlModel) {
                    return VisionPipCounter(model: vnModel)
                }
            }
        }
        return nil
    }

    func count(in image: UIImage) async throws -> PipCountResult {
        guard let cgImage = image.cgImage else {
            throw PipCounterError.badImage
        }
        let observations = try await runRequest(cgImage: cgImage, orientation: image.cgOrientation)
        return Self.consolidate(observations: observations)
    }

    // MARK: internal

    private func runRequest(cgImage: CGImage, orientation: CGImagePropertyOrientation) async throws -> [VNRecognizedObjectObservation] {
        try await withCheckedThrowingContinuation { cont in
            let request = VNCoreMLRequest(model: model) { req, err in
                if let err {
                    cont.resume(throwing: err)
                    return
                }
                let observations = (req.results as? [VNRecognizedObjectObservation]) ?? []
                cont.resume(returning: observations)
            }
            request.imageCropAndScaleOption = .scaleFill
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            do {
                try handler.perform([request])
            } catch {
                cont.resume(throwing: error)
            }
        }
    }

    static func consolidate(observations: [VNRecognizedObjectObservation]) -> PipCountResult {
        var tiles: [TileObservation] = []
        var confidences: [Float] = []
        for obs in observations {
            // Pick the top-1 label.
            guard let top = obs.labels.first else { continue }
            if let parsed = parseTileClass(top.identifier) {
                tiles.append(parsed)
                confidences.append(top.confidence)
            }
        }
        let total = tiles.reduce(0) { $0 + $1.pips }
        let confidence = bucket(for: confidences, tileCount: tiles.count)
        return PipCountResult(tiles: tiles, total: total, confidence: confidence)
    }

    /// Parse a model class string like "tile-5-3", "tile_12_12", "tile1212".
    static func parseTileClass(_ raw: String) -> TileObservation? {
        let lower = raw.lowercased()
        guard lower.hasPrefix("tile") else { return nil }
        // Extract all digit groups in the string.
        var nums: [Int] = []
        var current = ""
        for ch in lower {
            if ch.isNumber { current.append(ch) }
            else {
                if !current.isEmpty, let n = Int(current) { nums.append(n) }
                current.removeAll()
            }
        }
        if !current.isEmpty, let n = Int(current) { nums.append(n) }
        guard nums.count >= 2 else { return nil }
        let a = nums[0]
        let b = nums[1]
        if a < 0 || a > 12 || b < 0 || b > 12 { return nil }
        return TileObservation(a: a, b: b)
    }

    static func bucket(for confidences: [Float], tileCount: Int) -> Confidence {
        if tileCount == 0 { return .low }
        let avg = confidences.reduce(0, +) / Float(confidences.count)
        let minc = confidences.min() ?? 0
        if avg >= 0.80, minc >= 0.50 { return .high }
        if avg >= 0.50 { return .medium }
        return .low
    }
}

private extension UIImage {
    var cgOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}
