import XCTest
import SwiftData
@testable import MexicanTrain

@MainActor
final class GameReportTests: XCTestCase {
    private var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()
        container = DataStore.makeContainer(inMemory: true)
    }

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

    func testReportIncludesHeaderAndStandings() throws {
        let game = try GamePersistence.createGame(
            in: container.mainContext, length: 2, startingEngine: .traditional,
            playerNames: ["Alice", "Bob"], youIndex: 0, name: "Saturday"
        )
        let ctx = container.mainContext
        let p = game.sortedPlayers
        try GamePersistence.recordScore(in: ctx, game: game, player: p[0], stop: 1, pips: 12, source: .manual)
        try GamePersistence.recordScore(in: ctx, game: game, player: p[1], stop: 1, pips: 8, source: .manual)

        let text = GameReport.text(for: game)
        XCTAssertTrue(text.contains("MEXICAN TRAIN"), "header present")
        XCTAssertTrue(text.contains("Saturday"), "game title present")
        XCTAssertTrue(text.contains("FINAL STANDINGS"), "standings section present")
        XCTAssertTrue(text.contains("Alice"))
        XCTAssertTrue(text.contains("Bob"))
        XCTAssertTrue(text.contains("STOP 1"), "per-stop breakdown present")
    }

    func testReportAnnotatesAuditedAndExcluded() throws {
        let game = try GamePersistence.createGame(
            in: container.mainContext, length: 2, startingEngine: .traditional,
            playerNames: ["Alice"], youIndex: nil
        )
        let ctx = container.mainContext
        let p = game.sortedPlayers[0]
        // Original conductor-submitted, then player overrode via wire, then conductor audited
        try GamePersistence.recordScore(in: ctx, game: game, player: p, stop: 1, pips: 8, source: .manual,
                                        submittedBy: .conductor)
        _ = try GamePersistence.handleScoreSubmission(
            in: ctx, game: game,
            submission: ScoreSubmission(playerID: p.id, stopIndex: 1, pips: 15)
        )
        if let s = game.scores.first {
            try GamePersistence.setScoreExcluded(in: ctx, score: s, excluded: true)
        }

        let text = GameReport.text(for: game)
        XCTAssertTrue(text.contains("submitted 8 by conductor"))
        XCTAssertTrue(text.contains("audited to 15 by Alice"))
        XCTAssertTrue(text.contains("excluded"))
    }
}
