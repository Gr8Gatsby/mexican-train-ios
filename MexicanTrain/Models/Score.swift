import Foundation
import SwiftData

@Model
final class Score {
    @Attribute(.unique) var id: UUID
    var game: Game?
    var playerID: UUID
    var stopIndex: Int                 // 1-indexed
    var pips: Int
    var sourceRaw: String
    var captureID: UUID?
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        playerID: UUID,
        stopIndex: Int,
        pips: Int,
        source: ScoreSource = .manual,
        captureID: UUID? = nil,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.playerID = playerID
        self.stopIndex = stopIndex
        self.pips = pips
        self.sourceRaw = source.rawValue
        self.captureID = captureID
        self.updatedAt = updatedAt
    }

    var source: ScoreSource {
        ScoreSource(rawValue: sourceRaw) ?? .manual
    }
}
