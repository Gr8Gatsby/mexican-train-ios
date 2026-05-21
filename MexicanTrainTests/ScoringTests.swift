import XCTest
import SwiftData
@testable import MexicanTrain

@MainActor
final class ScoringTests: XCTestCase {
    private var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        container = DataStore.makeContainer(inMemory: true)
    }

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

    private func makeGame(
        length: Int = 13,
        engine: StartingEngine = .traditional,
        players: [String] = ["Aaron", "Kevin", "Comp"],
        you: Int? = 1
    ) throws -> Game {
        try GamePersistence.createGame(
            in: container.mainContext, length: length, startingEngine: engine,
            playerNames: players, youIndex: you
        )
    }

    func testEmptyTotalIsZero() throws {
        let game = try makeGame()
        let standings = Scoring.standings(for: game)
        XCTAssertEqual(standings.count, 3)
        XCTAssertTrue(standings.allSatisfy { $0.total == 0 })
    }

    func testSparseScoringTotals() throws {
        let game = try makeGame()
        let ctx = container.mainContext
        let players = game.sortedPlayers
        try GamePersistence.recordScore(in: ctx, game: game, player: players[0], stop: 1, pips: 12, source: .manual)
        try GamePersistence.recordScore(in: ctx, game: game, player: players[1], stop: 1, pips: 5, source: .manual)
        try GamePersistence.recordScore(in: ctx, game: game, player: players[0], stop: 2, pips: 8, source: .manual)
        XCTAssertEqual(Scoring.total(for: players[0].id, in: game), 20)
        XCTAssertEqual(Scoring.total(for: players[1].id, in: game), 5)
        XCTAssertEqual(Scoring.total(for: players[2].id, in: game), 0)
    }

    func testStandingsAscendingWithTie() throws {
        let game = try makeGame()
        let ctx = container.mainContext
        let p = game.sortedPlayers
        try GamePersistence.recordScore(in: ctx, game: game, player: p[0], stop: 1, pips: 10, source: .manual)
        try GamePersistence.recordScore(in: ctx, game: game, player: p[1], stop: 1, pips: 10, source: .manual)
        let s = Scoring.standings(for: game)
        XCTAssertEqual(s[0].name, "Comp")
        XCTAssertEqual(s[0].place, 1)
        XCTAssertEqual(s[1].place, 2)
        XCTAssertEqual(s[2].place, 2)
    }

    func testStopAdvanceOnComplete() throws {
        let game = try makeGame(length: 7)
        let ctx = container.mainContext
        let p = game.sortedPlayers
        XCTAssertEqual(game.currentStopIndex, 1)
        try GamePersistence.recordScore(in: ctx, game: game, player: p[0], stop: 1, pips: 5, source: .manual)
        try GamePersistence.recordScore(in: ctx, game: game, player: p[1], stop: 1, pips: 5, source: .manual)
        try GamePersistence.recordScore(in: ctx, game: game, player: p[2], stop: 1, pips: 5, source: .manual)
        try GamePersistence.maybeAdvanceStop(in: ctx, game: game)
        XCTAssertEqual(game.currentStopIndex, 2)
        XCTAssertFalse(game.isFinished)
    }

    func testGameFinishesAfterFinalStop() throws {
        let game = try makeGame(length: 1, players: ["A","B"])
        let ctx = container.mainContext
        let p = game.sortedPlayers
        try GamePersistence.recordScore(in: ctx, game: game, player: p[0], stop: 1, pips: 1, source: .manual)
        try GamePersistence.recordScore(in: ctx, game: game, player: p[1], stop: 1, pips: 2, source: .manual)
        try GamePersistence.maybeAdvanceStop(in: ctx, game: game)
        XCTAssertTrue(game.isFinished)
    }

    func testEngineTraditional() {
        XCTAssertEqual(Scoring.engineTile(stop: 1, rules: .traditional, length: 13), 12)
        XCTAssertEqual(Scoring.engineTile(stop: 1, rules: .traditional, length: 10), 9)
        XCTAssertEqual(Scoring.engineTile(stop: 1, rules: .traditional, length: 7), 6)
        XCTAssertEqual(Scoring.engineTile(stop: 7, rules: .traditional, length: 7), 0)
        XCTAssertEqual(Scoring.engineTile(stop: 13, rules: .traditional, length: 13), 0)
    }

    func testEngineAlwaysTwelve() {
        XCTAssertEqual(Scoring.engineTile(stop: 1, rules: .alwaysTwelve, length: 7), 12)
        XCTAssertEqual(Scoring.engineTile(stop: 7, rules: .alwaysTwelve, length: 7), 6)
        XCTAssertEqual(Scoring.engineTile(stop: 13, rules: .alwaysTwelve, length: 13), 0)
    }

    func testAuditOverwritesExisting() throws {
        let game = try makeGame()
        let ctx = container.mainContext
        let p = game.sortedPlayers[0]
        try GamePersistence.recordScore(in: ctx, game: game, player: p, stop: 1, pips: 5, source: .manual)
        try GamePersistence.recordScore(in: ctx, game: game, player: p, stop: 1, pips: 11, source: .manual)
        XCTAssertEqual(game.scores.filter { $0.playerID == p.id && $0.stopIndex == 1 }.count, 1)
        XCTAssertEqual(Scoring.total(for: p.id, in: game), 11)
    }
}
