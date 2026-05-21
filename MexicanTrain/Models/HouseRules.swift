import Foundation

enum StartingEngine: String, CaseIterable, Codable, Identifiable {
    case traditional
    case alwaysTwelve

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .traditional: "Traditional"
        case .alwaysTwelve: "Always start at double-12"
        }
    }

    var description: String {
        switch self {
        case .traditional:
            "Start double matches game length (6 / 9 / 12)."
        case .alwaysTwelve:
            "Always begin at double-12, regardless of length."
        }
    }
}

enum ScoreSource: String, Codable {
    case scanned
    case manual
}

enum Confidence: String, Codable {
    case high, medium, low
}
