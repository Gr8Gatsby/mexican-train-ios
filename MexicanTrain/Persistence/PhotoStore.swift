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
        let url = gameDir(gameID: gameID).appendingPathComponent(filename)
        return UIImage(contentsOfFile: url.path)
    }

    func thumbnail(filename: String, gameID: UUID, maxEdge: CGFloat = 256) -> UIImage? {
        guard let image = load(filename: filename, gameID: gameID) else { return nil }
        return image.resized(toMaxEdge: maxEdge)
    }

    func deleteAll(gameID: UUID) {
        try? FileManager.default.removeItem(at: gameDir(gameID: gameID))
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
