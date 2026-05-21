import Foundation
import SwiftData

@MainActor
@Observable
final class AppCoordinator {
    enum Route: Equatable {
        case home
        case newGame
        case scoreboard(gameID: UUID)
        case manualEntry(gameID: UUID, playerID: UUID, stop: Int)
        case audit(gameID: UUID, playerID: UUID, stop: Int)
        case endGame(gameID: UUID)
        case settings
        case gameHistory(gameID: UUID)
    }

    var route: Route = .home
    let container: ModelContainer
    let settings: AppSettings

    init(container: ModelContainer, settings: AppSettings? = nil) {
        self.container = container
        self.settings = settings ?? AppSettings()
    }

    func goHome() { route = .home }
    func openNewGame() { route = .newGame }
    func openScoreboard(_ game: Game) { route = .scoreboard(gameID: game.id) }
    func openManualEntry(game: Game, player: Player, stop: Int) {
        route = .manualEntry(gameID: game.id, playerID: player.id, stop: stop)
    }
    func openAudit(game: Game, player: Player, stop: Int) {
        route = .audit(gameID: game.id, playerID: player.id, stop: stop)
    }
    func openEndGame(_ game: Game) { route = .endGame(gameID: game.id) }
    func openSettings() { route = .settings }
    func openGameHistory(_ game: Game) { route = .gameHistory(gameID: game.id) }
}
