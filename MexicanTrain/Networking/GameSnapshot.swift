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

enum MultipeerMessage: Codable {
    case snapshot(GameSnapshot)
    case claim(PlayerClaim)
}
