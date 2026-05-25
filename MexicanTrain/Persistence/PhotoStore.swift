import Foundation
import UIKit

struct PhotoStore {
    let rootDirectory: URL

    init(rootDirectory: URL? = nil) {
        if let rootDirectory {
            self.rootDirectory = rootDirectory
        } else {
            let fm = FileManager.default
            let support = (try? fm.url(for: .applicationSupportDirectory,
                                       in: .userDomainMask,
                                       appropriateFor: nil,
                                       create: true)) ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.rootDirectory = support.appendingPathComponent("MexicanTrain/photos", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.rootDirectory,
                                                 withIntermediateDirectories: true)
    }

    @discardableResult
    func save(image: UIImage, gameID: UUID, captureID: UUID) throws -> String {
        let dir = gameDir(gameID: gameID)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(captureID.uuidString).jpg")
        guard let data = image.normalizedJPEG(quality: 0.85) else {
            throw PhotoStoreError.encodingFailed
        }
        try data.write(to: url, options: .atomic)
        return "\(captureID.uuidString).jpg"
    }

    func load(filename: String, gameID: UUID) -> UIImage? {
        let url = url(filename: filename, gameID: gameID)
        return UIImage(contentsOfFile: url.path)
    }

    /// Absolute on-disk URL for a stored capture. Exposed for callers
    /// (e.g. `TrainingDataExporter`) that need to copy the source file
    /// rather than decode an image.
    func url(filename: String, gameID: UUID) -> URL {
        gameDir(gameID: gameID).appendingPathComponent(filename)
    }

    func thumbnail(filename: String, gameID: UUID, maxEdge: CGFloat = 256) -> UIImage? {
        guard let image = load(filename: filename, gameID: gameID) else { return nil }
        return image.resized(toMaxEdge: maxEdge)
    }

    func deleteAll(gameID: UUID) {
        try? FileManager.default.removeItem(at: gameDir(gameID: gameID))
    }

    /// Remove photo directories that don't correspond to any known game ID.
    /// Call on launch to reclaim disk space from deleted games whose photos
    /// weren't cleaned up (e.g. crash during deletion).
    func cleanOrphaned(validGameIDs: Set<UUID>) {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for url in contents {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            guard isDir else { continue }
            let dirName = url.lastPathComponent
            guard let dirUUID = UUID(uuidString: dirName) else { continue }
            if !validGameIDs.contains(dirUUID) {
                try? fm.removeItem(at: url)
            }
        }
    }

    private func gameDir(gameID: UUID) -> URL {
        rootDirectory.appendingPathComponent(gameID.uuidString, isDirectory: true)
    }
}

enum PhotoStoreError: Error {
    case encodingFailed
}

extension UIImage {
    /// JPEG-encode while normalizing orientation so downstream consumers
    /// don't have to think about EXIF transforms.
    func normalizedJPEG(quality: CGFloat = 0.85) -> Data? {
        guard imageOrientation != .up else {
            return jpegData(compressionQuality: quality)
        }
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext()?.jpegData(compressionQuality: quality)
    }

    func resized(toMaxEdge edge: CGFloat) -> UIImage {
        let maxSide = max(size.width, size.height)
        guard maxSide > edge else { return self }
        let ratio = edge / maxSide
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
