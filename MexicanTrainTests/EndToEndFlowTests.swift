import XCTest
import SwiftData
@testable import MexicanTrain

/// Drives the golden path through the persistence layer (no UI), as a
/// belt-and-suspenders smoke test that the M0-M3 milestones still
/// compose into a finishable game.
@MainActor
final class EndToEndFlowTests: XCTestCase {
    private var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        container = DataStore.makeContainer(inMemory: true)
    }
    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

    func testGoldenPath() throws {
        let ctx = container.mainContext
        let game = try GamePersistence.createGame(
            in: ctx,
            length: 3,
            startingEngine: .traditional,
            playerNames: ["Alex", "Bea"],
            youIndex: 0
        )
        let p = game.sortedPlayers
        XCTAssertEqual(game.currentStopIndex, 1)
        XCTAssertEqual(Scoring.engineTile(stop: 1, rules: .traditional, length: 3), 2)

        for stop in 1...3 {
            try GamePersistence.recordScore(in: ctx, game: game, player: p[0], stop: stop, pips: stop, source: .manual)
            try GamePersistence.recordScore(in: ctx, game: game, player: p[1], stop: stop, pips: stop * 2, source: .manual)
            try GamePersistence.maybeAdvanceStop(in: ctx, game: game)
        }
        XCTAssertTrue(game.isFinished)
        let standings = Scoring.standings(for: game)
        XCTAssertEqual(standings[0].name, "Alex")
        XCTAssertEqual(standings[0].total, 1 + 2 + 3)
        XCTAssertEqual(standings[1].total, 2 + 4 + 6)
    }

    func testAuditChangesTotal() throws {
        let ctx = container.mainContext
        let game = try GamePersistence.createGame(
            in: ctx, length: 2, startingEngine: .traditional,
            playerNames: ["A"], youIndex: 0
        )
        let p = game.sortedPlayers[0]
        try GamePersistence.recordScore(in: ctx, game: game, player: p, stop: 1, pips: 7, source: .manual)
        try GamePersistence.recordScore(in: ctx, game: game, player: p, stop: 1, pips: 15, source: .manual)
        XCTAssertEqual(Scoring.total(for: p.id, in: game), 15)
    }

    func testDeleteCascades() throws {
        let ctx = container.mainContext
        let game = try GamePersistence.createGame(
            in: ctx, length: 1, startingEngine: .traditional,
            playerNames: ["A","B"], youIndex: 0
        )
        let p = game.sortedPlayers
        try GamePersistence.recordScore(in: ctx, game: game, player: p[0], stop: 1, pips: 1, source: .manual)
        try GamePersistence.recordScore(in: ctx, game: game, player: p[1], stop: 1, pips: 2, source: .manual)
        try GamePersistence.delete(game: game, in: ctx)
        let games = try ctx.fetch(FetchDescriptor<Game>())
        let scores = try ctx.fetch(FetchDescriptor<Score>())
        let players = try ctx.fetch(FetchDescriptor<Player>())
        XCTAssertEqual(games.count, 0)
        XCTAssertEqual(scores.count, 0)
        XCTAssertEqual(players.count, 0)
    }
}
