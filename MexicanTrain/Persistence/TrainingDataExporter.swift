import Foundation
import SwiftData
import UIKit

/// Builds a YOLO-format training bundle from all `Capture`s that have
/// human-corrected per-half labels. Output is a ZIP file suitable for
/// dropping into `apps/mextrain/ml/datasets/user-corrections/` and
/// re-running `train.py`.
///
/// Class taxonomy matches the existing web-app pipeline (14 classes:
/// 0..12 + blank), so the YOLO label IDs are simply the pip value, with
/// `blank` reserved as class 13 for future use. (`TileObservation.a`
/// already encodes the pip value 0..12; we never emit class 13 today.)
///
/// The zip is built via `NSFileCoordinator(.forUploading)`, which is
/// Apple's first-party "make a zip of this directory" facility — no
/// third-party archive library required.
enum TrainingDataExporter {
    /// 14 classes — pip value (0..12) plus "blank" — matching the
    /// taxonomy in `apps/mextrain/ml/scripts/`. Each class name doubles
    /// as the YOLO label index (its position in this array).
    static let classNames: [String] = (0...12).map { "\($0)" } + ["blank"]

    struct Summary {
        let zipURL: URL
        let imageCount: Int
        let labelCount: Int
    }

    enum ExportError: Error {
        case noLabeledCaptures
        case ioFailure(String)
    }

    /// Find every labeled capture in the store, write images + YOLO label
    /// files to a temp staging directory, then zip the directory and
    /// return its URL.
    static func export(context: ModelContext, photoStore: PhotoStore) throws -> Summary {
        let descriptor = FetchDescriptor<Capture>(
            predicate: #Predicate { $0.correctedTilesData != nil }
        )
        let captures = (try? context.fetch(descriptor)) ?? []
        guard !captures.isEmpty else { throw ExportError.noLabeledCaptures }

        let stamp = ISO8601DateFormatter.exportStamp.string(from: .now)
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("mextrain-export-\(stamp)", isDirectory: true)
        let imagesDir = staging.appendingPathComponent("images", isDirectory: true)
        let labelsDir = staging.appendingPathComponent("labels", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: labelsDir, withIntermediateDirectories: true)
        } catch {
            throw ExportError.ioFailure("Failed to make staging dirs: \(error.localizedDescription)")
        }

        var imageCount = 0
        var labelCount = 0
        for capture in captures {
            guard let gameID = capture.game?.id else { continue }
            let srcImageURL = photoStore.url(filename: capture.filename, gameID: gameID)
            let stem = capture.id.uuidString
            let destImageURL = imagesDir.appendingPathComponent("\(stem).jpg")
            let destLabelURL = labelsDir.appendingPathComponent("\(stem).txt")

            do {
                try FileManager.default.copyItem(at: srcImageURL, to: destImageURL)
            } catch {
                // Skip captures whose source photo is missing on disk.
                continue
            }
            imageCount += 1

            let labelText = yoloLabelText(for: capture.correctedTiles ?? [])
            do {
                try labelText.write(to: destLabelURL, atomically: true, encoding: .utf8)
                labelCount += 1
            } catch {
                throw ExportError.ioFailure("Failed to write labels: \(error.localizedDescription)")
            }
        }

        try writeDataYAML(into: staging)
        try writeReadme(into: staging, imageCount: imageCount)

        let zipURL = try makeZip(of: staging)
        try? FileManager.default.removeItem(at: staging)
        return Summary(zipURL: zipURL, imageCount: imageCount, labelCount: labelCount)
    }

    static func labeledCaptureCount(in context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<Capture>(
            predicate: #Predicate { $0.correctedTilesData != nil }
        )
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    // MARK: - Internals

    /// YOLO label format: one detection per line, `class_id cx cy w h`
    /// (all space-separated, normalized [0,1], box center coords).
    /// `TileObservation.a` already stores the pip value (0..12), which
    /// doubles as the class index per `classNames` order. Detections
    /// without bboxes are skipped (no spatial info to label).
    static func yoloLabelText(for tiles: [TileObservation]) -> String {
        var lines: [String] = []
        for tile in tiles {
            guard let bbox = tile.bbox else { continue }
            let cls = max(0, min(12, tile.a))
            let cx = bbox.x + bbox.width / 2
            let cy = bbox.y + bbox.height / 2
            lines.append(String(format: "%d %.6f %.6f %.6f %.6f",
                                cls, cx, cy, bbox.width, bbox.height))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func writeDataYAML(into dir: URL) throws {
        let yaml = """
        # YOLO dataset descriptor for Mexican Train iOS user-correction export.
        # Class names match apps/mextrain/ml taxonomy. Drop this directory under
        # `apps/mextrain/ml/datasets/user-corrections/` and merge via
        # scripts/merge_datasets.py before re-running train.py.
        train: images
        val: images
        nc: \(classNames.count)
        names: \(classNames.map { "'\($0)'" }.joined(separator: ", "))
        """
        try yaml.write(to: dir.appendingPathComponent("data.yaml"),
                       atomically: true, encoding: .utf8)
    }

    private static func writeReadme(into dir: URL, imageCount: Int) throws {
        let text = """
        Mexican Train iOS — user-corrected training export
        ---------------------------------------------------
        Exported on \(Date()) — \(imageCount) labeled photos.

        Layout (YOLO):
          images/  — one JPG per labeled capture (file name is the capture UUID)
          labels/  — matching .txt files, YOLO format (class_id cx cy w h, normalized)
          data.yaml — class names matching the existing apps/mextrain/ml pipeline

        Merge with the rest of the training data:
          1. Unzip under apps/mextrain/ml/datasets/user-corrections/
          2. Run scripts/merge_datasets.py
          3. Run scripts/train.py
          4. Run scripts/export.py to produce a fresh ONNX, then convert to CoreML
             via the recipe in MexicanTrain/Vision/MODEL_CONTRACT.md.
        """
        try text.write(to: dir.appendingPathComponent("README.txt"),
                       atomically: true, encoding: .utf8)
    }

    /// Zip the staging directory using `NSFileCoordinator`'s
    /// `.forUploading` read option, which returns a temporary `.zip`
    /// URL automatically.
    private static func makeZip(of dir: URL) throws -> URL {
        var coordError: NSError?
        var resultURL: URL?
        var thrown: Error?
        let coord = NSFileCoordinator()
        coord.coordinate(readingItemAt: dir, options: [.forUploading],
                         error: &coordError) { zippedURL in
            // The OS hands us a tmp URL inside a coordinator-managed sandbox.
            // Copy it out to a stable temp path so the share sheet has it
            // after this closure returns.
            let stem = dir.lastPathComponent
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(stem).zip")
            try? FileManager.default.removeItem(at: destination)
            do {
                try FileManager.default.copyItem(at: zippedURL, to: destination)
                resultURL = destination
            } catch {
                thrown = error
            }
        }
        if let coordError { throw ExportError.ioFailure(coordError.localizedDescription) }
        if let thrown { throw ExportError.ioFailure(thrown.localizedDescription) }
        guard let resultURL else { throw ExportError.ioFailure("zip produced no URL") }
        return resultURL
    }
}

private extension ISO8601DateFormatter {
    static let exportStamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withColonSeparatorInTime]
        return f
    }()
}
