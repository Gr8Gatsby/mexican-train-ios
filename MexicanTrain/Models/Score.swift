import Foundation
import SwiftData

@Model
final class Score {
    @Attribute(.unique) var id: UUID
    var game: Game?
    var playerID: UUID
    var stopIndex: Int                 // 1-indexed
    var pips: Int                      // current effective value
    var originalPips: Int              // value at first submission; never mutated
    var excluded: Bool                 // when true, total skips this score (still counts as "entered")
    var sourceRaw: String              // .scanned or .manual (origin of first submission)
    var submittedByRaw: String         // .player or .conductor — current "owner" of the value (mutates when a player overrides a conductor entry)
    var originalSubmittedByRaw: String // .player or .conductor — set at first submission and never mutated; what the audit report shows for the "submitted by …" line
    var captureID: UUID?
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \ScoreEdit.score)
    var edits: [ScoreEdit] = []

    init(
        id: UUID = UUID(),
        playerID: UUID,
        stopIndex: Int,
        pips: Int,
        source: ScoreSource = .manual,
        submittedBy: ScoreActor = .conductor,
        captureID: UUID? = nil,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.playerID = playerID
        self.stopIndex = stopIndex
        self.pips = pips
        self.originalPips = pips
        self.excluded = false
        self.sourceRaw = source.rawValue
        self.submittedByRaw = submittedBy.rawValue
        self.originalSubmittedByRaw = submittedBy.rawValue
        self.captureID = captureID
        self.updatedAt = updatedAt
    }

    var source: ScoreSource {
        ScoreSource(rawValue: sourceRaw) ?? .manual
    }

    var submittedBy: ScoreActor {
        ScoreActor(rawValue: submittedByRaw) ?? .conductor
    }

    var originalSubmittedBy: ScoreActor {
        ScoreActor(rawValue: originalSubmittedByRaw) ?? submittedBy
    }

    /// Value this score contributes to the running total. Zero when excluded.
    var effectivePips: Int { excluded ? 0 : pips }
}

@Model
final class ScoreEdit {
    @Attribute(.unique) var id: UUID
    var score: Score?
    var fromPips: Int
    var toPips: Int
    var fromExcluded: Bool
    var toExcluded: Bool
    var editedAt: Date
    var editedByRaw: String           // ScoreActor.rawValue
    var note: String?

    init(
        id: UUID = UUID(),
        fromPips: Int,
        toPips: Int,
        fromExcluded: Bool,
        toExcluded: Bool,
        editedAt: Date = .now,
        editedBy: ScoreActor = .conductor,
        note: String? = nil
    ) {
        self.id = id
        self.fromPips = fromPips
        self.toPips = toPips
        self.fromExcluded = fromExcluded
        self.toExcluded = toExcluded
        self.editedAt = editedAt
        self.editedByRaw = editedBy.rawValue
        self.note = note
    }

    var editedBy: ScoreActor {
        ScoreActor(rawValue: editedByRaw) ?? .conductor
    }
}

enum ScoreActor: String, Codable {
    case player
    case conductor
}
