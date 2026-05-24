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

    init(seq: Int, roomCode: String, hostName: String, gameID: UUID,
         gameName: String, length: Int, startingEngineRaw: String,
         currentStop: Int, players: [PlayerSnapshot], scores: [ScoreSnapshot],
         recentCaptures: [CaptureSnapshot], endedAt: Date? = nil,
         winnerPlayerID: UUID? = nil, claims: [PlayerClaim] = []) {
        self.seq = seq; self.roomCode = roomCode; self.hostName = hostName
        self.gameID = gameID; self.gameName = gameName; self.length = length
        self.startingEngineRaw = startingEngineRaw; self.currentStop = currentStop
        self.players = players; self.scores = scores
        self.recentCaptures = recentCaptures; self.endedAt = endedAt
        self.winnerPlayerID = winnerPlayerID; self.claims = claims
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.seq = try c.decode(Int.self, forKey: .seq)
        self.roomCode = try c.decode(String.self, forKey: .roomCode)
        self.hostName = try c.decode(String.self, forKey: .hostName)
        // Android sends gameID as a String; accept either UUID or String
        if let uuid = try? c.decode(UUID.self, forKey: .gameID) {
            self.gameID = uuid
        } else {
            let str = (try? c.decode(String.self, forKey: .gameID)) ?? ""
            self.gameID = UUID(uuidString: str) ?? UUID()
        }
        self.gameName = (try? c.decode(String.self, forKey: .gameName)) ?? ""
        self.length = try c.decode(Int.self, forKey: .length)
        self.startingEngineRaw = try c.decode(String.self, forKey: .startingEngineRaw)
        self.currentStop = try c.decode(Int.self, forKey: .currentStop)
        self.players = try c.decode([PlayerSnapshot].self, forKey: .players)
        self.scores = (try? c.decode([ScoreSnapshot].self, forKey: .scores)) ?? []
        self.recentCaptures = (try? c.decode([CaptureSnapshot].self, forKey: .recentCaptures)) ?? []
        // Android sends endedAt as Unix millis Long; iOS uses Date
        if let millis = try? c.decode(Int64.self, forKey: .endedAt) {
            self.endedAt = Date(timeIntervalSince1970: Double(millis) / 1000.0)
        } else {
            self.endedAt = try? c.decode(Date.self, forKey: .endedAt)
        }
        if let uuid = try? c.decode(UUID.self, forKey: .winnerPlayerID) {
            self.winnerPlayerID = uuid
        } else if let str = try? c.decode(String.self, forKey: .winnerPlayerID) {
            self.winnerPlayerID = UUID(uuidString: str)
        } else {
            self.winnerPlayerID = nil
        }
        self.claims = (try? c.decode([PlayerClaim].self, forKey: .claims)) ?? []
    }
}

struct PlayerSnapshot: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var seat: Int
    var isYou: Bool

    init(id: UUID, name: String, seat: Int, isYou: Bool = false) {
        self.id = id; self.name = name; self.seat = seat; self.isYou = isYou
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let uuid = try? c.decode(UUID.self, forKey: .id) {
            self.id = uuid
        } else {
            let str = (try? c.decode(String.self, forKey: .id)) ?? ""
            self.id = UUID(uuidString: str) ?? UUID()
        }
        self.name = try c.decode(String.self, forKey: .name)
        self.seat = try c.decode(Int.self, forKey: .seat)
        self.isYou = (try c.decodeIfPresent(Bool.self, forKey: .isYou)) ?? false
    }
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

    private enum CodingKeys: String, CodingKey {
        case snapshot, claim, scoreSubmission
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .snapshot(let v): try container.encode(v, forKey: .snapshot)
        case .claim(let v): try container.encode(v, forKey: .claim)
        case .scoreSubmission(let v): try container.encode(v, forKey: .scoreSubmission)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let v = try container.decodeIfPresent(GameSnapshot.self, forKey: .snapshot) {
            self = .snapshot(v)
        } else if let v = try container.decodeIfPresent(PlayerClaim.self, forKey: .claim) {
            self = .claim(v)
        } else if let v = try container.decodeIfPresent(ScoreSubmission.self, forKey: .scoreSubmission) {
            self = .scoreSubmission(v)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath,
                                      debugDescription: "No recognized MultipeerMessage key found"))
        }
    }
}
