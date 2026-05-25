import CoreML
@preconcurrency import Vision
import UIKit

/// Production pip counter backed by a YOLOv11n model trained to detect
/// individual domino HALVES (one detection per half, class label = pip value
/// 0–12). The exported model has no NMS baked in, so we apply NMS in Swift
/// after parsing the raw [1, 17, 8400] output tensor.
///
/// Model contract (see also `MODEL_CONTRACT.md`):
/// - Input: `image` ImageType, 640×640 RGB. Vision rescales for us.
/// - Output: `var_1688` (or similar) MLMultiArray of shape [1, 17, 8400]
///   where each anchor has 4 box values (cx, cy, w, h in 640-pixel space)
///   followed by 13 class scores (one per pip value).
/// - Total pip count = Σ (class_index of each surviving detection).
struct VisionPipCounter: PipCounter {
    static let modelVersion = "yolo11n-v1"

    let model: VNCoreMLModel
    var confidenceThreshold: Float = 0.30
    var iouThreshold: Float = 0.45

    static func loadFromBundle() -> VisionPipCounter? {
        let candidates = ["DominoDetector"]
        for name in candidates {
            if let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc")
                ?? Bundle.main.url(forResource: name, withExtension: "mlpackage") {
                if let mlModel = try? MLModel(contentsOf: url),
                   let vnModel = try? VNCoreMLModel(for: mlModel) {
                    print("[VisionPipCounter] Loaded model version: \(modelVersion)")
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
        let observations = try await runRequest(cgImage: cgImage,
                                                orientation: image.cgOrientation)
        return Self.consolidate(observations: observations,
                                confidenceThreshold: confidenceThreshold,
                                iouThreshold: iouThreshold)
    }

    // MARK: internal

    private func runRequest(cgImage: CGImage,
                            orientation: CGImagePropertyOrientation) async throws -> [VNCoreMLFeatureValueObservation] {
        try await withCheckedThrowingContinuation { cont in
            let request = VNCoreMLRequest(model: model) { req, err in
                if let err {
                    cont.resume(throwing: err); return
                }
                cont.resume(returning: (req.results as? [VNCoreMLFeatureValueObservation]) ?? [])
            }
            request.imageCropAndScaleOption = .scaleFill
            let handler = VNImageRequestHandler(cgImage: cgImage,
                                                orientation: orientation,
                                                options: [:])
            do { try handler.perform([request]) } catch { cont.resume(throwing: error) }
        }
    }

    /// Parse the raw YOLO output, run confidence filter + NMS, return half
    /// detections summed into a PipCountResult. Each detected half is
    /// modeled as a `TileObservation(a: value, b: 0)` so the existing
    /// (a + b) pip arithmetic still works.
    static func consolidate(
        observations: [VNCoreMLFeatureValueObservation],
        confidenceThreshold: Float,
        iouThreshold: Float
    ) -> PipCountResult {
        guard let raw = observations.first?.featureValue.multiArrayValue else {
            return PipCountResult(tiles: [], total: 0, confidence: .low)
        }
        let detections = decodeYOLO(output: raw,
                                    confidenceThreshold: confidenceThreshold)
        let kept = nms(detections: detections, iouThreshold: iouThreshold)
        let halves = kept.map { d in
            TileObservation(a: d.classIndex, b: 0, bbox: d.normalizedBox)
        }
        let total = halves.reduce(0) { $0 + $1.pips }
        let confidence = bucket(for: kept.map(\.confidence), tileCount: kept.count)
        return PipCountResult(tiles: halves, total: total, confidence: confidence)
    }

    // MARK: - YOLO decode

    struct YOLODetection {
        let cx, cy, w, h: Float       // 640-space pixel coords
        let classIndex: Int
        let confidence: Float
        var x1: Float { cx - w/2 }
        var y1: Float { cy - h/2 }
        var x2: Float { cx + w/2 }
        var y2: Float { cy + h/2 }
        var area: Float { max(0, x2 - x1) * max(0, y2 - y1) }

        /// Bounding box normalized to [0,1] against the model's 640²
        /// input. Because Vision uses `.scaleFill`, these coordinates map
        /// directly onto the source photo's [0,1] coordinate system —
        /// the photo is non-uniformly stretched to fill 640², but the
        /// stretch preserves normalized positions.
        var normalizedBox: NormalizedRect {
            NormalizedRect(
                x: Double(max(0, x1) / 640.0),
                y: Double(max(0, y1) / 640.0),
                width: Double(min(640, w) / 640.0),
                height: Double(min(640, h) / 640.0)
            )
        }
    }

    /// Decode the [1, 17, 8400] raw output into per-anchor detections.
    /// Channels 0–3 are bbox (cx, cy, w, h); 4–16 are class scores.
    static func decodeYOLO(output: MLMultiArray, confidenceThreshold: Float) -> [YOLODetection] {
        // Output may be [17, 8400] or [1, 17, 8400]. Normalize.
        let shape = output.shape.map { $0.intValue }
        let strides = output.strides.map { $0.intValue }
        guard shape.count >= 2 else { return [] }
        let (channels, anchors): (Int, Int) = {
            if shape.count == 3 { return (shape[1], shape[2]) }
            return (shape[0], shape[1])
        }()
        guard channels == 17 else { return [] }
        let (cStride, aStride): (Int, Int) = {
            if strides.count == 3 { return (strides[1], strides[2]) }
            return (strides[0], strides[1])
        }()
        let numClasses = channels - 4

        var result: [YOLODetection] = []
        result.reserveCapacity(64)

        // Avoid per-element boxing by binding the buffer pointer once.
        let ptr = output.dataPointer
        let dtype = output.dataType
        let read: (Int) -> Float = { index in
            switch dtype {
            case .float32:
                return ptr.load(fromByteOffset: index * MemoryLayout<Float>.size, as: Float.self)
            case .float16:
                let raw = ptr.load(fromByteOffset: index * 2, as: UInt16.self)
                return Float(Float16(bitPattern: raw))
            case .double:
                return Float(ptr.load(fromByteOffset: index * MemoryLayout<Double>.size, as: Double.self))
            default:
                // Falling through to NSNumber would force boxing per-cell.
                // The exporter writes Float16 (or Float32 when emulating);
                // anything else returns zero — better than crashing.
                return 0
            }
        }

        for a in 0..<anchors {
            // Find best class among 13.
            var bestClass = 0
            var bestScore: Float = 0
            for c in 0..<numClasses {
                let s = read((4 + c) * cStride + a * aStride)
                if s > bestScore { bestScore = s; bestClass = c }
            }
            if bestScore < confidenceThreshold { continue }
            let cx = read(0 * cStride + a * aStride)
            let cy = read(1 * cStride + a * aStride)
            let w  = read(2 * cStride + a * aStride)
            let h  = read(3 * cStride + a * aStride)
            result.append(YOLODetection(cx: cx, cy: cy, w: w, h: h,
                                        classIndex: bestClass,
                                        confidence: bestScore))
        }
        return result
    }

    /// Standard non-max suppression: sort by confidence descending, keep
    /// each detection only if it doesn't overlap (IoU > threshold) with any
    /// already-kept detection. Greedy O(n²) — fine for n ≤ ~200.
    static func nms(detections: [YOLODetection], iouThreshold: Float) -> [YOLODetection] {
        let sorted = detections.sorted { $0.confidence > $1.confidence }
        var kept: [YOLODetection] = []
        for d in sorted {
            var overlaps = false
            for k in kept {
                if iou(d, k) > iouThreshold {
                    overlaps = true
                    break
                }
            }
            if !overlaps { kept.append(d) }
        }
        return kept
    }

    static func iou(_ a: YOLODetection, _ b: YOLODetection) -> Float {
        let ix1 = max(a.x1, b.x1)
        let iy1 = max(a.y1, b.y1)
        let ix2 = min(a.x2, b.x2)
        let iy2 = min(a.y2, b.y2)
        let iw = max(0, ix2 - ix1)
        let ih = max(0, iy2 - iy1)
        let inter = iw * ih
        let union = a.area + b.area - inter
        return union > 0 ? inter / union : 0
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
