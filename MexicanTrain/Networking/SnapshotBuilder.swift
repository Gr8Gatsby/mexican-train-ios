import Foundation
import UIKit

enum SnapshotBuilder {
    @MainActor
    static func build(game: Game, roomCode: String) -> GameSnapshot {
        let entries = game.captures.map {
            CaptureManifestEntry(id: $0.id, playerID: $0.playerID, stop: $0.stopIndex)
        }
        print("[SnapshotBuilder] \(game.captures.count) captures on disk, \(entries.count) manifest entries (0 bytes in snapshot)")
        return GameSnapshot(
            seq: 0, // session overwrites
            roomCode: roomCode,
            hostName: UIDevice.current.name,
            gameID: game.id,
            gameName: game.displayName,
            length: game.lengthStops,
            startingEngineRaw: game.startingEngineRaw,
            currentStop: game.currentStopIndex,
            players: game.sortedPlayers.map {
                PlayerSnapshot(id: $0.id, name: $0.name, seat: $0.seat, isYou: $0.isYou, isActive: $0.isActive)
            },
            scores: game.scores.map {
                ScoreSnapshot(
                    playerID: $0.playerID,
                    stop: $0.stopIndex,
                    pips: $0.pips,
                    submittedByRaw: $0.submittedByRaw,
                    excluded: $0.excluded
                )
            },
            recentCaptures: entries,
            endedAt: game.finishedAt,
            winnerPlayerID: Scoring.standings(for: game).first?.playerID,
            claims: []
        )
    }
}
