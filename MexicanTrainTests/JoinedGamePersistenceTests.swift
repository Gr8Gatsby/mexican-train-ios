import XCTest
import SwiftData
@testable import MexicanTrain

@MainActor
final class JoinedGamePersistenceTests: XCTestCase {
    private var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        container = DataStore.makeContainer(inMemory: true)
    }

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

    private func makeSnapshot(
        gameID: UUID = UUID(),
        currentStop: Int = 2,
        scores: [ScoreSnapshot] = [],
        captures: [CaptureManifestEntry] = [],
        ended: Bool = false
    ) -> GameSnapshot {
        GameSnapshot(
            seq: 1,
            roomCode: "4719",
            hostName: "Bob",
            gameID: gameID,
            gameName: "Saturday",
            length: 7,
            startingEngineRaw: StartingEngine.traditional.rawValue,
            currentStop: currentStop,
            players: [
                PlayerSnapshot(id: UUID(), name: "Alice", seat: 0, isYou: false),
                PlayerSnapshot(id: UUID(), name: "Bob", seat: 1, isYou: true)
            ],
            scores: scores,
            recentCaptures: captures,
            endedAt: ended ? .now : nil,
            winnerPlayerID: nil,
            claims: []
        )
    }

    func testUpsertCreatesAndThenUpdates() throws {
        let ctx = container.mainContext
        let gameID = UUID()
        let snap1 = makeSnapshot(gameID: gameID, currentStop: 1)
        let r1 = try JoinedGamePersistence.upsert(in: ctx, snapshot: snap1, myPlayerID: nil)
        XCTAssertEqual(r1.gameID, gameID)
        XCTAssertEqual(r1.hostName, "Bob")
        XCTAssertEqual(r1.snapshot?.currentStop, 1)

        let snap2 = makeSnapshot(gameID: gameID, currentStop: 3, ended: true)
        let r2 = try JoinedGamePersistence.upsert(in: ctx, snapshot: snap2, myPlayerID: nil)
        XCTAssertEqual(r2.gameID, r1.gameID, "same record updated, not duplicated")
        XCTAssertEqual(r2.snapshot?.currentStop, 3)
        XCTAssertNotNil(r2.endedAt)

        let all = try ctx.fetch(FetchDescriptor<JoinedGameRecord>())
        XCTAssertEqual(all.count, 1)
    }

    func testCapturesAccumulateAcrossSnapshots() throws {
        let ctx = container.mainContext
        let gameID = UUID()
        let p1 = UUID(), p2 = UUID()
        let cap1ID = UUID(), cap2ID = UUID(), cap3ID = UUID()
        let entry1 = CaptureManifestEntry(id: cap1ID, playerID: p1, stop: 1)
        let entry2 = CaptureManifestEntry(id: cap2ID, playerID: p2, stop: 1)
        let entry3 = CaptureManifestEntry(id: cap3ID, playerID: p1, stop: 2)

        // Simulate a photo cache as if the joiner fetched photos on demand.
        let photoCache: [UUID: Data] = [
            cap1ID: Data([0x01]),
            cap2ID: Data([0x02]),
            cap3ID: Data([0x03])
        ]

        let snapA = makeSnapshot(gameID: gameID, currentStop: 2, captures: [entry1, entry2])
        let r = try JoinedGamePersistence.upsert(in: ctx, snapshot: snapA, myPlayerID: nil, photoCache: photoCache)
        XCTAssertEqual(r.captures.count, 2)

        // Same captures again — should be deduped, not re-added.
        let snapB = makeSnapshot(gameID: gameID, currentStop: 2, captures: [entry1, entry2])
        _ = try JoinedGamePersistence.upsert(in: ctx, snapshot: snapB, myPlayerID: nil, photoCache: photoCache)
        XCTAssertEqual(r.captures.count, 2)

        // New capture in a later stop's gallery — accumulates.
        let snapC = makeSnapshot(gameID: gameID, currentStop: 3, captures: [entry3])
        _ = try JoinedGamePersistence.upsert(in: ctx, snapshot: snapC, myPlayerID: nil, photoCache: photoCache)
        XCTAssertEqual(r.captures.count, 3)
    }

    func testReportFromSnapshotIncludesStandings() throws {
        let p1 = UUID(), p2 = UUID()
        let snap = GameSnapshot(
            seq: 1, roomCode: "4719", hostName: "Bob", gameID: UUID(),
            gameName: "Friday", length: 2,
            startingEngineRaw: StartingEngine.traditional.rawValue,
            currentStop: 3,
            players: [
                PlayerSnapshot(id: p1, name: "Alice", seat: 0, isYou: false),
                PlayerSnapshot(id: p2, name: "Bob", seat: 1, isYou: true)
            ],
            scores: [
                ScoreSnapshot(playerID: p1, stop: 1, pips: 10),
                ScoreSnapshot(playerID: p2, stop: 1, pips: 4)
            ],
            recentCaptures: [], endedAt: .now, winnerPlayerID: p2, claims: []
        )
        let text = GameReport.text(snapshot: snap)
        XCTAssertTrue(text.contains("MEXICAN TRAIN"))
        XCTAssertTrue(text.contains("Friday"))
        XCTAssertTrue(text.contains("FINAL STANDINGS"))
        XCTAssertTrue(text.contains("Alice"))
        XCTAssertTrue(text.contains("Bob"))
        XCTAssertTrue(text.contains("STOP 1"))
    }
}
