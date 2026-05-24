#if DEBUG
import Foundation
import SwiftData
import UIKit

/// One-shot seeder for visual testing. Only runs in DEBUG, and only when
/// the env variable MEXTRAIN_DEBUG_SEED=1 is set. Wipes everything and
/// creates two games:
///   - "In-progress": 4 players (Kevin is "you"), 3 stops scored, photos.
///   - "Finished": 3 players, all 13 stops scored, winner declared.
enum DebugSeed {

    @MainActor
    static func seedIfRequested(container: ModelContainer, photoStore: PhotoStore) {
        guard ProcessInfo.processInfo.environment["MEXTRAIN_DEBUG_SEED"] == "1" else { return }
        let ctx = container.mainContext

        // Wipe.
        for g in (try? ctx.fetch(FetchDescriptor<Game>())) ?? [] {
            photoStore.deleteAll(gameID: g.id)
            ctx.delete(g)
        }
        // Also clear any joined-game records left over from prior runs so
        // the home view's JOINED section starts empty.
        for r in (try? ctx.fetch(FetchDescriptor<JoinedGameRecord>())) ?? [] {
            ctx.delete(r)
        }
        for c in (try? ctx.fetch(FetchDescriptor<JoinedCapture>())) ?? [] {
            ctx.delete(c)
        }
        try? ctx.save()

        // In-progress.
        let live = try? GamePersistence.createGame(
            in: ctx, length: 13, startingEngine: .traditional,
            playerNames: ["Aaron", "Kevin", "Comp", "Dale"],
            youIndex: 1, name: "Friday night"
        )
        if let live {
            let players = live.sortedPlayers
            let pattern: [[Int]] = [
                [38, 12, 22],
                [14,  0, 18],
                [22,  5,  9],
                [16,  4, 12]
            ]
            for (pi, p) in players.enumerated() {
                for (si, val) in pattern[pi].enumerated() {
                    _ = try? GamePersistence.recordScore(in: ctx, game: live, player: p,
                                                     stop: si + 1, pips: val, source: .manual)
                }
            }
            live.currentStopIndex = 4
            // Seed a few captures so the gallery has something.
            for p in players {
                let img = makeTestImage(seed: p.id.uuidString)
                if let cap = try? CapturePersistence.saveCapture(
                    in: ctx, photoStore: photoStore, game: live, player: p,
                    stop: 3, image: img,
                    result: PipCountResult(tiles: [TileObservation(a: 5, b: 3)],
                                           total: 8, confidence: .high)
                ) {
                    _ = cap
                }
            }
            try? ctx.save()
        }

        // Finished.
        let done = try? GamePersistence.createGame(
            in: ctx, length: 7, startingEngine: .traditional,
            playerNames: ["Edie", "Frankie", "Gus"],
            youIndex: 0, name: "Sunday match"
        )
        if let done {
            let players = done.sortedPlayers
            let totals: [[Int]] = [
                [20,  9, 14, 10,  6,  8, 12],
                [11, 22,  8, 14,  7,  9, 11],
                [ 5, 17, 20, 12,  4,  6,  8]
            ]
            for (pi, p) in players.enumerated() {
                for (si, val) in totals[pi].enumerated() {
                    _ = try? GamePersistence.recordScore(in: ctx, game: done, player: p,
                                                     stop: si + 1, pips: val, source: .manual)
                }
            }
            done.currentStopIndex = 8
            done.finishedAt = .now
            try? ctx.save()
        }
    }

    private static func makeTestImage(seed: String) -> UIImage {
        let h = abs(seed.hashValue)
        let r = CGFloat((h >> 0) & 0xFF) / 255.0
        let g = CGFloat((h >> 8) & 0xFF) / 255.0
        let b = CGFloat((h >> 16) & 0xFF) / 255.0
        let size = CGSize(width: 256, height: 256)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(red: r, green: g, blue: b, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }
}
#endif
