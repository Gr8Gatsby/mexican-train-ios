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

    init() {
        let d = UserDefaults.standard
        let storedLen = d.object(forKey: Keys.length) as? Int
        self.defaultLengthStops = storedLen ?? 13
        self.defaultYouName = d.string(forKey: Keys.you) ?? ""
        let raw = d.string(forKey: Keys.engine) ?? StartingEngine.traditional.rawValue
        self.lastStartingEngine = StartingEngine(rawValue: raw) ?? .traditional
        self.trainingDataExportEnabled = d.bool(forKey: Keys.trainingExport)
    }

    private enum Keys {
        static let length = "settings.defaultLengthStops"
        static let you = "settings.defaultYouName"
        static let engine = "settings.lastStartingEngine"
        static let trainingExport = "settings.trainingDataExportEnabled"
    }
}
