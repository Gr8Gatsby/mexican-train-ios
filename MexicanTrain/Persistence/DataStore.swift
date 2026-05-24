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
            // Schema mismatch with existing store — wipe and recreate
            let url = config.url
            if FileManager.default.fileExists(atPath: url.path()) {
                try? FileManager.default.removeItem(at: url)
                try? FileManager.default.removeItem(at: URL(filePath: url.path() + "-wal"))
                try? FileManager.default.removeItem(at: URL(filePath: url.path() + "-shm"))
            }
            do {
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("Failed to create ModelContainer: \(error)")
            }
        }
    }
}
