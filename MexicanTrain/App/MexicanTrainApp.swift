import SwiftUI
import SwiftData

@main
struct MexicanTrainApp: App {
    @State private var coordinator: AppCoordinator

    init() {
        Fonts.registerBundledFonts()
        let container = DataStore.makeContainer()
        let coord = AppCoordinator(container: container)
        #if DEBUG
        DebugSeed.seedIfRequested(container: container, photoStore: coord.photoStore)
        DebugRoute.applyIfRequested(to: coord, container: container)
        #endif
        // Clean orphaned photo directories on launch
        Self.cleanOrphanedPhotos(container: container, photoStore: coord.photoStore)
        _coordinator = State(initialValue: coord)
    }

    @MainActor
    private static func cleanOrphanedPhotos(container: ModelContainer, photoStore: PhotoStore) {
        let context = container.mainContext
        let descriptor = FetchDescriptor<Game>()
        guard let games = try? context.fetch(descriptor) else { return }
        let validIDs = Set(games.map(\.id))
        photoStore.cleanOrphaned(validGameIDs: validIDs)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(coordinator)
                .environment(coordinator.settings)
                .environment(\.theme, .caboose)
                .modelContainer(coordinator.container)
                .preferredColorScheme(.light)
                .onOpenURL { url in
                    coordinator.handle(url: url)
                }
        }
    }
}

struct RootView: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.theme) private var theme

    var body: some View {
        @Bindable var bind = coordinator
        return ZStack {
            theme.bg.ignoresSafeArea()
            currentRoute
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(item: $bind.sheet) { sheet in
            switch sheet {
            case .share(let id):
                GameLookupView(gameID: id) { ShareGameSheet(game: $0) }
            case .join(let code):
                JoinSheet(initialCode: code)
            }
        }
    }

    @ViewBuilder
    private var currentRoute: some View {
        switch coordinator.route {
        case .home:
            HomeView()
        case .newGame:
            NewGameView()
        case .scoreboard(let id):
            GameLookupView(gameID: id) { ScoreboardView(game: $0) }
        case .camera(let gid, let pid, let stop, let subject):
            GameLookupView(gameID: gid) { game in
                if let player = game.players.first(where: { $0.id == pid }) {
                    CameraView(game: game, player: player, stop: stop, topBarSubject: subject)
                } else {
                    Text("Player not found").onAppear { coordinator.goHome() }
                }
            }
        case .manualEntry(let gid, let pid, let stop, let subject):
            GameLookupView(gameID: gid) { game in
                if let player = game.players.first(where: { $0.id == pid }) {
                    ManualEntryView(game: game, player: player, stop: stop, topBarSubject: subject)
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
        case .spectator:
            SpectatorView()
        case .joinerCamera(let pid, let pname, let stop, let len):
            JoinerCameraHost(playerID: pid, playerName: pname, stop: stop, lengthStops: len)
        case .joinerManualEntry(let pid, let pname, let stop, let len):
            JoinerManualEntryView(playerID: pid, playerName: pname, stop: stop, lengthStops: len)
        case .joinedGameDetail(let gid):
            JoinedGameView(gameID: gid)
        }
    }
}

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
