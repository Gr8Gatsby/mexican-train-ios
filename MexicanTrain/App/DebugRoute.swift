#if DEBUG
import Foundation
import SwiftData

/// Drives initial routing from the MEXTRAIN_DEBUG_ROUTE env variable, so
/// xcrun simctl launch --env can drop the app directly onto any screen
/// for visual auditing.
enum DebugRoute {
    @MainActor
    static func applyIfRequested(to coord: AppCoordinator, container: ModelContainer) {
        guard let name = ProcessInfo.processInfo.environment["MEXTRAIN_DEBUG_ROUTE"] else { return }
        let ctx = container.mainContext
        let games = (try? ctx.fetch(FetchDescriptor<Game>())) ?? []
        let liveGame = games.first(where: { !$0.isFinished })
        let finishedGame = games.first(where: { $0.isFinished })
        let firstPlayer = liveGame?.sortedPlayers.first
        let scoredPlayer = liveGame.flatMap { g in
            g.sortedPlayers.first { p in g.scores.contains { $0.playerID == p.id } }
        }

        switch name {
        case "home":
            coord.route = .home
        case "newGame":
            coord.route = .newGame
        case "settings":
            coord.route = .settings
        case "scoreboard":
            if let g = liveGame { coord.route = .scoreboard(gameID: g.id) }
        case "manualEntry":
            if let g = liveGame, let p = firstPlayer {
                coord.route = .manualEntry(gameID: g.id, playerID: p.id, stop: g.currentStopIndex)
            }
        case "camera":
            if let g = liveGame, let p = firstPlayer {
                coord.route = .camera(gameID: g.id, playerID: p.id, stop: g.currentStopIndex,
                                      topBarSubject: nil)
            }
        case "audit":
            if let g = liveGame, let p = scoredPlayer ?? firstPlayer {
                coord.route = .audit(gameID: g.id, playerID: p.id, stop: 1)
            }
        case "endGame":
            if let g = finishedGame { coord.route = .endGame(gameID: g.id) }
        case "gameHistory":
            if let g = finishedGame { coord.route = .gameHistory(gameID: g.id) }
        case "shareSheet":
            if let g = liveGame {
                coord.route = .scoreboard(gameID: g.id)
                coord.sheet = .share(gameID: g.id)
            }
        case "joinSheet":
            coord.sheet = .join(prefilledCode: nil)
        case "spectator":
            coord.route = .spectator
        default:
            break
        }
    }
}
#endif
