import Foundation
import SwiftData

@MainActor
@Observable
final class AppCoordinator {
    enum Route: Equatable {
        case home
        case newGame
        case scoreboard(gameID: UUID)
        case camera(gameID: UUID, playerID: UUID, stop: Int)
        case manualEntry(gameID: UUID, playerID: UUID, stop: Int)
        case audit(gameID: UUID, playerID: UUID, stop: Int)
        case endGame(gameID: UUID)
        case settings
        case gameHistory(gameID: UUID)
    }

    var route: Route = .home
    let container: ModelContainer
    let settings: AppSettings
    let photoStore: PhotoStore
    let pipCounter: any PipCounter

    init(
        container: ModelContainer,
        settings: AppSettings? = nil,
        photoStore: PhotoStore = PhotoStore(),
        pipCounter: (any PipCounter)? = nil
    ) {
        self.container = container
        self.settings = settings ?? AppSettings()
        self.photoStore = photoStore
        self.pipCounter = pipCounter ?? MockPipCounter()
    }

    func goHome() { route = .home }
    func openNewGame() { route = .newGame }
    func openScoreboard(_ game: Game) { route = .scoreboard(gameID: game.id) }
    func openCamera(game: Game, player: Player, stop: Int) {
        route = .camera(gameID: game.id, playerID: player.id, stop: stop)
    }
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
