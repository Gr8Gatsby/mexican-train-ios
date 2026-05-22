import Foundation
import SwiftData

/// Joiner-side persistence: upsert a `JoinedGameRecord` for each game
/// the user joins (player or spectator) and accumulate `JoinedCapture`
/// thumbnails as new captures show up in incoming snapshots.
///
/// Cheap to call on every snapshot — the upsert is one fetch + zero or
/// one write to the indexed `gameID`, and captures are deduped by
/// `captureID` so re-receiving the same gallery is a no-op.
enum JoinedGamePersistence {
    @discardableResult
    static func upsert(
        in context: ModelContext,
        snapshot: GameSnapshot,
        myPlayerID: UUID?
    ) throws -> JoinedGameRecord {
        let snapshotData = try JSONEncoder().encode(snapshot)
        let gameID = snapshot.gameID
        let descriptor = FetchDescriptor<JoinedGameRecord>(
            predicate: #Predicate { $0.gameID == gameID }
        )
        let existing = (try? context.fetch(descriptor))?.first

        let record: JoinedGameRecord
        if let existing {
            existing.gameName = snapshot.gameName
            existing.hostName = snapshot.hostName
            existing.lastUpdatedAt = .now
            existing.endedAt = snapshot.endedAt
            existing.snapshotData = snapshotData
            if existing.myPlayerID == nil, let myPlayerID {
                existing.myPlayerID = myPlayerID
            }
            record = existing
        } else {
            record = JoinedGameRecord(
                gameID: gameID,
                gameName: snapshot.gameName,
                hostName: snapshot.hostName,
                endedAt: snapshot.endedAt,
                myPlayerID: myPlayerID,
                snapshotData: snapshotData
            )
            context.insert(record)
        }

        try mergeCaptures(into: record, from: snapshot, context: context)
        try context.save()
        return record
    }

    private static func mergeCaptures(
        into record: JoinedGameRecord,
        from snapshot: GameSnapshot,
        context: ModelContext
    ) throws {
        guard !snapshot.recentCaptures.isEmpty else { return }
        let known = Set(record.captures.map(\.captureID))
        for capture in snapshot.recentCaptures where !known.contains(capture.id) {
            let cap = JoinedCapture(
                captureID: capture.id,
                playerID: capture.playerID,
                stopIndex: capture.stop,
                thumbJPEG: capture.thumbJPEG
            )
            cap.game = record
            context.insert(cap)
        }
    }

    static func delete(_ record: JoinedGameRecord, in context: ModelContext) throws {
        context.delete(record)
        try context.save()
    }
}
