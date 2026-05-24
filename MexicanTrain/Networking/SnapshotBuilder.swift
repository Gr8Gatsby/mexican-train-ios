import Foundation
import UIKit

enum SnapshotBuilder {
    @MainActor private static var thumbCache: [UUID: Data] = [:]
    @MainActor private static var pendingIDs: Set<UUID> = []

    @MainActor
    static func build(game: Game, photoStore: PhotoStore, roomCode: String) -> GameSnapshot {
        var caps: [CaptureSnapshot] = []
        var uncached: [(Capture, UUID)] = []
        for c in game.captures {
            if let cached = thumbCache[c.id] {
                caps.append(CaptureSnapshot(id: c.id, playerID: c.playerID, stop: c.stopIndex, thumbJPEG: cached))
            } else if !pendingIDs.contains(c.id) {
                uncached.append((c, game.id))
            }
        }
        if !uncached.isEmpty {
            for (c, gameID) in uncached { pendingIDs.insert(c.id) }
            let items = uncached.map { (id: $0.0.id, playerID: $0.0.playerID, stop: $0.0.stopIndex, filename: $0.0.filename, gameID: $0.1) }
            Task.detached(priority: .utility) {
                for item in items {
                    guard let img = photoStore.thumbnail(filename: item.filename, gameID: item.gameID, maxEdge: PlayerPhoto.targetEdge),
                          let data = img.jpegData(compressionQuality: 0.6),
                          data.count <= PlayerPhoto.maxJPEGBytes else { continue }
                    await MainActor.run {
                        thumbCache[item.id] = data
                        pendingIDs.remove(item.id)
                    }
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
            scores: game.scores.map {
                ScoreSnapshot(
                    playerID: $0.playerID,
                    stop: $0.stopIndex,
                    pips: $0.pips,
                    submittedByRaw: $0.submittedByRaw,
                    excluded: $0.excluded
                )
            },
            recentCaptures: caps,
            endedAt: game.finishedAt,
            winnerPlayerID: Scoring.standings(for: game).first?.playerID,
            claims: []
        )
    }
}
