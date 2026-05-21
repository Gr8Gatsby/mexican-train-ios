import XCTest
import UIKit
@testable import MexicanTrain

final class PhotoStoreTests: XCTestCase {
    private var tempRoot: URL!
    private var store: PhotoStore!

    override func setUp() {
        tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MexicanTrainTests/\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        store = PhotoStore(rootDirectory: tempRoot)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testSaveLoadRoundTrip() throws {
        let gameID = UUID()
        let captureID = UUID()
        let img = makeImage(color: .red, size: CGSize(width: 100, height: 100))
        let filename = try store.save(image: img, gameID: gameID, captureID: captureID)
        let loaded = store.load(filename: filename, gameID: gameID)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(filename, "\(captureID.uuidString).jpg")
    }

    func testThumbnailIsSmaller() throws {
        let gameID = UUID()
        let captureID = UUID()
        let img = makeImage(color: .blue, size: CGSize(width: 1024, height: 1024))
        let filename = try store.save(image: img, gameID: gameID, captureID: captureID)
        let thumb = store.thumbnail(filename: filename, gameID: gameID, maxEdge: 256)
        XCTAssertNotNil(thumb)
        XCTAssertLessThanOrEqual(max(thumb!.size.width, thumb!.size.height), 257)
    }

    func testDeleteAllRemovesGameDir() throws {
        let gameID = UUID()
        _ = try store.save(image: makeImage(color: .green, size: CGSize(width: 64, height: 64)),
                           gameID: gameID, captureID: UUID())
        store.deleteAll(gameID: gameID)
        let gameDir = tempRoot.appendingPathComponent(gameID.uuidString)
        XCTAssertFalse(FileManager.default.fileExists(atPath: gameDir.path))
    }

    private func makeImage(color: UIColor, size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }
}

final class MockPipCounterTests: XCTestCase {
    func testReturnsTilesAndTotal() async throws {
        let counter = MockPipCounter(simulateLatency: 0)
        let img = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200)).image { _ in }
        let result = try await counter.count(in: img)
        XCTAssertGreaterThan(result.tiles.count, 0)
        XCTAssertEqual(result.total, result.tiles.map(\.pips).reduce(0, +))
    }
}
