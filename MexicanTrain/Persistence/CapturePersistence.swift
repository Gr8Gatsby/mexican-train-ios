import Foundation
import SwiftData
import UIKit

enum CapturePersistence {
    @discardableResult
    static func saveCapture(
        in context: ModelContext,
        photoStore: PhotoStore,
        game: Game,
        player: Player,
        stop: Int,
        image: UIImage,
        result: PipCountResult
    ) throws -> Capture {
        let captureID = UUID()
        let filename = try photoStore.save(image: image, gameID: game.id, captureID: captureID)
        let capture = Capture(
            id: captureID,
            playerID: player.id,
            stopIndex: stop,
            filename: filename,
            pipsDetected: result.total,
            confidence: result.confidence,
            tiles: result.tiles
        )
        capture.game = game
        context.insert(capture)
        try context.save()
        return capture
    }

    /// Persist the conductor's per-half corrections as ground-truth labels
    /// for training-data export. Updates `correctedTilesData` and
    /// `labeledAt` without touching the immutable `tilesData` snapshot
    /// from the model.
    static func saveLabels(
        in context: ModelContext,
        capture: Capture,
        tiles: [TileObservation]
    ) throws {
        capture.correctedTilesData = try JSONEncoder().encode(tiles)
        capture.labeledAt = .now
        try context.save()
    }
}
