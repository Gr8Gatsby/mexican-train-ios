import Foundation

/// Full-state wire model. Re-sent on every meaningful host-side change.
/// Small enough that diffing is not worth the complexity.
struct GameSnapshot: Codable, Equatable {
    var seq: Int                            // monotonic per host session
    var roomCode: String
    var hostName: String
    var gameID: UUID
    var gameName: String
    var length: Int                         // total stops
    var startingEngineRaw: String
    var currentStop: Int
    var players: [PlayerSnapshot]
    var scores: [ScoreSnapshot]
    var recentCaptures: [CaptureSnapshot]   // previous stop's gallery (most recent N)
    var endedAt: Date?
    var winnerPlayerID: UUID?
    var claims: [PlayerClaim]

    var startingEngine: StartingEngine {
        StartingEngine(rawValue: startingEngineRaw) ?? .traditional
    }
    var isFinished: Bool { endedAt != nil }
}

struct PlayerSnapshot: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var seat: Int
    var isYou: Bool                         // host's view of "you"; joiners apply their own claim
}

struct ScoreSnapshot: Codable, Equatable {
    var playerID: UUID
    var stop: Int
    var pips: Int
    /// `"player"` or `"conductor"` — who originally submitted this score.
    /// Decodes to `"conductor"` for older snapshots that omit the field.
    var submittedByRaw: String
    /// Excluded scores still appear on the board but contribute 0 to the
    /// running total. Defaults to false for back-compat.
    var excluded: Bool

    init(playerID: UUID, stop: Int, pips: Int,
         submittedByRaw: String = ScoreActor.conductor.rawValue,
         excluded: Bool = false) {
        self.playerID = playerID
        self.stop = stop
        self.pips = pips
        self.submittedByRaw = submittedByRaw
        self.excluded = excluded
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.playerID = try c.decode(UUID.self, forKey: .playerID)
        self.stop = try c.decode(Int.self, forKey: .stop)
        self.pips = try c.decode(Int.self, forKey: .pips)
        self.submittedByRaw = (try c.decodeIfPresent(String.self, forKey: .submittedByRaw))
            ?? ScoreActor.conductor.rawValue
        self.excluded = (try c.decodeIfPresent(Bool.self, forKey: .excluded)) ?? false
    }

    var submittedBy: ScoreActor {
        ScoreActor(rawValue: submittedByRaw) ?? .conductor
    }
}

struct CaptureSnapshot: Codable, Equatable, Identifiable {
    var id: UUID
    var playerID: UUID
    var stop: Int
    var thumbJPEG: Data
}

/// Joiner-supplied identity for one slot. Photo is resized + JPEG-compressed
/// to fit comfortably in the reliable multipeer envelope.
struct PlayerClaim: Codable, Equatable, Identifiable {
    var playerID: UUID
    var displayName: String
    var photoJPEG: Data?

    var id: UUID { playerID }
}

enum PlayerPhoto {
    static let maxJPEGBytes = 32 * 1024
    static let targetEdge: CGFloat = 256
}

/// Player joiner → host: submit a pip count for the joiner's own slot at the
/// current stop. The optional thumbnail lets the conductor audit against the
/// same photo the joiner saw. Tiles are forwarded so the audit view can show
/// the detection grid, mirroring host-side captures.
struct ScoreSubmission: Codable, Equatable {
    var playerID: UUID
    var stopIndex: Int
    var pips: Int
    var source: ScoreSource
    var tiles: [TileObservation]
    var thumbJPEG: Data?

    init(playerID: UUID, stopIndex: Int, pips: Int,
         source: ScoreSource = .scanned,
         tiles: [TileObservation] = [],
         thumbJPEG: Data? = nil) {
        self.playerID = playerID
        self.stopIndex = stopIndex
        self.pips = pips
        self.source = source
        self.tiles = tiles
        self.thumbJPEG = thumbJPEG
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.playerID = try c.decode(UUID.self, forKey: .playerID)
        self.stopIndex = try c.decode(Int.self, forKey: .stopIndex)
        self.pips = try c.decode(Int.self, forKey: .pips)
        self.source = (try c.decodeIfPresent(ScoreSource.self, forKey: .source)) ?? .scanned
        self.tiles = (try c.decodeIfPresent([TileObservation].self, forKey: .tiles)) ?? []
        self.thumbJPEG = try c.decodeIfPresent(Data.self, forKey: .thumbJPEG)
    }
}

enum MultipeerMessage: Codable {
    case snapshot(GameSnapshot)
    case claim(PlayerClaim)
    case scoreSubmission(ScoreSubmission)
}
