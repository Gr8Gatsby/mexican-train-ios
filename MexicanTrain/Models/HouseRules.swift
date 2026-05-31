import Foundation

enum StartingEngine: String, CaseIterable, Codable, Identifiable {
    case traditional
    case alwaysTwelve
    case drawToFind

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .traditional: "Traditional"
        case .alwaysTwelve: "Always start at double-12"
        case .drawToFind: "Draw to find"
        }
    }

    var description: String {
        switch self {
        case .traditional:
            "Start double matches game length (6 / 9 / 12)."
        case .alwaysTwelve:
            "Always begin at double-12, regardless of length."
        case .drawToFind:
            "Players draw until someone finds the starting double."
        }
    }

    var isDrawToFind: Bool { self == .drawToFind }
}

enum ScoreSource: String, Codable {
    case scanned
    case manual
}

enum Confidence: String, Codable {
    case high, medium, low
}

/// Negative score applied to a player when they go out (empty their hand).
/// Stored on Game as a raw Int so SwiftData migrations stay trivial.
enum GoingOutBonus: Int, CaseIterable, Codable, Identifiable {
    case none = 0
    case minusFive = -5
    case minusTen = -10

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .none:      "None"
        case .minusFive: "−5"
        case .minusTen:  "−10"
        }
    }

    var summary: String {
        switch self {
        case .none:      "No bonus for going out"
        case .minusFive: "Going out subtracts 5 from your total"
        case .minusTen:  "Going out subtracts 10 from your total"
        }
    }
}

/// Auto-scaled draw counts in `Scoring`/`ScoreboardView` use these tiers.
/// Surfaced here so the picker can offer the same choices as overrides.
enum DrawCount {
    static let presetOptions: [Int] = [7, 10, 12, 15]

    /// Default draw count for a given active-player count when no override
    /// is set. Mirrors the legacy `ScoreboardView` table.
    static func auto(forActiveCount activeCount: Int) -> Int {
        if activeCount <= 4 { return 15 }
        if activeCount <= 6 { return 12 }
        return 10
    }
}

/// Common "+N if you can't satisfy a double" penalty. Stored as plain Int so
/// custom values are still possible if we later add them.
enum DoublesPenalty {
    static let presetOptions: [Int] = [0, 5, 10]
}
