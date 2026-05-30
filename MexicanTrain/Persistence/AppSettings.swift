import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    var defaultLengthStops: Int {
        didSet { UserDefaults.standard.set(defaultLengthStops, forKey: Keys.length) }
    }
    var defaultYouName: String {
        didSet { UserDefaults.standard.set(defaultYouName, forKey: Keys.you) }
    }
    /// User's saved profile photo, compressed JPEG (≤ ~32 KB). Stored as
    /// raw Data in UserDefaults so the lifecycle is trivially atomic and
    /// piggybacks on the existing settings sync. nil ⇒ no photo set.
    var defaultYouPhotoJPEG: Data? {
        didSet { UserDefaults.standard.set(defaultYouPhotoJPEG, forKey: Keys.youPhoto) }
    }
    var lastStartingEngine: StartingEngine {
        didSet { UserDefaults.standard.set(lastStartingEngine.rawValue, forKey: Keys.engine) }
    }
    /// Opt-in toggle that surfaces (a) the per-half editor on the audit
    /// screen so the conductor can correct the model's detections and
    /// (b) the "EXPORT LABELED PHOTOS" action in Settings. Off by
    /// default; explicit user choice required since corrected photos
    /// are training data destined to leave the device on share.
    var trainingDataExportEnabled: Bool {
        didSet { UserDefaults.standard.set(trainingDataExportEnabled, forKey: Keys.trainingExport) }
    }
    /// Tracks whether the conductor has used the cell-level "+" override
    /// at least once. While false, the scoreboard renders a one-time
    /// pulse on those affordances to make their interactivity obvious;
    /// flips true the moment they're tapped.
    var hasUsedConductorOverride: Bool {
        didSet { UserDefaults.standard.set(hasUsedConductorOverride, forKey: Keys.usedOverride) }
    }

    // MARK: - Active Join (rejoin after crash/leave)

    var activeJoinRoomCode: String? {
        didSet { UserDefaults.standard.set(activeJoinRoomCode, forKey: Keys.joinRoomCode) }
    }
    var activeJoinPlayerID: UUID? {
        didSet {
            UserDefaults.standard.set(activeJoinPlayerID?.uuidString, forKey: Keys.joinPlayerID)
        }
    }
    var activeJoinPlayerName: String? {
        didSet { UserDefaults.standard.set(activeJoinPlayerName, forKey: Keys.joinPlayerName) }
    }
    var activeJoinHostIP: String? {
        didSet { UserDefaults.standard.set(activeJoinHostIP, forKey: Keys.joinHostIP) }
    }
    var activeJoinHostPort: Int {
        didSet { UserDefaults.standard.set(activeJoinHostPort, forKey: Keys.joinHostPort) }
    }
    var activeJoinGameID: UUID? {
        didSet { UserDefaults.standard.set(activeJoinGameID?.uuidString, forKey: Keys.joinGameID) }
    }

    func clearActiveJoin() {
        activeJoinRoomCode = nil
        activeJoinPlayerID = nil
        activeJoinPlayerName = nil
        activeJoinHostIP = nil
        activeJoinHostPort = 5111
        activeJoinGameID = nil
    }

    init() {
        let d = UserDefaults.standard
        let storedLen = d.object(forKey: Keys.length) as? Int
        self.defaultLengthStops = storedLen ?? 13
        self.defaultYouName = d.string(forKey: Keys.you) ?? ""
        self.defaultYouPhotoJPEG = d.data(forKey: Keys.youPhoto)
        let raw = d.string(forKey: Keys.engine) ?? StartingEngine.traditional.rawValue
        self.lastStartingEngine = StartingEngine(rawValue: raw) ?? .traditional
        self.trainingDataExportEnabled = d.bool(forKey: Keys.trainingExport)
        self.hasUsedConductorOverride = d.bool(forKey: Keys.usedOverride)
        self.activeJoinRoomCode = d.string(forKey: Keys.joinRoomCode)
        if let idStr = d.string(forKey: Keys.joinPlayerID) {
            self.activeJoinPlayerID = UUID(uuidString: idStr)
        } else {
            self.activeJoinPlayerID = nil
        }
        self.activeJoinPlayerName = d.string(forKey: Keys.joinPlayerName)
        self.activeJoinHostIP = d.string(forKey: Keys.joinHostIP)
        self.activeJoinHostPort = d.object(forKey: Keys.joinHostPort) as? Int ?? 5111
        if let gidStr = d.string(forKey: Keys.joinGameID) {
            self.activeJoinGameID = UUID(uuidString: gidStr)
        } else {
            self.activeJoinGameID = nil
        }
    }

    private enum Keys {
        static let length = "settings.defaultLengthStops"
        static let you = "settings.defaultYouName"
        static let youPhoto = "settings.defaultYouPhotoJPEG"
        static let engine = "settings.lastStartingEngine"
        static let trainingExport = "settings.trainingDataExportEnabled"
        static let usedOverride = "settings.hasUsedConductorOverride"
        static let joinRoomCode = "settings.activeJoinRoomCode"
        static let joinPlayerID = "settings.activeJoinPlayerID"
        static let joinPlayerName = "settings.activeJoinPlayerName"
        static let joinHostIP = "settings.activeJoinHostIP"
        static let joinHostPort = "settings.activeJoinHostPort"
        static let joinGameID = "settings.activeJoinGameID"
    }
}
