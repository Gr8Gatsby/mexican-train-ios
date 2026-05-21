import Foundation
import SwiftData

enum DataStore {
    /// Build the SwiftData model container. M0 registers a single stub schema
    /// so the container instantiates cleanly; later milestones add the real
    /// Game / Player / Score / Capture models per dev-design §3.
    static func makeContainer() -> ModelContainer {
        let schema = Schema([
            Game.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
}
