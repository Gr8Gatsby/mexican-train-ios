import Foundation
import SwiftData

enum DataStore {
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema([
            Game.self,
            Player.self,
            Score.self,
            ScoreEdit.self,
            Capture.self,
            JoinedGameRecord.self,
            JoinedCapture.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            print("ModelContainer failed: \(error) — deleting store and retrying")
            Self.deleteStore()
            do {
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("Failed to create ModelContainer: \(error)")
            }
        }
    }

    private static func deleteStore() {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let storeName = "default.store"
        for suffix in ["", "-wal", "-shm"] {
            let url = appSupport.appendingPathComponent(storeName + suffix)
            try? FileManager.default.removeItem(at: url)
        }
    }
}
