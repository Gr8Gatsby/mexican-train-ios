import Foundation
import SwiftData

@MainActor
@Observable
final class AppCoordinator {
    enum Route: Equatable {
        case home
    }

    var route: Route = .home
    let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }
}
