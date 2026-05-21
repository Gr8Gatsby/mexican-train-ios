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
    var tilesData: Data                 // JSON-encoded [TileObservation]

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
}
