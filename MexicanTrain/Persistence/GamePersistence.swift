import Foundation
import SwiftData
import UIKit

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

    /// Rebuild a full local `Game` from a cached `GameSnapshot` so a joiner can
    /// take over hosting when the original host leaves. `newConductorID` becomes
    /// the `isYou` player. Photos present in `photoCache` are written to disk so
    /// the new host can keep serving them; any missing ones are simply skipped.
    @discardableResult
    static func reconstructForHostMigration(
        in context: ModelContext,
        snapshot: GameSnapshot,
        newConductorID: UUID,
        photoCache: [UUID: Data],
        photoStore: PhotoStore
    ) throws -> Game {
        // Reuse the original gameID so joiners' rejoin/gameID checks still match.
        let game = Game(
            id: snapshot.gameID,
            name: snapshot.gameName.isEmpty ? nil : snapshot.gameName,
            lengthStops: snapshot.length,
            startingEngine: snapshot.startingEngine,
            currentStopIndex: snapshot.currentStop,
            goingOutBonus: snapshot.goingOutBonus,
            blockedRoundCapEnabled: snapshot.blockedRoundCapEnabled,
            drawCountOverride: snapshot.drawCountOverride,
            doublesPenaltyPips: snapshot.doublesPenaltyPips
        )
        game.scoringOpen = snapshot.scoringOpen
        game.finishedAt = snapshot.endedAt
        context.insert(game)

        for ps in snapshot.players.sorted(by: { $0.seat < $1.seat }) {
            let p = Player(id: ps.id, name: ps.name, seat: ps.seat,
                           isYou: ps.id == newConductorID, isActive: ps.isActive)
            p.game = game
            context.insert(p)
        }

        for ss in snapshot.scores {
            let s = Score(playerID: ss.playerID, stopIndex: ss.stop, pips: ss.pips,
                          source: .manual,
                          submittedBy: ScoreActor(rawValue: ss.submittedByRaw) ?? .conductor)
            s.excluded = ss.excluded
            s.game = game
            context.insert(s)
        }

        for entry in snapshot.recentCaptures {
            guard let data = photoCache[entry.id],
                  let img = UIImage(data: data),
                  let filename = try? photoStore.save(image: img, gameID: game.id, captureID: entry.id)
            else { continue }
            let cap = Capture(id: entry.id, playerID: entry.playerID,
                              stopIndex: entry.stop, filename: filename)
            cap.game = game
            context.insert(cap)
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
        submittedBy: ScoreActor = .conductor,
        editedBy: ScoreActor = .conductor,
        captureID: UUID? = nil
    ) throws -> Score {
        if let existing = game.scores.first(where: {
            $0.playerID == player.id && $0.stopIndex == stop
        }) {
            // Preserve the original. Each subsequent change is logged as a
            // ScoreEdit so the audit trail is reconstructable.
            let edit = ScoreEdit(
                fromPips: existing.pips, toPips: pips,
                fromExcluded: existing.excluded, toExcluded: existing.excluded,
                editedBy: editedBy
            )
            edit.score = existing
            context.insert(edit)
            existing.pips = pips
            existing.captureID = captureID ?? existing.captureID
            existing.updatedAt = .now
            try context.save()
            return existing
        }
        let s = Score(playerID: player.id, stopIndex: stop, pips: pips,
                      source: source, submittedBy: submittedBy, captureID: captureID)
        s.game = game
        context.insert(s)
        try context.save()
        return s
    }

    /// Outcome of `handleScoreSubmission` — surfaced for tests and for the
    /// receive-path log so we can tell which branch fired.
    enum SubmissionOutcome: Equatable {
        case created            // no prior score; submission becomes the new score
        case overrodeConductor  // a conductor-submitted value was overwritten by the player
        case ignored            // player-submitted value already exists; submission discarded
        case rejected(String)   // validation failure (unknown player, wrong stop, …)
    }

    /// Apply a `ScoreSubmission` received from a player joiner. Implements the
    /// race rules from functional spec §7.4: a player's submission becomes
    /// the score of record; a prior conductor-submitted value is preserved
    /// in the audit history; a prior player-submitted value is left alone
    /// (player must use the audit screen on the host to change it).
    ///
    /// `saveCapture` is the closure used to persist an optional thumbnail to
    /// disk when one is attached — the persistence layer can't import
    /// `PhotoStore`'s file IO directly, so callers wire it from the
    /// scoreboard view.
    @discardableResult
    static func handleScoreSubmission(
        in context: ModelContext,
        game: Game,
        submission: ScoreSubmission,
        saveCapture: ((UUID) throws -> Void)? = nil
    ) throws -> SubmissionOutcome {
        guard let player = game.players.first(where: { $0.id == submission.playerID }) else {
            return .rejected("unknown player")
        }
        guard submission.stopIndex == game.currentStopIndex else {
            return .rejected("stale stop")
        }
        if let existing = game.scores.first(where: {
            $0.playerID == player.id && $0.stopIndex == submission.stopIndex
        }) {
            switch existing.submittedBy {
            case .player:
                return .ignored
            case .conductor:
                // Overwrite the value; log the transition with the player as the editor.
                let edit = ScoreEdit(
                    fromPips: existing.pips, toPips: submission.pips,
                    fromExcluded: existing.excluded, toExcluded: existing.excluded,
                    editedBy: .player
                )
                edit.score = existing
                context.insert(edit)
                existing.pips = submission.pips
                existing.submittedByRaw = ScoreActor.player.rawValue
                existing.sourceRaw = submission.source.rawValue
                existing.updatedAt = .now
                if let captureID = try Self.persistCapture(submission: submission,
                                                          game: game, player: player,
                                                          context: context,
                                                          saveCapture: saveCapture) {
                    existing.captureID = captureID
                }
                try context.save()
                return .overrodeConductor
            }
        }
        let captureID = try Self.persistCapture(submission: submission, game: game,
                                                player: player, context: context,
                                                saveCapture: saveCapture)
        let score = Score(
            playerID: player.id,
            stopIndex: submission.stopIndex,
            pips: submission.pips,
            source: submission.source,
            submittedBy: .player,
            captureID: captureID
        )
        score.game = game
        context.insert(score)
        try context.save()
        return .created
    }

    /// If the submission carries a thumbnail, build a `Capture` row pointing
    /// at the on-disk JPEG (written by `saveCapture` closure). Returns the
    /// capture ID so the caller can wire it to the new `Score`.
    private static func persistCapture(
        submission: ScoreSubmission,
        game: Game,
        player: Player,
        context: ModelContext,
        saveCapture: ((UUID) throws -> Void)?
    ) throws -> UUID? {
        guard submission.thumbJPEG != nil, let saveCapture else { return nil }
        let id = UUID()
        try saveCapture(id)
        let filename = "\(id.uuidString).jpg"
        let capture = Capture(
            id: id,
            playerID: player.id,
            stopIndex: submission.stopIndex,
            filename: filename,
            pipsDetected: submission.pips,
            confidence: .medium,
            tiles: submission.tiles
        )
        capture.game = game
        context.insert(capture)
        return id
    }

    /// Toggle a score's excluded flag. Excluded scores contribute 0 to the
    /// total but remain on the board for audit visibility.
    static func setScoreExcluded(
        in context: ModelContext,
        score: Score,
        excluded: Bool,
        editedBy: ScoreActor = .conductor,
        note: String? = nil
    ) throws {
        guard score.excluded != excluded else { return }
        let edit = ScoreEdit(
            fromPips: score.pips, toPips: score.pips,
            fromExcluded: score.excluded, toExcluded: excluded,
            editedBy: editedBy, note: note
        )
        edit.score = score
        context.insert(edit)
        score.excluded = excluded
        score.updatedAt = .now
        try context.save()
    }

    /// Whether the just-completed stop ended without anyone going out — i.e.
    /// every active player's recorded pips for this stop is > 0. Used by the
    /// blocked-round-cap rule to decide whether the conductor should be
    /// offered the "set lowest to 0" shortcut before advancing.
    static func wasStopBlocked(_ stop: Int, in game: Game) -> Bool {
        let activeIDs = Set(game.players.filter(\.isActive).map(\.id))
        let stopScores = game.scores.filter { activeIDs.contains($0.playerID) && $0.stopIndex == stop }
        guard !stopScores.isEmpty else { return false }
        return stopScores.allSatisfy { $0.pips > 0 }
    }

    /// Apply the blocked-round-cap rule: find the active player with the
    /// lowest pip total for `stop` and rewrite that score to 0. Other scores
    /// are left intact. Logged as a ScoreEdit so the audit shows the cap.
    @discardableResult
    static func applyBlockedRoundCap(_ stop: Int, in game: Game,
                                     context: ModelContext) throws -> Score? {
        let activeIDs = Set(game.players.filter(\.isActive).map(\.id))
        let candidates = game.scores
            .filter { activeIDs.contains($0.playerID) && $0.stopIndex == stop && $0.pips > 0 }
        guard let lowest = candidates.min(by: { $0.pips < $1.pips }) else { return nil }
        let edit = ScoreEdit(
            fromPips: lowest.pips, toPips: 0,
            fromExcluded: lowest.excluded, toExcluded: lowest.excluded,
            editedBy: .conductor, note: "blocked-round cap"
        )
        edit.score = lowest
        context.insert(edit)
        lowest.pips = 0
        lowest.updatedAt = .now
        try context.save()
        return lowest
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
            game.scoringOpen = false
        }
        try context.save()
    }

    static func delete(game: Game, in context: ModelContext, photoStore: PhotoStore? = nil) throws {
        photoStore?.deleteAll(gameID: game.id)
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
