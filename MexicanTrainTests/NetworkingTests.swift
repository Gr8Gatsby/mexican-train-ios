import XCTest
@testable import MexicanTrain

final class NetworkingTests: XCTestCase {
    func testRoomCodeIsFourDigits() {
        for _ in 0..<50 {
            let c = RoomCode.generate()
            XCTAssertEqual(c.count, 4)
            XCTAssertTrue(RoomCode.isValid(c))
            XCTAssertFalse(RoomCode.isAmbiguous(c))
        }
    }

    func testAmbiguousCodes() {
        XCTAssertTrue(RoomCode.isAmbiguous("1111"))
        XCTAssertTrue(RoomCode.isAmbiguous("1234"))
        XCTAssertTrue(RoomCode.isAmbiguous("4321"))
        XCTAssertTrue(RoomCode.isAmbiguous("2345"))
        XCTAssertFalse(RoomCode.isAmbiguous("4719"))
    }

    func testJoinURLRoundTrip() {
        let url = JoinURL.encode(roomCode: "4719")
        XCTAssertEqual(url.scheme, "mextrain")
        XCTAssertEqual(JoinURL.decode(url), "4719")
    }

    func testJoinURLRejectsInvalid() {
        XCTAssertNil(JoinURL.decode(URL(string: "http://example.com/join?code=4719")!))
        XCTAssertNil(JoinURL.decode(URL(string: "mextrain://join?code=abcd")!))
        XCTAssertNil(JoinURL.decode(URL(string: "mextrain://join?code=12")!))
    }

    func testGameSnapshotCodableRoundTrip() throws {
        let snap = GameSnapshot(
            seq: 5,
            roomCode: "4719",
            hostName: "Kevin",
            gameID: UUID(),
            gameName: "Friday Night",
            length: 13,
            startingEngineRaw: StartingEngine.traditional.rawValue,
            currentStop: 3,
            players: [
                PlayerSnapshot(id: UUID(), name: "Aaron", seat: 0, isYou: false),
                PlayerSnapshot(id: UUID(), name: "Kevin", seat: 1, isYou: true)
            ],
            scores: [],
            recentCaptures: [],
            endedAt: nil,
            winnerPlayerID: nil,
            claims: []
        )
        let data = try JSONEncoder().encode(MultipeerMessage.snapshot(snap))
        let decoded = try JSONDecoder().decode(MultipeerMessage.self, from: data)
        if case .snapshot(let out) = decoded {
            XCTAssertEqual(out.roomCode, "4719")
            XCTAssertEqual(out.players.count, 2)
        } else {
            XCTFail("Expected .snapshot")
        }
    }

    func testPlayerClaimRoundTrip() throws {
        let id = UUID()
        let claim = PlayerClaim(playerID: id, displayName: "Friendly", photoJPEG: Data([0xFF, 0xD8]))
        let data = try JSONEncoder().encode(MultipeerMessage.claim(claim))
        let decoded = try JSONDecoder().decode(MultipeerMessage.self, from: data)
        if case .claim(let out) = decoded {
            XCTAssertEqual(out.playerID, id)
            XCTAssertEqual(out.displayName, "Friendly")
        } else {
            XCTFail("Expected .claim")
        }
    }

    func testScoreSubmissionRoundTrip() throws {
        let pid = UUID()
        let submission = ScoreSubmission(
            playerID: pid, stopIndex: 4, pips: 27,
            source: .scanned,
            tiles: [
                TileObservation(a: 5, b: 0),
                TileObservation(a: 9, b: 0)
            ],
            thumbJPEG: Data([0xFF, 0xD8, 0xFF, 0xE0])
        )
        let data = try JSONEncoder().encode(MultipeerMessage.scoreSubmission(submission))
        let decoded = try JSONDecoder().decode(MultipeerMessage.self, from: data)
        guard case .scoreSubmission(let out) = decoded else {
            return XCTFail("Expected .scoreSubmission")
        }
        XCTAssertEqual(out.playerID, pid)
        XCTAssertEqual(out.stopIndex, 4)
        XCTAssertEqual(out.pips, 27)
        XCTAssertEqual(out.source, .scanned)
        XCTAssertEqual(out.tiles.count, 2)
        XCTAssertEqual(out.thumbJPEG?.count, 4)
    }

    func testScoreSnapshotDefaultsForBackCompat() throws {
        // Older clients omit `submittedByRaw` / `excluded`; decode must
        // still succeed and yield sensible defaults.
        let json = """
        {"playerID":"\(UUID().uuidString)","stop":1,"pips":5}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ScoreSnapshot.self, from: json)
        XCTAssertEqual(decoded.pips, 5)
        XCTAssertEqual(decoded.submittedBy, .conductor)
        XCTAssertFalse(decoded.excluded)
    }
}
