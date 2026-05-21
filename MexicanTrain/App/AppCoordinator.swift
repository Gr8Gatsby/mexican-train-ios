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
        case spectator
    }

    enum SheetRoute: Equatable, Identifiable {
        case share(gameID: UUID)
        case join(prefilledCode: String?)
        var id: String {
            switch self {
            case .share(let id): "share-\(id)"
            case .join(let c): "join-\(c ?? "")"
            }
        }
    }

    var route: Route = .home
    var sheet: SheetRoute?
    let container: ModelContainer
    let settings: AppSettings
    let photoStore: PhotoStore
    let pipCounter: any PipCounter
    let netSession: MexTrainNetSession

    init(
        container: ModelContainer,
        settings: AppSettings? = nil,
        photoStore: PhotoStore = PhotoStore(),
        pipCounter: (any PipCounter)? = nil,
        netSession: MexTrainNetSession? = nil
    ) {
        self.container = container
        self.settings = settings ?? AppSettings()
        self.photoStore = photoStore
        self.pipCounter = pipCounter ?? PipCounterFactory.makeProductionCounter()
        self.netSession = netSession ?? MexTrainNetSession()
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
    func openSpectator() { route = .spectator }

    func openShareSheet(for game: Game) { sheet = .share(gameID: game.id) }
    func openJoinSheet(code: String? = nil) { sheet = .join(prefilledCode: code) }
    func dismissSheet() { sheet = nil }

    /// Handle `mextrain://join?code=NNNN` URLs from the iOS Camera scanner or
    /// any other source.
    func handle(url: URL) {
        if let code = JoinURL.decode(url) {
            openJoinSheet(code: code)
        }
    }
}
