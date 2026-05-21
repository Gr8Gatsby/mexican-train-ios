import XCTest
@testable import MexicanTrain

final class VisionPipCounterTests: XCTestCase {
    func testParseTileVariants() {
        XCTAssertEqual(VisionPipCounter.parseTileClass("tile-5-3"),
                       TileObservation(a: 5, b: 3))
        XCTAssertEqual(VisionPipCounter.parseTileClass("tile_12_12"),
                       TileObservation(a: 12, b: 12))
        XCTAssertEqual(VisionPipCounter.parseTileClass("TILE-0-0"),
                       TileObservation(a: 0, b: 0))
    }

    func testParseRejectsNonTile() {
        XCTAssertNil(VisionPipCounter.parseTileClass("non-tile-5-3"))
        XCTAssertNil(VisionPipCounter.parseTileClass("tile-13-0"))
        XCTAssertNil(VisionPipCounter.parseTileClass("tile-5"))
    }

    func testBucketLogic() {
        XCTAssertEqual(VisionPipCounter.bucket(for: [], tileCount: 0), .low)
        XCTAssertEqual(VisionPipCounter.bucket(for: [0.90, 0.85, 0.80], tileCount: 3), .high)
        XCTAssertEqual(VisionPipCounter.bucket(for: [0.95, 0.95, 0.30], tileCount: 3), .medium)
        XCTAssertEqual(VisionPipCounter.bucket(for: [0.40, 0.30], tileCount: 2), .low)
        XCTAssertEqual(VisionPipCounter.bucket(for: [0.60, 0.60, 0.60], tileCount: 3), .medium)
    }

    func testProductionFactoryFallsBackToMockWithoutModel() {
        let counter = PipCounterFactory.makeProductionCounter()
        // No .mlmodel bundled at this milestone — should be the mock.
        XCTAssertTrue(counter is MockPipCounter)
    }
}
