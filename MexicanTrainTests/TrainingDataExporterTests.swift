import XCTest
import SwiftData
@testable import MexicanTrain

@MainActor
final class TrainingDataExporterTests: XCTestCase {
    private var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        container = DataStore.makeContainer(inMemory: true)
    }

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

    func testYoloLabelTextFormat() {
        let tile = TileObservation(a: 5, b: 0,
                                   bbox: NormalizedRect(x: 0.10, y: 0.20, width: 0.30, height: 0.40))
        let text = TrainingDataExporter.yoloLabelText(for: [tile])
        // class=5 (pip value), cx = x + w/2 = 0.25, cy = y + h/2 = 0.40, w=0.30, h=0.40
        XCTAssertTrue(text.contains("5 0.250000 0.400000 0.300000 0.400000"),
                      "unexpected line: \(text)")
        XCTAssertTrue(text.hasSuffix("\n"), "lines must end with newline")
    }

    func testYoloLabelSkipsTilesWithoutBbox() {
        let tiles = [
            TileObservation(a: 3, b: 0, bbox: nil),
            TileObservation(a: 7, b: 0,
                            bbox: NormalizedRect(x: 0.5, y: 0.5, width: 0.1, height: 0.1))
        ]
        let text = TrainingDataExporter.yoloLabelText(for: tiles)
        XCTAssertFalse(text.contains("3 "), "tiles without bboxes can't be labeled")
        XCTAssertTrue(text.contains("7 "))
    }

    func testYoloLabelClampsClassToPipRange() {
        let tile = TileObservation(a: 99, b: 0,
                                   bbox: NormalizedRect(x: 0, y: 0, width: 0.1, height: 0.1))
        let text = TrainingDataExporter.yoloLabelText(for: [tile])
        XCTAssertTrue(text.hasPrefix("12 "), "out-of-range class clamps to 12")
    }

    func testSaveLabelsPersistsCorrectedTiles() throws {
        let ctx = container.mainContext
        let game = try GamePersistence.createGame(
            in: ctx, length: 7, startingEngine: .traditional,
            playerNames: ["Alice"], youIndex: 0
        )
        let player = game.sortedPlayers[0]
        let originalTiles = [TileObservation(a: 5, b: 0)]
        let capture = Capture(
            playerID: player.id, stopIndex: 1,
            filename: "fake.jpg", pipsDetected: 5,
            confidence: .high, tiles: originalTiles
        )
        capture.game = game
        ctx.insert(capture)
        try ctx.save()
        XCTAssertNil(capture.correctedTilesData)
        XCTAssertFalse(capture.isLabeled)

        let corrections = [
            TileObservation(a: 7, b: 0,
                            bbox: NormalizedRect(x: 0.1, y: 0.1, width: 0.2, height: 0.3))
        ]
        try CapturePersistence.saveLabels(in: ctx, capture: capture, tiles: corrections)

        XCTAssertNotNil(capture.correctedTilesData)
        XCTAssertNotNil(capture.labeledAt)
        XCTAssertEqual(capture.correctedTiles?.count, 1)
        XCTAssertEqual(capture.correctedTiles?.first?.a, 7)
        XCTAssertTrue(capture.isLabeled)
        // Original detector output preserved.
        XCTAssertEqual(capture.tiles.first?.a, 5)
    }

    func testLabeledCaptureCount() throws {
        let ctx = container.mainContext
        XCTAssertEqual(TrainingDataExporter.labeledCaptureCount(in: ctx), 0)

        let game = try GamePersistence.createGame(
            in: ctx, length: 7, startingEngine: .traditional,
            playerNames: ["A"], youIndex: 0
        )
        let p = game.sortedPlayers[0]
        let unlabeled = Capture(playerID: p.id, stopIndex: 1, filename: "a.jpg",
                                pipsDetected: 0, confidence: .high, tiles: [])
        unlabeled.game = game
        ctx.insert(unlabeled)

        let labeled = Capture(playerID: p.id, stopIndex: 2, filename: "b.jpg",
                              pipsDetected: 0, confidence: .high, tiles: [])
        labeled.game = game
        ctx.insert(labeled)
        try ctx.save()
        try CapturePersistence.saveLabels(in: ctx, capture: labeled, tiles: [
            TileObservation(a: 3, b: 0, bbox: NormalizedRect(x: 0, y: 0, width: 0.1, height: 0.1))
        ])
        XCTAssertEqual(TrainingDataExporter.labeledCaptureCount(in: ctx), 1)
    }

    func testExportThrowsWhenNoLabels() throws {
        let ctx = container.mainContext
        XCTAssertThrowsError(
            try TrainingDataExporter.export(context: ctx, photoStore: PhotoStore())
        ) { error in
            guard case TrainingDataExporter.ExportError.noLabeledCaptures = error else {
                return XCTFail("expected noLabeledCaptures, got \(error)")
            }
        }
    }
}
