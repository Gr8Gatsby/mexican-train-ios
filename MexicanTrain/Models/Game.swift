import Foundation
import SwiftData

@Model
final class Game {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var name: String?
    var lengthStops: Int
    var startingEngineRaw: String
    var currentStopIndex: Int          // 1-indexed; reaches lengthStops + 1 when finished
    var finishedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \Player.game)
    var players: [Player] = []

    @Relationship(deleteRule: .cascade, inverse: \Score.game)
    var scores: [Score] = []

    @Relationship(deleteRule: .cascade, inverse: \Capture.game)
    var captures: [Capture] = []

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        name: String? = nil,
        lengthStops: Int = 13,
        startingEngine: StartingEngine = .traditional,
        currentStopIndex: Int = 1
    ) {
        self.id = id
        self.createdAt = createdAt
        self.name = name
        self.lengthStops = lengthStops
        self.startingEngineRaw = startingEngine.rawValue
        self.currentStopIndex = currentStopIndex
        self.finishedAt = nil
    }

    var startingEngine: StartingEngine {
        StartingEngine(rawValue: startingEngineRaw) ?? .traditional
    }

    var isFinished: Bool { finishedAt != nil }

    var sortedPlayers: [Player] {
        players.sorted { $0.seat < $1.seat }
    }

    var displayName: String {
        if let name, !name.isEmpty { return name }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: createdAt)
    }
}
