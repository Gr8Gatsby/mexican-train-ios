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
    var scoringOpen: Bool
    var players: [PlayerSnapshot]
    var scores: [ScoreSnapshot]
    var recentCaptures: [CaptureManifestEntry]   // metadata-only; photos fetched on demand
    var endedAt: Date?
    var winnerPlayerID: UUID?
    var claims: [PlayerClaim]
    // House rules — added in v0.9, decoded with safe defaults for back-compat
    // with joiners on older builds (and the Android bridge).
    var goingOutBonusRaw: Int
    var blockedRoundCapEnabled: Bool
    var drawCountOverride: Int?
    var doublesPenaltyPips: Int
    // v0.10: blank-related house rules.
    var doubleBlankPenaltyPips: Int
    var doublesCountDouble: Bool
    var anyBlankPenaltyPips: Int

    var startingEngine: StartingEngine {
        StartingEngine(rawValue: startingEngineRaw) ?? .traditional
    }
    var goingOutBonus: GoingOutBonus {
        GoingOutBonus(rawValue: goingOutBonusRaw) ?? .none
    }
    var isFinished: Bool { endedAt != nil }

    init(seq: Int, roomCode: String, hostName: String, gameID: UUID,
         gameName: String, length: Int, startingEngineRaw: String,
         currentStop: Int, scoringOpen: Bool = false,
         players: [PlayerSnapshot], scores: [ScoreSnapshot],
         recentCaptures: [CaptureManifestEntry], endedAt: Date? = nil,
         winnerPlayerID: UUID? = nil, claims: [PlayerClaim] = [],
         goingOutBonusRaw: Int = 0,
         blockedRoundCapEnabled: Bool = false,
         drawCountOverride: Int? = nil,
         doublesPenaltyPips: Int = 0,
         doubleBlankPenaltyPips: Int = 0,
         doublesCountDouble: Bool = false,
         anyBlankPenaltyPips: Int = 0) {
        self.seq = seq; self.roomCode = roomCode; self.hostName = hostName
        self.gameID = gameID; self.gameName = gameName; self.length = length
        self.startingEngineRaw = startingEngineRaw; self.currentStop = currentStop
        self.scoringOpen = scoringOpen
        self.players = players; self.scores = scores
        self.recentCaptures = recentCaptures; self.endedAt = endedAt
        self.winnerPlayerID = winnerPlayerID; self.claims = claims
        self.goingOutBonusRaw = goingOutBonusRaw
        self.blockedRoundCapEnabled = blockedRoundCapEnabled
        self.drawCountOverride = drawCountOverride
        self.doublesPenaltyPips = doublesPenaltyPips
        self.doubleBlankPenaltyPips = doubleBlankPenaltyPips
        self.doublesCountDouble = doublesCountDouble
        self.anyBlankPenaltyPips = anyBlankPenaltyPips
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
        self.scoringOpen = (try? c.decode(Bool.self, forKey: .scoringOpen)) ?? false
        self.players = try c.decode([PlayerSnapshot].self, forKey: .players)
        self.scores = (try? c.decode([ScoreSnapshot].self, forKey: .scores)) ?? []
        // Prefer manifest entries; fall back to decoding legacy CaptureSnapshot (back-compat).
        if let entries = try? c.decode([CaptureManifestEntry].self, forKey: .recentCaptures) {
            self.recentCaptures = entries
        } else if let legacy = try? c.decode([CaptureSnapshot].self, forKey: .recentCaptures) {
            self.recentCaptures = legacy.map { CaptureManifestEntry(id: $0.id, playerID: $0.playerID, stop: $0.stop) }
        } else {
            self.recentCaptures = []
        }
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
        // House rules — older snapshots omit these; default to "no special rules".
        self.goingOutBonusRaw = (try? c.decodeIfPresent(Int.self, forKey: .goingOutBonusRaw)) ?? 0
        self.blockedRoundCapEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .blockedRoundCapEnabled)) ?? false
        self.drawCountOverride = try? c.decodeIfPresent(Int.self, forKey: .drawCountOverride)
        self.doublesPenaltyPips = (try? c.decodeIfPresent(Int.self, forKey: .doublesPenaltyPips)) ?? 0
        self.doubleBlankPenaltyPips = (try? c.decodeIfPresent(Int.self, forKey: .doubleBlankPenaltyPips)) ?? 0
        self.doublesCountDouble = (try? c.decodeIfPresent(Bool.self, forKey: .doublesCountDouble)) ?? false
        self.anyBlankPenaltyPips = (try? c.decodeIfPresent(Int.self, forKey: .anyBlankPenaltyPips)) ?? 0
    }
}

struct PlayerSnapshot: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var seat: Int
    var isYou: Bool
    var isActive: Bool

    init(id: UUID, name: String, seat: Int, isYou: Bool = false, isActive: Bool = true) {
        self.id = id; self.name = name; self.seat = seat; self.isYou = isYou; self.isActive = isActive
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
        self.isActive = (try c.decodeIfPresent(Bool.self, forKey: .isActive)) ?? true
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

    init(id: UUID, playerID: UUID, stop: Int, thumbJPEG: Data) {
        self.id = id; self.playerID = playerID; self.stop = stop; self.thumbJPEG = thumbJPEG
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let uuid = try? c.decode(UUID.self, forKey: .id) {
            self.id = uuid
        } else {
            let str = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
            self.id = UUID(uuidString: str) ?? UUID()
        }
        if let uuid = try? c.decode(UUID.self, forKey: .playerID) {
            self.playerID = uuid
        } else {
            let str = (try? c.decode(String.self, forKey: .playerID)) ?? UUID().uuidString
            self.playerID = UUID(uuidString: str) ?? UUID()
        }
        self.stop = try c.decode(Int.self, forKey: .stop)
        if let data = try? c.decode(Data.self, forKey: .thumbJPEG), !data.isEmpty {
            self.thumbJPEG = data
        } else if let b64 = try? c.decode(String.self, forKey: .thumbJPEG),
                  let data = Data(base64Encoded: b64, options: .ignoreUnknownCharacters),
                  !data.isEmpty {
            print("[CaptureSnapshot] base64 string fallback used, decoded \(data.count) bytes")
            self.thumbJPEG = data
        } else {
            print("[CaptureSnapshot] thumbJPEG decode failed — empty")
            self.thumbJPEG = Data()
        }
    }
}

/// Lightweight metadata-only entry sent inside snapshots instead of full photo
/// bytes. Joiners use the `id` to request the actual JPEG on demand.
struct CaptureManifestEntry: Codable, Equatable, Identifiable {
    var id: UUID
    var playerID: UUID
    var stop: Int

    init(id: UUID, playerID: UUID, stop: Int) {
        self.id = id; self.playerID = playerID; self.stop = stop
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let uuid = try? c.decode(UUID.self, forKey: .id) {
            self.id = uuid
        } else {
            let str = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
            self.id = UUID(uuidString: str) ?? UUID()
        }
        if let uuid = try? c.decode(UUID.self, forKey: .playerID) {
            self.playerID = uuid
        } else {
            let str = (try? c.decode(String.self, forKey: .playerID)) ?? UUID().uuidString
            self.playerID = UUID(uuidString: str) ?? UUID()
        }
        self.stop = try c.decode(Int.self, forKey: .stop)
    }
}

/// Joiner-supplied identity for one slot. Photo is resized + JPEG-compressed
/// to fit comfortably in the reliable multipeer envelope.
struct PlayerClaim: Codable, Equatable, Identifiable {
    var playerID: UUID
    var displayName: String
    var photoJPEG: Data?

    var id: UUID { playerID }

    init(playerID: UUID, displayName: String, photoJPEG: Data? = nil) {
        self.playerID = playerID; self.displayName = displayName; self.photoJPEG = photoJPEG
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let uuid = try? c.decode(UUID.self, forKey: .playerID) {
            self.playerID = uuid
        } else {
            let str = (try? c.decode(String.self, forKey: .playerID)) ?? UUID().uuidString
            self.playerID = UUID(uuidString: str) ?? UUID()
        }
        self.displayName = try c.decode(String.self, forKey: .displayName)
        if let data = try? c.decode(Data.self, forKey: .photoJPEG), !data.isEmpty {
            self.photoJPEG = data
        } else if let b64 = try? c.decode(String.self, forKey: .photoJPEG),
                  let data = Data(base64Encoded: b64, options: .ignoreUnknownCharacters),
                  !data.isEmpty {
            self.photoJPEG = data
        } else {
            self.photoJPEG = nil
        }
    }
}

enum PlayerPhoto {
    static let maxJPEGBytes = 64 * 1024
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

/// Photo push payload (host → all joiners). The host sends one of these
/// for every capture immediately after creation, and replays all existing
/// photos to newly-connected joiners.
struct PhotoPush: Codable, Equatable {
    var captureID: UUID
    var playerID: UUID
    var stop: Int
    var thumbJPEG: Data
}

/// Avatar push payload (host → all joiners). Sent separately from the
/// snapshot so that player profile photos don't bloat the MPC envelope.
struct AvatarPush: Codable, Equatable {
    var playerID: UUID
    var photoJPEG: Data
}

enum MultipeerMessage: Codable {
    case snapshot(GameSnapshot)
    case claim(PlayerClaim)
    case scoreSubmission(ScoreSubmission)
    case heartbeat(timestamp: TimeInterval)
    case photoPush(PhotoPush)
    case avatarPush(AvatarPush)

    private enum CodingKeys: String, CodingKey {
        case snapshot, claim, scoreSubmission, heartbeat, photoPush, avatarPush
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .snapshot(let v): try container.encode(v, forKey: .snapshot)
        case .claim(let v): try container.encode(v, forKey: .claim)
        case .scoreSubmission(let v): try container.encode(v, forKey: .scoreSubmission)
        case .heartbeat(let ts): try container.encode(ts, forKey: .heartbeat)
        case .photoPush(let v): try container.encode(v, forKey: .photoPush)
        case .avatarPush(let v): try container.encode(v, forKey: .avatarPush)
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
        } else if let v = try container.decodeIfPresent(TimeInterval.self, forKey: .heartbeat) {
            self = .heartbeat(timestamp: v)
        } else if let v = try container.decodeIfPresent(PhotoPush.self, forKey: .photoPush) {
            self = .photoPush(v)
        } else if let v = try container.decodeIfPresent(AvatarPush.self, forKey: .avatarPush) {
            self = .avatarPush(v)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath,
                                      debugDescription: "No recognized MultipeerMessage key found"))
        }
    }
}
