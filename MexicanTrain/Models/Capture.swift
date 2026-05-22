import Foundation
import SwiftData

@Model
final class Capture {
    @Attribute(.unique) var id: UUID
    var game: Game?
    var playerID: UUID
    var stopIndex: Int
    var createdAt: Date
    var filename: String                // relative to PhotoStore root
    var pipsDetected: Int?
    var confidenceRaw: String
    var tilesData: Data                 // JSON-encoded [TileObservation] — model's raw output, immutable
    /// JSON-encoded [TileObservation] of human-corrected per-half labels.
    /// Set when the conductor edits the detection overlay inside AuditView
    /// (gated on `AppSettings.trainingDataExportEnabled`). When non-nil,
    /// this is the ground truth used by `TrainingDataExporter`.
    var correctedTilesData: Data?
    var labeledAt: Date?

    init(
        id: UUID = UUID(),
        playerID: UUID,
        stopIndex: Int,
        createdAt: Date = .now,
        filename: String,
        pipsDetected: Int? = nil,
        confidence: Confidence = .medium,
        tiles: [TileObservation] = []
    ) {
        self.id = id
        self.playerID = playerID
        self.stopIndex = stopIndex
        self.createdAt = createdAt
        self.filename = filename
        self.pipsDetected = pipsDetected
        self.confidenceRaw = confidence.rawValue
        self.tilesData = (try? JSONEncoder().encode(tiles)) ?? Data()
    }

    var confidence: Confidence {
        Confidence(rawValue: confidenceRaw) ?? .medium
    }

    var tiles: [TileObservation] {
        (try? JSONDecoder().decode([TileObservation].self, from: tilesData)) ?? []
    }

    /// Ground-truth labels when the conductor has corrected the model
    /// output. Nil when no human review has been done — in that case the
    /// raw `tiles` are still the best estimate but should not be exported
    /// as training data.
    var correctedTiles: [TileObservation]? {
        guard let correctedTilesData else { return nil }
        return try? JSONDecoder().decode([TileObservation].self, from: correctedTilesData)
    }

    var isLabeled: Bool { correctedTilesData != nil }
}
