import Foundation
import SwiftData

/// One row per game the user has joined (as player or spectator). Caches
/// the most recent `GameSnapshot` we received from the host so the joiner
/// has a local record after disconnect — addresses the spec's previously-
/// deferred "joiner persistence" item.
///
/// We hold the snapshot as opaque JSON Data plus a few indexed fields
/// that the Home list needs to render cheaply (gameName, hostName,
/// lastUpdatedAt, endedAt). Capture thumbnails accumulate separately so
/// the joiner ends up with every stop's gallery instead of just the
/// most recent one (`snapshot.recentCaptures` is intentionally narrow).
@Model
final class JoinedGameRecord {
    @Attribute(.unique) var gameID: UUID
    var gameName: String
    var hostName: String
    var joinedAt: Date
    var lastUpdatedAt: Date
    var endedAt: Date?
    /// The slot the joiner claimed for themselves, if any. Lets the
    /// detail view highlight the right row and exists primarily for the
    /// nice-to-have "your stats" strip in the future.
    var myPlayerID: UUID?
    /// JSON-encoded `GameSnapshot`. Decode lazily via `snapshot`.
    var snapshotData: Data

    @Relationship(deleteRule: .cascade, inverse: \JoinedCapture.game)
    var captures: [JoinedCapture] = []

    init(
        gameID: UUID,
        gameName: String,
        hostName: String,
        joinedAt: Date = .now,
        lastUpdatedAt: Date = .now,
        endedAt: Date? = nil,
        myPlayerID: UUID? = nil,
        snapshotData: Data
    ) {
        self.gameID = gameID
        self.gameName = gameName
        self.hostName = hostName
        self.joinedAt = joinedAt
        self.lastUpdatedAt = lastUpdatedAt
        self.endedAt = endedAt
        self.myPlayerID = myPlayerID
        self.snapshotData = snapshotData
    }

    var snapshot: GameSnapshot? {
        try? JSONDecoder().decode(GameSnapshot.self, from: snapshotData)
    }

    var isFinished: Bool { endedAt != nil }
}

/// Accumulated per-stop photo thumbnails for a joined game. Captures
/// arrive on the wire inside `GameSnapshot.recentCaptures` (only the
/// previous stop) — we dedup by `captureID` and persist so the joiner's
/// detail view can scroll all photos from all stops, not just the last.
@Model
final class JoinedCapture {
    @Attribute(.unique) var captureID: UUID
    var game: JoinedGameRecord?
    var playerID: UUID
    var stopIndex: Int
    var thumbJPEG: Data
    var receivedAt: Date

    init(
        captureID: UUID,
        playerID: UUID,
        stopIndex: Int,
        thumbJPEG: Data,
        receivedAt: Date = .now
    ) {
        self.captureID = captureID
        self.playerID = playerID
        self.stopIndex = stopIndex
        self.thumbJPEG = thumbJPEG
        self.receivedAt = receivedAt
    }
}
