import Foundation
import SwiftData

enum DataStore {
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema([
            Game.self,
            Player.self,
            Score.self,
            Capture.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
}
