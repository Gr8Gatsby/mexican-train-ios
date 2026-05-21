import Foundation
import UIKit

enum SnapshotBuilder {
    /// Build a snapshot of the current game state for broadcast. `claims` are
    /// merged in by the session itself; we pass an empty array here.
    @MainActor
    static func build(game: Game, photoStore: PhotoStore, roomCode: String) -> GameSnapshot {
        let recentStop = game.currentStopIndex - 1
        var caps: [CaptureSnapshot] = []
        if recentStop >= 1 {
            for c in game.captures where c.stopIndex == recentStop {
                if let img = photoStore.thumbnail(filename: c.filename, gameID: game.id, maxEdge: PlayerPhoto.targetEdge),
                   let data = img.jpegData(compressionQuality: 0.6),
                   data.count <= PlayerPhoto.maxJPEGBytes {
                    caps.append(CaptureSnapshot(id: c.id, playerID: c.playerID, stop: c.stopIndex, thumbJPEG: data))
                }
            }
        }
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
                PlayerSnapshot(id: $0.id, name: $0.name, seat: $0.seat, isYou: $0.isYou)
            },
            scores: game.scores.map { ScoreSnapshot(playerID: $0.playerID, stop: $0.stopIndex, pips: $0.pips) },
            recentCaptures: caps,
            endedAt: game.finishedAt,
            winnerPlayerID: Scoring.standings(for: game).first?.playerID,
            claims: []
        )
    }
}
