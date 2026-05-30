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
    var scoringOpen: Bool
    var finishedAt: Date?

    // House rules — defaults match v0.x behavior so existing rows stay valid
    // without a schema migration.
    var goingOutBonusRaw: Int = 0       // GoingOutBonus.rawValue: 0, -5, -10
    var blockedRoundCapEnabled: Bool = false
    /// nil = auto-scale by active player count; otherwise use this exact value.
    var drawCountOverride: Int? = nil
    var doublesPenaltyPips: Int = 0     // 0, 5, or 10 in v1
    var doubleBlankPenaltyPips: Int = 0 // 0, 25, or 50 in v1
    var doublesCountDouble: Bool = false
    var anyBlankPenaltyPips: Int = 0    // 0 or 5 in v1

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
        currentStopIndex: Int = 1,
        goingOutBonus: GoingOutBonus = .none,
        blockedRoundCapEnabled: Bool = false,
        drawCountOverride: Int? = nil,
        doublesPenaltyPips: Int = 0,
        doubleBlankPenaltyPips: Int = 0,
        doublesCountDouble: Bool = false,
        anyBlankPenaltyPips: Int = 0
    ) {
        self.id = id
        self.createdAt = createdAt
        self.name = name
        self.lengthStops = lengthStops
        self.startingEngineRaw = startingEngine.rawValue
        self.currentStopIndex = currentStopIndex
        self.scoringOpen = false
        self.finishedAt = nil
        self.goingOutBonusRaw = goingOutBonus.rawValue
        self.blockedRoundCapEnabled = blockedRoundCapEnabled
        self.drawCountOverride = drawCountOverride
        self.doublesPenaltyPips = doublesPenaltyPips
        self.doubleBlankPenaltyPips = doubleBlankPenaltyPips
        self.doublesCountDouble = doublesCountDouble
        self.anyBlankPenaltyPips = anyBlankPenaltyPips
    }

    var startingEngine: StartingEngine {
        StartingEngine(rawValue: startingEngineRaw) ?? .traditional
    }

    var goingOutBonus: GoingOutBonus {
        GoingOutBonus(rawValue: goingOutBonusRaw) ?? .none
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

    /// Active draw count, accounting for the conductor's override.
    func effectiveDrawCount(activeCount: Int) -> Int {
        drawCountOverride ?? DrawCount.auto(forActiveCount: activeCount)
    }
}
