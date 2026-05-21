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
        }
    }
}
