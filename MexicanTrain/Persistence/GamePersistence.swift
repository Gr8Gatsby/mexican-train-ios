import Foundation
import SwiftData

/// Stateless helpers that mutate game state through a ModelContext. Keeping the
/// CRUD here means views/viewmodels stay focused on UI; tests can exercise the
/// rules without touching SwiftUI.
enum GamePersistence {

    @discardableResult
    static func createGame(
        in context: ModelContext,
        length: Int,
        startingEngine: StartingEngine,
        playerNames: [String],
        youIndex: Int? = nil,
        name: String? = nil
    ) throws -> Game {
        let game = Game(name: name, lengthStops: length, startingEngine: startingEngine)
        context.insert(game)
        for (i, n) in playerNames.enumerated() {
            let p = Player(name: n.trimmingCharacters(in: .whitespacesAndNewlines),
                           seat: i,
                           isYou: youIndex == i)
            p.game = game
            context.insert(p)
        }
        try context.save()
        return game
    }

    @discardableResult
    static func recordScore(
        in context: ModelContext,
        game: Game,
        player: Player,
        stop: Int,
        pips: Int,
        source: ScoreSource,
        captureID: UUID? = nil
    ) throws -> Score {
        if let existing = game.scores.first(where: {
            $0.playerID == player.id && $0.stopIndex == stop
        }) {
            existing.pips = pips
            existing.sourceRaw = source.rawValue
            existing.captureID = captureID
            existing.updatedAt = .now
            try context.save()
            return existing
        }
        let s = Score(playerID: player.id, stopIndex: stop, pips: pips, source: source, captureID: captureID)
        s.game = game
        context.insert(s)
        try context.save()
        return s
    }

    /// Advance the current stop forward if the present one is complete. If
    /// the just-closed stop is the final one, the game is finished.
    static func maybeAdvanceStop(in context: ModelContext, game: Game) throws {
        guard !game.isFinished else { return }
        let stop = game.currentStopIndex
        guard Scoring.isStopComplete(stop, in: game) else { return }
        if stop >= game.lengthStops {
            game.finishedAt = .now
            game.currentStopIndex = game.lengthStops + 1
        } else {
            game.currentStopIndex = stop + 1
        }
        try context.save()
    }

    static func delete(game: Game, in context: ModelContext) throws {
        context.delete(game)
        try context.save()
    }

    static func renameGame(_ game: Game, to newName: String, in context: ModelContext) throws {
        game.name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        try context.save()
    }

    static func endGameEarly(_ game: Game, in context: ModelContext) throws {
        game.finishedAt = .now
        game.currentStopIndex = max(game.currentStopIndex, game.lengthStops + 1)
        try context.save()
    }
}
