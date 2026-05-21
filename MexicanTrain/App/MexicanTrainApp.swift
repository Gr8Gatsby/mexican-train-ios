import SwiftUI
import SwiftData

@main
struct MexicanTrainApp: App {
    @State private var coordinator: AppCoordinator

    init() {
        Fonts.registerBundledFonts()
        let container = DataStore.makeContainer()
        _coordinator = State(initialValue: AppCoordinator(container: container))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(coordinator)
                .environment(coordinator.settings)
                .environment(\.theme, .caboose)
                .modelContainer(coordinator.container)
                .preferredColorScheme(.light)
        }
    }
}

struct RootView: View {
    @Environment(AppCoordinator.self) private var coordinator

    var body: some View {
        switch coordinator.route {
        case .home:
            HomeView()
        case .newGame:
            NewGameView()
        case .scoreboard(let id):
            GameLookupView(gameID: id) { ScoreboardView(game: $0) }
        case .manualEntry(let gid, let pid, let stop):
            GameLookupView(gameID: gid) { game in
                if let player = game.players.first(where: { $0.id == pid }) {
                    ManualEntryView(game: game, player: player, stop: stop)
                } else {
                    Text("Player not found").onAppear { coordinator.goHome() }
                }
            }
        case .audit(let gid, let pid, let stop):
            GameLookupView(gameID: gid) { game in
                if let player = game.players.first(where: { $0.id == pid }) {
                    AuditView(game: game, player: player, stop: stop)
                } else {
                    Text("Player not found").onAppear { coordinator.goHome() }
                }
            }
        case .endGame(let id):
            GameLookupView(gameID: id) { EndGameView(game: $0) }
        case .settings:
            SettingsView()
        case .gameHistory(let id):
            GameLookupView(gameID: id) { GameHistoryView(game: $0) }
        }
    }
}

/// Helper view: looks a Game up by ID in the SwiftData store and renders
/// the provided builder. Encapsulates the @Query path so route views can
/// just take a `Game` parameter.
struct GameLookupView<Content: View>: View {
    let gameID: UUID
    @ViewBuilder let content: (Game) -> Content
    @Query private var games: [Game]
    @Environment(AppCoordinator.self) private var coordinator

    init(gameID: UUID, @ViewBuilder content: @escaping (Game) -> Content) {
        self.gameID = gameID
        let id = gameID
        _games = Query(filter: #Predicate<Game> { $0.id == id })
        self.content = content
    }

    var body: some View {
        if let game = games.first {
            content(game)
        } else {
            ContentUnavailableView("Game not found", systemImage: "questionmark.folder")
                .onAppear { coordinator.goHome() }
        }
    }
}
